# IDBridge Architecture & Execution Pipeline

This is the end-to-end story of a run. Source of truth:
[`src\IDBridge\Public\Core\Invoke-IDBridge.ps1`](../src/IDBridge/Public/Core/Invoke-IDBridge.ps1) and
[`src\IDBridge\Public\Core\Initialize-IDBridge.ps1`](../src/IDBridge/Public/Core/Initialize-IDBridge.ps1).

## Two-stage startup

`Invoke-IDBridge` is the entry point. Its first act is `Initialize-IDBridge -RootPath`,
which prepares all global state:

1. **Load config** — `Import-PowerShellDataFile` of
   `<RootPath>\Config\IDBridgeConfig.psd1` → `$script:IDBridgeConfig`.
2. **Build & validate paths** — computes `Paths.{Root,ConfigRoot,LogsRoot,ExportsRoot,
   PluginsRoot,DataRoot,VaultRoot}`, creating any missing directory.
3. **Logging** — sets `Paths.LogFile = <LogsRoot>\IDBridge.log`, inits the in-memory
   buffer `$script:Logs`, and **rotates the log if it exceeds 5 MB** (renames with a
   timestamp). Writes the run-start marker.
4. **AD module** (if `AD.enabled`) — `Import-Module ActiveDirectory`. On failure it
   throws **unless** `Debug.skipADCheck` is set.
5. **Feature-dependency cascade** — disabling Google/AD also disables their group
   processing.

Note Google auth is **not** part of `Initialize-IDBridge` — a fresh install can therefore
initialize cleanly and seed secrets/run the bootstrap before the Google key exists.

Back in `Invoke-IDBridge`, it then calls `Get-IDBridgeConfig`, applies **runtime switch
overrides** (`-ReadOnly/-TestRun/-SkipADCheck/-TraceLogging/-SkipAD/-SkipGoogle/
-SkipChangeThreshold`), logging each as `OVERRIDE: <key> = <value>` (switches win over the
config file), and **acquires Google auth** (if `GoogleToken.Enabled`) via
`Connect-IDBridgeGoogle`: reads the service-account key JSON from the secret vault
(`Get-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount'`; **no file fallback**), validates
it has a `private_key`, then calls `Get-GoogleApiAccessToken` (JWT → bearer token issued
to the service account **itself** — authorized by its `IDBridge` Workspace admin role, no
impersonation) into `$script:GoogleHeaders`, stashing the SA email alongside
(`Get-IDBridgeGoogleServiceAccountEmail`). An auth
failure throws rather than degrading — disable Google intentionally with
`GoogleToken.Enabled = $false` (`-SkipGoogle` disables processing but still acquires
headers for Sheets plugins and sheet logging).

## The ordered pipeline

Each step below maps to a `#region` block in `Invoke-IDBridge.ps1`. The whole body is
wrapped in `try/catch/finally`; per-user write errors are logged and skipped, but
startup/OU-creation failures `Throw` and abort the run.

```
Invoke-IDBridge
  └─ Initialize-IDBridge ──► $script:IDBridgeConfig / $script:Logs
  └─ apply -switch overrides
  └─ Connect-IDBridgeGoogle (GoogleToken.Enabled) ──► $script:GoogleHeaders
        │
  1. Invoke-SourcePlugins ───────────► $sourceData (Source), $overrideData (Override)
        each Source plugin's output is built via New-IDBridgeSourceRecord and
        passed through Test-IDBridgeSourceData (filter-and-log) before collection
  2. Get-TargetDataGoogle / Get-TargetDataAD ─► $googleData / $adData  (current state)
  3. Add-TargetDataGoogle / Add-TargetDataAD ─► enrich each source record w/ current
                                                state + duplicate flags
  4. Remove-IDBridgeDuplicateID ─────► drop pre-flagged + same-personID dupes (2 passes)
  5. Merge-IDBridgeOverrideData ─────► apply override rows (incl. AddGroup/RemoveGroup)
  6. Show-GroupsNotProcessed ────────► (trace only) warn re: proposed groups missing in target
  7. Match personIDs:
       Get-ADUsersToSetEmployeeID / Get-GoogleUsersToSetEmployeeID
       → link source ↔ existing target user by UPN+name; attach
         *Object / *CurrentUserID / *CurrentGroups / enabled|suspended status
        │
  8. Compute AD change lists (read-only):                    ┐
       Get-ADOrgUnitsForProcessing                           │
       Get-ADUsersToDeactivate                               │  no writes
       Get-ADUsersToUpdate  (→ UpdateList/RenameList/MoveList)│  happen yet
       Get-ADUsersToCreate                                   │
       Get-ADUserGroupsToUpdate (if group processing on)     │
  9. Compute Google change lists (read-only):                │
       Get-GoogleOrgUnitsForProcessing                       │
       Get-GoogleUsersToUpdate                               │
       Get-GoogleUsersToDeactivate                           │
       Get-GoogleUsersToCreate                               │
       Get-GoogleUserGroupsToUpdate (if group processing on) ┘
        │
9b. Change-threshold guard (if ChangeThreshold.Enabled): per directory, count proposed
       lifecycle changes (create/update/rename/move/deactivate) vs the managed root-OU
       population via Test-IDBridgeChangeThreshold; Throw (abort before any writes) if any
       directory exceeds ChangeThreshold.Percentage. Bypass: -SkipChangeThreshold.
        │
 10. EXECUTE AD changes      (only if AD.enabled    AND Debug.readOnly = $false)
       New-IDBridgeADOrgUnit → Disable-IDBridgeADUser → Set-ADUser (update) →
       Rename-ADObject → Move-ADObject → New-ADUser (create) →
       [refresh group list if users created] → Add/Remove group membership
 11. EXECUTE Google changes  (only if Google.enabled AND Debug.readOnly = $false)
       New-IDBridgeGoogleOrgUnit → Update-IDBridgeGoogleUser (archive+trash deactivates,
       + Remove-IDBridgeGoogleUserLicense when enableLicenseRemoval) →
       Update-IDBridgeGoogleUser (update/move/rename) → New-IDBridgeGoogleUser (create) →
       [refresh group list if users created] → Update-GoogleGroupMembers add/remove
        │
 12. Export non-students → <ExportsRoot>\UserList-Staff.csv   (PersonTypeID ≠ "1")
        │
 finally:
 13. Send-IDBridgeTelemetry (unless Telemetry.Tier = 'Off') → one anonymous usage event
       (self-contained try/catch, 10s timeout, no retries — can never affect the run;
       counts are APPLIED work so ReadOnly runs report zeros; see PRIVACY.md)
 14. Push-LogsToSheet (if Logging.GoogleSheetLoggingEnabled) → writes $script:Logs to sheet
```

