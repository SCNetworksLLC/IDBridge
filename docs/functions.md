# IDBridge Function Reference

Every **exported** function (per `IDBridge.psd1` → `FunctionsToExport`), grouped by layer.
One entry each: purpose, key params, return shape, notable deps/external calls. For the
overall flow see [architecture.md](architecture.md).

Legend: 🌐 = makes external API/cmdlet calls · 🧮 = pure decision/compute (no writes).

---

## Core (`src\IDBridge\Public\Core\`)

### `Invoke-IDBridge` 🌐
Top-level orchestrator. **Params:** `-RootPath` (def `C:\IDBridge`), switches `-ReadOnly
-TestRun -SkipADCheck -TraceLogging -SkipAD -SkipGoogle`. Runs the full pipeline (see
architecture.md). **Returns:** nothing; side effects + CSV export + log push.

### `Initialize-IDBridge` 🌐
Loads config, builds/validates `Paths.*`, sets up logging (+5 MB rotation), acquires Google
token → `$script:GoogleHeaders`, imports AD module, applies feature cascade. **Params:**
`-RootPath`. **Returns:** nothing; sets `$script:IDBridgeConfig`, `$script:Logs`,
`$script:GoogleHeaders`.

### `Get-IDBridgeConfig`
Accessor for `$script:IDBridgeConfig`. Throws if called before `Initialize-IDBridge`.

### `Get-IDBridgeSecret`
**Params:** `-Name` (mandatory), `-VaultName` (optional, defaults to config `Secrets.VaultName`),
`-AsPlainText`. Resolves a secret from a **SecretManagement vault** if available/configured,
otherwise falls back to `"<UserSecretsRoot>\<Name>.txt"` (`ConvertTo-SecureString`) — the
historical behavior. **Returns:** `[SecureString]` (or `[string]` with `-AsPlainText`). See
[secrets.md](secrets.md).

### `Write-Log` 🌐(file)
**Params:** `-Message` (alias `-LogContent`, mandatory), `-Path`/`-LogPath` (def
`Paths.LogFile`), `-Level {Error|Warn|Info|Trace}` (def `Info`), `-NoClobber`. Writes to
file + `$script:Logs` + console. Drops `Trace` unless `Debug.TraceLogging`.

### `Get-IDBridgeLogs`
Accessor for the in-memory `$script:Logs` buffer (used by `Push-LogsToSheet`). Throws if
uninitialized.

### `Get-GoogleHeaders`
Accessor for `$script:GoogleHeaders` (the bearer auth headers). Throws if Google auth
wasn't set up.

### `Get-RandomPassword`
**Params:** `-PasswordLength` (1–256, def 10). **Returns:** random string mixing
lower/upper/digit/special.

### `New-Passphrase` 🌐
Deterministic passphrase generator backed by an Azure Function. **Params:** `-Nonce`
(SecureString), `-Username` (string/array), `-Mode {words|verbnoun}`, `-WordCount` (2–6,
def 3), `-AuthToken` (SecureString, def `$env:PASSPHRASE_AUTH_TOKEN`), `-FunctionUrl`.
POSTs to `<FunctionUrl>/api/generate`. **Returns:** phrase string(s).

### `Get-StudentGrade`
**Params:** `-gradYear` (2000–2099), `-gradeAdvanceDate`. **Returns:** grade code
(`12`..`01`, `KG`, `K4`, `PK`, or `GD`) from birth year vs. school-year rollover.

### `Remove-IDBridgeDuplicateID` 🧮
**Params:** `-SourceData` (nullable/empty allowed). Two passes: drop records flagged
`ADDuplicateIDStatus`/`GoogleDuplicateIDStatus`, then drop *all* records sharing a
duplicate `personID`. **Returns:** array (guaranteed).

### `Show-GroupsNotProcessed` 🧮
**Params:** `-ProposedGroups`, `-TargetGroups`. Trace-logs each proposed group missing
from the target. No return.

---

## Source (`src\IDBridge\Public\Source\`)

