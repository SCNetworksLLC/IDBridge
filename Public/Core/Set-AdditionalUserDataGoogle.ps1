<#
.SYNOPSIS
    Adds or updates Google Workspace-related properties on a user object.

.DESCRIPTION
    Checks for duplicate Google users by UPN and flags them. If not a duplicate, looks up the user in the provided Google users collection by external ID.
    Adds the Google user ID, suspended status, and current group memberships to the user object as properties.
    Logs an error if a duplicate is found.

.PARAMETER userObject
    (Required) The user object to which Google Workspace properties will be added or updated.

.PARAMETER googleUsers
    (Required) The collection of Google Workspace user objects for lookup.

.PARAMETER duplicateGoogleUsers
    The collection of Google users identified as having duplicate UPNs.

.PARAMETER logFile
    (Required) The path to the log file for error and process logging.

.OUTPUTS
    The input userObject, with additional Google Workspace-related properties.

.EXAMPLE
    $user = Set-AdditionalUserDataGoogle -userObject $user -googleUsers $googleUsers -duplicateGoogleUsers $duplicateGoogleUsers -logFile $logFile

.NOTES
    Author: Sam Cattanach
    Intended for internal use within the IDBridge workflow.
#>

function Set-AdditionalUserDataGoogle {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $userObject,
        [Parameter(Mandatory = $true)]
        $googleUsers,
        $duplicateGoogleUsers,
        [Parameter(Mandatory = $true)]
        $logFile
    )

    #Add identifier if duplicate users exist in Google with the same externalID
    if ($userObject.UPN -in $duplicateGoogleUsers.UPN) {
        Write-Log -Path $logFile -Message ("Google: User with UPN: " + $userObject.UPN + " has a duplicate externalID with another user.") -Level Error
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleDuplicateIDStatus -Value "DUPLICATE_ID" -Force
    }

    #Add Google User ID and Google User Suspended Status if available - skip duplicate IDs
    if (!($userObject.GoogleDuplicateIDStatus)) {
        $googleUser = $googleUsers | Where-Object {$_.externalIDs.value -eq $userObject.personID}

        if ($googleUser) {
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentUserID -Value $googleUser.id -Force
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentUserSuspendedStatus -Value $googleUser.suspended -Force
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentGroups -Value $googleUser.CurrentGroups -Force
        } else {
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentUserID -Value $null -Force
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentUserSuspendedStatus -Value $null -Force
            $userObject | Add-Member -MemberType NoteProperty -Name GoogleCurrentGroups -Value $null -Force
        }
    }

    return $userObject
}