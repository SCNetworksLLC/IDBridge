<#
.SYNOPSIS
Trace-log any proposed group that does not exist in the target directory.

.DESCRIPTION
Compares the unique set of proposed group names against the groups present in the target
(AD or Google) and writes a Trace-level log line for each proposed group with no match, so
group typos or not-yet-created groups surface during a trace run. Read-only; returns nothing.

.PARAMETER ProposedGroups
The group names proposed across the source records (GroupsProposed). Null or empty allowed.

.PARAMETER TargetGroups
The group names that currently exist in the target directory. Null or empty allowed.

.EXAMPLE
Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $adData.Groups

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
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
        $TargetGroups
    )

    foreach ($item in $ProposedGroups | Select-Object -Unique | Sort-Object) {
        if ($item -notin $TargetGroups) {
            Write-Log -Message ("Not Processing Group: $item - Does Not Exist") -Level Trace
        }
    }
}