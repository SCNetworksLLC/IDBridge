# Contributing to IDBridge

## Development setup

- PowerShell 7.5+.
- Clone the repo. The module is under `src/IDBridge/`; import it with:
  ```powershell
  Import-Module .\src\IDBridge\IDBridge.psd1 -Force
  ```
- Configuration, plugins, and runtime data live **outside** the repo under `C:\IDBridge\`
  (or your `-RootPath`). Never commit secrets or runtime output — see
  [docs/secrets.md](docs/secrets.md).

## Branch / PR flow

1. Branch from `main` (e.g. `feature/<short-name>` or `fix/<short-name>`).
2. Make focused changes; match the existing function style (one `Verb-Noun.ps1` per file —
   exported functions under `src/IDBridge/Public/`, internal ones under
   `src/IDBridge/Private/` — comment-based help, `Write-Log` for logging).
3. Update [CHANGELOG.md](CHANGELOG.md) under `## [Unreleased]`.
4. Verify locally (below), then open a PR against `main`.

## Verifying changes

```powershell
Test-ModuleManifest .\src\IDBridge\IDBridge.psd1
Import-Module      .\src\IDBridge\IDBridge.psd1 -Force
Get-Command -Module IDBridge        # exported surface should match the manifest

# Always exercise the pipeline read-only before enabling writes
Invoke-IDBridge -ReadOnly -TraceLogging
```

If you add a public function, add it to `FunctionsToExport` in the manifest and give it
comment-based help. Internal helpers go under `Private/` and are **not** added to the
manifest — the loader dot-sources both trees, but only `FunctionsToExport` is the
supported surface.

If you meaningfully change a shipped template under `src/IDBridge/Templates/`, bump its
`# TemplateVersion: <n>` marker — `Install-IDBridge` compares it against installed copies
to print the "newer template available" notice.

## Versioning & releases

IDBridge uses a **calendar version** `YY.M.D.build` (e.g. `26.6.21.0` = 2026-06-21, build 0).
This is intentional: the version encodes the release date. A release always ships from
`main` — merging the work branch to `main` is part of cutting it. To cut a release:

1. On the work branch: move the `## [Unreleased]` notes into a new dated section in
   [CHANGELOG.md](CHANGELOG.md).
2. Bump `ModuleVersion` in `src/IDBridge/IDBridge.psd1` to the new `YY.M.D.build`, and commit.
3. **Merge the branch to `main`** (via pull request), so the tagged code and `main`'s
   history are the same commit.
4. Trigger the publish (next section), either way:
   - **Tag push** (from a normal clone): `git checkout main && git pull`, then
     `git tag v<version>` and `git push --tags`.
   - **Workflow dispatch** (works from anywhere, including Claude Code cloud sessions,
     which can push branches but not tags): Actions → Publish → Run workflow (or the
     GitHub API). The workflow reads `ModuleVersion` from `main`, refuses to run if that
     tag already exists, and mints the `v<version>` tag itself before publishing.

## Publishing to the PowerShell Gallery

Publishing is automated by the `Publish` GitHub Actions workflow
([.github/workflows/publish.yml](.github/workflows/publish.yml)), started either by pushing
a `v*` tag (the workflow validates that the tag matches `ModuleVersion`) or by dispatching
it manually (the workflow mints the `v<ModuleVersion>` tag itself, refusing to re-release an
existing version). Either way it then publishes `src/IDBridge` to the PowerShell Gallery and
creates a GitHub Release with that version's CHANGELOG.md section as the notes. It needs a
`PSGALLERY_API_KEY` repository secret (Gallery API key scoped to push `IDBridge` only;
keys expire after at most 365 days, so rotate yearly).

The module is packaged from its folder, so repo-only files (docs, `CLAUDE.md`, README) are
excluded automatically.

To publish manually instead (e.g. the first-ever publish, or if CI is unavailable — the
workflow itself uses `Publish-PSResource`; classic `Publish-Module` works the same for a
manual publish):

```powershell
# 1. Confirm the name is available (only needed the first time)
Find-Module IDBridge

# 2. Validate, then dry-run to confirm the package contents
Test-ModuleManifest .\src\IDBridge\IDBridge.psd1
Publish-Module -Path .\src\IDBridge -WhatIf

# 3. Publish for real
Publish-Module -Path .\src\IDBridge -NuGetApiKey <your-api-key>
```
