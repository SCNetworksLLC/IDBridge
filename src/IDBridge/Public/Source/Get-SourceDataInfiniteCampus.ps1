<#
.SYNOPSIS
    Retrieves student data from Infinite Campus via the OneRoster API.

.DESCRIPTION
    This function authenticates with Infinite Campus using client credentials,
    retrieves all students via the OneRoster API,
    and returns a flattened PSCustomObject for each student containing key properties.
    Each record is stamped with a LastSeen timestamp and merged with the prior-run
    state file in DataRoot so students missing from the current pull age out
    gracefully instead of disappearing immediately.

.PARAMETER ClientId
    The client ID for OAuth authentication.

.PARAMETER ClientSecret
    The client secret for OAuth authentication.

.PARAMETER TokenUrl
    The URL endpoint to request the OAuth access token.

.PARAMETER BaseUrl
    The base URL for the OneRoster rostering API (used to build the /schools and
    /students endpoints), e.g. ...\/oneroster/rostering/v1p2

.PARAMETER ExcludeSchoolIdentifiers
    Optional school identifier(s) to exclude (matched against the school's OneRoster
    identifier, the school number). Students whose primary school is excluded are
    dropped. Pass an array for multiple, e.g. @('0210','0220').

.PARAMETER SafetyCheckCount
    The expected baseline student count used for the safety-floor calculation.

.PARAMETER SafetyCheckPercentage
    The percentage of SafetyCheckCount that must be met for the run to proceed; the run aborts
    (throws) below this floor to prevent mass changes from a truncated source pull.

.EXAMPLE
    $paramsStudent = @{
        BaseUrl                 = "https://sampleschoolwi.infinitecampus.org/campus/api/oneroster/v1p2/sample/ims/oneroster/rostering/v1p2"
        TokenUrl                = "https://sampleschoolwi.infinitecampus.org/campus/oauth2/token?appName=sample"
        ClientId                = "your-client-id"
        ClientSecret            = "your-client-secret"
        SafetyCheckCount        = 900
        SafetyCheckPercentage   = 75
    }

    $students = Get-SourceDataInfiniteCampus @paramsStudent

    Retrieves all students from Infinite Campus and stores them in $students.

.NOTES
    Author: Sam Cattanach
    Date: 2025-10-12
    Version: 1.1

    Version History:
    1.0 - Initial release
    1.1 - Added safety-floor check, LastSeen user-state tracking, and school exclusion
