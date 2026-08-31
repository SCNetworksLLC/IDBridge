<#
.SYNOPSIS
Unit tests for the Set-ADAccountPassword reset list (Get-ADUsersToResetPassword).

.DESCRIPTION
New-Passphrase is mocked in module scope, so no passphrase API is ever called; the mock echoes
one phrase per requested username so order mapping and chunking can be asserted.
ConvertTo-SecureString runs for real on the mocked values.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    $script:TestAPI = @{
        Nonce     = (ConvertTo-SecureString 'n1' -AsPlainText -Force)
        AuthToken = (ConvertTo-SecureString 't' -AsPlainText -Force)
        Mode      = 'words'
        WordCount = 3
    }
}

Describe 'Get-ADUsersToResetPassword' {
    It 'builds a Set-ADAccountPassword splat per user with phrases mapped in request order' {
        $users = @(
            New-TestADUser -SamAccountName 'alice' -DistinguishedName 'CN=Alice A 1,OU=Staff,DC=example,DC=org'
            New-TestADUser -SamAccountName 'bob' -DistinguishedName 'CN=Bob B 2,OU=Staff,DC=example,DC=org'
        )

        InModuleScope IDBridge -Parameters @{ users = $users; api = $TestAPI } {
            Mock Write-Log {}
            Mock New-Passphrase { @($Username | ForEach-Object { "phrase-$_" }) }

            $result = @(Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api)

            $result.Count | Should -Be 2
            $result[0].SamAccountName | Should -Be 'alice'
            $result[0].Passphrase | Should -Be 'phrase-alice'
            $result[1].Passphrase | Should -Be 'phrase-bob'

            $splat = $result[0].Splat
            $splat.Identity | Should -Be 'CN=Alice A 1,OU=Staff,DC=example,DC=org'
            $splat.Reset | Should -BeTrue
            $splat.NewPassword | Should -BeOfType [securestring]
            (ConvertFrom-SecureString $splat.NewPassword -AsPlainText) | Should -Be 'phrase-alice'

            Should -Invoke New-Passphrase -Times 1 -Exactly
            Should -Invoke Write-Log -Times 2 -Exactly -ParameterFilter { $Message -like '*Proposed: Reset password*' }
        }
    }

    It 'chunks more than 500 users into multiple New-Passphrase calls, keeping the mapping' {
        $users = @(1..501 | ForEach-Object {
            New-TestADUser -SamAccountName "user$_" -DistinguishedName "CN=User $_,OU=Students,DC=example,DC=org"
        })

        InModuleScope IDBridge -Parameters @{ users = $users; api = $TestAPI } {
            Mock Write-Log {}
            Mock New-Passphrase { @($Username | ForEach-Object { "phrase-$_" }) }

            $result = @(Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api)

            $result.Count | Should -Be 501
            Should -Invoke New-Passphrase -Times 2 -Exactly
            Should -Invoke New-Passphrase -Times 1 -Exactly -ParameterFilter { @($Username).Count -eq 500 }
            Should -Invoke New-Passphrase -Times 1 -Exactly -ParameterFilter { @($Username).Count -eq 1 }

            #The last user's phrase proves per-user mapping survives the chunk boundary
            $result[500].SamAccountName | Should -Be 'user501'
            $result[500].Passphrase | Should -Be 'phrase-user501'
        }
    }

    It 'forwards Rev to New-Passphrase only when the API block carries one' {
        $users = @(New-TestADUser)

        InModuleScope IDBridge -Parameters @{ users = $users; api = $TestAPI } {
            Mock Write-Log {}
            Mock New-Passphrase { @($Username | ForEach-Object { 'p' }) }

            Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api | Out-Null
            Should -Invoke New-Passphrase -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Rev') }

            $revAPI = $api.Clone()
            $revAPI.Rev = 2
            Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $revAPI | Out-Null
            Should -Invoke New-Passphrase -Times 1 -Exactly -ParameterFilter { $Rev -eq 2 }
        }
    }

    It 'throws without building any splat when the passphrase API fails' {
        $users = @(New-TestADUser)

        InModuleScope IDBridge -Parameters @{ users = $users; api = $TestAPI } {
            Mock Write-Log {}
            Mock New-Passphrase { throw 'HTTP 401' }

            { Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api } | Should -Throw '*HTTP 401*'
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Error' -and $Message -like '*Password API Error*' }
        }
    }

    It 'throws when Keysmith returns a different number of phrases than users requested' {
        $users = @(
            New-TestADUser -SamAccountName 'alice'
            New-TestADUser -SamAccountName 'bob'
        )

        InModuleScope IDBridge -Parameters @{ users = $users; api = $TestAPI } {
            Mock Write-Log {}
            Mock New-Passphrase { @('only-one-phrase') }

            { Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api } | Should -Throw '*1 passphrase(s) for 2 user(s)*'
        }
    }
}
