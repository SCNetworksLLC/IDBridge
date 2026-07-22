#Infinite Campus Student Plugin — IDBridge plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
A minimal starting point for pulling students from the Infinite Campus OneRoster API. Edit every
placeholder value (API URLs, domain, OUs, building map, grade settings) for your district
before enabling the plugin in IDBridgeConfig.psd1 — it throws until the API URL is set.

The OneRoster connection is created in Infinite Campus under System Settings > Digital
Learning Applications ("Add Application" > browse for a generic OneRoster connection).
Use the OneRoster 1.2 rostering base URL and note that Infinite Campus does not expose
food-service PINs or password words via OneRoster, so the password types available here
are RANDOM and API-PASSPHRASE.
#>

<#
Secrets are stored in the IDBridge secret vault (encrypted files under <RootPath>\Vault). Add/change them with:

Set Passphrase API Key if in Use
Set-IDBridgeSecret -Name 'ApiKey-Passphrase'

Set Passphrase Nonce for students if in Use
Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStudent'

Set Infinite Campus OneRoster client secret
Set-IDBridgeSecret -Name 'ApiKey-InfiniteCampus'
#>


function Invoke-PluginInfiniteCampusStudents {
    [CmdletBinding()]
    param ()
    $PersonTypeGeneric = "Students"

    #Generic Config
    $DomainName = "my.yourdistrict.org"
    $Company = "Your School District"

    #Student Specific Config
    $DaysLastSeen = 14  # Number of days since last seen to consider a user "orphaned" and eligible for deactivation
    $DaysLastSeenGraduate = 90  # Grade-12 students who disappear (graduates) keep their accounts this long instead

    #AD Config
    $ADUserRootOU = "OU=YourDistrict,DC=yourdomain,DC=local"

    #Google Config
    $GoogleUserRootOU = "/YourDistrict"

    # InfiniteCampus Config — URLs from your district's Infinite Campus OneRoster connection
    $InfiniteCampusConfig = @{
        BaseUrl         = "https://yourdistrictwi.infinitecampus.org/campus/api/oneroster/v1p2/yourdistrict/ims/oneroster/rostering/v1p2"
        TokenUrl        = "https://yourdistrictwi.infinitecampus.org/campus/oauth2/token?appName=yourdistrict"
        ClientId        = 'your-client-id'
        ExcludeSchoolIdentifiers = @()   # School identifiers (school numbers) to skip entirely, e.g. @('0210')
        SafetyCheckCount        = 100   # Your expected student count — the run aborts if the API returns fewer than SafetyCheckPercentage% of this
        SafetyCheckPercentage   = 75
    }

    if ($InfiniteCampusConfig.BaseUrl -like "*yourdistrict*") {
        Throw "Invoke-PluginInfiniteCampusStudents: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    # Infinite Campus client secret - always required for the OneRoster API call
    try { $infiniteCampusClientSecret = Get-IDBridgeSecret -Name 'ApiKey-InfiniteCampus' }
    catch { Throw "Error retrieving the Infinite Campus client secret from the vault: $($_)" }
    $InfiniteCampusConfig.ClientSecret = $infiniteCampusClientSecret


    # Map your Infinite Campus school identifiers (school numbers) to friendly names and short codes ('000' is the fallback)
    $BuildingIDMapping = @{
        '0110' = @{ Name = 'Sample Elementary'; Code = 'SE' }
        '0410' = @{ Name = 'High School'; Code = 'HS' }
        '000' = @{ Name = 'Your School District';  Code = 'YSD' }  # fallback
    }

    ############
    # Per-grade settings — add/remove grades as needed
    # Password Type Must be API-PASSPHRASE or RANDOM (Infinite Campus OneRoster has no FSPIN/WORD source)
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
        # Vanished grade-12s are relabeled GD below and parked in the Grade-GD OU for the
        # rest of their $DaysLastSeenGraduate window. To deactivate them immediately
        # instead, disable GD provisioning:
        # 'GD' = @{
        #     Provision = $false
        #     AD = @{ Provision = $false }
        #     Google = @{ Provision = $false }
        # }
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
            BaseUrl                  = $InfiniteCampusConfig.BaseUrl
            TokenUrl                 = $InfiniteCampusConfig.TokenUrl
            ClientId                 = $InfiniteCampusConfig.ClientId
            ClientSecret             = $(ConvertFrom-SecureString $InfiniteCampusConfig.ClientSecret -AsPlainText)
            ExcludeSchoolIdentifiers = $InfiniteCampusConfig.ExcludeSchoolIdentifiers
            SafetyCheckCount         = $InfiniteCampusConfig.SafetyCheckCount
            SafetyCheckPercentage    = $InfiniteCampusConfig.SafetyCheckPercentage
        }

        $data = Get-SourceDataInfiniteCampus @params
    }
    catch { Throw "Error retrieving data from Infinite Campus: $($_)" }


    $dataNormalized = foreach ($item in $data) {
        #[string] coercion: a tobedeleted student comes back with no roles/grades, and a
        #$null would throw on the hashtable lookups below ('' falls through to the
        #grade-not-found skip / building fallback instead)
        $Grade = $null
        $Grade = [string]$item.Grade

        $building = $null
        $schoolID = [string]$item.SchoolIdentifier
        $building = if ($BuildingIDMapping.$($schoolID).Name) {
            $BuildingIDMapping.$($schoolID).Name} else {$BuildingIDMapping."000".Name
        }

        # --- IsActive Property ---
        $isActive = $null
        #Check LastSeen Date against threshold for orphaned accounts
        #Grade-12 students who disappear from the feed are (almost always) graduates — they get
        #the longer $DaysLastSeenGraduate window so accounts survive into the summer
        $daysLastSeenWindow = if ($Grade -eq '12') { $DaysLastSeenGraduate } else { $DaysLastSeen }
        if (([datetime]$item.LastSeen) -ge (Get-Date).AddDays(-$($daysLastSeenWindow))) {
            $isActive = $true
        } else {
            $isActive = $false
        }

        #A grade-12 past the normal window has graduated (or left) — relabel to GD so the
        #record lands in the Grade-GD OU/groups for the rest of the grace window
        if ($Grade -eq '12' -and ([datetime]$item.LastSeen) -lt (Get-Date).AddDays(-$($DaysLastSeen))) {
            $Grade = 'GD'
        }

        #Check the Infinite Campus status/account flags — a withdrawn or disabled student
        #should not wait out the DaysLastSeen window
        if ($item.Status -ne 'active') {
            $isActive = $false
        }
        if ("$($item.ActiveUserAccount)" -ne 'true') {
            $isActive = $false
        }
        #An enrollment end date in the past means the student has left
        if ($item.RoleEndDate -and ([datetime]$item.RoleEndDate) -lt (Get-Date).Date) {
            $isActive = $false
        }

        #Check if Grade is in configuration and enabled
        if (-not $GradeSettings.$($Grade)) {
            $isActive = $false
            Write-Log -Message ("Student: Grade " + $Grade + " not found in configuration file for PersonID: " + $item.LocalID + ". Disabling user from processing.") -Level Trace
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




        #AD Key Setup
        $keyAD = $null
        if ($gradeSettings.$($grade).AD.PasswordType -ne "API-PASSPHRASE") {
            $keyAD = "$((New-Guid).Guid)"
        }


        #Key Setup Google
        $keyGoogle = $null
        if ($gradeSettings.$($grade).Google.PasswordType -ne "API-PASSPHRASE") {
            $keyGoogle = "$((New-Guid).Guid)"
        }



        # --- Build the standardized source record via the module factory ---
        $recordFields = @{
            PersonID       = $item.LocalID
            NameFirst      = Format-IDBridgeName $item.NameFirst
            NameLast       = Format-IDBridgeName $item.NameLast
            Username       = $item.LocalID
            Building       = $building
            JobTitle       = "Student - Grade $($Grade)"
            Company        = $Company
            Department     = "Grade-$($Grade)"
            UPN            = "$($item.LocalID)@$($DomainName)"
            PersonTypeID   = "1"
            InternalID     = $item.InternalID
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
            Throw "Error creating source record for PersonID: $($item.LocalID) - $($item.NameFirst) $($item.NameLast) $($_)"
        }

    }

    return $dataNormalized
}




<#
Sample Data Returned by Get-SourceDataInfiniteCampus (fabricated example)

SourcedId         : FF7E5C0C-BA84-408A-AE42-FBAB90041547
Status            : active
DateLastModified  : 8/25/2025 8:35:00 PM
LocalID           : 200001
InternalID        : 10856
ActiveUserAccount : true
NameFirst         : SAMPLE
NameLast          : STUDENT
Email             : 200001@my.yourdistrict.org
Role              : student
RoleType          : primary
RoleBeginDate     : 2025-09-02
RoleEndDate       :
Grade             : 06
SchoolName        : SAMPLE MIDDLE SCHOOL
SchoolIdentifier  : 0210
LastSeen          : 2026-04-22 22:07:21
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
