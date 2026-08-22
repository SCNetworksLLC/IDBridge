<#
.SYNOPSIS
Unit tests for the New-ADUser creation list (Get-ADUsersToCreate).

.DESCRIPTION
New-Passphrase is mocked in module scope, so no passphrase API is ever called; ConvertTo-SecureString
runs for real on the mocked value.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-ADUsersToCreate' {
    It 'builds a New-ADUser splat for an unlinked user with an ADKey' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADKey 'presetsecret' -InternalID '555')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org')

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '10001'

            $splat = $result[0].Splat
            $splat.Name | Should -Be 'Test User 10001'
            $splat.DisplayName | Should -Be 'Test User'
            $splat.SamAccountName | Should -Be 'tuser'
            $splat.UserPrincipalName | Should -Be 'tuser@example.org'
            $splat.EmployeeID | Should -Be '10001'
            $splat.EmployeeNumber | Should -Be '555'
            $splat.Path | Should -Be 'OU=Staff,DC=example,DC=org'
            $splat.OtherAttributes.EmployeeType | Should -Be 'STAFF'
            $splat.OtherAttributes.extensionAttribute1 | Should -Be 'STAFF'
            $splat.Enabled | Should -BeTrue
            $splat.AccountPassword | Should -Be 'presetsecret'

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Proposed: Create User*' }
        }
    }

    It 'omits optional attributes the record does not provide' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADKey 'k')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $splat = (Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org'))[0].Splat

            $splat.Keys | Should -Not -Contain 'EmployeeNumber'
            $splat.Keys | Should -Not -Contain 'Description'
            $splat.Keys | Should -Not -Contain 'OfficePhone'
            $splat.Keys | Should -Not -Contain 'EmailAddress'
            $splat.OtherAttributes.Keys | Should -Not -Contain 'extensionAttribute2'
        }
    }

    It 'includes optional attributes when provided' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADKey 'k' `
            -Description 'Long-term sub' -TelephoneNumber '555-0100' -EmailAddress 'contact@example.org' -ExtensionAttribute2 'X2')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $splat = (Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org'))[0].Splat

            $splat.Description | Should -Be 'Long-term sub'
            $splat.OfficePhone | Should -Be '555-0100'
            $splat.EmailAddress | Should -Be 'contact@example.org'
            $splat.OtherAttributes.extensionAttribute2 | Should -Be 'X2'
        }
    }

    It 'gets the password from the passphrase API when ADPassphraseAPI is set' {
        # Nonce/AuthToken are SecureStrings on New-Passphrase - a plain string would fail binding.
        $api = [PSCustomObject]@{
            Nonce     = (ConvertTo-SecureString 'n1' -AsPlainText -Force)
            Mode      = 'words'
            WordCount = 4
            AuthToken = (ConvertTo-SecureString 't' -AsPlainText -Force)
        }
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADPassphraseAPI $api)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Mock New-Passphrase { 'correct-horse-battery-staple' }
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org')

            @($result).Count | Should -Be 1
            $result[0].Splat.AccountPassword | Should -BeOfType [securestring]

            Should -Invoke New-Passphrase -Times 1 -Exactly -ParameterFilter { $Username -contains 'tuser' -and $Mode -eq 'words' }
        }
    }

    It 'skips the user (with a warning) when the passphrase API fails' {
        $api = [PSCustomObject]@{
            Nonce     = (ConvertTo-SecureString 'n1' -AsPlainText -Force)
            Mode      = 'words'
            WordCount = 4
            AuthToken = (ConvertTo-SecureString 't' -AsPlainText -Force)
        }
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADPassphraseAPI $api)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Mock New-Passphrase { throw 'API down' }
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org')

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*Password API Error*' }
        }
    }

    It 'skips the user (with a warning) when neither ADPassphraseAPI nor ADKey is set' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org')

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*ADKey is not set*' }
        }
    }

    It 'never creates a user whose UPN already exists in AD' {
        $records = @(New-TestSourceRecord -ADCurrentUserID $null -ADKey 'k')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            # An account (any account) already holds tuser@example.org.
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser)

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'skips users that are inactive, not AD-provisioned, or already linked' {
        $records = @(
            (New-TestSourceRecord -PersonID '1' -IDBActive $false -ADCurrentUserID $null -ADKey 'k')
            (New-TestSourceRecord -PersonID '2' -ProvisionAD $false -ADCurrentUserID $null -ADKey 'k')
            (New-TestSourceRecord -PersonID '3' -ADKey 'k')   # linked: default ADCurrentUserID
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-ADUsersToCreate -UserList $records -CurrentADUsers @(New-TestADUser -UserPrincipalName 'other@example.org')

            @($result).Count | Should -Be 0
        }
    }
}
