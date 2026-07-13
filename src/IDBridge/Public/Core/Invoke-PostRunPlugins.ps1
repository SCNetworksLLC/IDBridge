<#
.SYNOPSIS
Discover and run the configured PostRun plugins with the run's RunResult object.

.DESCRIPTION
Iterates the Plugins array from the configuration in order, skipping every descriptor whose
Type is not PostRun. For each enabled descriptor it verifies <PluginsRoot>\<Function>.ps1
exists, dot-sources it, and confirms the function resolves — disabling the plugin with a Warn
if the file fails to load or the function is missing. Each plugin is invoked as
& <Function> -RunResult <RunResult>.

Called from the finally block of Invoke-IDBridge after every run (including failed and
ReadOnly runs — the RunResult carries Success/ReadOnly so plugins decide for themselves).
Every plugin invocation is isolated in its own try/catch: a failing PostRun plugin logs a
Warn and the next plugin still runs. This function never throws — it can never mask the
run's real outcome. Plugins read config and logs through the existing accessors
(Get-IDBridgeConfig, Get-IDBridgeLogs); the RunResult carries what those don't.

.PARAMETER RunResult
The RunResult object assembled by Invoke-IDBridge (SchemaVersion 1): outcome, timing, mode
flags, applied-work counts, threshold results, enriched source data, and the per-directory
change lists. SecureString values have already been scrubbed to $null.

.OUTPUTS
None. Side effects are whatever the plugins do (reports, webhooks, dashboards) plus log output.

.EXAMPLE
Invoke-PostRunPlugins -RunResult $runResult

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-12
#>
function Invoke-PostRunPlugins {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    #region Import Configuration
    # This runs inside the caller's finally block, so even a config failure must not throw.
    try { $IDConfig = Get-IDBridgeConfig } catch { return }
    #endregion Import Configuration

    foreach ($plugin in $IDConfig.Plugins) {
        if ($plugin.Type -ne "PostRun") { Continue }

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

        #If the plugin is enabled and the function exists, run the plugin with the RunResult.
        #Each plugin is isolated: a failure is logged and the remaining plugins still run.
        try {
            Write-Log -Message "Running $($plugin.Type) Plugin: $($plugin.Function)" -Level Info
            & $plugin.Function -RunResult $RunResult
        }
        catch {
            Write-Log -Message "Plugin: PostRun: $($plugin.Function) failed (run unaffected): $($_)" -Level Warn
        }
    }
}
