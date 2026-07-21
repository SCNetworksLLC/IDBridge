# IDBridge

**IdentityBridge** — automated account provisioning for **Google Workspace** and **Active
Directory** from school SIS / Google-Sheet data. IDBridge reconciles a source list of people
against both directories and creates, updates, deactivates, moves, and renames users, builds
the OUs they belong in, and syncs group membership.

A PowerShell 7.5 module by Sam Cattanach / SC Networks LLC.
Repo: <https://github.com/SCNetworksLLC/IDBridge>

## Requirements

- **PowerShell 7.5+**
- **ActiveDirectory** module (RSAT) — for AD processing
- A **Google service-account** JSON key — for Google Workspace. The service account holds
  a scoped custom admin role (no domain-wide delegation, no admin impersonation); the
  bootstrap sets it all up (see [docs/google-bootstrap.md](docs/google-bootstrap.md)). The
  key is stored in the built-in secret vault (see [docs/secrets.md](docs/secrets.md))

## Quick start

```powershell
# Install from the PowerShell Gallery (Update-Module IDBridge to upgrade later)
Install-Module IDBridge -Scope CurrentUser

Import-Module IDBridge

# First-time setup: scaffold C:\IDBridge (folder tree, default config, plugin templates)
Install-IDBridge

# Safe dry run — computes all changes, writes nothing, verbose logging
Invoke-IDBridge -ReadOnly -TraceLogging
```

`Invoke-IDBridge` is the entry point; `-RootPath` defaults to `C:\IDBridge`.

Setting up a new deployment? Follow [docs/getting-started.md](docs/getting-started.md) —
the ordered walkthrough from a clean machine to a first successful sync.

## Source sheet template

A new deployment reads its people from a Google Sheet. To start from scratch, copy the published
template — **<https://docs.google.com/spreadsheets/d/1OUlm-5WGce_x2z0L1dM2kD8Ejk_f3RNF3EC8sa6uHhE/copy>** — which opens Google's "Make a copy"
prompt and drops a ready-made workbook into your Drive: source and override tabs pre-built with
tables (filter/sort), Process checkboxes, a TerminationDate date column, a Groups reference tab,
and multi-select group dropdowns. Point your source plugin's sheet range at the copied
spreadsheet's ID. Migrating a site that already has AD/Google accounts? Use
`Export-IDBridgeDirectoryToSheet` to seed the sheet from current directory state instead,
scoped to one or more AD and/or Google OU subtrees.

## Safety model

IDBridge **decides, then acts**: it computes every change list read-only first and only writes
when `Debug.readOnly = $false`. The shipped config defaults to `ReadOnly = $true` with group
processing in `WhatIf` mode, so a fresh run reports intended changes without touching AD or
Google. See [docs/architecture.md](docs/architecture.md).

## Telemetry

IDBridge reports **anonymous, aggregate usage counts** (runs, creates/deactivates, duration —
never names, usernames, IDs, or any directory record) to help improve the module. The default
`Basic` tier sends no identifier of any kind; opt-in `Enhanced` adds a random install-scoped
SiteID that unlocks your install's run-history timeline in IDBridge Pulse (below). Disable it
with `Telemetry = @{ Tier = 'Off' }` in config or `-DisableTelemetry` per run, and verify exactly
what's sent with `-TraceLogging`. Full details: [PRIVACY.md](PRIVACY.md).

### IDBridge Pulse

[**IDBridge Pulse**](https://pulse.scnlabs.net) is the companion dashboard for the `Enhanced`
telemetry tier. Claim an install by its SiteID and Pulse shows that install's run history — a
timeline of syncs, per-run counts of users created/updated/deactivated, run success/failure, and
(on failed runs) the exception class and function that threw. To claim one, run
`Get-IDBridgeSiteID` on that server and enter the SiteID at the dashboard. Installs on the default
`Basic` tier or `Off` send no identifier and never appear in Pulse. What each tier transmits — and
the district-data-out privacy posture — is spelled out in [PRIVACY.md](PRIVACY.md).

## Code vs. configuration layout

The **module code** lives in this repo under `src/IDBridge/`. The **configuration, plugins,
and runtime data live outside the repo** under `C:\IDBridge\` (created/used at run time):

```
src/IDBridge/        module (psd1/psm1 + Public/Private/Templates/) — the publishable package
docs/                reference documentation (repo only)
CLAUDE.md            agent/developer onboarding (repo only)

C:\IDBridge\Config\IDBridgeConfig.psd1   configuration   (outside repo)
C:\IDBridge\Plugins\*.ps1                source/override/postrun plugins (outside repo)
C:\IDBridge\{Logs,Exports,Data,Vault}\   runtime dirs incl. the secret vault (outside repo)
```

## Documentation

- [CLAUDE.md](CLAUDE.md) — onboarding / orientation
- [docs/getting-started.md](docs/getting-started.md) — first-run setup: clean machine → first sync (Gallery install)
- [docs/architecture.md](docs/architecture.md) — startup + the full execution pipeline
- [docs/functions.md](docs/functions.md) — every exported function by layer
- [docs/configuration.md](docs/configuration.md) — `IDBridgeConfig.psd1` schema + paths
- [docs/plugins.md](docs/plugins.md) — plugin contract + worked examples
- [docs/secrets.md](docs/secrets.md) — secret vault (Cms/DPAPI-NG), certificate setup & migration
- [docs/google-bootstrap.md](docs/google-bootstrap.md) — Google service-account bootstrap (`Initialize-IDBridgeGoogleServiceAccount`)

## Contributing & releases

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch/PR flow, versioning, and how to publish
to the PowerShell Gallery. Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 SC Networks LLC.
