<#
.SYNOPSIS
Shared helpers for the IDBridge Pester tests.

.DESCRIPTION
Small toolkit imported by test files (`Import-Module $PSScriptRoot/../TestHelper.psm1 -Force`):
path resolution for the module under test, a fresh module import, and a factory for the
enriched source-record objects the pipeline's diffing functions consume.

Tests never touch C:\IDBridge, the real config, or any directory: module-internal calls to
Write-Log / Get-IDBridgeConfig are mocked inside module scope (see the Private\ test files
for the pattern).

.NOTES
   Created by: Sam Cattanach
#>

<#
.SYNOPSIS
Full path to the IDBridge module manifest under test (src\IDBridge\IDBridge.psd1).
#>
function Get-IDBridgeManifestPath {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    Join-Path (Split-Path $PSScriptRoot -Parent) 'src' 'IDBridge' 'IDBridge.psd1'
}

<#
.SYNOPSIS
Import the IDBridge module under test, replacing any already-loaded copy.
#>
function Import-IDBridgeForTest {
    [CmdletBinding()]
    param ()

    # -Global: this helper is itself a module, so a plain Import-Module would land the
    # IDBridge exports in the helper's scope instead of the test script's.
    Import-Module (Get-IDBridgeManifestPath) -Force -Global -ErrorAction Stop
}

<#
.SYNOPSIS
Build an enriched source record (source data + attached AD target state) for diff-function tests.

.DESCRIPTION
Returns a [pscustomobject] shaped like a record after the Add-TargetDataAD step: the source
fields plus the ADCurrent* link fields. Defaults describe an active, AD-provisioned, linked
user with no group changes pending; override only what a test cares about.

.EXAMPLE
$record = New-TestADRecord -GroupsProposed @('Staff','Math Dept') -ADCurrentGroups @('Staff')
#>
function New-TestADRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [string]$PersonID = '10001',
        [string]$NameFirst = 'Test',
        [string]$NameLast = 'User',
        [bool]$IDBActive = $true,
        [bool]$ProvisionAD = $true,
        [AllowNull()][string]$ADCurrentUserID = 'tuser',
        [AllowNull()][string[]]$GroupsProposed = @(),
        [AllowNull()][string[]]$ADCurrentGroups = @()
    )

    [PSCustomObject]@{
        PersonID        = $PersonID
        NameFirst       = $NameFirst
        NameLast        = $NameLast
        IDBActive       = $IDBActive
        ProvisionAD     = $ProvisionAD
        ADCurrentUserID = $ADCurrentUserID
        GroupsProposed  = $GroupsProposed
        ADCurrentGroups = $ADCurrentGroups
    }
}

Export-ModuleMember -Function Get-IDBridgeManifestPath, Import-IDBridgeForTest, New-TestADRecord
