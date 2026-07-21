# Getting Started — First Run

The ordered walkthrough from a clean Windows machine to a first successful sync, using the
**PowerShell Gallery install**. Each step says what to do and how to verify it; the linked
reference docs own the detail. Do the steps **in order** — later steps assume the earlier
ones (the vault needs the folder tree, the Google bootstrap seeds into the vault, the first
run needs a source plugin, …).

At the end of step 8 you have a deployment that reports every change it *would* make without
touching either directory. Step 9 turns writes on deliberately.

## 1. Prerequisites

- **Windows** with **PowerShell 7.5+** (`pwsh`).
- **ActiveDirectory** module (RSAT) on a **domain-joined** machine — only if you're syncing
  AD. Google-only deployments skip this (run with `-SkipAD`, or leave `AD.enabled = $false`).
- An **elevated** session for step 3 (the secret certificate goes in the machine store).
- For step 4 (once, ever): sign-in as the district's **Google Workspace super admin**, and
  *Google Cloud Platform* turned **ON** for that admin (Admin console → Apps → Additional
  Google services). See [google-bootstrap.md](google-bootstrap.md#prerequisites).

## 2. Install and scaffold

```powershell
Install-Module IDBridge -Scope CurrentUser   # Update-Module IDBridge to upgrade later
Import-Module IDBridge

Install-IDBridge                           # -RootPath 'D:\IDBridge' to relocate everything
```

`Install-IDBridge` creates the runtime tree under `C:\IDBridge`
(`Config/Logs/Exports/Plugins/Data/Vault`), writes a default
`Config\IDBridgeConfig.psd1` — every feature disabled, all safety brakes on (`ReadOnly`,
group `WhatIf`, `ChangeThreshold`), placeholder site values — and copies the six shipped
plugin templates into `Plugins\`. It never overwrites an existing config or plugin file.
You'll edit these in steps 6–7; the config schema reference is
[configuration.md](configuration.md).

**Verify:** the printed config path exists and `Initialize-IDBridge` runs without error
(it loads the config and sets up logging — safe on a fresh install; Google auth doesn't
happen here).

## 3. Secret vault

Secrets (the Google key, SIS API keys) live in the encrypted vault under
`C:\IDBridge\Vault` — never in the config file. The default `Cms` provider needs a one-time
Document Encryption certificate, created in an **elevated** session:

```powershell
Initialize-IDBridge
New-IDBridgeSecretCertificate     # prints the thumbprint
```

Leave `Secrets.Cms.Thumbprint` empty in the config (the single `CN=IDBridge Secrets` cert
is found automatically) or paste the thumbprint in. For unattended production runs under a
gMSA, or central storage in Azure Key Vault, see the alternative providers in
[secrets.md](secrets.md) — reads are provider-agnostic, so you can switch later.

**Verify:** `Get-IDBridgeSecretInfo` runs (empty list is fine — nothing is stored yet).

## 4. Google service account (one-time bootstrap)

Run once per district, signed in as their Workspace super admin:

```powershell
Initialize-IDBridgeGoogleServiceAccount -CreateProject
```

This creates the GCP project and service account, enables the APIs, creates + assigns the
scoped `IDBridge` Workspace admin role (no domain-wide delegation, no impersonation), and
seeds the key **straight into the vault** as `GoogleAuth-ServiceAccount` — it never touches
disk. It's idempotent; re-running is safe. The sign-in/token flow and the org-policy edge
cases are covered in [google-bootstrap.md](google-bootstrap.md).

It finishes by printing a short manual checklist. The part no API can do for you: **share
the source and log spreadsheets with the service-account email** (Editor) — the sheets
don't exist yet, so that lands in step 5. `Get-IDBridgeGoogleServiceAccountEmail` reprints
the email any time.

**Verify:** `Connect-IDBridgeGoogle` succeeds — that proves the vault, key, and token
acquisition end-to-end. (A `403` on later API calls usually means the role assignment is
still propagating — minutes — or a sheet isn't shared yet.)

## 5. Source sheet

A new deployment reads its people from a Google Sheet. Two ways to get one:

- **From scratch:** copy the published template —
  <https://docs.google.com/spreadsheets/d/1OUlm-5WGce_x2z0L1dM2kD8Ejk_f3RNF3EC8sa6uHhE/copy> —
  source and override tabs pre-built with tables, `Process` checkboxes, a `TerminationDate`
  date column, a Groups reference tab, and group dropdowns.
- **Migrating a site that already has AD/Google accounts:** seed a sheet from current
  directory state instead:

  ```powershell
  Initialize-IDBridge
  Connect-IDBridgeGoogle
  Export-IDBridgeDirectoryToSheet -SpreadsheetId '<id>' -GoogleOrgUnitPath '/YourDistrict' -ADSearchBase 'OU=YourDistrict,DC=...'
  ```

  Both scopes take one or more OUs (each a subtree) — e.g.
  `-ADSearchBase 'OU=Staff,DC=...', 'OU=Subs,DC=...'` — and a user under any of them is
  included. If your directories don't carry employee IDs, `-PersonIDCsv` takes a CSV with
  `ID` and `Username` columns (e.g. a SIS export) to fill in `PersonID` by username match.
  Every exported row gets `Process = FALSE` and review-helper columns — review and
  switch people on deliberately. Details:
  [functions.md](functions.md#export-idbridgedirectorytosheet-).

Then **share the spreadsheet (Editor) with the service-account email** from step 4. If you
want the run log pushed to a sheet too, create/share one more and put its ID in
`Logging.SheetID`.

**Note the spreadsheet ID** (the long string in the sheet URL) — your plugin needs it next.

## 6. Source plugin

Plugins are the only place source data enters IDBridge. Step 2 copied the six shipped
templates into `C:\IDBridge\Plugins\`. Three of them feed the run:

| Template | Type | Reads |
|----------|------|-------|
| `Invoke-PluginGSheetStaff` | Source | the staff tab of the sheet from step 5 |
| `Invoke-PluginStaffOverride` | Override | the override tab of the same sheet |
| `Invoke-PluginSkywardSMSStudents` | Source | students from the Skyward SMS OneRoster API (minimal starting point) |

(The other three are **PostRun** templates — end-of-run run reports, user-list CSV
exports, and a webhook. None is needed for a first run; see
[Next steps](#next-steps).)

Edit the placeholder values at the top of each template you'll use — spreadsheet ID,
domain, company, root OUs, password types — and the optional `Get-Custom*Groups` helper
that encodes your group policy. **An unedited template throws** with a message naming the
file, so there's no risk of a half-configured plugin silently running. Then enable it in
the config's `Plugins` array:

```powershell
Plugins = @(
    @{ Enabled = $true; Type = "Source"; Function = 'Invoke-PluginGSheetStaff' }
    @{ Enabled = $true; Type = "Override"; Function = 'Invoke-PluginStaffOverride' }
)
```

A run with no enabled source plugin throws (no source data), so at least one Source plugin
must be enabled before the first run. The plugin contract, record schema, and authoring
checklist for other SIS sources are in [plugins.md](plugins.md).

## 7. Fill in the config

Edit `C:\IDBridge\Config\IDBridgeConfig.psd1` (schema: [configuration.md](configuration.md)):

| Setting | Value |
|---------|-------|
| `GoogleToken.Enabled` | `$true` — the key secret exists now (step 4) |
| `Google.enabled` | `$true` |
| `Google.customerID` | Workspace customer ID (Admin console → Account settings) |
| `Google.userRootOU` | the root OU IDBridge manages, e.g. `/YourDistrict` |
| `AD.enabled` | `$true` if syncing AD |
| `AD.userRootOU` | managed root OU DN, e.g. `OU=YourDistrict,DC=yourdomain,DC=local` |
| `Logging.*` | log-sheet ID from step 5, if using sheet logging |
| `Telemetry.Tier` | keep `'Basic'`, or `'Enhanced'`/`'Off'` (see [PRIVACY.md](../PRIVACY.md)) |

Leave `Debug.ReadOnly = $true` and both `enableGroupProcessingWhatIf = $true` — that's the
point of step 8. The `userRootOU` values matter beyond OU placement: they anchor the
`ChangeThreshold` guard's managed-population count.

## 8. First run (read-only)

```powershell
Invoke-IDBridge -ReadOnly -TestRun -TraceLogging   # capped at 10 records/plugin for fast iteration
Invoke-IDBridge -ReadOnly -TraceLogging            # then the full dataset
```

IDBridge computes every change list — creates, updates, deactivates, moves, renames, group
adds/removes — and writes **nothing**. Iterate here until the log
(`C:\IDBridge\Logs\IDBridge.log`) reports exactly the changes you expect: fix the sheet,
the plugin, or the config and re-run. This is where OU paths, `PersonType` mappings, and
group proposals get proven out.

## 9. Enable writes — incrementally

Flip one brake at a time, with a read-only-style review after each:

1. `Debug.ReadOnly = $false` — user lifecycle writes (create/update/deactivate/move/rename)
   go live. Group changes are still log-only (`WhatIf`), and the `ChangeThreshold` guard
   still aborts any run whose proposed changes exceed `Percentage` (default 25%) of a
   directory's managed population. A fresh/empty root OU is skipped with a `Warn`, so a
   legitimate first population isn't blocked.
2. `enableGroupProcessing = $true` (per directory) with `WhatIf` still `$true` — review the
   group diffs in the log. Add patterns to `groupsExcluded` for any group IDBridge must
   never touch (manually curated clubs, committees).
3. `enableGroupProcessingWhatIf = $false` — group **adds** go live.
4. Later, as trust builds: `enableGroupProcessingRemove`, `enableGroupProcessingTrash`, and
   `Google.enableLicenseRemoval` (see [configuration.md](configuration.md#google-workspace-processing)).

## Next steps

- **Unattended/scheduled runs:** run under a gMSA with the `DpapiNG` secrets provider —
  or grant the gMSA private-key read on the Cms certificate
  (`Grant-IDBridgeCertificatePrivateKeyAccess`). See [secrets.md](secrets.md).
- **Students from a SIS:** a second source plugin (the Skyward OneRoster plugin in
  [plugins.md](plugins.md#invoke-pluginskywardsmsstudents--source-disabled-in-config) is a
  worked example).
- **Run reports, CSV exports, alerting:** the three PostRun templates consume each run's
  results — `Invoke-PluginPostRunReport` (JSON run summary) and
  `Invoke-PluginPostRunExport` (user-list CSVs) work as-is once their descriptors are
  enabled; `Invoke-PluginPostRunWebhook` POSTs a compact summary to your own endpoint.
  See [plugins.md](plugins.md#the-postrun-contract-invoke-postrunplugins).
- **Run-history dashboard:** `Telemetry.Tier = 'Enhanced'`, then claim your SiteID
  (`Get-IDBridgeSiteID`) at [IDBridge Pulse](https://pulse.scnlabs.net).
