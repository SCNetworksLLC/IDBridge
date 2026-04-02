function Get-SourceDataGSheetOverride {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$sheetID,

        [Parameter(Mandatory = $true)]
        [string]$sheetRange,

        [Parameter(Mandatory = $true)]
        [string]$logFile,

        [Parameter(Mandatory = $true)]
        [PSObject]$headers
    )

    #Get Data from Spreadsheet
    try {
        $data = Get-GoogleSheetData -GoogleSheetID $sheetID -GoogleSheetRange $sheetRange -tokenInformation $headers
        Write-Log -Path $logFile -Message "Source Data: Successfully retrieved Google Sheet Override data"
        if(-not $data) {
            Write-Log -Path $logFile -Message "Source Data: No data found in Google Sheet" -Level Warning
            return
        }
    }
    catch {
        Throw (Write-Log -Path $logFile -Message "Source Data: Failed to Retrieve Google Sheet Data" -Level Error)
    }

    #Required Columns in the Google Sheet
    $requiredColumnsConfig = @(
        "PersonID"
        "NameFirst"
        "NameLast"
        "Username"
        "ForceDisable"
        "GoogleOUOverride"
        "OverrideEndDate"
    )

    #Check to make sure required columns exist in the data
    $columnsReturned = $data | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Write-Log -Path $logFile -Message "Required columns not found. Columns Needed: $columnCheck" -Level Error
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }

    #Trim Whitespace from all string fields in the data
    foreach ($item in $data) {
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Value -is [string]) {
                $item.$($property.Name) = $item.$($property.Name).Trim()
            }
        }
    }

    return $data
}