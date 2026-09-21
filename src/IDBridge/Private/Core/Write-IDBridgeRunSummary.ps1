<#
.SYNOPSIS
Write the end-of-run summary file (Data\LastRun.json) a reader on the box can consume.

.DESCRIPTION
Called from the finally block of Invoke-IDBridge after telemetry and before the PostRun
plugins, on every run that is not a Preview. Replaces <DataRoot>\LastRun.json whole with
the run's counts, mode flags, timing and module version, so a monitor on the same box can
see how the last sync went without reading the log.

The schema is versioned (schemaVersion 1) and grows additively only - a reader typed to
this schema refuses a key it does not know. Counts are APPLIED work, so a ReadOnly run
writes zeros alongside readOnly = true. lastSuccessAt is runEnd on a successful run and
CARRIED FORWARD from the previous file on a failed one (empty when there has never been
one) - the one field a single run cannot supply. A failed run contributes only the
exception CLASS name and the throwing FUNCTION name, never the message, which can contain
UPNs/DNs; no name, id, UPN, DN or group name is ever written.

The reader is SC Networks' Beacon collector on the same box where a district runs Beacon;
nothing here leaves the machine by IDBridge's doing (see PRIVACY.md). The write is
self-contained: a failure logs a Warn and never affects the run.

.PARAMETER RunResult
The run report built in the finally block of Invoke-IDBridge.

.OUTPUTS
None. Side effects: one file write and log output.

.EXAMPLE
Write-IDBridgeRunSummary -RunResult $runResult

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-09-21
#>
function Write-IDBridgeRunSummary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    $IDConfig = Get-IDBridgeConfig

    $path = "$($IDConfig.Paths.DataRoot)\LastRun.json"

    #region Carry Forward
    # A failed run has no success time of its own, so the previous file's survives it - a
    # reader can tell a sync that just broke from one that has been broken for a week. No
    # previous file, or one that won't parse, means no known success.
    $previousSuccessAt = ''
    if (Test-Path $path) {
        try {
            $previous = Get-Content -Path $path -Raw | ConvertFrom-Json
            # ConvertFrom-Json turns the ISO-8601 stamp back into a [datetime]; it goes out
            # again the way it was written.
            $previousSuccessAt = if ($previous.lastSuccessAt -is [datetime]) {
                $previous.lastSuccessAt.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            }
            else { "$($previous.lastSuccessAt)" }
        }
        catch {
            Write-Log -Message "Run summary: Previous $path unreadable ($($_.Exception.GetType().Name)) - no carried-forward success time." -Level Trace
        }
    }
    #endregion Carry Forward

    #region Build Payload
    $directories = @(
        if ($IDConfig.AD.enabled -eq $true) { 'AD' }
        if ($IDConfig.Google.enabled -eq $true) { 'Google' }
    ) -join '+'
    if (-not $directories) { $directories = 'None' }

    $success = [bool]$RunResult.Success
    $runEnd = $RunResult.RunEnd.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")

    $payload = [ordered]@{
        schemaVersion     = 1
        moduleVersion     = "$($MyInvocation.MyCommand.Module.Version)"
        runStart          = $RunResult.RunStart.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        runEnd            = $runEnd
        durationSeconds   = [int]$RunResult.DurationSeconds
        success           = $success
        readOnly          = [bool]$RunResult.ReadOnly
        testRun           = [bool]$RunResult.TestRun
        directories       = $directories
        managed           = [int]$RunResult.Counts.Managed
        created           = [int]$RunResult.Counts.Create
        updated           = [int]$RunResult.Counts.Update
        deactivated       = [int]$RunResult.Counts.Deactivate
        groupAdds         = [int]$RunResult.Counts.GroupAdd
        groupRemoves      = [int]$RunResult.Counts.GroupRemove
        writeFailures     = [int]$RunResult.Counts.Failed
        thresholdExceeded = [bool](@($RunResult.ThresholdResults).Where({ $null -ne $_ -and $_.Exceeded }).Count -gt 0)
        errorType         = ''
        errorFunction     = ''
        lastSuccessAt     = if ($success) { $runEnd } else { $previousSuccessAt }
    }

    if ($RunResult.RunError) {
        # Exception CLASS and FUNCTION name only - message text can contain UPNs/DNs and never leaves the box.
        $payload.errorType = $RunResult.RunError.Exception.GetType().Name

        $errorFunction = "$($RunResult.RunError.InvocationInfo.MyCommand)"
        if (-not $errorFunction -and $RunResult.RunError.ScriptStackTrace) {
            # A Throw statement has no MyCommand; take the function name from the first stack
            # frame ("at Function-Name, <file>: line N") and drop the file path after the comma.
            $errorFunction = ($RunResult.RunError.ScriptStackTrace -split "`n")[0] -replace '^at ', '' -replace ',.*$', ''
        }
        $payload.errorFunction = $errorFunction
    }
    #endregion Build Payload

    #region Write
    try {
        # -ErrorAction Stop so an unwritable Data directory reaches the catch below instead
        # of the error stream: the run is over and nothing here is worth failing it for.
        $payload | ConvertTo-Json -Depth 3 | Set-Content -Path $path -Encoding utf8 -ErrorAction Stop
        Write-Log -Message "Run summary: Wrote $path" -Level Trace
    }
    catch {
        Write-Log -Message "Run summary: Write failed (non-fatal, run unaffected): $($_.Exception.GetType().Name)" -Level Warn
    }
    #endregion Write
}
