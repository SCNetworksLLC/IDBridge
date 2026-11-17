<#
.SYNOPSIS
Unit tests for the run-start marker Initialize-IDBridge writes.

.DESCRIPTION
The marker is the run's first log line once logging is up, and carries the run's own ID
when Invoke-IDBridge passes one - that is how a run's log is found from what a PostRun
plugin sent. The setup callers pass none, and their marker stays as it was. A throwaway
root under TestDrive holds a minimal config with both directories off, so no AD module
import is attempted.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Initialize-IDBridge run-start marker' {
    BeforeEach {
        $rootPath = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path (Join-Path $rootPath 'Config') -ItemType Directory -Force | Out-Null
        Set-Content -Path (Join-Path $rootPath 'Config' 'IDBridgeConfig.psd1') -Value "@{ Debug = @{ readOnly = `$true }; AD = @{ enabled = `$false }; Google = @{ enabled = `$false } }"
    }

    It 'names the run ID on the Begin line when one is given' {
        InModuleScope IDBridge -Parameters @{ rootPath = $rootPath } {
            Mock Write-Log {}
            Mock Write-Host {}

            Initialize-IDBridge -RootPath $rootPath -RunId '3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b'

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '######## Begin of Script Run: * Run ID: 3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b ########' }
        }
    }

    It 'writes the Begin line without an ID when none is given' {
        InModuleScope IDBridge -Parameters @{ rootPath = $rootPath } {
            Mock Write-Log {}
            Mock Write-Host {}

            Initialize-IDBridge -RootPath $rootPath

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '######## Begin of Script Run: * ########' }
            Should -Invoke Write-Log -Times 0 -Exactly -ParameterFilter { $Message -like '*Run ID*' }
        }
    }
}
