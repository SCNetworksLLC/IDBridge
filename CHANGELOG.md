# Changelog

All notable changes to IDBridge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use
a calendar scheme `YY.M.D.build` (see [CONTRIBUTING.md](CONTRIBUTING.md#versioning--releases)).

## [Unreleased]

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
