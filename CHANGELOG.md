# Changelog

All notable changes to IDBridge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use
a calendar scheme `YY.M.D.build` (see [CONTRIBUTING.md](CONTRIBUTING.md#versioning--releases)).

## [Unreleased]

## [26.6.26.2] - 2026-06-26

### Changed
- **Comment-based help on every public function.** All 53 exported functions now carry consistent
  `.SYNOPSIS/.DESCRIPTION/.PARAMETER/.OUTPUTS/.EXAMPLE/.NOTES` help, so `Get-Help <function>` works
  across the whole module. No function logic was changed.

### Fixed
- `Get-Help` now resolves help for `Remove-IDBridgeDuplicateID` (a description line beginning with
  `.Count` was parsed as an invalid help directive, voiding the block) and `New-Passphrase` (its
  leading `#Requires` bound the help to the script rather than the function; help moved into the
  function body).
- Corrected stale parameter docs referencing non-existent parameters: `New-Passphrase` (removed
  `InputFile`/`OutputFile`/`ChunkSize`), `Update-IDBridgeGoogleUser` (documented `RemoveAlias`,
  dropped `tokenInformation`), `New-IDBridgeGoogleOrgUnit` (`OrgUnit`), `Get-GoogleSheetData`
  (`GoogleSheetID`/`GoogleSheetRange`), and added the Skyward safety-check params.

## [26.6.26.1] - 2026-06-26

### Added
- **Change-volume safety guard** (`ChangeThreshold` config block) — after the AD/Google change
  lists are computed and before any writes, the run aborts if a directory's proposed lifecycle
  changes (create/update/rename/move/deactivate) exceed a percentage (default `25`) of its
  managed root-OU population. Protects against a broken source feed mass-changing a directory.
- `Test-IDBridgeChangeThreshold` — pure helper that computes the change percentage and flags a
  breach (population `0` is skipped, not a breach).
- `-SkipChangeThreshold` switch on `Invoke-IDBridge` to bypass the guard for an intentional mass
  run (mirrors `ChangeThreshold.Enabled = $false`).

## [26.6.26.0] - 2026-06-26

### Added
- `Format-IDBridgeName` — title-cases a name (handles spaces, hyphens, apostrophes; null/empty
  safe; pipeline-friendly). The Skyward plugin runs `NameFirst`/`NameLast` through it.

### Changed
- Name comparisons in `Get-ADUsersToUpdate` / `Get-GoogleUsersToUpdate` are now
  **case-sensitive** (`-cne`), so a casing fix from a plugin is applied to existing accounts
  (not just new ones) — the plugin output is the source of truth for name casing.

## [26.6.25.0] - 2026-06-25

### Added
- `New-IDBridgeSourceRecord` — canonical factory for source records (typed/`Mandatory` fields,
  `ValidateSet` on `PersonTypeID`, defaults, one ordered 35-field shape).
- `Test-IDBridgeSourceData` — validates each source plugin's output inside
  `Invoke-SourcePlugins` (cross-field rules + safety net), dropping bad records with a `Warn`
  and continuing (filter-and-log).

- Canonical record gained optional AD attributes — `Description`, `TelephoneNumber`,
  `EmailAddress`, `PasswordNeverExpires`, `ExtensionAttribute2-4` — wired into
  `Get-ADUsersToCreate`/`Get-ADUsersToUpdate` (set-but-don't-clear) and retrieved by
  `Get-TargetDataAD`; plus override flags `ForceDisable`/`GoogleOUOverride` are now declared on
  the record (default `$false`).
- **Per-user directory provisioning** — `ProvisionAD` / `ProvisionGoogle` (renamed from the
  inert `ADEnabled` / `GoogleEnabled`) now control, per user, whether a person is provisioned
  into each directory. Create/update/groups require `IDBActive=true AND Provision<Dir>=true`;
  deactivation (disable + trash) fires on `IDBActive=false OR Provision<Dir>=false`, so
  `IDBActive=false` alone still deactivates everywhere. Use case: younger students get Google
  but no AD (Skyward plugin wires `ProvisionAD/Google` to its per-grade `AD.Enabled`/
  `Google.Enabled`).

### Changed
- `Get-*UsersToSetEmployeeID` no longer gate on `IDBActive` — they link **any** unlinked source
  user (active or not) so a deprovisioned user's existing account can be found and deactivated.
- Source plugins (`Invoke-PluginGSheetStaff`, `Invoke-PluginSkywardSMSStudents`) build records
  via `New-IDBridgeSourceRecord` instead of hand-rolled hashtables; dropped the unused
  Skyward `LastSeen` field so both plugins emit the same shape. *(Plugins live outside the
  repo; this note records the change.)*
- `New-IDBridgeSourceRecord`: dropped vestigial `ADPassPrefix`/`GooglePassPrefix`;
  `GroupsProposed` is now `[string[]]`.

### Fixed
- `Get-GoogleUsersToCreate` read the wrong property (`GoogleChangeAtNextLogin`) so the
  force-password-change-at-next-login flag was never applied at Google account creation; it now
  reads `GoogleChangePasswordAtLogon` (matching the record/AD side).

## [26.6.22.0] - 2026-06-22

### Added
- Reference documentation: `CLAUDE.md` and `docs/` (architecture, functions, configuration,
  plugins, secrets).
- Repo standards: `README.md`, `LICENSE` (MIT), `CHANGELOG.md`, `CONTRIBUTING.md`, `.gitignore`.
- `Get-IDBridgeSecret` — resolves a named secret from a SecretManagement vault, falling back
  to the per-user `*.txt` file store (no behavior change for existing deployments).
- Module manifest metadata: `CompanyName`, `Copyright`, and `PrivateData.PSData`
  (Tags, ProjectUri, LicenseUri, ReleaseNotes).

### Changed
- Restructured the repo so the module lives under `src/IDBridge/`, keeping repo-only files
  (docs, `CLAUDE.md`, README) out of the published package.
- Documented the versioning & release process.

### Fixed
- Corrected misleading log messages: `Get-TargetDataAD` no longer logs "Google", and the
  Google group-refresh trace no longer says "AD".

## [26.6.21.0]

- Baseline release: source ingestion (GSheet / Skyward SMS / Infinite Campus), AD and Google
  Workspace provisioning (create / update / deactivate / OU / group sync), plugin system,
  logging to file and Google Sheet.
