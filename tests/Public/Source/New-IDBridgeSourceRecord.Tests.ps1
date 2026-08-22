<#
.SYNOPSIS
Unit tests for the source-record factory (New-IDBridgeSourceRecord).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    # The minimum a plugin must supply; tests splat this and override per case.
    $script:BaseFields = @{
        PersonID        = '10001'
        NameFirst       = 'Test'
        NameLast        = 'User'
        Username        = 'tuser'
        UPN             = 'tuser@example.org'
        Building        = 'Main'
        JobTitle        = 'Teacher'
        Company         = 'District'
        PersonType      = 'Staff'
        PersonTypeID    = '2'
        IDBActive       = $true
        ProvisionAD     = $true
        ProvisionGoogle = $true
    }
}

Describe 'New-IDBridgeSourceRecord' {
    It 'builds a record with the defaults applied' {
        $record = New-IDBridgeSourceRecord @BaseFields

        $record.PersonID | Should -Be '10001'
        $record.ForceDisable | Should -BeFalse
        $record.GoogleOUOverride | Should -BeFalse
        $record.PasswordNeverExpires | Should -BeFalse
        $record.ADChangePasswordAtLogon | Should -BeFalse
        $record.ADOrganizationalUnit | Should -Be ''
        $record.ADKey | Should -BeNullOrEmpty
        $record.GroupsProposed | Should -Be @()
    }

    It 'normalizes a null GroupsProposed to an empty string array' {
        $record = New-IDBridgeSourceRecord @BaseFields -GroupsProposed $null

        , $record.GroupsProposed | Should -BeOfType [string[]]
        $record.GroupsProposed.Count | Should -Be 0
    }

    It 'normalizes blank optional strings to $null (so blank reads as absent)' {
        $record = New-IDBridgeSourceRecord @BaseFields -Department '' -Description '   ' -InternalID $null

        $record.Department | Should -BeNullOrEmpty
        $record.Description | Should -BeNullOrEmpty
        $record.InternalID | Should -BeNullOrEmpty
    }

    It 'keeps non-blank optional strings' {
        $record = New-IDBridgeSourceRecord @BaseFields -Department 'Math'

        $record.Department | Should -Be 'Math'
    }

    It 'rejects an empty core identity field' {
        { New-IDBridgeSourceRecord @BaseFields -PersonID '' -ErrorAction Stop } | Should -Throw
        { New-IDBridgeSourceRecord @BaseFields -NameFirst '' -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a PersonTypeID outside 1/2/3' {
        { New-IDBridgeSourceRecord @BaseFields -PersonTypeID '9' -ErrorAction Stop } | Should -Throw
    }

    It 'rejects a plain-string ADKey (SecureString required)' {
        { New-IDBridgeSourceRecord @BaseFields -ADKey 'plaintext' -ErrorAction Stop } | Should -Throw
        { New-IDBridgeSourceRecord @BaseFields -ADKey (ConvertTo-SecureString 'x' -AsPlainText -Force) } | Should -Not -Throw
    }
}
