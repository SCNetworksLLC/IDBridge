function Get-GoogleUsersToDeactivate {
    param (
        [Parameter(Mandatory = $true)]
        $UserList
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $false -and $_.GoogleCurrentUserSuspendedStatus -eq $false}) {
        Write-Log -Message "Google: Adding User to Process List: Deactivate: $($item.PersonID)"
        $itemList += $item
    }

    return $itemList
}