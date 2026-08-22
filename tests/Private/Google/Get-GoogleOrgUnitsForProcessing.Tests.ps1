<#
.SYNOPSIS
Unit tests for the missing-Google-OU planner (Get-GoogleOrgUnitsForProcessing).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleOrgUnitsForProcessing' {
    It 'expands ancestors and orders parents before children' {
        $records = @(New-TestSourceRecord -GoogleOrganizationalUnit '/A/B/C' -GoogleOrganizationalUnitTrash '/Trash')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            # Only /A exists; everything under it (and the trash OU) needs creating.
            $result = @(Get-GoogleOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('/A'))

            $result | Should -Contain '/A/B'
            $result | Should -Contain '/A/B/C'
            $result | Should -Contain '/Trash'
            $result | Should -Not -Contain '/A'
            $result.IndexOf('/A/B') | Should -BeLessThan $result.IndexOf('/A/B/C')

            Should -Invoke Write-Log -Times 3 -Exactly -ParameterFilter { $Message -like '*Proposed: Create Org Unit*' }
        }
    }

    It 'deduplicates OUs shared by multiple users' {
        $records = @(
            (New-TestSourceRecord -PersonID '1')
            (New-TestSourceRecord -PersonID '2')
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-GoogleOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('/'))

            # Both users share /Staff and /Trash - each appears once.
            $result | Should -Be @('/Staff', '/Trash')
        }
    }

    It 'ignores inactive users' {
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleOrganizationalUnit '/New')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-GoogleOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('/'))

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'returns nothing when every needed OU already exists' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-GoogleOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('/Staff', '/Trash'))

            $result.Count | Should -Be 0
        }
    }
}
