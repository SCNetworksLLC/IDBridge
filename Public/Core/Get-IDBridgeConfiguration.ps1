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