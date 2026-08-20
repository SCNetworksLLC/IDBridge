# IDBridge Function Reference

Every module function, grouped by layer. One entry each: purpose, key params, return
shape, notable deps/external calls. For the overall flow see
[architecture.md](architecture.md).

Functions marked 🔒 are **internal** (module `Private\`, not in `FunctionsToExport`):
the sync pipeline's planners, target-data readers, and directory writers, called only by
`Invoke-IDBridge` and free to change between releases. Everything unmarked is the
supported public surface — what an admin or plugin author calls directly. (To reach an
internal function for testing: `& (Get-Module IDBridge) { <function> ... }`.)

Legend: 🌐 = makes external API/cmdlet calls · 🧮 = pure decision/compute (no writes) ·
🔒 = internal, not exported.

---

## Core

### `Invoke-IDBridge` 🌐
Top-level orchestrator. **Params:** `-RootPath` (def `C:\IDBridge`), switches `-ReadOnly
-TestRun -SkipADCheck -TraceLogging -SkipAD -SkipGoogle -SkipChangeThreshold
-DisableTelemetry`. Calls
`Initialize-IDBridge`, applies switch overrides, runs the notify-only Gallery update
check (a newer release logs a `Warn`; failures are skipped at Trace), acquires the
Google token (when `GoogleToken.Enabled`) from the vault secret
`GoogleAuth-ServiceAccount` → `$script:GoogleHeaders`, then runs the full pipeline (see
architecture.md). **Returns:** nothing; side effects + log push (user-list CSV exports
live in the PostRun export plugin).

### `Initialize-IDBridge` 🌐
Loads config, builds/validates `Paths.*`, sets up logging (+5 MB rotation), imports AD
module, applies feature cascade. No Google auth — that happens in `Invoke-IDBridge`, so a
fresh install initializes cleanly before any secrets exist. **Params:** `-RootPath`,
`-SkipADCheck`/`-SkipAD` (applied to the config before the AD module import — forwarded by
the matching `Invoke-IDBridge` switches, whose other overrides land after initialization).
**Returns:** nothing; sets `$script:IDBridgeConfig`, `$script:Logs`.

### `Install-IDBridge` 🌐(filesystem)
Install scaffold. Creates the runtime folder tree (`Config/Logs/Exports/Plugins/Data/
Vault`) under `-RootPath` (def `C:\IDBridge`), copies the shipped config template
(default `IDBridgeConfig.psd1` — every feature disabled, placeholder site values, safety
brakes on: `ReadOnly`, group `WhatIf`, `ChangeThreshold`), and copies the shipped plugin
templates (module `Templates\Plugins\`) into `<RootPath>\Plugins`. **Never overwrites
anything (no `-Force`)** — existing config and plugin files are skipped with a notice, so
re-running it on an existing install is safe and is how you pick up NEW plugin templates
after a module update. Templates carry a `# TemplateVersion: <n>` marker; when a skipped
file's shipped template is newer than the installed copy, the skip notice adds a
"newer template available" pointer (compare and port changes by hand — site edits are
never touched). Needs no initialized state (`Write-Host` only, no `Write-Log`);
run it before `Initialize-IDBridge` on a fresh install. **Params:** `-RootPath`.
**Returns:** nothing; prints what it created.

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

### `Send-IDBridgeTelemetry` 🔒 🌐
Posts one anonymous usage event per run to the IDBridge Pulse ingest endpoint from the
`finally` block of `Invoke-IDBridge` (see [PRIVACY.md](../PRIVACY.md)). **Params:**
`-Success` (mandatory bool), `-DurationSeconds -ManagedCount -CreateCount -UpdateCount
-DeactivateCount -GroupAddCount -GroupRemoveCount -WriteFailureCount` (ints; the action
counts are actual applied successes, the failure count is failures — all aggregated from
the run's per-write results), `-RunError` (ErrorRecord — Enhanced tier extracts exception
*class* + throwing *function* name only, never the message). Tier from `Telemetry.Tier`
(missing = `Basic`, unrecognized = `Off`); logs the exact payload at Trace; sends with a
10 s timeout, no retries, all errors swallowed — can never affect the run. **Returns:** nothing.

### `Invoke-PostRunPlugins` 🔒 🌐
Discovers\runs the `Type = 'PostRun'` plugins from `$IDConfig.Plugins`, called from the
`finally` block of `Invoke-IDBridge` after telemetry and before the log push — on every
run, including failed and ReadOnly runs. Same load steps as `Invoke-SourcePlugins`
(file check, dot-source, `Get-Command`, warn + disable on failure) but invokes each plugin
as `& <Function> -RunResult <RunResult>` (SecureStrings already scrubbed to `$null`), and
each invocation is isolated in its own try/catch (Warn, next plugin still runs). Never
throws. **Params:** `-RunResult` (mandatory). **Returns:** nothing. See [plugins.md](plugins.md).

### `Get-IDBridgeSiteID`
Returns the install's telemetry SiteID from `<ConfigRoot>\IDBridgeSiteID.json`, generating
a random GUID (plain-text file, deliberately unencrypted/non-secret) on first use or when
the file is invalid. Only transmitted at the Enhanced tier; used to claim the install in
the Pulse dashboard. Delete the file when cloning a config to a new install.

### `Test-IDBridgeUpdateAvailable` 🔒 🌐
No params. Queries the PowerShell Gallery for the latest stable IDBridge release (10 s
timeout) and logs a `Warn` when a newer one exists ("run `Update-Module IDBridge`"), Trace
when current. Notify-only — never installs anything. Failures throw to the caller
(`Invoke-IDBridge` swallows them at Trace). **Returns:** `[bool]`.

### `Get-IDBridgeTemplateVersion` 🔒
**Params:** `-Path`. Reads the `# TemplateVersion: <n>` marker from a template file.
**Returns:** `[int]`, or `$null` when the file has no marker. Powers `Install-IDBridge`'s
"newer template available" notice; uses no module state or `Write-Log` (it runs before
initialization).

### `Add-IDBridgeWriteResult` 🔒
**Params:** `-Directory {AD|Google}`, `-Action {Create|Update|Rename|Move|Deactivate|
GroupAdd|GroupRemove}`, `-PersonID`, `-Target`, `-Success` (bool), `-ErrorMessage`.
Appends one structured record to the run's write-result buffer (`$script:WriteResults`,
reset by `Initialize-IDBridge`) — the source of the RunResult `Applied` list and the
actual-outcome telemetry counts. No return.

