<#
.SYNOPSIS
Unit tests for the missing-AD-OU planner (Get-ADOrgUnitsForProcessing).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADOrgUnitsForProcessing' {
    It 'expands ancestors and orders parents before children' {
        $records = @(New-TestSourceRecord -ADOrganizationalUnit 'OU=C,OU=B,OU=A,DC=example,DC=org' -ADOrganizationalUnitTrash 'OU=Trash,DC=example,DC=org')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            # Only OU=A exists; everything under it (and the trash OU) needs creating.
            $result = @(Get-ADOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('OU=A,DC=example,DC=org'))

            $result | Should -Be @(
                'OU=Trash,DC=example,DC=org'
                'OU=B,OU=A,DC=example,DC=org'
                'OU=C,OU=B,OU=A,DC=example,DC=org'
            )
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
            $result = @(Get-ADOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('DC=example,DC=org'))

            # Both users share OU=Staff and OU=Trash - each appears once.
            $result | Should -Be @('OU=Staff,DC=example,DC=org', 'OU=Trash,DC=example,DC=org')
        }
    }

    It 'matches existing OUs case-insensitively' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-ADOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('ou=staff,dc=example,dc=org', 'OU=TRASH,DC=EXAMPLE,DC=ORG'))

            $result.Count | Should -Be 0
        }
    }

    It 'ignores inactive users' {
        $records = @(New-TestSourceRecord -IDBActive $false -ADOrganizationalUnit 'OU=New,DC=example,DC=org')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-ADOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('DC=example,DC=org'))

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'returns nothing when every needed OU already exists' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = @(Get-ADOrgUnitsForProcessing -UserList $records -CurrentOrgUnits @('OU=Staff,DC=example,DC=org', 'OU=Trash,DC=example,DC=org'))

            $result.Count | Should -Be 0
        }
    }
}
