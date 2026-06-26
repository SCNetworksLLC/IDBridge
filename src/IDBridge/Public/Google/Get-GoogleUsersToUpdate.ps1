function Get-GoogleUsersToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $LookupByID,

        [Parameter(Mandatory = $true)]
        $GoogleUsers
    )

    $itemUpdateList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionGoogle -eq $true -and $_.GoogleCurrentUserID}) {
        $googleUser = $null
        $googleUser = $LookupByID[$item.personID]

        $itemUpdateSplat = @{}

        if ($googleUser.primaryEmail -ne $item.UPN) {
            if ($item.UPN -notin $GoogleUsers.PrimaryEmail) {

                $itemUpdateSplat["PrimaryEmail"] = $item.UPN

                if ($item.UPN -in ($GoogleUsers.emails | Select-Object -ExpandProperty address)) {
                    $aliasUser = $GoogleUsers | Where-Object {$item.UPN -in ($_.emails | Select-Object -ExpandProperty address)}
                    $itemUpdateSplat["RemoveAlias"] = $item.UPN
                    Write-Log -Message ("Google: User: $($item.personID) with new UPN: $($item.UPN). New UPN already in use as Alias, will remove alias from $($aliasUser.primaryEmail).") -Level Warn
                }
            } else {
                Write-Log -Message ("Google: User: $($item.personID) with new UPN: $($item.UPN). New UPN already in use.") -Level Error
                continue
            }
        }

        if ($item.PersonID -notin $googleUser.ExternalIDs.value) {
            $itemUpdateSplat["PersonID"] = $item.PersonID
        }

        # Names compare case-sensitively (-cne) so a casing fix from the plugin is applied.
        if ($googleUser.Name.givenName -cne $item.NameFirst -or $googleUser.Name.familyName -cne $item.NameLast) {
            $itemUpdateSplat["FirstName"] = $item.NameFirst.trim()
            $itemUpdateSplat["LastName"] = $item.NameLast.trim()
        }

        if ($googleUser.organizations.department -ne $item.Building -or $googleUser.organizations.title -ne $item.JobTitle) {
            $itemUpdateSplat["Building"] = $item.Building.trim()
            $itemUpdateSplat["JobTitle"] = $item.JobTitle.trim()
        }

        if ($googleUser.suspended -ne $false) {
            $itemUpdateSplat["Suspended"] = 'false'
        }

        if ($item.ForceDisable -eq "TRUE") {
            $itemUpdateSplat["Suspended"] = 'true'
        }

        if ($googleUser.orgUnitPath -ne $item.GoogleOrganizationalUnit -and $item.GoogleOUOverride -ne "TRUE") {
            $itemUpdateSplat["OrgUnitPath"] = $item.GoogleOrganizationalUnit
        }

        #Update the user account information if needed
        if ($itemUpdateSplat.Count -gt 0) {
            $itemUpdateSplat["GoogleUserID"] = $item.GoogleCurrentUserID

            Write-Log -Message ("Google: Information that needs updating for: " + $item.UPN + " - " + $item.personID)
            Write-Log -Message ($itemUpdateSplat | ConvertTo-Json -Compress)

            $itemUpdateList += [PSCustomObject]@{
                UPN = $item.UPN
                Splat = $itemUpdateSplat
            }
        }
    }

    return $itemUpdateList
}