function Show-GroupsNotProcessedAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADGroups,

        [Parameter(Mandatory = $true)]
        $logFile
    )

    foreach ($item in $UserList.GroupsProposed | Select-Object -Unique | Sort-Object) {
        if ($item -notin $CurrentADGroups) {
            Write-Log -Path $logFile -Message ("AD: Not Processing Group: $item - Does Not Exist")
        }
    }
}