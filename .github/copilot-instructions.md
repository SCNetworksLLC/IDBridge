## IDBridge — Copilot instructions (concise)

This project is a PowerShell-driven identity sync/orchestration tool that synchronizes data from Google Workspace and Active Directory based on JSON configuration files. The goal of this document is to give an AI coding agent the precise, actionable context needed to make safe, useful edits.

- Primary runner: `IDBridge.ps1` (root). This is the orchestration script that:
  - Imports module paths from `C:\IDBridge\Config\ModulePath.json`
  - Calls `Initialize-Logging` and `Get-IDBridgeConfiguration`
  - Requests a Google access token via `Get-GoogleApiAccessToken`
  - Calls source/target functions like `Get-SourceDataGSheet`, `Get-TargetDataGoogle`, `Get-TargetDataAD`.

- Module loading pattern: the module file `IDBridge.psm1` dot-sources all `Public\*.ps1` files and then exports `-Function '*'`. Prefer adding new public functions under the `Public` tree (e.g., `Public/Google`, `Public/Target`, `Public/Core`). A commented `private` sourcing block exists but is not currently used.

- Configuration and environment expectations:
  - Runtime config folder: `C:\IDBridge\Config` (the code reads JSON files from here via `Get-IDBridgeConfiguration`). Files are imported by base filename (spaces -> underscores) into the `$IDBridgeConfig` hashtable.
  - Auth JSON (Google service account) is expected under `IDBridge/Auth` and located via `Get-IDBridgeGoogleAuthFile`.
  - Logs: `C:\IDBridge\Logs\IDBridge.log` with `$logFile` and `$logDate` set globally by `IDBridge.psm1` / `Initialize-Logging`.

- Key flags and safety patterns to respect when making changes:
  - Debug/read-only: `$IDConfig.Debug.readOnly` (many write changes are guarded by `if ($IDConfig.Debug.readOnly -eq $false)`)
  - Group processing toggles: `Google.enableGroupProcessing`, `Google.enableGroupProcessingWhatIf`, `AD.enableGroupProcessing`, etc. Many destructive operations depend on these flags.
  - WhatIf logging: functions call `Write-Log -WhatIfLogging` and respect the above toggles; preserve that behavior.

- Google integration notes:
  - Auth: `Get-GoogleApiAccessToken` builds `$headers` used by `Get-GoogleData`, `Update-GoogleUser`, `New-GoogleUser`, etc.
  - REST pattern: `Get-GoogleData` uses `Invoke-RestMethod` and handles pagination with `nextPageToken` (append `&pageToken=` to the APIUri).
  - Example usage: `Get-TargetDataGoogle -logFile $logFile -headers $headers` returns an object `{ Users, Groups, OrgUnits }`.

- Active Directory integration notes:
  - AD cmdlets (Import-Module ActiveDirectory) are used; the module is expected to exist on the host running the script. Tests in `Get-IDBridgeConfiguration` may abort if AD module missing (unless `Debug.SkipADCHeck` is true).
  - AD operations also use guarded execution via the debug flags.

- Coding conventions and patterns to follow when editing or adding code:
  - Use Verb-Noun function names (PowerShell standard) and `CmdletBinding()` with explicit `param()` blocks.
  - Preserve use of splatting for payloads (see many `@{}` splats when calling `Set-ADUser`, `New-ADUser`, or Google update functions).
  - Logging: use `Write-Log -Path $logFile -Message <...>` rather than Write-Host for operational messages.
  - Avoid mutating global variables (`$logFile`, `$logDate`) unless intentionally changing log behavior.

- Files that exemplify major flows (read before making changes):
  - `IDBridge.ps1` — primary orchestration and run sequence.
  - `IDBridge.psm1` — module loader (dot-sources `Public/*.ps1`) and global variable setup.
  - `Public/Core/Get-IDBridgeConfiguration.ps1` — JSON config loading and feature flags.
  - `Public/Core/Initialize-Logging.ps1` — log rotation and bootstrap logging.
  - `Public/Google/Get-GoogleData.ps1` — REST + pagination helper.
  - `Public/Target/Get-TargetDataGoogle.ps1` — how Google target data is assembled and group mapping is built.

- How to run locally (developer workflow):
  1. Ensure required config files are present under `C:\IDBridge\Config` (e.g., `General.json`, `Google.json`, `GoogleToken.json`, `ModulePath.json`).
  2. Ensure `IDBridge/Auth` contains the Google service account JSON and that the `adminEmail` and scopes are set in `GoogleToken.json`.
  3. Run PowerShell as a user with appropriate permissions (AD actions require RSAT / domain privileges). The main script is `IDBridge.ps1`.
  4. Check `C:\IDBridge\Logs\IDBridge.log` for runtime details; set `Debug.readOnly` in config to avoid making changes while testing.

- Troubleshooting hints for agents making edits:
  - If changes touch AD or Google API surfaces, keep `Debug.readOnly` true and use `enableGroupProcessingWhatIf` to avoid destructive actions while testing.
  - Configuration errors surface as throws from `Get-IDBridgeConfiguration` or `Test-IDBridgeConfiguration`. Inspect JSON file names (spaces -> underscores) and required properties.
  - Missing PS modules: `Get-IDBridgeConfiguration` attempts to import the ActiveDirectory module and will throw unless `Debug.SkipADCHeck` is true.

- Example small task checklist for safe edits:
  - Locate the public function to modify under `Public/<area>`.
  - Add unit-like validations consistent with `Get-GoogleData` (validate inputs, use Write-Log on errors).
  - Preserve existing logging and guard destructive API calls behind the read-only config flag.
  - Run `IDBridge.ps1` locally with the debug flags set and inspect `C:\IDBridge\Logs\IDBridge.log`.

If parts of the runtime environment are missing (local AD, Google credentials), ask for the missing artifact rather than guessing. If you want, I can expand this with CI/PR guidelines or a short checklist for creating new public functions.
