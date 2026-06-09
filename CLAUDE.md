# IDBridge

PowerShell module that syncs user accounts from source SIS/HR systems into Active Directory and Google Workspace. Written for PowerShell 7.5+.

## How it runs

`IDBridge.ps1` is the entry point. It imports the module from `IDBridge.psd1`, loads configuration, then runs the full sync pipeline top-to-bottom as a flat script (~542 lines).

```powershell
# Run it
.\IDBridge.ps1

# Watch logs live
Get-Content -Path "C:\IDBridge\Logs\IDBridge.log" -Tail 200 -Wait
```

## Repo vs live paths

| Purpose | Path |
|---------|------|
| Module source (git) | `C:\GIT\IDBridge\` |
| Live config + data | `C:\IDBridge\` |
| Config file | `C:\IDBridge\Config\IDBridgeConfig.psd1` |
| Auth (Google service account JSON) | `C:\IDBridge\Auth\` |
| Logs | `C:\IDBridge\Logs\IDBridge.log` |
| Exports | `C:\IDBridge\Exports\` |
| Custom functions (not in repo) | `C:\IDBridge\Custom\*.ps1` |
| Plugin functions (not in repo) | `C:\IDBridge\Plugins\*.ps1` |

## Module loading (`IDBridge.psm1`)

Dot-sources all files under `Public\**\*.ps1`, then `C:\IDBridge\Custom\*.ps1`, then `C:\IDBridge\Plugins\*.ps1`. Any import error halts the entire module load with a warning.

## Directory structure

```
Public\
  Core\          # Config, logging, passwords, passphrase, script end
  AD\            # AD user/group/OU functions
  Google\        # Google Workspace user/group/OU functions
  Google\Sheets\ # Google Sheets API helpers
  Source\        # Source data connectors (InfiniteCampus, Skyward, GSheet)
  Target\        # Target data fetchers (AD, Google)
```

## Global state

Two globals are set by `Get-IDBridgeConfiguration` and used throughout:

- `$global:IDConfig` — the full config hashtable (also accessible as `$IDConfig`)
- `$global:logFile` — path to the active log file

All `Write-Log` calls pass `-Path $logFile`. Plugins may read `$IDconfig.Paths.*` directly (e.g. `Get-SourceDataSkywardSMS` accesses `$IDconfig.Paths.DataRoot`).

## Config structure (`IDBridgeConfig.psd1`)

```
Paths         — Root, ConfigRoot, AuthRoot, LogsRoot, ExportsRoot, PluginsRoot, DataRoot
Debug         — readOnly, testRun, skipADCheck, verboseLogging
GoogleToken   — googleAuthScope, adminEmail  (authFilePath added at runtime)
Google        — enabled, customerID, userRootOU, group processing flags
AD            — enabled, userRootOU, group processing flags
Logging       — SheetID (Google Sheet for log uploads)
Plugins       — integer-keyed hashtable of { Enabled, Type, Function }
```

`readOnly = $true` is the safe default — no writes happen. Set `$false` to apply changes.

## Pipeline flow (IDBridge.ps1)

1. **Load config** → `Get-IDBridgeConfiguration`
2. **Auth** → `Get-GoogleApiAccessToken` → `$headersGoogle`
3. **Source plugins** → loop `$IDConfig.Plugins` (sorted by key name), run enabled Source plugins → `$sourceData[]`, Override plugins → `$overrideData[]`
4. **Target data** → `Get-TargetDataGoogle`, `Get-TargetDataAD`
5. **Deduplicate** source data by personID (cross-checks AD and Google duplicate lists too)
6. **Enrich** — attach `ADObject`, `GoogleObject`, current groups, enabled/suspended status to each source record
7. **Apply overrides** — merge `$overrideData` into source records (AddGroup/RemoveGroup handled specially)
8. **Build processing lists** — for AD and Google independently: OUs to create, users to create/update/deactivate, groups to add/remove
9. **Execute** (skipped if `readOnly = $true`) — OUs → deactivations → updates/renames/moves → creates → group membership
10. **Export** staff CSV to `Exports\UserList-Staff.csv`
11. **`Start-ScriptEnd`** — logs completion, uploads log to Google Sheet

## AD vs Google symmetry

Most operations have parallel AD and Google implementations with the same naming pattern:

| Operation | AD | Google |
|-----------|----|----|
| Fetch target state | `Get-TargetDataAD` | `Get-TargetDataGoogle` |
| OUs to create | `Get-ADOrgUnitsForProcessing` | `Get-GoogleOrgUnitsForProcessing` |
| Users to create | `Get-ADUsersToCreate` | `Get-GoogleUsersToCreate` |
| Users to update | `Get-ADUsersToUpdate` (returns UpdateList/RenameList/MoveList) | `Get-GoogleUsersToUpdate` |
| Users to deactivate | `Get-ADUsersToDeactivate` | `Get-GoogleUsersToDeactivate` |
| Groups to update | `Get-ADUserGroupsToUpdate` | `Get-GoogleUserGroupsToUpdate` |

AD uses DN-based paths (`OU=X,DC=domain,DC=local`); Google uses slash paths (`/Root/Child`).

## Plugin architecture

Plugins live in `C:\IDBridge\Plugins\` (not in the repo). Two types:
- **Source** — return user records that become `$sourceData`
- **Override** — return records that patch `$sourceData` before processing (e.g. add/remove group memberships)

Plugin functions follow the naming convention `Invoke-Plugin*` (exported via wildcard in `IDBridge.psd1`).