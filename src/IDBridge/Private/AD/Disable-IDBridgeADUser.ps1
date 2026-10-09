<#
.SYNOPSIS
Disable an AD user, stamp it, move it to trash, and optionally strip its groups.

.DESCRIPTION
Disables the account (recording the timestamp in Division, and setting EmployeeID when the account
was matched by name and doesn't carry it yet, so the link persists), moves it to its
ADOrganizationalUnitTrash, and logs its current group memberships. When
GroupRemovalProcessingStatus is $true, also removes the user from all of its current groups —
each removal is recorded as its own GroupRemove write result (Add-IDBridgeWriteResult), and a
failed group is logged and skipped without aborting the rest. A disable or move failure
returns the error record rather than throwing (the caller records it as the Deactivate
write result).

.PARAMETER User
The source record for the user to deactivate (uses ADCurrentUserID, ADObject.EmployeeID,
ADOrganizationalUnitTrash, ADCurrentGroups, and PersonID).

.PARAMETER GroupRemovalProcessingStatus
When $true, remove the user from all current groups as part of deactivation. Invoke-IDBridge passes
$true only when AD enableGroupProcessing and enableGroupProcessingTrash are on, WhatIf is off, and
the user's ProcessGroupsAD is not $false.

.EXAMPLE
Disable-IDBridgeADUser -User $item -GroupRemovalProcessingStatus ($adGroupTrashEnabled -and $item.ProcessGroupsAD -ne $false)

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-10-09
#>
function Disable-IDBridgeADUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        $GroupRemovalProcessingStatus
    )

    #Disable the account
    try {
        Write-Log -Message ("AD: Applying: Disabling account for " + $User.PersonID)
        $disableSplat = @{
            Identity = $User.ADCurrentUserID
            Division = (Get-Date -format yyyy-MM-dd-HH:mm)
            Enabled  = $false
        }

        #Persist the EmployeeID link on accounts matched by name - the update list only covers active users, so without this the account is re-matched every run
        if ($User.ADObject.EmployeeID -ne $User.PersonID) {
            $disableSplat['EmployeeID'] = $User.PersonID
        }

        Set-ADUser @disableSplat
    }
    catch {
        return $_
    }

    #Move the User to the Trash OU
    try {
        Write-Log -Message ("AD: Applying: Moving user to trash: " + $User.PersonID)
        Move-ADObject -Identity $User.ADCurrentUserID -TargetPath $User.ADOrganizationalUnitTrash
    }
    catch {
        return $_
    }

    #Get all the groups and write that to the log
    if (-not [string]::IsNullOrEmpty($User.ADCurrentGroups)) {
        Write-Log -Message ("AD: Current groups for " + $User.PersonID + ": " + ($User.ADCurrentGroups -join ", "))

        if ($GroupRemovalProcessingStatus -eq $true) {
            Write-Log -Message  ("AD: Applying: Removing groups for " + $User.PersonID)
            #Per group so each removal gets its own write result and one bad group doesn't
            #abort the rest (the account is already disabled and trashed at this point).
            foreach ($group in $User.ADCurrentGroups) {
                try {
                    Remove-ADGroupMember -Identity $group -Members $User.ADCurrentUserID -Confirm:$false -ErrorAction Stop
                    Add-IDBridgeWriteResult -Directory AD -Action GroupRemove -PersonID $User.PersonID -Target $group -Success $true
                }
                catch {
                    Write-Log -Message ("AD: Error removing group " + $group + " for " + $User.PersonID) -Level Error
                    Add-IDBridgeWriteResult -Directory AD -Action GroupRemove -PersonID $User.PersonID -Target $group -Success $false -ErrorMessage $_.Exception.Message
                }
            }
        } else {
            Write-Log -Message ("AD: Group removal processing is disabled for " + $User.PersonID + ". <No Action Taken>")
        }
    } else {
        Write-Log -Message ("AD: Current groups for " + $User.PersonID + " : NONE")
    }
}