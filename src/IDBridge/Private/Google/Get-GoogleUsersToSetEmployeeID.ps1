<#
.SYNOPSIS
Match unlinked source users to existing Google accounts by primary email and name.

.DESCRIPTION
For each source user without a GoogleCurrentUserID, looks for a Google user whose primaryEmail
equals the source UPN and whose given/family name match. A match is returned so the source record
can be linked to (and its externalId set on) that existing account — letting unlinked or
deprovisioned accounts be reconciled and, if inactive, deactivated. A primaryEmail that matches a
different name is logged as an error and skipped — unless that exact mismatch was approved via
Approve-IDBridgeNameMismatch (persisted in <DataRoot>\ApprovedNameMismatches.csv), in which case
it links; an approval whose recorded account/name no longer matches the current Google account is
logged as a warning and skipped. A match for a user who is inactive or not Google-provisioned whose
account is already suspended or archived is still returned, but logged at Trace ("nothing to
reconcile") instead of Info: nothing writes the link for it (updates cover active users, the
deactivate step not-yet-deactivated accounts), so it recurs every run.

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
   Modified: 2026-10-09
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
    #Username has to pair with the first name and last name - unless the mismatch was
    #explicitly approved via Approve-IDBridgeNameMismatch

    $itemUpdateList = @{}

    $approvedMismatches = Get-IDBridgeApprovedNameMismatches

    foreach ($item in $UserList | Where-Object {-not $_.GoogleCurrentUserID}) {
        $googleUser = $null

        #One outcome line per user, logged where the decision is made, so the discovery
        #and its result read together instead of in separate phases
        if ($item.UPN -in $GoogleUsers.primaryEmail) {
            $googleUser = ($GoogleUsers | Where-Object {$_.primaryEmail -eq $item.UPN})

            $link = $false
            $matchedBy = $null

            if ($googleUser.Name.familyName -eq $item.NameLast -and $googleUser.Name.givenName -eq $item.NameFirst) {
                $matchedBy = "by username+name"
                $link = $true
            } else {
                #Name differs - honor a recorded approval only while both sides still match
                #what was approved; a drifted account name means re-approval is required
                $approval = $approvedMismatches["Google|$($item.personID)"]

                if ($approval -and $approval.Account -eq $item.UPN -and $approval.DirectoryName -eq ($googleUser.Name.givenName + " " + $googleUser.Name.familyName)) {
                    $matchedBy = "by username with name mismatch approved on $($approval.ApprovedDate)"
                    $link = $true
                } elseif ($approval) {
                    Write-Log -Message ("Google: Username: " + $item.UPN + " for " + $item.personID + " has an approval from " + $approval.ApprovedDate + " but the account no longer matches it (approved: " + $approval.Account + " / " + $approval.DirectoryName + ", current: " + $item.UPN + " / " + $googleUser.Name.givenName + " " + $googleUser.Name.familyName + ") - not linked; re-approve with Approve-IDBridgeNameMismatch.") -Level Warn
                } else {
                    Write-Log -Message ("Google: Username: " + $item.UPN + " for " + $item.personID + " is already taken by " + $googleUser.Name.givenName + " " + $googleUser.Name.familyName + " in Google but source name is " + $item.NameFirst + " " + $item.NameLast + " - not linked.") -Level Error
                }
            }

            if ($link) {
                #Not active in Google and the account is already suspended/archived: neither the update step (active
                #users) nor the deactivate step (not-yet-deactivated accounts) writes the link, so it re-matches every run - Trace, not Info
                if (($item.IDBActive -eq $false -or $item.ProvisionGoogle -eq $false) -and ($googleUser.Suspended -or $googleUser.Archived)) {
                    Write-Log -Message ("Google: No user with EmployeeID: $($item.personID) - matched existing $($googleUser.primaryEmail) $matchedBy, but the source user is inactive or not Google-provisioned and the account is already deactivated - nothing to reconcile.") -Level Trace
                } else {
                    Write-Log -Message ("Google: No user with EmployeeID: $($item.personID) - matched existing $($googleUser.primaryEmail) $matchedBy; will link EmployeeID.")
                }

                $itemUpdateList[$item.personID] = [PSCustomObject]@{
                    ID = $googleUser.ID
                    Groups = $googleUser.CurrentGroups
                    SuspendedStatus = ($googleUser.Suspended -or $googleUser.Archived)
                    User = $googleUser
                }
            }
        } elseif ($item.IDBActive -eq $false) {
            Write-Log -Message ("Google: No user found with EmployeeID: $($item.personID). Source user is inactive and has no Google account - nothing to reconcile.") -Level Trace
        } else {
            Write-Log -Message ("Google: No user found with EmployeeID: $($item.personID) - no username match; treated as new.") -Level Trace
        }
    }

    return $itemUpdateList
}