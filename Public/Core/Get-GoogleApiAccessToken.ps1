function Get-GoogleApiAccessToken {
    <#
    .SYNOPSIS
    Retrieves an access token from Google API using a service account.

    .DESCRIPTION
    This function generates a JWT (JSON Web Token) and exchanges it for an access token from Google API.
    The access token can then be used for authenticated requests to Google services.

    .PARAMETER ServiceAccountKeyPath
    PAth to a JSON file containing the service account credentials, including the private key and client email.
    This is the Google credential file downloaded from the Google Cloud Console.

    .PARAMETER Scope
    The scope of access requested from Google API (e.g., 'https://www.googleapis.com/auth/drive').

    .PARAMETER TargetUserEmail
    The email address of the user for which the application is requesting delegated access.

    .EXAMPLE
    $credentialsJson = Get-Content 'C:\path\to\credentials.json' -Raw
    $accessToken = Get-GoogleApiAccessToken -ServiceAccountKeyPath $credentialsJson -Scope 'https://www.googleapis.com/auth/drive.readonly'
    
    Use the $accessToken for authenticated API requests.

    .NOTES
    Ensure that the service account has the necessary permissions for the requested scope.

    Created by: Sam Cattanach
    Modified: 02/18/2025 09:30:19 AM   
    #>

    param (
        [Parameter(Mandatory)]
        [string]$ServiceAccountKeyPath,

        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$TargetUserEmail
    )

    # Convert JSON credentials into a PowerShell object
    $jsonContent = ConvertFrom-Json -InputObject (Get-Content $ServiceAccountKeyPath -Raw)
    $ServiceAccountEmail = $jsonContent.client_email
    $PrivateKey = $jsonContent.private_key -replace '-----BEGIN PRIVATE KEY-----\n' -replace '\n-----END PRIVATE KEY-----\n' -replace '\n'

    # Create JWT Header (Base64-encoded JSON)
    $header = @{
        alg = "RS256"
        typ = "JWT"
    }
    $headerBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))

    # Generate JWT Payload (Claim Set)
    $timestamp = [Math]::Round((Get-Date -UFormat %s))  # Current time in seconds
    $claimSet = @{
        iss   = $ServiceAccountEmail
        scope = $Scope
        aud   = "https://oauth2.googleapis.com/token"
        exp   = $timestamp + 3600  # Token expiration (1 hour)
        iat   = $timestamp         # Issued at time
        sub   = $TargetUserEmail   # Delegated user access
    }
    $claimSetBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($claimSet | ConvertTo-Json -Compress)))

    # Generate JWT Signature
    $signatureInput = "$headerBase64.$claimSetBase64"
    $signatureBytes = [System.Text.Encoding]::UTF8.GetBytes($signatureInput)
    $privateKeyBytes = [System.Convert]::FromBase64String($PrivateKey)

    # Create RSA provider and import the private key
    $rsaProvider = [System.Security.Cryptography.RSA]::Create()
    $bytesRead = $null
    $rsaProvider.ImportPkcs8PrivateKey($privateKeyBytes, [ref]$bytesRead)

    # Sign the JWT using SHA-256 and PKCS1 padding
    $signature = $rsaProvider.SignData($signatureBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $signatureBase64 = [System.Convert]::ToBase64String($signature)

    # Construct the final JWT
    $jwt = "$headerBase64.$claimSetBase64.$signatureBase64"

    # Create request body for token exchange
    $body = @{
        grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        assertion  = $jwt
    }

    # Request access token from Google OAuth2 API
    try {
        $response = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"

        $accessToken = $response.access_token

        $headers = @{
            'Authorization' = "Bearer $accessToken"
            'Accept' = 'application/json'
        }
        
        Write-Log -Path $logFile -Message "Successfully retrieved Google Access Token"

        return $headers
    } catch {
        Write-Log -Path $logFile -Message "Failed to Retrieve Google Access Token" -Level Error
        Throw $_
    }
}