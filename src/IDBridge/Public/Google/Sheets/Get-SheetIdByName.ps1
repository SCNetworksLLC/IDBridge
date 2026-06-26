<#
.SYNOPSIS
Resolve a sheet/tab's numeric sheetId from its name.

.DESCRIPTION
Reads the spreadsheet metadata and returns the numeric sheetId of the tab whose title matches
sheetName. Throws if no tab with that name exists.

.PARAMETER spreadSheetID
The spreadsheet id.

.PARAMETER sheetName
The sheet/tab title to look up.

.PARAMETER TokenInformation
The Google API auth headers.

.OUTPUTS
[int] the numeric sheetId.

.EXAMPLE
$sheetId = Get-SheetIdByName -spreadSheetID $id -sheetName 'Staff' -TokenInformation $headers

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-SheetIdByName {
    param (
        [string]$spreadSheetID,      # Spreadsheet ID
        [string]$sheetName,          # Sheet name
        [hashtable]$TokenInformation # Authentication token headers
    )

    $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID"
    $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $TokenInformation

    # Search for the sheet by name and get its ID
    $sheet = $response.sheets | Where-Object { $_.properties.title -eq $sheetName }
    if ($sheet) {
        return $sheet.properties.sheetId
    } else {
        throw "Sheet '$sheetName' not found."
    }
}