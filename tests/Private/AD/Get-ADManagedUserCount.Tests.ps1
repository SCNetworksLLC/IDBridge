<#
.SYNOPSIS
Unit tests for the AD managed-population count (Get-ADManagedUserCount) - the change-volume
guard's denominator.

.DESCRIPTION
The population is the enabled AD accounts IDBridge has linked (EmployeeID set), anywhere in the
domain - never a count derived from the source feed, and not tied to AD.userRootOU (that key is
only the service account's delegation OU).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADManagedUserCount' {
    It 'counts enabled linked accounts in any OU, and ignores accounts IDBridge never linked' {
        $users = @(
            (New-TestADUser -SamAccountName 's1' -EmployeeID '1' -DistinguishedName 'CN=S1,OU=Grade-05,OU=Students,OU=District,DC=example,DC=org')
            (New-TestADUser -SamAccountName 't1' -EmployeeID '2' -DistinguishedName 'CN=T1,OU=Teacher,OU=Staff,OU=District,DC=example,DC=org')
            (New-TestADUser -SamAccountName 'x1' -EmployeeID '3' -DistinguishedName 'CN=X1,OU=Elsewhere,DC=example,DC=org')
            (New-TestADUser -SamAccountName 'svc' -EmployeeID $null -DistinguishedName 'CN=svc,OU=Service Accounts,DC=example,DC=org')
            (New-TestADUser -SamAccountName 'admin' -EmployeeID '' -DistinguishedName 'CN=admin,CN=Users,DC=example,DC=org')
        )

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-ADManagedUserCount -Users $users | Should -Be 3
        }
    }

    It 'excludes disabled linked accounts - e.g. deactivated users in the trash OU' {
        $users = @(
            (New-TestADUser -SamAccountName 'active' -EmployeeID '1')
            (New-TestADUser -SamAccountName 'trashed' -EmployeeID '2' -Enabled $false -DistinguishedName 'CN=T,OU=2026,OU=Students,OU=Trash,OU=District,DC=example,DC=org')
        )

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-ADManagedUserCount -Users $users | Should -Be 1
        }
    }

    It 'returns 0 when nothing is linked yet (a fresh domain) or there are no users' {
        $users = @(New-TestADUser -EmployeeID $null)

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-ADManagedUserCount -Users $users | Should -Be 0
            Get-ADManagedUserCount -Users $null | Should -Be 0
            Get-ADManagedUserCount -Users @() | Should -Be 0
        }
    }
}
