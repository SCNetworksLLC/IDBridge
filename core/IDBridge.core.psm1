<# 
.Synopsis 
   Write-Log writes a message to a specified log file with the current time stamp. 
.DESCRIPTION 
   The Write-Log function is designed to add logging capability to other scripts. 
   In addition to writing output and/or verbose you can write to a log file for 
   later debugging. 
.NOTES 
   Created by: Jason Wasser @wasserja 
   Modified: 11/24/2015 09:30:19 AM   
 
   Changelog: 
    * Code simplification and clarification - thanks to @juneb_get_help 
    * Added documentation. 
    * Renamed LogPath parameter to Path to keep it standard - thanks to @JeffHicks 
    * Revised the Force switch to work as it should - thanks to @JeffHicks 
 
   To Do: 
    * Add error handling if trying to create a log file in a inaccessible location. 
    * Add ability to write $Message to $Verbose or $Error pipelines to eliminate 
      duplicates. 
.PARAMETER Message 
   Message is the content that you wish to add to the log file.  
.PARAMETER Path 
   The path to the log file to which you would like to write. By default the function will  
   create the path and file if it does not exist.  
.PARAMETER Level 
   Specify the criticality of the log information being written to the log (i.e. Error, Warning, Informational) 
.PARAMETER NoClobber 
   Use NoClobber if you do not wish to overwrite an existing file. 
.EXAMPLE 
   Write-Log -Message 'Log message'  
   Writes the message to c:\Logs\PowerShellLog.log. 
.EXAMPLE 
   Write-Log -Message 'Restarting Server.' -Path c:\Logs\Scriptoutput.log 
   Writes the content to the specified log file and creates the path and file specified.  
.EXAMPLE 
   Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error 
   Writes the message to the specified log file as an error message, and writes the message to the error pipeline. 
.LINK 
   https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0 
#> 
function Write-Log { 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('LogPath')] 
        [string]$Path='C:\Logs\PowerShellLog.log', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber , 
         
        [Parameter(Mandatory=$false)] 
        [bool]$WhatIfLogging
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $Path) -AND $NoClobber) { 
            Write-Error "Log file $Path already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $Path)) { 
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File | Out-Null
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                if ($WhatIfLogging -eq $true) {
                    Write-Error "WhatIf: $Message"
                    $LevelText = 'ERROR:' 
                } else {
                    Write-Error $Message 
                    $LevelText = 'ERROR:' 
                }
            } 
            'Warn' { 
                if ($WhatIfLogging -eq $true) {
                    Write-Warning "WhatIf: $Message"
                    $LevelText = 'WARNING:' 
                } else {
                    Write-Warning $Message 
                    $LevelText = 'WARNING:' 
                }

            } 
            'Info' { 
                if ($WhatIfLogging -eq $true) {
                    Write-Verbose "WhatIf: $Message"
                    $LevelText = 'INFO:' 
                } else {
                    Write-Verbose $Message 
                    $LevelText = 'INFO:' 
                }
            } 
        } 
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End { } 
}


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

<#
.SYNOPSIS
    Retrieves data from a Google Sheet using the Google Sheets API.

.DESCRIPTION
    This function connects to the Google Sheets API using the provided sheet 
    information and authentication token. It fetches the specified sheet's 
    data and returns it as an array of PowerShell objects.

.PARAMETER googleSheetInformation
    A hashtable containing:
      - sheetId: The unique identifier of the Google Sheet.
      - sheetRange: The range of cells to retrieve (e.g., "Sheet1!A1:D10" or "Sheet1").

.PARAMETER tokenInformation
    A hashtable containing the authorization headers, typically including an OAuth token 
    required to authenticate API requests.

.OUTPUTS
    Returns an array of PowerShell objects where each object represents a row from 
    the Google Sheet, with column names as property names.

.EXAMPLE
    $sheetInfo = @{
        sheetId = "1aBcD2EfGhIjKlMnOpQrStUvWxYz1234567890"
        sheetRange = "Sheet1!A1:D10"
    }
    $tokenInfo = @{
        "Authorization" = "Bearer YOUR_ACCESS_TOKEN"
        "Accept" = "application/json"
    }

    $data = Get-GoogleSheetData -googleSheetInformation $sheetInfo -tokenInformation $tokenInfo

    This example retrieves the data from a specific range in a Google Sheet and 
    returns it as structured PowerShell objects.

