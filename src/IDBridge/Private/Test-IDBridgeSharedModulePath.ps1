<#
.SYNOPSIS
Test whether a module folder sits under an all-users module path (internal).

.DESCRIPTION
Internal helper for Register-IDBridgeScheduledTask: returns $true when -ModuleBase is
under any of -SharedModulePaths, the module folders every account on the machine sees - so
the gMSA's pwsh finds the module by name. The comparison is case-insensitive, treats '\'
and '/' alike, ignores trailing separators, and matches whole path segments only
('...\PowerShell\ModulesX' is not under '...\PowerShell\Modules'). Uses no module state or
Write-Log.

.PARAMETER ModuleBase
The loaded module's folder, e.g. 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0'.

.PARAMETER SharedModulePaths
The all-users module folders. Defaults to the machine-scope PSModulePath plus
$env:ProgramFiles\PowerShell\Modules - pwsh's all-users folder, where
Install-Module -Scope AllUsers puts a module; pwsh adds it at startup and it is not in the
machine variable.

.OUTPUTS
[bool] $true when ModuleBase is under a shared module path, otherwise $false.

.EXAMPLE
Test-IDBridgeSharedModulePath -ModuleBase (Get-Module IDBridge).ModuleBase

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-09-25
#>
function Test-IDBridgeSharedModulePath {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string]$ModuleBase,

        [Parameter()]
        [string[]]$SharedModulePaths
    )

    if (-not $PSBoundParameters.ContainsKey('SharedModulePaths')) {
        $SharedModulePaths = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split [IO.Path]::PathSeparator
        if ($env:ProgramFiles) { $SharedModulePaths += Join-Path $env:ProgramFiles 'PowerShell\Modules' }
    }

    $base = $ModuleBase.Replace('\', '/').TrimEnd('/')
    foreach ($sharedPath in $SharedModulePaths | Where-Object { $_ }) {
        $shared = $sharedPath.Replace('\', '/').TrimEnd('/')
        if ($base -eq $shared -or $base.StartsWith("$shared/", [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}
