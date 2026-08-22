<#
.SYNOPSIS
Unit tests for the AD update/rename/move diff (Get-ADUsersToUpdate).

.DESCRIPTION
The default New-TestSourceRecord and New-TestADUser fixtures match exactly, so the baseline is
"no changes proposed" and each test changes one thing. LookupByID is the personID -> AD user
hashtable Get-TargetDataAD would have built.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADUsersToUpdate' {
    It 'proposes nothing when AD already matches the source' {
        $records = @(New-TestSourceRecord)
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 0
            @($result.RenameList).Count | Should -Be 0
            @($result.MoveList).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'builds a Set-ADUser splat containing only the changed attribute (plus Identity/Division)' {
        $records = @(New-TestSourceRecord -JobTitle 'Principal')
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 1
            $splat = $result.UpdateList[0].Splat
            $splat.Title | Should -Be 'Principal'
            $splat.Identity | Should -Be 'tuser'
            $splat.Keys | Should -Contain 'Division'
            # Nothing else changed, so nothing else may be pushed.
            $splat.Count | Should -Be 3
        }
    }

    It 'applies a case-only name fix (names compare case-sensitively)' {
        $records = @(New-TestSourceRecord -NameFirst 'Test' -NameLast 'USER')
        $adUser = New-TestADUser   # Surname 'User'

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            $splat = $result.UpdateList[0].Splat
            $splat.Surname | Should -BeExactly 'USER'
            $splat.DisplayName | Should -BeExactly 'Test USER'
        }
    }

    It 'changes username and UPN together when the new username is free' {
        $records = @(New-TestSourceRecord -Username 'tuser2' -UPN 'tuser2@example.org')
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            $splat = $result.UpdateList[0].Splat
            $splat.SamAccountName | Should -Be 'tuser2'
            $splat.UserPrincipalName | Should -Be 'tuser2@example.org'
        }
    }

    It 'skips the whole user when the new username collides with a different account' {
        $records = @(New-TestSourceRecord -Username 'taken' -UPN 'taken@example.org' -JobTitle 'Principal')
        $adUser = New-TestADUser
        $conflict = New-TestADUser -SamAccountName 'taken' -UserPrincipalName 'taken@example.org' -ObjectGUID 'other-guid'

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser; conflict = $conflict } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser, $conflict)

            # Even the JobTitle change is dropped - the user is terminated for this run.
            @($result.UpdateList).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*has the username of*' }
        }
    }

    It 'does not treat the user''s own account as a username collision when only SamAccountName changes' {
        # UPN stays the same; the collision check must exclude the user's own ObjectGUID or the
        # unchanged UPN would match the user's own account.
        $records = @(New-TestSourceRecord -Username 'tuser2')
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 1
            $result.UpdateList[0].Splat.SamAccountName | Should -Be 'tuser2'
        }
    }

    It 're-enables a disabled account for an active user' {
        $records = @(New-TestSourceRecord)
        $adUser = New-TestADUser -Enabled $false

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            $result.UpdateList[0].Splat.Enabled | Should -BeTrue
        }
    }

    It 'ForceDisable wins: the account is disabled even though the user is active' {
        $records = @(New-TestSourceRecord -ForceDisable 'TRUE')
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            $result.UpdateList[0].Splat.Enabled | Should -BeFalse
        }
    }

    It 'does not clear optional attributes the source no longer provides (set-but-don''t-clear)' {
        $records = @(New-TestSourceRecord)   # Description/TelephoneNumber/EmailAddress all null
        $adUser = New-TestADUser -Description 'Old note' -OfficePhone '555-0100' -EmailAddress 'old@example.org'

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 0
        }
    }

    It 'replaces EmployeeType and extensionAttribute1 together when the person type changes' {
        $records = @(New-TestSourceRecord -PersonTypeID 'STUDENT')
        $adUser = New-TestADUser   # EmployeeType/extensionAttribute1 both 'STAFF'

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            $replace = $result.UpdateList[0].Splat.Replace
            $replace.EmployeeType | Should -Be 'STUDENT'
            $replace.extensionAttribute1 | Should -Be 'STUDENT'
        }
    }

    It 'proposes a rename when the CN no longer matches "First Last PersonID"' {
        $records = @(New-TestSourceRecord -NameLast 'Married')
        $adUser = New-TestADUser   # CN 'Test User 10001'

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.RenameList).Count | Should -Be 1
            $result.RenameList[0].NewName | Should -Be 'Test Married 10001'
        }
    }

    It 'proposes a move when the user sits in the wrong OU' {
        $records = @(New-TestSourceRecord -ADOrganizationalUnit 'OU=Students,DC=example,DC=org')
        $adUser = New-TestADUser   # DN under OU=Staff

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 0
            @($result.MoveList).Count | Should -Be 1
            $result.MoveList[0].NewOrgUnit | Should -Be 'OU=Students,DC=example,DC=org'
        }
    }

    It 'skips users that are inactive, not AD-provisioned, or unlinked' {
        $records = @(
            (New-TestSourceRecord -IDBActive $false -JobTitle 'Changed')
            (New-TestSourceRecord -ProvisionAD $false -JobTitle 'Changed')
            (New-TestSourceRecord -ADCurrentUserID $null -JobTitle 'Changed')
        )
        $adUser = New-TestADUser

        InModuleScope IDBridge -Parameters @{ records = $records; adUser = $adUser } {
            Mock Write-Log {}
            $result = Get-ADUsersToUpdate -UserList $records -LookupByID @{ '10001' = $adUser } -CurrentADUsers @($adUser)

            @($result.UpdateList).Count | Should -Be 0
            @($result.RenameList).Count | Should -Be 0
            @($result.MoveList).Count | Should -Be 0
        }
    }
}