### `Add-IDBridgeGoogleBatchResult` 🔒
**Params:** `-Action`, `-Requests`, `-Responses`, `-IdentityMap` (ContentId →
`@{ PersonID; Target }`). Matches each Google batch request to its response part by
ContentId and records one write result per request via `Add-IDBridgeWriteResult` (missing
response part or status ≥ 400 ⇒ failure). No return.

### `Hide-IDBridgeSecureString` 🔒 🧮
**Params:** `-InputObject`. Walks the RunResult object graph (hashtables, lists,
PSCustomObjects; cycle-safe) and replaces every `[SecureString]` with `$null`, in place —
type-driven, so new credential fields are covered automatically. Called by
`Invoke-IDBridge` just before `Invoke-PostRunPlugins`. No return.

### `New-Passphrase` 🌐
Deterministic passphrase generator backed by Keysmith (see [keysmith.md](keysmith.md)).
**Params:** `-Nonce` (SecureString), `-Username` (string/array), `-Mode {words|verbnoun}`,
`-WordCount` (2–6, def 3), `-AuthToken` (SecureString, required — throws when absent; sent
as the `x-api-key` header — the Static Web App proxy overwrites `Authorization`), `-Rev`
(1–99, optional — pin a word-list revision; omit for the server's latest), `-FunctionUrl`
(def `https://keysmith.scnlabs.net`). POSTs to `<FunctionUrl>/api/generate` and logs the
word-list rev used on every call. **Returns:** phrase string(s).

### `Get-StudentGrade`
**Params:** `-gradYear` (2000–2099), `-gradeAdvanceDate` (`MM-dd` rollover date). **Returns:**
grade code (`12`..`01`, `KG`, `K4`, `PK`, or `GD`) from graduation year vs. the school-year
rollover; `$null` when the year falls outside the computed grade window (a year outside
2000–2099 throws at parameter binding).

### `Format-IDBridgeName`
**Params:** `-Name` (pipeline-friendly). Title-cases a name, capitalizing after spaces,
hyphens, and apostrophes (`JOSHUA MOIN`→`Joshua Moin`, `O'BRIEN`→`O'Brien`); null/empty passed
through. Can't infer intentional internal caps (`McDonald`→`Mcdonald`). The Skyward plugin uses
it on `NameFirst`/`NameLast`; paired with the update functions' case-sensitive name compare, the
casing fix reaches existing accounts too.

### `Remove-IDBridgeDuplicateID` 🔒 🧮
**Params:** `-SourceData` (nullable/empty allowed). Two passes: drop records flagged
`ADDuplicateIDStatus`/`GoogleDuplicateIDStatus`, then drop *all* records sharing a
duplicate `personID`. **Returns:** array (guaranteed).

### `Show-GroupsNotProcessed` 🔒 🧮
**Params:** `-Directory` (`AD`/`Google`, mandatory — log prefix), `-ProposedGroups`,
`-TargetGroups`. Trace-logs one line listing the proposed groups missing from the target.
No return.

### `Test-IDBridgeChangeThreshold` 🔒 🧮
**Params:** `-Directory` (`AD`/`Google`, log context), `-ChangeCount`, `-PopulationCount`,
`-ThresholdPercent` (0–100). Computes `ChangeCount / PopulationCount` as a percentage and flags
whether it exceeds `ThresholdPercent`; a `PopulationCount` of 0 is **skipped** (logged Warn, not
a breach). Pure compute + log — the caller (`Invoke-IDBridge`) decides whether to abort.
**Returns:** `[pscustomobject]@{ Directory; ChangeCount; PopulationCount; Percent; Exceeded;
Skipped }`. Used by the change-volume safety guard between the compute and execute regions.

### `Export-IDBridgeDirectoryToSheet` 🌐
One-time onboarding tool: seeds the staff source sheet from the current directory state.
**Params:** `-SpreadsheetId` (mandatory), `-SheetName` (def `StaffSeed-<yyyy-MM-dd>`),
`-GroupsSheetName` (def `GroupsSeed-<yyyy-MM-dd>`) — throws if either tab already exists,
never appends/overwrites — `-ADSearchBase` / `-GoogleOrgUnitPath`
(one or more subtree scopes each — a user under any of them is included; trailing slashes on
Google OU paths are normalized away; **no config default** — a directory is fetched only when its scope is named,
and an omitted scope is skipped entirely rather than failing, so a Google-only run never touches
or requires AD and vice versa; at least one is required). Pulls `Get-TargetDataAD` and/or
`Get-TargetDataGoogle`, merges per person by UPN=primaryEmail, and writes one row per person in the staff sheet
layout plus review-helper columns (`InAD`/`InGoogle`/`ADEnabled`/`GoogleSuspended`/
`ADOrgUnit`/`GoogleOrgUnit`). All rows get `Process=FALSE`; `PersonType`/`Word` are left
blank (nothing derived from OU names); `ApplicationGroups` is the de-duped dump of current
AD group names and `EmailGroups` the same for Google group names; users disabled/suspended
in **every** directory they exist in get yesterday's date as `TerminationDate` (mixed state
⇒ Warn, treated active). PersonID = AD `EmployeeID`, falling back to the Google externalId
(mismatch ⇒ Warn, AD wins); an optional `-PersonIDCsv` (CSV with `ID` and `Username` columns,
e.g. a SIS export, matched case-insensitively on Username) fills in `PersonID` when the
directories carry none — a directory ID wins a CSV mismatch (⇒ Warn). Also writes a
`GroupsSeed-<yyyy-MM-dd>` tab listing the distinct
group names in use — Google groups under `Email` in column A, AD groups under `Application`
in column C — as the source range for multi-select group dropdowns on the staff sheet.
Requires `Initialize-IDBridge` + `Connect-IDBridgeGoogle` first. **Returns:**
`@{ SpreadsheetId; SheetName; GroupsSheetName; RowsWritten }`.

