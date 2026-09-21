<#
.SYNOPSIS
Unit tests for the end-of-run summary file (Write-IDBridgeRunSummary).

.DESCRIPTION
The file is a contract with a reader on the box, so the two things that could break that
reader are pinned exactly: the key set (a stranger key is what could carry a person out of
the module) and lastSuccessAt, the one field a single run cannot supply - runEnd on a
success, carried forward from the previous file on a failure. The write itself is
best-effort: an unwritable Data directory logs a Warn and the run carries on.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    # The schema, in the order it is written.
    $schemaKeys = @(
        'schemaVersion', 'moduleVersion', 'runStart', 'runEnd', 'durationSeconds',
        'success', 'readOnly', 'testRun', 'directories',
        'managed', 'created', 'updated', 'deactivated', 'groupAdds', 'groupRemoves',
        'writeFailures', 'thresholdExceeded', 'errorType', 'errorFunction', 'lastSuccessAt'
    )

    function New-TestRunResult {
        param (
            [bool]$Success = $true,
            $RunError = $null,
            [bool]$ReadOnly = $false,
            [bool]$TestRun = $false,
            [int]$Failed = 0,
            $ThresholdResults = @()
        )
        [PSCustomObject]@{
            SchemaVersion    = 1
            ModuleVersion    = '26.9.1.3'
            Success          = $Success
            RunError         = $RunError
            RunStart         = [DateTime]::new(2026, 9, 9, 3, 0, 0, [DateTimeKind]::Utc)
            RunEnd           = [DateTime]::new(2026, 9, 9, 3, 0, 47, [DateTimeKind]::Utc)
            DurationSeconds  = 47
            ReadOnly         = $ReadOnly
            TestRun          = $TestRun
            Counts           = [PSCustomObject]@{
                Managed = 412; Create = 3; Update = 5; Deactivate = 1; GroupAdd = 2; GroupRemove = 0; Failed = $Failed
            }
            ThresholdResults = $ThresholdResults
        }
    }

    function New-TestRunError {
        param ([string]$Message)
        try { throw [System.InvalidOperationException]::new($Message) } catch { return $_ }
    }
}

