<#
.SYNOPSIS
Send anonymous usage telemetry for a completed run (see PRIVACY.md).

.DESCRIPTION
Called from the finally block of Invoke-IDBridge after every run. Builds the payload for
the configured tier (Telemetry.Tier, default 'Basic') and POSTs it to the IDBridge Pulse
ingest endpoint, fire-and-forget:

  - Off      — nothing is sent.
  - Basic    (default) — anonymous aggregate counts only. No stable identifier is sent,
               so runs from this install cannot be linked to each other.
  - Enhanced — adds the install's random SiteID (Get-IDBridgeSiteID) so runs form a
               timeline in the Pulse dashboard, plus — on failed runs — the exception
               CLASS name and throwing FUNCTION name. Never the exception message,
               which can contain UPNs/DNs.

No names, usernames, email addresses, person IDs, or directory records are transmitted
at any tier. Counts are APPLIED work, so a ReadOnly run reports zeros alongside
readOnly = true. The exact payload is logged at Trace level, so running with
-TraceLogging shows precisely what leaves the machine.

The send uses a short timeout with NO retries (a retry after a client-side timeout could
double-count a Basic event, which has no identifier to dedupe on) and swallows all
errors, logging locally only — telemetry can never fail, delay, or mask a run.

.PARAMETER Success
Whether the run completed without a fatal error.

.PARAMETER DurationSeconds
Total run duration in seconds.

.PARAMETER ManagedCount
Number of source records processed this run.

.PARAMETER CreateCount
Users created across all enabled directories (0 in ReadOnly).

.PARAMETER UpdateCount
Users updated/renamed/moved across all enabled directories (0 in ReadOnly).

.PARAMETER DeactivateCount
Users deactivated across all enabled directories (0 in ReadOnly).

.PARAMETER GroupAddCount
Group memberships added across all enabled directories (0 in ReadOnly, and a
directory contributes 0 while its group processing is off or in WhatIf).

.PARAMETER GroupRemoveCount
Group memberships removed across all enabled directories (0 in ReadOnly, and a
directory contributes 0 while its group processing is off or in WhatIf).

.PARAMETER WriteFailureCount
Number of individual writes that failed this run (a count only - which users/groups
failed never leaves the machine; see the RunResult Applied list locally).

.PARAMETER RunError
The ErrorRecord of a failed run. Only the exception class name and throwing function
name are extracted from it, and only at the Enhanced tier.

.OUTPUTS
None. Side effects: one HTTP POST (Basic/Enhanced) and log output.

.EXAMPLE
Send-IDBridgeTelemetry -Success $true -DurationSeconds 42 -ManagedCount 1250 -CreateCount 3 -UpdateCount 12 -DeactivateCount 1 -GroupAddCount 5 -GroupRemoveCount 2

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-06
#>
function Send-IDBridgeTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [int]$DurationSeconds = 0,
        [int]$ManagedCount = 0,
        [int]$CreateCount = 0,
        [int]$UpdateCount = 0,
        [int]$DeactivateCount = 0,
        [int]$GroupAddCount = 0,
        [int]$GroupRemoveCount = 0,
        [int]$WriteFailureCount = 0,

        [System.Management.Automation.ErrorRecord]$RunError
    )

    $IDConfig = Get-IDBridgeConfig

    #region Resolve Tier
    # Missing block/key = 'Basic' (the documented default); an unrecognized value fails safe to Off.
    $tier = 'Basic'
    if ($IDConfig.ContainsKey('Telemetry') -and $IDConfig.Telemetry.Tier) {
        $tier = "$($IDConfig.Telemetry.Tier)"
    }

    if ($tier -notin @('Basic', 'Enhanced', 'Off')) {
        Write-Log -Message "Telemetry: Unrecognized Telemetry.Tier value '$tier' - nothing sent. Valid values: Basic, Enhanced, Off." -Level Warn
        return
    }

    if ($tier -eq 'Off') {
        Write-Log -Message "Telemetry: Off - nothing sent." -Level Trace
        return
    }

    Write-Log -Message "Telemetry: $tier tier - sending anonymous aggregate usage counts (no names, usernames, or IDs - see PRIVACY.md). Set Telemetry.Tier = 'Off' or run with -DisableTelemetry to disable."
    #endregion Resolve Tier

    #region Build Payload
    $directories = @(
        if ($IDConfig.AD.enabled -eq $true) { 'AD' }
        if ($IDConfig.Google.enabled -eq $true) { 'Google' }
    ) -join '+'
    if (-not $directories) { $directories = 'None' }

    $payload = @{
        schemaVersion   = 1
        tier            = $tier
        moduleVersion   = "$($MyInvocation.MyCommand.Module.Version)"
        psVersion       = "$($PSVersionTable.PSVersion)"
        success         = $Success
        readOnly        = ($IDConfig.Debug.readOnly -eq $true)
        testRun         = ($IDConfig.Debug.testRun -eq $true)
        directories     = $directories
        managedCount     = $ManagedCount
        createCount      = $CreateCount
        updateCount      = $UpdateCount
        deactivateCount  = $DeactivateCount
        groupAddCount    = $GroupAddCount
        groupRemoveCount = $GroupRemoveCount
        writeFailureCount = $WriteFailureCount
        durationSeconds  = $DurationSeconds
    }

    if ($tier -eq 'Enhanced') {
        $payload.siteID = Get-IDBridgeSiteID

        if ($RunError) {
            # Exception CLASS and FUNCTION name only - message text can contain UPNs/DNs and never leaves the box.
            $payload.errorType = $RunError.Exception.GetType().Name

            $errorFunction = "$($RunError.InvocationInfo.MyCommand)"
            if (-not $errorFunction -and $RunError.ScriptStackTrace) {
                # A Throw statement has no MyCommand; take the function name from the first stack
                # frame ("at Function-Name, <file>: line N") and drop the file path after the comma.
                $errorFunction = ($RunError.ScriptStackTrace -split "`n")[0] -replace '^at ', '' -replace ',.*$', ''
            }
            $payload.errorFunction = $errorFunction
        }
    }

    $payloadJson = $payload | ConvertTo-Json -Compress
    Write-Log -Message "Telemetry: Payload: $payloadJson" -Level Trace
    #endregion Build Payload

    #region Send
    $endpoint = 'https://pulse.scnlabs.net/api/ingest'
    if ($IDConfig.ContainsKey('Telemetry') -and $IDConfig.Telemetry.Endpoint) {
        $endpoint = $IDConfig.Telemetry.Endpoint
    }

    try {
        # 10s accommodates an ingest-backend cold start; 2s was routinely exceeded by the
        # first request after idle. Still one attempt only — see the no-retries note above.
        Invoke-RestMethod -Uri $endpoint -Method Post -Body $payloadJson -ContentType 'application/json' -TimeoutSec 10 | Out-Null
        Write-Log -Message "Telemetry: Sent." -Level Trace
    }
    catch {
        Write-Log -Message "Telemetry: Send failed (non-fatal, run unaffected): $($_.Exception.GetType().Name)" -Level Trace
    }
    #endregion Send
}
