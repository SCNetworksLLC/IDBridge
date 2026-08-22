<#
.SYNOPSIS
Unit tests for the change-volume safety guard (Test-IDBridgeChangeThreshold).

.DESCRIPTION
This is the guard that stops a broken source feed from mass-changing a directory, so the
boundary behavior is pinned down exactly: the limit itself is allowed (-gt, not -ge), and a
zero population skips rather than blocks a legitimate first run.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'Test-IDBridgeChangeThreshold' {
    It 'does not trip below the threshold' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 10 -PopulationCount 100 -ThresholdPercent 25

            $result.Exceeded | Should -BeFalse
            $result.Skipped | Should -BeFalse
            $result.Percent | Should -Be 10

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -ne 'Warn' -and $Level -ne 'Error' }
        }
    }

    It 'does not trip at exactly the threshold (limit is inclusive)' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 25 -PopulationCount 100 -ThresholdPercent 25

            $result.Exceeded | Should -BeFalse
            $result.Percent | Should -Be 25
        }
    }

    It 'trips just above the threshold and logs a warning' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'Google' -ChangeCount 26 -PopulationCount 100 -ThresholdPercent 25

            $result.Exceeded | Should -BeTrue
            $result.Skipped | Should -BeFalse
            $result.Directory | Should -Be 'Google'

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'rounds the percentage to two decimals' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 1 -PopulationCount 3 -ThresholdPercent 25

            $result.Percent | Should -Be 33.33
            $result.Exceeded | Should -BeTrue
        }
    }

    It 'skips (never trips) on a zero population, warning instead' {
        # A fresh tenant / empty managed OU has no meaningful ratio - a first run that
        # creates everyone must not be blocked.
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 500 -PopulationCount 0 -ThresholdPercent 25

            $result.Skipped | Should -BeTrue
            $result.Exceeded | Should -BeFalse
            $result.Percent | Should -BeNullOrEmpty

            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'a threshold of 0 trips on any change' {
        InModuleScope IDBridge {
            Mock Write-Log {}
            $result = Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 1 -PopulationCount 1000 -ThresholdPercent 0

            $result.Exceeded | Should -BeTrue
        }
    }

    It 'rejects a threshold outside 0-100' {
        InModuleScope IDBridge {
            { Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount 1 -PopulationCount 10 -ThresholdPercent 101 } |
                Should -Throw
        }
    }
}
