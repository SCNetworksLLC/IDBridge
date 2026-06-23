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