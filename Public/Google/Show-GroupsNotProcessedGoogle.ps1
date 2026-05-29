function Show-GroupsNotProcessedGoogle {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentGoogleGroups,

        [Parameter(Mandatory = $true)]
        $logFile
    )

    foreach ($item in $UserList.GroupsProposed | Select-Object -Unique | Sort-Object) {
        if ($item -notin $CurrentGoogleGroups.name) {
            Write-Log -Path $logFile -Message ("Google: Not Processing Group: $item - Does Not Exist")
        }
    }
}