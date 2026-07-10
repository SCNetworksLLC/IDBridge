<#
.SYNOPSIS
Match unlinked source users to existing AD accounts by username and name.

.DESCRIPTION
For each source user without an ADCurrentUserID, looks for an AD account whose SamAccountName
equals the source Username and whose GivenName/Surname also match. A match is returned so the
source record can be linked to (and its EmployeeID set on) that existing account — letting
previously unlinked or deprovisioned accounts be reconciled and, if inactive, deactivated. A
username that matches a different person is logged as an error and skipped.

.PARAMETER UserList
The source records (the in-progress user list).

.PARAMETER CurrentADUsers
All current AD users (from Get-TargetDataAD .Users).

.OUTPUTS
[hashtable] personID -> @{ ID (ObjectGUID); Groups; EnabledStatus; User }.

.EXAMPLE
$matches = Get-ADUsersToSetEmployeeID -UserList $sourceData -CurrentADUsers $adData.Users

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-ADUsersToSetEmployeeID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers
    )

    #Set Users that need EmployeeID set in AD
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name

    $itemUpdateList = @{}

    foreach ($item in $UserList | Where-Object {-not $_.ADCurrentUserID}) {
        if ($item.personID -notin $CurrentADUsers.employeeID){
            if ($item.username -notin $CurrentADUsers.SamAccountName -and $item.IDBActive -eq $false) {
                Write-Log -Message ("AD: No user found with EmployeeID: $($item.personID). Source user is inactive and has no AD account - nothing to reconcile.") -Level Trace
            } else {
                Write-Log -Message ("AD: No user found with EmployeeID: " + $item.personID) -Level Trace
            }

            if ($item.username -in $CurrentADUsers.SamAccountName) {
                $ADUser = $null

                $ADUser = ($CurrentADUsers | Where-Object {$_.SamAccountName -eq $item.username})

                if ($ADUser.Surname -eq $item.NameLast -and $ADUser.GivenName -eq $item.NameFirst) {
                    $itemUpdateList[$item.personID] = [PSCustomObject]@{
                        ID = $ADUser.ObjectGUID
                        Groups = ($ADUser.MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name)
                        EnabledStatus = $ADUser.Enabled
                        User = $ADUser
                    }
                } else {
                    Write-Log -Message ("AD: Username " + $item.username + " for " + $item.personID + " is already taken with a different name of " + $ADUser.GivenName + " " + $ADUser.Surname) -Level Error
                }
            } 
        }
    }

    return $itemUpdateList
}