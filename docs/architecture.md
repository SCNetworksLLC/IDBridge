# IDBridge Architecture & Execution Pipeline

This is the end-to-end story of a run. Source of truth:
[`src\IDBridge\Public\Core\Invoke-IDBridge.ps1`](../src/IDBridge/Public/Core/Invoke-IDBridge.ps1) and
[`src\IDBridge\Public\Core\Initialize-IDBridge.ps1`](../src/IDBridge/Public/Core/Initialize-IDBridge.ps1).

## Two-stage startup

`Invoke-IDBridge` is the entry point. Its first act is `Initialize-IDBridge -RootPath`,
which prepares all global state:

1. **Load config** — `Import-PowerShellDataFile` of
   `<RootPath>\Config\IDBridgeConfig.psd1` → `$script:IDBridgeConfig`.
2. **Build & validate paths** — computes `Paths.{Root,ConfigRoot,AuthRoot,LogsRoot,
   ExportsRoot,PluginsRoot,DataRoot}`, creating any missing directory.
3. **Logging** — sets `Paths.LogFile = <LogsRoot>\IDBridge.log`, inits the in-memory
   buffer `$script:Logs`, and **rotates the log if it exceeds 5 MB** (renames with a
   timestamp). Writes the run-start marker.
4. **Google auth** (if `GoogleToken.Enabled`) — requires **exactly one** `*.json` service
   account file in `AuthRoot` (errors on zero or multiple), validates it has a
   `private_key`, then calls `Get-GoogleApiAccessToken` (JWT → bearer token via
   domain-wide delegation to `GoogleToken.adminEmail`) and stores the result in
   `$script:GoogleHeaders`.
5. **User secrets dir** — ensures `AuthRoot\<username>` exists →
   `Paths.UserSecretsRoot` (per-operator API keys live here).
6. **AD module** (if `AD.enabled`) — `Import-Module ActiveDirectory`. On failure it
   throws **unless** `Debug.skipADCheck` is set.
7. **Feature-dependency cascade** — if Google auth never produced headers, force
   `Google.enabled = $false`; disabling Google/AD also disables their group processing.

Back in `Invoke-IDBridge`, it then calls `Get-IDBridgeConfig` and applies **runtime
switch overrides** (`-ReadOnly/-TestRun/-SkipADCheck/-TraceLogging/-SkipAD/-SkipGoogle`),
logging each as `OVERRIDE: <key> = <value>`. Switches win over the config file.

## The ordered pipeline

Each step below maps to a `#region` block in `Invoke-IDBridge.ps1`. The whole body is
wrapped in `try/catch/finally`; per-user write errors are logged and skipped, but
startup/OU-creation failures `Throw` and abort the run.

```
Invoke-IDBridge
  └─ Initialize-IDBridge ──► $script:IDBridgeConfig / $script:Logs / $script:GoogleHeaders
  └─ apply -switch overrides
        │
  1. Invoke-SourcePlugins ───────────► $sourceData (Source), $overrideData (Override)
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
 10. EXECUTE AD changes      (only if AD.enabled    AND Debug.readOnly = $false)
       New-IDBridgeADOrgUnit → Disable-IDBridgeADUser → Set-ADUser (update) →
       Rename-ADObject → Move-ADObject → New-ADUser (create) →
       [refresh group list if users created] → Add/Remove group membership
 11. EXECUTE Google changes  (only if Google.enabled AND Debug.readOnly = $false)
       New-IDBridgeGoogleOrgUnit → Update-IDBridgeGoogleUser (suspend+trash deactivates) →
       Update-IDBridgeGoogleUser (update/move/rename) → New-IDBridgeGoogleUser (create) →
       [refresh group list if users created] → Update-GoogleGroupMembers add/remove
        │
 12. Export non-students → <ExportsRoot>\UserList-Staff.csv   (PersonTypeID ≠ "1")
        │
 finally:
 13. Push-LogsToSheet (if Logging.GoogleSheetLoggingEnabled) → writes $script:Logs to sheet
```

## Data-object lifecycle

A single source record is a `PSCustomObject` that **accretes properties** as it flows:

1. **From plugins:** normalized fields — `personID`, `NameFirst/NameLast`, `Username`,
   `UPN`, `PersonTypeID`, `IDBActive`, `GroupsProposed`, plus `AD*`/`Google*` OU,
   password, and passphrase fields. (See [plugins.md](plugins.md) for the full schema.)
2. **After `Add-TargetData*`:** `ADObject`/`GoogleObject`, `ADCurrentUserID`/
   `GoogleCurrentUserID`, `ADCurrentGroups`/`GoogleCurrentGroups`,
   `ADCurrentUserEnabledStatus`/`GoogleCurrentUserSuspendedStatus`, and
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
- **Create** = `IDBActive = true` AND no `*CurrentUserID` AND UPN not already present in target.
- **Update** = active + linked + a detected property delta. AD splits results into
  `UpdateList` (property changes), `RenameList` (CN ≠ `FirstName LastName personID`), and
  `MoveList` (wrong OU).
- **Deactivate** = `IDBActive = false` AND still enabled (AD) / not suspended (Google).
  Deactivation also moves the user to the trash OU.
- **Orphans** (Google): `Get-GoogleUsersOrphaned` finds target users absent from source.

## State & logging model

- **Global state** (script scope): `$script:IDBridgeConfig`, `$script:Logs`,
  `$script:GoogleHeaders` — all set by `Initialize-IDBridge`, read via their accessors.
- **`Write-Log`** writes to three places: the rotating file (`Paths.LogFile`), the
  in-memory `$script:Logs` list, and the console (mapped to Error/Warning/Verbose).
  `Trace`-level messages are suppressed unless `Debug.TraceLogging = $true`.
- **`Push-LogsToSheet`** (in `finally`) reverses the buffer (newest first), creates the
  target sheet/header if missing, inserts blank rows, and writes via `Set-GSheetData`.

