# IDBridge Function Reference

Every **exported** function (per `IDBridge.psd1` → `FunctionsToExport`), grouped by layer.
One entry each: purpose, key params, return shape, notable deps/external calls. For the
overall flow see [architecture.md](architecture.md).

Legend: 🌐 = makes external API/cmdlet calls · 🧮 = pure decision/compute (no writes).

---

## Core (`src\IDBridge\Public\Core\`)

### `Invoke-IDBridge` 🌐
Top-level orchestrator. **Params:** `-RootPath` (def `C:\IDBridge`), switches `-ReadOnly
-TestRun -SkipADCheck -TraceLogging -SkipAD -SkipGoogle -SkipChangeThreshold`. Calls
`Initialize-IDBridge`, applies switch overrides, acquires the Google token (when
`GoogleToken.Enabled`) from the vault secret `GoogleAuth-ServiceAccount` →
`$script:GoogleHeaders`, then runs the full pipeline (see architecture.md). **Returns:**
nothing; side effects + CSV export + log push.

### `Initialize-IDBridge` 🌐
Loads config, builds/validates `Paths.*`, sets up logging (+5 MB rotation), imports AD
module, applies feature cascade. No Google auth — that happens in `Invoke-IDBridge`, so a
fresh install initializes cleanly before any secrets exist. **Params:** `-RootPath`.
**Returns:** nothing; sets `$script:IDBridgeConfig`, `$script:Logs`.

### `Get-IDBridgeConfig`
Accessor for `$script:IDBridgeConfig`. Throws if called before `Initialize-IDBridge`.

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

### `Format-IDBridgeName`
**Params:** `-Name` (pipeline-friendly). Title-cases a name, capitalizing after spaces,
hyphens, and apostrophes (`JOSHUA MOIN`→`Joshua Moin`, `O'BRIEN`→`O'Brien`); null/empty passed
through. Can't infer intentional internal caps (`McDonald`→`Mcdonald`). The Skyward plugin uses
it on `NameFirst`/`NameLast`; paired with the update functions' case-sensitive name compare, the
casing fix reaches existing accounts too.

### `Remove-IDBridgeDuplicateID` 🧮
**Params:** `-SourceData` (nullable/empty allowed). Two passes: drop records flagged
`ADDuplicateIDStatus`/`GoogleDuplicateIDStatus`, then drop *all* records sharing a
duplicate `personID`. **Returns:** array (guaranteed).

### `Show-GroupsNotProcessed` 🧮
**Params:** `-ProposedGroups`, `-TargetGroups`. Trace-logs each proposed group missing
from the target. No return.

### `Test-IDBridgeChangeThreshold` 🧮
**Params:** `-Directory` (`AD`/`Google`, log context), `-ChangeCount`, `-PopulationCount`,
`-ThresholdPercent` (0–100). Computes `ChangeCount / PopulationCount` as a percentage and flags
whether it exceeds `ThresholdPercent`; a `PopulationCount` of 0 is **skipped** (logged Warn, not
a breach). Pure compute + log — the caller (`Invoke-IDBridge`) decides whether to abort.
**Returns:** `[pscustomobject]@{ Directory; ChangeCount; PopulationCount; Percent; Exceeded;
Skipped }`. Used by the change-volume safety guard between the compute and execute regions.

---

## Secrets (`src\IDBridge\Public\Secrets\`)

### `Get-IDBridgeSecret` 🌐(AzKeyVault)
**Params:** `-Name` (mandatory), `-AsPlainText`. Reads a secret's envelope file
(`<Name>.secret.json`) from the vault folder (`Paths.VaultRoot`) and decrypts it with the
provider the envelope records (`Cms` via `Unprotect-CmsMessage`, `DpapiNG` via the built-in
DPAPI-NG wrapper); when `Secrets.Provider` is `AzKeyVault`, fetches from Azure Key Vault over
REST instead. Throws if the secret is missing (pointing at `Set-IDBridgeSecret`) or can't be
decrypted/read (naming the required key/principal/role). **Returns:** `[SecureString]` (or
`[string]` with `-AsPlainText`). See [secrets.md](secrets.md).

