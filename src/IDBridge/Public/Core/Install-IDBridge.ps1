<#
.SYNOPSIS
Install scaffold: create the IDBridge folder tree, default config, and plugin templates.

.DESCRIPTION
Setup helper for a fresh install. It:
  - creates the runtime directory tree under RootPath (Config/Logs/Exports/Plugins/Data/Vault);
  - copies the shipped config template (module Templates\Config\IDBridgeConfig.psd1) to
    <RootPath>\Config\IDBridgeConfig.psd1 — every feature disabled and placeholder values
    for all site-specific settings;
  - copies the shipped plugin templates (module Templates\Plugins) into <RootPath>\Plugins.

Nothing that exists is ever overwritten (there is deliberately no -Force): an existing
config file or plugin file is left alone with a notice. That makes it safe to re-run on
an existing install — after a module update, re-running it copies any NEW plugin
templates the update shipped and touches nothing else. When a skipped file's shipped
template carries a higher '# TemplateVersion: <n>' marker than the installed copy, a
notice points at the shipped template to review — the site's edited copy is still never
touched. The generated config is safe to
load immediately: ReadOnly stays $true, AD/Google processing and every plugin are
disabled, and all site-specific values are obvious placeholders to fill in before
enabling anything — the plugin templates themselves throw until their placeholder values
are edited.

This runs before any state exists, so it does not use Write-Log or require
Initialize-IDBridge — run it first, edit the config, then run Initialize-IDBridge.

.PARAMETER RootPath
Base directory for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.
Missing directories are created.

.OUTPUTS
None. Writes the default config file and prints its path.

.EXAMPLE
Install-IDBridge

.EXAMPLE
Install-IDBridge -RootPath 'D:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-13
#>
function Install-IDBridge {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge"
    )

    $configFilePath = Join-Path $RootPath "Config\IDBridgeConfig.psd1"

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

            #Notify (never overwrite) when the shipped template is newer than the installed copy
            $installedVersion = Get-IDBridgeTemplateVersion -Path $destination
            $shippedVersion = Get-IDBridgeTemplateVersion -Path $template.FullName
            if ($shippedVersion -gt [int]$installedVersion) {
                $installedLabel = if ($installedVersion) { "v$installedVersion" } else { "unversioned" }
                Write-Host "  -> newer template available (your copy: $installedLabel, shipped: v$shippedVersion) - review $($template.FullName)" -ForegroundColor Cyan
            }
        } else {
            Copy-Item -Path $template.FullName -Destination $destination
            Write-Host "Copied plugin template: $destination" -ForegroundColor Green
        }
    }
    #endregion Copy Plugin Templates

    #region Copy Default Config
    $configTemplate = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\Templates\Config\IDBridgeConfig.psd1"))
    if (Test-Path $configFilePath) {
        Write-Host "Config already exists and will not be overwritten: $configFilePath" -ForegroundColor Yellow

        #Notify (never overwrite) when the shipped config template is newer than the installed config
        $installedVersion = Get-IDBridgeTemplateVersion -Path $configFilePath
        $shippedVersion = Get-IDBridgeTemplateVersion -Path $configTemplate
        if ($shippedVersion -gt [int]$installedVersion) {
            $installedLabel = if ($installedVersion) { "v$installedVersion" } else { "unversioned" }
            Write-Host "  -> newer config template available (your copy: $installedLabel, shipped: v$shippedVersion) - review $configTemplate for new settings" -ForegroundColor Cyan
        }
    } else {
        try {
            Copy-Item -Path $configTemplate -Destination $configFilePath -ErrorAction Stop
        }
        catch {
            Throw "Error writing default config file: $_"
        }

        Write-Host "Created default config: $configFilePath" -ForegroundColor Green
        Write-Host "Edit the placeholder values, then run Initialize-IDBridge to load it."
    }
    #endregion Copy Default Config
}
