<#
.SYNOPSIS
Unit tests for the Google update diff (Get-GoogleUsersToUpdate).

.DESCRIPTION
The default New-TestSourceRecord and New-TestGoogleUser fixtures match exactly, so the baseline
is "no changes proposed" and each test changes one thing. LookupByID is the externalId -> user
hashtable Get-TargetDataGoogle would have built.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleUsersToUpdate' {
    It 'proposes nothing when Google already matches the source' {
        $records = @(New-TestSourceRecord)
        $googleUser = New-TestGoogleUser

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'changes the primaryEmail when the new UPN is free' {
        $records = @(New-TestSourceRecord -UPN 'tuser2@example.org')
        $googleUser = New-TestGoogleUser

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            @($result).Count | Should -Be 1
            $splat = $result[0].Splat
            $splat.PrimaryEmail | Should -Be 'tuser2@example.org'
            $splat.GoogleUserID | Should -Be 'g-tuser'
            $splat.Keys | Should -Not -Contain 'RemoveAlias'
        }
    }

    It 'skips the whole user when the new UPN is already another primaryEmail' {
        $records = @(New-TestSourceRecord -UPN 'taken@example.org' -JobTitle 'Principal')
        $googleUser = New-TestGoogleUser
        $conflict = New-TestGoogleUser -primaryEmail 'taken@example.org' -ID 'g-other' -ExternalIdValue '99999'

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser; conflict = $conflict } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser, $conflict)

            # Even the JobTitle change is dropped for this run.
            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*already in use*' }
        }
    }

    It 'removes the alias first when the new UPN exists only as another account''s alias' {
        $records = @(New-TestSourceRecord -UPN 'shared@example.org')
        $googleUser = New-TestGoogleUser
        $aliasHolder = New-TestGoogleUser -primaryEmail 'holder@example.org' -ID 'g-holder' -ExternalIdValue '99999' -AliasEmails 'shared@example.org'

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser; aliasHolder = $aliasHolder } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser, $aliasHolder)

            @($result).Count | Should -Be 1
            $splat = $result[0].Splat
            $splat.PrimaryEmail | Should -Be 'shared@example.org'
            $splat.RemoveAlias | Should -Be 'shared@example.org'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*will remove alias from holder@example.org*' }
        }
    }

    It 'sets the personID externalId when the account does not carry it yet' {
        $records = @(New-TestSourceRecord)
        $googleUser = New-TestGoogleUser -ExternalIdValue $null

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            $result[0].Splat.PersonID | Should -Be '10001'
        }
    }

    It 'applies a case-only name fix (names compare case-sensitively)' {
        $records = @(New-TestSourceRecord -NameLast 'USER')
        $googleUser = New-TestGoogleUser   # familyName 'User'

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            $result[0].Splat.LastName | Should -BeExactly 'USER'
            $result[0].Splat.FirstName | Should -BeExactly 'Test'
        }
    }

    It 'unsuspends and unarchives a deactivated account for an active user (rehire)' {
        $records = @(New-TestSourceRecord)
        $googleUser = New-TestGoogleUser -suspended $true -archived $true

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            $splat = $result[0].Splat
            $splat.Suspended | Should -BeExactly 'false'
            $splat.Archived | Should -BeExactly 'false'
        }
    }

    It 'ForceDisable suspends (never archives) even though the user is active' {
        $records = @(New-TestSourceRecord -ForceDisable 'TRUE')
        $googleUser = New-TestGoogleUser

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            $splat = $result[0].Splat
            $splat.Suspended | Should -BeExactly 'true'
            $splat.Keys | Should -Not -Contain 'Archived'
        }
    }

    It 'moves the user to the proposed OU' {
        $records = @(New-TestSourceRecord -GoogleOrganizationalUnit '/Students')
        $googleUser = New-TestGoogleUser   # orgUnitPath '/Staff'

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            $result[0].Splat.OrgUnitPath | Should -Be '/Students'
        }
    }

    It 'honors GoogleOUOverride: the OU is left alone' {
        $records = @(New-TestSourceRecord -GoogleOrganizationalUnit '/Students' -GoogleOUOverride 'TRUE')
        $googleUser = New-TestGoogleUser

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            @($result).Count | Should -Be 0
        }
    }

    It 'skips users that are inactive, not Google-provisioned, or unlinked' {
        $records = @(
            (New-TestSourceRecord -IDBActive $false -JobTitle 'Changed')
            (New-TestSourceRecord -ProvisionGoogle $false -JobTitle 'Changed')
            (New-TestSourceRecord -GoogleCurrentUserID $null -JobTitle 'Changed')
        )
        $googleUser = New-TestGoogleUser

        InModuleScope IDBridge -Parameters @{ records = $records; googleUser = $googleUser } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToUpdate -UserList $records -LookupByID @{ '10001' = $googleUser } -GoogleUsers @($googleUser)

            @($result).Count | Should -Be 0
        }
    }
}
