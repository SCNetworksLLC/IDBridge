<#
.SYNOPSIS
    Adds or updates Active Directory-related properties on a user object.

.DESCRIPTION
    Checks for duplicate Active Directory users by UPN and flags them. If not a duplicate, looks up the user in the provided AD users collection by UPN.
    Adds the AD user GUID, enabled status, and current group memberships to the user object as properties.
    Logs an error if a duplicate is found.

.PARAMETER userObject
    (Required) The user object to which Active Directory properties will be added or updated.

.PARAMETER ADUsers
    (Required) [hashtable] The collection of Active Directory user objects for lookup. Key must be the Employee ID.

.PARAMETER duplicateADUsers
    The collection of AD users identified as having duplicate UPNs.

.PARAMETER logFile
    (Required) The path to the log file for error and process logging.

.OUTPUTS
    The input userObject, with additional Active Directory-related properties.

.EXAMPLE
    $user = Set-AdditionalUserDataAD -userObject $user -ADUsers $ADUsers -duplicateADUsers $duplicateADUsers -logFile $logFile

.NOTES
    Author: Sam Cattanach
    Intended for internal use within the IDBridge workflow.
#>

function Set-AdditionalUserDataAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $userObject,
        [Parameter(Mandatory = $true)]
        [hashtable]$ADUsers,
        $duplicateADUsers,
        [Parameter(Mandatory = $true)]
        $logFile
    )

    #Add identifier if duplicate users exist in AD with the same employeeID
    if ($userObject.UPN -in $duplicateADUsers.UserPrincipalName) {
        Write-Log -Path $logFile -Message ("AD: User with UPN: " + $userObject.UPN + " has a duplicate employeeID with another user.") -Level Error
        $userObject.ADDuplicateIDStatus = "DUPLICATE_ID"
    }

    #Add AD User GUID, Enabled Status, and Current Groups if available - skip duplicate IDs
    if (!($userObject.ADDuplicateIDStatus)) {
        $adUser = $ADUsers[$userObject.personID]

        if ($adUser) {
            $userObject.ADCurrentUserID = $adUser.ObjectGUID
            $userObject.ADCurrentUserEnabledStatus = $adUser.Enabled
            $userObject.ADCurrentGroups = $adUser.CurrentGroups
        } else {
            $userObject.ADCurrentUserID = $null
            $userObject.ADCurrentUserEnabledStatus = $null
            $userObject.ADCurrentGroups = $null
        }
    }

    return $userObject
}