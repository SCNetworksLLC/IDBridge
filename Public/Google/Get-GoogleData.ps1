<#
.SYNOPSIS
    Retrieves data from a Google API using the provided headers and API URI.

.DESCRIPTION
    This function sends a GET request to a specified Google API endpoint using
    the provided authentication headers. If the API response includes paginated 
    results, it continues to fetch additional pages until all data is retrieved.

.PARAMETER GoogleHeaders
    A hashtable containing the necessary headers for authenticating the request 
    to the Google API (e.g., authorization token, content type).

.PARAMETER APIUri
    A string representing the full URI of the Google API endpoint.

.OUTPUTS
    Returns the retrieved data from the API. If the response is paginated, all pages
    are combined into a single collection before returning.

.EXAMPLE
    $headers = @{
        "Authorization" = "Bearer YOUR_ACCESS_TOKEN"
        "Accept" = "application/json"
    }
    $uri = "https://www.googleapis.com/someapi/v1/resource"

    $result = Get-GoogleData -GoogleHeaders $headers -APIUri $uri

    This example sends a request to the Google API endpoint and retrieves the
    data while handling pagination if necessary.

.NOTES
    - The function assumes that the API response contains a JSON object with 
      a property that holds the relevant data.
    - If more than 500 records exist, the function retrieves additional pages 
      using the `nextPageToken` parameter.
    - The function logs an error if no data is retrieved.
    - Input validation checks for empty headers and invalid API URIs.

    Created by: Sam Cattanach
    Modified: 02/18/2025 09:30:19 AM   
#>
function Get-GoogleData {
    param (
        [Parameter(Mandatory)]
        [hashtable]$GoogleHeaders,  # Authentication headers for the Google API request

        [Parameter(Mandatory)]
        [string]$APIUri,  # The Google API endpoint URI

        $VerboseLogging = $false
    )

    # Validate GoogleHeaders - Ensure it's not empty
    if (-not $GoogleHeaders -or $GoogleHeaders.Count -eq 0) {
        Throw "Invalid input: GoogleHeaders cannot be empty."
    }

    # Validate APIUri - Ensure it's a valid URL format
    if ($APIUri -notmatch "^https?:\/\/[\w\-]+(\.[\w\-]+)+[/#?]?.*$") {
        Throw "Invalid input: APIUri must be a valid URL: $($APIUri)"
    }

    # Send the initial request to the Google API
    try {
        $request = Invoke-RestMethod -Uri $APIUri -Headers $GoogleHeaders -Method Get
    } catch {
        Throw "Failed to fetch data from Google API $($APIUri): $_"
    }

    # Identify the primary data object within the response
    $dataType = $request | Get-Member -MemberType NoteProperty | Where-Object { $_.Definition -like "Object*" } | Select-Object -ExpandProperty Name
    $data = $request.$dataType

    # Handle pagination: Fetch additional data if a nextPageToken exists
    while ($request.nextPageToken) {
        $requestUri = ($APIUri + "&pageToken=" + $request.nextPageToken)
        
        try {
            # Send a request for the next page
            $request = Invoke-RestMethod -Uri $requestUri -Headers $GoogleHeaders -Method Get
        } catch {
            Throw "Failed to fetch additional data from API: $_"
        }

        # Append new data to the existing dataset
        $data += $request.$dataType
    }
    
    return $data
}