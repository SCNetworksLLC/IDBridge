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

    It 'logs at Trace (nothing to reconcile) when the user is not active in AD and the matched account is already disabled' {
        # Neither the update step (active users) nor the deactivate step (enabled accounts) will
        # write the link, so an Info "will link" line would repeat on every run.
        $records = @(
            (New-TestSourceRecord -PersonID '1' -Username 'inactive' -IDBActive $false -ADCurrentUserID $null)
            (New-TestSourceRecord -PersonID '2' -Username 'unprovisioned' -ProvisionAD $false -ADCurrentUserID $null)
        )
        $adUsers = @(
            (New-TestADUser -SamAccountName 'inactive' -EmployeeID $null -Enabled $false)
            (New-TestADUser -SamAccountName 'unprovisioned' -EmployeeID $null -Enabled $false)
        )

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            $result = Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers

            $result.Count | Should -Be 2
            Should -Invoke Write-Log -Times 2 -Exactly -ParameterFilter { $Level -eq 'Trace' -and $Message -like '*already disabled - nothing to reconcile*' }
            Should -Invoke Write-Log -Times 0 -ParameterFilter { $Message -like '*will link EmployeeID*' }
        }
    }

    It 'keeps the Info "will link" line for an inactive user whose matched account is still enabled' {
        # The deactivate step will disable this account and write the link.
        $records = @(New-TestSourceRecord -IDBActive $false -ADCurrentUserID $null)
        $adUsers = @(New-TestADUser -EmployeeID $null -Enabled $true)

        InModuleScope IDBridge -Parameters @{ records = $records; adUsers = $adUsers } {
            Mock Write-Log {}
            Mock Get-IDBridgeApprovedNameMismatches { @{} }
            Get-ADUsersToSetEmployeeID -UserList $records -CurrentADUsers $adUsers | Out-Null

            # Write-Log is called without -Level (Info default), so assert "not demoted to Trace"
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -ne 'Trace' -and $Message -like '*will link EmployeeID*' }
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
