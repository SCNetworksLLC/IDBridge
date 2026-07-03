<#
.SYNOPSIS
Acquire an Entra ID (Azure AD) OAuth token using a certificate credential (internal).

.DESCRIPTION
Internal helper for the AzKeyVault secrets provider. Implements the OAuth 2.0 client
credentials flow with a certificate: builds a signed JWT client assertion (RS256, base64url,
x5t = certificate hash) and exchanges it at the tenant's v2.0 token endpoint — no external
module. The app registration must have the certificate's public key uploaded as a credential.

The signing certificate is looked up by thumbprint in the CurrentUser and LocalMachine My
stores; the running account needs read access to its private key.

.PARAMETER ClientId
The app registration (client) ID.

.PARAMETER TenantId
The Entra tenant ID or domain (e.g. 'contoso.onmicrosoft.com').

.PARAMETER CertThumbprint
Thumbprint of the certificate uploaded to the app registration.

.PARAMETER Scope
The requested scope (e.g. 'https://vault.azure.net/.default').

.EXAMPLE
$token = Get-IDBridgeAzureAuthToken -ClientId $id -TenantId $tenant -CertThumbprint $thumb -Scope 'https://vault.azure.net/.default'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-02
#>
function Get-IDBridgeAzureAuthToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$CertThumbprint,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    # Find the auth certificate in the user or machine store (the private key signs the assertion)
    $clientCertificate = Get-Item "Cert:\*\My\$CertThumbprint" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $clientCertificate) {
        Throw "The Azure auth certificate '$CertThumbprint' (Secrets.AzKeyVault.CertThumbprint) was not found in the CurrentUser or LocalMachine My store."
    }

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # JWT parts are base64url encoded (base64 with -/_ and no padding)
    $x5t = [System.Convert]::ToBase64String($clientCertificate.GetCertHash()) -replace '\+', '-' -replace '/', '_' -replace '='

    $jwtHeader = @{
        alg = "RS256"
        typ = "JWT"
        x5t = $x5t
    }

    $now = [DateTimeOffset]::UtcNow
    $jwtPayload = @{
        aud = $tokenUrl
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.ToUnixTimeSeconds()
        exp = $now.AddMinutes(10).ToUnixTimeSeconds()
    }

    $encodedHeader = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($jwtHeader | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '='
    $encodedPayload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($jwtPayload | ConvertTo-Json -Compress))) -replace '\+', '-' -replace '/', '_' -replace '='
    $jwt = "$encodedHeader.$encodedPayload"

    # Sign the assertion with the certificate's private key (SHA-256 / PKCS1)
    $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($clientCertificate)
    if (-not $privateKey) {
        Throw "The Azure auth certificate '$CertThumbprint' has no readable private key for the current account."
    }
    $signature = [System.Convert]::ToBase64String(
        $privateKey.SignData([System.Text.Encoding]::UTF8.GetBytes($jwt), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    ) -replace '\+', '-' -replace '/', '_' -replace '='
    $jwt = "$jwt.$signature"

    $body = @{
        client_id             = $ClientId
        client_assertion      = $jwt
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        scope                 = $Scope
        grant_type            = "client_credentials"
    }

    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    }
    catch {
        Throw "Failed to acquire an Azure token for client '$ClientId' in tenant '$TenantId': $($_)"
    }

    Write-Log -Message "Secret: Acquired Azure token for client '$ClientId' (scope $Scope)." -Level Trace

    return $tokenResponse
}
