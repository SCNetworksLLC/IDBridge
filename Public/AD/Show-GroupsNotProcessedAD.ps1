function Show-GroupsNotProcessedAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADGroups,

        [Parameter(Mandatory = $true)]
        $logFile,

        $WhatIfLogging = $false
    )

    $checkGroupsListAD = @()

    foreach ($item in $userList | Where-Object {$_.IDBActive -eq $true}) {
        $checkGroupsListAD += $item.GroupsAutomatic

        if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {
            $checkGroupsListAD += ($item.ApplicationGroups -split ",").trim()
        }
        
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
            $checkGroupsListAD += ($item.EmailGroups -split ",").trim()
        }  
    }

    foreach ($item in $checkGroupsListAD | Select-Object -Unique | Sort-Object) {
        if ($item -notin $CurrentADGroups) {
            Write-Log -Path $logFile -Message ("AD: Not Processing Group: $item - Does Not Exist") -WhatIfLogging $WhatIfLogging
        }
    }
}