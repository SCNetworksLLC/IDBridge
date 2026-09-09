# Beacon Heartbeat Plugin — IDBridge PostRun plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
Set the Beacon ingest URL and the site id below, store the automation's Beacon site key
in the vault (Set-IDBridgeSecret -Name 'ApiKey-Beacon'), then enable the plugin in
IDBridgeConfig.psd1 — it throws until the placeholders are edited.

POSTs one heartbeat to Beacon (SC Networks' status dashboard) after every run, failed and
ReadOnly runs included: an envelope of sourceType 'automation' whose data carries result
(Success / Warning when a write failed / Failed when the run threw), a one-line message
built from the counts ("412 managed: 3 created, 5 updated, 1 deactivated, 2 group changes,
0 write failures, 47s"), and the counts and flags themselves. Beacon's staleness model does
the rest: an automation source is expected every ~12 hours, so a nightly run that stops
reporting goes amber on its own and a Failed result goes red at once. Counts and flags
only, no per-user data.

The send is fire-and-forget: short timeout, failures are logged as a Warn and never affect
the run. The envelope is built by ConvertTo-BeaconHeartbeat below, a pure helper the tests
under tests\Templates\Plugins exercise.
#>


function Invoke-PluginPostRunBeacon {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    $ingestUrl = "https://YOUR-BEACON/api/ingest"   # e.g. https://beacon.scnlabs.net/api/ingest
    $siteId    = "YOUR-SITE-ID"                      # the district's Beacon site id (Beacon Setup → Sites)
    $sourceId  = "idbridge-sync"                     # how this install shows on the dashboard; one per install

    if ($ingestUrl -eq "https://YOUR-BEACON/api/ingest" -or $siteId -eq "YOUR-SITE-ID") {
        Throw "Invoke-PluginPostRunBeacon: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    $envelope = ConvertTo-BeaconHeartbeat -RunResult $RunResult -SiteId $siteId -SourceId $sourceId

    try {
        $apiKey = Get-IDBridgeSecret -Name 'ApiKey-Beacon' -AsPlainText
        $response = Invoke-RestMethod -Uri $ingestUrl -Method Post -Headers @{ 'x-api-key' = $apiKey } `
            -Body ($envelope | ConvertTo-Json -Depth 5 -Compress) -ContentType 'application/json' -TimeoutSec 30
        if ($response.rejected -gt 0) {
            Write-Log -Message "Plugin: Invoke-PluginPostRunBeacon: Beacon rejected the heartbeat (run unaffected): $($response.errors | ConvertTo-Json -Compress)" -Level Warn
        }
        else {
            Write-Log -Message "Plugin: Invoke-PluginPostRunBeacon sent a $($envelope.data.result) heartbeat: $($envelope.data.message)" -Level Trace
        }
    }
    catch {
        Write-Log -Message "Plugin: Invoke-PluginPostRunBeacon send failed (run unaffected): $($_.Exception.GetType().Name)" -Level Warn
    }
}


# The heartbeat envelope Beacon ingests, built from the RunResult alone. Pure: no config,
# no vault, no network — which is what makes it testable without a run.
function ConvertTo-BeaconHeartbeat {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult,

        [Parameter(Mandatory = $true)]
        [string]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$SourceId
    )

    $counts = $RunResult.Counts
    $writeFailures = [int]$counts.Failed

    # Failed when the run threw (a threshold abort, a startup failure, an unhandled write
    # error); Warning when the run finished but a write did not stick; Success otherwise —
    # a ReadOnly run that computed cleanly is a Success, its mode named in the message.
    if (-not $RunResult.Success) {
        $result = 'Failed'
        $error = $RunResult.RunError
        $reason = if ($error) { "$($error.Exception.GetType().Name): $($error.Exception.Message)" } else { 'unknown error' }
        if ($reason.Length -gt 160) { $reason = $reason.Substring(0, 157) + '...' }
        $message = "run failed after $($RunResult.DurationSeconds)s -- $reason"
    }
    else {
        $result = if ($writeFailures -gt 0) { 'Warning' } else { 'Success' }
        $mode = if ($RunResult.ReadOnly) { 'ReadOnly: ' } elseif ($RunResult.TestRun) { 'test run: ' } else { '' }
        $message = "$mode$($counts.Managed) managed: $($counts.Create) created, $($counts.Update) updated, " +
            "$($counts.Deactivate) deactivated, $([int]$counts.GroupAdd + [int]$counts.GroupRemove) group changes, " +
            "$writeFailures write failures, $($RunResult.DurationSeconds)s"
    }

    return [ordered]@{
        siteId      = $SiteId
        sourceType  = 'automation'
        sourceId    = $SourceId
        collectedAt = $RunResult.RunEnd.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        data        = [ordered]@{
            result          = $result
            message         = $message
            moduleVersion   = $RunResult.ModuleVersion
            durationSeconds = $RunResult.DurationSeconds
            readOnly        = [bool]$RunResult.ReadOnly
            testRun         = [bool]$RunResult.TestRun
            managed         = [int]$counts.Managed
            created         = [int]$counts.Create
            updated         = [int]$counts.Update
            deactivated     = [int]$counts.Deactivate
            groupAdds       = [int]$counts.GroupAdd
            groupRemoves    = [int]$counts.GroupRemove
            writeFailures   = $writeFailures
        }
    }
}
