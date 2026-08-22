<#
.SYNOPSIS
Unit tests for the primaryEmail+name reconciliation matcher (Get-GoogleUsersToSetEmployeeID).

.DESCRIPTION
Get-IDBridgeApprovedNameMismatches is mocked in module scope so no ApprovedNameMismatches.csv
is read; tests hand it whatever approval state the case needs.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleUsersToSetEmployeeID' {
    It 'links an unlinked source user to a Google account matching by primaryEmail and name' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null)
        $googleUsers = @(New-TestGoogleUser -ID 'g-1' -ExternalIdValue $null -CurrentGroups 'staff@example.org' -suspended $true)

        InModuleScope IDBridge -Parameters @{ records = $records; googleUsers = $googleUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            $result = Get-GoogleUsersToSetEmployeeID -UserList $records -GoogleUsers $googleUsers

            $result.Count | Should -Be 1
            $result['10001'].ID | Should -Be 'g-1'
            @($result['10001'].Groups) | Should -Be @('staff@example.org')
            # Suspended OR archived both count as deactivated for the link state.
            $result['10001'].SuspendedStatus | Should -BeTrue

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*will link EmployeeID*' }
        }
    }

    It 'does not link when the primaryEmail matches but the name differs (no approval) - logs an error' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null)
        $googleUsers = @(New-TestGoogleUser -GivenName 'Somebody' -FamilyName 'Else')

        InModuleScope IDBridge -Parameters @{ records = $records; googleUsers = $googleUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            $result = Get-GoogleUsersToSetEmployeeID -UserList $records -GoogleUsers $googleUsers

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*not linked*' }
        }
    }

    It 'links a name mismatch that was approved via Approve-IDBridgeNameMismatch' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null)
        $googleUsers = @(New-TestGoogleUser -ID 'g-1' -GivenName 'Somebody' -FamilyName 'Else')
        $approvals = @{ 'Google|10001' = [PSCustomObject]@{ Account = 'tuser@example.org'; DirectoryName = 'Somebody Else'; ApprovedDate = '2026-08-01' } }

        InModuleScope IDBridge -Parameters @{ records = $records; googleUsers = $googleUsers; approvals = $approvals } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { $approvals }
            $result = Get-GoogleUsersToSetEmployeeID -UserList $records -GoogleUsers $googleUsers

            $result.Count | Should -Be 1
            $result['10001'].ID | Should -Be 'g-1'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*mismatch approved on 2026-08-01*' }
        }
    }

    It 'does not honor an approval whose recorded directory name has drifted - warns instead' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null)
        $googleUsers = @(New-TestGoogleUser -GivenName 'Somebody' -FamilyName 'Renamed')
        $approvals = @{ 'Google|10001' = [PSCustomObject]@{ Account = 'tuser@example.org'; DirectoryName = 'Somebody Else'; ApprovedDate = '2026-08-01' } }

        InModuleScope IDBridge -Parameters @{ records = $records; googleUsers = $googleUsers; approvals = $approvals } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { $approvals }
            $result = Get-GoogleUsersToSetEmployeeID -UserList $records -GoogleUsers $googleUsers

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*no longer matches*' }
        }
    }

    It 'skips source users already linked, and users with no primaryEmail match' {
        $records = @(
            (New-TestSourceRecord -PersonID '1')                                                          # linked
            (New-TestSourceRecord -PersonID '2' -GoogleCurrentUserID $null -UPN 'nobody@example.org')     # no such primaryEmail
        )
        $googleUsers = @(New-TestGoogleUser)

        InModuleScope IDBridge -Parameters @{ records = $records; googleUsers = $googleUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            (Get-GoogleUsersToSetEmployeeID -UserList $records -GoogleUsers $googleUsers).Count | Should -Be 0
        }
    }
}
