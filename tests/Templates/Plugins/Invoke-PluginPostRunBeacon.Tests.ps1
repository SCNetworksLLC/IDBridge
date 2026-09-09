<#
.SYNOPSIS
Unit tests for the shipped Invoke-PluginPostRunBeacon template: the heartbeat envelope and the send.

.DESCRIPTION
The template is dot-sourced from src\IDBridge\Templates\Plugins the way Invoke-PostRunPlugins
dot-sources an installed copy. ConvertTo-BeaconHeartbeat is pure and gets the result/message
cases; the send is exercised with Get-IDBridgeSecret, Invoke-RestMethod and Write-Log mocked
(the template's own copy keeps its placeholders, so the plugin entry point is tested for the
throw those placeholders promise).
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
    . (Join-Path (Split-Path (Get-IDBridgeManifestPath) -Parent) 'Templates' 'Plugins' 'Invoke-PluginPostRunBeacon.ps1')

    function New-TestRunResult {
        param (
            [bool]$Success = $true,
            $RunError = $null,
            [bool]$ReadOnly = $false,
            [bool]$TestRun = $false,
            [int]$Failed = 0
        )
        [PSCustomObject]@{
            SchemaVersion   = 1
            ModuleVersion   = '26.9.1.3'
            Success         = $Success
            RunError        = $RunError
            RunStart        = [DateTime]::new(2026, 9, 9, 3, 0, 0, [DateTimeKind]::Utc)
            RunEnd          = [DateTime]::new(2026, 9, 9, 3, 0, 47, [DateTimeKind]::Utc)
            DurationSeconds = 47
            ReadOnly        = $ReadOnly
            TestRun         = $TestRun
            Counts          = [PSCustomObject]@{
                Managed = 412; Create = 3; Update = 5; Deactivate = 1; GroupAdd = 2; GroupRemove = 0; Failed = $Failed
            }
        }
    }
}

Describe 'ConvertTo-BeaconHeartbeat' {
    It 'builds a Success envelope with the counts in the message and the data' {
        $envelope = ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult) -SiteId 'colby' -SourceId 'idbridge-sync'

        $envelope.siteId | Should -Be 'colby'
        $envelope.sourceType | Should -Be 'automation'
        $envelope.sourceId | Should -Be 'idbridge-sync'
        $envelope.collectedAt | Should -Be '2026-09-09T03:00:47Z'
        $envelope.data.result | Should -Be 'Success'
        $envelope.data.message | Should -Be '412 managed: 3 created, 5 updated, 1 deactivated, 2 group changes, 0 write failures, 47s'
        $envelope.data.managed | Should -Be 412
        $envelope.data.created | Should -Be 3
        $envelope.data.groupAdds | Should -Be 2
        $envelope.data.writeFailures | Should -Be 0
        $envelope.data.moduleVersion | Should -Be '26.9.1.3'
        $envelope.data.readOnly | Should -BeFalse
    }

    It 'is a Warning when a write did not stick' {
        $envelope = ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult -Failed 2) -SiteId 'colby' -SourceId 'idbridge-sync'
        $envelope.data.result | Should -Be 'Warning'
        $envelope.data.message | Should -BeLike '*2 write failures, 47s'
        $envelope.data.writeFailures | Should -Be 2
    }

    It 'is Failed with the error class and message when the run threw' {
        $runError = $null
        try { throw [System.InvalidOperationException]::new('Change threshold exceeded: AD 31% (limit 25%).') } catch { $runError = $_ }
        $envelope = ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult -Success $false -RunError $runError) -SiteId 'colby' -SourceId 'idbridge-sync'
        $envelope.data.result | Should -Be 'Failed'
        $envelope.data.message | Should -Be 'run failed after 47s -- InvalidOperationException: Change threshold exceeded: AD 31% (limit 25%).'
    }

    It 'names the mode of a ReadOnly or test run in the message, still a Success' {
        (ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult -ReadOnly $true) -SiteId 'colby' -SourceId 'idbridge-sync').data.message |
            Should -BeLike 'ReadOnly: 412 managed:*'
        (ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult -TestRun $true) -SiteId 'colby' -SourceId 'idbridge-sync').data.message |
            Should -BeLike 'test run: 412 managed:*'
        (ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult -ReadOnly $true) -SiteId 'colby' -SourceId 'idbridge-sync').data.result |
            Should -Be 'Success'
    }

    It 'serializes to the envelope Beacon ingests -- no per-user data, counts only' {
        $json = ConvertTo-BeaconHeartbeat -RunResult (New-TestRunResult) -SiteId 'colby' -SourceId 'idbridge-sync' | ConvertTo-Json -Depth 5 -Compress
        $json | Should -BeLike '{"siteId":"colby","sourceType":"automation","sourceId":"idbridge-sync","collectedAt":"2026-09-09T03:00:47Z","data":{"result":"Success","message":"412 managed:*'
        $json | Should -Not -BeLike '*SourceData*'
        $json | Should -Not -BeLike '*Applied*'
    }
}

