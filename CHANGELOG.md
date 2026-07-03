# Changelog

All notable changes to IDBridge are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions use
a calendar scheme `YY.M.D.build` (see [CONTRIBUTING.md](CONTRIBUTING.md#versioning--releases)).

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
