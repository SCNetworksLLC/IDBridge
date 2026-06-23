# IDBridge Configuration Reference

IDBridge is driven by a single PowerShell data file **outside this repo**:

```
C:\IDBridge\Config\IDBridgeConfig.psd1
```

It is loaded by `Initialize-IDBridge` into `$script:IDBridgeConfig` and read everywhere via
`Get-IDBridgeConfig`. The file holds **site-specific values** (customer ID, sheet IDs, admin
email, OU paths) but **no raw secrets** — secrets are read at runtime from per-operator
files under `C:\IDBridge\Auth\<username>\` (see [Secrets](#secrets-not-in-the-config-file)).

> Precedence: command-line switches on `Invoke-IDBridge` override the file values for that
> run (logged as `OVERRIDE: …`). See [architecture.md](architecture.md).

---

## Schema

### `Debug`
| Key            | Type | Effect | Read by |
|----------------|------|--------|---------|
| `ReadOnly`     | bool | `$true` ⇒ compute change lists but **write nothing**. Shipped default `$true`. | `Invoke-IDBridge` (gates both execute regions) |
| `TestRun`      | bool | Plugins process a small subset for fast iteration. | Plugins (via `Get-SourceData*` `testRun`) |
| `SkipADCheck`  | bool | Don't throw if the `ActiveDirectory` module fails to import. | `Initialize-IDBridge` |
| `TraceLogging` | bool | Emit `Trace`-level logs (and enables parallel-logging path in `Get-TargetDataGoogle`). | `Write-Log`, `Invoke-IDBridge`, `Get-TargetDataGoogle` |

### `GoogleToken` (API authentication)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `Enabled`         | bool   | Gate Google token acquisition at startup. | `Initialize-IDBridge` |
| `googleAuthScope` | string | Space-separated OAuth scopes (directory user/orgunit/group + spreadsheets). | `Get-GoogleApiAccessToken` |
| `adminEmail`      | string | Delegated admin the service account impersonates. | `Get-GoogleApiAccessToken` |
| `authFilePath`    | string | **Runtime-added** — path to the one `*.json` service-account key found in `AuthRoot`. | `Initialize-IDBridge` |

### `Google` (Workspace processing)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `enabled`                     | bool   | Master switch for Google processing (auto-set `$false` if auth fails). | `Invoke-IDBridge`, `Get-TargetDataGoogle` |
| `customerID`                  | string | Workspace customer ID. | Google target/API calls |
| `userRootOU`                  | string | Root OU path, e.g. `/Marshfield`. | `Get-GoogleOrgUnitsForProcessing` |
| `GroupPrimaryDomainName`      | string | Domain used to build group emails (`name@domain`). | `Get-GoogleUserGroupsToUpdate` |
| `enableGroupProcessing`       | bool   | Enable Google group sync. | `Invoke-IDBridge` |
| `enableGroupProcessingWhatIf` | bool   | Compute group diffs for logging without applying. | `Invoke-IDBridge` |
| `enableGroupProcessingRemove` | bool   | Allow removals (not just adds). | `Invoke-IDBridge` |
| `enableGroupProcessingTrash`  | bool   | Strip group memberships when deactivating. | `Invoke-IDBridge` |

### `AD` (Active Directory processing)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `enabled`                     | bool   | Master switch for AD processing. | `Initialize-IDBridge`, `Invoke-IDBridge` |
| `userRootOU`                  | string | Root OU DN, e.g. `OU=Marshfield,DC=sdom,DC=local`. | `Get-ADOrgUnitsForProcessing` |
| `enableGroupProcessing`       | bool   | Enable AD group sync. | `Invoke-IDBridge` |
| `enableGroupProcessingWhatIf` | bool   | Compute group diffs for logging without applying. | `Invoke-IDBridge` |
| `enableGroupProcessingRemove` | bool   | Allow removals. | `Invoke-IDBridge` |
| `enableGroupProcessingTrash`  | bool   | Strip groups on deactivate (passed to `Disable-IDBridgeADUser`). | `Invoke-IDBridge` |

### `Logging`
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `GoogleSheetLoggingEnabled` | bool   | Push the in-memory log buffer to a sheet at end of run. | `Invoke-IDBridge` (finally) |
| `SheetID`                   | string | Target spreadsheet ID for logs. | `Push-LogsToSheet` |

### `Plugins`
Array of plugin descriptors, executed in order by `Invoke-SourcePlugins`:

```powershell
@{ Enabled = $true;  Type = "Source";   Function = 'Invoke-PluginGSheetStaff' }
@{ Enabled = $false; Type = "Source";   Function = 'Invoke-PluginSkywardSMSStudents' }
@{ Enabled = $true;  Type = "Override";  Function = 'Invoke-PluginStaffOverride' }
```

| Key | Effect |
|-----|--------|
| `Enabled`  | Skip the descriptor when `$false`. |
| `Type`     | `Source` (contributes users) or `Override` (modifies users by `personID`). |
| `Function` | Function name **and** expected file name `<Function>.ps1` under `PluginsRoot`. |

See [plugins.md](plugins.md) for the contract and the shipped plugins.

### `Secrets` (optional)
Controls where `Get-IDBridgeSecret` looks first. Omit the whole block to keep the historical
file-based behavior (`Auth\<user>\<name>.txt`).

| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `UseSecretManagement` | bool   | Opt-in marker for vault-based secrets. | `Get-IDBridgeSecret` |
| `VaultName`           | string | SecretManagement vault to read from (falls back to file store if unavailable). | `Get-IDBridgeSecret` |

```powershell
Secrets = @{ UseSecretManagement = $true; VaultName = 'IDBridge' }
```

See [secrets.md](secrets.md) for setup and migration.

---

## Runtime `Paths` (added by `Initialize-IDBridge`)

Derived from `-RootPath` (default `C:\IDBridge`); missing directories are created.

| `Paths` key       | Value                         | Purpose |
|-------------------|-------------------------------|---------|
| `Root`            | `<RootPath>`                  | Base directory |
| `ConfigRoot`      | `<Root>\Config`               | Holds `IDBridgeConfig.psd1` |
| `AuthRoot`        | `<Root>\Auth`                 | Service-account JSON (exactly one) + per-user secrets |
| `LogsRoot`        | `<Root>\Logs`                 | `IDBridge.log` (rotated at 5 MB) |
| `ExportsRoot`     | `<Root>\Exports`              | `UserList-Staff.csv` and other exports |
| `PluginsRoot`     | `<Root>\Plugins`              | Plugin `.ps1` files |
| `DataRoot`        | `<Root>\Data`                 | Plugin state (e.g. Skyward `LastSeen` CSV) |
| `LogFile`         | `<LogsRoot>\IDBridge.log`     | Active log file |
| `UserSecretsRoot` | `<AuthRoot>\<username>`        | Per-operator API keys/nonces |

---

## Secrets (NOT in the config file)

Stored as text files under `Paths.UserSecretsRoot` (`C:\IDBridge\Auth\<username>\`) and the
service-account key under `AuthRoot`. **Only names/locations are documented here — never
values.**

| File / item | Used by |
|-------------|---------|
| One `*.json` service-account key in `AuthRoot` | `Initialize-IDBridge` → `Get-GoogleApiAccessToken` |
| `ApiKey-SkywardSMS.txt`             | Skyward students plugin (SecureString client secret) |
| `ApiKey-Passphrase.txt`             | Passphrase API bearer token (`New-Passphrase`) |
| `ApiKey-PassphraseNonceStaff.txt`   | Staff passphrase nonce |
| `ApiKey-PassphraseNonceStudent.txt` | Student passphrase nonce |
| `$env:PASSPHRASE_AUTH_TOKEN`        | Fallback auth token for `New-Passphrase` |

---

## Behavioral notes

- **Auth-fail cascade:** if `Initialize-IDBridge` can't produce `$script:GoogleHeaders`,
  it forces `Google.enabled = $false`. Disabling Google or AD also disables that side's
  `enableGroupProcessing`.
- **WhatIf vs. ReadOnly:** `Debug.ReadOnly` blocks *all* writes; `enableGroupProcessingWhatIf`
  scopes only group changes to log-only while other writes still happen (when not ReadOnly).
- **Safe default:** the shipped config has `Debug.ReadOnly = $true` and AD/Google group
  `WhatIf = $true` — a fresh run reports intended changes without modifying anything.