### `Approve-IDBridgeNameMismatch`
Onboarding tool: interactive console review of source/directory name mismatches, run by hand —
never called by the pipeline. **Params:** `-RootPath` (def `C:\IDBridge`), `-SkipAD`,
`-SkipGoogle`. Gathers the same source and directory data the pipeline would
(`Initialize-IDBridge` → source plugins → target data → dedupe → overrides), finds every
unlinked source user whose username is taken by an account with a **different name**, and walks
them one at a time showing both names side by side (`[A]pprove / [S]kip / [Q]uit`). Approving
records the decision to `<DataRoot>\ApprovedNameMismatches.csv` (PersonID, Directory, Account,
SourceName, DirectoryName, ApprovedDate) — **no directory writes happen here**; the next
`Invoke-IDBridge` run links the approved account via the `Get-*UsersToSetEmployeeID` functions
and the normal update pass then sets the EmployeeID and **renames the account to the source
(SIS) name** under all the usual gates (ReadOnly, ChangeThreshold). Each approval saves as it is
made (quitting loses nothing); AD and Google are approved independently; an approval is honored
only while the account's username and directory name still match what was approved — a drifted
account shows up for re-approval (replacing its old row). Warns when `Debug.testRun` is on
(capped source data ⇒ incomplete mismatch set). **Returns:**
`@{ Reviewed; Approved; Skipped; FilePath }`.

### `Get-IDBridgeApprovedNameMismatches` 🔒
No params. Loads `<DataRoot>\ApprovedNameMismatches.csv` (the decisions recorded by
`Approve-IDBridgeNameMismatch`). **Returns:** hashtable `"<Directory>|<PersonID>"` → approval
row; empty when the file doesn't exist. Consumed by the two `Get-*UsersToSetEmployeeID`
functions.

> For a deployment with **no** directory data to seed from, start from the published source-sheet
> template (copy link: <https://docs.google.com/spreadsheets/d/1OUlm-5WGce_x2z0L1dM2kD8Ejk_f3RNF3EC8sa6uHhE/copy>) instead — it ships the source
> and override tabs pre-built with tables, Process checkboxes, a TerminationDate date column, a
> Groups reference tab, and multi-select group dropdowns. Point the source plugin's sheet range at
> the copied spreadsheet.

---

## Secrets

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
e.g. the gMSA, granted private-key read via `Grant-IDBridgeCertificatePrivateKeyAccess`; machine
store only). Creates the self-signed Document Encryption certificate the `Cms` provider needs
(non-exportable RSA 3072). **Returns:** the certificate; put its thumbprint in
`Secrets.Cms.Thumbprint`.

### `Grant-IDBridgeCertificatePrivateKeyAccess` 🌐
**Params:** `-Thumbprint` (mandatory; certificate in `Cert:\LocalMachine\My`), `-Identity`
(mandatory account, e.g. `'DOMAIN\gMSA-IDBridge$'`). Adds a read ACE for the account on the
certificate's private-key file (under `%ProgramData%\Microsoft\Crypto`) — what an account needs
to decrypt Cms secrets or authenticate to Azure Key Vault with the cert. Same grant
`New-IDBridgeSecretCertificate -GrantRead` does at creation time, for a certificate that
already exists. Machine store only; needs elevation. **Returns:** nothing.

