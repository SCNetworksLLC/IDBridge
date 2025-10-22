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

    $checkGroupsListGoogle = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true}) {
        $checkGroupsListGoogle += $item.GroupsAutomatic

        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
            $checkGroupsListGoogle += ($item.EmailGroups -split ",").trim()
        }
    }

    foreach ($item in $checkGroupsListGoogle | Select-Object -Unique | Sort-Object) {
        if ($item -notin $CurrentGoogleGroups.name) {
            Write-Log -Path $logFile -Message ("Google: Not Processing Group: $item - Does Not Exist")
        }
    }
}