<#
.SYNOPSIS
Locates and validates the Google service account JSON file used for API authentication.

.DESCRIPTION
Searches the folder `C:\IDBridge\Auth` for JSON files and verifies there is exactly one
service account file present. The JSON is parsed and validated to ensure it contains the
required `private_key` property used by Google service account credentials. If validation
passes the full path to the JSON file is returned; otherwise the function throws an error.

.EXAMPLE
$authPath = Get-IDBridgeGoogleAuthFile
Returns the full path to the single Google service account JSON file under
`C:\IDBridge\Auth` and writes a confirmation to the host.

.INPUTS
None. The function does not accept pipeline input.

.OUTPUTS
System.String — full path to the validated Google service account JSON file.

.NOTES
Author: SCNetworksLLC (Sam Cattanach)
File: Public/Core/Get-IDBridgeGoogleAuthFile.ps1
#>
function Get-IDBridgeGoogleAuthFile {
    [CmdletBinding()]
    param ()

    $authPath   = "C:\IDBridge\Auth"

    # Handle the Google Auth file in the Auth folder
    $authFiles = Get-ChildItem -Path $authPath -Filter *.json -File

    if ($authFiles.Count -ne 1) {
        throw "Expected exactly one JSON file in $($authPath), but found $($authFiles.Count)."
    }

    $authFilePath = $authFiles[0].FullName

    # Validate if the file is a valid Google Service Account JSON by checking for a private key
    try {
        $googleAuthContent = Get-Content $authFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Throw "Invalid Google Auth JSON file at $($authFilePath). Error: $_"
    }
    
    if ($googleAuthContent.PSObject.Properties.Name -notcontains "private_key") {
        throw "The Google Auth JSON file does not contain a valid 'private_key'."
    }

    # Return the path
    Write-Host "Loaded valid Google Auth JSON file: $($authFilePath)"
    return $authFilePath
}