### `Get-IDBridgeSecretInfo` 🌐(AzKeyVault)
No params. Lists every vault envelope as `Name / Provider / ProtectedTo / Created / Path` —
never values. With the `AzKeyVault` provider, lists the Key Vault's secrets instead (paged
via `nextLink`; includes everything the app registration can see in that vault).

### `Remove-IDBridgeSecret` 🌐(AzKeyVault)
**Params:** `-Name` (mandatory). Deletes the secret's envelope file — or, with the
`AzKeyVault` provider, DELETEs it from the Key Vault. Throws if absent.

### `Resolve-IDBridgeCmsCertificate` 🔒
No params. Resolves the Document Encryption certificate the `Cms` provider encrypts with:
`Secrets.Cms.Thumbprint` when configured, else exactly one unexpired `CN=IDBridge Secrets`
certificate in the LocalMachine/CurrentUser My stores. Throws pointing at
`New-IDBridgeSecretCertificate` (none found) or at configuring the thumbprint (ambiguous
match). **Returns:** the certificate.

### `Import-IDBridgeDpapiNGType` 🔒
No params. Compiles the `[IDBridge.DpapiNG]` P/Invoke wrapper over `ncrypt.dll`
(`NCryptCreateProtectionDescriptor`/`NCryptProtectSecret`/`NCryptUnprotectSecret`) used by
the `DpapiNG` provider — once per session; later calls are no-ops. No return.

### `Get-IDBridgeAzKeyVaultContext` 🔒 🌐
No params. Validates the `Secrets.AzKeyVault` config block and returns
`@{ VaultUri; ApiVersion; Headers }` for the Key Vault REST calls. The bearer token (from
`Get-IDBridgeAzureAuthToken`) is cached script-scoped for the session and refreshed 5
minutes before expiry.

### `Get-IDBridgeAzureAuthToken` 🔒 🌐
**Params:** `-ClientId`, `-TenantId`, `-CertThumbprint`, `-Scope` (all mandatory). OAuth2
client-credentials flow with a certificate credential: builds a signed JWT client
assertion (RS256, `x5t` from the cert hash) and exchanges it at the tenant's v2.0 token
endpoint. **Returns:** the token response (access token + expiry).

---

## Source

### `Invoke-SourcePlugins` 🔒 🌐
Discovers/runs plugins from `$IDConfig.Plugins` (skipping `Type = 'PostRun'` entries —
those run via `Invoke-PostRunPlugins` at end of run). For each enabled entry: verifies
`<PluginsRoot>\<Function>.ps1` exists, dot-sources it, confirms the function via
`Get-Command`, invokes with no args. Source results are passed through
`Test-IDBridgeSourceData` before collection; when `Debug.testRun` is set, each source
plugin's validated output is capped at the first 10 records. **Returns:** `@{ SourceData; OverrideData }`
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
(safety-net `PersonID`/`IDBActive`; cross-field: if `ProvisionAD` → target + trash OUs +
`ADKey`-or-`ADPassphraseAPI`, same for `Google*`); drops failures with a `Warn` (plugin + reasons),
keeps the rest. **Returns:** the valid records as an array. Called per source plugin inside
`Invoke-SourcePlugins`.

### `Get-SourceDataGSheet` 🌐
**Params:** `-sheetID`, `-sheetRange`, `-userCount`, `-userCountSafetyPercentage` (def 75).
Reads a sheet via `Get-GoogleSheetData`, validates required columns, enforces a count
safety floor (counting only `PersonID`-populated rows), returns rows where `Process='TRUE'`
that carry every required value (only `TerminationDate` may be blank; incomplete rows are
dropped with a log line). **Returns:** array of row objects.

### `Get-SourceDataSkywardSMS` 🌐
**Params:** `-ClientId`, `-ClientSecret`, `-TokenUrl`, `-BaseUrl`, `-ExcludeEntityIDs`,
`-SafetyCheckCount`, `-SafetyCheckPercentage`. OAuth2 client-credentials → OneRoster
`/schools/{id}/students` (paginated). Dedupes by `NameID`, enriches with school names +
`LastSeen`, merges prior-run state CSV in `DataRoot`. **Returns:** student records.

### `Get-SourceDataInfiniteCampus` 🌐
**Params:** `-ClientId`, `-ClientSecret`, `-TokenUrl`, `-BaseUrl`,
`-ExcludeSchoolIdentifiers` (optional), `-SafetyCheckCount`, `-SafetyCheckPercentage`.
OAuth2 → OneRoster `/schools` + `/students` (paginated). Normalizes to `SourcedId/LocalID/
InternalID/NameFirst/NameLast/Email/Role/SchoolName/Grade/Status/...`, drops excluded
schools, enforces the count safety floor, stamps `LastSeen`, merges prior-run state CSV
in `DataRoot` (keyed by `SourcedId`). **Returns:** student records.