### `Set-IDBridgeSecret` 🌐(AzKeyVault)
**Params:** `-Name` (mandatory), `-Secret` (optional `[SecureString]`; prompts when omitted),
`-InFile` (optional; store a file's raw content, e.g. the Google service-account JSON).
Encrypts with the `Secrets.Provider` from config (`Cms` default; `DpapiNG` uses
`Secrets.DpapiNG.ProtectionDescriptor`, else current-user SID with a `Warn`) and writes the
envelope file to `Paths.VaultRoot`; when the provider is `AzKeyVault`, PUTs the value to the
Key Vault under the same name instead. Re-running with the same `-Name` overwrites.
**Returns:** nothing. See [secrets.md](secrets.md).

### `New-IDBridgeSecretCertificate` 🌐
**Params:** `-Subject` (def `'CN=IDBridge Secrets'`), `-StoreLocation {LocalMachine|CurrentUser}`
(def `LocalMachine`, needs elevation), `-ValidityYears` (def 10), `-GrantRead` (optional account,
e.g. the gMSA, granted private-key read; machine store only). Creates the self-signed Document
Encryption certificate the `Cms` provider needs (non-exportable RSA 3072). **Returns:** the
certificate; put its thumbprint in `Secrets.Cms.Thumbprint`.

### `Get-IDBridgeSecretInfo` 🌐(AzKeyVault)
No params. Lists every vault envelope as `Name / Provider / ProtectedTo / Created / Path` —
never values. With the `AzKeyVault` provider, lists the Key Vault's secrets instead (paged
via `nextLink`; includes everything the app registration can see in that vault).

### `Remove-IDBridgeSecret` 🌐(AzKeyVault)
**Params:** `-Name` (mandatory). Deletes the secret's envelope file — or, with the
`AzKeyVault` provider, DELETEs it from the Key Vault. Throws if absent.

---

## Source (`src\IDBridge\Public\Source\`)

