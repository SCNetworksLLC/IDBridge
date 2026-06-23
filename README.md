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
- A **Google service-account** JSON key with domain-wide delegation — for Google Workspace
- *(Optional)* **Microsoft.PowerShell.SecretManagement** — for vault-based secrets
  (see [docs/secrets.md](docs/secrets.md))

## Quick start

```powershell
Import-Module .\src\IDBridge\IDBridge.psd1

# Safe dry run — computes all changes, writes nothing, verbose logging
Invoke-IDBridge -ReadOnly -TraceLogging
```

`Invoke-IDBridge` is the entry point; `-RootPath` defaults to `C:\IDBridge`.

## Safety model

IDBridge **decides, then acts**: it computes every change list read-only first and only writes
when `Debug.readOnly = $false`. The shipped config defaults to `ReadOnly = $true` with group
processing in `WhatIf` mode, so a fresh run reports intended changes without touching AD or
Google. See [docs/architecture.md](docs/architecture.md).

## Code vs. configuration layout

The **module code** lives in this repo under `src/IDBridge/`. The **configuration, plugins,
and runtime data live outside the repo** under `C:\IDBridge\` (created/used at run time):

```
src/IDBridge/        module (psd1/psm1 + Public/) — the publishable package
docs/                reference documentation (repo only)
CLAUDE.md            agent/developer onboarding (repo only)

C:\IDBridge\Config\IDBridgeConfig.psd1   configuration   (outside repo)
C:\IDBridge\Plugins\*.ps1                source/override plugins (outside repo)
C:\IDBridge\{Auth,Logs,Exports,Data}\    runtime dirs (outside repo)
```

## Documentation

- [CLAUDE.md](CLAUDE.md) — onboarding / orientation
- [docs/architecture.md](docs/architecture.md) — startup + the full execution pipeline
- [docs/functions.md](docs/functions.md) — every exported function by layer
- [docs/configuration.md](docs/configuration.md) — `IDBridgeConfig.psd1` schema + paths
- [docs/plugins.md](docs/plugins.md) — plugin contract + worked examples
- [docs/secrets.md](docs/secrets.md) — SecretManagement migration & secret layout

## Contributing & releases

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch/PR flow, versioning, and how to publish
to the PowerShell Gallery. Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE) © 2026 SC Networks LLC.
