<#
.SYNOPSIS
Flatten the computed change lists into uniform preview rows for table review.

.DESCRIPTION
Called by Invoke-IDBridge -Preview after the plan phase. Turns every change list the
pipeline computed (org units, deactivations, updates/renames/moves, creates, and group
membership, per directory) into one flat row shape - Directory, Action, PersonID, Name,
Account, Building, OrgUnit, Password, Changes - so the proposed run can be reviewed with
Format-Table / Where-Object / Out-GridView without exporting anything. Rows are emitted
per directory in the same order the apply phase would execute them (CreateOU, Deactivate,
Update, Rename, Move, Create, GroupAdd, GroupRemove). Group changes emit one row per
user+group pair.

The Password column is filled for Create rows only, and only when -ShowPasswords is set -
the create splats' SecureStrings are decoded at emit time and never logged. Every list
parameter is optional so disabled directories or disabled group processing simply
contribute no rows.

.PARAMETER SourceData
The enriched source records; used to resolve Name/Account/Building for rows whose change
list item doesn't carry them (updates, renames, moves, groups).

.PARAMETER ShowPasswords
Decode the create splats' passwords into the Password column. Off by default.

.PARAMETER ADUsersToCreate
Output of Get-ADUsersToCreate.

.PARAMETER ADUsersToUpdate
Output of Get-ADUsersToUpdate (@{ UpdateList; RenameList; MoveList }).

.PARAMETER ADUsersToDeactivate
Output of Get-ADUsersToDeactivate.

.PARAMETER ADUserGroupsToUpdate
Output of Get-ADUserGroupsToUpdate (@{ Add; Remove }).

.PARAMETER ADOrgUnitsToCreate
Output of Get-ADOrgUnitsForProcessing (OU distinguished names).

.PARAMETER GoogleUsersToCreate
Output of Get-GoogleUsersToCreate.

.PARAMETER GoogleUsersToUpdate
Output of Get-GoogleUsersToUpdate.

.PARAMETER GoogleUsersToDeactivate
Output of Get-GoogleUsersToDeactivate.

.PARAMETER GoogleUserGroupsToUpdate
Output of Get-GoogleUserGroupsToUpdate (@{ Add; Remove }).

.PARAMETER GoogleOrgUnitsToCreate
Output of Get-GoogleOrgUnitsForProcessing (OU paths).

.OUTPUTS
[object[]] of @{ Directory; Action; PersonID; Name; Account; Building; OrgUnit; Password; Changes }.

