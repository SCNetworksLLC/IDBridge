<#
.SYNOPSIS
Unit tests for the Google group-membership diff (Get-GoogleUserGroupsToUpdate).

.DESCRIPTION
Proposed groups are names; current memberships (GoogleCurrentGroups) are the groups' real
emails — the diff maps between the two via the GoogleGroups name/email table, so a group whose
email does not match its name still diffs correctly.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    # A group whose email matches its name, and one whose email does not (the Grade-PK case).
    $script:Groups = @(
        [PSCustomObject]@{ name = 'Staff'; email = 'staff@example.org' }
        [PSCustomObject]@{ name = 'Grade-PK'; email = 'studentsgradepk@example.org' }
    )
}

Describe 'Get-GoogleUserGroupsToUpdate' {
    It 'adds a proposed group the user is not in yet' {
        $records = @(New-TestSourceRecord -GroupsProposed 'Staff', 'Grade-PK' -GoogleCurrentGroups 'staff@example.org')

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 1
            $result.Add[0].PersonID | Should -Be '10001'
            $result.Add[0].GoogleCurrentUserID | Should -Be 'g-tuser'
            @($result.Add[0].Groups) | Should -Be @('Grade-PK')
            @($result.Remove).Count | Should -Be 0

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Add Groups*' }
        }
    }

    It 'recognizes membership by the group''s email even when it differs from the name' {
        # Proposed 'Grade-PK'; current membership is the email studentsgradepk@ - already a member.
        $records = @(New-TestSourceRecord -GroupsProposed 'Grade-PK' -GoogleCurrentGroups 'studentsgradepk@example.org')

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
        }
    }

    It 'never adds a proposed group that does not exist in Google' {
        $records = @(New-TestSourceRecord -GroupsProposed 'Ghost Group')

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 0
        }
    }

    It 'removes a membership whose group name is no longer proposed - the Remove list stays emails' {
        $records = @(New-TestSourceRecord -GroupsProposed 'Staff' -GoogleCurrentGroups 'staff@example.org', 'studentsgradepk@example.org')

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 1
            # The API call needs the email; the log line shows the name.
            @($result.Remove[0].Groups) | Should -Be @('studentsgradepk@example.org')
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Remove Groups: 10001*Grade-PK*' }
        }
    }

    It 'still computes removals when no groups exist in Google (GoogleGroups is null)' {
        $records = @(New-TestSourceRecord -GroupsProposed 'Staff' -GoogleCurrentGroups 'old@example.org')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $null

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 1
            @($result.Remove[0].Groups) | Should -Be @('old@example.org')
        }
    }

    It 'skips users that are inactive, not Google-provisioned, or not linked to a Google account' {
        $records = @(
            (New-TestSourceRecord -PersonID '1' -IDBActive $false -GroupsProposed 'Staff')
            (New-TestSourceRecord -PersonID '2' -ProvisionGoogle $false -GroupsProposed 'Staff')
            (New-TestSourceRecord -PersonID '3' -GoogleCurrentUserID $null -GroupsProposed 'Staff')
        )

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'returns empty lists when membership already matches' {
        $records = @(New-TestSourceRecord -GroupsProposed 'Staff' -GoogleCurrentGroups 'staff@example.org')

        InModuleScope IDBridge -Parameters @{ records = $records; groups = $Groups } {
            Mock Write-Log {}
            $result = Get-GoogleUserGroupsToUpdate -UserList $records -GoogleGroups $groups

            @($result.Add).Count | Should -Be 0
            @($result.Remove).Count | Should -Be 0
        }
    }
}
