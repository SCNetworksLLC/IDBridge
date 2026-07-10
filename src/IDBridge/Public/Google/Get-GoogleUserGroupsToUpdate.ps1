<#
.SYNOPSIS
Diff proposed vs current Google group membership for active linked users.

.DESCRIPTION
For each active, Google-provisioned, linked user, compares GroupsProposed against
GoogleCurrentGroups and builds an Add list (proposed groups that exist in Google and the user isn't
already in) and a Remove list (current memberships no longer proposed). Membership is compared by
each group's real email from GoogleGroups (a group's email does not always match its name), so a
group named Grade-PK with email studentsgradepk@domain diffs correctly. Adds are limited to groups
present in GoogleGroups.

.PARAMETER UserList
The enriched source records.

.PARAMETER GoogleGroups
The Google groups (null allowed); a proposed group must exist here (by name) to be added.

.OUTPUTS
[pscustomobject] @{ Add; Remove }, each an array of @{ PersonID; GoogleCurrentUserID; Groups }.

.EXAMPLE
$groups = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleUserGroupsToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $GoogleGroups
    )

    $itemListAdd = @()
    $itemListRemove = @()

    #Map group names to emails (and back) so membership is compared by each group's real email
    $groupEmailByName = @{}
    $groupNameByEmail = @{}
    foreach ($group in $GoogleGroups) {
        $groupEmailByName[$group.name] = $group.email
        $groupNameByEmail[$group.email] = $group.name
    }

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionGoogle -eq $true -and $_.GoogleCurrentUserID}) {
        #Create list for adding groups
        $userGroupsAdd = @()

        foreach ($group in $item.GroupsProposed | Where-Object {$groupEmailByName.ContainsKey($_)}) {
            if ($groupEmailByName[$group] -notin $item.GoogleCurrentGroups) {
                $userGroupsAdd += $group
            }
        }

        if ($userGroupsAdd.Count -gt 0) {
            Write-Log -Message "Google: Information that needs updating - Add Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsAdd -join ', ')"
            $itemListAdd += [PSCustomObject]@{
                PersonID = $item.PersonID
                GoogleCurrentUserID = $item.GoogleCurrentUserID
                Groups = $userGroupsAdd
            }
        }

        #Create list for removing groups
        $userGroupsRemove = @()

        foreach ($group in $item.GoogleCurrentGroups) {
            if ($groupNameByEmail[$group] -notin $item.GroupsProposed) {
                $userGroupsRemove += $group
            }
        }

        if ($userGroupsRemove.Count -gt 0) {
            Write-Log -Message "Google: Information that needs updating - Remove Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsRemove -join ', ')"
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