## Data-object lifecycle

A single source record is a `PSCustomObject` that **accretes properties** as it flows:

1. **From plugins:** normalized fields — `personID`, `NameFirst/NameLast`, `Username`,
   `UPN`, `PersonTypeID`, `IDBActive`, `GroupsProposed`, plus `AD*`/`Google*` OU,
   password, and passphrase fields. (See [plugins.md](plugins.md) for the full schema.)
2. **After `Add-TargetData*`:** `ADObject`/`GoogleObject`, `ADCurrentUserID`/
   `GoogleCurrentUserID`, `ADCurrentGroups`/`GoogleCurrentGroups`,
   `ADCurrentUserEnabledStatus`/`GoogleCurrentUserSuspendedStatus` (true when the Google
   account is suspended **or** archived), and
   `ADDuplicateIDStatus`/`GoogleDuplicateIDStatus` when a duplicate ID is detected.
3. **After override merge:** overridden scalar fields replaced; `GroupsProposed` mutated
   by `AddGroup`/`RemoveGroup`; `ForceDisable`/`GoogleOUOverride` flags applied.
4. **After match-personIDs:** records that matched an existing-but-unlinked target user
   get `*CurrentUserID` filled in (so they become *updates* rather than *creates*).

**Create → refresh-groups pattern:** after new users are created in step 10/11, the
group-to-update list is recomputed (`Get-*UserGroupsToUpdate`) so brand-new accounts get
their group memberships in the same run, using the GUID/ID returned by the create call
(written back onto the source record).

## Identity keys & diffing (summary)

- **Join key:** `personID` → AD `EmployeeID` → Google `externalIds` (type `organization`).
- **Per-directory targeting:** `Provision<Dir>` (with `IDBActive`) decides each side
  independently — `IDBActive` is the master "active in source" flag; `ProvisionAD`/
  `ProvisionGoogle` say whether the person belongs in that directory. Setting `IDBActive=false`
  alone deactivates everywhere.
- **Create** = `IDBActive = true` AND `Provision<Dir> = true` AND no `*CurrentUserID` AND UPN not
  already present in target.
- **Update** = `IDBActive = true` AND `Provision<Dir> = true` AND linked + a property delta. AD
  splits results into `UpdateList`, `RenameList` (CN ≠ `FirstName LastName personID`), and
  `MoveList` (wrong OU).
- **Deactivate** = `(IDBActive = false OR Provision<Dir> = false)` AND still enabled (AD) / not
  yet deactivated (Google: neither archived nor suspended). Deactivation moves the user to the
  trash OU; on Google it **archives** (not suspends) so the base Education Fundamentals license
  self-releases — pre-archive suspended users are grandfathered, and `ForceDisable` still
  suspends (the temporary block).
- **Link** (`SetEmployeeID`) = **any** unlinked source user (active or not), so deprovisioned
  accounts get linked and can be deactivated.
- **Orphans** (Google): `Get-GoogleUsersOrphaned` finds target users absent from source.

## State & logging model

- **Global state** (script scope): `$script:IDBridgeConfig` and `$script:Logs` set by
  `Initialize-IDBridge`; `$script:GoogleHeaders` set by `Connect-IDBridgeGoogle` (called
  by `Invoke-IDBridge` at run start) — all read via their accessors.
- **`Write-Log`** writes to three places: the rotating file (`Paths.LogFile`), the
  in-memory `$script:Logs` list, and the console (mapped to Error/Warning/Verbose).
  `Trace`-level messages are suppressed unless `Debug.TraceLogging = $true`.
- **`Push-LogsToSheet`** (in `finally`) reverses the buffer (newest first), creates the
  target sheet/header if missing, inserts blank rows, and writes via `Set-GSheetData`.

