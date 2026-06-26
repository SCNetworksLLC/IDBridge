<#
.SYNOPSIS
Disable an AD user, stamp it, move it to trash, and optionally strip its groups.

.DESCRIPTION
Disables the account (recording the timestamp in Division), moves it to its
ADOrganizationalUnitTrash, and logs its current group memberships. When
GroupRemovalProcessingStatus is $true, also removes the user from all of its current groups;
otherwise the memberships are left in place. On error the error record is returned rather than thrown.

.PARAMETER User
The source record for the user to deactivate (uses ADCurrentUserID, ADOrganizationalUnitTrash,
ADCurrentGroups, and PersonID).

.PARAMETER GroupRemovalProcessingStatus
When $true, remove the user from all current groups as part of deactivation (driven by the AD
enableGroupProcessingTrash setting).

.EXAMPLE
Disable-IDBridgeADUser -User $item -GroupRemovalProcessingStatus $IDConfig.AD.enableGroupProcessingTrash

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
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
        Write-Log -Message ("AD: Disabling account for " + $User.PersonID)
        Set-ADUser -Identity $User.ADCurrentUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm) -Enabled $false
    }
    catch {
        return $_
    }

    #Move the User to the Trash OU
    try {
        Write-Log -Message ("AD: Moving user to trash: " + $User.PersonID)
        Move-ADObject -Identity $User.ADCurrentUserID -TargetPath $User.ADOrganizationalUnitTrash
    }
    catch {
        return $_
    }

    #Get all the groups and write that to the log
    if (-not [string]::IsNullOrEmpty($User.ADCurrentGroups)) {
        Write-Log -Message ("AD: Current groups for " + $User.PersonID)
        Write-Log -Message ($User.ADCurrentGroups -join ",")
        
        if ($GroupRemovalProcessingStatus -eq $true) {
            Write-Log -Message  ("AD: Removing groups for " + $User.PersonID)
            try {
                $User.ADCurrentGroups | Remove-ADGroupMember -Members $User.ADCurrentUserID -Confirm:$false
            }
            catch {
                Write-Log -Message ("AD: Error removing groups for " + $User.PersonID) -Level Error
                return $_
            }
        } else {
            Write-Log -Message ("AD: Group removal processing is disabled for " + $User.PersonID + ". <No Action Taken>")
        }
    } else {
        Write-Log -Message ("AD: Current groups for " + $User.PersonID + " : NONE")
    }
}