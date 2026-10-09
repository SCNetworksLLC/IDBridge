<#
.SYNOPSIS
Unit tests for the Google managed-population count (Get-GoogleManagedUserCount) - the
change-volume guard's denominator.

.DESCRIPTION
The population is the active Google accounts IDBridge has linked (a personID in the
'organization' externalId), wherever they sit in the OU tree - never a count derived from the
source feed, so a broken feed cannot shrink its own denominator.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Get-GoogleManagedUserCount' {
    It 'counts active linked accounts in any OU, and ignores accounts IDBridge never linked' {
        $users = @(
            (New-TestGoogleUser -primaryEmail 's1@example.org' -orgUnitPath '/Students/Grade-05' -ExternalIdValue '1')
            (New-TestGoogleUser -primaryEmail 's2@example.org' -orgUnitPath '/Students/Grade-12' -ExternalIdValue '2')
            (New-TestGoogleUser -primaryEmail 't1@example.org' -orgUnitPath '/Staff/Teacher' -ExternalIdValue '3')
            (New-TestGoogleUser -primaryEmail 'admin@example.org' -orgUnitPath '/Administrators' -ExternalIdValue $null)
            (New-TestGoogleUser -primaryEmail 'kiosk@example.org' -orgUnitPath '/Kiosk' -ExternalIdValue $null)
        )

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-GoogleManagedUserCount -Users $users | Should -Be 3
        }
    }

    It 'excludes linked accounts that are suspended or archived' {
        $users = @(
            (New-TestGoogleUser -primaryEmail 'active@example.org' -ExternalIdValue '1')
            (New-TestGoogleUser -primaryEmail 'archived@example.org' -ExternalIdValue '2' -archived $true)
            (New-TestGoogleUser -primaryEmail 'suspended@example.org' -ExternalIdValue '3' -suspended $true)
        )

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-GoogleManagedUserCount -Users $users | Should -Be 1
        }
    }

    It 'only counts an organization externalId with a value - other types and blank values are not a link' {
        $otherType = New-TestGoogleUser -primaryEmail 'other@example.org' -ExternalIdValue $null
        $otherType.externalIds = @([PSCustomObject]@{ type = 'custom'; value = '99' })
        $blank = New-TestGoogleUser -primaryEmail 'blank@example.org' -ExternalIdValue $null
        $blank.externalIds = @([PSCustomObject]@{ type = 'organization'; value = '' })
        $users = @($otherType, $blank, (New-TestGoogleUser -primaryEmail 'linked@example.org' -ExternalIdValue '1'))

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-GoogleManagedUserCount -Users $users | Should -Be 1
        }
    }

    It 'returns 0 when nothing is linked yet (a fresh tenant) or there are no users' {
        $users = @(New-TestGoogleUser -ExternalIdValue $null)

        InModuleScope IDBridge -Parameters @{ users = $users } {
            Get-GoogleManagedUserCount -Users $users | Should -Be 0
            Get-GoogleManagedUserCount -Users $null | Should -Be 0
            Get-GoogleManagedUserCount -Users @() | Should -Be 0
        }
    }
}
