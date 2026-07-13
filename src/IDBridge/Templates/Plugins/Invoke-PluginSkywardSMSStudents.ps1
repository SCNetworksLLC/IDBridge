#Skyward SMS Student Plugin — IDBridge plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
A minimal starting point for pulling students from the Skyward SMS OneRoster API. Edit every
placeholder value (API URLs, domain, OUs, building map, grade settings) for your district
before enabling the plugin in IDBridgeConfig.psd1 — it throws until the API URL is set.
#>

<#
Secrets are stored in the IDBridge secret vault (encrypted files under <RootPath>\Vault). Add/change them with:

Set Passphrase API Key if in Use
Set-IDBridgeSecret -Name 'ApiKey-Passphrase'

Set Passphrase Nonce for students if in Use
Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStudent'

Set Skyward SMS API Key
Set-IDBridgeSecret -Name 'ApiKey-SkywardSMS'
#>


function Invoke-PluginSkywardSMSStudents {
    [CmdletBinding()]
    param ()
    $PersonTypeGeneric = "Students"

    #Generic Config
    $DomainName = "my.yourdistrict.org"
    $Company = "Your School District"

    #Student Specific Config
    $DaysLastSeen = 14  # Number of days since last seen to consider a user "orphaned" and eligible for deactivation
    $FSPINLength = 4     # Length of Food Service PINs; used for padding leading zeros if needed

    #AD Config
    $ADUserRootOU = "OU=YourDistrict,DC=yourdomain,DC=local"

    #Google Config
    $GoogleUserRootOU = "/YourDistrict"

    # SkywardSMS Config — URLs from your Skyward-hosted API endpoint
    $SkywardSMSConfig = @{
        BaseUrl         = "https://skyward.iscorp.com/APIyourdistrictSTU/v1"
        TokenUrl        = "https://skyward.iscorp.com/APIyourdistrictSTU/token"
        ClientId        = 'IDBridge'
        ExcludeEntityIDs = @()   # Skyward entity IDs to skip entirely, e.g. @('800')
        SafetyCheckCount        = 100   # Your expected student count — the run aborts if the API returns fewer than SafetyCheckPercentage% of this
        SafetyCheckPercentage   = 75
    }

    if ($SkywardSMSConfig.BaseUrl -like "*APIyourdistrict*") {
        Throw "Invoke-PluginSkywardSMSStudents: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    # SkywardSMS client secret - always required for the OneRoster API call
    try { $skywardClientSecret = Get-IDBridgeSecret -Name 'ApiKey-SkywardSMS' }
    catch { Throw "Error retrieving the Skyward SMS client secret from the vault: $($_)" }
    $SkywardSMSConfig.ClientSecret = $skywardClientSecret


    # Map your Skyward SchoolIDs to friendly names and short codes ('000' is the fallback)
    $BuildingIDMapping = @{
        '100' = @{ Name = 'Sample Elementary'; Code = 'SE' }
        '400' = @{ Name = 'High School'; Code = 'HS' }
        '000' = @{ Name = 'Your School District';  Code = 'YSD' }  # fallback
    }

    ############
    # Per-grade settings — add/remove grades as needed
    # Password Type Must be API-PASSPHRASE, WORD, RANDOM, FSPIN
    # Define defaults once
    $GradeDefaultSettings = @{
        Provision = $true
        AD = @{
            Provision = $true
            passPrefix = 'Temp'
            ChangePasswordAtLogon = $false
            PasswordType = 'RANDOM'
        }
        Google = @{
            Provision = $true
            passPrefix = 'Temp'
            ChangePasswordAtLogon = $false
            PasswordType = 'RANDOM'
        }
    }

    # Only define grades that differ from defaults
    $GradeOverrides = @{
        'GD' = @{
            Provision = $false
            AD = @{ Provision = $false }
            Google = @{ Provision = $false }
        }
        # Example: younger grades Google-only
        # 'KG' = @{ AD = @{ Provision = $false } }
        # Example: if 9-12 used passphrases instead
        # '09' = @{ AD = @{ PasswordType = 'API-PASSPHRASE' }; Google = @{ PasswordType = 'API-PASSPHRASE' } }
    }

    # All valid grades
    $ValidGrades = @('PK','K4','KG','01','02','03','04','05','06','07','08','09','10','11','12','GD')

    # Build the merged settings
    $GradeSettings = @{}
    foreach ($grade in $ValidGrades) {
        $merged = @{
            Provision = $GradeDefaultSettings.Provision
            AD      = $GradeDefaultSettings.AD.Clone()
            Google  = $GradeDefaultSettings.Google.Clone()
        }

        if ($GradeOverrides.ContainsKey($grade)) {
            $override = $GradeOverrides[$grade]

            if ($override.ContainsKey('Provision')) { $merged.Provision = $override.Provision }

            foreach ($key in @('AD','Google')) {
                if ($override.ContainsKey($key)) {
                    foreach ($prop in $override[$key].Keys) {
                        $merged[$key][$prop] = $override[$key][$prop]
                    }
                }
            }
        }

        $GradeSettings[$grade] = $merged
    }
    ############

    #Passphrase API Configuration - only fetch the secrets when a grade actually uses the passphrase API
    $usePassphraseAPI = [bool]($GradeSettings.Values | Where-Object { $_.AD.PasswordType -eq 'API-PASSPHRASE' -or $_.Google.PasswordType -eq 'API-PASSPHRASE' })
    $PassphraseAPI = @{
        Nonce = if ($usePassphraseAPI) { Get-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStudent' } #Shared secret nonce
        Mode = "WORDS" #Must be WORDS or VERBNOUN
        WordCount = 3 #How many words the passphrase will have.  Only applies to WORDS mode
        AuthToken = if ($usePassphraseAPI) { Get-IDBridgeSecret -Name 'ApiKey-Passphrase' } #API Auth token in SecureString Format
    }



    try {
        $params = @{
            BaseUrl                 = $SkywardSMSConfig.BaseUrl
            TokenUrl                = $SkywardSMSConfig.TokenUrl
            ClientId                = $SkywardSMSConfig.ClientId
            ClientSecret            = $(ConvertFrom-SecureString $SkywardSMSConfig.ClientSecret -AsPlainText)
            ExcludeEntityIDs        = $SkywardSMSConfig.ExcludeEntityIDs
            SafetyCheckCount        = $SkywardSMSConfig.SafetyCheckCount
            SafetyCheckPercentage   = $SkywardSMSConfig.SafetyCheckPercentage
        }

        $data = Get-SourceDataSkywardSMS @params
    }
    catch { Throw "Error retrieving data from SkywardSMS: $($_)" }


    #Food-service PINs are only needed when a grade uses the FSPIN password type. Uncomment the
    #filter to exclude students without a PIN (they'd otherwise get no FSPIN password source):
    #$filteredData = $data | Where-Object {$_.FoodServiceKeyPadNumber -gt 0}
    $filteredData = $data

    #Set FoodServicePin to string to preserve leading zeros
    foreach ($item in ($filteredData | Where-Object {$_.FoodServiceKeyPadNumber})) {
        $item.FoodServiceKeyPadNumber = $item.FoodServiceKeyPadNumber.ToString().PadLeft($FSPINLength, '0')
    }


    $dataNormalized = foreach ($item in $filteredData) {
        $Grade = $null
        $Grade = $item.GradeLevel

        $building = $null
        $building = if ($BuildingIDMapping.$($item.SchoolID).Name) {
            $BuildingIDMapping.$($item.SchoolID).Name} else {$BuildingIDMapping."000".Name
        }

        # --- IsActive Property ---
        $isActive = $null
        #Check LastSeen Date against threshold for orphaned accounts
        if ($item.LastSeen -ge (Get-Date).AddDays(-$($DaysLastSeen))) {
            $isActive = $true
        } else {
            $isActive = $false
        }

        #Check if Grade is in configuration and enabled
        if (-not $GradeSettings.$($Grade)) {
            $isActive = $false
            Write-Log -Message ("Student: Grade " + $Grade + " not found in configuration file for PersonID: " + $item.DisplayID + ". Disabling user from processing.") -Level Trace
            Continue
        }

        if ($isActive -eq $true) {
            $isActive = $GradeSettings.$($Grade).Provision
        }



        #Groups
        # Determine automatic groups based on the student's building and grade
        # The optional Get-CustomStudentGroups helper (bottom of this file) encodes your
        # district's group policy.
        $groupsAutomatic = $null
        $groupsAutomatic = if (Test-Path Function:\Get-CustomStudentGroups) {
            Get-CustomStudentGroups -building $building -grade $Grade
        }

        #Proposed Groups
        $proposedGroupList = @()
        if ($groupsAutomatic) {$proposedGroupList += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {$proposedGroupList += ($item.ApplicationGroups -split ",").trim()}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupList += ($item.EmailGroups -split ",").trim()}




        #AD Key Setup
        $keyAD = $null
        if ($gradeSettings.$($grade).AD.PasswordType -eq "FSPIN") {
            if ($item.FoodServiceKeyPadNumber) {
                $keyAD = "$($gradeSettings.$($grade).AD.passPrefix)$($item.FoodServiceKeyPadNumber)"
            }
        } elseif ($gradeSettings.$($grade).AD.PasswordType -eq "Word") {
            if ($item.Word) {
                $keyAD = "$($gradeSettings.$($grade).AD.passPrefix)$($item.Word)"
            }
        } else {
            $keyAD = "$((New-Guid).Guid)"
        }


        #Key Setup Google
        $keyGoogle = $null
        if ($gradeSettings.$($grade).Google.PasswordType -eq "FSPIN") {
            if ($item.FoodServiceKeyPadNumber) {
                $keyGoogle = "$($gradeSettings.$($grade).Google.passPrefix)$($item.FoodServiceKeyPadNumber)"
            }
        } elseif ($gradeSettings.$($grade).Google.PasswordType -eq "Word") {
            if ($item.Word) {
                $keyGoogle = "$($gradeSettings.$($grade).Google.passPrefix)$($item.Word)"
            }
        } else {
            $keyGoogle = "$((New-Guid).Guid)"
        }



        # --- Build the standardized source record via the module factory ---
        $recordFields = @{
            PersonID       = $item.DisplayId
            NameFirst      = Format-IDBridgeName $item.FirstName
            NameLast       = Format-IDBridgeName $item.LastName
            Username       = $item.DisplayId
            Building       = $building
            JobTitle       = "Student - Grade $($Grade)"
            Company        = $Company
            Department     = "Grade-$($Grade)"
            UPN            = "$($item.DisplayId)@$($DomainName)"
            PersonTypeID   = "1"
            InternalID     = $item.NameId
            IDBActive      = $isActive
            GroupsProposed = ($proposedGroupList | Select-Object -Unique)
            PersonType     = "Student - Grade $($Grade)"

            ProvisionAD               = [bool]$GradeSettings.$($Grade).AD.Provision
            ADOrganizationalUnit      = "OU=Grade-$($Grade),OU=$($PersonTypeGeneric),$($ADUserRootOU)"
            ADOrganizationalUnitTrash = "OU=$(Get-Date -Format yyyy),OU=$($PersonTypeGeneric),OU=Trash,$($ADUserRootOU)"
            ADChangePasswordAtLogon   = $GradeSettings.$($Grade).AD.ChangePasswordAtLogon
            ADPassphraseAPI           = if ($gradeSettings.$($grade).AD.PasswordType -eq "API-PASSPHRASE") { $PassphraseAPI } else { $null }
            ADKey                     = if ($keyAD) { ConvertTo-SecureString -String $keyAD -AsPlainText -Force } else { $null }

            ProvisionGoogle           = [bool]$GradeSettings.$($Grade).Google.Provision
            GoogleOrganizationalUnit      = "$($GoogleUserRootOU)/$($PersonTypeGeneric)/Grade-$($Grade)"
            GoogleOrganizationalUnitTrash = "/Trash/$($PersonTypeGeneric)/$(Get-Date -Format yyyy)"
            GoogleChangePasswordAtLogon   = $GradeSettings.$($Grade).Google.ChangePasswordAtLogon
            GooglePassphraseAPI           = if ($gradeSettings.$($grade).Google.PasswordType -eq "API-PASSPHRASE") { $PassphraseAPI } else { $null }
            GoogleKey                     = if ($keyGoogle) { ConvertTo-SecureString -String $keyGoogle -AsPlainText -Force } else { $null }
        }

        try {
            New-IDBridgeSourceRecord @recordFields
        } catch {
            Throw "Error creating source record for PersonID: $($item.DisplayId) - $($item.FirstName) $($item.LastName) $($_)"
        }

    }

    return $dataNormalized
}




<#
Sample Data Returned by Get-SourceDataSkywardSMS (fabricated example)

SchoolIds               : {400}
StateIds                : @{WISE ID=0000000000}
NameId                  : 12345
FirstName               : SAMPLE
MiddleName              :
LastName                : STUDENT
DateOfBirth             : 1/1/2010 12:00:00 AM
GradYr                  : 2028
DisplayNameFML          : SAMPLE STUDENT
DisplayNameLFM          : STUDENT SAMPLE
Username                : 200001
NameKey                 : STUDENT SAM000
SchoolEmail             : 200001@my.yourdistrict.org
HomeEmail               :
Gender                  :
GradeLevel              : 10
DisplayId               : 200001
DefaultSchoolId         : 400
StudentPathCode         :
StateId                 : 0000000000
FederalRace             :
HispanicLatinoEthnicity : False
FullFirstName           :
FullMiddleName          :
FullLastName            :
FoodServiceKeyPadNumber : 1234
OtherName               :
SchoolName              : SAMPLE HIGH SCHOOL
SchoolID                : 400
LastSeen                : 2026-04-22 22:07:21
#>


function Get-CustomStudentGroups() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $building,
        [parameter(Mandatory=$true)]
        $grade
    )

    # OPTIONAL helper — encode your district's student group policy here (or delete the
    # function; the plugin only calls it when it exists).

    #Initialize Group Variable
    $groups = @()

    #Building Short Name for Groups — buildings in this map get a "<code>_Students" group
    $buildingShortName = @{
        "Sample Elementary" = "SE"
        "High School" = "HS"
    }

    #All Students
    ######------------######
    $groups += ("Students")
    ######------------######

    #All Building Students (ex. "HS_Students")
    ######------------######
    if ($buildingShortName.$building) {
        $groups += ($buildingShortName.$building + "_Students")
    }
    ######------------######

    #Grade Level Groups
    ######------------######
    $groups += ("Grade-" + $grade)
    ######------------######

    return $groups
}
