<#
.SYNOPSIS
Uncheck (set to FALSE) one or more checkbox cells via the Sheets batchUpdate API.

.DESCRIPTION
For each supplied A1 cell reference, builds a repeatCell request that sets the cell's boolean value
to false, then sends them in a single batchUpdate. Resolves the numeric sheetId with
Get-SheetIdByName and converts each cell with Convert-CellToIndex.

.PARAMETER cells
The A1-style cell references to uncheck (e.g. @('M63','M65')).

.PARAMETER spreadSheetID
The spreadsheet id.

.PARAMETER sheetName
The sheet/tab name containing the cells.

.PARAMETER TokenInformation
The Google API auth headers.

.EXAMPLE
Set-CheckboxesToFalse -cells @('M63','M65') -spreadSheetID $id -sheetName 'Staff' -TokenInformation $headers

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Set-CheckboxesToFalse {
    param (
        $cells,           # Array of cell references like ["M63", "M65"]
        [string]$spreadSheetID,      # The spreadsheet ID
        [string]$sheetName,         # The sheet name (e.g., "Staff")
        [hashtable]$TokenInformation # Authentication token headers
    )

    # Get the sheet ID from the sheet name
    $sheetId = Get-SheetIdByName -spreadSheetID $spreadSheetID -sheetName $sheetName -TokenInformation $TokenInformation

    $requests = @()

    # Convert each cell into the corresponding request format
    foreach ($cell in $cells) {
        $cellIndexes = Convert-CellToIndex $cell
        $startRowIndex = $cellIndexes.row
        $startColumnIndex = $cellIndexes.column
        $endRowIndex = $startRowIndex + 1
        $endColumnIndex = $startColumnIndex + 1

        $request = @{
            repeatCell = @{
                range = @{
                    sheetId = $sheetId
                    startRowIndex = $startRowIndex
                    startColumnIndex = $startColumnIndex
                    endRowIndex = $endRowIndex
                    endColumnIndex = $endColumnIndex
                }
                cell = @{
                    userEnteredValue = @{
                        boolValue = $false # Uncheck checkbox
                    }
                }
                fields = "userEnteredValue"
            }
        }

        $requests += $request
    }

    # Build the body for the batchUpdate API request
    $body = @{
        requests = $requests
    } | ConvertTo-Json -Depth 10

    # Send the request to the Google Sheets API
    $uri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadSheetID):batchUpdate"
    Invoke-RestMethod -Method POST -Uri $uri -Body $body -ContentType "application/json" -Headers $TokenInformation
}