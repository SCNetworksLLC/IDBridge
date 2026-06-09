function Get-GoogleUsersOrphaned {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject[]]$UserList,

        [Parameter(Mandatory = $true)]
        [PSObject[]]$GoogleUsers,

        [Parameter(Mandatory = $true)]
        [string]$TrashOU
    )

    #Create lookup table of UserList by GoogleCurrentUserID for faster searching
    $userListLookupByID = @{}
    foreach ($item in $UserList | Where-Object {$_.GoogleCurrentUserID}) {
        $userListLookupByID[$item.GoogleCurrentUserID] = $item.GoogleCurrentUserID
    }

    #$orphanedUsers = $GoogleUsers | Where-Object {$_.id -notin $userListLookupByID.Keys}

    $orphanedUsers = foreach ($item in $GoogleUsers | Where-Object {$_.id -notin $userListLookupByID.Keys}) {
        Write-Log -Message "Orphaned User Found in Google: $($item.primaryEmail) (ID: $($item.id))"

        [PSCustomObject]@{
            GoogleCurrentUserID             = $item.id
            GoogleOrganizationalUnitTrash   = $TrashOU
            Groups                          = $item.CurrentGroups
        }
    }

    return $orphanedUsers
}