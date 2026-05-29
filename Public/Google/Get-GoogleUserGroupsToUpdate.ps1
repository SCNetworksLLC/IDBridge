function Get-GoogleUserGroupsToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $GoogleGroups,

        [Parameter(Mandatory = $true)]
        $GroupPrimaryDomainName,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemListAdd = @()
    $itemListRemove = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.GoogleCurrentUserID}) {
        #Create list for adding groups
        $userGroupsAdd = @()

        foreach ($group in $item.GroupsProposed | Where-Object {$_ -in $GoogleGroups.name}) {
            if (("$group@$($GroupPrimaryDomainName)") -notin $item.GoogleCurrentGroups) {
                $userGroupsAdd += $group
            }
        }

        if ($userGroupsAdd.Count -gt 0) {
            Write-Log -Path $logFile -Message "Google: Information that needs updating - Add Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsAdd -join ', ')"
            $itemListAdd += [PSCustomObject]@{
                PersonID = $item.PersonID
                GoogleCurrentUserID = $item.GoogleCurrentUserID
                Groups = $userGroupsAdd
            }
        }

        #Create list for removing groups
        $userGroupsRemove = @()

        foreach ($group in $item.GoogleCurrentGroups) {
            if ($group.Split("@")[0] -notin $item.GroupsProposed) {
                $userGroupsRemove += $group
            }
        }

        if ($userGroupsRemove.Count -gt 0) {
            Write-Log -Path $logFile -Message "Google: Information that needs updating - Remove Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsRemove -join ', ')"
            $itemListRemove += [PSCustomObject]@{
                PersonID = $item.PersonID
                GoogleCurrentUserID = $item.GoogleCurrentUserID
                Groups = $userGroupsRemove
            }
        }
    }

    return [PSCustomObject]@{
        Add = $itemListAdd
        Remove = $itemListRemove
    }
}