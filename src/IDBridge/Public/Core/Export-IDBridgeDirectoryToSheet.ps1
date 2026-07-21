<#
.SYNOPSIS
Seed the staff source Google Sheet from the current AD and Google Workspace directory state.

.DESCRIPTION
One-time onboarding tool for a new IDBridge deployment. Reads the current users, attributes, and
group memberships from Active Directory (Get-TargetDataAD) and/or Google Workspace
(Get-TargetDataGoogle), scoped to the OU subtree(s) you name, merges the directories per person by
UPN/primaryEmail, and writes one row per person to a NEW tab in the target spreadsheet using the
staff source-sheet column layout (PersonID, NameFirst, NameLast, Username, Building, PersonType,
JobTitle, TerminationDate, ApplicationGroups, EmailGroups, Word, Process, ForceDisable,
GoogleOUOverride) plus review-helper columns (InAD, InGoogle, ADEnabled, GoogleSuspended,
ADOrgUnit, GoogleOrgUnit).

Every row is written with Process = FALSE for human review before use. PersonType and Word are
always blank — nothing is derived from OU names. ApplicationGroups is the de-duplicated dump of
the person's current AD group names; EmailGroups is the same for their Google groups (group
emails are mapped back to group names). PersonID comes from AD EmployeeID, falling back to the
Google organization externalId; a mismatch between the two is logged as a warning and AD wins.

A second tab (default GroupsSeed-<yyyy-MM-dd>) is also written listing the distinct group names
in use across the exported users — Google groups under an Email header in column A, AD groups
under an Application header in column C — intended as the source range for multi-select group
dropdowns on the staff sheet.

A person whose every existing account is disabled/suspended gets yesterday's date as
TerminationDate so the staff plugin computes IDBActive = $false; a mixed state (e.g. AD disabled
but Google active) is logged as a warning and left active. The function throws if either target tab
already exists — it never appends to or overwrites existing sheet data.

A directory is processed only when its scope is named: pass -ADSearchBase to include AD, pass
-GoogleOrgUnitPath to include Google, or pass both. A directory whose scope is omitted is skipped
entirely (never fetched, never a failure) — so a Google-only run does not touch or require AD, and
vice versa. At least one of the two must be provided. Requires Initialize-IDBridge and
Connect-IDBridgeGoogle to have run first (Google auth is always needed to write the result sheet).

.PARAMETER SpreadsheetId
The target spreadsheet ID to write the seed tab into.

.PARAMETER SheetName
The tab name to create (default StaffSeed-<yyyy-MM-dd>). Throws if the tab already exists.

.PARAMETER GroupsSheetName
The groups tab name to create (default GroupsSeed-<yyyy-MM-dd>). Throws if the tab already exists.

.PARAMETER ADSearchBase
One or more OU DNs to scope the AD users to (each a subtree; a user under any of them is included).
Omit to skip Active Directory entirely. No config default.

.PARAMETER GoogleOrgUnitPath
One or more OU paths to scope the Google users to (each a subtree; a user under any of them is
included). Trailing slashes are ignored. Omit to skip Google Workspace entirely. No config default.

.OUTPUTS
[pscustomobject] @{ SpreadsheetId; SheetName; GroupsSheetName; RowsWritten }.

.EXAMPLE
Export-IDBridgeDirectoryToSheet -SpreadsheetId '<spreadsheet id>' -GoogleOrgUnitPath '/YourDistrict/Staff'

.EXAMPLE
Export-IDBridgeDirectoryToSheet -SpreadsheetId '<spreadsheet id>' -ADSearchBase 'OU=Staff,OU=YourDistrict,DC=yourdomain,DC=local' -GoogleOrgUnitPath '/YourDistrict/Staff'