#>
function Get-SourceDataInfiniteCampus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]$TokenUrl,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $false)]
        $ExcludeSchoolIdentifiers = @(),

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckCount,

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckPercentage
    )

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    #Normalize ExcludeSchoolIdentifiers to an array so -notin filters work (a comma-separated string is split)
    $ExcludeSchoolIdentifiers = @($ExcludeSchoolIdentifiers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Prepare OAuth token request
    $tokenBody = @{
        grant_type    = "client_credentials"  # OAuth2 client credentials grant
        client_id     = $ClientId             # Client ID for authentication
        client_secret = $ClientSecret         # Client secret for authentication
    }

    try {
        Write-Log "Requesting access token from $TokenUrl" -Level Trace
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUrl -Body $tokenBody -ErrorAction Stop
        $accessToken   = $tokenResponse.access_token
        Write-Log -Message "Access token for Infinite Campus retrieved successfully" -Level Trace
    }
    catch {
        Write-Log -Message "Access token request failed: $_" -Level Error
        return @()  # Return empty array on failure
    }


    # Prepare headers for OneRoster API request
    $headers = @{
        "Authorization" = "Bearer $accessToken"  # Bearer token for authentication
        "Accept"        = "application/json"    # Expect JSON response
    }

    #Get schools
    try {
        $urlSchools = "$baseUrl/schools"
        $responseSchools = Invoke-RestMethod -Method Get -Uri $urlSchools -Headers $headers  -ErrorAction Stop
    }
    catch {
        Write-Log -Message "School data request failed: $_" -Level Error
        return @()  # Return empty array on failure
    }

    # Output total number of schools retrieved
    Write-Log "Total schools retrieved: $($responseSchools.orgs.Count)" -Level Trace

    # Build hash map for quick lookup by sourcedId
    $schoolLookup = @{}
    foreach ($item in $responseSchools.orgs) {
        $schoolLookup[$item.sourcedId] = @{
            Name       = $item.name
            Identifier = $item.identifier
        }
    }

    # Initialize array to store all users and paging variables
    $students = @()
    $limit = 100   # Number of users to request per API call
    $offset = 0    # Starting offset for paging

    Write-Log "Starting student retrieval loop from $BaseUrl/students" -Level Trace
    # Loop through API paging to retrieve all users
    do {
        try {
            $url = "$BaseUrl/students?limit=$limit&offset=$offset"
            Write-Log "Requesting students from $url" -Level Trace
            $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

            if ($null -ne $response.users) {
                # Add retrieved users to collection
                $students += $response.users
                # Increment offset by number of users returned
                $offset += $response.users.Count
                Write-Log -Message ("Retrieved $($response.users.Count) students; total so far: $($students.Count)") -Level Trace
            } else {
                Write-Log "No more students returned; ending loop" -Level Trace
                break
            }
        }
        catch {
            Write-Log -Message ("Student data request failed: $_") -Level Error
            return @()  # Return empty array on failure
        }
    } while ($response.users.Count -eq $limit)

    # Output total number of users retrieved
    Write-Log -Message ("Total students retrieved: $($students.Count)")

    # Define the grade order from highest → lowest
    $gradeOrder = @("12","11","10","09","08","07","06","05","04","03","02","01","KG","K4","PK")

    # Transform each student into a flattened object
    $studentsFiltered = $students | ForEach-Object {

        # Find primary role (preferred) or first role if missing
        $roleInfo = $null
        if ($_.roles) {
            $roleInfo = $_.roles | Where-Object { $_.roleType -eq 'primary' } | Select-Object -First 1
            if (-not $roleInfo) {
                $roleInfo = $_.roles | Select-Object -First 1
            }
        }

        # Resolve org sourcedId → school
        $schoolId = $null
        $schoolName = $null
        $schoolIdentifier = $null

        if ($roleInfo.org -and $roleInfo.org.sourcedId) {
            $schoolId = $roleInfo.org.sourcedId
            if ($schoolLookup.ContainsKey($schoolId)) {
                $schoolName = $schoolLookup[$schoolId].Name
                $schoolIdentifier = $schoolLookup[$schoolId].Identifier
            }
        }

        # Get the highest grade for a student
        $highestGrade = $null
        if ($_.grades -and $_.grades.Count -gt 0) {
            # Sort by custom order and take the first one (highest)
            $highestGrade = $_.grades | Sort-Object {
                $gradeOrder.IndexOf($_)
            } | Select-Object -First 1
        }

        Write-Verbose "Processing student: $($_.sourcedId)"

        # Return PSCustomObject with selected student properties
        [PSCustomObject]@{
            SourcedId            = $_.sourcedId
            Status               = $_.status
            DateLastModified     = $_.dateLastModified
            LocalID              = $_.identifier
            InternalID           = $_.username
            ActiveUserAccount    = $_.enabledUser
            NameFirst            = $_.givenName
            NameLast             = $_.familyName
            Email                = $_.email
            Role                 = $roleInfo.role
            RoleType             = $roleInfo.roleType
            RoleBeginDate        = $roleInfo.beginDate
            RoleEndDate          = $roleInfo.endDate
            Grade                = $highestGrade
            SchoolName           = $schoolName
            SchoolIdentifier     = $schoolIdentifier
        }
    }

    # Remove students whose primary school is in ExcludeSchoolIdentifiers
    if ($ExcludeSchoolIdentifiers.Count -gt 0) {
        $studentsFiltered = @($studentsFiltered | Where-Object { $_.SchoolIdentifier -notin $ExcludeSchoolIdentifiers })
        Write-Log -Message "Students remaining after school exclusion: $($studentsFiltered.Count)" -Level Trace
    }

    #Add LastSeen Property
    $lastSeenDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    foreach ($item in $studentsFiltered) {
        $item | Add-Member -MemberType NoteProperty -Name 'LastSeen' -Value $lastSeenDate -Force
    }

    #Make Sure Data Returned is over the safety check count
    if ($studentsFiltered.Count -lt ([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100))) {
        Throw "Infinite Campus: Retrieved user count: $($studentsFiltered.Count) is below the safety check count: $([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100)). Aborting processing to prevent potential data loss."
    }

    Write-Log -Message "Finished fetching all students from Infinite Campus: $($studentsFiltered.Count)"




    #region User State
    #Import previous user state file
    if (Test-Path "$($IDconfig.Paths.DataRoot)\InfiniteCampus_Students_User_State.csv") {
        $userState = Import-Csv -Path "$($IDconfig.Paths.DataRoot)\InfiniteCampus_Students_User_State.csv"

        #Convert LastSeen to DateTime
        $userState = $userState | ForEach-Object { $_.LastSeen = [datetime]$_.LastSeen; $_ }
    }

    if ($userState) {
        Write-Log -Message "Imported previous student user state with $($userState.Count) records" -Level Trace

        #Combine current and previous user state to get latest LastSeen
        $lookup = @{}

        foreach ($item in ($studentsFiltered + $userState)) {
            if (-not $lookup.ContainsKey($item.SourcedId) -or [datetime]$item.LastSeen -gt [datetime]$lookup[$item.SourcedId].LastSeen) {
                $lookup[$item.SourcedId] = $item
            }
        }

        #Export updated user state
        Write-Log -Message "User state comparison completed, merged to $($lookup.Count) unique records" -Level Trace
        Write-Log -Message "Exporting updated student user state" -Level Trace

        $lookup.Values | Export-Csv -Path "$($IDconfig.Paths.DataRoot)\InfiniteCampus_Students_User_State.csv" -NoTypeInformation -Force
    } else {
        Write-Log -Message "No previous student user state file found, skipping user state comparison" -Level Trace
        Write-Log -Message "Exporting current student user state with $($studentsFiltered.Count) records" -Level Trace

        if (-not (Test-Path "$($IDconfig.Paths.DataRoot)")) {
            New-Item -Path "$($IDconfig.Paths.DataRoot)" -ItemType Directory -Force | Out-Null
        }

        $studentsFiltered | Export-Csv -Path "$($IDconfig.Paths.DataRoot)\InfiniteCampus_Students_User_State.csv" -NoTypeInformation -Force
    }
    #endregion User State



    # Return the collection of student objects
    if ($UserState) {
        return $lookup.Values
    } else {
        return $studentsFiltered
    }
}