Describe 'Write-IDBridgeRunSummary' {
    BeforeEach {
        # A Data directory of its own per test, so the carry-forward cases control exactly
        # which previous file is there. The function addresses the file the way every other
        # Data-file reader does, so the test builds the same path.
        $dataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $dataRoot -ItemType Directory | Out-Null
        $summaryPath = "$dataRoot\LastRun.json"
    }

    It 'writes exactly the schema keys, in order, for a successful run' {
        $runResult = New-TestRunResult

        InModuleScope IDBridge -Parameters @{ runResult = $runResult; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            Write-IDBridgeRunSummary -RunResult $runResult
        }

        $text = Get-Content -Path $summaryPath -Raw
        $summary = $text | ConvertFrom-Json

        @($summary.PSObject.Properties.Name) | Should -Be $schemaKeys

        $summary.schemaVersion | Should -Be 1
        $summary.durationSeconds | Should -Be 47
        $summary.success | Should -BeTrue
        $summary.readOnly | Should -BeFalse
        $summary.testRun | Should -BeFalse
        $summary.directories | Should -Be 'AD+Google'
        $summary.managed | Should -Be 412
        $summary.created | Should -Be 3
        $summary.updated | Should -Be 5
        $summary.deactivated | Should -Be 1
        $summary.groupAdds | Should -Be 2
        $summary.groupRemoves | Should -Be 0
        $summary.writeFailures | Should -Be 0
        $summary.thresholdExceeded | Should -BeFalse
        $summary.errorType | Should -Be ''
        $summary.errorFunction | Should -Be ''

        # Stamps go out ISO-8601 UTC (ConvertFrom-Json reads them back as [datetime], so the
        # text is what pins the format), and a successful run IS the last success.
        $text | Should -BeLike '*"runStart": "2026-09-09T03:00:00Z"*'
        $text | Should -BeLike '*"runEnd": "2026-09-09T03:00:47Z"*'
        $text | Should -BeLike '*"lastSuccessAt": "2026-09-09T03:00:47Z"*'
    }

    It 'carries the previous success time forward through a failed run, without its message' {
        $goodRun = New-TestRunResult
        $failedRun = New-TestRunResult -Success $false -Failed 2 `
            -RunError (New-TestRunError -Message 'Change threshold exceeded: AD 31% (limit 25%) - tuser@example.org')

        InModuleScope IDBridge -Parameters @{ goodRun = $goodRun; failedRun = $failedRun; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            # The good run first - its runEnd is the success time the failure inherits.
            Write-IDBridgeRunSummary -RunResult $goodRun
            Write-IDBridgeRunSummary -RunResult $failedRun
        }

        $text = Get-Content -Path $summaryPath -Raw
        $summary = $text | ConvertFrom-Json

        $summary.success | Should -BeFalse
        $summary.writeFailures | Should -Be 2
        $summary.errorType | Should -Be 'InvalidOperationException'
        $summary.errorFunction | Should -Not -BeNullOrEmpty
        $text | Should -BeLike '*"lastSuccessAt": "2026-09-09T03:00:47Z"*'

        # The exception MESSAGE never reaches the file.
        $text | Should -Not -BeLike '*Change threshold exceeded*'
        $text | Should -Not -BeLike '*@example.org*'
    }

    It 'has no success time to carry forward when there is no previous file' {
        $failedRun = New-TestRunResult -Success $false -RunError (New-TestRunError -Message 'Change threshold exceeded: AD 31% (limit 25%).')

        InModuleScope IDBridge -Parameters @{ failedRun = $failedRun; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $false } } }

            Write-IDBridgeRunSummary -RunResult $failedRun
        }

        $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
        $summary.lastSuccessAt | Should -Be ''
        $summary.directories | Should -Be 'AD'
    }

    It 'reports thresholdExceeded when a directory tripped the guard' {
        $thresholds = @(
            [PSCustomObject]@{ Directory = 'AD'; Exceeded = $false; Skipped = $false; Percent = 3 }
            [PSCustomObject]@{ Directory = 'Google'; Exceeded = $true; Skipped = $false; Percent = 31 }
        )
        $runResult = New-TestRunResult -ThresholdResults $thresholds

        InModuleScope IDBridge -Parameters @{ runResult = $runResult; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            Write-IDBridgeRunSummary -RunResult $runResult
        }

        (Get-Content -Path $summaryPath -Raw | ConvertFrom-Json).thresholdExceeded | Should -BeTrue
    }

    It 'flags a ReadOnly run and writes the counts it was given' {
        $runResult = New-TestRunResult -ReadOnly $true

        InModuleScope IDBridge -Parameters @{ runResult = $runResult; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            Write-IDBridgeRunSummary -RunResult $runResult
        }

        $summary = Get-Content -Path $summaryPath -Raw | ConvertFrom-Json
        $summary.readOnly | Should -BeTrue
        $summary.success | Should -BeTrue
        $summary.created | Should -Be 3
    }

    It 'treats a previous file that will not parse as no previous file' {
        Set-Content -Path $summaryPath -Value '{ this is not json'
        $failedRun = New-TestRunResult -Success $false -RunError (New-TestRunError -Message 'Change threshold exceeded: AD 31% (limit 25%).')

        InModuleScope IDBridge -Parameters @{ failedRun = $failedRun; dataRoot = $dataRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            { Write-IDBridgeRunSummary -RunResult $failedRun } | Should -Not -Throw
        }

        (Get-Content -Path $summaryPath -Raw | ConvertFrom-Json).lastSuccessAt | Should -Be ''
    }

    It 'logs a Warn and does not throw when the file cannot be written' {
        $runResult = New-TestRunResult
        # A Data directory that does not exist - Set-Content has nowhere to write.
        $missingRoot = Join-Path $dataRoot 'gone'

        InModuleScope IDBridge -Parameters @{ runResult = $runResult; dataRoot = $missingRoot } {
            Mock Write-Log {}
            Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot }; AD = @{ enabled = $true }; Google = @{ enabled = $true } } }

            { Write-IDBridgeRunSummary -RunResult $runResult } | Should -Not -Throw

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'Run summary: Write failed*' }
        }
    }
}
