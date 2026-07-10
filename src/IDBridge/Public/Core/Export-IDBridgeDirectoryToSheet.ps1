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

Every row is written with Process = FALSE for human review before use. PersonType, Word, and
EmailGroups are always blank — nothing is derived from OU names. ApplicationGroups is the full
dump of the person's current AD and Google group names (Google group emails are mapped back to
group names), merged and de-duplicated. PersonID comes from AD EmployeeID, falling back to the
Google organization externalId; a mismatch between the two is logged as a warning and AD wins.

A person whose every existing account is disabled/suspended gets yesterday's date as
TerminationDate so the staff plugin computes IDBActive = $false; a mixed state (e.g. AD disabled
but Google active) is logged as a warning and left active. The function throws if the target tab
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

.PARAMETER ADSearchBase
OU DN to scope the AD users to (subtree). Omit to skip Active Directory entirely. No config default.

.PARAMETER GoogleOrgUnitPath
OU path to scope the Google users to (subtree). Omit to skip Google Workspace entirely. No config default.

.OUTPUTS
[pscustomobject] @{ SpreadsheetId; SheetName; RowsWritten }.

.EXAMPLE
Export-IDBridgeDirectoryToSheet -SpreadsheetId '1qrZ...' -GoogleOrgUnitPath '/Marshfield/Staff'

.EXAMPLE
Export-IDBridgeDirectoryToSheet -SpreadsheetId '1qrZ...' -ADSearchBase 'OU=Staff,OU=Marshfield,DC=sdom,DC=local' -GoogleOrgUnitPath '/Marshfield/Staff'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-08
#>
function Export-IDBridgeDirectoryToSheet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SpreadsheetId,

        [string]$SheetName = ("StaffSeed-" + (Get-Date -Format 'yyyy-MM-dd')),

        [string]$ADSearchBase,

        [string]$GoogleOrgUnitPath
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

        #Scope to the subtree under the search base
        $adUsers = @($adData.Users | Where-Object { $_.DistinguishedName -like ("*," + $ADSearchBase) })
        Write-Log -Message "Export: $($adUsers.Count) of $($adData.Users.Count) AD users are under $ADSearchBase" -Level Info
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

        #Scope to the subtree under the OU path
        $googlePathPrefix = $GoogleOrgUnitPath.TrimEnd('/') + "/*"
        $googleUsers = @($googleData.Users | Where-Object { $_.orgUnitPath -eq $GoogleOrgUnitPath -or $_.orgUnitPath -like $googlePathPrefix })
        Write-Log -Message "Export: $($googleUsers.Count) of $($googleData.Users.Count) Google users are under $GoogleOrgUnitPath" -Level Info
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

        #Full dump of current group memberships from both directories, de-duplicated
        $groupNames = @()
        if ($ad -and $ad.CurrentGroups) { $groupNames += $ad.CurrentGroups }
        if ($google -and $google.CurrentGroups) {
            foreach ($groupEmail in $google.CurrentGroups) {
                $groupNames += if ($googleGroupNameByEmail.ContainsKey($groupEmail)) { $googleGroupNameByEmail[$groupEmail] } else { ($groupEmail -split '@')[0] }
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
            ApplicationGroups = (@($groupNames | Sort-Object -Unique) -join ', ')
            EmailGroups       = ""
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

    #region Write to Sheet
    $sheetColumns = @(
        "PersonID", "NameFirst", "NameLast", "Username", "Building", "PersonType", "JobTitle",
        "TerminationDate", "ApplicationGroups", "EmailGroups", "Word", "Process", "ForceDisable",
        "GoogleOUOverride", "InAD", "InGoogle", "ADEnabled", "GoogleSuspended", "ADOrgUnit", "GoogleOrgUnit"
    )

    try {
        #Refuse to touch an existing tab - this tool only ever writes a fresh one
        $metaUri = "https://sheets.googleapis.com/v4/spreadsheets/$($SpreadsheetId)?fields=sheets.properties"
        $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop

        if ($meta.sheets | Where-Object { $_.properties.title -eq $SheetName }) {
            Write-Log -Message "Export: Sheet '$SheetName' already exists in spreadsheet $SpreadsheetId - refusing to overwrite. Re-run with a different -SheetName." -Level Error
            Throw "Export: Sheet '$SheetName' already exists in spreadsheet $SpreadsheetId - refusing to overwrite. Re-run with a different -SheetName."
        }

        #Create the tab sized to the data
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
    }
    catch {
        Write-Log -Message ("Export: Failed writing to spreadsheet: " + $_.Exception.Message) -Level Error
        Throw $_
    }
    #endregion Write to Sheet

    return [PSCustomObject]@{
        SpreadsheetId = $SpreadsheetId
        SheetName     = $SheetName
        RowsWritten   = $rows.Count
    }
}
