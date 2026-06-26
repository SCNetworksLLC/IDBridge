<#
.SYNOPSIS
Evaluate a directory's proposed change volume against a safety percentage.

.DESCRIPTION
A pure decision helper run after the AD/Google change lists are computed but before any writes.
It compares the number of proposed lifecycle changes (creates/updates/renames/moves/deactivates)
for a single directory against that directory's existing managed population and reports whether
the change volume exceeds the configured threshold percentage. The caller (Invoke-IDBridge)
decides whether to abort the run; this function only computes, logs, and returns the result.

A population of zero (e.g. a brand-new tenant or an empty managed OU) cannot produce a
meaningful ratio, so the check is skipped (Skipped = $true, Exceeded = $false) and logged as a
Warn rather than tripping the guard.

.PARAMETER Directory
The directory being evaluated ('AD' or 'Google'), used for log context.

.PARAMETER ChangeCount
The total proposed lifecycle changes for the directory.

.PARAMETER PopulationCount
The existing managed user count used as the denominator.

.PARAMETER ThresholdPercent
The maximum allowed change percentage (0-100). A computed percentage greater than this trips the guard.

.EXAMPLE
$result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 30 -PopulationCount 100 -ThresholdPercent 25
if ($result.Exceeded) { Throw "Too many changes." }

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Test-IDBridgeChangeThreshold {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][int]$ChangeCount,
        [Parameter(Mandatory)][int]$PopulationCount,
        [Parameter(Mandatory)][ValidateRange(0, 100)][double]$ThresholdPercent
    )

    # Without an existing population there is no meaningful ratio (fresh tenant / empty managed OU).
    # Skip rather than block a legitimate first run that creates everyone.
    if ($PopulationCount -le 0) {
        Write-Log -Message "${Directory}: Change threshold check skipped - no existing managed users to compare against ($ChangeCount change(s) proposed)." -Level Warn
        return [pscustomobject]@{
            Directory       = $Directory
            ChangeCount     = $ChangeCount
            PopulationCount = $PopulationCount
            Percent         = $null
            Exceeded        = $false
            Skipped         = $true
        }
    }

    $percent = [math]::Round(($ChangeCount / $PopulationCount) * 100, 2)
    $exceeded = $percent -gt $ThresholdPercent

    $level = if ($exceeded) { 'Warn' } else { 'Info' }
    Write-Log -Message "${Directory}: Change threshold - $ChangeCount change(s) across $PopulationCount managed user(s) = $percent% (limit $ThresholdPercent%)." -Level $level

    return [pscustomobject]@{
        Directory       = $Directory
        ChangeCount     = $ChangeCount
        PopulationCount = $PopulationCount
        Percent         = $percent
        Exceeded        = $exceeded
        Skipped         = $false
    }
}
