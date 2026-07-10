<#
.SYNOPSIS
Discover and run the configured source and override plugins, returning their data.

.DESCRIPTION
Iterates the Plugins array from the configuration in order. For each enabled descriptor it
verifies <PluginsRoot>\<Function>.ps1 exists, dot-sources it, and confirms the function resolves
— disabling the plugin with a Warn if the file fails to load or the function is missing. Each
plugin is invoked with no arguments. Source plugin output is passed through
Test-IDBridgeSourceData before being collected; when Debug.testRun is set, each source plugin's
validated output is then capped at the first 10 records for faster iteration. Override output is
collected as-is. Throws if no source data was gathered after all plugins run.

.OUTPUTS
[pscustomobject] @{ SourceData; OverrideData } — the combined results split by plugin Type.

.EXAMPLE
$plugins = Invoke-SourcePlugins
$sourceData = $plugins.SourceData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Invoke-SourcePlugins {
    [CmdletBinding()]
    param()

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    $sourceData = @()
    $overrideData = @()
    foreach ($plugin in $IDConfig.Plugins) {
        if ($plugin.Enabled -ne $true) {
            Write-Log -Message "Plugin: $($plugin.Function) is disabled in config. Skipping plugin." -Level Trace
            Continue
        }

        if (Test-Path "$($IDConfig.Paths.PluginsRoot)\$($plugin.Function).ps1" -PathType Leaf -ErrorAction SilentlyContinue) {
            try {
                . "$($IDConfig.Paths.PluginsRoot)\$($plugin.Function).ps1"
            }
            catch {
                Write-Log -Message "Plugin: $($plugin.Function) is enabled in config but failed to load. Disabling plugin. Error: $($_)" -Level Warn
                $plugin.Enabled = $false
                Continue
            }
        }

        if (-not (Get-Command $plugin.Function -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Plugin: $($plugin.Function) is enabled in config but not found. Disabling plugin." -Level Warn
            $plugin.Enabled = $false
            Continue
        }

        #If the plugin is enabled and the function exists, run the plugin to gather data and add it to the list of data to be processed later in the script.
        try {
            Write-Log -Message "Running $($plugin.Type) Plugin: $($plugin.Function)" -Level Info
            $pluginData = $null
            
            $pluginData = & $plugin.Function
            #$pluginData = & (Get-Command "$($IDConfig.Paths.PluginsRoot)\$($plugin.Function).ps1").ScriptBlock
        }
        catch { Throw $_ }

        if ($pluginData) {
            if ($plugin.Type -eq "Source") {
                $validData = Test-IDBridgeSourceData -InputObject $pluginData -PluginName $plugin.Function

                #Limit each source plugin's data to 10 records if Test Run is active
                if ($IDConfig.Debug.testRun -eq $true -and $validData.Count -gt 0) {
                    $validData = @($validData | Select-Object -First 10)
                    Write-Log -Message "TEST RUN: LIMITING $($plugin.Function) SOURCE DATA TO $($validData.Count) USERS - $($validData.PersonID)"
                }

                $sourceData += $validData
            }
            if ($plugin.Type -eq "Override") {
                $overrideData += $pluginData
            }
        } else {
            if ($plugin.Type -eq "Source") {
                Write-Log -Message "Plugin: Source: $($plugin.Function) did not return any data." -Level Warn
            }
            if ($plugin.Type -eq "Override") {
                Write-Log -Message "Plugin: Override: $($plugin.Function) did not return any data." -Level Trace
            }
        }
    }

    if ($sourceData.Count -eq 0) {
        Throw "No source data gathered from plugins. Please check plugin configurations and logs for details."
    }

    return [PSCustomObject]@{
        SourceData   = $sourceData
        OverrideData = $overrideData
    }
}