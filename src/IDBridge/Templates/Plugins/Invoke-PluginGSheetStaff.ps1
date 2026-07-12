#Spreadsheet Data Staff — IDBridge plugin template
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by New-IDBridgeConfig.
Every placeholder value below must be edited for your district before enabling the plugin
in IDBridgeConfig.psd1 — the plugin throws until the spreadsheet ID is set.

Pairs with the published source-sheet template (see docs/getting-started.md); share the
spreadsheet with the service-account email (Get-IDBridgeGoogleServiceAccountEmail).
#>


<#
Secrets are stored in the IDBridge secret vault (encrypted files under <RootPath>\Vault). Add/change them with:

Set Passphrase API Key if in Use
Set-IDBridgeSecret -Name 'ApiKey-Passphrase'

Set Passphrase Nonce for staff if in Use
Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStaff'
#>


function Invoke-PluginGSheetStaff {
    [CmdletBinding()]
    param ()
    $PersonTypeGeneric = "Staff"

    $GoogleSheetConfig = @{
        SheetID        = "YOUR-SPREADSHEET-ID"   # From the sheet URL: docs.google.com/spreadsheets/d/<this part>/edit
        SheetRange     = 'Staff'
        SafetyCheckCount = 100                   # Your expected staff row count — the run aborts if the sheet returns fewer than SafetyCheckPercentage% of this
        SafetyCheckPercentage = 75
    }

    if ($GoogleSheetConfig.SheetID -eq "YOUR-SPREADSHEET-ID") {
        Throw "Invoke-PluginGSheetStaff: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    #Generic Config
    $DomainName = "yourdistrict.org"
    $Company = "Your School District"

    #AD Config
    $ADProvision = $true
    $ADUserRootOU = "OU=YourDistrict,DC=yourdomain,DC=local"
    $ADPassPrefix = 'Temp-'
    $ADChangePasswordAtLogon = $true
    $ADPasswordType = 'WORD' #Must be API-PASSPHRASE, WORD, RANDOM, FSPIN

    #Google Config
    $GoogleProvision = $true
    $GoogleUserRootOU = "/YourDistrict"
    $GooglePassPrefix = 'Temp-'
    $GoogleChangePasswordAtLogon = $false
    $GooglePasswordType = 'RANDOM' #Must be API-PASSPHRASE, WORD, RANDOM, FSPIN


    # Staff PersonTypes that should get PersonTypeID = "3" — adjust to your sheet's PersonType values
    $PersonTypeThree = @(
        'Administrator',
        'Teacher',
        'Principal',
        'Secretary',
        'Support Staff'
    )

    #Passphrase API Configuration - only fetch the secrets from the vault when a password type uses them
    $usePassphraseAPI = ($ADPasswordType -eq 'API-PASSPHRASE') -or ($GooglePasswordType -eq 'API-PASSPHRASE')
    $passphraseNonce     = $null
    $passphraseAuthToken = $null
    if ($usePassphraseAPI) {
        try {
            $passphraseNonce     = Get-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStaff'
            $passphraseAuthToken = Get-IDBridgeSecret -Name 'ApiKey-Passphrase'
        }
        catch { Throw "Error retrieving passphrase API secrets from the vault: $($_)" }
    }

    $PassphraseAPI = @{
        Nonce = $passphraseNonce #Shared secret nonce
        Mode = "WORDS" #Must be WORDS or VERBNOUN
        WordCount = 3 #How many words the passphrase will have.  Only applies to WORDS mode
        AuthToken = $passphraseAuthToken #API Auth token in SecureString Format
    }

    try {
        $params = @{
            sheetID                     = $GoogleSheetConfig.SheetID
            sheetRange                  = $GoogleSheetConfig.SheetRange
            userCount                   = $GoogleSheetConfig.SafetyCheckCount
            userCountSafetyPercentage   = $GoogleSheetConfig.SafetyCheckPercentage
        }

        $data = Get-SourceDataGSheet @params
    }
    catch { Throw "Error retrieving data from Google Sheet: $($_)" }


    $dataNormalized = foreach ($item in $data) {
        # --- IsActive Property ---
        if ($item.TerminationDate -and ([datetime]$item.TerminationDate -lt (Get-Date))) {
            $isActive = $false
        } else {
            $isActive = $true
        }


        # Groups
        # Determine automatic groups based on PersonType
        # The optional Get-CustomStaffGroups helper (bottom of this file) encodes your district's
        # group policy — dynamic group assignment based on the person's role and location.
        $groupsAutomatic = $null
        $groupsAutomatic = if (Test-Path Function:\Get-CustomStaffGroups) {
            Get-CustomStaffGroups -building $item.Building -personType $item.PersonType
        }

        #Proposed Groups
        $proposedGroupList = @()
        if ($groupsAutomatic) {$proposedGroupList += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {$proposedGroupList += ($item.ApplicationGroups -split ",").trim()}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupList += ($item.EmailGroups -split ",").trim()}



        #Key Setup AD
        $keyAD = $null
        if ($ADPasswordType -eq "Word") {
            if ($item.Word) {
                $keyAD = "$($ADPassPrefix)$($item.Word)"
            }
        } else {
            $keyAD = "$((New-Guid).Guid)"
        }

        #Key Setup Google
        $keyGoogle = $null
        if ($GooglePasswordType -eq "Word") {
            if ($item.Word) {
                $keyGoogle = "$($GooglePassPrefix)$($item.Word)"
            }
        } else {
            $keyGoogle = "$((New-Guid).Guid)"
        }




        # --- Build the standardized source record via the module factory ---
        $recordFields = @{
            PersonID       = $item.PersonID
            NameFirst      = $item.NameFirst
            NameLast       = $item.NameLast
            Username       = $item.Username
            Building       = $item.Building
            JobTitle       = $item.JobTitle
            Company        = $Company
            UPN            = "$($item.Username)@$($DomainName)"
            PersonTypeID   = if ($item.PersonType -in $PersonTypeThree) { "3" } else { "2" }
            IDBActive      = $isActive
            GroupsProposed = ($proposedGroupList | Select-Object -Unique)
            PersonType     = $item.PersonType

            ProvisionAD               = $ADProvision
            ADOrganizationalUnit      = "OU=$($item.PersonType),OU=$($PersonTypeGeneric),$($ADUserRootOU)"
            ADOrganizationalUnitTrash = "OU=$(Get-Date -Format yyyy),OU=$($PersonTypeGeneric),OU=Trash,$($ADUserRootOU)"
            ADChangePasswordAtLogon   = $ADChangePasswordAtLogon
            ADPassphraseAPI           = if ($ADPasswordType -eq "API-PASSPHRASE") { $PassphraseAPI } else { $null }
            ADKey                     = if ($keyAD) { ConvertTo-SecureString -String $keyAD -AsPlainText -Force } else { $null }

            ProvisionGoogle           = $GoogleProvision
            GoogleOrganizationalUnit      = "$($GoogleUserRootOU)/$($PersonTypeGeneric)/$($item.PersonType)"
            GoogleOrganizationalUnitTrash = "/Trash/$($PersonTypeGeneric)/$(Get-Date -Format yyyy)"
            GoogleChangePasswordAtLogon   = $GoogleChangePasswordAtLogon
            GooglePassphraseAPI           = if ($GooglePasswordType -eq "API-PASSPHRASE") { $PassphraseAPI } else { $null }
            GoogleKey                     = if ($keyGoogle) { ConvertTo-SecureString -String $keyGoogle -AsPlainText -Force } else { $null }
        }

        New-IDBridgeSourceRecord @recordFields
    }

    return $dataNormalized
}



<#
Sample Data Returned by Get-SourceDataGSheet:

PersonID          : 100001
NameFirst         : Jane
NameLast          : Doe
Username          : doej
Building          : Sample Elementary
PersonType        : Principal
JobTitle          : Principal
TerminationDate   :
ApplicationGroups : APP_HelpDesk_Submitter, APP_Door_Access
EmailGroups       :
Word              : trainer
Process           : TRUE
ForceDisable      : FALSE
GoogleOUOverride  : FALSE



PersonID          : 999999
NameFirst         : Test
NameLast          : Test
Username          : test123
Building          : District Wide
PersonType        : Administrator
JobTitle          : TEST TITLE
TerminationDate   : 12/21/2025
ApplicationGroups :
EmailGroups       : All Staff
Word              : poem
Process           : TRUE
ForceDisable      : FALSE
GoogleOUOverride  : FALSE


#>


function Get-CustomStaffGroups() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $building,
        [parameter(Mandatory=$true)]
        $personType
    )

    # OPTIONAL helper — encode your district's group policy here (or delete the function; the
    # plugin only calls it when it exists). A minimal starting point is below; build it out
    # with building/person-type allow- and deny-lists as your policy grows.

    #Initialize Group Variable
    $groups = @()

    #All Staff
    ######------------######
    $groups += ("All Staff")
    ######------------######

    #Building Staff (ex. "Sample Elementary Staff")
    ######------------######
    if ($building) {
        $groups += ($building + " Staff")
    }
    ######------------######

    #All Professional Staff
    ######------------######
    #personTypes to include
    $groupAllProfessionalPersonType = @(
        "Administrator"
        "Principal"
        "Teacher"
    )

    if ($personType -in $groupAllProfessionalPersonType) {
        $groups += ("All Professional Staff")
    }
    ######------------######

    return $groups
}
