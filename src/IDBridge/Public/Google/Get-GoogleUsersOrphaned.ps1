<#
.SYNOPSIS
Find Google users that are absent from the source data (orphans).

.DESCRIPTION
Builds a lookup of linked GoogleCurrentUserIDs from the source records and returns each Google user
whose id is not present — i.e. accounts that exist in Google but no longer have a matching source
record. Each orphan is returned with the supplied trash OU for optional cleanup. Not called by the
main pipeline; available for orphan handling.

.PARAMETER UserList
The enriched source records (linked users provide GoogleCurrentUserID).

.PARAMETER GoogleUsers
All current Google users to scan for orphans.

.PARAMETER TrashOU
The trash OU path to record on each orphan for a later move.

.OUTPUTS
[object[]] of @{ GoogleCurrentUserID; GoogleOrganizationalUnitTrash; Groups }.

.EXAMPLE
$orphans = Get-GoogleUsersOrphaned -UserList $sourceData -GoogleUsers $googleData.Users -TrashOU $trashOU

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
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