### `Invoke-SourcePlugins` 🌐
Discovers/runs plugins from `$IDConfig.Plugins`. For each enabled entry: verifies
`<PluginsRoot>\<Function>.ps1` exists, dot-sources it, confirms the function via
`Get-Command`, invokes with no args. Source results are passed through
`Test-IDBridgeSourceData` before collection. **Returns:** `@{ SourceData; OverrideData }`
(split by each plugin's `Type`). Throws if no source data gathered. See [plugins.md](plugins.md).

### `New-IDBridgeSourceRecord` 🧮
Canonical factory for a source record — the shape plugins must emit. **Params:** typed,
`Mandatory` core fields (`PersonID`, `NameFirst`, `NameLast`, `Username`, `UPN`, `Building`,
`JobTitle`, `Company`, `PersonType`, `PersonTypeID` [ValidateSet `1`/`2`/`3`], `IDBActive`
[bool], `ProvisionAD`/`ProvisionGoogle` [bool]); optional/defaulted everything else
(`Department`/`InternalID` → `$null`, `GroupsProposed` → `@()`, the AD/Google OU/password
fields). **Returns:** an ordered `PSCustomObject` with the full 35-field contract (incl. optional
AD attributes `Description`/`TelephoneNumber`/`EmailAddress`/`PasswordNeverExpires`/
`ExtensionAttribute2-4`, and the override flags `ForceDisable`/`GoogleOUOverride`). Construction
enforces presence + type; cross-field rules live in `Test-IDBridgeSourceData`.

### `Test-IDBridgeSourceData` 🧮
**Params:** `-InputObject` (records, null/empty ok), `-PluginName`. Validates each record
(safety-net `PersonID`/`IDBActive`; cross-field: if `ProvisionAD` → OU + `ADKey`-or-
`ADPassphraseAPI`, same for `Google*`); drops failures with a `Warn` (plugin + reasons),
keeps the rest. **Returns:** the valid records as an array. Called per source plugin inside
`Invoke-SourcePlugins`.

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
`CurrentGroups`; enumerates license assignments per `Google.licenseProductIds` product into
`CurrentLicenses` (skipped when `enableLicenseRemoval = $false`); detects duplicate
`externalIds`; builds `LookupByID` keyed by externalID.
**Returns:** `@{ Users; Groups; OrgUnits; DuplicateUsers; LookupByID }`.

### `Add-TargetDataAD` 🧮
**Params:** `-SourceData`, `-ADData`. For each source record, if `LookupByID[personID]`
hits, attaches `ADObject`, `ADCurrentUserID`, `ADCurrentUserEnabledStatus`,
`ADCurrentGroups`; flags `ADDuplicateIDStatus` when applicable. **Returns:** enriched array.

### `Add-TargetDataGoogle` 🧮
**Params:** `-SourceData`, `-GoogleData`. As above for Google: `GoogleObject`,
`GoogleCurrentUserID`, `GoogleCurrentUserSuspendedStatus`, `GoogleCurrentGroups`,
`GoogleCurrentLicenses`, `GoogleDuplicateIDStatus`. **Returns:** enriched array.

---

## Active Directory (`src\IDBridge\Public\AD\`)

> Identity key: **`EmployeeID` = `personID`**. CN convention: `FirstName LastName personID`.
> Per-user targeting: **`ProvisionAD`** (with `IDBActive`) gates these — create/update/groups
> require `IDBActive=true AND ProvisionAD=true`; deactivate fires on `IDBActive=false OR
> ProvisionAD=false`. So a Google-only user (`ProvisionAD=false`) is never created in AD, and an
> existing AD account is deactivated. Setting `IDBActive=false` alone deactivates everywhere.

### `Get-ADUsersToSetEmployeeID` 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`. For **any unlinked** source user (active or not),
matches an existing AD user by SamAccountName **and** name — so deprovisioned users get linked
and can then be deactivated. **Returns:** hashtable
`personID → @{ ID(ObjectGUID); Groups; EnabledStatus; User }`.

### `Get-ADOrgUnitsForProcessing` 🧮
**Params:** `-UserList`, `-UserRootOU`, `-CurrentOrgUnits`. Collects needed OU DNs (+trash),
expands ancestors, removes existing, sorts parents-first. **Returns:** ordered OU DN array.

### `Get-ADUsersToCreate` 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`, `-Nonce`. **Predicate:** `IDBActive=true` AND
`ProvisionAD=true` AND no `ADCurrentUserID` AND UPN absent from AD. Builds a `New-ADUser` splat
(password from `ADKey` or `ADPassphraseAPI`→`New-Passphrase`). **Returns:** `@{ PersonID; Splat }[]`.

### `Get-ADUsersToUpdate` 🧮🌐
**Params:** `-UserList`, `-LookupByID`. **Predicate:** `IDBActive=true` AND `ProvisionAD=true`
AND has `ADCurrentUserID` + any delta (name, username/UPN, EmployeeID, office/title/company/
dept, description/phone/email, enabled state, employeeType/ext-attr, passwordNeverExpires, CN,
OU). Name comparisons are **case-sensitive** (`-cne`) so a casing fix from the plugin (e.g.
ALL-CAPS→Title-Case) is applied. **Returns:** `@{ UpdateList; RenameList; MoveList }`.

### `Get-ADUsersToDeactivate` 🧮
**Params:** `-UserList`. **Predicate:** `(IDBActive=false OR ProvisionAD=false)` AND
`ADCurrentUserEnabledStatus=true`. **Returns:** user objects to disable.

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
> Per-user targeting mirrors AD via **`ProvisionGoogle`**: create/update/groups need
> `IDBActive=true AND ProvisionGoogle=true`; deactivate fires on `IDBActive=false OR
> ProvisionGoogle=false`.

### `Get-GoogleData` 🌐
**Params:** `-GoogleHeaders`, `-APIUri`. Generic paginated GET (follows `nextPageToken`),
consolidates the primary collection. **Returns:** combined array.

### `Get-GoogleApiAccessToken` 🌐
**Params:** `-ServiceAccountKeyPath`, `-Scope`, `-TargetUserEmail`. Builds + RS256-signs a
JWT, exchanges it at `https://oauth2.googleapis.com/token`. **Returns:**
`@{ Authorization='Bearer …'; Accept='application/json' }`.

### `Get-GoogleUsersToSetEmployeeID` 🧮
**Params:** `-UserList`, `-GoogleUsers`. Matches **any unlinked** source user (active or not)
to existing Google users by primaryEmail+name. **Returns:** hashtable `personID → @{ ID; Groups;
SuspendedStatus; User }`.

### `Get-GoogleOrgUnitsForProcessing` 🧮
**Params:** `-UserList`, `-UserRootOU`, `-CurrentOrgUnits`. Collects needed OU paths
(+trash), expands ancestors (`/A/B/C`→`/A`,`/A/B`,`/A/B/C`), removes existing, sorts
shallow-first. **Returns:** ordered OU path array.

### `Get-GoogleUsersToCreate` 🧮🌐
**Params:** `-UserList`, `-GoogleUsers`. **Predicate:** `IDBActive=true` AND
`ProvisionGoogle=true` AND no `GoogleCurrentUserID` AND UPN absent from Google. Builds create
splat (password from `GooglePassphraseAPI`→`New-Passphrase` or `GoogleKey`; skips if neither;
honors `GoogleChangePasswordAtLogon`). **Returns:** `@{ UPN; Splat }[]`.

### `Get-GoogleUsersToUpdate` 🧮
**Params:** `-UserList`, `-LookupByID`, `-GoogleUsers`. **Predicate:** `IDBActive=true` AND
`ProvisionGoogle=true` AND linked + delta in primaryEmail (with alias-conflict handling →
`RemoveAlias`), externalId, name, dept/title, suspended state (incl. `ForceDisable`), or OU
(unless `GoogleOUOverride`). **Returns:** `@{ UPN; Splat }[]` only for changed users.

### `Get-GoogleUsersToDeactivate` 🧮
**Params:** `-UserList`. **Predicate:** `(IDBActive=false OR ProvisionGoogle=false)` AND
`GoogleCurrentUserSuspendedStatus=false`. Logs the licenses the deactivate step will remove
(from `GoogleCurrentLicenses`) — visible in ReadOnly runs. **Returns:** user objects.

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

### `Connect-IDBridgeGoogle` 🌐
No params. Reads the `GoogleAuth-ServiceAccount` vault secret, validates the `private_key`,
exchanges the DWD JWT via `Get-GoogleApiAccessToken`, and sets `$script:GoogleHeaders`.
Called by `Invoke-IDBridge` at run start (when `GoogleToken.Enabled`); run it standalone to
verify the auth chain after seeding the key or changing the DWD grant
(`unauthorized_client` ⇒ the DWD client ID/scopes don't match). Throws on any failure.

### `Initialize-IDBridgeGoogleServiceAccount` 🌐
**Params:** `-ProjectId` (default `idbridge-<random>` with `-CreateProject`), `-ProjectName`
(def `'IDBridge'`), `-CreateProject`, `-ServiceAccountName` (def `'idbridge'`),
`-AccessToken` (SecureString, skips the interactive tiers). One-command Google-side
bootstrap run in the district's tenant: tiered sign-in (token → gcloud → OAuth Playground)
→ org discovery (orchestrates the first-console-visit terms acceptance) → project → enable
APIs → service account → key seeded straight into the vault (never on disk), with a
self-grant/exempt/revoke org-policy dance only if key creation is blocked. Prints the
manual DWD checklist. **Returns:** `@{ ProjectId; ServiceAccountEmail; ClientId }`. See
[google-bootstrap.md](google-bootstrap.md).

### `Remove-IDBridgeGoogleUserLicense` 🌐
**Params:** `-UserEmail` (the Licensing API user key), `-Assignments` (the user's license
assignments from the target snapshot, `GoogleCurrentLicenses`; empty = no-op). One DELETE
per assignment, logging every removal by SKU name; per-assignment errors are logged and
don't stop the rest. Called by `Invoke-IDBridge` on the full deactivate (trash) step (on by
default; `enableLicenseRemoval = $false` disables) — never on `ForceDisable` updates.
License discovery happens in `Get-TargetDataGoogle`, so ReadOnly runs show what would be
removed.

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