.EXAMPLE
Export-IDBridgeDirectoryToSheet -SpreadsheetId '<spreadsheet id>' -ADSearchBase 'OU=Staff,OU=YourDistrict,DC=yourdomain,DC=local', 'OU=Subs,OU=YourDistrict,DC=yourdomain,DC=local' -GoogleOrgUnitPath '/YourDistrict/Staff', '/YourDistrict/Subs'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-21
#>
function Export-IDBridgeDirectoryToSheet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SpreadsheetId,

        [string]$SheetName = ("StaffSeed-" + (Get-Date -Format 'yyyy-MM-dd')),

        [string]$GroupsSheetName = ("GroupsSeed-" + (Get-Date -Format 'yyyy-MM-dd')),

        [string[]]$ADSearchBase,

        [string[]]$GoogleOrgUnitPath
    )

    #region Validate Scope
    #Each directory is processed only when its OU scope is named - no config defaults, and an
    #omitted scope is skipped entirely (never fetched, never a failure). Require at least one.
    if (-not $ADSearchBase -and -not $GoogleOrgUnitPath) {
        Write-Log -Message "Export: Specify at least one of -ADSearchBase or -GoogleOrgUnitPath - neither was provided." -Level Error
        Throw "Export: Specify at least one of -ADSearchBase or -GoogleOrgUnitPath - neither was provided."
    }

    #Import Google API Headers (with access token) - always needed to write the result sheet
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }

    Write-Log -Message "Export: Starting directory export to spreadsheet $SpreadsheetId tab '$SheetName'" -Level Info
    #endregion Validate Scope

    #region Get AD Users
    $adUsers = @()
    if ($ADSearchBase) {
        $adData = Get-TargetDataAD

        #Scope to the subtree under any of the search bases
        $adUsers = @($adData.Users | Where-Object {
            $distinguishedName = $_.DistinguishedName
            [bool]($ADSearchBase | Where-Object { $distinguishedName -like ("*," + $_) })
        })
        Write-Log -Message "Export: $($adUsers.Count) of $($adData.Users.Count) AD users are under $($ADSearchBase -join ', ')" -Level Info
    } else {
        Write-Log -Message "Export: No -ADSearchBase specified - skipping Active Directory" -Level Info
    }
    #endregion Get AD Users

    #region Get Google Users
    $googleUsers = @()
    $googleGroupNameByEmail = @{}
    if ($GoogleOrgUnitPath) {
        $googleData = Get-TargetDataGoogle

        #Map group emails back to group names for the sheet dump
        foreach ($group in $googleData.Groups) {
            if ($group.email) { $googleGroupNameByEmail[$group.email] = $group.name }
        }

        #Normalize trailing slashes so '/District/Staff/' scopes the same users as '/District/Staff'
        #(the root OU '/' is kept as-is)
        $googleOrgUnitPaths = @($GoogleOrgUnitPath | ForEach-Object { if ($_.TrimEnd('/')) { $_.TrimEnd('/') } else { '/' } })

        #Scope to the subtree under any of the OU paths
        $googleUsers = @($googleData.Users | Where-Object {
            $orgUnitPath = $_.orgUnitPath
            [bool]($googleOrgUnitPaths | Where-Object { $orgUnitPath -eq $_ -or $orgUnitPath -like ($_.TrimEnd('/') + "/*") })
        })
        Write-Log -Message "Export: $($googleUsers.Count) of $($googleData.Users.Count) Google users are under $($googleOrgUnitPaths -join ', ')" -Level Info
    } else {
        Write-Log -Message "Export: No -GoogleOrgUnitPath specified - skipping Google Workspace" -Level Info
    }
    #endregion Get Google Users

    #region Merge Directories
    #Merge AD and Google accounts per person, joined by UPN = primaryEmail
    $people = [ordered]@{}
    foreach ($adUser in $adUsers) {
        $key = if ($adUser.UserPrincipalName) { $adUser.UserPrincipalName.ToLower() } else { $adUser.SamAccountName.ToLower() }
        $people[$key] = [PSCustomObject]@{ AD = $adUser; Google = $null }
    }
    foreach ($googleUser in $googleUsers) {
        $key = $googleUser.primaryEmail.ToLower()
        if ($people.Contains($key)) {
            $people[$key].Google = $googleUser
        } else {
            $people[$key] = [PSCustomObject]@{ AD = $null; Google = $googleUser }
        }
    }
    Write-Log -Message "Export: Merged into $($people.Count) unique people" -Level Info
    #endregion Merge Directories

    #region Build Rows
    $rows = foreach ($entry in $people.GetEnumerator()) {
        $ad = $entry.Value.AD
        $google = $entry.Value.Google
        $googleOrg = if ($google) { $google.organizations | Select-Object -First 1 } else { $null }

        #PersonID from whichever directory has it; a mismatch is logged and AD wins
        $adPersonID = if ($ad) { [string]$ad.EmployeeID } else { "" }
        $googlePersonID = if ($google) { [string](($google.externalIds | Where-Object { $_.type -eq "organization" }).value | Select-Object -First 1) } else { "" }
        if ($adPersonID -and $googlePersonID -and ($adPersonID -ne $googlePersonID)) {
            Write-Log -Message "Export: PersonID mismatch for $($entry.Key) - AD EmployeeID '$adPersonID' vs Google externalId '$googlePersonID'; using AD" -Level Warn
        }
        $personID = if ($adPersonID) { $adPersonID } else { $googlePersonID }

        #Disabled only when every existing account is disabled/suspended; a mixed state stays active
        $accountDisabledStates = @()
        if ($ad) { $accountDisabledStates += (-not $ad.Enabled) }
        if ($google) { $accountDisabledStates += [bool]$google.suspended }
        $isDisabled = ($accountDisabledStates -notcontains $false)
        if (($accountDisabledStates -contains $true) -and ($accountDisabledStates -contains $false)) {
            Write-Log -Message "Export: Mixed account state for $($entry.Key) (AD enabled: $($ad.Enabled), Google suspended: $($google.suspended)) - treating as active" -Level Warn
        }

        #Current group memberships split per directory: AD -> ApplicationGroups, Google -> EmailGroups
        $adGroupNames = @()
        if ($ad -and $ad.CurrentGroups) { $adGroupNames += $ad.CurrentGroups }
        $googleGroupNames = @()
        if ($google -and $google.CurrentGroups) {
            foreach ($groupEmail in $google.CurrentGroups) {
                $googleGroupNames += if ($googleGroupNameByEmail.ContainsKey($groupEmail)) { $googleGroupNameByEmail[$groupEmail] } else { ($groupEmail -split '@')[0] }
            }
        }

        [PSCustomObject]@{
            PersonID          = $personID
            NameFirst         = if ($ad -and $ad.GivenName) { $ad.GivenName } elseif ($google) { [string]$google.name.givenName } else { "" }
            NameLast          = if ($ad -and $ad.Surname) { $ad.Surname } elseif ($google) { [string]$google.name.familyName } else { "" }
            Username          = if ($ad) { $ad.SamAccountName } else { ($google.primaryEmail -split '@')[0] }
            Building          = if ($ad -and $ad.physicalDeliveryOfficeName) { $ad.physicalDeliveryOfficeName } elseif ($googleOrg) { [string]$googleOrg.department } else { "" }
            PersonType        = ""
            JobTitle          = if ($ad -and $ad.Title) { $ad.Title } elseif ($googleOrg) { [string]$googleOrg.title } else { "" }
            TerminationDate   = if ($isDisabled) { (Get-Date).AddDays(-1).ToString('MM/dd/yyyy') } else { "" }
            ApplicationGroups = (@($adGroupNames | Sort-Object -Unique) -join ', ')
            EmailGroups       = (@($googleGroupNames | Sort-Object -Unique) -join ', ')
            Word              = ""
            Process           = "FALSE"
            ForceDisable      = "FALSE"
            GoogleOUOverride  = "FALSE"
            InAD              = if ($ad) { "TRUE" } else { "FALSE" }
            InGoogle          = if ($google) { "TRUE" } else { "FALSE" }
            ADEnabled         = if ($ad) { ([string]$ad.Enabled).ToUpper() } else { "" }
            GoogleSuspended   = if ($google) { ([string][bool]$google.suspended).ToUpper() } else { "" }
            ADOrgUnit         = if ($ad) { ($ad.DistinguishedName -split ',', 2)[1] } else { "" }
            GoogleOrgUnit     = if ($google) { $google.orgUnitPath } else { "" }
        }
    }

    $rows = @($rows | Sort-Object NameLast, NameFirst)
    if ($rows.Count -eq 0) {
        Write-Log -Message "Export: No users found under the given OU scopes - nothing to write" -Level Error
        Throw "Export: No users found under the given OU scopes - nothing to write"
    }
    #endregion Build Rows

    #region Build Groups In Use
    #Distinct group names across the exported users - feeds the GroupsSeed dropdown-source tab
    #(Email column = Google groups, Application column = AD groups, matching the staff-sheet split)
    $adGroupsInUse = @($adUsers | ForEach-Object { $_.CurrentGroups } | Where-Object { $_ } | Sort-Object -Unique)
    $googleGroupsInUse = @($googleUsers | ForEach-Object { $_.CurrentGroups } | Where-Object { $_ } | ForEach-Object {
        if ($googleGroupNameByEmail.ContainsKey($_)) { $googleGroupNameByEmail[$_] } else { ($_ -split '@')[0] }
    } | Sort-Object -Unique)
    #endregion Build Groups In Use

    #region Write to Sheet
    $sheetColumns = @(
        "PersonID", "NameFirst", "NameLast", "Username", "Building", "PersonType", "JobTitle",
        "TerminationDate", "ApplicationGroups", "EmailGroups", "Word", "Process", "ForceDisable",
        "GoogleOUOverride", "InAD", "InGoogle", "ADEnabled", "GoogleSuspended", "ADOrgUnit", "GoogleOrgUnit"
    )

    try {
        #Refuse to touch an existing tab - this tool only ever writes fresh ones
        $metaUri = "https://sheets.googleapis.com/v4/spreadsheets/$($SpreadsheetId)?fields=sheets.properties"
        $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop

        foreach ($tabName in @($SheetName, $GroupsSheetName)) {
            if ($meta.sheets | Where-Object { $_.properties.title -eq $tabName }) {
                Write-Log -Message "Export: Sheet '$tabName' already exists in spreadsheet $SpreadsheetId - refusing to overwrite. Re-run with a different -SheetName/-GroupsSheetName." -Level Error
                Throw "Export: Sheet '$tabName' already exists in spreadsheet $SpreadsheetId - refusing to overwrite. Re-run with a different -SheetName/-GroupsSheetName."
            }
        }

        #Create both tabs sized to the data
        $groupsRowCount = [Math]::Max($adGroupsInUse.Count, $googleGroupsInUse.Count)
        $batchUri = "https://sheets.googleapis.com/v4/spreadsheets/$($SpreadsheetId):batchUpdate"
        $createBody = @{
            requests = @(
                @{
                    addSheet = @{
                        properties = @{
                            title          = $SheetName
                            gridProperties = @{
                                rowCount    = $rows.Count + 10
                                columnCount = $sheetColumns.Count
                            }
                        }
                    }
                },
                @{
                    addSheet = @{
                        properties = @{
                            title          = $GroupsSheetName
                            gridProperties = @{
                                rowCount    = $groupsRowCount + 10
                                columnCount = 3
                            }
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 8
        $null = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $createBody -ContentType 'application/json' -ErrorAction Stop

        #Header plus one row per person, written in a single call
        $values = [System.Collections.Generic.List[object]]::new()
        $values.Add($sheetColumns)
        foreach ($row in $rows) {
            $values.Add(@(foreach ($column in $sheetColumns) { [string]$row.$column }))
        }

        #Sheet name is quoted so names with dashes/spaces parse as A1 notation
        $null = Set-GSheetData -TokenInformation $headers -rangeA1 'A1' -sheetName ("'" + $SheetName + "'") -spreadSheetID $SpreadsheetId -values $values

        Write-Log -Message "Export: Wrote $($rows.Count) rows to '$SheetName' in spreadsheet $SpreadsheetId" -Level Info

        #GroupsSeed tab: Email (Google groups) in column A, Application (AD groups) in column C
        $groupsValues = [System.Collections.Generic.List[object]]::new()
        $groupsValues.Add(@("Email", "", "Application"))
        for ($i = 0; $i -lt $groupsRowCount; $i++) {
            $groupsValues.Add(@(
                $(if ($i -lt $googleGroupsInUse.Count) { $googleGroupsInUse[$i] } else { "" }),
                "",
                $(if ($i -lt $adGroupsInUse.Count) { $adGroupsInUse[$i] } else { "" })
            ))
        }
        $null = Set-GSheetData -TokenInformation $headers -rangeA1 'A1' -sheetName ("'" + $GroupsSheetName + "'") -spreadSheetID $SpreadsheetId -values $groupsValues

        Write-Log -Message "Export: Wrote $($googleGroupsInUse.Count) Google and $($adGroupsInUse.Count) AD groups to '$GroupsSheetName' in spreadsheet $SpreadsheetId" -Level Info
    }
    catch {
        Write-Log -Message ("Export: Failed writing to spreadsheet: " + $_.Exception.Message) -Level Error
        Throw $_
    }
    #endregion Write to Sheet

    return [PSCustomObject]@{
        SpreadsheetId   = $SpreadsheetId
        SheetName       = $SheetName
        GroupsSheetName = $GroupsSheetName
        RowsWritten     = $rows.Count
    }
}
