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