### `Merge-IDBridgeOverrideData` 🔒 🧮
**Params:** `-SourceData`, `-OverrideData`. Applies override rows by `personID`: non-empty
scalar values overwrite; `AddGroup`/`RemoveGroup` mutate `GroupsProposed`; `PersonID` and
null/blank values skipped. **Returns:** mutated source array.

---

## Target 🔒

### `Get-TargetDataAD` 🔒 🌐
No params. Pulls all AD users (rich property set incl. `EmployeeID`, `MemberOf`,
`extensionAttribute1-5`), groups (minus `AD.groupsExcluded` name patterns — excluded groups
are invisible to all group processing), OUs; resolves `MemberOf`→names into `CurrentGroups`;
detects duplicate `EmployeeID`s; builds `LookupByID` keyed by EmployeeID. **Returns:**
`@{ Users; Groups; OrgUnits; DuplicateUsers; LookupByID }`.

### `Get-TargetDataGoogle` 🔒 🌐
No params. Pulls all Google users (via `Get-GoogleData`), groups (minus
`Google.groupsExcluded` email patterns, default `classroom_teachers@*` — excluded groups
are invisible to all group processing), and OUs; fetches group members **in parallel** (throttle 10) into
`CurrentGroups`; enumerates license assignments per `Google.licenseProductIds` product into
`CurrentLicenses` (skipped when `enableLicenseRemoval = $false`); detects duplicate
`externalIds`; builds `LookupByID` keyed by externalID.
**Returns:** `@{ Users; Groups; OrgUnits; DuplicateUsers; LookupByID }`.

### `Add-TargetDataAD` 🔒 🧮
**Params:** `-SourceData`, `-ADData`. For each source record, if `LookupByID[personID]`
hits, attaches `ADObject`, `ADCurrentUserID`, `ADCurrentUserEnabledStatus`,
`ADCurrentGroups`; flags `ADDuplicateIDStatus` when applicable. **Returns:** enriched array.

### `Add-TargetDataGoogle` 🔒 🧮
**Params:** `-SourceData`, `-GoogleData`. As above for Google: `GoogleObject`,
`GoogleCurrentUserID`, `GoogleCurrentUserSuspendedStatus` (true when suspended **or** archived;
`$null` when there is no Google account), `GoogleCurrentGroups`,
`GoogleCurrentLicenses`, `GoogleDuplicateIDStatus`. **Returns:** enriched array.

---

## Active Directory 🔒

> Identity key: **`EmployeeID` = `personID`**. CN convention: `FirstName LastName personID`.
> Per-user targeting: **`ProvisionAD`** (with `IDBActive`) gates these — create/update/groups
> require `IDBActive=true AND ProvisionAD=true`; deactivate fires on `IDBActive=false OR
> ProvisionAD=false`. So a Google-only user (`ProvisionAD=false`) is never created in AD, and an
> existing AD account is deactivated. Setting `IDBActive=false` alone deactivates everywhere.

### `Get-ADUsersToSetEmployeeID` 🔒 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`. For **any unlinked** source user (active or not),
matches an existing AD user by SamAccountName **and** name — so deprovisioned users get linked
and can then be deactivated. A name mismatch is an error and skipped, unless approved via
`Approve-IDBridgeNameMismatch` (honored only while the account still matches the approval;
drifted ⇒ Warn + skip). Unlinked users with no AD account at all are logged at Trace only
(inactive ones with an explicit "nothing to reconcile" message, mirroring
`Get-GoogleUsersToSetEmployeeID`). **Returns:** hashtable
`personID → @{ ID(ObjectGUID); Groups; EnabledStatus; User }`. `Groups` reuses the target
snapshot's exclusion-filtered `CurrentGroups`, so `AD.groupsExcluded` applies to linked
users too (matching the Google side).

### `Get-ADOrgUnitsForProcessing` 🔒 🧮
**Params:** `-UserList`, `-CurrentOrgUnits`. Collects needed OU DNs (+trash) for **active**
(`IDBActive=true`) users, expands ancestors, removes existing, sorts parents-first.
**Returns:** ordered OU DN array.

