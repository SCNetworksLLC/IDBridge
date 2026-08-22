<#
.SYNOPSIS
Unit tests for the two-pass duplicate-personID removal (Remove-IDBridgeDuplicateID).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Remove-IDBridgeDuplicateID' {
    It 'removes records flagged as duplicates in AD or Google (pass 1)' {
        $records = @(
            (New-TestSourceRecord -PersonID '1')
            (New-TestSourceRecord -PersonID '2' | Add-Member -NotePropertyName ADDuplicateIDStatus -NotePropertyValue 'DUPLICATE_ID' -PassThru)
            (New-TestSourceRecord -PersonID '3' | Add-Member -NotePropertyName GoogleDuplicateIDStatus -NotePropertyValue 'DUPLICATE_ID' -PassThru)
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData $records

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '1'

            Should -Invoke Write-Log -Times 2 -Exactly -ParameterFilter { $Message -like '*Duplicate Person ID*' }
        }
    }

    It 'removes every record sharing a personID within the source set (pass 2)' {
        # Both copies go - there is no way to know which one is right.
        $records = @(
            (New-TestSourceRecord -PersonID '1')
            (New-TestSourceRecord -PersonID '2' -UPN 'a@example.org')
            (New-TestSourceRecord -PersonID '2' -UPN 'b@example.org')
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData $records

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '1'
        }
    }

    It 'does not treat blank personIDs as duplicates of each other' {
        $records = @(
            (New-TestSourceRecord -PersonID '' -UPN 'a@example.org')
            (New-TestSourceRecord -PersonID '' -UPN 'b@example.org')
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData $records

            @($result).Count | Should -Be 2
        }
    }

    It 'returns an array even for a single survivor' {
        $records = @(New-TestSourceRecord -PersonID '1')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData $records

            # Downstream code indexes and counts the result - a scalar would break it.
            $result -is [System.Array] | Should -BeTrue
            $result.Count | Should -Be 1
        }
    }

    It 'returns an empty array for empty input' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData @()

            @($result).Count | Should -Be 0
        }
    }

    It 'passes a clean set through untouched, logging nothing' {
        $records = @(
            (New-TestSourceRecord -PersonID '1')
            (New-TestSourceRecord -PersonID '2')
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Remove-IDBridgeDuplicateID -SourceData $records

            @($result).Count | Should -Be 2
            Should -Invoke Write-Log -Times 0
        }
    }
}
