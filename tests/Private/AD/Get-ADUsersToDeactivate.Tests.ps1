<#
.SYNOPSIS
Unit tests for the AD deactivate selection (Get-ADUsersToDeactivate).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADUsersToDeactivate' {
    It 'selects an inactive user whose AD account is still enabled' {
        $records = @(New-TestSourceRecord -IDBActive $false)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUsersToDeactivate -UserList $records

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '10001'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Proposed: Deactivate User*' }
        }
    }

    It 'selects an active user that is no longer AD-provisioned' {
        $records = @(New-TestSourceRecord -ProvisionAD $false)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-ADUsersToDeactivate -UserList $records).Count | Should -Be 1
        }
    }

    It 'skips an inactive user whose AD account is already disabled' {
        $records = @(New-TestSourceRecord -IDBActive $false -ADCurrentUserEnabledStatus $false)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-ADUsersToDeactivate -UserList $records).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'never selects an active, provisioned user' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-ADUsersToDeactivate -UserList $records).Count | Should -Be 0
        }
    }

    It 'logs the current groups of a user being deactivated' {
        $records = @(New-TestSourceRecord -IDBActive $false -ADCurrentGroups 'Staff', 'Math Dept')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Get-ADUsersToDeactivate -UserList $records | Out-Null

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Current groups for 10001: Staff, Math Dept*' }
        }
    }
}
