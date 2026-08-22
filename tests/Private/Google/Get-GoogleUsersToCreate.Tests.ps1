<#
.SYNOPSIS
Unit tests for the Google create list (Get-GoogleUsersToCreate).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleUsersToCreate' {
    It 'builds a New-IDBridgeGoogleUser splat for an unlinked user with a GoogleKey' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null -GoogleKey 'presetsecret')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org')

            @($result).Count | Should -Be 1
            $result[0].UPN | Should -Be 'tuser@example.org'
            $result[0].PersonID | Should -Be '10001'

            $splat = $result[0].Splat
            $splat.PrimaryEmail | Should -Be 'tuser@example.org'
            $splat.PersonID | Should -Be '10001'
            $splat.FirstName | Should -Be 'Test'
            $splat.LastName | Should -Be 'User'
            $splat.Building | Should -Be 'Main'
            $splat.JobTitle | Should -Be 'Teacher'
            $splat.OrgUnitPath | Should -Be '/Staff'
            $splat.ChangeAtNextLogin | Should -Be 'true'
            $splat.Password | Should -Be 'presetsecret'

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*Proposed: Create User*' }
        }
    }

    It 'maps GoogleChangePasswordAtLogon $false to the string ''false''' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null -GoogleKey 'k' -GoogleChangePasswordAtLogon $false)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $splat = (Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org'))[0].Splat

            $splat.ChangeAtNextLogin | Should -BeExactly 'false'
        }
    }

    It 'gets the password from the passphrase API when GooglePassphraseAPI is set' {
        # Nonce/AuthToken are SecureStrings on New-Passphrase - a plain string would fail binding.
        $api = [PSCustomObject]@{
            Nonce     = (ConvertTo-SecureString 'n1' -AsPlainText -Force)
            Mode      = 'words'
            WordCount = 4
            AuthToken = (ConvertTo-SecureString 't' -AsPlainText -Force)
        }
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null -GooglePassphraseAPI $api)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Mock New-Passphrase { 'correct-horse-battery-staple' }
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org')

            @($result).Count | Should -Be 1
            $result[0].Splat.Password | Should -BeOfType [securestring]

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
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null -GooglePassphraseAPI $api)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            Mock New-Passphrase { throw 'API down' }
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org')

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*Password API Error*' }
        }
    }

    It 'skips the user (with a warning) when neither GooglePassphraseAPI nor GoogleKey is set' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org')

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*GoogleKey is not set*' }
        }
    }

    It 'never creates a user whose UPN already exists as a Google primaryEmail' {
        $records = @(New-TestSourceRecord -GoogleCurrentUserID $null -GoogleKey 'k')

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser)   # holds tuser@example.org

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 0
        }
    }

    It 'skips users that are inactive, not Google-provisioned, or already linked' {
        $records = @(
            (New-TestSourceRecord -PersonID '1' -IDBActive $false -GoogleCurrentUserID $null -GoogleKey 'k')
            (New-TestSourceRecord -PersonID '2' -ProvisionGoogle $false -GoogleCurrentUserID $null -GoogleKey 'k')
            (New-TestSourceRecord -PersonID '3' -GoogleKey 'k')   # linked: default GoogleCurrentUserID
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Get-GoogleUsersToCreate -UserList $records -GoogleUsers @(New-TestGoogleUser -primaryEmail 'other@example.org')

            @($result).Count | Should -Be 0
        }
    }
}
