<#
.SYNOPSIS
Compute the AD update, rename, and move lists for linked, active users.

.DESCRIPTION
For each active, AD-provisioned source user linked to an AD account, diffs the desired state
against the current AD user and produces three lists: an UpdateList of Set-ADUser splats for
changed attributes (username/UPN, EmployeeID/Number, name fields, office/title/company/department,
optional Description/OfficePhone/Email, passwordNeverExpires, enabled state including ForceDisable,
and EmployeeType/extensionAttributes); a RenameList when the CN differs from "First Last PersonID";
and a MoveList when the user is in the wrong OU. Name comparisons are case-sensitive so a casing
fix from the plugin is applied. A username change that collides with a different existing account
is logged and skipped.

.PARAMETER UserList
The enriched source records.

.PARAMETER LookupByID
The AD LookupByID hashtable (EmployeeID -> AD user) from Get-TargetDataAD.

.PARAMETER CurrentADUsers
All current AD users (from Get-TargetDataAD .Users); used for the username/UPN collision
check on renames — a new username or UPN already held by a different account skips the user.

.OUTPUTS
[pscustomobject] @{ UpdateList; RenameList; MoveList }.

.EXAMPLE
$toUpdate = Get-ADUsersToUpdate -UserList $sourceData -LookupByID $adData.LookupByID

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-ADUsersToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $LookupByID,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers
    )

    $itemUpdateList = @()
    $itemRenameList = @()
    $itemMoveList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionAD -eq $true -and $_.ADCurrentUserID}) {
        $ADUser = $null
        $ADUser = $LookupByID[$item.personID]

        $itemUpdateSplat = @{}

        if ($ADUser.SamAccountName -ne $item.Username) {
            #Check the target-data snapshot for a DIFFERENT account already holding the new
            #username or UPN (mirrors the primaryEmail collision check in Get-GoogleUsersToUpdate).
            #Excluding the user's own ObjectGUID matters when only the SamAccountName changes:
            #the unchanged UPN would otherwise match the user's own account.
            $conflictUser = $CurrentADUsers | Where-Object { ($_.SamAccountName -eq $item.Username -or $_.UserPrincipalName -eq $item.UPN) -and $_.ObjectGUID -ne $ADUser.ObjectGUID } | Select-Object -First 1

            if ($conflictUser) {
                Write-Log -Message ("AD: Another user account (" + $conflictUser.UserPrincipalName + ") has the username of " + $item.Username + ". Terminating updating person: " + $item.PersonID) -Level Error

                continue
            }

            Write-Log -Message ("AD: New Username found for " + $item.PersonID + ". Old username is " + $ADUser.SamAccountName + ". New username is " + $item.Username + ".")

            $itemUpdateSplat["SamAccountName"] = $item.Username
            $itemUpdateSplat["UserPrincipalName"] = $item.UPN
        }

        if ($ADUser.EmployeeID -ne $item.PersonID) {
            $itemUpdateSplat["EmployeeID"] = $item.PersonID
        }

        if ($item.InternalID -and $ADUser.EmployeeNumber -ne $item.InternalID) {
            $itemUpdateSplat["EmployeeNumber"] = $item.InternalID
        }

        # Names compare case-sensitively (-cne) so a casing fix from the plugin (e.g. ALL-CAPS ->
        # Title-Case) is applied, not just content changes.
        if ($ADUser.Surname -cne $item.NameLast.trim()) {
            $itemUpdateSplat["Surname"] = $item.NameLast.trim()
        }

        if ($ADUser.GivenName -cne $item.NameFirst.trim()) {
            $itemUpdateSplat["GivenName"] = $item.NameFirst.trim()
        }

        if ($ADUser.DisplayName -cne ($item.NameFirst.trim() + " " + $item.NameLast.trim())) {
            $itemUpdateSplat["DisplayName"] = ($item.NameFirst.trim() + " " + $item.NameLast.trim())
        }

        if ($ADUser.physicalDeliveryOfficeName -ne $item.Building) {
            $itemUpdateSplat["Office"] = $item.Building
        }

        if ($ADUser.title -ne $item.JobTitle) {
            $itemUpdateSplat["Title"] = $item.JobTitle
        }

        if ($ADUser.company -ne $item.company) {
            $itemUpdateSplat["Company"] = $item.company
        }

        if ($ADUser.Department -ne $item.Department) {
            $itemUpdateSplat["Department"] = $item.Department
        }

        #Optional attributes - set-but-don't-clear (only push when the record provides a value)
        if ($item.Description -and $ADUser.Description -ne $item.Description) {
            $itemUpdateSplat["Description"] = $item.Description
        }

        if ($item.TelephoneNumber -and $ADUser.OfficePhone -ne $item.TelephoneNumber) {
            $itemUpdateSplat["OfficePhone"] = $item.TelephoneNumber
        }

        if ($item.EmailAddress -and $ADUser.EmailAddress -ne $item.EmailAddress) {
            $itemUpdateSplat["EmailAddress"] = $item.EmailAddress
        }

        if ($ADUser.PasswordNeverExpires -ne $item.PasswordNeverExpires) {
            $itemUpdateSplat["PasswordNeverExpires"] = $item.PasswordNeverExpires
        }

        if ($ADUser.Enabled -ne $true) {
            $itemUpdateSplat["Enabled"] = $true
        }

        if ($item.ForceDisable -eq "TRUE") {
            $itemUpdateSplat["Enabled"] = $false
        }

        $replace = @{}
        if ($ADUser.EmployeeType -ne $item.PersonTypeID -or $ADUser.extensionAttribute1 -ne $item.PersonTypeID) {
            $replace['EmployeeType'] = $item.PersonTypeID
            $replace['extensionAttribute1'] = $item.PersonTypeID
        }
        if ($item.ExtensionAttribute2 -and $ADUser.extensionAttribute2 -ne $item.ExtensionAttribute2) { $replace['extensionAttribute2'] = $item.ExtensionAttribute2 }
        if ($item.ExtensionAttribute3 -and $ADUser.extensionAttribute3 -ne $item.ExtensionAttribute3) { $replace['extensionAttribute3'] = $item.ExtensionAttribute3 }
        if ($item.ExtensionAttribute4 -and $ADUser.extensionAttribute4 -ne $item.ExtensionAttribute4) { $replace['extensionAttribute4'] = $item.ExtensionAttribute4 }
        if ($replace.Count -gt 0) {
            $itemUpdateSplat["Replace"] = $replace
        }

        if ($itemUpdateSplat.Count -gt 0) {
            $itemUpdateSplat["Identity"] = $item.ADCurrentUserID
            $itemUpdateSplat["Division"] = (Get-Date -format yyyy-MM-dd-HH:mm)

            Write-Log -Message ("AD: Proposed: Update User: " + $item.UPN + " - " + $item.personID + " Properties: " + ($itemUpdateSplat | ConvertTo-Json -Compress))

            $itemUpdateList += [PSCustomObject]@{
                CN = $ADUser.CN
                PersonID = $item.PersonID
                Splat = $itemUpdateSplat
            }
        }

        if ($ADUser.CN -cne ($item.NameFirst.trim() + " " + $item.NameLast.trim() + " " + $item.PersonID)) {
            Write-Log -Message ("AD: Proposed: Rename User: " + $item.PersonID + " (Canonical Name does not match).")

            $itemRenameList += [PSCustomObject]@{
                CN = $ADUser.CN
                PersonID = $item.PersonID
                ADUserID = $item.ADCurrentUserID
                NewName = "$($item.NameFirst.trim()) $($item.NameLast.trim()) $($item.PersonID)"
            }
        }

        if ($ADUser.DistinguishedName.split(",",2)[1] -ne $item.ADOrganizationalUnit) {
            Write-Log -Message ("AD: Proposed: Move User: " + $item.PersonID + " (Organization Unit does not match).")

            $itemMoveList += [PSCustomObject]@{
                CN = $ADUser.CN
                PersonID = $item.PersonID
                ADUserID = $item.ADCurrentUserID
                NewOrgUnit = $item.ADOrganizationalUnit
            }
        }
    }

    return [PSCustomObject]@{
        UpdateList = $itemUpdateList
        RenameList = $itemRenameList
        MoveList = $itemMoveList
    }
}