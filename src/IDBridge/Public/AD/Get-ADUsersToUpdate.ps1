function Get-ADUsersToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $LookupByID
    )

    $itemUpdateList = @()
    $itemRenameList = @()
    $itemMoveList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionAD -eq $true -and $_.ADCurrentUserID}) {
        $ADUser = $null
        $ADUser = $LookupByID[$item.personID]

        $itemUpdateSplat = @{}

        if ($ADUser.SamAccountName -ne $item.Username) {
            try {
                Get-ADUser -Identity $item.UPN -ErrorAction Stop | Out-Null

                Write-Log -Message ("AD: Another user account has the username of " + $item.Username + ". Terminating updating person: " + $item.PersonID) -Level Error

                continue
            }
            catch {
                if ($_.CategoryInfo.Reason -eq 'ADIdentityNotFoundException') {
                    Write-Log -Message ("AD: New Username found for " + $item.PersonID + ". Old username is " + $ADUser.SamAccountName + ". New username is " + $item.Username + ".")

                    $itemUpdateSplat["SamAccountName"] = $item.Username
                    $itemUpdateSplat["UserPrincipalName"] = $item.UPN
                }
            }
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

            Write-Log -Message ("AD: Information that needs updating for: " + $item.UPN + " - " + $item.personID)
            Write-Log -Message ($itemUpdateSplat | ConvertTo-Json -Compress)

            $itemUpdateList += [PSCustomObject]@{
                CN = $ADUser.CN
                Splat = $itemUpdateSplat
            }
        }

        if ($ADUser.CN -cne ($item.NameFirst.trim() + " " + $item.NameLast.trim() + " " + $item.PersonID)) {
            Write-Log -Message ("AD: Canonical Name does not match for " + $item.PersonID + ".")

            $itemRenameList += [PSCustomObject]@{
                CN = $ADUser.CN
                ADUserID = $item.ADCurrentUserID
                NewName = "$($item.NameFirst.trim()) $($item.NameLast.trim()) $($item.PersonID)"
            }
        }

        if ($ADUser.DistinguishedName.split(",",2)[1] -ne $item.ADOrganizationalUnit) {
            Write-Log -Message ("AD: Organization Unit does not match for " + $item.PersonID + ".")

            $itemMoveList += [PSCustomObject]@{
                CN = $ADUser.CN
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