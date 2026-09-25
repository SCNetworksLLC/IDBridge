<#
.SYNOPSIS
Unit tests for Test-IDBridgeSharedModulePath (pure helper — no mocking needed).

.DESCRIPTION
The answer decides whether Register-IDBridgeScheduledTask imports IDBridge by name or
refuses the install, so the match is pinned exactly: whole path segments only (a sibling
folder that merely starts with the shared path is not under it), case and separator
differences ignored. The tests always pass -SharedModulePaths - the default reads the
machine's PSModulePath, which is empty on the Linux runners.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Test-IDBridgeSharedModulePath' {
    It 'is shared under an all-users path: <ModuleBase>' -ForEach @(
        @{ ModuleBase = 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0' }
        @{ ModuleBase = 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0\' }          # trailing separator
        @{ ModuleBase = 'c:\program files\powershell\modules\IDBridge\26.9.21.0' }           # case
        @{ ModuleBase = 'C:/Program Files/PowerShell/Modules/IDBridge/26.9.21.0' }           # forward slashes
    ) {
        InModuleScope IDBridge -Parameters @{ ModuleBase = $ModuleBase } {
            Test-IDBridgeSharedModulePath -ModuleBase $ModuleBase -SharedModulePaths 'C:\Program Files\PowerShell\Modules' | Should -BeTrue
        }
    }

    It 'matches a shared path given with a trailing separator' {
        InModuleScope IDBridge {
            Test-IDBridgeSharedModulePath -ModuleBase 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0' -SharedModulePaths 'C:\Program Files\PowerShell\Modules\' | Should -BeTrue
        }
    }

    It 'is not shared outside every all-users path: <ModuleBase>' -ForEach @(
        @{ ModuleBase = 'C:\Users\admin\Documents\PowerShell\Modules\IDBridge\26.9.21.0' }   # a per-user install
        @{ ModuleBase = 'C:\Program Files\PowerShell\ModulesX\IDBridge\26.9.21.0' }          # sibling sharing the prefix
        @{ ModuleBase = 'C:\Program Files\PowerShell' }                                      # the shared path's parent
    ) {
        InModuleScope IDBridge -Parameters @{ ModuleBase = $ModuleBase } {
            Test-IDBridgeSharedModulePath -ModuleBase $ModuleBase -SharedModulePaths 'C:\Program Files\PowerShell\Modules' | Should -BeFalse
        }
    }

    It 'checks every shared path' {
        InModuleScope IDBridge {
            $sharedPaths = @('C:\Program Files\WindowsPowerShell\Modules', 'C:\Program Files\PowerShell\Modules')
            Test-IDBridgeSharedModulePath -ModuleBase 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0' -SharedModulePaths $sharedPaths | Should -BeTrue
            Test-IDBridgeSharedModulePath -ModuleBase 'C:\Users\admin\Documents\PowerShell\Modules\IDBridge\26.9.21.0' -SharedModulePaths $sharedPaths | Should -BeFalse
        }
    }

    It 'is not shared when there are no shared paths' {
        InModuleScope IDBridge {
            Test-IDBridgeSharedModulePath -ModuleBase 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0' -SharedModulePaths @() | Should -BeFalse
            Test-IDBridgeSharedModulePath -ModuleBase 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0' -SharedModulePaths @('', '') | Should -BeFalse
        }
    }
}
