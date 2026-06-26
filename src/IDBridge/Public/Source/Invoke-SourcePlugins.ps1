<#
Check for enabled plugins and if the function exists for them, if not disable the plugin and log a warning
For each plugin, run the funciton, and add the returned values to an array to be processed later in the script.
This allows for dynamic data gathering and processing based on the plugins enabled in the configuration file.
There are specific plugin types.
Source plugins gather data that is used as the basis for processing in the script, such as user lists from a SIS or HR system.
Override plugins gather data that is used to override or modify the source data before processing.
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
                $sourceData += Test-IDBridgeSourceData -InputObject $pluginData -PluginName $plugin.Function
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