function Get-ADUsersToDeactivate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $false -and $_.ADCurrentUserEnabledStatus -eq $true}) {
        $itemList += $item

        Write-Log -Message ("AD: Marking user: $($item.PersonID) for deactivation.")

        if ($item.ADCurrentGroups) {
            Write-Log -Message ("AD: Current groups for " + $item.PersonID)
            Write-Log -Message ($item.ADCurrentGroups -join ",")
        }
    }

    return $itemList
}