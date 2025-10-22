function Get-ADUsersToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsersLookupByID,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemUpdateList = @()
    $itemRenameList = @()
    $itemMoveList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ADCurrentUserID}) {
        $ADUser = $null
        $ADUser = $CurrentADUsersLookupByID[$item.personID]

        $itemUpdateSplat = @{}

        if ($ADUser.SamAccountName -ne $item.Username) {
            try {
                Get-ADUser -Identity $item.UPN -ErrorAction Stop | Out-Null

                Write-Log -Path $logFile -Message ("AD: Another user account has the username of " + $item.Username + ". Terminating updating person: " + $item.PersonID) -Level Error

                continue
            }
            catch {
                if ($_.CategoryInfo.Reason -eq 'ADIdentityNotFoundException') {
                    Write-Log -Path $logFile -Message ("AD: New Username for " + $item.PersonID + ". Old username is " + $ADUser.SamAccountName)

                    $itemUpdateSplat["SamAccountName"] = $item.Username
                    $itemUpdateSplat["UserPrincipalName"] = $item.UPN
                }
            }
        }

        if ($ADUser.EmployeeID -ne $item.PersonID) {
            $itemUpdateSplat["EmployeeID"] = $item.PersonID
        }

        if ($ADUser.Surname -ne $item.NameLast.trim()) {
            $itemUpdateSplat["Surname"] = $item.NameLast.trim()
        }

        if ($ADUser.GivenName -ne $item.NameFirst.trim()) {
            $itemUpdateSplat["GivenName"] = $item.NameFirst.trim()
        }

        if ($ADUser.DisplayName -ne ($item.NameFirst.trim() + " " + $item.NameLast.trim())) {
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

        if ($ADUser.Enabled -ne $true) {
            $itemUpdateSplat["Enabled"] = $true
        }

        if ($ADUser.EmployeeType -ne $item.PersonTypeID -or $ADUser.extensionAttribute1 -ne $item.PersonTypeID) {
            $itemUpdateSplat["Replace"] = @{ 'EmployeeType' = ($item.PersonTypeID) ; 'extensionAttribute1' = ($item.PersonTypeID)}
        }

        if ($itemUpdateSplat.Count -gt 0) {
            $itemUpdateSplat["Identity"] = $item.ADCurrentUserID
            $itemUpdateSplat["Division"] = (Get-Date -format yyyy-MM-dd-HH:mm)

            Write-Log -Path $logFile -Message ("AD: Information that needs updating for: " + $item.UPN + " - " + $item.personID)
            Write-Log -Path $logFile -Message ($itemUpdateSplat | ConvertTo-Json -Compress)

            $itemUpdateList += $itemUpdateSplat
        }

        if ($ADUser.CN -ne ($item.NameFirst.trim() + " " + $item.NameLast.trim() + " " + $item.PersonID)) {
            Write-Log -Path $logFile -Message ("AD: Canonical Name does not match for " + $item.PersonID + ".")

            $itemRenameList += [PSCustomObject]@{
                ADCurrentUserID = $item.ADCurrentUserID
                NewName = "$($item.NameFirst.trim()) $($item.NameLast.trim()) $($item.PersonID)"
            }
        }

        if ($ADUser.DistinguishedName.split(",",2)[1] -ne $item.ADOrganizationalUnit) {
            Write-Log -Path $logFile -Message ("AD: Organization Unit does not match for " + $item.PersonID + ".")

            $itemMoveList += [PSCustomObject]@{
                ADCurrentUserID = $item.ADCurrentUserID
                NewOrgUnit = $item.ADOrganizationalUnit
            }
        }
    }

    return [PSCustomObject]@{
        UpdateList = $itemUpdateList
        MoveList = $itemMoveList
        RenameList = $itemRenameList
    }
}