<#
.SYNOPSIS
Unit tests for the AD group-membership diff (Get-ADUserGroupsToUpdate).

.DESCRIPTION
Template for testing the Private\ decision functions: build synthetic enriched records with
New-TestADRecord, enter module scope with InModuleScope (the function isn't exported), and
mock Write-Log so no config or filesystem is needed. Pure decide-phase — nothing here can
touch AD.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADUserGroupsToUpdate' {
    It 'adds a proposed group the user is not in yet' {
        $records = @(New-TestADRecord -GroupsProposed 'Staff', 'Math Dept' -ADCurrentGroups 'Staff')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups @('Staff', 'Math Dept')

            @($result.Add).Count | Should -Be 1
            $result.Add[0].PersonID | Should -Be '10001'
            $result.Add[0].ADCurrentUserID | Should -Be 'tuser'
            @($result.Add[0].Groups) | Should -Be @('Math Dept')
            @($result.Remove).Count | Should -Be 0

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Add Groups*' }
        }
    }

    It 'never adds a proposed group that does not exist in AD' {
        $records = @(New-TestADRecord -GroupsProposed 'Ghost Group' -ADCurrentGroups @())

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups @('Staff')

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
        }
    }

    It 'removes a current group that is no longer proposed' {
        $records = @(New-TestADRecord -GroupsProposed 'Staff' -ADCurrentGroups 'Staff', 'Old Team')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups @('Staff', 'Old Team')

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 1
            @($result.Remove[0].Groups) | Should -Be @('Old Team')

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Remove Groups*' }
        }
    }

    It 'still computes removals when no groups exist in AD (CurrentADGroups is null)' {
        $records = @(New-TestADRecord -GroupsProposed 'Staff' -ADCurrentGroups 'Old Team')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups $null

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 1
            @($result.Remove[0].Groups) | Should -Be @('Old Team')
        }
    }

    It 'skips users that are inactive, not AD-provisioned, or not linked to an AD account' {
        # Each record proposes an obvious change that must NOT surface because of its gate field.
        $records = @(
            (New-TestADRecord -PersonID '1' -IDBActive $false -GroupsProposed 'Staff')
            (New-TestADRecord -PersonID '2' -ProvisionAD $false -GroupsProposed 'Staff')
            (New-TestADRecord -PersonID '3' -ADCurrentUserID $null -GroupsProposed 'Staff')
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups @('Staff')

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'returns empty lists when membership already matches' {
        $records = @(New-TestADRecord -GroupsProposed 'Staff' -ADCurrentGroups 'Staff')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUserGroupsToUpdate -UserList $records -CurrentADGroups @('Staff')

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
        }
    }
}
