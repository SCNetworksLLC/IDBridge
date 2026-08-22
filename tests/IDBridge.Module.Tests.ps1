<#
.SYNOPSIS
Structural tests: every module file parses, the manifest is valid, the module imports,
and the exported surface matches the Public\ folder exactly.

.DESCRIPTION
These tests know nothing about behavior — they lock down the module's packaging rules:
one Verb-Noun function per file, Public\ = FunctionsToExport (the "added a function,
forgot the manifest" class of bug), Private\ never exported, Templates\ never loaded.
#>

BeforeDiscovery {
    $moduleRoot = Join-Path (Split-Path $PSCommandPath -Parent | Split-Path -Parent) 'src' 'IDBridge'
    $script:FunctionFiles = Get-ChildItem -Path (Join-Path $moduleRoot 'Private'), (Join-Path $moduleRoot 'Public') -Filter *.ps1 -Recurse |
        ForEach-Object { @{ Name = $_.Name; FullName = $_.FullName; BaseName = $_.BaseName } }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TestHelper.psm1') -Force
    $manifestPath = Get-IDBridgeManifestPath
    $moduleRoot = Split-Path $manifestPath -Parent
}

Describe 'Module files' {
    It 'parses without errors and defines exactly one matching function: <Name>' -ForEach $FunctionFiles {
        $tokens = $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FullName, [ref]$tokens, [ref]$errors)

        $errors | Should -BeNullOrEmpty

        # One function per file, named after the file - the repo's layout convention.
        $functions = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $functions.Count | Should -Be 1
        $functions[0].Name | Should -Be $BaseName
    }
}

Describe 'Module manifest' {
    It 'is a valid manifest' {
        { Test-ModuleManifest -Path $manifestPath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports every function in Public\ and nothing else' {
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $publicFunctions = (Get-ChildItem -Path (Join-Path $moduleRoot 'Public') -Filter *.ps1 -Recurse).BaseName

        # Compare as sets so the failure message names the exact drift in either direction.
        $missingFromManifest = $publicFunctions | Where-Object { $_ -notin $manifest.FunctionsToExport }
        $missingFromPublic = $manifest.FunctionsToExport | Where-Object { $_ -notin $publicFunctions }

        $missingFromManifest | Should -BeNullOrEmpty -Because 'every Public\ function must be in FunctionsToExport'
        $missingFromPublic | Should -BeNullOrEmpty -Because 'every FunctionsToExport entry must have a Public\ file'
    }
}

Describe 'Module import' {
    BeforeAll {
        Import-IDBridgeForTest
    }

    It 'imports and exposes the manifest surface exactly' {
        $exported = (Get-Command -Module IDBridge -CommandType Function).Name
        $manifest = Import-PowerShellDataFile -Path $manifestPath

        $exported | Should -Not -BeNullOrEmpty
        Compare-Object $exported $manifest.FunctionsToExport | Should -BeNullOrEmpty
    }

    It 'does not export Private\ functions' {
        $privateFunctions = (Get-ChildItem -Path (Join-Path $moduleRoot 'Private') -Filter *.ps1 -Recurse).BaseName
        $exported = (Get-Command -Module IDBridge -CommandType Function).Name

        $privateFunctions | Where-Object { $_ -in $exported } | Should -BeNullOrEmpty
    }

    It 'loads Private\ functions into module scope' {
        # Internal functions are callable inside the module (the & (Get-Module) pattern from CLAUDE.md).
        $names = & (Get-Module IDBridge) { (Get-Command Get-ADUserGroupsToUpdate, Get-TargetDataAD).Name }
        $names | Should -Be @('Get-ADUserGroupsToUpdate', 'Get-TargetDataAD')
    }
}
