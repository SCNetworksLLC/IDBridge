<#
.SYNOPSIS
Match unlinked source users to existing AD accounts by username and name.

.DESCRIPTION
For each source user without an ADCurrentUserID, looks for an AD account whose SamAccountName
equals the source Username and whose GivenName/Surname also match. A match is returned so the
source record can be linked to (and its EmployeeID set on) that existing account — letting
previously unlinked or deprovisioned accounts be reconciled and, if inactive, deactivated. A
username that matches a different name is logged as an error and skipped — unless that exact
mismatch was approved via Approve-IDBridgeNameMismatch (persisted in
<DataRoot>\ApprovedNameMismatches.csv), in which case it links; an approval whose recorded
account/name no longer matches the current AD account is logged as a warning and skipped.

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
   Modified: 2026-08-19
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
    #Username has to pair with the first name and last name - unless the mismatch was
    #explicitly approved via Approve-IDBridgeNameMismatch

    $itemUpdateList = @{}

    $approvedMismatches = Get-IDBridgeApprovedNameMismatches

    foreach ($item in $UserList | Where-Object {-not $_.ADCurrentUserID}) {
        if ($item.personID -notin $CurrentADUsers.employeeID){
            #One outcome line per user, logged where the decision is made, so the discovery
            #and its result read together instead of in separate phases
            if ($item.username -in $CurrentADUsers.SamAccountName) {
                $ADUser = $null

                $ADUser = ($CurrentADUsers | Where-Object {$_.SamAccountName -eq $item.username})

                $link = $false

                if ($ADUser.Surname -eq $item.NameLast -and $ADUser.GivenName -eq $item.NameFirst) {
                    Write-Log -Message ("AD: No user with EmployeeID: $($item.personID) - matched existing $($ADUser.UserPrincipalName) by username+name; will link EmployeeID.")
                    $link = $true
                } else {
                    #Name differs - honor a recorded approval only while both sides still match
                    #what was approved; a drifted account name means re-approval is required
                    $approval = $approvedMismatches["AD|$($item.personID)"]

                    if ($approval -and $approval.Account -eq $item.username -and $approval.DirectoryName -eq ($ADUser.GivenName + " " + $ADUser.Surname)) {
                        Write-Log -Message ("AD: No user with EmployeeID: $($item.personID) - matched existing $($ADUser.UserPrincipalName) by username with name mismatch approved on $($approval.ApprovedDate); will link EmployeeID.")
                        $link = $true
                    } elseif ($approval) {
                        Write-Log -Message ("AD: Username " + $item.username + " for " + $item.personID + " has an approval from " + $approval.ApprovedDate + " but the account no longer matches it (approved: " + $approval.Account + " / " + $approval.DirectoryName + ", current: " + $item.username + " / " + $ADUser.GivenName + " " + $ADUser.Surname + ") - not linked; re-approve with Approve-IDBridgeNameMismatch.") -Level Warn
                    } else {
                        Write-Log -Message ("AD: Username " + $item.username + " for " + $item.personID + " is already taken by " + $ADUser.GivenName + " " + $ADUser.Surname + " in AD but source name is " + $item.NameFirst + " " + $item.NameLast + " - not linked.") -Level Error
                    }
                }

                if ($link) {
                    $itemUpdateList[$item.personID] = [PSCustomObject]@{
                        ID = $ADUser.ObjectGUID
                        Groups = ($ADUser.MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name)
                        EnabledStatus = $ADUser.Enabled
                        User = $ADUser
                    }
                }
            } elseif ($item.IDBActive -eq $false) {
                Write-Log -Message ("AD: No user found with EmployeeID: $($item.personID). Source user is inactive and has no AD account - nothing to reconcile.") -Level Trace
            } else {
                Write-Log -Message ("AD: No user found with EmployeeID: $($item.personID) - no username match; treated as new.") -Level Trace
            }
        }
    }

    return $itemUpdateList
}