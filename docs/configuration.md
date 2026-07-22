# IDBridge Configuration Reference

IDBridge is driven by a single PowerShell data file **outside this repo**:

```
C:\IDBridge\Config\IDBridgeConfig.psd1
```

It is loaded by `Initialize-IDBridge` into `$script:IDBridgeConfig` and read everywhere via
`Get-IDBridgeConfig`. On a fresh install, `Install-IDBridge` scaffolds the folder tree and
writes a default all-features-off config with placeholder values (it never overwrites an
existing config). The file holds **site-specific values** (customer ID, sheet IDs, admin
email, OU paths) but **no raw secrets** — secrets are read at runtime from the encrypted
vault under `C:\IDBridge\Vault\` (see [Secrets](#secrets-not-in-the-config-file)).

> Precedence: command-line switches on `Invoke-IDBridge` override the file values for that
> run (logged as `OVERRIDE: …`). See [architecture.md](architecture.md).

---

## Schema

### `Debug`
| Key            | Type | Effect | Read by |
|----------------|------|--------|---------|
| `ReadOnly`     | bool | `$true` ⇒ compute change lists but **write nothing**. Shipped default `$true`. | `Invoke-IDBridge` (gates both execute regions) |
| `TestRun`      | bool | Each source plugin's output is capped at 10 records for fast iteration. | `Invoke-SourcePlugins` |
| `SkipADCheck`  | bool | Don't throw if the `ActiveDirectory` module fails to import. | `Initialize-IDBridge` |
| `TraceLogging` | bool | Emit `Trace`-level logs (and enables parallel-logging path in `Get-TargetDataGoogle`). | `Write-Log`, `Invoke-IDBridge`, `Get-TargetDataGoogle` |

### `ChangeThreshold` (change-volume safety guard)
Optional block. After the change lists are computed (read-only) and **before any writes**,
`Invoke-IDBridge` compares each enabled directory's proposed lifecycle changes
(create/update/rename/move/deactivate — group churn excluded) against that directory's existing
**managed** population (users under `AD.userRootOU` / `Google.userRootOU`). If the percentage
exceeds `Percentage`, the run **aborts before writing anything**. Omit the whole block to leave
the guard off (older configs keep working).

| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `Enabled`    | bool   | Master switch for the guard. `$false` (or `-SkipChangeThreshold`) bypasses it. | `Invoke-IDBridge` |
| `Percentage` | number | Max allowed change % of the managed population, per directory (def `25`). | `Invoke-IDBridge` → `Test-IDBridgeChangeThreshold` |

> A directory whose managed population is **0** (fresh tenant / empty root OU) is skipped with a
> `Warn` rather than tripping the guard, so a legitimate first run isn't blocked by a zero
> denominator. The `-SkipChangeThreshold` switch sets `Enabled = $false` for that run.

### `GoogleToken` (API authentication)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `Enabled`         | bool   | Gate Google token acquisition at run start. | `Invoke-IDBridge` (→ `Connect-IDBridgeGoogle`) |

> The service-account key itself is the vault secret `GoogleAuth-ServiceAccount`
> (see [secrets.md](secrets.md)) — no file path is configured or discovered. The token is
> issued to the **service account itself** (no impersonation, no admin user): Admin SDK
> calls are authorized by the `IDBridge` Workspace admin role assigned by the bootstrap,
> and Sheets access comes from sharing the sheets with the service-account email
> (`Get-IDBridgeGoogleServiceAccountEmail`). OAuth **scopes are not configured** — they're
> defined by the module (`Get-IDBridgeGoogleScope`): directory user/orgunit/group +
> Sheets, plus `apps.licensing` unless `Google.enableLicenseRemoval = $false`. See
> [google-bootstrap.md](google-bootstrap.md).

### `Google` (Workspace processing)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `enabled`                     | bool   | Master switch for Google processing (an auth failure throws — see behavioral notes). | `Invoke-IDBridge`, `Get-TargetDataGoogle` |
| `customerID`                  | string | Workspace customer ID. | Google target/API calls |
| `userRootOU`                  | string | Root OU path, e.g. `/YourDistrict`. Managed-population anchor for the change-volume guard. | `Invoke-IDBridge` (`ChangeThreshold`) |
| `enableGroupProcessing`       | bool   | Enable Google group sync. | `Invoke-IDBridge` |
| `enableGroupProcessingWhatIf` | bool   | While `$true`, group diffs are computed and logged but **no group writes happen** (even with `enableGroupProcessing = $true`). | `Invoke-IDBridge` |
| `enableGroupProcessingRemove` | bool   | Allow removals (not just adds). | `Invoke-IDBridge` |
| `enableGroupProcessingTrash`  | bool   | Strip group memberships when deactivating. | `Invoke-IDBridge` |
| `groupsExcluded`              | array  | Group **email** wildcard patterns IDBridge never touches — matching groups are dropped at target-data retrieval, so no adds, removes, or deactivate strips ever reach them (exclusion wins even over a proposed group). Key absent = `@('classroom_teachers@*')` (the previous hardcoded behavior); if you set the key, include that pattern yourself. | `Get-TargetDataGoogle` |
| `enableLicenseRemoval`        | bool   | Remove a user's discovered **paid** license assignments on the **full deactivate (trash) step only** — never on a `ForceDisable` update. The base Education Fundamentals license self-releases when the deactivate step archives the user. **Default on**; set `$false` to disable (also drops the `apps.licensing` scope from token requests). | `Invoke-IDBridge` |
| `licenseProductIds`           | array  | Products searched for a user's assignments (SKUs are discovered, not configured). Default `@('101031','101037')` (Education Standard/Plus + Teaching and Learning Upgrade) — paid products only; the base license is not touched by API (archiving releases it, and API removal fights OU auto-licensing). IDs: [Google's product list](https://developers.google.com/workspace/admin/licensing/how-to/products). | `Get-TargetDataGoogle` |

> License removal (on by default) needs the **License Management privilege** on the
> service account's `IDBridge` admin role. Bootstrap-created roles include it (when the
> privilege exists in the tenant); if licensing calls fail with a 403, re-run the
> bootstrap to converge the role's privileges — or set `enableLicenseRemoval = $false`.

### `AD` (Active Directory processing)
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `enabled`                     | bool   | Master switch for AD processing. | `Initialize-IDBridge`, `Invoke-IDBridge` |
| `userRootOU`                  | string | Root OU DN, e.g. `OU=YourDistrict,DC=yourdomain,DC=local`. Managed-population anchor for the change-volume guard. | `Invoke-IDBridge` (`ChangeThreshold`) |
| `enableGroupProcessing`       | bool   | Enable AD group sync. | `Invoke-IDBridge` |
| `enableGroupProcessingWhatIf` | bool   | While `$true`, group diffs are computed and logged but **no group writes happen** (even with `enableGroupProcessing = $true`). | `Invoke-IDBridge` |
| `enableGroupProcessingRemove` | bool   | Allow removals. | `Invoke-IDBridge` |
| `enableGroupProcessingTrash`  | bool   | Strip groups on deactivate (passed to `Disable-IDBridgeADUser`). | `Invoke-IDBridge` |
| `groupsExcluded`              | array  | Group **name** wildcard patterns IDBridge never touches — matching groups are dropped at target-data retrieval, so no adds, removes, or deactivate strips ever reach them (exclusion wins even over a proposed group). Default `@()`. | `Get-TargetDataAD` |

### `Logging`
| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `GoogleSheetLoggingEnabled` | bool   | Push the in-memory log buffer to a sheet at end of run. | `Invoke-IDBridge` (finally) |
| `SheetID`                   | string | Target spreadsheet ID for logs. | `Push-LogsToSheet` |

### `Telemetry`
Anonymous usage telemetry to the IDBridge Pulse backend (see [PRIVACY.md](../PRIVACY.md) for
exactly what each tier sends). Omit the block for the default tier `'Basic'`; an
unrecognized `Tier` value fails safe to `Off`. `-DisableTelemetry` silences a single run.

| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `Tier`     | string | `'Basic'` (default — anonymous counts), `'Enhanced'` (adds random install SiteID + error class/function on failures), or `'Off'`. | `Send-IDBridgeTelemetry` |
| `Endpoint` | string | Optional ingest URL override (default `https://pulse.scnlabs.net/api/ingest`), e.g. for an egress proxy. | `Send-IDBridgeTelemetry` |

