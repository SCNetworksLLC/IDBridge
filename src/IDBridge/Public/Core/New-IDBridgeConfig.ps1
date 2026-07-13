<#
.SYNOPSIS
First-run scaffold: create the IDBridge folder tree and a default IDBridgeConfig.psd1.

.DESCRIPTION
One-time setup helper for a fresh install. It:
  - creates the runtime directory tree under RootPath (Config/Logs/Exports/Plugins/Data/Vault);
  - copies the shipped config template (module Templates\Config\IDBridgeConfig.psd1) to
    <RootPath>\Config\IDBridgeConfig.psd1 — every feature disabled and placeholder values
    for all site-specific settings;
  - copies the shipped plugin templates (module Templates\Plugins) into <RootPath>\Plugins.

An existing config file is NEVER overwritten — the function throws instead (there is
deliberately no -Force); an existing plugin file is likewise left alone. The generated
config is safe to load immediately: ReadOnly stays $true, AD/Google processing and every
plugin are disabled, and all site-specific values are obvious placeholders to fill in
before enabling anything — the plugin templates themselves throw until their placeholder
values are edited.

This runs before any state exists, so it does not use Write-Log or require
Initialize-IDBridge — run it first, edit the config, then run Initialize-IDBridge.

.PARAMETER RootPath
Base directory for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.
Missing directories are created.

.OUTPUTS
None. Writes the default config file and prints its path.

.EXAMPLE
New-IDBridgeConfig

.EXAMPLE
New-IDBridgeConfig -RootPath 'D:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-13
#>
function New-IDBridgeConfig {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge"
    )

    $configFilePath = Join-Path $RootPath "Config\IDBridgeConfig.psd1"
    if (Test-Path $configFilePath) {
        Throw "Config file already exists and will not be overwritten: $configFilePath"
    }

    #region Create Directories
    $directories = @(
        $RootPath
        "$RootPath\Config"
        "$RootPath\Logs"
        "$RootPath\Exports"
        "$RootPath\Plugins"
        "$RootPath\Data"
        "$RootPath\Vault"
    )
    foreach ($directory in $directories) {
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Write-Host "Created missing directory: $directory" -ForegroundColor Yellow
        }
    }
    #endregion Create Directories

    #region Copy Plugin Templates
    $templateSource = Join-Path $PSScriptRoot "..\..\Templates\Plugins"
    foreach ($template in (Get-ChildItem -Path $templateSource -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
        $destination = Join-Path "$RootPath\Plugins" $template.Name
        if (Test-Path $destination) {
            Write-Host "Plugin already exists and will not be overwritten: $destination" -ForegroundColor Yellow
        } else {
            Copy-Item -Path $template.FullName -Destination $destination
            Write-Host "Copied plugin template: $destination" -ForegroundColor Green
        }
    }
    #endregion Copy Plugin Templates

    #region Copy Default Config
    $configTemplate = Join-Path $PSScriptRoot "..\..\Templates\Config\IDBridgeConfig.psd1"
    try {
        Copy-Item -Path $configTemplate -Destination $configFilePath -ErrorAction Stop
    }
    catch {
        Throw "Error writing default config file: $_"
    }
    #endregion Copy Default Config

    Write-Host "Created default config: $configFilePath" -ForegroundColor Green
    Write-Host "Edit the placeholder values, then run Initialize-IDBridge to load it."
}
