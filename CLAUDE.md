# IDBridge — Agent / Developer Onboarding

IDBridge ("IdentityBridge") is a **PowerShell 7.5 module** that provisions and
synchronizes identity accounts in **Active Directory** and **Google Workspace** from
school SIS / Google-Sheet source data. For each person it can create, update, deactivate,
move, and rename users, create the OUs they belong in, and reconcile group membership.
Module version comes from `IDBridge.psd1` (`ModuleVersion`, currently `26.6.21.0`).

> ⚠️ **Code and config/plugins live in DIFFERENT places.**
> - **Code (this git repo):** `C:\GIT\IDBridge`
> - **Config:** `C:\IDBridge\Config\IDBridgeConfig.psd1` *(outside the repo)*
> - **Plugins:** `C:\IDBridge\Plugins\*.ps1` *(outside the repo)*
> - **Runtime dirs** (`Auth`, `Logs`, `Exports`, `Data`) are created under
>   `C:\IDBridge\` by `Initialize-IDBridge` on first run.

## Repo layout

```
src\IDBridge\          # The publishable module package (publish from here)
  IDBridge.psm1        # Loader: dot-sources every Public\**\*.ps1; breaks on import error
  IDBridge.psd1        # Manifest: explicit FunctionsToExport (public surface)
  Public\
    Core\              # Orchestrator, init, config, logging, secrets, helpers
    Source\            # SIS/GSheet ingestion + plugin runner + override merge
    Target\            # Read current AD/Google state; attach it to source records
    AD\                # Active Directory create/update/deactivate/OU/group logic
    Google\            # Google Workspace create/update/deactivate/OU/group logic
    Google\Sheets\     # Sheets API helpers (read/write/format)
  Private\             # (reserved for internal helpers; not loaded yet)
docs\                  # Reference docs (repo only — NOT in the package)
images\                # Logos (non-code, repo only)
CLAUDE.md  README.md  LICENSE  CHANGELOG.md  CONTRIBUTING.md   # repo root (not packaged)
```

> The module lives under `src\IDBridge\` so `Publish-Module -Path .\src\IDBridge` packages
> only the module — `docs/`, `CLAUDE.md`, and README stay in GitHub but out of the package.

Functions are organized one-per-file, named `Verb-Noun.ps1`. The manifest's
`FunctionsToExport` is the source of truth for the public API — internal helpers
embedded inside plugins (e.g. `Get-CustomStaffGroups`) are **not** exported.

## How to run

```powershell
Import-Module C:\GIT\IDBridge\src\IDBridge\IDBridge.psd1
Invoke-IDBridge   # entry point; defaults -RootPath C:\IDBridge
```

Switches (override the config file at runtime):

| Switch           | Effect                                                            |
|------------------|------------------------------------------------------------------|
| `-RootPath`      | Base dir for Config/Auth/Logs/Exports/Plugins/Data (def `C:\IDBridge`) |
| `-ReadOnly`      | Sets `Debug.readOnly`; when `$true`, computes but writes nothing  |
| `-TestRun`       | Sets `Debug.testRun`; plugins process a small subset             |
| `-SkipADCheck`   | Don't fail startup if the AD module can't import                 |
| `-TraceLogging`  | Enable verbose/trace logging                                     |
| `-SkipAD`        | Disable all AD processing for this run                           |
| `-SkipGoogle`    | Disable all Google processing for this run                       |
| `-SkipChangeThreshold` | Bypass the change-volume safety guard (`ChangeThreshold`) for this run    |

## Safety model (read this before changing behavior)

1. **Decide, then act.** The pipeline computes *all* change lists (create/update/
   deactivate/OU/groups) read-only first, then executes them only when
   `Debug.readOnly = $false`. The shipped config defaults `ReadOnly = $true`.
2. **Group writes are double-gated** by `enableGroupProcessing`, plus
   `enableGroupProcessingWhatIf` (log-only), `enableGroupProcessingRemove`
   (allow removals), and `enableGroupProcessingTrash` (strip groups on deactivate).
3. A run that loses Google auth **auto-disables** Google processing rather than erroring out.
4. **Change-volume guard.** After the change lists are computed and before any writes, the
   `ChangeThreshold` config block aborts the whole run if a directory's proposed lifecycle
   changes (create/update/rename/move/deactivate) exceed a percentage (default `25`) of its
   managed root-OU population — protection against a broken source feed mass-changing the
   directory. Bypass with `ChangeThreshold.Enabled = $false` or `-SkipChangeThreshold`.

## Conventions

- **Script-scoped state** set by `Initialize-IDBridge`, read everywhere via accessors:
  `$script:IDBridgeConfig` (→ `Get-IDBridgeConfig`), `$script:Logs`
  (→ `Get-IDBridgeLogs`), `$script:GoogleHeaders` (→ `Get-GoogleHeaders`).
- **`personID`** is the universal join key across source / AD (`EmployeeID`) /
  Google (`externalIds` type `organization`).
- **`Write-Log`** is used for all logging (file + in-memory + optional Google Sheet).
- AD/Google mutations are driven by **`*Splat` hashtables** built in the `Get-*To*`
  functions and splatted into the underlying cmdlet/API call.
- **Secrets** are read via `Get-IDBridgeSecret -Name <name>` (SecretManagement vault →
  `Auth\<user>\<name>.txt` fallback). See [docs/secrets.md](docs/secrets.md).

## Deeper references (`docs/`)

- [docs/architecture.md](docs/architecture.md) — startup + the full ordered pipeline, data-object lifecycle, logging model (start here).
- [docs/functions.md](docs/functions.md) — every exported function by layer: purpose, params, returns, diffing predicates.
- [docs/configuration.md](docs/configuration.md) — full `IDBridgeConfig.psd1` schema, runtime `Paths`, and secret file locations.
- [docs/plugins.md](docs/plugins.md) — plugin contract + output schemas, with the three shipped plugins as worked examples.
- [docs/secrets.md](docs/secrets.md) — SecretManagement migration + secret names/locations.
- [README.md](README.md) — public-facing overview, quick start, and publishing pointers.
