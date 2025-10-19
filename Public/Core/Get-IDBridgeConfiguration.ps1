<#
.SYNOPSIS
Loads IDBridge runtime configuration from JSON files and performs environment checks.

.DESCRIPTION
Reads all JSON files from the configured config folder (default: C:\IDBridge\Config) and builds
a hashtable where each key is the JSON filename base (spaces replaced with underscores) and the
value is the parsed JSON object. The function also performs a small set of environment checks:
 - If AD is enabled in the loaded config, attempts to import the ActiveDirectory PowerShell module.
   If the module is missing and `Debug.SkipADCHeck` is not set, the function will throw.
 - Adjusts some runtime flags (for example it disables group processing for Google/AD when the
   respective service is disabled).

This function returns a hashtable (PSCustomObject-like) containing all loaded configuration objects
indexed by filename base (e.g., `$IDBridgeConfig.General`, `$IDBridgeConfig.Google`, etc.).

.PARAMETER None
This implementation accepts no parameters and uses the hard-coded config path `C:\IDBridge\Config`.
Consider adding a `-ConfigPath` parameter to validate other locations or improve testability.

.EXAMPLE
$IDConfig = Get-IDBridgeConfiguration
# $IDConfig now contains all JSON config objects loaded from C:\IDBridge\Config

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
Hashtable of configuration objects (PSCustomObject). Example access:
$IDConfig.General
$IDConfig.Google
$IDConfig.AD

.NOTES
Author: SCNetworksLLC (Sam Cattanach)
File: Public/Core/Get-IDBridgeConfiguration.ps1
#>

function Get-IDBridgeConfiguration {
    [CmdletBinding()]
    param ()

    $configPath = "C:\IDBridge\Config"

    Write-Host "Importing all JSON config files from $($configPath)"

    $IDBridgeConfig = @{}

    # Load all .json config files in the Config folder
    Get-ChildItem -Path $configPath -Filter *.json -File | ForEach-Object {
        try {
            $baseName = $_.BaseName -replace ' ', '_'  # Replace spaces with underscores
            $jsonContent = Get-Content $_.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $IDBridgeConfig[$baseName] = $jsonContent
            Write-Host "Loaded config: $($baseName)"
        }
        catch {
            Throw "Error getting JSON for file $($baseName): $_"
        }
    }

    Write-Host "All configuration files successfully loaded"

    #region Test Additional Modules
    if ($IDBridgeConfig.AD.enabled -eq $true) {
        #Test AD Module
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Write-Host "Imported Active Directory Module"
        }
        catch {
            Write-Log -Message "AD Powershell Module does not exit on the local machine: $_" -Path $logFile
            if ($IDBridgeConfig.Debug.SkipADCHeck -ne $true) {
                Throw "AD Powershell Module does not exit on the local machine: $_"
            }
        }
    }
    #endregion Test Additional Modules

    #region Check Active IDBridge Configurations
    #Check if Read Only Mode is active
    if ($IDBridgeConfig.General.readOnly -eq $true) {
        Write-Log -Path $logFile -Message "READ ONLY MODE: NO CHANGES WILL BE MADE"
    }

    #Deactivate Groups if module isn't enabled
    if ($IDBridgeConfig.Google.enabled -eq $false) {
        $IDBridgeConfig.Google.enableGroupProcessing = $false
    }

    if ($IDBridgeConfig.AD.enabled -eq $false) {
        $IDBridgeConfig.AD.enableGroupProcessing = $false
    }
    #endregion Check Active IDBridge Configurations

    # Return the $IDBridgeConfig Variable
    return $IDBridgeConfig
}