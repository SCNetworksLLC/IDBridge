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
    The Entity ID to Exclude (used to filter results). Comman Separated if multiple.

.PARAMETER logFile
    A PSObject representing the log file to use for logging events or errors (currently unused).

.EXAMPLE
    $params = @{
        BaseUrl      = "https://skyward.iscorp.com/APImarshfieldwiSTU/v1"
        TokenUrl     = "https://skyward.iscorp.com/APImarshfieldwiSTU/token"
        ClientId     = "IDBridge"
        ClientSecret = "your_secret"   # <-- Replace with your real secret
        ExcludeEntityIDs = "your_census_entity_id"   # <-- Replace with your real census entity ID and other Entity IDs to exclude, comma-separated
        logFile      = $logFile
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
        [string]$ExcludeEntityIDs,

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckCount,

        [Parameter(Mandatory = $true)]
        [int]$SafetyCheckPercentage,

        [Parameter(Mandatory = $true)]
        [PSObject]$logFile,

        $VerboseLogging = $false
    )

    # Prepare OAuth token request
    $tokenBody = @{
        grant_type    = "client_credentials"  # OAuth2 client credentials grant
        client_id     = $ClientId             # Client ID for authentication
        client_secret = $ClientSecret         # Client secret for authentication
    }

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUrl -Body $tokenBody -ErrorAction Stop
        $accessToken   = $tokenResponse.access_token
        if ($VerboseLogging) {
            Write-Log -Path $logFile -Message "Access token for Skyward SMS retrieved successfully"
        }
    }
    catch {
        Write-Log -Path $logFile -Message "Access token request failed: $_" -Level Error
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
        Write-Log -Path $logFile -Message "School data request failed: $_" -Level Error
        return @()  # Return empty array on failure
    }

    # Output total number of users retrieved
    if ($VerboseLogging) {
        Write-Log -Path $logFile -Message "Total schools retrieved: $($responseSchools.Count)"
    }

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

    if ($VerboseLogging) {
        Write-Log -Path $logFile -Message "Beginning user student retrieval"
    }

    # Loop through API paging to retrieve all users
    # Using Schools endpoint to get students by school to remove ExcludeEntityIDs schools

    foreach ($school in $responseSchools) {
        $offset = 0    # Starting offset for paging
        do {
            try {
                $url = "$BaseUrl/schools/$($school.SchoolID)/students?limit=$limit&offset=$offset"

                if ($VerboseLogging) {
                    Write-Log -Path $logFile -Message "Requesting users from $url"
                }

                $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

                if ($null -ne $response) {
                    # Add retrieved users to collection
                    $students += $response
                    # Increment offset by number of users returned
                    $offset += $response.Count

                    if ($VerboseLogging) {
                        Write-Log -Path $logFile -Message ("Retrieved $($response.Count) users for school $($school.SchoolId); total so far: $($students.Count)")
                    }
                } else {
                    break
                }
            }
            catch {
                Write-Log -Path $logFile -Message ("User data request failed: $_") -Level Error
                return @()  # Return empty array on failure
            }
        } while ($response.Count -eq $limit)
    }

    #Filter for unique users based on NameID
    $students = $students | Sort-Object -Property NameID -Unique

    # Output total number of users retrieved
    if ($VerboseLogging) {
        Write-Log -Path $logFile -Message ("Total users retrieved before filtering: $($students.Count)")
    }

    #Filter out students with FoodServiceKeyPadNumber greater than 0
    if ($VerboseLogging) {
        $studentsWithFoodService = $students | Where-Object {$_.FoodServiceKeyPadNumber -eq 0}
        foreach ($item in $studentsWithFoodService) {
            Write-Log -Path $logFile -Message "Excluding Student without Food Service Key Pad Number: $($item.DisplayId) - $($item.FirstName) $($item.LastName)"
        }
    }

    $students = $students | Where-Object {$_.FoodServiceKeyPadNumber -gt 0}

    #Set FoodServicePin to string to preserve leading zeros
    $maxLength = ($students | ForEach-Object { $_.FoodServiceKeyPadNumber.ToString().Length } | Measure-Object -Maximum).Maximum

    foreach ($item in $students) {
        $item.FoodServiceKeyPadNumber = $item.FoodServiceKeyPadNumber.ToString().PadLeft($maxLength, '0')
    }

    #Add school names to student objects
    foreach ($item in $students) {
        #Set School Name with ExcludeEntityIDs check
        $schoolIDTemp = $null
        if ($schoolLookup[$item.DefaultSchoolId]) {
            $item | Add-Member -MemberType NoteProperty -Name SchoolName -Value $($schoolLookup[$item.DefaultSchoolId]) -Force
        } else {
            $schoolIDTemp = $item.SchoolIds | Where-Object {$_ -notin $ExcludeEntityIDs} | Select-Object -First 1
            $item | Add-Member -MemberType NoteProperty -Name SchoolName -Value $($schoolLookup[$schoolIDTemp]) -Force
        }
    }

    #Add IDBActive Property and set to false by default
    foreach ($item in $students) {
        $item | Add-Member -MemberType NoteProperty -Name 'IDBActive' -Value $false -Force
    }

    #Make Sure Data Returned is over the safety check count
    if ($students.Count -lt ([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100))) {
        Throw "Skyward SMS: Retrieved user count: $($students.Count) is below the safety check count: $([int]$SafetyCheckCount * ([int]$SafetyCheckPercentage / 100)). Aborting processing to prevent potential data loss."
    }

    Write-Log -Path $logFile -Message "Finished fetching all students from Skyward SMS: $($students.Count)"

    # Return the collection of student objects
    return $students
}