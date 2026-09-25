<#
.SYNOPSIS
Unit tests for Get-IDBridgeTaskCommand (pure helper — no mocking needed).

.DESCRIPTION
The string is what Task Scheduler runs as the gMSA, so both shapes are asserted whole,
quoting included - a change to either is a deliberate one.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-IDBridgeTaskCommand' {
    It 'imports IDBridge by name without -ModulePath' {
        InModuleScope IDBridge {
            Get-IDBridgeTaskCommand -RootPath 'C:\IDBridge' |
                Should -BeExactly "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"Import-Module IDBridge; Invoke-IDBridge -RootPath 'C:\IDBridge'`""
        }
    }

    It 'imports the pinned manifest with -ModulePath' {
        InModuleScope IDBridge {
            Get-IDBridgeTaskCommand -RootPath 'D:\IDBridge' -ModulePath 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0\IDBridge.psd1' |
                Should -BeExactly "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"Import-Module 'C:\Program Files\PowerShell\Modules\IDBridge\26.9.21.0\IDBridge.psd1'; Invoke-IDBridge -RootPath 'D:\IDBridge'`""
        }
    }
}
