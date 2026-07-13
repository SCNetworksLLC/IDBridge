# IDBridge Plugin Guide

Plugins are the **only** place source data enters IDBridge. They live **outside this repo**
in `C:\IDBridge\Plugins\` (= `Paths.PluginsRoot`) and are registered in the `Plugins` array
of [`IDBridgeConfig.psd1`](configuration.md#plugins). Each plugin is a single `.ps1` file
whose function name matches both the config `Function` value and the file name.

Sanitized **templates** of the shipped plugins are packaged with the module
(`Templates\Plugins\`) and copied into `PluginsRoot` by `New-IDBridgeConfig` on first-run
scaffold (existing files are never overwritten). Templates with placeholder values
(spreadsheet ID / API URLs, domain, OUs) throw until they are edited; the PostRun report
template works as-is. The worked examples below describe the full deployment versions the
templates were derived from.

There are three kinds:
- **Source** — produce the canonical list of people to manage (one record per person).
- **Override** — modify already-loaded source records, matched by `personID`.
- **PostRun** — consume the finished run's results (reports, dashboards, your own
  telemetry). See [the PostRun contract](#the-postrun-contract-invoke-postrunplugins).

## The contract (`Invoke-SourcePlugins`)

Source of truth: [`src\IDBridge\Public\Source\Invoke-SourcePlugins.ps1`](../src/IDBridge/Public/Source/Invoke-SourcePlugins.ps1).

For each enabled `Plugins` entry, in config order (`PostRun` entries are skipped here —
they run at end of run):
1. Skip if `Enabled -ne $true`.
2. Require `<PluginsRoot>\<Function>.ps1` to exist; **dot-source** it (load on failure ⇒
   warn + disable).
3. Require `Get-Command <Function>` to resolve (missing ⇒ warn + disable).
4. Invoke with **no arguments**: `& $plugin.Function`.
5. Append the returned object(s) to `SourceData` or `OverrideData` based on `Type`. When
   `Debug.testRun` is set, each source plugin's validated output is capped at the first 10
   records before collection (after `Test-IDBridgeSourceData` and the plugin's own safety
   floors) — plugins don't need to implement test-run logic themselves.

Returns `[PSCustomObject]@{ SourceData; OverrideData }`. **Throws** if `SourceData` is empty
after all plugins run. A plugin therefore:
- takes **no parameters**,
- pulls everything it needs from `Get-IDBridgeConfig` (paths, secrets, debug flags),
- logs via `Write-Log`,
- returns an array of `[PSCustomObject]` (or `$null`/empty for an override that has nothing).

> Plugins may also define **helper functions in the same file** (e.g.
> `Get-CustomStaffGroups`, `Get-CustomStudentGroups`). Because the file is dot-sourced, those
> helpers become available in the session; the plugin calls them guarded by
> `Test-Path Function:\<Name>` so they're optional.

## Source-plugin output schema

Source plugins **must build each record with the `New-IDBridgeSourceRecord` factory** (splat
your field hashtable: `New-IDBridgeSourceRecord @recordFields`) rather than hand-rolling a
`PSCustomObject`. The factory guarantees one canonical, ordered shape and enforces required
fields + types at construction (core fields are `Mandatory`; `PersonTypeID` is a
`ValidateSet`; `IDBActive`/`ProvisionAD`/`ProvisionGoogle` are `[bool]`; `GroupsProposed` null is
normalized to `@()`). Downstream `Get-*To*` functions depend on these exact property names:

| Property | Notes |
|----------|-------|
| `PersonID` | **Universal join key** (→ AD `EmployeeID`, Google `externalId`). |
| `NameFirst`, `NameLast`, `Username` | Identity basics. |
| `Building`, `JobTitle`, `Company`, `Department` | Org attributes (Building→AD Office/Google dept). |
| `UPN` | Primary email / SamAccountName source, e.g. `username@domain`. |
| `PersonTypeID` | `"1"` = student, `"2"`/`"3"` = staff tiers. Drives the staff-CSV export filter. |
| `InternalID` | Optional secondary id (AD `EmployeeNumber`). |
| `IDBActive` | `$true`/`$false` — the create/update vs. deactivate driver. |
| `GroupsProposed` | `[string[]]` of desired group **names** (unique). |
| `PersonType` | Human-readable role (used for OU paths + custom-group logic). |
| `Description`, `TelephoneNumber`, `EmailAddress` | Optional AD attributes (Description / OfficePhone / mail). Applied only when non-empty (set-but-don't-clear). |
| `PasswordNeverExpires` | `[bool]` (def `$false`) — AD passwordNeverExpires. |
| `ExtensionAttribute2`, `ExtensionAttribute3`, `ExtensionAttribute4` | Optional AD extensionAttributes (1 is set from `PersonTypeID`); reserved for future use. |
| `ForceDisable` | `[bool]` (def `$false`) — override-driven force-disable/suspend. |
| `GoogleOUOverride` | `[bool]` (def `$false`) — override-driven skip of the Google OU move. |
| `IDBActive` | Master "active in source" flag. `$false` ⇒ deactivate in **every** directory. |
| `ProvisionAD` / `ProvisionGoogle` | Per-user directory targeting `[bool]`. With `IDBActive`: create/update when both true; deactivate when either is false. (A young student = `ProvisionAD=$false`.) |
| `ADOrganizationalUnit` / `GoogleOrganizationalUnit` | Target OU (DN / path). |
| `ADOrganizationalUnitTrash` / `GoogleOrganizationalUnitTrash` | Deactivation OU. |
| `ADChangePasswordAtLogon` / `GoogleChangePasswordAtLogon` | Force change flag. |
| `ADPassphraseAPI` / `GooglePassphraseAPI` | `@{Nonce;Mode;WordCount;AuthToken}` or `$null` (→ `New-Passphrase`). |
| `ADKey` / `GoogleKey` | SecureString password, or `$null` if using the passphrase API. |

Password selection: a `*PasswordType` of `API-PASSPHRASE` populates `*PassphraseAPI` (and
leaves `*Key` null); `WORD`/`FSPIN`/`RANDOM` populate `*Key` as a SecureString. A record with
neither a key nor passphrase config is **skipped** by the create functions (logged Warn).

### Validation

`Invoke-SourcePlugins` runs every source plugin's output through `Test-IDBridgeSourceData`
before collecting it. Validation is **filter-and-log**: a record that fails is dropped with a
`Warn` (plugin name + reasons) and the run continues with the rest. Checks are the cross-field
rules the factory can't enforce on its own:

- `PersonID` present and `IDBActive` is a real boolean (safety net for records that bypass the
  factory);
- if `ProvisionAD` → `ADOrganizationalUnit` + `ADOrganizationalUnitTrash` non-empty **and**
  (`ADKey` is a SecureString **or** `ADPassphraseAPI` is a hashtable);
- same for the `Google*` fields.

Building records through `New-IDBridgeSourceRecord` makes most of this pass automatically.
Override plugins are **not** run through this — they self-validate (see
`Invoke-PluginStaffOverride`).

## Override-plugin output schema

Each record needs `PersonID` plus one or more override keys; all unset keys should be `$null`.
Applied by [`Merge-IDBridgeOverrideData`](functions.md#merge-idbridgeoverridedata-).

| Key | Effect |
|-----|--------|
| `NameFirst`, `NameLast`, `Username` | Overwrite the matching source field. |
| `ForceDisable` | `$true` ⇒ force the account suspended/disabled even if active. |
| `GoogleOUOverride` | `$true` ⇒ leave the user's Google OU untouched (skip OU move). |
| `AddGroup` | Append a group name to `GroupsProposed`. |
| `RemoveGroup` | Remove a group name from `GroupsProposed`. |

Override merge skips `PersonID` itself and any null/blank value, so a sparse override row only
touches the fields it sets.

## The PostRun contract (`Invoke-PostRunPlugins`)

Source of truth: [`src\IDBridge\Public\Core\Invoke-PostRunPlugins.ps1`](../src/IDBridge/Public/Core/Invoke-PostRunPlugins.ps1).

PostRun plugins run from the `finally` block of `Invoke-IDBridge`, after telemetry and
before the Google Sheet log push (so their `Write-Log` lines make it into the sheet). They
fire on **every** run — failed and ReadOnly runs included; the RunResult carries
`Success`/`ReadOnly` so the plugin decides what to do. Discovery/loading is identical to
the source contract (file check, dot-source, `Get-Command`, warn + disable on failure),
but each plugin:

- is invoked as `& <Function> -RunResult <RunResult>` — so it declares
  `param([pscustomobject]$RunResult)`,
- is isolated in its own try/catch: a throw is logged as a `Warn` and the remaining
  plugins still run — a PostRun plugin can never fail the run or mask its outcome,
- returns nothing (any output is discarded),
- pulls the **config** from `Get-IDBridgeConfig` (it already reflects the run's switch
  overrides) and the run's **log lines** from `Get-IDBridgeLogs`, same as source plugins —
  neither is duplicated on the RunResult.

### RunResult schema (v1)

One `[pscustomobject]`, grown **additively only** — new properties may appear, existing
ones won't be renamed. Check `SchemaVersion` if you depend on shape.

| Property | Notes |
|----------|-------|
| `SchemaVersion` | `1`. |
| `ModuleVersion` | The IDBridge module version that produced the run. |
| `Success` | `$false` when the run threw a fatal error. |
| `RunError` | The full `ErrorRecord` of a failed run (message + stack — nothing is stripped locally), or `$null`. |
| `RunStart` / `RunEnd` / `DurationSeconds` | Run timing. |
| `ReadOnly` / `TestRun` | Effective mode flags **after** switch overrides — interpret zero counts with these. |
| `Counts` | `Managed/Create/Update/Deactivate/GroupAdd/GroupRemove/Failed` — **actual applied outcomes** aggregated from `Applied` (`Update` includes renames/moves; `Failed` = total failed writes). Zeros in ReadOnly or while a directory's group processing is off/WhatIf — nothing attempted, nothing recorded. |
| `Applied` | One record per **attempted** write: `Timestamp/Directory/Action/PersonID/Target/Success/Error` (`Action` ∈ Create, Update, Rename, Move, Deactivate, GroupAdd, GroupRemove; `Error` `$null` on success). Empty in ReadOnly. |
| `SourceData` | The full enriched source records (incl. matched `ADObject`/`GoogleObject` where found). |
| `ThresholdResults` | Change-volume guard results (`Directory/Percent/Exceeded/Skipped` per enabled directory), empty if the guard is off. |
| `AD` | `Enabled`, `UsersToCreate`, `UsersToUpdate` (keeps its `UpdateList/RenameList/MoveList` shape), `UsersToDeactivate`, `GroupsToUpdate` (keeps its `Add/Remove` shape), `OrgUnitsToCreate`. |
| `Google` | Same shape: `Enabled/UsersToCreate/UsersToUpdate/UsersToDeactivate/GroupsToUpdate/OrgUnitsToCreate`. |

On a failed run the lists that were never computed are empty arrays (`UsersToUpdate`/
`GroupsToUpdate` may be `$null`) — guard accordingly.

Two things to know about the data:

- **SecureStrings are scrubbed.** Every SecureString anywhere in the graph (`ADKey`/
  `GoogleKey`, passphrase-API `Nonce`/`AuthToken`, create-splat passwords) is replaced
  with `$null` before any plugin sees the RunResult. Everything else — names, IDs, UPNs,
  group names — is intact: it's your data on your server, but **think before shipping
  records off the box**; a webhook payload built from counts can't leak a student record.
- **The change lists are *computed* work; `Applied` is what actually happened.** The
  `AD`/`Google` lists are what the run intended; `Applied` records the per-write outcome
  ("did user 1001's update stick?") — filter on `Success -eq $false` for a failure report
  (the shipped report template does this). Two write types are not covered by `Applied`
  and remain log-only: Google license removals and OU creation (an OU failure aborts the
  run anyway).

---

## Worked examples (the shipped plugins)

### `Invoke-PluginGSheetStaff` — Source *(enabled)*
File: `C:\IDBridge\Plugins\Invoke-PluginGSheetStaff.ps1`. Pulls staff from a Google Sheet via
`Get-SourceDataGSheet` (spreadsheet ID + range `Staff`, safety floor 650 @ 75%).
- `UPN = <Username>@yourdistrict.org`; AD OU `OU=<PersonType>,OU=Staff,<root>`,
  Google OU `/YourDistrict/Staff/<PersonType>`; trash OUs use the current year.
- `PersonTypeID = "3"` when `PersonType` is in a leadership/role list (Administrator, Teacher,
  Principal, …), else `"2"`.
- `IDBActive = $false` when `TerminationDate` is in the past.
- AD password type `WORD` (prefix `Temp-` + sheet `Word`), Google `RANDOM` (GUID). Passphrase
  API only if a type is `API-PASSPHRASE` (reads the `ApiKey-PassphraseNonceStaff` +
  `ApiKey-Passphrase` vault secrets via `Get-IDBridgeSecret`).
- Groups = `Get-CustomStaffGroups -building -personType` (optional, bundled in-file) **+**
  comma-split `ApplicationGroups` **+** `EmailGroups`, de-duplicated. The bundled helper
  encodes the district's group policy (All Staff, building Staff/Faculty/Support, Admin tiers,
  All Principals, etc.) via building/person-type allow- and deny-lists.

### `Invoke-PluginStaffOverride` — Override *(enabled)*
File: `C:\IDBridge\Plugins\Invoke-PluginStaffOverride.ps1`. Reads `Get-GoogleSheetData`
(same sheet, range `Override`). Required columns: `PersonID, Type, Value, StartDate, EndDate`.
- Validates `Type` against the allowed override list; invalid ⇒ Warn + skip.
- **Date-gated:** skips rows whose `StartDate` is future or `EndDate` is past, so overrides
  self-activate/expire.
- Emits one normalized record per row with the matched `Type=Value` (and `ForceDisable`/
  `GoogleOUOverride` coerced to `$true`).

### `Invoke-PluginSkywardSMSStudents` — Source *(disabled in config)*
File: `C:\IDBridge\Plugins\Invoke-PluginSkywardSMSStudents.ps1`. Pulls students via
`Get-SourceDataSkywardSMS` (OneRoster API; client secret from the vault secret
`ApiKey-SkywardSMS`; exclude entity `800`; safety floor 3700 @ 75%).
- Pads `FoodServiceKeyPadNumber` to 4 digits when present (used as the FSPIN password); an
  optional commented-out filter drops students without a PIN when a grade uses FSPIN.
- `PersonID/Username = DisplayId`, `InternalID = NameId`,
  `UPN = <DisplayId>@my.yourdistrict.org`, `PersonTypeID = "1"`.
- Grade from `GradeLevel`; building from a `SchoolID`→name/code map (fallback `000`).
- **Per-grade settings** (`GradeDefaultSettings` + `GradeOverrides`, merged across
  `ValidGrades`) control provisioning and AD/Google password type/prefix/change-flag. AD OU
  `OU=Grade-<grade>,OU=Students,<root>`, Google `/YourDistrict/Students/Grade-<grade>`.
- **Per-directory provisioning:** `ProvisionAD = [bool]$GradeSettings.<grade>.AD.Provision` and
  `ProvisionGoogle = [bool]…Google.Provision` — so "younger grades = Google only" is set by adding
  a `GradeOverrides` entry with `AD = @{ Provision = $false }`.
- **Name casing:** `NameFirst`/`NameLast` are run through the module's `Format-IDBridgeName`
  (Skyward returns ALL-CAPS → Title Case). Because the update functions compare names
  case-sensitively (`-cne`), existing accounts get the casing fix too, not just new ones.
- `IDBActive`: false if not seen within `DaysLastSeen` (14), or if the grade is missing/
  disabled in settings.
- Groups = `Get-CustomStudentGroups -building -grade` (bundled: `Students`, optional
  `<code>_Students`, `Grade-<grade>`) **+** `ApplicationGroups`/`EmailGroups`.

### `Invoke-PluginPostRunReport` — PostRun *(works as-is)*
File: `C:\IDBridge\Plugins\Invoke-PluginPostRunReport.ps1`. Writes
`RunSummary-<timestamp>.json` to `Paths.ExportsRoot` after every run: outcome, timing, mode
flags, actual applied counts, an `Applied` section (succeeded/failed write tallies + one
line per failed write), per-directory *proposed* change-list sizes, threshold results, and
the run's `Warn`/`Error` log lines (via `Get-IDBridgeLogs`). Counts, failure lines, and log
lines only — no full user records — so the file is safe to feed a dashboard. The only template with no
placeholders: enable its descriptor and it runs.

### `Invoke-PluginPostRunWebhook` — PostRun *(disabled in config)*
File: `C:\IDBridge\Plugins\Invoke-PluginPostRunWebhook.ps1`. POSTs a compact JSON summary
(success, error text, duration, mode flags, counts — no per-user data) to your own endpoint;
throws until the placeholder URL is edited. Fire-and-forget: 10 s timeout, send failures log
a `Warn` and never affect the run. The starting point for shipping your own telemetry or
alerting ("tell me when the run breaks").

## Authoring a new plugin (checklist)

1. Create `C:\IDBridge\Plugins\Invoke-PluginX.ps1` defining `function Invoke-PluginX { param() … }`
   (for PostRun: `param([pscustomobject]$RunResult)`).
2. Pull config/secrets via `Get-IDBridgeConfig`; log via `Write-Log`.
3. Return an array of `[PSCustomObject]` matching the schema above (Source) or override schema.
   PostRun plugins return nothing — their value is their side effect (report/POST/export).
4. Register it in `IDBridgeConfig.psd1` `Plugins` with `Enabled`, `Type`, and `Function`.
5. Test with `Invoke-IDBridge -ReadOnly -TraceLogging` and inspect the log + change lists
   before enabling writes.
