<#
.SYNOPSIS
Unit tests for Format-IDBridgeName (pure helper — no mocking needed).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Format-IDBridgeName' {
    It 'title-cases "<Name>" to "<Expected>"' -ForEach @(
        @{ Name = 'JOSHUA MOIN';   Expected = 'Joshua Moin' }
        @{ Name = 'MARY-JANE';     Expected = 'Mary-Jane' }
        @{ Name = "O'BRIEN";       Expected = "O'Brien" }
        @{ Name = 'van der berg';  Expected = 'Van Der Berg' }
        @{ Name = 'ANNE--MARIE';   Expected = 'Anne--Marie' }   # consecutive separators survive
        @{ Name = 'SMITH-';        Expected = 'Smith-' }        # trailing separator survives
        @{ Name = '-SMITH';        Expected = '-Smith' }        # leading separator survives
        @{ Name = 'X';             Expected = 'X' }
    ) {
        Format-IDBridgeName $Name | Should -BeExactly $Expected
    }

    It 'cannot know intentional internal capitals (documented limitation)' {
        # McDonald -> Mcdonald is the documented tradeoff, not a bug. If this test starts
        # failing, the limitation was fixed - update the comment-based help too.
        Format-IDBridgeName 'McDONALD' | Should -BeExactly 'Mcdonald'
    }

    It 'trims surrounding whitespace' {
        Format-IDBridgeName '  bob  ' | Should -BeExactly 'Bob'
    }

    It 'returns null/empty/whitespace input unchanged' {
        Format-IDBridgeName $null | Should -BeExactly ''   # [string] param coerces $null to ''
        Format-IDBridgeName '' | Should -BeExactly ''
        Format-IDBridgeName '   ' | Should -BeExactly '   '
    }

    It 'accepts pipeline input' {
        'MARY-JANE', "O'BRIEN" | Format-IDBridgeName | Should -BeExactly @('Mary-Jane', "O'Brien")
    }
}