.NOTES
    - Requires valid OAuth 2.0 credentials with permission to access the specified Google Sheet.
    - The first row in the range is treated as column headers.
    - Data is formatted into objects where each row's values are mapped to the corresponding header.
    - Uses `Invoke-RestMethod` to send the request to the Google Sheets API.

    Created by: Sam Cattanach
    Modified: 02/18/2025 09:30:19 AM   
#>
function Get-GoogleSheetData() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        [string]$GoogleSheetID,  # sheet ID

        [parameter(Mandatory=$true)]
        [string]$GoogleSheetRange,  # Sheet Range

        [parameter(Mandatory=$true)]
        [hashtable]$tokenInformation  # Hashtable containing OAuth authentication headers
    )

    # Construct the API request URL using the sheet ID and range
    $uri = "https://sheets.googleapis.com/v4/spreadsheets/{0}/values/{1}?majorDimension=ROWS" -f $googleSheetID, $googleSheetRange

    # Send GET request to Google Sheets API
    $results = Invoke-RestMethod -Uri $uri -Method GET -Headers $tokenInformation -Verbose:$false;

    # Extract column headers from the first row
    $columns = $results.values[0]

    # Initialize an array to store row data
    $allData = @()

    # Process each subsequent row and map values to column headers
    foreach($row in ($results.values | Select-Object -Skip 1) ) {
        if ($rowData) {Remove-Variable rowData}

        $rowData = New-Object -TypeName psobject

        for($i=0; $i -lt $columns.count; $i++) {
            $rowData | Add-Member -MemberType NoteProperty -Name $columns[$i] -Value "$($row[$i])"
        }

        # Append the row data object to the result array
        $allData += $rowData
    }

    $allData
}


<#
.SYNOPSIS
Create a random password given a length

.DESCRIPTION
Create a random password given a length. Default length is 10.

.PARAMETER passwordLength
Integer with the password length between 1 & 256

.EXAMPLE
Get-RandomPassword -PasswordLength 8

.NOTES
   Created by: Sam Cattanach 
   Modified: 2025-01-27 9:33 AM CST
#>
function Get-RandomPassword() {
    [cmdletbinding()]
    Param(
        [Parameter(ValueFromPipeline=$false)]
        [ValidateRange(1,256)]
        [int]$PasswordLength = 10
    )
 
    #ASCII Character set for Password
    $CharacterSet = @{
            Lowercase   = (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_}
            Uppercase   = (65..90)  | Get-Random -Count 10 | ForEach-Object {[char]$_}
            Numeric     = (48..57)  | Get-Random -Count 10 | ForEach-Object {[char]$_}
            #SpecialChar = "!@#$%^&*" -split '' | Where-Object {$_ -ne ''} | Get-Random -Count 10
            SpecialChar = (33..47)+(58..64)+(91..96)+(123..126) | Get-Random -Count 10 | ForEach-Object {[char]$_}
    }
 
    #Frame Random Password from given character set
    $StringSet = $CharacterSet.Uppercase + $CharacterSet.Lowercase + $CharacterSet.Numeric + $CharacterSet.SpecialChar
    
    #Join the objects together to get a string
    -join(Get-Random -Count $PasswordLength -InputObject $StringSet)
}


function Get-StudentGrade() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        [ValidateRange(2000,2099)]
        [int]$gradYear,
        [parameter(Mandatory=$true)]
        $gradeAdvanceDate
    )

    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $currentYear = Get-Date -Format "yyyy"
    $currentYearPlusOne = [int]$currentYear + 1

    if ($currentDate -lt "$currentYear-$gradeAdvanceDate") {
        $schoolYear = $currentYear
    } else {
        $schoolYear = $currentYearPlusOne
    }

    $gradeSet = @{
        [int]$schoolYear = "12"
        ([int]$schoolYear+1) = "11"
        ([int]$schoolYear+2) = "10"
        ([int]$schoolYear+3) = "09"
        ([int]$schoolYear+4) = "08"
        ([int]$schoolYear+5) = "07"
        ([int]$schoolYear+6) = "06"
        ([int]$schoolYear+7) = "05"
        ([int]$schoolYear+8) = "04"
        ([int]$schoolYear+9) = "03"
        ([int]$schoolYear+10) = "02"
        ([int]$schoolYear+11) = "01"
        ([int]$schoolYear+12) = "KG"
        ([int]$schoolYear+13) = "K4"
        ([int]$schoolYear+14) = "PK"
        ([int]$schoolYear+15) = "PK"
        ([int]$schoolYear+16) = "PK"
        ([int]$schoolYear+17) = "PK"
    }

    $gradeSet.($gradYear)
}