### `Get-ADUsersToCreate` 🔒 🧮🌐
**Params:** `-UserList`, `-CurrentADUsers`, `-Nonce` (unused — passphrase nonces come from
each record's `ADPassphraseAPI`). **Predicate:** `IDBActive=true` AND
`ProvisionAD=true` AND no `ADCurrentUserID` AND UPN absent from AD. Builds a `New-ADUser` splat
(password from `ADKey` or `ADPassphraseAPI`→`New-Passphrase`). **Returns:** `@{ PersonID; Splat }[]`.

### `Get-ADUsersToUpdate` 🔒 🧮
**Params:** `-UserList`, `-LookupByID`, `-CurrentADUsers`. **Predicate:** `IDBActive=true` AND
`ProvisionAD=true` AND has `ADCurrentUserID` + any delta (name, username — the UPN is written
only as part of a username change, never on its own — EmployeeID, EmployeeNumber/`InternalID`,
office/title/company/dept, description/phone/email, enabled state, employeeType/ext-attr,
passwordNeverExpires, CN, OU). On a username change, a new username/UPN already held by a
**different** account in the `CurrentADUsers` snapshot is logged as an error and the user is
skipped that run (mirrors
`Get-GoogleUsersToUpdate`'s primaryEmail collision check). Name comparisons are
**case-sensitive** (`-cne`) so a casing fix from the plugin (e.g. ALL-CAPS→Title-Case) is
applied. **Returns:** `@{ UpdateList; RenameList; MoveList }` (items carry `CN` +
`PersonID` for write-result attribution).

### `Get-ADUsersToDeactivate` 🔒 🧮
**Params:** `-UserList`. **Predicate:** `(IDBActive=false OR ProvisionAD=false)` AND
`ADCurrentUserEnabledStatus=true`. **Returns:** user objects to disable.

### `Get-ADUserGroupsToUpdate` 🔒 🧮
**Params:** `-UserList`, `-CurrentADGroups`. Diffs `GroupsProposed` vs `ADCurrentGroups`
(adds must exist in AD). **Returns:** `@{ Add; Remove }` (each `@{PersonID; ADCurrentUserID;
Groups}`).

### `New-IDBridgeADOrgUnit` 🔒 🌐
**Params:** `-OrgUnit` (DN). Parses DN → `New-ADOrganizationalUnit`. Throws on failure —
`Invoke-IDBridge` treats a failed OU creation as fatal and aborts the run.

### `Disable-IDBridgeADUser` 🔒 🌐
**Params:** `-User`, `-GroupRemovalProcessingStatus`. Disables account, stamps `Division`
with timestamp, moves to trash OU, and (if flag) removes all current groups — each removal
recorded as its own `GroupRemove` write result; a failed group is logged and skipped.
Disable/move failures return the ErrorRecord (the caller records the `Deactivate` result).

---

## Google Workspace

> Identity key: **`externalIds` (type `organization`).value = `personID`**.
> All write functions get auth via `Get-GoogleHeaders` and hit the Admin SDK Directory API
> base `https://admin.googleapis.com/admin/directory/v1/` (exceptions:
> `Remove-IDBridgeGoogleUserLicense` calls the Licensing API, `Push-LogsToSheet` the
> Sheets API).
> Per-user targeting mirrors AD via **`ProvisionGoogle`**: create/update/groups need
> `IDBActive=true AND ProvisionGoogle=true`; deactivate fires on `IDBActive=false OR
> ProvisionGoogle=false`.

### `Get-GoogleData` 🔒 🌐
**Params:** `-GoogleHeaders`, `-APIUri`. Generic paginated GET (follows `nextPageToken`,
appended with `?`/`&` as the URI requires), consolidates the primary collection.
**Returns:** combined array.

### `Get-GoogleApiAccessToken` 🔒 🌐
**Params:** `-ServiceAccountKeyPath` or `-ServiceAccountKeyJson`, `-Scope`. Builds +
RS256-signs a JWT issued to the service account itself (no `sub` claim / impersonation),
exchanges it at `https://oauth2.googleapis.com/token`. **Returns:**
`@{ Authorization='Bearer …'; Accept='application/json' }`.

### `Get-IDBridgeGoogleScope` 🔒
No params. Returns the space-separated OAuth scope string for the token request — Admin
SDK directory user/orgunit/group + Sheets, plus `apps.licensing` unless
`Google.enableLicenseRemoval = $false`. The scope list is a property of the module's code
(which APIs it calls), not site configuration.

### `Get-GoogleUsersToSetEmployeeID` 🔒 🧮
**Params:** `-UserList`, `-GoogleUsers`. Matches **any unlinked** source user (active or not)
to existing Google users by primaryEmail+name. A name mismatch is an error and skipped, unless
approved via `Approve-IDBridgeNameMismatch` (honored only while the account still matches the
approval; drifted ⇒ Warn + skip). Unlinked users with no Google account at all are
logged at Trace only (inactive ones with an explicit "nothing to reconcile" message — inactive
source rows with no account are expected and recur until the row leaves the source feed).
**Returns:** hashtable `personID → @{ ID; Groups; SuspendedStatus; User }`.

### `Get-GoogleOrgUnitsForProcessing` 🔒 🧮
**Params:** `-UserList`, `-CurrentOrgUnits`. Collects needed OU paths (+trash) for
**active** (`IDBActive=true`) users, expands ancestors (`/A/B/C`→`/A`,`/A/B`,`/A/B/C`),
removes existing, sorts so parents precede children (lexicographic — a parent path
prefixes its children). **Returns:** ordered OU path array.

### `Get-GoogleUsersToCreate` 🔒 🧮🌐
**Params:** `-UserList`, `-GoogleUsers`. **Predicate:** `IDBActive=true` AND
`ProvisionGoogle=true` AND no `GoogleCurrentUserID` AND UPN absent from Google. Builds create
splat (password from `GooglePassphraseAPI`→`New-Passphrase` or `GoogleKey`; skips if neither;
honors `GoogleChangePasswordAtLogon`). **Returns:** `@{ UPN; PersonID; Splat }[]`.

### `Get-GoogleUsersToUpdate` 🔒 🧮
**Params:** `-UserList`, `-LookupByID`, `-GoogleUsers`. **Predicate:** `IDBActive=true` AND
`ProvisionGoogle=true` AND linked + delta in primaryEmail (with alias-conflict handling →
`RemoveAlias`), externalId, name, dept/title, suspended/archived state (archived rehires are
unarchived; `ForceDisable` suspends — the temporary block, never an archive), or OU
(unless `GoogleOUOverride`). **Returns:** `@{ UPN; PersonID; Splat }[]` only for changed users.

> **Alias removal on renames — exact scope.** `RemoveAlias` is set only when ALL of these
> hold: the user is being *renamed* (desired UPN ≠ current primaryEmail), the new UPN is
> *not* anyone's primary email (that case logs an error and skips the user's **entire
> update** for the run, not just the rename), and the new UPN
> *is* currently on some user as an **alias**. At execute time exactly that one alias is
> deleted from its holder (refused if it's actually their primary) so the rename PUT doesn't
> 409 — no other aliases on anyone are ever touched. The conflict is logged as a warning at
> decide time, so ReadOnly runs show which alias would be stripped from whom. Note Google
> automatically keeps the *old* primary email as an alias on a renamed account; IDBridge does
> not clean those up, and they are the usual source of these conflicts (e.g. a name-change
> rename freeing an address a later hire should get). The alias holder can be the renamed
> user themselves (renaming back to an address Google kept as their own alias) — that works.

### `Get-GoogleUsersToDeactivate` 🔒 🧮
**Params:** `-UserList`. **Predicate:** `(IDBActive=false OR ProvisionGoogle=false)` AND
`GoogleCurrentUserSuspendedStatus=false` (that property is true when the account is suspended
**or** archived, so pre-archive suspends are grandfathered). The deactivate step **archives**
the account (base Education license self-releases). Logs the paid licenses the step will remove
(from `GoogleCurrentLicenses`) — visible in ReadOnly runs. Also logs when the deactivate step
will set the personID externalId: accounts matched by UPN+name have no externalId yet, and the
update list only covers active users, so the deactivate write persists the link (otherwise the
account would be re-matched every run). **Returns:** user objects.

### `Get-GoogleUserGroupsToUpdate` 🔒 🧮
**Params:** `-UserList`, `-GoogleGroups` (nullable). Diffs proposed vs current groups
(adds must exist in Google; membership compared by each group's real email from
`GoogleGroups` — a group's email does not always match its name). **Returns:** `@{ Add; Remove }`.

### `Get-GoogleUsersOrphaned` 🧮
**Params:** `-UserList`, `-GoogleUsers`, `-TrashOU`. Finds Google users whose ID isn't in
source. **Returns:** `@{ GoogleCurrentUserID; GoogleOrganizationalUnitTrash; Groups }[]`.
*(Not currently called by `Invoke-IDBridge`; available for orphan cleanup.)*

### `New-IDBridgeGoogleUser` 🔒 🌐
**Params:** `-PrimaryEmail`, `-PersonID`, `-FirstName`, `-LastName`, `-Building`,
`-JobTitle`, `-OrgUnitPath`, `-Password` (SecureString), `-ChangeAtNextLogin`,
`-AsBatchRequest`. POST `/users/`. **Returns:** API user object (has `.ID`), or with
`-AsBatchRequest` the request descriptor for `Invoke-GoogleBatchRequest` (ContentId =
primaryEmail, so the new ID can be matched back from the batch response).

### `Update-IDBridgeGoogleUser` 🔒 🌐
**Params:** `-GoogleUserID` + any of `-PrimaryEmail -Suspended -Archived -PersonID -FirstName
-LastName -Building -JobTitle -OrgUnitPath -Password -ChangeAtNextLogin -RemoveAlias
-AsBatchRequest`. PUT `/users/{id}` with only changed fields; `RemoveAlias` does a lookup +
DELETE on the alias (always immediately, even with `-AsBatchRequest`). With
`-AsBatchRequest` returns the request descriptor for `Invoke-GoogleBatchRequest` instead of
calling the API. Used for updates, moves, renames, and archive-to-trash deactivations
(`-Suspended` remains for the temporary `ForceDisable` block).

### `Invoke-GoogleBatchRequest` 🔒 🌐
**Params:** `-Requests` (`@{ Method; Path; Body; ContentId }[]`), `-BatchUri` (def the
Directory API batch endpoint). Sends the requests as `multipart/mixed` batch POSTs, 50 per
round trip, and parses the multipart response manually. Per-item failures are logged and
returned, never thrown. Google doesn't guarantee execution order inside a batch, so callers
must not mix order-dependent calls (`Invoke-IDBridge` sends deactivates, updates, and
creates as three sequential batches). Batching cuts round trips, not quota. **Returns:**
`@{ ContentId; StatusCode; Body }[]`.

### `New-IDBridgeGoogleOrgUnit` 🔒 🌐
**Params:** `-OrgUnit` (path). POST
`/customer/<Google.customerID>/orgunits` with name + parentOrgUnitPath (the real customer
ID from config — `my_customer` doesn't resolve for the service account's own token).
Logs then throws on failure — `Invoke-IDBridge` treats a failed OU creation as fatal.

### `Update-GoogleGroupMembers` 🔒 🌐
**Params:** `-GroupEmail`, `-PersonID`, `-UpdateType {Add|Remove}`, `-AsBatchRequest`,
`-ContentId` (def `<PersonID>|<GroupEmail>`). Add → POST `/groups/{email}/members` (role
MEMBER); Remove → DELETE `/groups/{email}/members/{id}`. With `-AsBatchRequest` returns a
descriptor for `Invoke-GoogleBatchRequest` instead of calling the API — `Invoke-IDBridge`
sends all membership adds, removes, and deactivate group-strips as three separate batches
(order inside one batch isn't guaranteed, so change types don't share a batch).

### `Connect-IDBridgeGoogle` 🌐
No params. Reads the `GoogleAuth-ServiceAccount` vault secret, validates the `private_key`,
exchanges a JWT issued to the service account **itself** (no impersonation — authorization
comes from the SA's `IDBridge` Workspace admin role) via `Get-GoogleApiAccessToken`, and
sets `$script:GoogleHeaders` plus the script-scoped SA email and GCP project ID
(`Get-IDBridgeGoogleServiceAccountEmail` / `Get-IDBridgeGoogleProjectId`). Called by
`Invoke-IDBridge` at run start (when
`GoogleToken.Enabled`); run it standalone to verify the auth chain after seeding the key
or assigning the role (a later API `403` ⇒ role missing/not yet propagated; Sheets `403`
⇒ sheet not shared with the SA). Throws on any failure.

### `Get-IDBridgeGoogleServiceAccountEmail` 🌐
No params. Returns the service account's email (`client_email`). Uses the value stashed by
`Connect-IDBridgeGoogle`; before a connect it falls back to parsing the
`GoogleAuth-ServiceAccount` vault secret (initialized session required, no token needed) —
handy to know which address to share a sheet with.

### `Get-IDBridgeGoogleProjectId` 🌐
No params. Returns the service account's GCP project ID (`project_id`). Same sourcing as
`Get-IDBridgeGoogleServiceAccountEmail`: stashed by `Connect-IDBridgeGoogle`, with a
pre-connect fallback to parsing the `GoogleAuth-ServiceAccount` vault secret — handy to
find the install's Cloud project or to re-run the bootstrap with `-ProjectId`.

### `Initialize-IDBridgeGoogleServiceAccount` 🌐
**Params:** `-ProjectId` (default `idbridge-<random>` with `-CreateProject`), `-ProjectName`
(def `'IDBridge'`), `-CreateProject`, `-ServiceAccountName` (def `'idbridge'`),
`-AccessToken` (SecureString, skips the interactive tiers). One-command Google-side
bootstrap run in the district's tenant: tiered sign-in (token → gcloud → OAuth Playground)
→ org discovery (orchestrates the first-console-visit terms acceptance) → project → enable
APIs → service account → key seeded straight into the vault (never on disk), with a
self-grant/exempt/revoke org-policy dance only if key creation is blocked → creates the
`IDBridge` custom admin role (privileges resolved from `privileges.list`) and assigns it
to the SA (prompting for an `admin.directory.rolemanagement`-scoped token if the bootstrap
token lacks it). Prints the share-the-sheets checklist. **Returns:**
`@{ ProjectId; ServiceAccountEmail; ClientId; RoleId }`. See
[google-bootstrap.md](google-bootstrap.md).

### `Remove-IDBridgeGoogleUserLicense` 🔒 🌐
**Params:** `-UserEmail` (the Licensing API user key), `-Assignments` (the user's license
assignments from the target snapshot, `GoogleCurrentLicenses`; empty = no-op). One DELETE
per assignment, logging every removal by SKU name; per-assignment errors are logged and
don't stop the rest. Called by `Invoke-IDBridge` on the full deactivate (trash) step (on when the config key is
absent; the shipped config template sets `enableLicenseRemoval = $false`) — never on
`ForceDisable` updates.
License discovery happens in `Get-TargetDataGoogle`, so ReadOnly runs show what would be
removed.

### `Push-LogsToSheet` 🔒 🌐
**Params:** `-spreadsheetId`, `-sheetName`. Pulls `Get-IDBridgeLogs`, creates the sheet if
missing, then one atomic batchUpdate: header (new sheets), insert rows, write newest-first,
and trim the bottom past 50,000 rows (keeps the newest 25,000).

---

## Google Sheets helpers

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
**Params:** `-ColumnNumber` (0-based). **Returns:** Excel column letter(s) (0→A, 25→Z, 26→AA).

### `Convert-CellToIndex`
**Params:** `-cell` (e.g. `B2`). **Returns:** `@{ row; column }` (0-based).

### `Set-CheckboxesToFalse` 🌐
**Params:** `-cells`, `-spreadSheetID`, `-sheetName`, `-TokenInformation`. batchUpdate
`repeatCell` setting each cell's bool to false. Uses `Get-SheetIdByName` +
`Convert-CellToIndex`.
