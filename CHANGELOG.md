# Changelog

All notable changes to IDBridge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use
a calendar scheme `YY.M.D.build` (see [CONTRIBUTING.md](CONTRIBUTING.md#versioning--releases)).

## [26.8.27.0] - 2026-08-27

### Added
- **AD service-account bootstrap (`Initialize-IDBridgeADServiceAccount`).** One-command
  AD-side setup for unattended runs: creates the `gMSA-IDBridge` group Managed Service
  Account with this computer's account allowed to retrieve the password (no password
  ever generated or stored; a missing/immature KDS root key is explained, never created
  silently), delegates least-privilege rights on the managed root OU (`AD.userRootOU`
  by default: create OUs only — no OU delete/modify; create + full control over
  descendant user objects — Delete included, required by `Move-ADObject` for OU moves
  and trash; write the `member` attribute of descendant group objects only — no group
  create/delete), and grants the gMSA private-key read on the Cms certificate via the
  existing `Grant-IDBridgeCertificatePrivateKeyAccess` (auto-resolved like
  `Set-IDBridgeSecret`; `-SkipCertificateAccess` for DpapiNG/AzKeyVault sites).
  Idempotent — re-runs add missing computer principals/ACEs and touch nothing else.
- **Scheduled-run registration (`Register-IDBridgeScheduledTask`).** Host-side
  follow-up: installs and verifies the gMSA on this computer (a stale-Kerberos-ticket
  failure right after account creation is fixed automatically — the computer's tickets
  are purged and the install retried once before a reboot is suggested), grants it the
  'Log on as a batch job' right (new internal `Grant-IDBridgeBatchLogonRight`, a
  built-in P/Invoke over `advapi32` `LsaAddAccountRights`; local — a GPO managing the
  right still wins) and the filesystem rights a run needs (read on the module folder
  and runtime root, modify on `Logs`/`Exports`/`Data`), and registers a Task Scheduler
  task running `Invoke-IDBridge -RootPath <root>` in pwsh as the gMSA every
  `-IntervalMinutes` (default 15, midnight-aligned; `-LogonType Password`, no stored
  credential; never overlaps a still-running run, hung runs killed after 1 hour). The
  task is **created disabled** unless `-Enabled` is passed — verify with
  `Start-ScheduledTask`, then `Enable-ScheduledTask`. Re-running replaces the task.
- **Single-run lock.** `Invoke-IDBridge` now takes a machine-wide named mutex (per
  RootPath, `Global\` so a console session and the scheduled task's session 0 see the
  same lock) before initialization; a second concurrent run aborts immediately with
  "another IDBridge run is already in progress" — before any shared write, no telemetry
  or PostRun side effects. ReadOnly and Preview runs hold the lock too: they still write
  the shared log file and the source plugins' `Data` state CSVs, and a preview racing a
  live run would show half-applied state. A mutex rather than a lock file so the OS
  releases it when a run dies holding it (a kill at the task's execution time limit
  included) — it can never go stale. Complements, not replaces, Task Scheduler's own
  no-overlap policy: the lock covers interactive-vs-scheduled collisions.
- **docs/ad-bootstrap.md** — the AD counterpart to google-bootstrap.md: both functions,
  the exact delegation ACE table, the moves-require-Delete caveat, the "never place
  privileged accounts under the managed root OU" rule, KDS root key and
  "Log on as a batch job" prerequisites, verification and recovery steps. Getting-started's
  unattended-runs pointer now leads here.

## [26.8.22.0] - 2026-08-22

### Added
- **Pester test suite (`tests\`).** First tests for the module, runnable on any OS with
  PowerShell 7.5+ and Pester 5.5+ (`Invoke-Pester -Path .\tests`) — no AD, Google, or
  `C:\IDBridge` needed. Structural tests (`IDBridge.Module.Tests.ps1`) lock down the
  packaging rules: every module file parses, one `Verb-Noun` function per file, `Public\`
  matches `FunctionsToExport` exactly, `Private\` is never exported. Unit tests cover
  `Format-IDBridgeName` and `Get-ADUserGroupsToUpdate`, the latter establishing the
  pattern for testing the Private\ decision functions (`InModuleScope` + mocked
  `Write-Log` + `New-TestADRecord` fixtures from `tests\TestHelper.psm1`). See
  `tests\README.md` for conventions. Tests live outside `src\IDBridge` so they are
  never packaged.
- **Decide-phase test coverage for the sync pipeline.** Unit tests for the change-volume
  safety guard (`Test-IDBridgeChangeThreshold`, including the inclusive-limit boundary and
  the zero-population skip), duplicate-personID removal (`Remove-IDBridgeDuplicateID`), and
  the full AD + Google change-list planner family: `Get-ADUsersToCreate` / `ToDeactivate` /
  `ToSetEmployeeID` / `ToUpdate` and `Get-GoogleUsersToCreate` / `ToDeactivate` /
  `ToSetEmployeeID` / `ToUpdate` / `Get-GoogleUserGroupsToUpdate` — covering the safety
  behaviors (never add unknown groups, username/UPN collision skips, set-but-don't-clear,
  ForceDisable suspend-not-archive, approved-name-mismatch linking, OU override). The test
  helper gains `New-TestADUser` / `New-TestGoogleUser` fixture factories (and
  `New-TestADRecord` is now `New-TestSourceRecord`).
- **Tests for the remaining decide-phase functions.** The OU planners
  (`Get-ADOrgUnitsForProcessing` / `Get-GoogleOrgUnitsForProcessing`: ancestor expansion,
  parents-before-children ordering, dedupe, existing-OU filtering), the `-Preview` row
  flattener (`ConvertTo-IDBridgePreviewRow`: apply-order rows, password column gated on
  `-ShowPasswords`, SecureStrings rendered `(secure)` in Changes), and the source toolkit
  (`New-IDBridgeSourceRecord` defaults/normalization/validation, `Test-IDBridgeSourceData`
  cross-field rules and safety net).
- **CI: `Tests` workflow.** `.github/workflows/tests.yml` runs the Pester suite on
  ubuntu-latest for every push and pull request.
- **CLAUDE.md: Tests section.** How to run the suite, plus the Claude Code cloud-session
  recipe (PSGallery is blocked there: PowerShell comes from the GitHub release tarball,
  Pester from its nuget.org package).
- **Publish workflow: `workflow_dispatch` release path.** The `Publish` workflow can now
  be dispatched (Actions → Publish → Run workflow, or the GitHub API) as an alternative
  to pushing a `v*` tag: it reads `ModuleVersion` from `main`, refuses to run if that
  version's tag already exists, mints the `v<version>` tag itself, then publishes to the
  Gallery and creates the GitHub Release as before. Lets environments that can push
  branches but not tags (e.g. Claude Code cloud sessions) cut a release; the tag-push
  path is unchanged.

### Fixed
- **`Get-ADOrgUnitsForProcessing`: a one-OU DN was mangled into an invalid create
  proposal.** With exactly one `OU=` component (e.g. a root-level `OU=Trash,DC=x`),
  `Where-Object` unrolled the component list to a plain string and the ancestor slice then
  indexed characters, proposing the invalid DN `O,DC=x` — on every run, even when the real
  OU already existed (the mangled name never matched). Live runs would try to create that
  DN and fail. Found by the new OU-planner tests; multi-level OU paths were unaffected.

### Changed
- **Docs: CONTRIBUTING.md release steps now include the merge to `main`.** A release
  always ships from `main`: fold the changelog and bump `ModuleVersion` on the work
  branch, merge to `main` via PR, then tag the merge commit — the tag push triggers the
  Gallery publish. Also notes that Claude Code cloud sessions can push branches but not
  tags, so the tag step runs from a normal clone.

## [26.8.21.0] - 2026-08-21

### Added
- **`Invoke-IDBridge -Preview`: review the proposed changes as a table, no CSV export
  needed.** Forces ReadOnly, runs the exact pipeline a live run would (same plugins,
  matching, plan phase), and emits every proposed change as flat row objects —
  `Directory / Action / PersonID / Name / Account / Building / OrgUnit / Password /
  Changes` — for `Format-Table` / `Where-Object` / `Out-GridView` review
  (`Invoke-IDBridge -Preview | Format-Table`). Rows cover OU creates, deactivations
  (Google rows list the licenses removal would strip), updates (compact changed-property
  summary), renames/moves (old → new), creates, and per-group membership changes. Preview
  runs stay quiet: no telemetry, no PostRun plugins, no Google Sheet log push, and a
  tripped `ChangeThreshold` logs a warning and continues instead of aborting — a preview
  exists to review exactly those changes. New internal `ConvertTo-IDBridgePreviewRow`
  does the flattening.
- **`-ShowPasswords`** (with `-Preview`): fills the Password column for pending creates,
  decoded at emit time and never logged. Keysmith passphrases are deterministic, so the
  previewed password is the one the real run will set; without the switch the column is
  empty.

### Fixed
- **Module loader: `Private`/`Public` glob casing.** `IDBridge.psm1` globbed
  `\private\*.ps1` / `\public\*.ps1` while the folders are capitalized — harmless on
  Windows, but on a case-sensitive filesystem (Linux, e.g. Claude Code cloud sessions)
  the module imported with zero functions. The globs now match the real folder names.

### Changed
- **The gather phase now lives in one place: new internal `Get-IDBridgePipelineData`.**
  `Invoke-IDBridge` and `Approve-IDBridgeNameMismatch` carried verbatim copies of the
  Google auth → source plugins → target data → enrich → dedupe → override-merge sequence;
  both now call the shared function, so a gather-phase fix lands in the rarely-run
  onboarding tool automatically instead of silently drifting. Pure refactor — no behavior
  change (the only visible difference is log ordering: the "Gather Source & Directory
  Data" phase line now precedes the Google auth messages it wraps).

## [26.8.20.0] - 2026-08-20

### Changed
- **Docs: full staleness pass — every doc verified against the code.** functions.md:
  `New-Passphrase` entry brought up to Keysmith 2.0 (default
  `https://keysmith.scnlabs.net`, `x-api-key` header, `-Rev` parameter, rev logging — the
  code changed in 26.7.24.0, the entry hadn't); `Show-GroupsNotProcessed` gains its
  mandatory `-Directory` param (added in 26.7.13.1); ten previously-undocumented internal
  helpers get 🔒 entries (`Add-IDBridgeWriteResult`, `Add-IDBridgeGoogleBatchResult`,
  `Hide-IDBridgeSecureString`, `Test-IDBridgeUpdateAvailable`,
  `Get-IDBridgeTemplateVersion`, `Resolve-IDBridgeCmsCertificate`,
  `Import-IDBridgeDpapiNGType`, `Get-IDBridgeAzKeyVaultContext`,
  `Get-IDBridgeAzureAuthToken`, `Get-IDBridgeGoogleScope`); the AD update entry now says
  the UPN is written only as part of a username change (and the collision check is scoped
  to that case); the Google alias-conflict note now says a primary-email collision skips
  the user's entire update that run, not just the rename; OU-planner entries note the
  active-users-only scope and the real (parents-before-children) ordering; the AD linking
  entry documents that a just-linked user's groups come from an unfiltered query, so
  `AD.groupsExcluded` applies to them from the next run.
- **Docs: architecture.md pipeline diagram corrected.** `-DisableTelemetry` added to the
  switch-override list, with a note that overrides land after `Initialize-IDBridge` (so
  `-SkipADCheck`/`-SkipAD` can't rescue a failed AD import at startup — use the config
  keys for that); `Add-TargetDataAD` runs before `Add-TargetDataGoogle`; the Google
  execute step now shows the deactivate group-strip pass and puts license removal after
  it; the Run Summary log block appears as step 11b; `Applied` results are recorded in
  steps 10–11 (not 6–11); the outer catch is documented as log-and-continue (no re-throw
  to the caller); linking is by username+name (AD `SamAccountName` / Google
  `primaryEmail`), and `GoogleCurrentLicenses` joins the data-lifecycle list.
- **Docs: configuration.md defaults and attributions corrected.** `enableLicenseRemoval`
  is on when the key is absent but the shipped template sets `$false` (the old "default
  on" wording read as if a fresh install removes licenses) — same correction in CLAUDE.md
  and functions.md; `ChangeThreshold.Percentage` has no code fallback (the shipped config
  sets 25); `TraceLogging` ships `$true`; `Google.enabled` is not read by
  `Get-TargetDataGoogle`; `Logging.SheetID` is read in `Invoke-IDBridge`'s finally block,
  not by `Push-LogsToSheet`; the Plugins example notes all eight shipped descriptors are
  disabled.
- **Docs: plugins.md contract fixes.** A missing plugin file is tolerated when the
  function already exists in the session (the `Get-Command` check is the real gate); a
  Source/Override plugin that throws aborts the whole run (unlike the isolated PostRun
  contract); the duplicate `IDBActive` row is gone; `ThresholdResults` documents its full
  six-property shape; `Google.UsersToUpdate` is documented as a flat array (only the AD
  side has `UpdateList/RenameList/MoveList`); the GSheet staff worked example now
  describes the bundled group helper that actually ships.
- **Docs: keysmith.md fixed and linked.** The vault example used a nonexistent
  `-Value` parameter (now `Set-IDBridgeSecret -Name … ` prompting) and invented secret
  names (now the shipped `ApiKey-Passphrase` / `ApiKey-PassphraseNonceStaff` /
  `ApiKey-PassphraseNonceStudent`); `New-Passphrase` is exported, not module-internal; the
  doc is now listed in README.md and CLAUDE.md (it wasn't linked from anywhere).
- **Docs: smaller corrections.** getting-started.md counts eight shipped plugin templates
  (said six since 26.7.22.0 added two); README's secrets line mentions the Azure Key Vault
  provider; CONTRIBUTING notes CI publishes with `Publish-PSResource`; PRIVACY.md notes
  the `Telemetry.Endpoint` override. Docs only — no behavior change.

### Fixed
- **`AD.groupsExcluded` now applies to users linked during the run.**
  `Get-ADUsersToSetEmployeeID` populated a just-linked user's group list from a fresh,
  unfiltered AD query, so on the run that linked a user (typically onboarding runs, when
  linking is heaviest) excluded groups could reach the group-remove list or the deactivate
  group strip. It now reuses the exclusion-filtered `CurrentGroups` from the target
  snapshot — matching how the Google side has always worked, and dropping a live
  `Get-ADGroup` round trip per linked user.
- **`-SkipADCheck` and `-SkipAD` now take effect at startup.** Both switches were applied
  after `Initialize-IDBridge` had already imported the AD module, so neither could prevent
  the startup throw on a machine without RSAT (`-SkipADCheck` was fully inert; `-SkipAD`
  still disabled processing but not the import). `Invoke-IDBridge` now forwards them into
  `Initialize-IDBridge`, which applies them to the loaded config before the import — the
  documented behavior, now real. Config-file behavior is unchanged, and
  `Initialize-IDBridge` gains the two optional switches for standalone use.
- **`Get-GoogleData` pagination no longer assumes a query string.** The `pageToken` was
  always appended with `&`, which would malform the follow-up URI for a base URI without
  one. Every current caller passes a query string, so nothing was broken in practice —
  the helper now picks `?` or `&` as the URI requires. Also corrected the
  `Get-IDBridgeGoogleScope` doc comment that still called license removal "on by default"
  (the shipped config template sets `enableLicenseRemoval = $false`).

## [26.8.19.0] - 2026-08-19

### Added
- **Interactive name-mismatch approval: `Approve-IDBridgeNameMismatch`.** New onboarding
  cmdlet that gathers the same source and directory data the pipeline would, finds every
  unlinked source user whose username is taken by an account with a different name, and
  walks them one at a time in the console (`[A]pprove / [S]kip / [Q]uit`) showing the SIS
  and directory names side by side. Approvals persist to
  `<DataRoot>\ApprovedNameMismatches.csv` (each saved as it is made) — no directory writes
  happen in the review; the next `Invoke-IDBridge` run links approved accounts through the
  normal gated pipeline, where the update pass sets the EmployeeID and renames the account
  to the SIS name. AD and Google are approved independently, and an approval is honored
  only while the account's username and directory name still match what was approved — a
  drifted account is skipped with a warning and shows up for re-approval.

### Changed
- **Name-mismatch log lines now show both sides.** When EmployeeID linking finds the
  username taken by a different name, the AD and Google error lines now include the
  source (SIS) name alongside the directory name, so the mismatch can be resolved
  without looking up the source record.

## [26.7.24.0] - 2026-07-24

### Changed
- **`New-Passphrase` updated for Keysmith 2.0.** The passphrase service moved to
  `https://keysmith.scnlabs.net` (new default `-FunctionUrl`; the old
  `passphrase.azurewebsites.net` endpoint is pending decommission), and the API
  token is now sent in the `x-api-key` header — the Static Web App proxy
  overwrites `Authorization` before it reaches the API. New optional `-Rev`
  parameter pins a word-list revision (omit for the server's latest), and every
  call logs the rev used so account-creation runs record which era their
  passphrases belong to. Per-school tokens are minted in the Keysmith admin UI
  and stored in each school's vault as before; no config or plugin changes
  required.

### Added
- `docs/keysmith.md` — how IDBridge integrates with Keysmith: registering a
  district (invite → org admin → self-service staff access), provisioning the
  per-school token + nonce into the vault, and the operational rules
  (x-api-key header, word-list rev logging, annual renewal).

## [26.7.22.1] - 2026-07-22

### Changed
- **EmployeeID-link discovery logs one outcome line per user.** `Get-ADUsersToSetEmployeeID`
  and `Get-GoogleUsersToSetEmployeeID` previously logged a flat "No user found with
  EmployeeID" for every unlinked user and the "Matched" line came from `Invoke-IDBridge`
  a whole phase later, so on a first run the discovery sweep and its results appeared as
  two separate blocks. Each user now gets a single line at the point of decision:
  matched-by-username+name → "will link EmployeeID" (Info), no match → "treated as new"
  (Trace), inactive with no account → "nothing to reconcile" (Trace, unchanged), username
  taken by a different name → Error (unchanged). The duplicate caller-side "Matched"
  lines are removed; matching behavior itself is untouched.

## [26.7.22.0] - 2026-07-22

### Added
- **Orphan-report PostRun plugin template** (`Invoke-PluginPostRunOrphanReport`): reports
  enabled directory accounts with a PersonID link (AD `EmployeeID` / Google `externalId`
  type `organization`) that matched no source record this run — accounts the pipeline can
  never update or deactivate because nothing feeds them. Writes
  `OrphanReport-<timestamp>.csv` to `ExportsRoot` and logs a Warn with counts; skips
  failed runs and TestRuns; report-only, no placeholders. To support it, the RunResult
  gains `AD.CurrentUsers` / `Google.CurrentUsers` (additive, the run's fetched directory
  user lists).
- **Graduate grace windows in both student plugin templates.** Skyward (TemplateVersion 2):
  `GD` students now stay provisioned and active until `$GraduateActiveUntil` (default
  `09/01`) of their `GradYr`, then deactivate — the old immediate-deactivate GD override
  is kept as a commented-out alternative. Infinite Campus: Grade-12 students who disappear
  from the feed (IC drops graduates rather than flagging them) age out after
  `$DaysLastSeenGraduate` (default 90) instead of `$DaysLastSeen` (14); past the normal
  14-day window they're relabeled `GD`, parking them in the `Grade-GD` OU/groups for the
  rest of the grace — the same visible 12 → GD → Trash progression as Skyward.
- **Infinite Campus students plugin template** (`Invoke-PluginInfiniteCampusStudents`),
  modeled on the Skyward SMS one: same per-grade settings/OU/group model, client secret
  from the new vault secret `ApiKey-InfiniteCampus`, password types limited to
  `RANDOM`/`API-PASSPHRASE` (Infinite Campus OneRoster has no FSPIN/word source), and
  `IDBActive` additionally driven by the IC-provided signals (`Status`,
  `ActiveUserAccount`, past `RoleEndDate`). Shipped disabled in the config template.

### Changed
- **`Get-SourceDataInfiniteCampus` brought to parity with `Get-SourceDataSkywardSMS`:**
  new mandatory `-SafetyCheckCount`/`-SafetyCheckPercentage` (throws below the floor to
  prevent mass changes from a truncated pull), `LastSeen` stamping + prior-run state merge
  via `InfiniteCampus_Students_User_State.csv` in `DataRoot` (keyed by `SourcedId`), and an
  optional `-ExcludeSchoolIdentifiers` filter (drops students whose primary school's
  identifier matches). Also: the primary-role pick now falls back to the first role when no
  `primary` exists (as the comment always claimed), and the "users" log messages/doc
  comment now say students.
- **Skyward students plugin template (TemplateVersion 2): `LastSeen` orphan check now
  casts to `[datetime]`.** Fresh-pull records carry `LastSeen` as a string, so the old
  bare comparison coerced the DateTime threshold to a string and only passed by a quirk
  of string ordering (always true for fresh records); state-file records were already
  DateTime and compared correctly. No behavior change today — the cast makes the
  comparison real instead of accidental. Installed copies get the standard
  "newer template available" notice from `Install-IDBridge`.

## [26.7.21.4] - 2026-07-21

### Changed
- **`Push-LogsToSheet` is atomic and caps the log sheet at 50,000 rows.** The header
  write (new sheets), row insert, entry write, and a new bottom-row trim now go in a
  single `spreadsheets.batchUpdate` (requests apply in order, all-or-nothing), so a
  failure mid-push can no longer leave blank rows under the header, and the redundant
  metadata re-fetch after sheet creation is gone (the addSheet reply already returns the
  sheetId). Once the sheet passes 50,000 rows the oldest (bottom) rows are trimmed in the
  same call, keeping the newest 25,000. Cells are still written as literal strings.

## [26.7.21.3] - 2026-07-21

### Changed
- **`Get-GoogleUserGroupsToUpdate` logs group names on the Remove side.** The
  "Proposed: Remove Groups" log line previously showed each group's email address
  (current memberships come back from Google as emails); it now maps them to the
  group's name via the existing name/email lookup, matching the Add side. Groups
  whose email isn't in the fetched GoogleGroups still log as the email. The Remove
  list itself is unchanged (the API calls need emails).

## [26.7.21.2] - 2026-07-21

### Added
- **`Export-IDBridgeDirectoryToSheet -PersonIDCsv`.** Optional CSV (ID and Username columns,
  e.g. from a SIS export) that fills in `PersonID` for exported people whose directories
  carry no ID, matched case-insensitively on Username. A directory ID still wins a mismatch
  with the CSV (logged as a warning), consistent with the existing AD-over-Google rule.

## [26.7.21.1] - 2026-07-21

### Changed
- **`Export-IDBridgeDirectoryToSheet` now writes a `GroupsSeed-<yyyy-MM-dd>` tab and splits
  the group dump per directory.** `ApplicationGroups` now holds only the person's current AD
  group names and `EmailGroups` their Google group names (previously everything was merged
  into `ApplicationGroups` and `EmailGroups` was blank). The new second tab (name via
  `-GroupsSheetName`) lists the distinct group names in use — Google groups under an `Email`
  header in column A, AD groups under an `Application` header in column C — ready to use as
  the source range for multi-select group dropdowns on the staff sheet. The existing-tab
  guard covers both tabs, and the return object gains `GroupsSheetName`.

## [26.7.21.0] - 2026-07-21

### Changed
- **`Export-IDBridgeDirectoryToSheet` now accepts multiple OU scopes.** `-ADSearchBase` and
  `-GoogleOrgUnitPath` are now `[string[]]` — pass one or more OUs per directory and a user
  under any of them is included. Trailing slashes on Google OU paths are now normalized away
  (previously `/District/Staff/` missed users sitting directly in that OU). Single-OU calls
  otherwise behave exactly as before.

## [26.7.13.2] - 2026-07-13

### Added
- **Automated releases.** New `Publish` GitHub Actions workflow: pushing a `v*` tag now
  validates the manifest (and that the tag matches `ModuleVersion`), publishes the module
  to the PowerShell Gallery, and creates a GitHub Release using that version's changelog
  section as the notes. Requires a `PSGALLERY_API_KEY` repository secret; CONTRIBUTING.md's
  publishing section updated to match, keeping the manual steps as a fallback.

### Changed
- **Docs: staleness pass across the repo docs and READMEs.** getting-started.md and the
  repo CLAUDE.md said three plugin templates ship (six do — the PostRun report, webhook,
  and export templates were missing); plugins.md's source-of-truth links still pointed at
  the old `Public\` paths for `Invoke-SourcePlugins`/`Invoke-PostRunPlugins` (moved to
  `Private\` in 26.7.13.1); the README quick start skipped the `Install-IDBridge`
  scaffold step and its layout section predated `Private\`/`Templates\`; functions.md's
  `Invoke-IDBridge` entry still claimed the inline CSV export (moved to the PostRun
  export plugin in 26.7.13.0); architecture.md and functions.md now mention the run-start
  update check; CONTRIBUTING.md now covers the Public/Private split and the
  `# TemplateVersion` bump rule; PRIVACY.md gains a "Not telemetry: the update check"
  section disclosing the PowerShell Gallery version query. Docs only — no behavior change.

## [26.7.13.1] - 2026-07-13

### Added
- **Template versioning.** Every shipped plugin template and the config template now
  start with a `# TemplateVersion: <n>` marker (all start at v1), bumped when the
  template meaningfully changes. On re-run, `Install-IDBridge` compares the marker in
  each installed copy against the shipped template and prints a "newer template
  available" notice pointing at the shipped file — so a district can see that a template
  has improved since they scaffolded, without IDBridge ever touching their edited copy.
  A copy without the marker (all pre-existing installs) reads as unversioned and gets
  the notice too. Leave the marker line in place when customizing a template.

### Changed
- **BREAKING: `New-IDBridgeConfig` renamed to `Install-IDBridge`** (no alias). The old
  name described a fraction of what it does — the function scaffolds the whole install
  (folder tree, config, plugin templates), and setup now reads as a natural pair:
  `Install-Module IDBridge`, then `Install-IDBridge`. Docs and template headers updated.
- **`Install-IDBridge` is now safe to re-run on an existing install.** It no longer
  throws when the config file exists — it skips the config (and any existing plugin
  file) with a notice and still creates whatever is missing. Re-running it after a
  module update is now the supported way to pick up newly shipped plugin templates
  (e.g. `Invoke-PluginPostRunExport` from 26.7.13.0, which previously had to be copied
  by hand). Nothing existing is ever overwritten, same as before.
- **BREAKING: public API narrowed to the supported surface (70 → 34 exports).** The sync
  pipeline's internals — change-list planners (`Get-AD*/Get-Google*ToCreate/ToUpdate/
  ToDeactivate/ToSetEmployeeID`, group planners), target-data readers (`Get/Add-TargetData*`),
  directory writers (`New/Update-IDBridgeGoogleUser`, `Update-GoogleGroupMembers`,
  `Disable-IDBridgeADUser`, `New-IDBridge*OrgUnit`, `Invoke-GoogleBatchRequest`,
  `Remove-IDBridgeGoogleUserLicense`), plugin runners (`Invoke-SourcePlugins`,
  `Invoke-PostRunPlugins`, `Merge-IDBridgeOverrideData`), and run machinery
  (`Test-IDBridgeChangeThreshold`, `Remove-IDBridgeDuplicateID`, `Show-GroupsNotProcessed`,
  `Send-IDBridgeTelemetry`, `Push-LogsToSheet`, `Get-GoogleData`,
  `Get-GoogleApiAccessToken`) — moved to `Private\` and are no longer exported. They are
  called only by `Invoke-IDBridge`; nothing a plugin or admin session calls was removed
  (verified against the shipped templates and live plugins). Still exported: run/setup
  commands, the secrets vault, Google auth/bootstrap, the plugin toolkit (source readers,
  record factory, Sheets helpers, `Write-Log`/`Get-IDBridgeConfig`/`Get-IDBridgeSecret`),
  and diagnostics (`Get-GoogleUsersOrphaned`, `Get-IDBridgeSiteID`). If a custom script
  called an internal function, reach it with `& (Get-Module IDBridge) { <function> ... }`
  — or open an issue and it can be promoted back. docs/functions.md now marks internal
  functions with 🔒.
- **Every log line is now self-contained.** Follow-up consistency pass on the run log:
  the proposed create/update lines carry their properties JSON inline (matching the
  `Applying:` format) instead of logging a bare unprefixed JSON line after, and the
  "Current groups for" lines carry the group list inline — so a line filtered or sorted
  out of context (e.g. in the Google Sheet log) still identifies itself.
  `Show-GroupsNotProcessed` logs one line listing all missing groups instead of one line
  per group, and gains a mandatory `-Directory` parameter so the line says AD or Google.
  The access-token and source-row-skip messages gain their `Google:`/`Source Data:`
  prefixes. Log-wording change only — no behavior change.

## [26.7.13.0] - 2026-07-13

### Added
- **Update check (notify-only).** `Invoke-IDBridge` now checks the PowerShell Gallery for
  a newer stable IDBridge release at the start of every run and logs a warning ("run
  `Update-Module IDBridge`") when one exists. Nothing is ever auto-installed, and the
  check is fully self-contained — offline or gallery-blocked environments log a Trace
  skip and the run proceeds unaffected (10 s timeout).
- **User list CSV export plugin.** New PostRun template `Invoke-PluginPostRunExport`
  writes the user list CSVs defined in its `$exportFiles` map (file name → the
  `PersonTypeID`s it carries; one file can combine multiple IDs) to `Exports`, for
  feeding downstream systems. Defaults to `UserList-Staff.csv` (`'2','3'`) and
  `UserList-Students.csv` (`'1'`); the file map and column list are editable in the
  template. Exports are skipped on failed runs and on TestRun so a partial dataset never
  overwrites the last good export. No placeholders — works as-is once enabled. **Replaces the hardcoded
  `UserList-Staff.csv` staff export that `Invoke-IDBridge` wrote directly** — existing
  installs that rely on that file should add the plugin descriptor
  (`@{ Enabled = $true; Type = "PostRun"; Function = 'Invoke-PluginPostRunExport' }`) and
  copy the template into `PluginsRoot`.

### Changed
- **Log phases are now labeled.** The run log gains phase banners (`Phase: Gather Source
  & Directory Data`, `Phase: Plan Changes`, `Phase: Apply Changes` — the latter noting
  when ReadOnly skipped it), and the per-user lines are prefixed by phase: change-list
  computation logs `AD:/Google: Proposed: ...` while the write phase logs
  `AD:/Google: Applying: ...`, so a line is self-identifying even in isolation.
  Log-wording change only — no behavior change.
- **Source sheet row count now reflects real users.** `Get-SourceDataGSheet` counts only
  populated rows (PersonID present) instead of every row in the sheet range, so blank
  future-use rows no longer inflate the "Successfully retrieved N Users" log line — and,
  more importantly, no longer pad the `userCount` safety floor. The floor now guards the
  populated-row count; a site whose `userCount` was calibrated against the inflated
  number could newly trip it (the log shows both counts).
- **Default config template is now a shipped file.** `New-IDBridgeConfig` copies
  `Templates\Config\IDBridgeConfig.psd1` instead of writing an embedded here-string —
  same generated config, plus the new export plugin descriptor. Refactor only; existing
  configs are untouched (and still never overwritten).

## [26.7.12.4] - 2026-07-12

### Fixed
- **AD deactivation group-strips are now recorded as `GroupRemove` write results.** The
  group removals `Disable-IDBridgeADUser` performs on deactivation (when
  `enableGroupProcessingTrash` is on) happened invisibly inside the function — a
  deactivated user's run showed `GroupRemove = 0` even though groups were stripped. Each
  removal is now its own write result (feeding `Applied`, `Counts.GroupRemove`, and
  telemetry's `groupRemoveCount`, matching the Google trash-strip batch, which was
  already counted). Behavior refinement: one failed group removal is logged and skipped
  instead of aborting the remaining groups and marking the whole deactivation failed —
  the account is already disabled and trashed at that point, and the disable/move steps
  still return their error as before.

### Changed
- **Report template gains the full write journal.** `Invoke-PluginPostRunReport`'s
  `Applied` section adds `Writes` — one line per attempted write (timestamp, directory,
  action, PersonID, target, outcome), the complete "what did the run do" record, not just
  the failure lines. New scaffolds only, as always — existing copies in `PluginsRoot` are
  never overwritten, though they keep working unchanged.
- **Docs: count semantics clarified — directory writes, not people.** PRIVACY.md, the
  `Send-IDBridgeTelemetry` help, and the RunResult schema in docs/plugins.md now state
  explicitly that the create/update/deactivate/failure counts are one per directory
  write, so a person provisioned to both AD and Google counts twice (`managedCount` is
  the per-person number). Wording only — no behavior change.

## [26.7.12.3] - 2026-07-12

### Added
- **Structured per-user write results (`Applied`).** Every attempted directory write
  (create, update, rename, move, deactivate, group add/remove — AD and Google, including
  batched Google calls, whose responses were previously discarded) now records a
  structured outcome: `Directory/Action/PersonID/Target/Success/Error`. The RunResult
  passed to PostRun plugins gains an `Applied` list plus `Counts.Failed`, and the counts
  now reflect **actual outcomes** instead of intended work — a partially failed run
  reports what really happened. A whole failed Google batch chunk is attributed to each
  of its requests ("no batch response"). Telemetry gains `writeFailureCount` (a count
  only — which users/groups failed never leaves the machine; see PRIVACY.md), and its
  action counts are now actual successes. The shipped report template gains an `Applied`
  section with one line per failed write; the webhook template gains `writeFailureCount`.
  Not covered (log-only): Google license removals and OU creation.

### Fixed
- **`Disable-IDBridgeADUser`'s returned ErrorRecord no longer leaks to pipeline output.**
  The deactivate loop now captures the return value (it doubles as the write result) —
  previously a failed AD deactivate emitted the raw ErrorRecord to the caller's pipeline.

## [26.7.12.2] - 2026-07-12

### Added
- **PostRun plugins — an end-of-run extension point.** A third plugin `Type = "PostRun"`
  (alongside `Source`/`Override`) for shipping your own telemetry, dashboards, or change
  reports. `Invoke-PostRunPlugins` runs the configured PostRun plugins from the `finally`
  block of `Invoke-IDBridge` — after usage telemetry, before the Google Sheet log push —
  on **every** run, including failed and ReadOnly runs. Each plugin receives a single
  `-RunResult` object (`SchemaVersion` 1): outcome + full `ErrorRecord`, timing, effective
  mode flags, applied-work counts (same semantics as telemetry), threshold results, the
  enriched source data, and the per-directory change lists. Every SecureString in the
  graph (account keys, passphrase-API secrets) is scrubbed to `$null` before any plugin
  sees it. Plugin failures are isolated: a throwing PostRun plugin logs a `Warn` and can
  never fail the run or mask its outcome. Two new templates ship with the module:
  `Invoke-PluginPostRunReport` (run-summary JSON to `Exports`, works as-is) and
  `Invoke-PluginPostRunWebhook` (compact summary POST to your own endpoint). Documented
  in [docs/plugins.md](docs/plugins.md).

## [26.7.12.1] - 2026-07-12

### Added
- **Group-change counts in run telemetry.** The Pulse payload now includes
  `groupAddCount`/`groupRemoveCount` — group memberships added/removed this run,
  matching the Run Summary's GroupAdd/GroupRemove figures. Like the other counts
  they are **applied** work only: a directory contributes 0 while ReadOnly is on,
  while its group processing is off or in WhatIf, and removes also require
  `enableGroupProcessingRemove`. Group *names* are never transmitted
  (see PRIVACY.md).

## [26.7.12.0] - 2026-07-12

### Added
- **Shipped plugin templates.** Sanitized templates of the three plugins
  (`Invoke-PluginGSheetStaff`, `Invoke-PluginStaffOverride`,
  `Invoke-PluginSkywardSMSStudents`) are now packaged with the module under
  `Templates\Plugins\` (outside the loader's path, so they're never dot-sourced at import)
  and copied into `<RootPath>\Plugins` by `New-IDBridgeConfig` (existing files are never
  overwritten). Every site-specific value is a placeholder, and each template throws with
  an edit-me message naming the file until its placeholders are edited — a
  copied-but-unconfigured plugin can't silently run.
- **`docs/getting-started.md`** — ordered first-run walkthrough (PowerShell Gallery
  install): scaffold, secret vault, Google bootstrap, source sheet, source plugin, config
  fill-in, read-only first run, and enabling writes incrementally. Linked from the README
  quick start / documentation list and the CLAUDE.md references. Docs only — no code
  changes.

### Fixed
- **OU-creation failures now abort the run as documented.** `New-IDBridgeADOrgUnit` and
  `New-IDBridgeGoogleOrgUnit` returned the ErrorRecord instead of throwing, so
  `Invoke-IDBridge`'s catch (which logs and aborts — a missing OU cascades into user
  create/move failures) could never fire. Both now throw; the Google function still logs
  the error first.
- **The AD username-collision check on renames actually works now.** `Get-ADUsersToUpdate`
  checked for a taken username with `Get-ADUser -Identity <UPN>`, but `-Identity` does not
  accept a UPN — the lookup always failed as not-found, so the guard could never fire and a
  rename into a taken username only surfaced later as a `Set-ADUser` error. The check now
  runs in-memory against the `Get-TargetDataAD` snapshot (new `-CurrentADUsers` parameter,
  passed from `Invoke-IDBridge`), skipping the user when a **different** account (by
  ObjectGUID, so a SamAccountName-only change doesn't self-collide on its own unchanged
  UPN) already holds the new SamAccountName or UPN — the same pattern as
  `Get-GoogleUsersToUpdate`'s primaryEmail collision check, with no per-user AD query.
- **Group-membership fetch errors are detected reliably.** The parallel-processing error
  check in `Get-TargetDataGoogle` string-matched the whole log entry (`-like "*error*"`),
  which also tripped on any *trace* message containing "error" — e.g. a group email like
  `data-errors@…` would have aborted every run. It now checks the entry's `Level`
  explicitly.
- **`Push-LogsToSheet` no longer crashes on an empty log buffer** — it passed
  `-Level Warning` to `Write-Log`, whose ValidateSet only allows `Warn`, turning the
  intended warning into a parameter-binding error.
- **`Get-SourceDataGSheet` failures now throw real messages.** Three `Throw (Write-Log …)`
  calls threw `$null` (Write-Log returns nothing), producing empty exceptions; each now
  logs and throws the message. The safety-floor failure also reports the actual computed
  row floor (e.g. `75 (75% of 100)`) instead of the bare fraction, and the retrieval
  failure includes the underlying error.
- **`Get-SourceDataSkywardSMS -ExcludeEntityIDs` accepts a comma-separated string.** The
  filter uses `-notin`, which needs an array — a string like `'800,801'` silently filtered
  nothing. Input is now normalized to a trimmed array (arrays pass through unchanged).
- **Google JWT segments are now base64url-encoded** (RFC 7515) in
  `Get-GoogleApiAccessToken` instead of standard Base64 with padding — Google's token
  endpoint tolerated the old encoding, but it was out of spec; the Azure auth helper
  already did this correctly. Verified live against the token endpoint.
- **Log-message corrections:** the Google create-skip message said "ADKey is not set"
  (now GoogleKey); `Initialize-IDBridge`'s AD-module error said "does not exit" (now
  "does not exist").
- **Docs/help accuracy pass (docs only — no code changes).** Corrected drift between the
  docs/comment-based help and the current code: Google auth is acquired by
  `Connect-IDBridgeGoogle` at run start, not by `Initialize-IDBridge`
  (configuration.md, `Get-GoogleHeaders` help); `Write-Log`'s help now describes the
  IDBridge behavior (Trace gating, in-memory buffer, config-derived path) instead of the
  original 2015 gallery text; `Get-ColumnLetter` is documented as zero-based (its actual
  behavior; help/functions.md said 1-based with a wrong example); Google deactivation is
  archive + move-to-trash, not suspend (`Remove-IDBridgeGoogleUserLicense` help); telemetry
  timeout is 10 s (functions.md said 2 s); `Get-StudentGrade` maps graduation year, not
  birth year (functions.md); fixed stale examples (`New-IDBridgeGoogleUser` referenced a
  removed `-tokenInformation` parameter; `Get-GoogleApiAccessToken` passed JSON content to
  `-ServiceAccountKeyPath`); `Get-SourceDataSkywardSMS -ExcludeEntityIDs` takes an array,
  not a comma-separated string; plugins.md Skyward example updated to the vault secret and
  the template's `Provision` keys; README runtime dirs no longer list the removed `Auth\`
  folder (now `Vault\`); CLAUDE.md no longer pins a stale version and correctly says
  `Private\` helpers are loaded.
- **Pilot-district specifics scrubbed from docs and help examples.** District names,
  domains, OU paths, the Skyward tenant URL, gMSA domain, and the source-spreadsheet ID
  prefix in `docs/plugins.md`, `docs/configuration.md`, and six functions' comment-based
  help examples now use the generic placeholders the templates use (`YourDistrict`,
  `yourdistrict.org`, `DC=yourdomain,DC=local`, `DOMAIN\gMSA-IDBridge$`,
  `<spreadsheet id>`).

### Removed
- **`Get-RandomPassword` removed.** Nothing in the module or the shipped plugin templates
  called it (the `RANDOM` password type uses `New-Guid`, and the other types use
  Word/FSPIN/the passphrase API), and its implementation had real flaws: lengths over 40
  were silently capped at 40 (it sampled a 40-character pool without replacement),
  characters never repeated, no character class was guaranteed, and it used a
  non-cryptographic RNG. Rather than rewrite an unused helper, it's gone — a plugin that
  needs a random password should use `New-Guid`, the passphrase API, or its own generator
  (PowerShell 7.4+ ships `Get-SecureRandom`).
- **`New-Passphrase` no longer falls back to `$env:PASSPHRASE_AUTH_TOKEN`.** The fallback
  was broken anyway (assigning the env string to the SecureString-typed parameter threw),
  and the env var was an unencrypted escape hatch around the vault. `-AuthToken` is now
  required; a missing token throws immediately with a clear message.

## [26.7.10.9] - 2026-07-10

### Added
- **`Grant-IDBridgeCertificatePrivateKeyAccess`** — grants an account read access to a
  machine-store certificate's private key by thumbprint. The grant already existed inside
  `New-IDBridgeSecretCertificate -GrantRead`, but only at creation time; the new function
  covers certificates that already exist (e.g. adding the gMSA later, or an Azure Key Vault
  auth certificate). `New-IDBridgeSecretCertificate -GrantRead` now delegates to it — same
  behavior, one implementation.

## [26.7.10.8] - 2026-07-10

### Added
- **Group skip lists: `Google.groupsExcluded` and `AD.groupsExcluded`.** Wildcard patterns
  (matched against the group **email** on the Google side, the group **name** on the AD
  side) for groups IDBridge must never touch — e.g. manually curated clubs or committees,
  which the remove step would otherwise strip from managed users. Matching groups are
  dropped at target-data retrieval (`Get-TargetDataGoogle`/`Get-TargetDataAD`), making them
  invisible to ALL group processing: no adds (even if a plugin proposes them), no removes,
  no deactivate group-strips — and their member lists are never fetched. The previously
  hardcoded `classroom_teachers@*` exclusion moved into the Google default; a config
  without the key keeps that behavior, and a config that sets the key should include the
  pattern itself.

## [26.7.10.7] - 2026-07-10

### Added
- **`Get-IDBridgeGoogleProjectId`** — accessor for the install's GCP project ID. The ID was
  already persisted in the vault (the `project_id` field of the `GoogleAuth-ServiceAccount`
  key JSON) but had no way to read it back without opening the secret by hand. Mirrors
  `Get-IDBridgeGoogleServiceAccountEmail`: `Connect-IDBridgeGoogle` stashes it at connect
  time, with a pre-connect fallback to parsing the vault secret.

## [26.7.10.6] - 2026-07-10

### Changed
- **Google group membership changes are now batched** like the user create/update/
  deactivate calls. `Update-GoogleGroupMembers` gains `-AsBatchRequest`/`-ContentId`, and
  `Invoke-IDBridge` sends membership adds, membership removes, and deactivate group-strips
  through `Invoke-GoogleBatchRequest` as three separate batches (Google doesn't guarantee
  execution order inside a batch, so change types don't share one). Wall-clock win only —
  quota usage is unchanged. Batch item failures now log with a `<personID>|<group>`
  correlation id instead of a bare HTTP status.

## [26.7.10.5] - 2026-07-10

### Fixed
- **Google group diff no longer assumes a group's email matches its name.**
  `Get-GoogleUserGroupsToUpdate` built membership emails as `<name>@GroupPrimaryDomainName`;
  for a group whose real email differs (e.g. `Grade-PK` = `studentsgradepk@…`) every run
  proposed a bogus add (409 Conflict — already a member) **and** a bogus remove of the
  correct membership, oscillating the group every other run. Adds and removes now compare
  by each group's real email from the fetched group list. The `GroupPrimaryDomainName`
  parameter and config key are removed (unused; a leftover key in existing configs is
  ignored).
- **`enableGroupProcessingWhatIf` now actually suppresses group writes.** The flag was only
  consulted when *computing* the change lists; with `enableGroupProcessing = $true` the
  add/remove writes executed regardless — contrary to the documented log-only semantics.
  The AD and Google group execute regions are now skipped (with an explicit log line) while
  WhatIf is `$true`.

## [26.7.10.4] - 2026-07-10

### Fixed
- **`-TestRun` works again.** The switch (and `Debug.testRun`) had no effect: the only
  consumer was `Get-SourceDataGSheet -testRun`, which the plugins stopped passing at some
  point — so a "test run" silently processed the full dataset. The cap now lives centrally
  in `Invoke-SourcePlugins`: each source plugin's validated output is limited to the first
  10 records when `Debug.testRun` is set, after `Test-IDBridgeSourceData` and after each
  source's own safety-floor checks (which still see the full dataset). Works for every
  source plugin — including Skyward, which never supported it — with no plugin-side code.
  The now-redundant `testRun` parameter is removed from `Get-SourceDataGSheet`.

## [26.7.10.3] - 2026-07-10

### Changed
- **Google deactivation now ARCHIVES users instead of suspending them.** Archiving is the
  deactivation state Google built for school churn: the account can't sign in, is hidden
  from the GAL, and its **base Education Fundamentals license self-releases** (~24h) —
  with no OU auto-licensing tug-of-war, since the account converts to the free Archived
  User license. Paid add-on licenses (Education Standard/Plus, Teaching & Learning) are
  **not** released by archiving and are still removed by `enableLicenseRemoval`, which
  therefore stays essential. Details:
  - "Already deactivated" now means suspended **or** archived
    (`GoogleCurrentUserSuspendedStatus` carries the OR), so users suspended under the old
    behavior are grandfathered — no convergence churn.
  - Reactivation (rehire/returning student) unarchives; `ForceDisable` still **suspends**
    — it's the temporary, override-driven block, never an archive.
  - `Update-IDBridgeGoogleUser` gains `-Archived` ("true"/"false").
  - Default `licenseProductIds` drops `Google-Apps` → `@('101031','101037')` (paid
    products only): the base license self-releases on archive, and removing it by API just
    fights OU auto-licensing. Sites that explicitly configure `licenseProductIds` are
    unaffected.
  - Archiving expects an edition with included Archived User licenses (all Education
    editions qualify; Business/Enterprise tenants must own AU licenses).

## [26.7.10.2] - 2026-07-10

### Fixed
- **Telemetry timeout raised from 2s to 10s.** The 2-second budget was routinely exceeded
  by the ingest backend's first response after idle (cold start), so sends failed with
  `TaskCanceledException` whenever the endpoint wasn't already warm. Still fire-and-forget,
  still a single attempt (a retry after a client-side timeout could double-count a Basic
  event, which has no identifier to dedupe on), still never affects the run.

## [26.7.10.1] - 2026-07-10

### Changed
- **`Get-ADUsersToSetEmployeeID` now mirrors the Google side's unlinked-user logging.**
  Unlinked source users with no AD account are logged at Trace only (previously Info),
  with an explicit "inactive and has no AD account - nothing to reconcile" message for
  inactive ones — the same refinement `Get-GoogleUsersToSetEmployeeID` already had, so
  recurring inactive source rows no longer read like a problem in the log.

## [26.7.10.0] - 2026-07-10

### Changed
- **BREAKING: the service account now authenticates as itself — domain-wide delegation and
  admin impersonation are gone.** Authorization for Admin SDK calls comes from a custom
  Google Workspace admin role named `IDBridge` (User/Org Unit/Group management + License
  Management — never Super Admin) assigned directly to the service account;
  `Initialize-IDBridgeGoogleServiceAccount` now creates and assigns it (idempotent —
  privileges are resolved from `privileges.list` and re-runs converge an existing role).
  Consequences:
  - `GoogleToken.adminEmail` is no longer read — remove it from the config (the
    `New-IDBridgeConfig` scaffold no longer emits it). No admin user account is involved
    at run time.
  - `Get-GoogleApiAccessToken` lost its `-TargetUserEmail` parameter (the JWT carries no
    `sub` claim).
  - Sheets access is now by **sharing**: share the staff source sheet and the log sheet
    with the service account's email. The bootstrap checklist prints it, and the new
    `Get-IDBridgeGoogleServiceAccountEmail` accessor returns it any time (from
    connect-time state, falling back to the vault key's `client_email`).
  - **Migration (existing deployments):** re-run the bootstrap with
    `-ProjectId <existing id>` to create/assign the role, share the sheets with the SA,
    verify with `Connect-IDBridgeGoogle` then `Invoke-IDBridge -ReadOnly`, and only then
    delete the old domain-wide delegation grant and drop `adminEmail` from the config.
  - The bootstrap's role steps need the `admin.directory.rolemanagement` scope; the OAuth
    Playground instructions now request it up front, and the gcloud/`-AccessToken` tiers
    prompt once for a second Playground token when needed.
  - All Directory API calls now pass the real customer ID (`Google.customerID`) instead of
    the `my_customer` alias, which only resolves for a domain user's token and returned
    `400 Invalid Input` under the service account's own token (users/groups/org-unit reads
    in `Get-TargetDataGoogle`, OU creation in `New-IDBridgeGoogleOrgUnit`; the spurious
    `customer` param on the group-members call was dropped — `members.list` doesn't take
    one).

## [26.7.9.0] - 2026-07-09

### Added
- **`New-IDBridgeConfig`.** First-run scaffold: creates the runtime folder tree
  (`Config/Logs/Exports/Plugins/Data/Vault`) under `-RootPath` (default `C:\IDBridge`) and
  writes a default `IDBridgeConfig.psd1` with every feature disabled, all plugins off, and
  obvious placeholder values for the site-specific settings. Safety brakes ship on
  (`ReadOnly = $true`, group `WhatIf = $true`, `ChangeThreshold` enabled). An existing
  config file is never overwritten — the function throws instead, and there is deliberately
  no `-Force`. Runs before any state exists (no `Write-Log`/`Initialize-IDBridge` needed).

### Documentation
- **Published source-sheet template for fresh deployments.** Onboarding without existing
  directory data now starts from a pre-built Google Sheet template (copy link:
  `https://docs.google.com/spreadsheets/d/1OUlm-5WGce_x2z0L1dM2kD8Ejk_f3RNF3EC8sa6uHhE/copy`) that ships the source and override tabs with
  tables, Process checkboxes, a TerminationDate date column, a Groups reference tab, and
  multi-select group dropdowns. Documented in the README and `docs/functions.md`. (Replaces the
  never-released `New-IDBridgeSourceSheet` builder, which the API couldn't give multi-select
  dropdowns.)
- **First-class IDBridge Pulse pointer in the README.** Added a short `IDBridge Pulse` section
  describing the companion dashboard (`pulse.scnlabs.net`), what a claimed install shows, and
  how to claim one with `Get-IDBridgeSiteID` — so Pulse reads as a product to use, not just a
  telemetry endpoint.

### Changed
- **Dropped the unused `-UserRootOU` parameter from `Get-ADOrgUnitsForProcessing` and
  `Get-GoogleOrgUnitsForProcessing`.** Both declared it `Mandatory` but never used it —
  ancestor expansion derives the needed OUs from the user list alone. Removed the parameter,
  its doc block, and the two call sites in `Invoke-IDBridge`. **No config change:** the
  `AD.userRootOU` / `Google.userRootOU` keys stay — they're read directly by the
  `ChangeThreshold` change-volume guard as its managed-population anchor, which is now their
  only consumer (docs and the config template comments updated to say so).
- **`Export-IDBridgeDirectoryToSheet` is now scope-driven, not config-driven.** The
  `-ADSearchBase` / `-GoogleOrgUnitPath` parameters no longer default to the config root OUs;
  a directory is fetched only when its scope is named. An omitted scope is skipped entirely
  (never fetched, never a failure) instead of falling back to `AD.enabled`/`Google.enabled`,
  so a Google-only run (only `-GoogleOrgUnitPath`) never touches or requires Active Directory
  and vice versa. At least one of the two scopes must now be provided.

## [26.7.8.0] - 2026-07-08

### Added
- **`Export-IDBridgeDirectoryToSheet`.** One-time onboarding tool that seeds the staff
  source sheet from the current directory state: reads AD + Google users, attributes, and
  group memberships (scoped to an OU subtree per side, default the config root OUs), merges
  the two directories per person by UPN/primaryEmail, and writes one row per person to a
  **new** tab (throws if the tab exists) in the staff sheet column layout plus review-helper
  columns (`InAD`, `InGoogle`, `ADEnabled`, `GoogleSuspended`, `ADOrgUnit`, `GoogleOrgUnit`).
  Every row is written with `Process = FALSE` for human review; `PersonType`, `Word`, and
  `EmailGroups` are left blank (nothing is derived from OU names); `ApplicationGroups` is
  the full de-duplicated dump of current AD + Google group names; people disabled/suspended
  in every directory they exist in get yesterday's date as `TerminationDate`.

### Changed
- **`Word` is no longer a required source-sheet column.** `Get-SourceDataGSheet` no longer
  requires the column to exist or rows to have it populated. Note a row with a blank `Word`
  under the `WORD` password type still yields no `ADKey`, so `Test-IDBridgeSourceData` drops
  that record (Warn) until the word is filled in or the plugin's password type changes.

## [26.7.6.0] - 2026-07-06

### Added
- **Usage telemetry (opt-out) + IDBridge Pulse.** One anonymous usage event per run is
  sent from the `finally` block of `Invoke-IDBridge` to the IDBridge Pulse backend
  (`pulse.scnlabs.net`). Three tiers via the new `Telemetry` config block
  (`Tier = 'Basic' | 'Enhanced' | 'Off'`, default `Basic`; optional `Endpoint` override):
  Basic sends anonymous aggregate counts with **no identifier of any kind**; Enhanced
  (opt-in) adds a random install-scoped `SiteID` GUID plus the exception *class* and
  throwing *function* name on failed runs — never the exception message. No names,
  usernames, emails, person IDs, or directory records are transmitted at any tier; counts
  are applied work, so ReadOnly runs report zeros. The send is fully self-contained
  (2 s timeout, no retries, all errors swallowed and logged locally) and can never delay,
  fail, or mask a run. The exact payload is logged at Trace level for verification. See
  the new [PRIVACY.md](PRIVACY.md).
- **`Send-IDBridgeTelemetry`.** Builds and posts the telemetry event (exported, called
  from `Invoke-IDBridge`).
- **`Get-IDBridgeSiteID`.** Returns (creating on first Enhanced use) the install's random
  telemetry SiteID from the plain-text `<ConfigRoot>\IDBridgeSiteID.json`; districts use
  it to claim their install in the Pulse dashboard. Delete the file when cloning a config
  to a new install.
- **`-DisableTelemetry` switch on `Invoke-IDBridge`.** Silences telemetry for a single run.

## [26.7.5.0] - 2026-07-05

### Added
- **`Invoke-GoogleBatchRequest`.** Sends multiple Google Directory API calls in one
  `multipart/mixed` batch HTTP request (chunked 50 per batch) and parses the multipart
  response back into per-call results keyed by `Content-ID`. Per-call failures are logged
  and returned; they do not stop the remaining calls. Note batching reduces round trips
  (wall-clock time), not quota — every inner call still counts against the API rate limit.
- **`-AsBatchRequest` on `New-IDBridgeGoogleUser` / `Update-IDBridgeGoogleUser`.** Returns
  the request descriptor (method/path/body/content-ID) for `Invoke-GoogleBatchRequest`
  instead of calling the API. An `-RemoveAlias` pre-step still executes immediately so the
  alias is free before the batched update lands.
### Documentation
- Documented the exact scope of alias removal on renames in [docs/functions.md](docs/functions.md)
  (behavior unchanged): it fires only when a rename's new UPN is in use as another user's
  alias, removes only that one blocking alias, and never cleans up the alias Google
  auto-creates from the old primary email on a renamed account.

### Fixed
- **Name-matched inactive accounts now get their personID persisted on deactivation.** The
  externalId write previously only happened via the update list, which covers active users
  only — so an inactive user matched by UPN+name was suspended but never linked, and was
  re-matched (and re-logged) on every subsequent run. The deactivate step now includes the
  personID externalId in its suspend+trash update whenever the Google account doesn't have
  it yet, and `Get-GoogleUsersToDeactivate` logs this at decide time (visible in ReadOnly).

### Changed
- **"No user found with EmployeeID" is now Trace-level.** `Get-GoogleUsersToSetEmployeeID`
  logged this at Info for every unlinked source user each run, including inactive rows with
  no Google account where nothing can ever change; those now get an accurate
  "inactive and has no Google account — nothing to reconcile" Trace message instead.
- **Google user writes are now batched.** The execute phase sends deactivates (suspend +
  move-to-trash), updates, and creates as three separate sequential batches — types are
  never mixed in one batch because Google does not guarantee execution order within a
  batch, and cross-type order matters (deactivates → updates → creates, as before). New
  Google IDs from batched creates are matched back to source records by `primaryEmail` for
  the same-run group-membership refresh. Group membership and license removal calls are
  unchanged (sequential). No change to decide-then-act, `ReadOnly`, or the change-threshold
  guard — batching only affects how already-approved writes are transmitted.

## [26.7.3.0] - 2026-07-03

> Supersedes the earlier unreleased SecretManagement-based secrets work: the external-module
> stack (`Microsoft.PowerShell.SecretManagement` / `SecretStore` / `SecretManagement.DpapiNG`)
> is replaced by a built-in, zero-dependency vault before ever shipping.

### Added
- **Built-in secret vault.** Secrets are encrypted JSON envelope files (`<Name>.secret.json`)
  under `<Root>\Vault` (new runtime `Paths.VaultRoot`). Each envelope records the provider
  that protected it, so reads decrypt any mix of providers. No external modules, no per-user
  vault registration, no unlock step. Secret functions live in the new `Public\Secrets\`
  folder.
- **Two encryption providers, selected by `Secrets.Provider` at write time.** `Cms` (default)
  encrypts with `Protect-CmsMessage` and a Document Encryption certificate; `DpapiNG` protects
  to an AD principal (e.g. a gMSA SID, with `OR` descriptors supported) through a built-in
  P/Invoke wrapper over `ncrypt.dll` — no `SecretManagement.DpapiNG`. `AzKeyVault` remains
  reserved.
- **`New-IDBridgeSecretCertificate`.** Creates the self-signed Document Encryption certificate
  the `Cms` provider needs (non-exportable RSA 3072, 10-year validity, machine or user store)
  and can grant a service account private-key read via `-GrantRead 'DOMAIN\gMSA$'`.
- **`Get-IDBridgeSecretInfo` / `Remove-IDBridgeSecret`.** List vault entries (names and
  metadata, never values) and delete an entry.
- **`Set-IDBridgeSecret -InFile`.** Store a file's raw content as a secret — used for the
  Google service-account key JSON.
- **`AzKeyVault` provider implemented.** With `Secrets.Provider = 'AzKeyVault'` all secret
  functions go to an Azure Key Vault over REST — no local envelopes and still no external
  modules. Auth is an Entra app registration with a certificate credential (client-credentials
  flow with a self-built RS256 JWT assertion, private helpers `Get-IDBridgeAzureAuthToken` /
  `Get-IDBridgeAzKeyVaultContext`; the token is cached per session). Secrets are stored under
  their IDBridge names as-is; config takes `VaultUri`, `TenantId`, `ClientId`, and
  `CertThumbprint`.

- **`Remove-IDBridgeGoogleUserLicense`.** License cleanup on deactivation, **on by default**
  (`Google.enableLicenseRemoval = $false` disables): the full deactivate (suspend +
  move-to-trash) step also removes **all** of the user's license assignments via the
  Enterprise License Manager API, logging each by SKU name. Assignments are discovered in
  the target snapshot — `Get-TargetDataGoogle` enumerates `listForProduct` per
  `Google.licenseProductIds` product (default Workspace/Education + Teaching and Learning)
  into a `CurrentLicenses` property on each user, flowing to source records as
  `GoogleCurrentLicenses` — no SKUs hard-coded, and the decide phase logs exactly which
  licenses a deactivation will remove, **visible in ReadOnly runs**. `ForceDisable` updates
  never touch licenses. Requires the `apps.licensing` scope in the service account's
  domain-wide delegation (the module requests it automatically while the feature is
  enabled — **pre-existing deployments must add the scope to their DWD grant or disable the
  feature, or token acquisition fails**).

- **`Initialize-IDBridgeGoogleServiceAccount`.** One-command Google-side bootstrap for new
  deployments, run in the district's tenant as their super admin: tiered sign-in
  (`-AccessToken` → gcloud → OAuth Playground paste),
  organization discovery (orchestrating the no-API-exists console terms acceptance), optional
  project creation (display name `IDBridge`), API enablement, service-account creation, and
  the JSON key seeded directly into the vault without touching disk. If
  `iam.disableServiceAccountKeyCreation` blocks key creation it temporarily self-grants
  `orgpolicy.policyAdmin`, exempts the project, retries, and revokes the role. Prints the
  manual domain-wide delegation checklist (client ID + live scope list). See
  [docs/google-bootstrap.md](docs/google-bootstrap.md).

### Changed
- **The Google service-account key moved into the vault.** `Initialize-IDBridge` reads the
  secret `GoogleAuth-ServiceAccount` instead of discovering a `*.json` file in `Auth\`; there
  is **no file fallback**. `Get-GoogleApiAccessToken` gained a `-ServiceAccountKeyJson`
  parameter set alongside the existing `-ServiceAccountKeyPath`.
- **`Secrets` config block reshaped.** `Provider` is now `'Cms'` (default) or `'DpapiNG'`;
  `VaultName` is gone (the vault folder is always `Paths.VaultRoot`); sub-blocks are
  `Cms.Thumbprint` and `DpapiNG.ProtectionDescriptor`.
- **Private helper loading enabled.** `IDBridge.psm1` now dot-sources `Private\*.ps1`
  (the CMS certificate resolver and the DPAPI-NG type live there, unexported).
- **OAuth scopes moved from config into the module.** `GoogleToken.googleAuthScope` is
  removed — the scope list is a property of the code, defined by the private
  `Get-IDBridgeGoogleScope` helper (directory user/orgunit/group + Sheets), which includes
  `apps.licensing` unless `Google.enableLicenseRemoval = $false` (requesting an ungranted
  scope fails DWD token exchange, so disabling the feature also drops the scope). The
  bootstrap's DWD checklist prints the full set so grants are future-proof.
- **Google auth moved from `Initialize-IDBridge` to `Invoke-IDBridge`, as the new
  `Connect-IDBridgeGoogle`.** Initialization is now pure state bootstrap
  (config/paths/logging/AD/cascade) and always succeeds on a fresh install, so the
  certificate/secret/bootstrap functions can run before the `GoogleAuth-ServiceAccount`
  secret exists — no first-run chicken-and-egg. `Invoke-IDBridge` calls
  `Connect-IDBridgeGoogle` after the runtime overrides, gated on `GoogleToken.Enabled` only
  (`-SkipGoogle` runs still get headers for Sheets plugins and sheet logging). The function
  is also exported for standalone use: it verifies the whole auth chain (vault key → DWD
  JWT → token) without running the pipeline — ideal right after a bootstrap/DWD change.
- **Google auth failures now fail the run.** The old auto-disable cascade (a run that lost
  Google auth silently forced `Google.enabled = $false`) is removed along with the file
  fallback — `Initialize-IDBridge` throws at startup instead. Disable Google intentionally
  with `-SkipGoogle` or `GoogleToken.Enabled = $false`.

### Removed
- **`Register-IDBridgeSecretVault`** and every SecretManagement dependency. Vault access needs
  no registration; the legacy per-user secrets directory (`Paths.UserSecretsRoot`,
  `Auth\<username>\`) is no longer created or exposed. A one-time migration snippet is in
  [docs/secrets.md](docs/secrets.md#migrating-from-the-secretmanagement-vault).
- **`Paths.AuthRoot` (`<Root>\Auth`).** Nothing reads it since the Google service-account key
  moved into the secret vault; the directory is no longer created or listed in `Paths`. An
  existing `Auth\` folder is left untouched — delete it once its old contents are migrated.

## [26.6.26.3] - 2026-06-26

### Fixed
- **AD org-unit creation order.** Removed a redundant `Sort-Object -Unique` in `Invoke-IDBridge`
  that re-sorted the OU list alphabetically and could place a child OU before its parent (e.g.
  `OU=Grade-12,...` before `OU=Students,...`), causing creation to fail.
  `Get-ADOrgUnitsForProcessing` already returns OUs deduped and parents-first.
- **Null-safe failure path in `Invoke-IDBridge`.** The catch block now logs the full error via
  `Out-String` and falls back to `Write-Error` when the config never loaded (previously the
  catch's `Write-Log` could throw again); the finally block is guarded so a pre-config failure no
  longer dereferences a null config.

### Changed
- **ChangeThreshold counts distinct affected AD users.** A user needing update + rename + move now
  counts once (via a `CN` HashSet) rather than three times, making the AD change ratio comparable
  to the per-user Google ratio.
- **End-of-run summary.** `Invoke-IDBridge` now logs per-directory change totals
  (create/update/rename/move/deactivate/group add/remove) labeled `PROPOSED (ReadOnly)` or
  `APPLIED`, plus each directory's change-volume percentage against the threshold.
- Per-operation error logs now use `$_.Exception.Message`; removed dead `$itemSplat = $null` lines.

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
