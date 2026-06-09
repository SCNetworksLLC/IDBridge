function Show-GroupsNotProcessedAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADGroups
    )

    foreach ($item in $UserList.GroupsProposed | Select-Object -Unique | Sort-Object) {
        if ($item -notin $CurrentADGroups) {
            Write-Log -Message ("AD: Not Processing Group: $item - Does Not Exist")
        }
    }
}