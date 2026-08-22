<#
.SYNOPSIS
Unit tests for the username+name reconciliation matcher (Get-ADUsersToSetEmployeeID).

.DESCRIPTION
Get-IDBridgeApprovedNameMismatches is mocked in module scope so no ApprovedNameMismatches.csv
is read; tests hand it whatever approval state the case needs.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADUsersToSetEmployeeID' {
    It 'links an unlinked source user to an AD account matching by username and name' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)
        # An existing account with the right SamAccountName + names but no EmployeeID yet.
        $adUsers = @(New-TestADUser -EmployeeID $null -ObjectGUID 'guid-1' -CurrentGroups 'Staff' -Enabled $false)

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            $result = Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers

            $result.Count | Should -Be 1
            $result['10001'].ID | Should -Be 'guid-1'
            @($result['10001'].Groups) | Should -Be @('Staff')
            $result['10001'].EnabledStatus | Should -BeFalse

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*will link EmployeeID*' }
        }
    }

    It 'does not link when the username matches but the name differs (no approval) - logs an error' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)
        $adUsers = @(New-TestADUser -EmployeeID $null -GivenName 'Somebody' -Surname 'Else')

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            $result = Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*not linked*' }
        }
    }

    It 'links a name mismatch that was approved via Approve-IDBridgeNameMismatch' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)
        $adUsers = @(New-TestADUser -EmployeeID $null -ObjectGUID 'guid-1' -GivenName 'Somebody' -Surname 'Else')
        $approvals = @{ 'AD|10001' = [PSCustomObject]@{ Account = 'tuser'; DirectoryName = 'Somebody Else'; ApprovedDate = '2026-08-01' } }

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers; approvals = $approvals } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { $approvals }
            $result = Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers

            $result.Count | Should -Be 1
            $result['10001'].ID | Should -Be 'guid-1'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*mismatch approved on 2026-08-01*' }
        }
    }

    It 'does not honor an approval whose recorded directory name has drifted - warns instead' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)
        $adUsers = @(New-TestADUser -EmployeeID $null -GivenName 'Somebody' -Surname 'Renamed')
        # Approval was recorded against 'Somebody Else'; the account now reads 'Somebody Renamed'.
        $approvals = @{ 'AD|10001' = [PSCustomObject]@{ Account = 'tuser'; DirectoryName = 'Somebody Else'; ApprovedDate = '2026-08-01' } }

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers; approvals = $approvals } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { $approvals }
            $result = Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers

            $result.Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*no longer matches*' }
        }
    }

    It 'skips a source user whose personID already exists on an AD account' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)
        # Default New-TestADUser carries EmployeeID 10001 - already linked directory-side.
        $adUsers = @(New-TestADUser)

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            (Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers).Count | Should -Be 0
        }
    }

    It 'skips source users already linked, and users with no username match' {
        $records = @(
            (New-TestSourceRecord -PersonID '1')                                            # linked (ADCurrentUserID set)
            (New-TestSourceRecord -PersonID '2' -ADCurrentUserID $null -Username 'nobody')  # no such SamAccountName
        )
        $adUsers = @(New-TestADUser -EmployeeID $null)

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            (Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers).Count | Should -Be 0
        }
    }
}
