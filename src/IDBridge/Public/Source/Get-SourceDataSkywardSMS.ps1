<#
.SYNOPSIS
    Retrieves student data from Skyward SMS 2.0 via the OneRoster API.

.DESCRIPTION
    This function authenticates with Skyward using client credentials,
    retrieves all students via the OneRoster API,
    and returns a flattened PSCustomObject for each student containing key properties.

.PARAMETER BaseUrl
    The base URL for the OneRoster API (used to build the /users endpoint).

.PARAMETER TokenUrl
    The URL endpoint to request the OAuth access token.

.PARAMETER ClientId
    The client ID for OAuth authentication.

.PARAMETER ClientSecret
    The client secret for OAuth authentication.

.PARAMETER ExcludeEntityIDs
    The Entity ID(s) to exclude (used to filter results). Pass an array for multiple,
    e.g. @('800','801').

.PARAMETER SafetyCheckCount
    The expected baseline student count used for the safety-floor calculation.

.PARAMETER SafetyCheckPercentage
    The percentage of SafetyCheckCount that must be met for the run to proceed; the run aborts
    (throws) below this floor to prevent mass changes from a truncated source pull.

.EXAMPLE
    $params = @{
        BaseUrl      = "https://skyward.iscorp.com/APIyourdistrictSTU/v1"
        TokenUrl     = "https://skyward.iscorp.com/APIyourdistrictSTU/token"
        ClientId     = "IDBridge"
        ClientSecret = "your_secret"   # <-- Replace with your real secret
        ExcludeEntityIDs = @("your_census_entity_id")   # <-- Replace with your real census entity ID and any other Entity IDs to exclude
    }

    $students = Get-SourceDataSkywardSMS @params

    Retrieves all students from Skyward and stores them in $students.

.NOTES
    Author: Sam Cattanach
    Date: 2025-10-12
    Version: 1.0

    Version History:
    1.0 - Initial release