### `Invoke-SourcePlugins` 🌐
Discovers/runs plugins from `$IDConfig.Plugins`. For each enabled entry: verifies
`<PluginsRoot>\<Function>.ps1` exists, dot-sources it, confirms the function via
`Get-Command`, invokes with no args. **Returns:** `@{ SourceData; OverrideData }`
(split by each plugin's `Type`). Throws if no source data gathered. See [plugins.md](plugins.md).

### `Get-SourceDataGSheet` 🌐
**Params:** `-sheetID`, `-sheetRange`, `-userCount`, `-userCountSafetyPercentage` (def 75),
`-testRun` (def `$false`). Reads a sheet via `Get-GoogleSheetData`, validates required
columns, enforces a count safety floor, returns rows where `Process='TRUE'` (capped at 10
when `testRun`). **Returns:** array of row objects.

### `Get-SourceDataSkywardSMS` 🌐
**Params:** `-ClientId`, `-ClientSecret`, `-TokenUrl`, `-BaseUrl`, `-ExcludeEntityIDs`,
`-SafetyCheckCount`, `-SafetyCheckPercentage`. OAuth2 client-credentials → OneRoster
`/schools/{id}/students` (paginated). Dedupes by `NameID`, enriches with school names +
`LastSeen`, merges prior-run state CSV in `DataRoot`. **Returns:** student records.

### `Get-SourceDataInfiniteCampus` 🌐
**Params:** `-ClientId`, `-ClientSecret`, `-TokenUrl`, `-BaseUrl`. OAuth2 →
OneRoster `/schools` + `/students` (paginated). Normalizes to `SourcedId/LocalID/
InternalID/NameFirst/NameLast/Email/Role/SchoolName/Grade/Status/...`. **Returns:** records.

### `Merge-IDBridgeOverrideData` 🧮
**Params:** `-SourceData`, `-OverrideData`. Applies override rows by `personID`: non-empty
scalar values overwrite; `AddGroup`/`RemoveGroup` mutate `GroupsProposed`; `PersonID` and
null/blank values skipped. **Returns:** mutated source array.

---

## Target (`src\IDBridge\Public\Target\`)

### `Get-TargetDataAD` 🌐
No params. Pulls all AD users (rich property set incl. `EmployeeID`, `MemberOf`,
`extensionAttribute1-5`), groups, OUs; resolves `MemberOf`→names into `CurrentGroups`;
detects duplicate `EmployeeID`s; builds `LookupByID` keyed by EmployeeID. **Returns:**
`@{ Users; Groups; OrgUnits; DuplicateUsers; LookupByID }`.

### `Get-TargetDataGoogle` 🌐
No params. Pulls all Google users (via `Get-GoogleData`), groups (excludes
`classroom_teachers`), and OUs; fetches group members **in parallel** (throttle 10) into
`CurrentGroups`; detects duplicate `externalIds`; builds `LookupByID` keyed by externalID.
**Returns:** `@{ Users; Groups; OrgUnits; DuplicateUsers; LookupByID; Students; Staff }`.

### `Add-TargetDataAD` 🧮
**Params:** `-SourceData`, `-ADData`. For each source record, if `LookupByID[personID]`
hits, attaches `ADObject`, `ADCurrentUserID`, `ADCurrentUserEnabledStatus`,
`ADCurrentGroups`; flags `ADDuplicateIDStatus` when applicable. **Returns:** enriched array.

### `Add-TargetDataGoogle` 🧮
**Params:** `-SourceData`, `-GoogleData`. As above for Google: `GoogleObject`,
`GoogleCurrentUserID`, `GoogleCurrentUserSuspendedStatus`, `GoogleCurrentGroups`,
`GoogleDuplicateIDStatus`. **Returns:** enriched array.

---

## Active Directory (`src\IDBridge\Public\AD\`)

> Identity key: **`EmployeeID` = `personID`**. CN convention: `FirstName LastName personID`.

### `Get-ADUsersToSetEmployeeID` 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`. For active, unlinked source users, matches an
existing AD user by EmployeeID or SamAccountName **and** name. **Returns:** hashtable
`personID → @{ ID(ObjectGUID); Groups; EnabledStatus; User }`.

### `Get-ADOrgUnitsForProcessing` 🧮
**Params:** `-UserList`, `-UserRootOU`, `-CurrentOrgUnits`. Collects needed OU DNs (+trash),
expands ancestors, removes existing, sorts parents-first. **Returns:** ordered OU DN array.

### `Get-ADUsersToCreate` 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`, `-Nonce`. **Predicate:** `IDBActive=true` AND no
`ADCurrentUserID` AND UPN absent from AD. Builds a `New-ADUser` splat (password from
`ADKey` or `ADPassphraseAPI`→`New-Passphrase`). **Returns:** `@{ PersonID; Splat }[]`.

### `Get-ADUsersToUpdate` 🧮🌐
*(file: `Get-ADUsersUpdate.ps1`)* **Params:** `-UserList`, `-LookupByID`. **Predicate:**
active + has `ADCurrentUserID` + any delta (name, username/UPN, EmployeeID, office/title/
company/dept, enabled state, employeeType/ext-attr, CN, OU). **Returns:** `@{ UpdateList;
RenameList; MoveList }`.

### `Get-ADUsersToDeactivate` 🧮
**Params:** `-UserList`. **Predicate:** `IDBActive=false` AND `ADCurrentUserEnabledStatus=true`.
**Returns:** user objects to disable.

### `Get-ADUserGroupsToUpdate` 🧮
**Params:** `-UserList`, `-CurrentADGroups`. Diffs `GroupsProposed` vs `ADCurrentGroups`
(adds must exist in AD). **Returns:** `@{ Add; Remove }` (each `@{PersonID; ADCurrentUserID;
Groups}`).

### `New-IDBridgeADOrgUnit` 🌐
**Params:** `-OrgUnit` (DN). Parses DN → `New-ADOrganizationalUnit`.

### `Disable-IDBridgeADUser` 🌐
**Params:** `-User`, `-GroupRemovalProcessingStatus`. Disables account, stamps `Division`
with timestamp, moves to trash OU, and (if flag) removes all current groups.

---

## Google Workspace (`src\IDBridge\Public\Google\`)

> Identity key: **`externalIds` (type `organization`).value = `personID`**.
> All write functions get auth via `Get-GoogleHeaders` and hit the Admin SDK Directory API
> base `https://admin.googleapis.com/admin/directory/v1/`.

### `Get-GoogleData` 🌐
**Params:** `-GoogleHeaders`, `-APIUri`. Generic paginated GET (follows `nextPageToken`),
consolidates the primary collection. **Returns:** combined array.

### `Get-GoogleApiAccessToken` 🌐
**Params:** `-ServiceAccountKeyPath`, `-Scope`, `-TargetUserEmail`. Builds + RS256-signs a
JWT, exchanges it at `https://oauth2.googleapis.com/token`. **Returns:**
`@{ Authorization='Bearer …'; Accept='application/json' }`.

### `Get-GoogleUsersToSetEmployeeID` 🧮
**Params:** `-UserList`, `-GoogleUsers`. Matches active, unlinked source users to existing
Google users by primaryEmail+name. **Returns:** hashtable `personID → @{ ID; Groups;
SuspendedStatus; User }`.

### `Get-GoogleOrgUnitsForProcessing` 🧮
**Params:** `-UserList`, `-UserRootOU`, `-CurrentOrgUnits`. Collects needed OU paths
(+trash), expands ancestors (`/A/B/C`→`/A`,`/A/B`,`/A/B/C`), removes existing, sorts
shallow-first. **Returns:** ordered OU path array.

### `Get-GoogleUsersToCreate` 🧮🌐
**Params:** `-UserList`, `-GoogleUsers`. **Predicate:** `IDBActive=true` AND no
`GoogleCurrentUserID` AND UPN absent from Google. Builds create splat (password from
`GooglePassphraseAPI`→`New-Passphrase` or `GoogleKey`; skips if neither). **Returns:**
`@{ UPN; Splat }[]`.

### `Get-GoogleUsersToUpdate` 🧮
**Params:** `-UserList`, `-LookupByID`, `-GoogleUsers`. **Predicate:** active + linked +
delta in primaryEmail (with alias-conflict handling → `RemoveAlias`), externalId, name,
dept/title, suspended state (incl. `ForceDisable`), or OU (unless `GoogleOUOverride`).
**Returns:** `@{ UPN; Splat }[]` only for changed users.

### `Get-GoogleUsersToDeactivate` 🧮
**Params:** `-UserList`. **Predicate:** `IDBActive=false` AND
`GoogleCurrentUserSuspendedStatus=false`. **Returns:** user objects.

### `Get-GoogleUserGroupsToUpdate` 🧮
**Params:** `-UserList`, `-GoogleGroups` (nullable), `-GroupPrimaryDomainName`. Diffs
proposed vs current groups (adds must exist in Google; group email = `name@domain`).
**Returns:** `@{ Add; Remove }`.

### `Get-GoogleUsersOrphaned` 🧮
**Params:** `-UserList`, `-GoogleUsers`, `-TrashOU`. Finds Google users whose ID isn't in
source. **Returns:** `@{ GoogleCurrentUserID; GoogleOrganizationalUnitTrash; Groups }[]`.
*(Not currently called by `Invoke-IDBridge`; available for orphan cleanup.)*

### `New-IDBridgeGoogleUser` 🌐
**Params:** `-PrimaryEmail`, `-PersonID`, `-FirstName`, `-LastName`, `-Building`,
`-JobTitle`, `-OrgUnitPath`, `-Password` (SecureString), `-ChangeAtNextLogin`. POST
`/users/`. **Returns:** API user object (has `.ID`).

### `Update-IDBridgeGoogleUser` 🌐
**Params:** `-GoogleUserID` + any of `-PrimaryEmail -Suspended -PersonID -FirstName
-LastName -Building -JobTitle -OrgUnitPath -Password -ChangeAtNextLogin -RemoveAlias`.
PUT `/users/{id}` with only changed fields; `RemoveAlias` does a lookup + DELETE on the
alias. Used for updates, moves, renames, and suspend-to-trash deactivations.

### `New-IDBridgeGoogleOrgUnit` 🌐
**Params:** `-OrgUnit` (path). POST
`/customer/my_customer/orgunits` with name + parentOrgUnitPath.

### `Update-GoogleGroupMembers` 🌐
**Params:** `-GroupEmail`, `-PersonID`, `-UpdateType {Add|Remove}`. Add → POST
`/groups/{email}/members` (role MEMBER); Remove → DELETE `/groups/{email}/members/{id}`.

### `Push-LogsToSheet` 🌐
**Params:** `-spreadsheetId`, `-sheetName`. Pulls `Get-IDBridgeLogs`, creates the sheet/
header if missing, inserts rows, writes newest-first via `Set-GSheetData`.

---

## Google Sheets helpers (`src\IDBridge\Public\Google\Sheets\`)

### `Get-GoogleSheetData` 🌐
**Params:** `-GoogleSheetID`, `-GoogleSheetRange`. GET Sheets v4 `values` (`majorDimension=
ROWS`); first row = headers; trims strings. **Returns:** array of row objects.

### `Set-GSheetData` 🌐
**Params:** `-TokenInformation`, `-sheetName`, `-spreadSheetID`, `-values`, plus parameter
sets `-append` (POST `:append`) or `-rangeA1` (PUT `…!A1`), `-valueInputOption` (def RAW),
`-contenttype`. Writes rows.

### `Get-SheetIdByName` 🌐
**Params:** `-spreadSheetID`, `-sheetName`, `-TokenInformation`. **Returns:** numeric
sheetId (throws if not found).

### `Get-ColumnLetter`
**Params:** `-ColumnNumber` (1-based). **Returns:** Excel column letter(s) (A, …, AA).

### `Convert-CellToIndex`
**Params:** `-cell` (e.g. `B2`). **Returns:** `@{ row; column }` (0-based).

### `Set-CheckboxesToFalse` 🌐
**Params:** `-cells`, `-spreadSheetID`, `-sheetName`, `-TokenInformation`. batchUpdate
`repeatCell` setting each cell's bool to false. Uses `Get-SheetIdByName` +
`Convert-CellToIndex`.
