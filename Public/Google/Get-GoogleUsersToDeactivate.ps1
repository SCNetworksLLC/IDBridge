function Get-GoogleUsersToDeactivate {
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $false -and $_.GoogleCurrentUserSuspendedStatus -eq $false}) {
        Write-Log -Path $logFile -Message "Google: Adding User to Process List: Deactivate: $($item.PersonID)"
        $itemList += $item
    }

    return $itemList
}