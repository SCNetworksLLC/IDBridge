<#
.SYNOPSIS
Return the in-memory log buffer for the current run.

.DESCRIPTION
Accessor for the script-scoped log list populated by Write-Log. Used by Push-LogsToSheet to
flush the run's entries to a Google Sheet without re-reading the log file. Throws if called
before Initialize-IDBridge has run.

.OUTPUTS
[System.Collections.Generic.List[PSCustomObject]] of @{ Timestamp; Level; Message } entries.

.EXAMPLE
$logs = Get-IDBridgeLogs

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-IDBridgeLogs {
    if ($null -eq $script:Logs) {
        throw "IDBridge is not initialized. Call Initialize-IDBridge first."
    }
    return $script:Logs
}