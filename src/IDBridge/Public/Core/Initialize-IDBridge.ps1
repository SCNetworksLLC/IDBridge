<#
.SYNOPSIS
Load configuration and prepare all global state for an IDBridge run.

.DESCRIPTION
First stage of a run, called by Invoke-IDBridge. It:
  - imports <RootPath>\Config\IDBridgeConfig.psd1 into the script-scoped configuration;
  - builds and creates the runtime Paths.* directories (Config/Logs/Exports/Plugins/Data/Vault);
  - initializes logging (in-memory buffer + log file, rotating the file past 5 MB) and writes
    the run-start marker;
  - imports the ActiveDirectory module when AD.enabled (throwing unless Debug.skipADCheck);
  - applies the feature-dependency cascade (disabling a directory disables its group
    processing).

Google auth is NOT acquired here — Invoke-IDBridge does that at the start of a run (after
the runtime overrides). That keeps first-run setup simple: Initialize-IDBridge always
succeeds on a fresh install, so the certificate/secret/bootstrap functions can run before
the 'GoogleAuth-ServiceAccount' secret exists.

.PARAMETER RootPath
Base directory for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.
Missing directories are created.

.PARAMETER SkipADCheck
Set Debug.skipADCheck before the AD module import, so a failed import does not throw.
Forwarded by Invoke-IDBridge -SkipADCheck (the other runtime overrides are applied after
initialization, too late to affect the import).

.PARAMETER SkipAD
Set AD.enabled = $false before the AD module import, skipping it entirely (the feature
cascade then also disables AD group processing). Forwarded by Invoke-IDBridge -SkipAD.

.OUTPUTS
None. Populates the script-scoped IDBridgeConfig and Logs state.

.EXAMPLE
Initialize-IDBridge -RootPath 'C:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-20
#>
function Initialize-IDBridge {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge",

        [switch]$SkipADCheck,

        [switch]$SkipAD
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

    #Switch overrides forwarded by Invoke-IDBridge that must land BEFORE the AD module
    #import below - the remaining runtime overrides are applied after initialization
    if ($SkipADCheck) { $script:IDBridgeConfig.Debug.skipADCheck = $true }
    if ($SkipAD)      { $script:IDBridgeConfig.AD.enabled = $false }

    $script:IDBridgeConfig.Paths = @{
        Root        = $RootPath
        ConfigRoot  = "$RootPath\Config"
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

    # Per-user write results for this run (populated by Add-IDBridgeWriteResult during the
    # write phases) - reset here so results never leak across runs in one session.
    $script:WriteResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ((Test-Path $script:IDBridgeConfig.Paths.LogFile) -and (Get-Item $script:IDBridgeConfig.Paths.LogFile).Length -gt 5000000) {
        Rename-Item $script:IDBridgeConfig.Paths.LogFile ((Get-Item $script:IDBridgeConfig.Paths.LogFile).BaseName + "_" + $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########"

    if ($script:IDBridgeConfig.Debug.TraceLogging -eq $true) {
        Write-Log -Message "Trace logging is ENABLED" -Level Trace
    }
    #endregion Set Logging

  


    #region Test Additional Modules
    if ($script:IDBridgeConfig.AD.enabled -eq $true) {
        #Test AD Module
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Write-Log -Message "Imported Active Directory Module" -Level Trace
        }
        catch {
            Write-Host "AD Powershell Module does not exist on the local machine: $($_)" -ForegroundColor Red
            if ($script:IDBridgeConfig.Debug.skipADCheck -ne $true) {
                Throw "AD Powershell Module does not exist on the local machine: $_"
            }
        }
    }
    #endregion Test Additional Modules



    #region Check Active IDBridge Configurations
    #Check if Read Only Mode is active
    if ($script:IDBridgeConfig.Debug.readOnly -eq $true) {
        Write-Log -Message "READ ONLY MODE: NO CHANGES WILL BE MADE"
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