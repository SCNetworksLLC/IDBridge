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
2. Make focused changes; match the existing function style (one `Verb-Noun.ps1` per file under
   `src/IDBridge/Public/`, comment-based help, `Write-Log` for logging).
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
comment-based help.

## Versioning & releases

IDBridge uses a **calendar version** `YY.M.D.build` (e.g. `26.6.21.0` = 2026-06-21, build 0).
This is intentional: the version encodes the release date. To cut a release:

1. Move the `## [Unreleased]` notes into a new dated section in [CHANGELOG.md](CHANGELOG.md).
2. Bump `ModuleVersion` in `src/IDBridge/IDBridge.psd1` to the new `YY.M.D.build`.
3. Commit, then tag: `git tag v<version>` and `git push --tags`.

## Publishing to the PowerShell Gallery

The module is packaged from its folder, so repo-only files (docs, `CLAUDE.md`, README) are
excluded automatically.

```powershell
# 1. Confirm the name is available (only needed the first time)
Find-Module IDBridge

# 2. Validate, then dry-run to confirm the package contents
Test-ModuleManifest .\src\IDBridge\IDBridge.psd1
Publish-Module -Path .\src\IDBridge -WhatIf

# 3. Publish for real
Publish-Module -Path .\src\IDBridge -NuGetApiKey <your-api-key>
```
