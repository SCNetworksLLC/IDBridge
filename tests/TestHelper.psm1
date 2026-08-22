<#
.SYNOPSIS
Shared helpers for the IDBridge Pester tests.

.DESCRIPTION
Small toolkit imported by test files (`Import-Module $PSScriptRoot/../TestHelper.psm1 -Force`):
path resolution for the module under test, a fresh module import, and factories for the three
object shapes the pipeline's diffing functions consume — enriched source records, AD users, and
Google users. The factory defaults are mutually consistent: a default record diffed against a
default AD/Google user proposes NO changes, so each test overrides only the field it is about.

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
Build an enriched source record (source data + attached AD/Google target state) for diff-function tests.

.DESCRIPTION
Returns a [pscustomobject] shaped like a record after the Add-TargetData* steps: the source
fields plus the ADCurrent* / GoogleCurrent* link fields. Defaults describe an active user,
provisioned and linked in both directories, whose state already matches New-TestADUser /
New-TestGoogleUser — no changes pending. Override only what a test cares about.

.EXAMPLE
$record = New-TestSourceRecord -GroupsProposed @('Staff','Math Dept') -ADCurrentGroups @('Staff')
#>
function New-TestSourceRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [string]$PersonID = '10001',
        [string]$NameFirst = 'Test',
        [string]$NameLast = 'User',
        [string]$Username = 'tuser',
        [string]$UPN = 'tuser@example.org',
        [bool]$IDBActive = $true,
        [string]$JobTitle = 'Teacher',
        [string]$Building = 'Main',
        [string]$Company = 'District',
        [string]$Department = 'Staff',
        [string]$PersonTypeID = 'STAFF',
        [AllowNull()][string]$InternalID = $null,
        [AllowNull()][string]$Description = $null,
        [AllowNull()][string]$TelephoneNumber = $null,
        [AllowNull()][string]$EmailAddress = $null,
        [AllowNull()][string]$ExtensionAttribute2 = $null,
        [AllowNull()][string]$ExtensionAttribute3 = $null,
        [AllowNull()][string]$ExtensionAttribute4 = $null,
        [bool]$PasswordNeverExpires = $false,
        [AllowNull()][string]$ForceDisable = $null,
        [AllowNull()][string[]]$GroupsProposed = @(),

        # AD provisioning + attached AD target state
        [bool]$ProvisionAD = $true,
        [AllowNull()][string]$ADCurrentUserID = 'tuser',
        [bool]$ADCurrentUserEnabledStatus = $true,
        [AllowNull()][string[]]$ADCurrentGroups = @(),
        [string]$ADOrganizationalUnit = 'OU=Staff,DC=example,DC=org',
        [bool]$ADChangePasswordAtLogon = $true,
        $ADPassphraseAPI = $null,
        $ADKey = $null,

        # Google provisioning + attached Google target state
        [bool]$ProvisionGoogle = $true,
        [AllowNull()][string]$GoogleCurrentUserID = 'g-tuser',
        [bool]$GoogleCurrentUserSuspendedStatus = $false,
        [AllowNull()][string[]]$GoogleCurrentGroups = @(),
        $GoogleCurrentLicenses = $null,
        $GoogleObject = $null,
        [string]$GoogleOrganizationalUnit = '/Staff',
        [bool]$GoogleChangePasswordAtLogon = $true,
        $GooglePassphraseAPI = $null,
        $GoogleKey = $null,
        [AllowNull()][string]$GoogleOUOverride = $null
    )

    [PSCustomObject]@{
        PersonID                         = $PersonID
        NameFirst                        = $NameFirst
        NameLast                         = $NameLast
        Username                         = $Username
        UPN                              = $UPN
        IDBActive                        = $IDBActive
        JobTitle                         = $JobTitle
        Building                         = $Building
        Company                          = $Company
        Department                       = $Department
        PersonTypeID                     = $PersonTypeID
        InternalID                       = $InternalID
        Description                      = $Description
        TelephoneNumber                  = $TelephoneNumber
        EmailAddress                     = $EmailAddress
        ExtensionAttribute2              = $ExtensionAttribute2
        ExtensionAttribute3              = $ExtensionAttribute3
        ExtensionAttribute4              = $ExtensionAttribute4
        PasswordNeverExpires             = $PasswordNeverExpires
        ForceDisable                     = $ForceDisable
        GroupsProposed                   = $GroupsProposed
        ProvisionAD                      = $ProvisionAD
        ADCurrentUserID                  = $ADCurrentUserID
        ADCurrentUserEnabledStatus       = $ADCurrentUserEnabledStatus
        ADCurrentGroups                  = $ADCurrentGroups
        ADOrganizationalUnit             = $ADOrganizationalUnit
        ADChangePasswordAtLogon          = $ADChangePasswordAtLogon
        ADPassphraseAPI                  = $ADPassphraseAPI
        ADKey                            = $ADKey
        ProvisionGoogle                  = $ProvisionGoogle
        GoogleCurrentUserID              = $GoogleCurrentUserID
        GoogleCurrentUserSuspendedStatus = $GoogleCurrentUserSuspendedStatus
        GoogleCurrentGroups              = $GoogleCurrentGroups
        GoogleCurrentLicenses            = $GoogleCurrentLicenses
        GoogleObject                     = $GoogleObject
        GoogleOrganizationalUnit         = $GoogleOrganizationalUnit
        GoogleChangePasswordAtLogon      = $GoogleChangePasswordAtLogon
        GooglePassphraseAPI              = $GooglePassphraseAPI
        GoogleKey                        = $GoogleKey
        GoogleOUOverride                 = $GoogleOUOverride
    }
}