### `Plugins`
Array of plugin descriptors. `Source`/`Override` entries are executed in order by
`Invoke-SourcePlugins` at the start of the run; `PostRun` entries by `Invoke-PostRunPlugins`
at the end of the run (in the `finally` block, after telemetry — they fire on failed and
ReadOnly runs too):

```powershell
@{ Enabled = $true;  Type = "Source";   Function = 'Invoke-PluginGSheetStaff' }
@{ Enabled = $false; Type = "Source";   Function = 'Invoke-PluginSkywardSMSStudents' }
@{ Enabled = $false; Type = "Source";   Function = 'Invoke-PluginInfiniteCampusStudents' }
@{ Enabled = $true;  Type = "Override";  Function = 'Invoke-PluginStaffOverride' }
@{ Enabled = $false; Type = "PostRun";  Function = 'Invoke-PluginPostRunReport' }
@{ Enabled = $false; Type = "PostRun";  Function = 'Invoke-PluginPostRunWebhook' }
@{ Enabled = $false; Type = "PostRun";  Function = 'Invoke-PluginPostRunExport' }
@{ Enabled = $false; Type = "PostRun";  Function = 'Invoke-PluginPostRunOrphanReport' }
```

| Key | Effect |
|-----|--------|
| `Enabled`  | Skip the descriptor when `$false`. |
| `Type`     | `Source` (contributes users), `Override` (modifies users by `personID`), or `PostRun` (consumes the run's results — reports, dashboards, your own telemetry). |
| `Function` | Function name **and** expected file name `<Function>.ps1` under `PluginsRoot`. |

See [plugins.md](plugins.md) for the contract and the shipped plugins.

### `Secrets`
Selects the **provider** `Set-IDBridgeSecret` protects new secrets with. Omit the block to
use the default provider `'Cms'`. For the local providers (`Cms`/`DpapiNG`) the vault folder
is always the runtime `Paths.VaultRoot` (`<Root>\Vault`) and reads are provider-agnostic —
each envelope file records the provider that protected it, so `Get-IDBridgeSecret` decrypts
any mix; the provider choice matters at **write** time only. `'AzKeyVault'` is the remote
exception: all secret functions go to Azure Key Vault over REST instead of local envelopes.

| Key | Type | Effect | Read by |
|-----|------|--------|---------|
| `Provider`   | string | Secrets backend: `'Cms'` (certificate, default), `'DpapiNG'` (gMSA), `'AzKeyVault'` (Azure Key Vault, remote). | all secret functions |
| `Cms`        | hashtable | Cms-only sub-block (see below). Ignored by other providers. | `Set-IDBridgeSecret` |
| `DpapiNG`    | hashtable | DpapiNG-only sub-block (see below). Ignored by other providers. | `Set-IDBridgeSecret` |
| `AzKeyVault` | hashtable | AzKeyVault-only sub-block (see below). Ignored by other providers. | all secret functions |

`Cms` sub-block (only used when `Provider = 'Cms'`):

| Key | Type | Effect |
|-----|------|--------|
| `Thumbprint` | string | Document Encryption certificate to encrypt with (from `New-IDBridgeSecretCertificate`). Omit/empty ⇒ the single unexpired `CN=IDBridge Secrets` certificate is found automatically. |

`DpapiNG` sub-block (only used when `Provider = 'DpapiNG'`):

| Key | Type | Effect |
|-----|------|--------|
| `ProtectionDescriptor` | string | DPAPI-NG protection descriptor applied on write, e.g. `'SID=<gMSA SID>'` or `'SID=<gMSA SID> OR SID=<admins group SID>'`. Omit ⇒ protected to the current account only (logged `Warn`). |

`AzKeyVault` sub-block (only used when `Provider = 'AzKeyVault'`):

| Key | Type | Effect |
|-----|------|--------|
| `VaultUri`       | string | Key Vault URI, e.g. `'https://<vault>.vault.azure.net/'`. |
| `TenantId`       | string | Entra tenant ID or domain. |
| `ClientId`       | string | App registration (client) ID holding the certificate credential. |
| `CertThumbprint` | string | Thumbprint of the auth certificate (CurrentUser or LocalMachine My store; the running account needs private-key read). |

```powershell
# Certificate (default; works on or off domain)
Secrets = @{
    Provider = 'Cms'
    Cms      = @{ Thumbprint = '<from New-IDBridgeSecretCertificate>' }
}

# Production (gMSA / DPAPI-NG, domain-joined)
Secrets = @{
    Provider = 'DpapiNG'
    DpapiNG  = @{ ProtectionDescriptor = 'SID=S-1-5-21-...-<gMSA SID> OR SID=<admins group SID>' }
}

# Azure Key Vault (remote)
Secrets = @{
    Provider   = 'AzKeyVault'
    AzKeyVault = @{
        VaultUri       = 'https://<vault>.vault.azure.net/'
        TenantId       = '<tenant>.onmicrosoft.com'
        ClientId       = '<app registration client id>'
        CertThumbprint = '<auth certificate thumbprint>'
    }
}
```

See [secrets.md](secrets.md) for provider setup, the certificate workflow, and the
gMSA/DPAPI-NG model.

---

## Runtime `Paths` (added by `Initialize-IDBridge`)

Derived from `-RootPath` (default `C:\IDBridge`); missing directories are created.

| `Paths` key       | Value                         | Purpose |
|-------------------|-------------------------------|---------|
| `Root`            | `<RootPath>`                  | Base directory |
| `ConfigRoot`      | `<Root>\Config`               | Holds `IDBridgeConfig.psd1` |
| `LogsRoot`        | `<Root>\Logs`                 | `IDBridge.log` (rotated at 5 MB) |
| `ExportsRoot`     | `<Root>\Exports`              | Run reports and `UserList-<PersonType>.csv` exports |
| `PluginsRoot`     | `<Root>\Plugins`              | Plugin `.ps1` files |
| `DataRoot`        | `<Root>\Data`                 | Plugin state (e.g. Skyward / Infinite Campus `LastSeen` CSVs) |
| `VaultRoot`       | `<Root>\Vault`                | Secret vault (`*.secret.json` envelope files) |
| `LogFile`         | `<LogsRoot>\IDBridge.log`     | Active log file |

---

## Secrets (NOT in the config file)

Secrets live in the **IDBridge secret vault** — encrypted `*.secret.json` envelope files under
`<Root>\Vault` (add/change with `Set-IDBridgeSecret`), including the Google service-account
key. **Only names/locations are documented here — never values.** See [secrets.md](secrets.md).

| Secret / item | Used by |
|---------------|---------|
| `GoogleAuth-ServiceAccount` (vault)     | `Connect-IDBridgeGoogle` → `Get-GoogleApiAccessToken` (the service-account key JSON; no file fallback) |
| `ApiKey-SkywardSMS` (vault)             | Skyward students plugin (client secret) |
| `ApiKey-InfiniteCampus` (vault)         | Infinite Campus students plugin (client secret) |
| `ApiKey-Passphrase` (vault)             | Passphrase API bearer token (`New-Passphrase`) |
| `ApiKey-PassphraseNonceStaff` (vault)   | Staff passphrase nonce |
| `ApiKey-PassphraseNonceStudent` (vault) | Student passphrase nonce |

---

## Behavioral notes

- **Auth failures throw:** if `Connect-IDBridgeGoogle` (called by `Invoke-IDBridge` at run
  start when `GoogleToken.Enabled`) can't read the Google key secret or acquire a token, the
  run fails at startup (no silent degradation). Disabling Google or AD
  (config or `-SkipGoogle`/`-SkipAD`) also disables that side's `enableGroupProcessing`.
- **WhatIf vs. ReadOnly:** `Debug.ReadOnly` blocks *all* writes; `enableGroupProcessingWhatIf`
  scopes only group changes to log-only while other writes still happen (when not ReadOnly).
- **Safe default:** the shipped config has `Debug.ReadOnly = $true` and AD/Google group
  `WhatIf = $true` — a fresh run reports intended changes without modifying anything.
- **Change-volume guard:** `ChangeThreshold` aborts the whole run (before any writes) if a
  directory's proposed lifecycle changes exceed `Percentage` of its managed population. It fires
  regardless of `ReadOnly`, so even a preview run that breaches the limit stops at the guard.
  Bypass with `ChangeThreshold.Enabled = $false` or the `-SkipChangeThreshold` switch.
