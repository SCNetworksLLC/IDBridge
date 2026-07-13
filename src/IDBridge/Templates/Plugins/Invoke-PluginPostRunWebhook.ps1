# Run Summary Webhook Plugin — IDBridge PostRun plugin template
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by New-IDBridgeConfig.
Set the webhook URL before enabling the plugin in IDBridgeConfig.psd1 — it throws until
the URL is set.

POSTs a compact run-summary JSON to your own endpoint after every run (including failed
and ReadOnly runs) — the starting point for shipping your own telemetry or feeding a
dashboard/alerting pipeline. The payload below is counts and flags only, no per-user data;
if you extend it from RunResult.SourceData or the change lists, remember those records
carry names and IDs (SecureStrings are already scrubbed to $null).

The send is fire-and-forget: short timeout, failures are logged as a Warn and never affect
the run.
#>


function Invoke-PluginPostRunWebhook {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    $webhookUrl = "https://YOUR-WEBHOOK-URL"   # e.g. your ingest endpoint, Power Automate flow, or chat webhook

    if ($webhookUrl -eq "https://YOUR-WEBHOOK-URL") {
        Throw "Invoke-PluginPostRunWebhook: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    $payload = [ordered]@{
        schemaVersion   = $RunResult.SchemaVersion
        moduleVersion   = $RunResult.ModuleVersion
        success         = $RunResult.Success
        error           = if ($RunResult.RunError) { "$($RunResult.RunError)" } else { $null }
        runEnd          = $RunResult.RunEnd.ToString("yyyy-MM-dd HH:mm:ss")
        durationSeconds = $RunResult.DurationSeconds
        readOnly        = $RunResult.ReadOnly
        testRun         = $RunResult.TestRun
        managedCount    = $RunResult.Counts.Managed
        createCount     = $RunResult.Counts.Create
        updateCount     = $RunResult.Counts.Update
        deactivateCount = $RunResult.Counts.Deactivate
        groupAddCount   = $RunResult.Counts.GroupAdd
        groupRemoveCount = $RunResult.Counts.GroupRemove
    }

    try {
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body ($payload | ConvertTo-Json -Compress) -ContentType 'application/json' -TimeoutSec 10 | Out-Null
        Write-Log -Message "Plugin: Invoke-PluginPostRunWebhook sent run summary." -Level Trace
    }
    catch {
        Write-Log -Message "Plugin: Invoke-PluginPostRunWebhook send failed (run unaffected): $($_.Exception.GetType().Name)" -Level Warn
    }
}