<#
.SYNOPSIS
Build a current-AD-user object (the Get-TargetDataAD shape) for diff-function tests.

.DESCRIPTION
Defaults match New-TestSourceRecord exactly, so a default AD user diffed against a default
record produces no update/rename/move. Override only the field under test.

.EXAMPLE
$adUser = New-TestADUser -title 'Old Title'
#>
function New-TestADUser {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [string]$SamAccountName = 'tuser',
        [string]$UserPrincipalName = 'tuser@example.org',
        [string]$ObjectGUID = 'tuser',
        [AllowNull()][string]$EmployeeID = '10001',
        [AllowNull()][string]$EmployeeNumber = $null,
        [string]$GivenName = 'Test',
        [string]$Surname = 'User',
        [string]$DisplayName = 'Test User',
        [AllowNull()][string]$physicalDeliveryOfficeName = 'Main',
        [AllowNull()][string]$title = 'Teacher',
        [AllowNull()][string]$company = 'District',
        [AllowNull()][string]$Department = 'Staff',
        [AllowNull()][string]$Description = $null,
        [AllowNull()][string]$OfficePhone = $null,
        [AllowNull()][string]$EmailAddress = $null,
        [bool]$PasswordNeverExpires = $false,
        [bool]$Enabled = $true,
        [AllowNull()][string]$EmployeeType = 'STAFF',
        [AllowNull()][string]$extensionAttribute1 = 'STAFF',
        [AllowNull()][string]$extensionAttribute2 = $null,
        [AllowNull()][string]$extensionAttribute3 = $null,
        [AllowNull()][string]$extensionAttribute4 = $null,
        [string]$CN = 'Test User 10001',
        [string]$DistinguishedName = 'CN=Test User 10001,OU=Staff,DC=example,DC=org',
        [AllowNull()][string[]]$CurrentGroups = @()
    )

    [PSCustomObject]@{
        SamAccountName             = $SamAccountName
        UserPrincipalName          = $UserPrincipalName
        ObjectGUID                 = $ObjectGUID
        EmployeeID                 = $EmployeeID
        EmployeeNumber             = $EmployeeNumber
        GivenName                  = $GivenName
        Surname                    = $Surname
        DisplayName                = $DisplayName
        physicalDeliveryOfficeName = $physicalDeliveryOfficeName
        title                      = $title
        company                    = $company
        Department                 = $Department
        Description                = $Description
        OfficePhone                = $OfficePhone
        EmailAddress               = $EmailAddress
        PasswordNeverExpires       = $PasswordNeverExpires
        Enabled                    = $Enabled
        EmployeeType               = $EmployeeType
        extensionAttribute1        = $extensionAttribute1
        extensionAttribute2        = $extensionAttribute2
        extensionAttribute3        = $extensionAttribute3
        extensionAttribute4        = $extensionAttribute4
        CN                         = $CN
        DistinguishedName          = $DistinguishedName
        CurrentGroups              = $CurrentGroups
    }
}

<#
.SYNOPSIS
Build a current-Google-user object (the Get-TargetDataGoogle shape) for diff-function tests.

.DESCRIPTION
Defaults match New-TestSourceRecord exactly, so a default Google user diffed against a default
record produces no update. Pass -ExternalIds @() for an account with no personID link, or
-Emails to add alias addresses (the primary is always included).

.EXAMPLE
$googleUser = New-TestGoogleUser -suspended $true
#>
function New-TestGoogleUser {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [string]$primaryEmail = 'tuser@example.org',
        [string]$ID = 'g-tuser',
        [string]$GivenName = 'Test',
        [string]$FamilyName = 'User',
        [AllowNull()][string]$Department = 'Main',      # Google stores Building in organizations.department
        [AllowNull()][string]$Title = 'Teacher',
        [bool]$suspended = $false,
        [bool]$archived = $false,
        [string]$orgUnitPath = '/Staff',
        [AllowNull()][string]$ExternalIdValue = '10001',
        [AllowNull()][string[]]$AliasEmails = @(),
        [AllowNull()][string[]]$CurrentGroups = @()
    )

    $externalIds = @()
    if ($ExternalIdValue) {
        $externalIds = @([PSCustomObject]@{ type = 'organization'; value = $ExternalIdValue })
    }

    $emails = @([PSCustomObject]@{ address = $primaryEmail; primary = $true })
    foreach ($alias in $AliasEmails) {
        $emails += [PSCustomObject]@{ address = $alias }
    }

    [PSCustomObject]@{
        primaryEmail  = $primaryEmail
        ID            = $ID
        Name          = [PSCustomObject]@{ givenName = $GivenName; familyName = $FamilyName }
        organizations = @([PSCustomObject]@{ department = $Department; title = $Title })
        suspended     = $suspended
        archived      = $archived
        orgUnitPath   = $orgUnitPath
        externalIds   = $externalIds
        emails        = $emails
        CurrentGroups = $CurrentGroups
    }
}

Export-ModuleMember -Function Get-IDBridgeManifestPath, Import-IDBridgeForTest, New-TestSourceRecord, New-TestADUser, New-TestGoogleUser
