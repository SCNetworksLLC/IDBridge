<#
.SYNOPSIS
Unit tests for the Google deactivate selection (Get-GoogleUsersToDeactivate).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleUsersToDeactivate' {
    It 'selects an inactive user whose Google account is not yet deactivated' {
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleObject (New-TestGoogleUser))

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToDeactivate -UserList $records

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '10001'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Proposed: Deactivate User*' }
        }
    }

    It 'selects an active user that is no longer Google-provisioned' {
        $records = @(New-TestSourceRecord -ProvisionGoogle $false -GoogleObject (New-TestGoogleUser))

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-GoogleUsersToDeactivate -UserList $records).Count | Should -Be 1
        }
    }

    It 'skips an inactive user whose account is already deactivated' {
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleCurrentUserSuspendedStatus $true)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-GoogleUsersToDeactivate -UserList $records).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'never selects an active, provisioned user' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Get-GoogleUsersToDeactivate -UserList $records).Count | Should -Be 0
        }
    }

    It 'logs the paid licenses the deactivation will remove, by name (falling back to skuId)' {
        $licenses = @(
            [PSCustomObject]@{ skuName = 'Education Plus'; skuId = 'sku-1' }
            [PSCustomObject]@{ skuId = 'sku-2' }   # no name known - the id is logged instead
        )
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleObject (New-TestGoogleUser) -GoogleCurrentLicenses $licenses)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Get-GoogleUsersToDeactivate -UserList $records | Out-Null

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*will remove licenses from 10001: Education Plus, sku-2*' }
        }
    }

    It 'flags a name-matched account whose externalId is not set yet' {
        # Matched by UPN+name: the Google account has no personID externalId, so the
        # deactivate step must also set it or the account is re-matched every run.
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleObject (New-TestGoogleUser -ExternalIdValue $null))

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Get-GoogleUsersToDeactivate -UserList $records | Out-Null

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*will also set EmployeeID*' }
        }
    }

    It 'does not flag an account already carrying the personID externalId' {
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleObject (New-TestGoogleUser))

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Get-GoogleUsersToDeactivate -UserList $records | Out-Null

            Should -Invoke Write-Log -Times 0 -ParameterFilter { $Message -like '*will also set EmployeeID*' }
        }
    }
}