.EXAMPLE
$rows = ConvertTo-IDBridgePreviewRow -SourceData $sourceData -ADUsersToCreate $ADUsersToCreate

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-21
#>
function ConvertTo-IDBridgePreviewRow {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $SourceData,

        [switch]$ShowPasswords,

        $ADUsersToCreate,
        $ADUsersToUpdate,
        $ADUsersToDeactivate,
        $ADUserGroupsToUpdate,
        $ADOrgUnitsToCreate,

        $GoogleUsersToCreate,
        $GoogleUsersToUpdate,
        $GoogleUsersToDeactivate,
        $GoogleUserGroupsToUpdate,
        $GoogleOrgUnitsToCreate
    )

    #Source record lookup for rows whose list item carries only PersonID + splat
    $recordByID = @{}
    foreach ($record in $SourceData) { $recordByID["$($record.personID)"] = $record }

    #"First Last" from a source record, empty when the record can't be resolved
    $recordName = { param($record) if ($record) { "$($record.NameFirst) $($record.NameLast)".Trim() } else { '' } }

    #Compact "Key=value; Key=value" rendering of a splat, minus bookkeeping keys.
    #SecureStrings never appear in update splats, but render as (secure) defensively
    #so a password can never leak through the Changes column.
    $formatSplat = {
        param($Splat, $ExcludeKeys)
        $parts = foreach ($key in $Splat.Keys | Where-Object { $_ -notin $ExcludeKeys } | Sort-Object) {
            $value = $Splat[$key]
            if ($value -is [securestring]) { $value = '(secure)' }
            elseif ($value -is [hashtable]) { $value = ($value | ConvertTo-Json -Compress) }
            "$key=$value"
        }
        $parts -join '; '
    }

    #Create-row password: decoded only when -ShowPasswords, empty otherwise
    $formatPassword = {
        param($Value)
        if (-not $ShowPasswords) { '' }
        elseif ($Value -is [securestring]) { ConvertFrom-SecureString -SecureString $Value -AsPlainText }
        else { "$Value" }
    }

    $rows = [System.Collections.Generic.List[object]]::new()

    #Rows follow the apply phase's execution order within each directory

    #region AD Rows
    foreach ($item in @($ADOrgUnitsToCreate)) {
        if ($null -eq $item) { continue }
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';  Action = 'CreateOU'; PersonID = ''; Name = ''; Account = ''
            Building  = '';    OrgUnit = "$item";   Password = ''; Changes = ''
        })
    }

    foreach ($item in @($ADUsersToDeactivate)) {
        if ($null -eq $item) { continue }
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';               Action  = 'Deactivate';                     PersonID = "$($item.PersonID)"
            Name      = & $recordName $item; Account = $item.Username;                   Building = $item.Building
            OrgUnit   = $item.ADOrganizationalUnitTrash; Password = ''; Changes = 'Disable account; move to trash OU'
        })
    }

    foreach ($item in @($ADUsersToUpdate.UpdateList)) {
        if ($null -eq $item) { continue }
        $record = $recordByID["$($item.PersonID)"]
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';                  Action  = 'Update';         PersonID = "$($item.PersonID)"
            Name      = & $recordName $record; Account = $record.Username; Building = $record.Building
            OrgUnit   = '';                    Password = ''
            Changes   = & $formatSplat $item.Splat @('Identity', 'Division')
        })
    }

    foreach ($item in @($ADUsersToUpdate.RenameList)) {
        if ($null -eq $item) { continue }
        $record = $recordByID["$($item.PersonID)"]
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';                  Action  = 'Rename';         PersonID = "$($item.PersonID)"
            Name      = & $recordName $record; Account = $record.Username; Building = $record.Building
            OrgUnit   = '';                    Password = ''
            Changes   = "CN '$($item.CN)' -> '$($item.NewName)'"
        })
    }

    foreach ($item in @($ADUsersToUpdate.MoveList)) {
        if ($null -eq $item) { continue }
        $record = $recordByID["$($item.PersonID)"]
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';                  Action  = 'Move';           PersonID = "$($item.PersonID)"
            Name      = & $recordName $record; Account = $record.Username; Building = $record.Building
            OrgUnit   = $item.NewOrgUnit;      Password = ''
            Changes   = "Move to $($item.NewOrgUnit)"
        })
    }

    foreach ($item in @($ADUsersToCreate)) {
        if ($null -eq $item) { continue }
        $rows.Add([PSCustomObject]@{
            Directory = 'AD';                     Action  = 'Create';                    PersonID = "$($item.PersonID)"
            Name      = $item.Splat.DisplayName;  Account = $item.Splat.SamAccountName;  Building = $item.Splat.Office
            OrgUnit   = $item.Splat.Path
            Password  = & $formatPassword $item.Splat.AccountPassword
            Changes   = ''
        })
    }

    foreach ($listName in @('Add', 'Remove')) {
        $action = if ($listName -eq 'Add') { 'GroupAdd' } else { 'GroupRemove' }
        foreach ($item in @($ADUserGroupsToUpdate.$listName)) {
            if ($null -eq $item) { continue }
            $record = $recordByID["$($item.PersonID)"]
            foreach ($group in @($item.Groups)) {
                $rows.Add([PSCustomObject]@{
                    Directory = 'AD';                  Action  = $action;          PersonID = "$($item.PersonID)"
                    Name      = & $recordName $record; Account = $record.Username; Building = $record.Building
                    OrgUnit   = '';                    Password = '';              Changes  = "$group"
                })
            }
        }
    }
    #endregion AD Rows




    #region Google Rows
    foreach ($item in @($GoogleOrgUnitsToCreate)) {
        if ($null -eq $item) { continue }
        $rows.Add([PSCustomObject]@{
            Directory = 'Google'; Action = 'CreateOU'; PersonID = ''; Name = ''; Account = ''
            Building  = '';       OrgUnit = "$item";   Password = ''; Changes = ''
        })
    }

    foreach ($item in @($GoogleUsersToDeactivate)) {
        if ($null -eq $item) { continue }
        $changes = 'Archive account; move to trash OU'
        if ($item.GoogleCurrentLicenses) {
            $skuNames = ($item.GoogleCurrentLicenses | ForEach-Object { if ($_.skuName) { $_.skuName } else { $_.skuId } }) -join ', '
            $changes += "; removes licenses: $skuNames"
        }
        $rows.Add([PSCustomObject]@{
            Directory = 'Google';            Action  = 'Deactivate'; PersonID = "$($item.PersonID)"
            Name      = & $recordName $item; Account = $item.UPN;    Building = $item.Building
            OrgUnit   = $item.GoogleOrganizationalUnitTrash; Password = ''; Changes = $changes
        })
    }

    foreach ($item in @($GoogleUsersToUpdate)) {
        if ($null -eq $item) { continue }
        $record = $recordByID["$($item.PersonID)"]
        $rows.Add([PSCustomObject]@{
            Directory = 'Google';              Action  = 'Update';  PersonID = "$($item.PersonID)"
            Name      = & $recordName $record; Account = $item.UPN; Building = $record.Building
            OrgUnit   = '';                    Password = ''
            Changes   = & $formatSplat $item.Splat @('GoogleUserID')
        })
    }

    foreach ($item in @($GoogleUsersToCreate)) {
        if ($null -eq $item) { continue }
        $rows.Add([PSCustomObject]@{
            Directory = 'Google';                                          Action  = 'Create'
            PersonID  = "$($item.PersonID)"
            Name      = "$($item.Splat.FirstName) $($item.Splat.LastName)" ; Account = $item.Splat.PrimaryEmail
            Building  = $item.Splat.Building;                               OrgUnit = $item.Splat.OrgUnitPath
            Password  = & $formatPassword $item.Splat.Password
            Changes   = ''
        })
    }

    foreach ($listName in @('Add', 'Remove')) {
        $action = if ($listName -eq 'Add') { 'GroupAdd' } else { 'GroupRemove' }
        foreach ($item in @($GoogleUserGroupsToUpdate.$listName)) {
            if ($null -eq $item) { continue }
            $record = $recordByID["$($item.PersonID)"]
            foreach ($group in @($item.Groups)) {
                $rows.Add([PSCustomObject]@{
                    Directory = 'Google';              Action  = $action;     PersonID = "$($item.PersonID)"
                    Name      = & $recordName $record; Account = $record.UPN; Building = $record.Building
                    OrgUnit   = '';                    Password = '';         Changes  = "$group"
                })
            }
        }
    }
    #endregion Google Rows

    return $rows
}
