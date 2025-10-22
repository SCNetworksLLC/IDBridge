function Get-ADUsersToCreate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and -not $_.ADCurrentUserID -and $_.UPN -notin $CurrentADUsers.UserPrincipalName}) {
        $itemList += $item

        Write-Log -Path $logFile -Message ("AD: No user found for $($item.PersonID). Adding user to create list.")
    }

    return $itemList
}