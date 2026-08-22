# IDBridge tests

Pester v5 tests for the module under `src\IDBridge`. The layout mirrors the module:
`tests\Public\Core\Format-IDBridgeName.Tests.ps1` tests
`src\IDBridge\Public\Core\Format-IDBridgeName.ps1`, and so on. `IDBridge.Module.Tests.ps1`
holds the structural tests (every file parses, one `Verb-Noun` function per file,
`Public\` ⇔ `FunctionsToExport`, `Private\` never exported).

## Running

```powershell
Install-Module Pester -MinimumVersion 5.5   # once
Invoke-Pester -Path .\tests                 # from the repo root
```

The suite is pure decide-phase: no Active Directory, no Google, no `C:\IDBridge`, no
config file. It runs on any OS with PowerShell 7.5+ (including Linux).

## Conventions

- **`TestHelper.psm1`** — import it first in `BeforeAll`, then call `Import-IDBridgeForTest`
  to (re)load the module under test. `New-TestADRecord` builds the enriched source-record
  objects the diffing functions consume.
- **Private functions** aren't exported — call them inside `InModuleScope IDBridge { ... }`,
  passing fixtures in via `-Parameters`. See `Private\AD\Get-ADUserGroupsToUpdate.Tests.ps1`
  for the pattern.
- **`Write-Log`** requires an initialized session, so mock it (inside `InModuleScope`) in any
  test that exercises a function that logs. The mock also lets you assert on proposed-change
  log lines with `Should -Invoke`.
- **Config** — functions read config via `Get-IDBridgeConfig`; mock that accessor (again in
  module scope) with a minimal hashtable rather than running `Initialize-IDBridge`.
- Tests live outside `src\IDBridge` on purpose: `Publish-Module -Path .\src\IDBridge` must
  never package them.
