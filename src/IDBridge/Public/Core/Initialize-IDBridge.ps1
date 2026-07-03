<#
.SYNOPSIS
Load configuration and prepare all global state for an IDBridge run.

.DESCRIPTION
First stage of a run, called by Invoke-IDBridge. It:
  - imports <RootPath>\Config\IDBridgeConfig.psd1 into the script-scoped configuration;
  - builds and creates the runtime Paths.* directories (Config/Auth/Logs/Exports/Plugins/Data/Vault);
  - initializes logging (in-memory buffer + log file, rotating the file past 5 MB) and writes
    the run-start marker;
  - when GoogleToken.Enabled, reads the service-account key JSON from the secret vault
    (secret 'GoogleAuth-ServiceAccount'), validates it has a private_key, and acquires a
    bearer token into the script-scoped Google headers via Get-GoogleApiAccessToken;
  - imports the ActiveDirectory module when AD.enabled (throwing unless Debug.skipADCheck);
  - applies the feature-dependency cascade (missing Google headers disables Google; disabling a
    directory disables its group processing).

.PARAMETER RootPath
Base directory for Config/Auth/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.
Missing directories are created.

.OUTPUTS
None. Populates the script-scoped IDBridgeConfig, Logs, and GoogleHeaders state.

.EXAMPLE
Initialize-IDBridge -RootPath 'C:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Initialize-IDBridge {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge"
    )

    Write-Host "Importing config file from $RootPath"

    try {
        $configFilePath = Join-Path $RootPath "Config\IDBridgeConfig.psd1"
        if (Test-Path $configFilePath) {
            $script:IDBridgeConfig = Import-PowerShellDataFile -Path $configFilePath -ErrorAction Stop
            Write-Host "Successfully imported IDBridgeConfig.psd1" -ForegroundColor Green
        } else {
            Throw "Config file not found: $configFilePath"
        }
    }
    catch {
        Throw "Error importing config file: $_"
    }

    $script:IDBridgeConfig.Paths = @{
        Root        = $RootPath
        ConfigRoot  = "$RootPath\Config"
        AuthRoot    = "$RootPath\Auth"
        LogsRoot    = "$RootPath\Logs"
        ExportsRoot = "$RootPath\Exports"
        PluginsRoot = "$RootPath\Plugins"
        DataRoot    = "$RootPath\Data"
        VaultRoot   = "$RootPath\Vault"
    }

    #region Validate Paths
    foreach ($path in $script:IDBridgeConfig.Paths.GetEnumerator()) {
        if (-not (Test-Path $path.Value)) {
            New-Item -ItemType Directory -Path $path.Value -Force | Out-Null
            Write-Host "Created missing directory: $($path.Value)" -ForegroundColor Yellow
        }
    }
    #endregion Validate Paths


    #region Set Logging
    $script:IDBridgeConfig.Paths.LogFile = Join-Path $script:IDBridgeConfig.Paths.LogsRoot "IDBridge.log"
    
    # Initialize the global $Log variable as a hashtable if it doesn't already exist. This allows us to store log information in memory for use elsewhere in the script (e.g. for Google Sheet logging) without having to read from the log file.
    $script:Logs = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ((Test-Path $script:IDBridgeConfig.Paths.LogFile) -and (Get-Item $script:IDBridgeConfig.Paths.LogFile).Length -gt 5000000) {
        Rename-Item $script:IDBridgeConfig.Paths.LogFile ((Get-Item $script:IDBridgeConfig.Paths.LogFile).BaseName + "_" + $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########"

    if ($script:IDBridgeConfig.Debug.TraceLogging -eq $true) {
        Write-Log -Message "Trace logging is ENABLED" -Level Trace
    }
    #endregion Set Logging

  


    #region Google Auth
    if ($script:IDBridgeConfig.GoogleToken.Enabled -eq $true) {
        # Read the service-account key JSON from the IDBridge secret vault (no file fallback)
        try {
            $googleAuthJson = Get-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -AsPlainText
        }
        catch {
            Throw "The Google service-account key could not be read from the secret vault. Seed it with: Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -InFile <key.json>. ($_)"
        }

        # Validate it is a valid Google Service Account JSON by checking for a private key
        try {
            $googleAuthContent = $googleAuthJson | ConvertFrom-Json
        }
        catch {
            Throw "The 'GoogleAuth-ServiceAccount' secret is not valid JSON. Error: $_"
        }

        if ($googleAuthContent.PSObject.Properties.Name -notcontains "private_key") {
            throw "The Google Auth JSON does not contain a valid 'private_key'."
        }

        Write-Log -Message "Loaded Google service-account key from secret 'GoogleAuth-ServiceAccount'" -Level Trace

        try {
            $paramsGoogleHeaders = @{
                ServiceAccountKeyJson = $googleAuthJson
                Scope                 = $script:IDBridgeConfig.GoogleToken.googleAuthScope
                TargetUserEmail      = $script:IDBridgeConfig.GoogleToken.adminEmail
            }

            $script:GoogleHeaders = Get-GoogleApiAccessToken @paramsGoogleHeaders
        }
        catch { Throw }

    } else {
        Write-Log -Message "Google API integration is disabled. Google-related functions will be skipped." -Level Trace
    }
    #endregion Google Auth




    #region Test Additional Modules
    if ($script:IDBridgeConfig.AD.enabled -eq $true) {
        #Test AD Module
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Write-Log -Message "Imported Active Directory Module" -Level Trace
        }
        catch {
            Write-Host "AD Powershell Module does not exit on the local machine: $($_)" -ForegroundColor Red
            if ($script:IDBridgeConfig.Debug.skipADCheck -ne $true) {
                Throw "AD Powershell Module does not exit on the local machine: $_"
            }
        }
    }
    #endregion Test Additional Modules



    #region Check Active IDBridge Configurations
    #Check if Read Only Mode is active
    if ($script:IDBridgeConfig.Debug.readOnly -eq $true) {
        Write-Log -Message "READ ONLY MODE: NO CHANGES WILL BE MADE"
    }

    #Deactivate Google if Auth isn't enabled
    if (-not $script:GoogleHeaders) {
        $script:IDBridgeConfig.Google.Enabled = $false
    }

    #Deactivate Groups if module isn't enabled
    if ($script:IDBridgeConfig.Google.enabled -eq $false) {
        $script:IDBridgeConfig.Google.enableGroupProcessing = $false
    }

    if ($script:IDBridgeConfig.AD.enabled -eq $false) {
        $script:IDBridgeConfig.AD.enableGroupProcessing = $false
    }
    #endregion Check Active IDBridge Configurations



    # Return the $script:IDBridgeConfig Variable
    #return $IDBridgeConfig
}