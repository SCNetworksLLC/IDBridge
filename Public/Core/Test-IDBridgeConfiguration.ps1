<#
.SYNOPSIS
Validates the runtime configuration for IDBridge (folders and required JSON files).

.DESCRIPTION
Performs a quick set of checks to ensure the IDBridge runtime configuration is present and minimally valid.
By default it checks:
 - The base folder C:\IDBridge exists.
 - The `Config` folder exists and contains the expected configuration files:
   GoogleToken.json, GoogleSheet.json, General.json, Google.json, AD.json, PersonTypeThree.json
 - The `Auth` folder exists and contains exactly one JSON file (the Google service account file).

If any check fails the function throws with a clear message so callers (the runner) can abort safely.

.PARAMETER None
This implementation accepts no parameters (operates on the hard-coded C:\IDBridge paths). Consider adding a
`-BasePath` parameter if you want to validate a different location.

.EXAMPLE
Test-IDBridgeConfiguration

Runs all checks and writes status messages to the console. If everything is present the function exits normally.
If a required item is missing the function throws with a message naming the missing item.

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None. The function writes status messages to host and throws on error. Callers can assume success if no exception is raised.

.NOTES
Remarks:
- Expected config files (checked in `C:\IDBridge\Config`):
  GoogleToken.json, GoogleSheet.json, General.json, Google.json, AD.json, PersonTypeThree.json
- The Auth folder (`C:\IDBridge\Auth`) must contain exactly one `.json` file (the service account credential).
- The function uses exceptions to signal missing/invalid configuration; the main runner (`IDBridge.ps1`) relies on these exceptions to stop startup and surface a helpful error to the user.
- To make this function more testable or flexible, consider adding optional parameters:
    -BasePath <string>   # default: C:\IDBridge
    -RequiredConfigFiles <string[]> # override the expected config file list

Author: SCNetworksLLC (Sam Cattanach)
File: Public/Core/Test-IDBridgeConfiguration.ps1
#>

function Test-IDBridgeConfiguration {
    [CmdletBinding()]
    param ()

    $basePath = "C:\IDBridge"
    $configPath = Join-Path $basePath "Config"
    $authPath = Join-Path $basePath "Auth"

    $expectedConfigFiles = @(
        "GoogleToken.json",
        "GoogleSheet.json",
        "Google.json",
        "AD.json",
        "PersonTypeThree.json",
        "Staff.json",
        "Student.json",
        "Staff.json"
    )

    Write-Host "Checking IDBridge configuration folder structure..." -ForegroundColor Cyan

    if (-not (Test-Path $basePath)) {
        Throw "'Folder C:\IDBridge Not Found"
    }

    # Check each config file
    if (Test-Path $configPath) {
        foreach ($file in $expectedConfigFiles) {
            $filePath = Join-Path $configPath $file
            if (-Not (Test-Path $filePath)) {
                Throw "Missing config file: $file"
            } else {
                Write-Host "Found config file: $file" -ForegroundColor Green
            }
        }
    } else {
        Throw "'Config' folder not found"
    }

    # Check for exactly 1 JSON file in the Auth folder
    if (Test-Path $authPath) {
        $authJsonFiles = Get-ChildItem -Path $authPath -Filter *.json -File
        if ($authJsonFiles.Count -eq 1) {
            Write-Host "Found 1 authentication JSON file: $($authJsonFiles[0].Name)" -ForegroundColor Green
        } elseif ($authJsonFiles.Count -eq 0) {
            Throw "No authentication JSON file found in 'Auth'"
        } else {
            Throw "Multiple authentication JSON files found in 'Auth'"
        }
    } else {
        Throw "'Auth' folder not found"
    }
    
    Write-Host "All required configuration files are present." -ForegroundColor Green


}