<#
.SYNOPSIS
Start-ScriptEnd logs the end of the script

.DESCRIPTION
Start-ScriptEnd writes to the log file that the script finished

.EXAMPLE
Start-ScriptEnd

.NOTES
   Created by: Sam Cattanach 
   Modified: 2025-04-12 9:47 PM CST
#>
function Start-ScriptEnd {
    [cmdletbinding()]
    Param(
        [string]$Message,
        [switch]$WriteError
    )
    
    if ($Message) {
        if ($WriteError) {
            Write-Log -Message $Message -Path $logFile -Level Error
        } else {
            Write-Log -Message $Message -Path $logFile
        }
    }

    Write-Log -Message "######## End of Script Run: $logDate ########" -Path $logFile

    if ($Message) {
        Return $Message
    }
}



function Test-SourceData {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )

    #Required Columns in the Google Sheet
    $requiredColumnsConfig = @(
        "PersonID"
        "NameFirst"
        "NameLast"
        "Username"
        "Building"
        "PersonType"
        "JobTitle"
        "TerminationDate"
        "Word"
        "Process"
    )

    #Check to make sure required columns exist in the data
    $columnsReturned = $SourceData | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Write-Log -Path $logFile -Message "Required columns not found. Columns Needed: $columnCheck" -Level Error
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }

    <# Not needed anymore due to checking files with Test-IDBridgeConfiguration
    #Validate Required Variables are set
    if (!($IDConfig.PersonTypeThree)) {
        Write-Log -Path $logFile -Message "Staff personTypeThree variable needs to be configured" -Level Error
        Throw "Staff personTypeThree variable needs to be configured"
    }
    #>

    #Remove Users who do not have data in all required fields except for terminationDate
    #Remove Users where the process field is false
    $filteredData = @()
    $skippedData = @()

    foreach ($item in $SourceData) {
        if ($item.Process -eq "TRUE") {
            foreach ($column in ($requiredColumnsConfig | Where-Object {$_ -ne "TerminationDate"})) {
                if (!($item.$column)) {
                    $dataCheckFailed = "yes"
                }
            }

            if ($dataCheckFailed) {
                $skippedData += $item
                Write-Log -Path $logFile -Message ("Skipping Person Due to Missing Data in Required Columns: " + $item.PersonID)
                Remove-Variable dataCheckFailed
            } else {
                $filteredData += $item
            }
        } else {
            $skippedData += $item
            Write-Log -Path $logFile -Message ("Skipping Person Due to process field set to false: " + $item.PersonID)
        }
    }

    return $filteredData
}



function Get-DuplicateIDsGoogle {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )

    #Get Google users with duplicate organization external ID
    $duplicateUsers = ($SourceData | ForEach-Object {
        $pkID = ($_.externalIds | Where-Object { $_.Type -eq "organization" }).value
        if ($pkID) {
            [PSCustomObject]@{
                UPN = $_.primaryEmail
                FullName = $_.name.fullName
                OrgID = $pkID
            }
        }
    } | Group-Object -Property OrgID | Where-Object { $_.Count -gt 1 }).group

    if ($duplicateUsers) {
        Write-Log -Path $logFile -Message ("Google: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress)) -Level Error
    }

    return $duplicateUsers
}


function Get-DuplicateIDsAD {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )
    #Get AD users with duplicate employeeID
    $duplicateUsers = ($SourceData.where{$_.employeeID} | 
        Select-Object -Property UserPrincipalName, employeeID | 
        Group-Object -Property employeeID | 
        Where-Object { $_.Count -gt 1 }
        ).group

    if ($duplicateUsers) {
        Write-Log -Path $logFile -Message ("AD: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress)) -Level Error
    }

    return $duplicateUsers
}