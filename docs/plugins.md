# IDBridge Plugin Guide

Plugins are the **only** place source data enters IDBridge. They live **outside this repo**
in `C:\IDBridge\Plugins\` (= `Paths.PluginsRoot`) and are registered in the `Plugins` array
of [`IDBridgeConfig.psd1`](configuration.md#plugins). Each plugin is a single `.ps1` file
whose function name matches both the config `Function` value and the file name.

There are two kinds:
- **Source** — produce the canonical list of people to manage (one record per person).
- **Override** — modify already-loaded source records, matched by `personID`.

## The contract (`Invoke-SourcePlugins`)

Source of truth: [`src\IDBridge\Public\Source\Invoke-SourcePlugins.ps1`](../src/IDBridge/Public/Source/Invoke-SourcePlugins.ps1).

For each enabled `Plugins` entry, in config order:
1. Skip if `Enabled -ne $true`.
2. Require `<PluginsRoot>\<Function>.ps1` to exist; **dot-source** it (load on failure ⇒
   warn + disable).
3. Require `Get-Command <Function>` to resolve (missing ⇒ warn + disable).
4. Invoke with **no arguments**: `& $plugin.Function`.
5. Append the returned object(s) to `SourceData` or `OverrideData` based on `Type`.

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

Every source record is an ordered `[PSCustomObject]`. Downstream `Get-*To*` functions depend
on these exact property names:

| Property | Notes |
|----------|-------|
| `PersonID` | **Universal join key** (→ AD `EmployeeID`, Google `externalId`). |
| `NameFirst`, `NameLast`, `Username` | Identity basics. |
| `Building`, `JobTitle`, `Company`, `Department` | Org attributes (Building→AD Office/Google dept). |
| `UPN` | Primary email / SamAccountName source, e.g. `username@domain`. |
| `PersonTypeID` | `"1"` = student, `"2"`/`"3"` = staff tiers. Drives the staff-CSV export filter. |
| `InternalID` | Optional secondary id (AD `EmployeeNumber`). |
| `IDBActive` | `$true`/`$false` — the create/update vs. deactivate driver. |
| `GroupsProposed` | Array of desired group **names** (unique). |
| `PersonType` | Human-readable role (used for OU paths + custom-group logic). |
| `ADEnabled` / `GoogleEnabled` | Per-record side toggles. |
| `ADOrganizationalUnit` / `GoogleOrganizationalUnit` | Target OU (DN / path). |
| `ADOrganizationalUnitTrash` / `GoogleOrganizationalUnitTrash` | Deactivation OU. |
| `ADPassPrefix` / `GooglePassPrefix` | Password prefix. |
| `ADChangePasswordAtLogon` / `GoogleChangePasswordAtLogon` | Force change flag. |
| `ADPassphraseAPI` / `GooglePassphraseAPI` | `@{Nonce;Mode;WordCount;AuthToken}` or `$null` (→ `New-Passphrase`). |
| `ADKey` / `GoogleKey` | SecureString password, or `$null` if using the passphrase API. |

Password selection: a `*PasswordType` of `API-PASSPHRASE` populates `*PassphraseAPI` (and
leaves `*Key` null); `WORD`/`FSPIN`/`RANDOM` populate `*Key` as a SecureString. A record with
neither a key nor passphrase config is **skipped** by the create functions (logged Warn).

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

---

## Worked examples (the three shipped plugins)

### `Invoke-PluginGSheetStaff` — Source *(enabled)*
File: `C:\IDBridge\Plugins\Invoke-PluginGSheetStaff.ps1`. Pulls staff from a Google Sheet via
`Get-SourceDataGSheet` (sheet `1qrZ…`, range `Staff`, safety floor 650 @ 75%).
- `UPN = <Username>@marshfieldschools.org`; AD OU `OU=<PersonType>,OU=Staff,<root>`,
  Google OU `/Marshfield/Staff/<PersonType>`; trash OUs use the current year.
- `PersonTypeID = "3"` when `PersonType` is in a leadership/role list (Administrator, Teacher,
  Principal, …), else `"2"`.
- `IDBActive = $false` when `TerminationDate` is in the past.
- AD password type `WORD` (prefix `Mfld-` + sheet `Word`), Google `RANDOM` (GUID). Passphrase
  API only if a type is `API-PASSPHRASE` (reads `ApiKey-PassphraseNonceStaff.txt` +
  `ApiKey-Passphrase.txt` from `UserSecretsRoot`).
- Groups = `Get-CustomStaffGroups -building -personType` (optional, bundled in-file) **+**
  comma-split `ApplicationGroups` **+** `EmailGroups`, de-duplicated. The bundled helper
  encodes Marshfield's group policy (All Staff, building Staff/Faculty/Support, Admin tiers,
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
`Get-SourceDataSkywardSMS` (OneRoster API; client secret from `ApiKey-SkywardSMS.txt`; exclude
entity `800`; safety floor 3700 @ 75%).
- Keeps only students with a `FoodServiceKeyPadNumber > 0`, padded to 4 digits (used as the
  FSPIN password).
- `PersonID/Username = DisplayId`, `InternalID = NameId`,
  `UPN = <DisplayId>@my.marshfieldschools.org`, `PersonTypeID = "1"`.
- Grade from `GradeLevel`; building from a `SchoolID`→name/code map (fallback `000`).
- **Per-grade settings** (`GradeDefaultSettings` + `GradeOverrides`, merged across
  `ValidGrades`) control Enabled state and AD/Google password type/prefix/change-flag. AD OU
  `OU=Grade-<grade>,OU=Students,<root>`, Google `/Marshfield/Students/Grade-<grade>`.
- `IDBActive`: false if not seen within `DaysLastSeen` (14), or if the grade is missing/
  disabled in settings.
- Groups = `Get-CustomStudentGroups -building -grade` (bundled: `Students`, optional
  `<code>_Students`, `Grade-<grade>`) **+** `ApplicationGroups`/`EmailGroups`.

## Authoring a new plugin (checklist)

1. Create `C:\IDBridge\Plugins\Invoke-PluginX.ps1` defining `function Invoke-PluginX { param() … }`.
2. Pull config/secrets via `Get-IDBridgeConfig`; log via `Write-Log`.
3. Return an array of `[PSCustomObject]` matching the schema above (Source) or override schema.
4. Register it in `IDBridgeConfig.psd1` `Plugins` with `Enabled`, `Type`, and `Function`.
5. Test with `Invoke-IDBridge -ReadOnly -TraceLogging` and inspect the log + change lists
   before enabling writes.