Describe 'Invoke-PluginPostRunBeacon' {
    It 'throws while the template still carries its placeholders' {
        { Invoke-PluginPostRunBeacon -RunResult (New-TestRunResult) } | Should -Throw '*placeholder values*'
    }

    Context 'with the placeholders edited' {
        BeforeAll {
            # An edited copy, as a district's Plugins folder holds it.
            $template = Get-Content -Raw (Join-Path (Split-Path (Get-IDBridgeManifestPath) -Parent) 'Templates' 'Plugins' 'Invoke-PluginPostRunBeacon.ps1')
            $edited = $template.Replace('"https://YOUR-BEACON/api/ingest"   #', '"https://beacon.test/api/ingest"   #').Replace('"YOUR-SITE-ID"                      #', '"colby"                             #')
            $editedPath = Join-Path $TestDrive 'Invoke-PluginPostRunBeacon.ps1'
            Set-Content -Path $editedPath -Value $edited
            . $editedPath
        }

        BeforeEach {
            Mock Write-Log {}
            Mock Get-IDBridgeSecret { 'bcn_test' }
        }

        It 'POSTs the envelope to the ingest URL with the vault key and logs the send' {
            Mock Invoke-RestMethod { [pscustomobject]@{ accepted = 1; rejected = 0 } }
            Invoke-PluginPostRunBeacon -RunResult (New-TestRunResult)
            Should -Invoke Get-IDBridgeSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'ApiKey-Beacon' -and $AsPlainText }
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://beacon.test/api/ingest' -and $Method -eq 'Post' -and $Headers['x-api-key'] -eq 'bcn_test' -and
                $ContentType -eq 'application/json' -and $TimeoutSec -eq 30 -and $Body -like '{"siteId":"colby","sourceType":"automation","sourceId":"idbridge-sync",*'
            }
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Trace' -and $Message -like '*sent a Success heartbeat: 412 managed:*' }
        }

        It 'logs a Warn and does not throw when Beacon rejects the heartbeat' {
            Mock Invoke-RestMethod { [pscustomobject]@{ accepted = 0; rejected = 1; errors = @([pscustomobject]@{ index = 0; error = 'siteId unknown' }) } }
            { Invoke-PluginPostRunBeacon -RunResult (New-TestRunResult) } | Should -Not -Throw
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*rejected the heartbeat*siteId unknown*' }
        }

        It 'logs a Warn and does not throw when the send fails -- the run is unaffected' {
            Mock Invoke-RestMethod { throw [System.Net.WebException]::new('The remote name could not be resolved') }
            { Invoke-PluginPostRunBeacon -RunResult (New-TestRunResult) } | Should -Not -Throw
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*send failed (run unaffected): WebException' }
        }

        It 'logs a Warn and does not throw when the vault has no key' {
            Mock Get-IDBridgeSecret { throw [System.IO.FileNotFoundException]::new('ApiKey-Beacon') }
            Mock Invoke-RestMethod { throw 'must not be reached' }
            { Invoke-PluginPostRunBeacon -RunResult (New-TestRunResult) } | Should -Not -Throw
            Should -Invoke Invoke-RestMethod -Times 0 -Exactly
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*send failed (run unaffected): FileNotFoundException' }
        }
    }
}
