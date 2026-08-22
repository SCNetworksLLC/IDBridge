<#
.SYNOPSIS
Unit tests for the source-record validator (Test-IDBridgeSourceData).

.DESCRIPTION
The validator is public but logs through Write-Log, so the tests run it in module scope with
the log mocked. Valid records come from New-IDBridgeSourceRecord (the real factory); the
safety-net cases hand-build records the way a misbehaving plugin might.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    # A factory-built record that passes every rule: provisioned in both directories,
    # with OUs and keys set.
    $script:NewValidRecord = {
        param([hashtable]$Overrides = @{})
        $fields = @{
            PersonID                      = '10001'
            NameFirst                     = 'Test'
            NameLast                      = 'User'
            Username                      = 'tuser'
            UPN                           = 'tuser@example.org'
            Building                      = 'Main'
            JobTitle                      = 'Teacher'
            Company                       = 'District'
            PersonType                    = 'Staff'
            PersonTypeID                  = '2'
            IDBActive                     = $true
            ProvisionAD                   = $true
            ADOrganizationalUnit          = 'OU=Staff,DC=example,DC=org'
            ADOrganizationalUnitTrash     = 'OU=Trash,DC=example,DC=org'
            ADKey                         = (ConvertTo-SecureString 'x' -AsPlainText -Force)
            ProvisionGoogle               = $true
            GoogleOrganizationalUnit      = '/Staff'
            GoogleOrganizationalUnitTrash = '/Trash'
            GoogleKey                     = (ConvertTo-SecureString 'x' -AsPlainText -Force)
        }
        foreach ($key in $Overrides.Keys) { $fields[$key] = $Overrides[$key] }
        New-IDBridgeSourceRecord @fields
    }
}

Describe 'Test-IDBridgeSourceData' {
    It 'passes a fully-provisioned factory record' {
        $records = @(& $NewValidRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 1
            Should -Invoke Write-Log -Times 0 -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'accepts a passphrase API hashtable in place of a key' {
        $records = @(& $NewValidRecord @{ ADKey = $null; ADPassphraseAPI = @{ Mode = 'words' } })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest').Count | Should -Be 1
        }
    }

    It 'drops a record with no PersonID (safety net for records bypassing the factory)' {
        $records = @([PSCustomObject]@{ PersonID = '  '; IDBActive = $true; ProvisionAD = $false; ProvisionGoogle = $false })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*missing PersonID*' }
        }
    }

    It 'drops a record whose IDBActive is not a boolean' {
        $records = @([PSCustomObject]@{ PersonID = '1'; IDBActive = 'TRUE'; ProvisionAD = $false; ProvisionGoogle = $false })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*IDBActive is not a boolean*' }
        }
    }

    It 'drops an AD-provisioned record missing its OUs or key, naming every reason' {
        $records = @([PSCustomObject]@{ PersonID = '1'; IDBActive = $true; ProvisionAD = $true; ProvisionGoogle = $false })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter {
                $Level -eq 'Warn' -and
                $Message -like '*ADOrganizationalUnit is empty*' -and
                $Message -like '*ADOrganizationalUnitTrash is empty*' -and
                $Message -like '*no ADKey or ADPassphraseAPI*'
            }
        }
    }

    It 'drops a Google-provisioned record missing its OUs or key' {
        $records = @(& $NewValidRecord @{ GoogleOrganizationalUnit = ''; GoogleOrganizationalUnitTrash = ''; GoogleKey = $null })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 0
            Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*ProvisionGoogle but*' }
        }
    }

    It 'applies no directory rules to a record provisioned nowhere' {
        $records = @([PSCustomObject]@{ PersonID = '1'; IDBActive = $false; ProvisionAD = $false; ProvisionGoogle = $false })

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            @(Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest').Count | Should -Be 1
        }
    }

    It 'keeps the valid records when a batch is mixed, and skips null entries' {
        $records = @(
            (& $NewValidRecord)
            $null
            [PSCustomObject]@{ PersonID = ''; IDBActive = $true; ProvisionAD = $false; ProvisionGoogle = $false }
        )

        InModuleScope IDBridge -Parameters @{ records = $records } {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $records -PluginName 'Invoke-PluginTest'

            @($result).Count | Should -Be 1
            $result[0].PersonID | Should -Be '10001'
            # The summary counts only real records: 1 of 2 passed (the null entry is not counted).
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Trace' -and $Message -like '*1/2 records passed*' }
        }
    }

    It 'returns an empty array for null input' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeSourceData -InputObject $null -PluginName 'Invoke-PluginTest'

            $result -is [System.Array] | Should -BeTrue
            @($result).Count | Should -Be 0
        }
    }
}
