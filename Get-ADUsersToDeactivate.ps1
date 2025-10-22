function Get-ADUsersToDeactivate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $false -and $_.ADCurrentUserEnabledStatus -eq $true}) {
        $itemList += $item

        Write-Log -Path $logFile -Message ("AD: Marking user: $($item.PersonID) for deactivation.")

        if ($item.ADCurrentGroups) {
            Write-Log -Path $logFile -Message ("AD: Current groups for " + $item.PersonID)
            Write-Log -Path $logFile -Message ($item.ADCurrentGroups -join ",")
        }
    }

    return $itemList
}