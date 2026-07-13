<#
.SYNOPSIS
Trace-log the proposed groups that do not exist in the target directory.

.DESCRIPTION
Compares the unique set of proposed group names against the groups present in the target
(AD or Google) and writes one Trace-level log line listing every proposed group with no
match, so group typos or not-yet-created groups surface during a trace run. Read-only;
returns nothing.

.PARAMETER ProposedGroups
The group names proposed across the source records (GroupsProposed). Null or empty allowed.

.PARAMETER TargetGroups
The group names that currently exist in the target directory. Null or empty allowed.

.PARAMETER Directory
Which directory the target groups came from (AD or Google); prefixes the log line so the
same message is self-identifying.

.EXAMPLE
Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $adData.Groups -Directory 'AD'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-13
#>
function Show-GroupsNotProcessed {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $ProposedGroups,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        $TargetGroups,

        [Parameter(Mandatory = $true)]
        [ValidateSet("AD", "Google")]
        [string]$Directory
    )

    $missingGroups = @($ProposedGroups | Select-Object -Unique | Where-Object { $_ -notin $TargetGroups } | Sort-Object)

    if ($missingGroups.Count -gt 0) {
        Write-Log -Message ("$($Directory): $($missingGroups.Count) proposed group(s) do not exist in the target directory (not processed): " + ($missingGroups -join ', ')) -Level Trace
    }
}