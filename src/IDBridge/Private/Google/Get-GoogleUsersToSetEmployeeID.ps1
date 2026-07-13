<#
.SYNOPSIS
Match unlinked source users to existing Google accounts by primary email and name.

.DESCRIPTION
For each source user without a GoogleCurrentUserID, looks for a Google user whose primaryEmail
equals the source UPN and whose given/family name match. A match is returned so the source record
can be linked to (and its externalId set on) that existing account — letting unlinked or
deprovisioned accounts be reconciled and, if inactive, deactivated. A primaryEmail that matches a
different person is logged as an error and skipped.

.PARAMETER UserList
The source records (the in-progress user list).

.PARAMETER GoogleUsers
All current Google users (from Get-TargetDataGoogle .Users).

.OUTPUTS
[hashtable] personID -> @{ ID; Groups; SuspendedStatus; User }.

.EXAMPLE
$matches = Get-GoogleUsersToSetEmployeeID -UserList $sourceData -GoogleUsers $googleData.Users

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleUsersToSetEmployeeID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $GoogleUsers
    )

    #Set Users that need EmployeeID set in Google
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name

    $itemUpdateList = @{}

    foreach ($item in $UserList | Where-Object {-not $_.GoogleCurrentUserID}) {
        $googleUser = $null

        if ($item.UPN -notin $GoogleUsers.primaryEmail -and $item.IDBActive -eq $false) {
            Write-Log -Message ("Google: No user found with EmployeeID: $($item.personID). Source user is inactive and has no Google account - nothing to reconcile.") -Level Trace
        } else {
            Write-Log -Message ("Google: No user found with EmployeeID: " + $item.personID) -Level Trace
        }

        if ($item.UPN -in $GoogleUsers.primaryEmail) {
            $googleUser = ($GoogleUsers | Where-Object {$_.primaryEmail -eq $item.UPN})

            if ($googleUser.Name.familyName -eq $item.NameLast -and $googleUser.Name.givenName -eq $item.NameFirst) {
                $itemUpdateList[$item.personID] = [PSCustomObject]@{
                    ID = $googleUser.ID
                    Groups = $googleUser.CurrentGroups
                    SuspendedStatus = ($googleUser.Suspended -or $googleUser.Archived)
                    User = $googleUser
                }
            } else {
                Write-Log -Message ("Google: Username: " + $item.UPN + " for " + $item.personID + " is already taken with a different name of " + $googleUser.Name.givenName + " " + $googleUser.Name.familyName) -Level Error
            }
        }
    }

    return $itemUpdateList
}