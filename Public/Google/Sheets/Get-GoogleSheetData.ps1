<#
.SYNOPSIS
    Retrieves data from a Google Sheet using the Google Sheets API.

.DESCRIPTION
    This function connects to the Google Sheets API using the provided sheet 
    information and authentication token. It fetches the specified sheet's 
    data and returns it as an array of PowerShell objects.

.PARAMETER googleSheetInformation
    A hashtable containing:
      - sheetId: The unique identifier of the Google Sheet.
      - sheetRange: The range of cells to retrieve (e.g., "Sheet1!A1:D10" or "Sheet1").

.PARAMETER tokenInformation
    A hashtable containing the authorization headers, typically including an OAuth token 
    required to authenticate API requests.

.OUTPUTS
    Returns an array of PowerShell objects where each object represents a row from 
    the Google Sheet, with column names as property names.

.EXAMPLE
    $sheetInfo = @{
        sheetId = "1aBcD2EfGhIjKlMnOpQrStUvWxYz1234567890"
        sheetRange = "Sheet1!A1:D10"
    }
    $tokenInfo = @{
        "Authorization" = "Bearer YOUR_ACCESS_TOKEN"
        "Accept" = "application/json"
    }

    $data = Get-GoogleSheetData -googleSheetInformation $sheetInfo -tokenInformation $tokenInfo

    This example retrieves the data from a specific range in a Google Sheet and 
    returns it as structured PowerShell objects.

.NOTES
    - Requires valid OAuth 2.0 credentials with permission to access the specified Google Sheet.
    - The first row in the range is treated as column headers.
    - Data is formatted into objects where each row's values are mapped to the corresponding header.
    - Uses `Invoke-RestMethod` to send the request to the Google Sheets API.

    Created by: Sam Cattanach
    Modified: 02/18/2025 09:30:19 AM   
#>
function Get-GoogleSheetData() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        [string]$GoogleSheetID,  # sheet ID

        [parameter(Mandatory=$true)]
        [string]$GoogleSheetRange,  # Sheet Range

        [parameter(Mandatory=$true)]
        [hashtable]$tokenInformation  # Hashtable containing OAuth authentication headers
    )

    # Construct the API request URL using the sheet ID and range
    $uri = "https://sheets.googleapis.com/v4/spreadsheets/{0}/values/{1}?majorDimension=ROWS" -f $googleSheetID, $googleSheetRange

    # Send GET request to Google Sheets API
    $results = Invoke-RestMethod -Uri $uri -Method GET -Headers $tokenInformation -Verbose:$false

    # Extract column headers from the first row
    $columns = $results.values[0]

    # Initialize an array to store row data
    $allData = @()

    # Process each subsequent row and map values to column headers
    # Slice the values array from index 1 to the last index, skipping the header row (index 0).
    # Unlike Select-Object -Skip 1, array slicing preserves each row as an Object[] rather than unwrapping it into individual elements.
    foreach ($row in $results.values[1..($results.values.Count - 1)]) {
        if ($rowData) {Remove-Variable rowData}

        $rowData = New-Object -TypeName psobject

        for($i=0; $i -lt $columns.count; $i++) {
            $rowData | Add-Member -MemberType NoteProperty -Name $columns[$i] -Value "$($row[$i])"
        }

        # Append the row data object to the result array
        $allData += $rowData
    }

    #Trim Whitespace from all string fields in the data
    foreach ($item in $allData) {
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Value -is [string]) {
                $item.$($property.Name) = $item.$($property.Name).Trim()
            }
        }
    }

    return $allData
}