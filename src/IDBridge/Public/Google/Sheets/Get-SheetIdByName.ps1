# Function to get sheet ID by sheet name
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