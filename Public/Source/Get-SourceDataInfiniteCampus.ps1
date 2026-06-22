<#
.SYNOPSIS
    Retrieves student data from Infinite Campus via the OneRoster API.

.DESCRIPTION
    This function authenticates with Infinite Campus using client credentials,
    retrieves all students via the OneRoster API,
    and returns a flattened PSCustomObject for each student containing key properties.

.PARAMETER ClientId
    The client ID for OAuth authentication.

.PARAMETER ClientSecret
    The client secret for OAuth authentication.

.PARAMETER TokenUrl
    The URL endpoint to request the OAuth access token.

.PARAMETER BaseUrl
    The base URL for the OneRoster API (used to build the /users endpoint).

.EXAMPLE
    $paramsStudent = @{
        BaseUrl                 = "https://sampleschoolwi.infinitecampus.org/campus/api/oneroster/v1p2/sample/ims/oneroster/rostering/v1p2"
        TokenUrl                = "https://sampleschoolwi.infinitecampus.org/campus/oauth2/token?appName=sample"
        ClientId                = "your-client-id"
        ClientSecret            = "your-client-secret"
    }
    
    $students = Get-SourceDataInfiniteCampus @paramsStudent

    Retrieves all active primary students from Infinite Campus and stores them in $students.

.NOTES
    Author: Sam Cattanach
    Date: 2025-10-12
    Version: 1.0

    Version History:
    1.0 - Initial release
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
        [string]$BaseUrl
    )

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

    # Output total number of users retrieved
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

    Write-Log "Starting user retrieval loop from $BaseUrl/users" -Level Trace
    # Loop through API paging to retrieve all users
    do {
        try {
            $url = "$BaseUrl/students?limit=$limit&offset=$offset"
            Write-Log "Requesting users from $url" -Level Trace
            $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers

            if ($null -ne $response.users) {
                # Add retrieved users to collection
                $students += $response.users
                # Increment offset by number of users returned
                $offset += $response.users.Count
                Write-Log -Message ("Retrieved $($response.users.Count) users; total so far: $($students.Count)")
            } else {
                Write-Log "No more users returned; ending loop" -Level Trace
                break
            }
        }
        catch {
            Write-Log -Message ("User data request failed: $_") -Level Error
            return @()  # Return empty array on failure
        }
    } while ($response.users.Count -eq $limit)

    # Output total number of users retrieved
    Write-Log -Message ("Total users retrieved: $($students.Count)")

    # Transform each student into a flattened object
    $studentsFiltered = $students | ForEach-Object {

        # Find primary role (preferred) or first role if missing
        $roleInfo = $null
        if ($_.roles) {
            $roleInfo = $_.roles | Where-Object { $_.roleType -eq 'primary' } | Select-Object -First 1
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

        # Define the grade order from highest → lowest
        $gradeOrder = @("12","11","10","09","08","07","06","05","04","03","02","01","KG","K4","PK")

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
    
    Write-Log "Finished processing all students" -Level Trace

    # Return the collection of filtered student objects
    return $studentsFiltered
}
