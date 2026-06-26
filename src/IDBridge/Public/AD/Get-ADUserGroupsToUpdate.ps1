<#
.SYNOPSIS
Diff proposed vs current AD group membership for active linked users.

.DESCRIPTION
For each active, AD-provisioned, linked user, compares GroupsProposed against ADCurrentGroups and
builds an Add list (proposed groups that exist in AD and the user isn't already in) and a Remove
list (current groups no longer proposed). Adds are limited to groups present in CurrentADGroups.

.PARAMETER UserList
The enriched source records.

.PARAMETER CurrentADGroups
The group names that exist in AD (null allowed); a proposed group must be in this set to be added.

.OUTPUTS
[pscustomobject] @{ Add; Remove }, each an array of @{ PersonID; ADCurrentUserID; Groups }.

.EXAMPLE
$groups = Get-ADUserGroupsToUpdate -UserList $sourceData -CurrentADGroups $adData.Groups

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-ADUserGroupsToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $CurrentADGroups
    )

    $itemListAdd = @()
    $itemListRemove = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionAD -eq $true -and $_.ADCurrentUserID}) {
        #Create list for adding groups
        $userGroupsAdd = @()

        foreach ($groupAdd in $item.GroupsProposed | Where-Object {$_ -in $CurrentADGroups}) {
            if ($groupAdd -notin $item.ADCurrentGroups) {
                $userGroupsAdd += $groupAdd
            }
        }

        if ($userGroupsAdd.Count -gt 0) {
            Write-Log -Message "AD: Information that needs updating - Add Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsAdd -join ', ')"
            $itemListAdd += [PSCustomObject]@{
                PersonID = $item.PersonID
                ADCurrentUserID = $item.ADCurrentUserID
                Groups = $userGroupsAdd
            }
        }

        #Create list for removing groups
        $userGroupsRemove = @()

        foreach ($groupCurrent in $item.ADCurrentGroups) {
            if ($groupCurrent -notin $item.GroupsProposed) {
                $userGroupsRemove += $groupCurrent
            }
        }

        if ($userGroupsRemove.Count -gt 0) {
            Write-Log -Message "AD: Information that needs updating - Remove Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsRemove -join ', ')"
            $itemListRemove += [PSCustomObject]@{
                PersonID = $item.PersonID
                ADCurrentUserID = $item.ADCurrentUserID
                Groups = $userGroupsRemove
            }
        }
    }

    return [PSCustomObject]@{
        Add = $itemListAdd
        Remove = $itemListRemove
    }
}