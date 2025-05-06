function Set-GSheetData{
    <#
    .Synopsis
        Set values in sheet in specific cell locations or append data to a sheet

    .DESCRIPTION
        Set json data values on a sheet in specific cell ranges, specific cells, or append a new row to a sheet
        Original work by UMN - https://github.com/umn-microsoft-automation/UMN-Google/blob/master/UMN-Google.psm1

    .PARAMETER TokenInformation
        Headers used for authentication.

    .PARAMETER append
        Switch option to append data. See rangeA1 if not appending

    .PARAMETER contenttype
        The contenttype specifies the content type of the web request. Default value is 'application/json'.

    .PARAMETER rangeA1
        Range in A1 notation https://msdn.microsoft.com/en-us/library/bb211395(v=office.12).aspx . The dimensions of the $values you put in MUST fit within this range

    .PARAMETER sheetName
        Name of sheet to set data in

    .PARAMETER spreadSheetID
        ID for the target Spreadsheet.

    .PARAMETER valueInputOption
        Default to RAW. Optionally, you can specify if you want it processed as a formula and so forth.

    .PARAMETER values
        The values to write to the sheet. This should be an array list.  Each list array represents one ROW on the sheet.

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -rangeA1 'A1:B2' -sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values @(@("a","b"),@("c","D"))

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -append 'Append'-sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values $arrayValues

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -rangeA1 "B2" -sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values @(@('only_one_updated_cell'),@())
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory)]
        [hashtable]$TokenInformation,

        [Parameter(ParameterSetName='Append')]
        [switch]$append,

        [Parameter(ParameterSetName='set')]
        [string]$rangeA1,

        [Parameter(Mandatory)]
        [string]$sheetName,

        [Parameter(Mandatory)]
        [string]$spreadSheetID,

        [string]$valueInputOption = 'RAW',

        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$values,

        [string]$contenttype = 'application/json'
    )

    Begin
    {
        if ($append)
            {
                $method = 'POST'
                $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID/values/$sheetName"+":append?valueInputOption=$valueInputOption"
            }
        else
            {
                $method = 'PUT'
                $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID/values/$sheetName!$rangeA1"+"?valueInputOption=$valueInputOption"
            }
    }

    Process
    {
        $json = @{values=$values} | ConvertTo-Json
        Invoke-RestMethod -Method $method -Uri $uri -Body $json -ContentType $contenttype -Headers $TokenInformation
    }

    End{}
}
