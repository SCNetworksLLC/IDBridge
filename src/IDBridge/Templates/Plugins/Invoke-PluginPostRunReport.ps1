# Local JSON Run Report Plugin — IDBridge PostRun plugin template
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by New-IDBridgeConfig.
Works out of the box — just set Enabled = $true on its descriptor in IDBridgeConfig.psd1.

Writes a run-summary JSON (RunSummary-<timestamp>.json) to <RootPath>\Exports after every
run, including failed and ReadOnly runs. Demonstrates the PostRun contract: the run's
outcome, counts, and change lists arrive on the -RunResult parameter (see docs/plugins.md
for the schema); config and the run's log lines come from the existing accessors
Get-IDBridgeConfig and Get-IDBridgeLogs.

The summary sticks to counts and log lines — no per-user records — so the file is safe to
feed a dashboard. RunResult.SourceData and the change lists carry the full records if your
report needs them (SecureStrings are already scrubbed to $null, but the records still
contain names and IDs — think before shipping them off the box).
#>


function Invoke-PluginPostRunReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    #Warn/Error lines from the in-memory log buffer - the closest thing to "what actually
    #failed" (per-user write errors are logged, not collected in the change lists).
    $problemLogs = @((Get-IDBridgeLogs) | Where-Object { $_.Level -in @('Warn', 'Error') })

    $summary = [ordered]@{
        SchemaVersion    = $RunResult.SchemaVersion
        ModuleVersion    = $RunResult.ModuleVersion
        Success          = $RunResult.Success
        Error            = if ($RunResult.RunError) { "$($RunResult.RunError)" } else { $null }
        RunStart         = $RunResult.RunStart.ToString("yyyy-MM-dd HH:mm:ss")
        RunEnd           = $RunResult.RunEnd.ToString("yyyy-MM-dd HH:mm:ss")
        DurationSeconds  = $RunResult.DurationSeconds
        ReadOnly         = $RunResult.ReadOnly
        TestRun          = $RunResult.TestRun
        AppliedCounts    = $RunResult.Counts   # applied work - zeros in ReadOnly
        Proposed         = [ordered]@{          # computed change lists, sizes only
            AD = [ordered]@{
                Enabled     = $RunResult.AD.Enabled
                Create      = @($RunResult.AD.UsersToCreate).Count
                Update      = @($RunResult.AD.UsersToUpdate.UpdateList).Where({ $null -ne $_ }).Count
                Rename      = @($RunResult.AD.UsersToUpdate.RenameList).Where({ $null -ne $_ }).Count
                Move        = @($RunResult.AD.UsersToUpdate.MoveList).Where({ $null -ne $_ }).Count
                Deactivate  = @($RunResult.AD.UsersToDeactivate).Count
                GroupAdd    = @($RunResult.AD.GroupsToUpdate.Add.Groups).Where({ $null -ne $_ }).Count
                GroupRemove = @($RunResult.AD.GroupsToUpdate.Remove.Groups).Where({ $null -ne $_ }).Count
                OrgUnits    = @($RunResult.AD.OrgUnitsToCreate).Count
            }
            Google = [ordered]@{
                Enabled     = $RunResult.Google.Enabled
                Create      = @($RunResult.Google.UsersToCreate).Count
                Update      = @($RunResult.Google.UsersToUpdate).Count
                Deactivate  = @($RunResult.Google.UsersToDeactivate).Count
                GroupAdd    = @($RunResult.Google.GroupsToUpdate.Add.Groups).Where({ $null -ne $_ }).Count
                GroupRemove = @($RunResult.Google.GroupsToUpdate.Remove.Groups).Where({ $null -ne $_ }).Count
                OrgUnits    = @($RunResult.Google.OrgUnitsToCreate).Count
            }
        }
        ThresholdResults = @($RunResult.ThresholdResults)
        Warnings         = @($problemLogs | ForEach-Object { "$($_.Timestamp) $($_.Level): $($_.Message)" })
    }

    $reportPath = "$($IDConfig.Paths.ExportsRoot)\RunSummary-$($RunResult.RunEnd.ToString("yyyy-MM-dd-HH.mm.ss")).json"
    $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $reportPath -Force

    Write-Log -Message "Plugin: Invoke-PluginPostRunReport wrote run summary to $reportPath"
}