#>
function Get-SourceDataSkywardSMS {
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

        [Parameter(Mandatory = $true)]
        $ExcludeEntityIDs,

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckCount,

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckPercentage
    )

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    #Normalize ExcludeEntityIDs to an array so -notin filters work (a comma-separated string is split)
    $ExcludeEntityIDs = @($ExcludeEntityIDs -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Prepare OAuth token request
    $tokenBody = @{
        grant_type    = "client_credentials"  # OAuth2 client credentials grant
        client_id     = $ClientId             # Client ID for authentication
        client_secret = $ClientSecret         # Client secret for authentication
    }

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUrl -Body $tokenBody -ErrorAction Stop
        $accessToken   = $tokenResponse.access_token

        Write-Log -Message "Access token for Skyward SMS retrieved successfully" -Level Trace
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
        $responseSchools = Invoke-RestMethod -Method Get -Uri $urlSchools -Headers $headers -ErrorAction Stop
    }
    catch {
        Write-Log -Message "School data request failed: $_" -Level Error
        return @()  # Return empty array on failure
    }

    # Output total number of users retrieved
    Write-Log -Message "Total schools retrieved: $($responseSchools.Count)" -Level Trace

    # Remove ExcludeEntityIDs schools from list
    $responseSchools = $responseSchools | Where-Object { $_.SchoolId -notin $ExcludeEntityIDs }

    # Build hash map for quick lookup by sourcedId
    $schoolLookup = @{}
    foreach ($item in $responseSchools) {
        $schoolLookup[$item.SchoolID] = $item.SchoolName
    }

    # Initialize array to store all users and paging variables
    $students = @()
    $limit = 10000   # Number of users to request per API call

    Write-Log -Message "Beginning user student retrieval" -Level Trace

    # Loop through API paging to retrieve all users
    # Using Schools endpoint to get students by school to remove ExcludeEntityIDs schools

    foreach ($school in $responseSchools) {
        $offset = 0    # Starting offset for paging
        do {
            try {
                $url = "$BaseUrl/schools/$($school.SchoolID)/students?limit=$limit&offset=$offset"

                Write-Log -Message "Requesting users from $url" -Level Trace

                $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

                if ($null -ne $response) {
                    # Add retrieved users to collection
                    $students += $response
                    # Increment offset by number of users returned
                    $offset += $response.Count

                    Write-Log -Message ("Retrieved $($response.Count) users for school $($school.SchoolId); total so far: $($students.Count)") -Level Trace
                } else {
                    break
                }
            }
            catch {
                Write-Log -Message ("User data request failed: $_") -Level Error
                return @()  # Return empty array on failure
            }
        } while ($response.Count -eq $limit)
    }

    #Filter for unique users based on NameID
    $students = $students | Sort-Object -Property NameID -Unique



    #Add school names to student objects
    foreach ($item in $students) {
        #Set School Name with ExcludeEntityIDs check
        $schoolIDTemp = $null
        if ($schoolLookup[$item.DefaultSchoolId]) {
            $item | Add-Member -MemberType NoteProperty -Name SchoolName -Value $($schoolLookup[$item.DefaultSchoolId]) -Force
            $item | Add-Member -MemberType NoteProperty -Name SchoolID -Value $($item.DefaultSchoolId) -Force
        } else {
            $schoolIDTemp = $item.SchoolIds | Where-Object {$_ -notin $ExcludeEntityIDs} | Select-Object -First 1
            $item | Add-Member -MemberType NoteProperty -Name SchoolName -Value $($schoolLookup[$schoolIDTemp]) -Force
            $item | Add-Member -MemberType NoteProperty -Name SchoolID -Value $($schoolIDTemp) -Force
        }
    }

    #Add LastSeen Property
    $lastSeenDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    foreach ($item in $students) {
        $item | Add-Member -MemberType NoteProperty -Name 'LastSeen' -Value $lastSeenDate -Force
    }

    #Make Sure Data Returned is over the safety check count
    if ($students.Count -lt ([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100))) {
        Throw "Skyward SMS: Retrieved user count: $($students.Count) is below the safety check count: $([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100)). Aborting processing to prevent potential data loss."
    }

    Write-Log -Message "Finished fetching all students from Skyward SMS: $($students.Count)"




    #region User State
    #Import previous user state file
    if (Test-Path "$($IDconfig.Paths.DataRoot)\SkywardSMS_Students_User_State.csv") {
        $userState = Import-Csv -Path "$($IDconfig.Paths.DataRoot)\SkywardSMS_Students_User_State.csv"

        #Convert LastSeen to DateTime
        $userState = $userState | ForEach-Object { $_.LastSeen = [datetime]$_.LastSeen; $_ }
    }

    if ($userState) {
        Write-Log -Message "Imported previous student user state with $($userState.Count) records" -Level Trace

        #Combine current and previous user state to get latest LastSeen
        $lookup = @{}

        foreach ($item in ($students + $userState)) {
            if (-not $lookup.ContainsKey($item.NameID.ToString()) -or [datetime]$item.LastSeen -gt [datetime]$lookup[$item.NameID.ToString()].LastSeen) {
                $lookup[$item.NameID.ToString()] = $item
            }
        }

        #Export updated user state
        Write-Log -Message "User state comparison completed, merged to $($lookup.Count) unique records" -Level Trace
        Write-Log -Message "Exporting updated student user state" -Level Trace

        $lookup.Values | Export-Csv -Path "$($IDconfig.Paths.DataRoot)\SkywardSMS_Students_User_State.csv" -NoTypeInformation -Force
    } else {
        Write-Log -Message "No previous student user state file found, skipping user state comparison" -Level Trace
        Write-Log -Message "Exporting current student user state with $($students.Count) records" -Level Trace

        if (-not (Test-Path "$($IDconfig.Paths.DataRoot)")) {
            New-Item -Path "$($IDconfig.Paths.DataRoot)" -ItemType Directory -Force | Out-Null
        }
        
        $students | Export-Csv -Path "$($IDconfig.Paths.DataRoot)\SkywardSMS_Students_User_State.csv" -NoTypeInformation -Force
    }
    #endregion User State



    # Return the collection of student objects
    if ($UserState) {
        return $lookup.Values
    } else {
        return $students
    }
}