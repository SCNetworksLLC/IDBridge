<#
.SYNOPSIS
Read and validate source rows from a Google Sheet.

.DESCRIPTION
Retrieves the given sheet range via Get-GoogleSheetData, verifies the required columns are
present, and enforces a safety floor on the row count — aborting if the sheet returns fewer rows
than userCount * userCountSafetyPercentage% (protection against a truncated or empty sheet).
Returns only rows flagged Process = 'TRUE' that have every required column populated
(TerminationDate excepted); rows missing data or not flagged to process are logged and skipped.
When testRun is set, the result is capped at the first 10 rows.

.PARAMETER sheetID
The Google Spreadsheet ID to read.

.PARAMETER sheetRange
The sheet name or range to read (e.g. a named range like 'Staff').

.PARAMETER userCount
The expected baseline row count used for the safety-floor calculation.

.PARAMETER userCountSafetyPercentage
The percentage of userCount that must be exceeded for the run to proceed. Default 75.

.PARAMETER testRun
When $true, limit the returned rows to the first 10 for faster iteration. Default $false.

.OUTPUTS
[object[]] the validated rows flagged to process.

.EXAMPLE
Get-SourceDataGSheet -sheetID '1qrZ...' -sheetRange 'Staff' -userCount 650

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-SourceDataGSheet {
    [CmdletBinding()]
    param (        
        [Parameter(Mandatory = $true)]
        [string]$sheetID,

        [Parameter(Mandatory = $true)]
        [string]$sheetRange,

        [Parameter(Mandatory = $true)]
        [int]$userCount,

        [int]$userCountSafetyPercentage = 75,

        [bool]$testRun = $false
    )

    #Get Data from Spreadsheet
    try {
        $data = Get-GoogleSheetData -GoogleSheetID $sheetID -GoogleSheetRange $sheetRange
        Write-Log -Message "Source Data: Successfully retrieved Google Sheet data"
    }
    catch {
        Throw (Write-Log -Message "Source Data: Failed to Retrieve Google Sheet Data" -Level Error)
    }

    #Required Columns in the Google Sheet
    $requiredColumnsConfig = @(
        "PersonID"
        "NameFirst"
        "NameLast"
        "Username"
        "Building"
        "PersonType"
        "JobTitle"
        "TerminationDate"
        "Process"
    )

    #Check to make sure required columns exist in the data
    $columnsReturned = $data | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Write-Log -Message "Required columns not found. Columns Needed: $columnCheck" -Level Error
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }


    #Check data fetched count for safety
    if ($data.count -gt ([int]$userCount * ([int]$userCountSafetyPercentage / 100))) {
        Write-Log -Message "Source Data: Successfully retrieved $($data.count) Users"
    } else {
        Throw (Write-Log -Message "Source Data: $($data.count) retrieved but does not meet the threshold of $([int]$userCountSafetyPercentage / 100)" -Level Error)
    }


    #Limit data to 10 objects if Test Run is active
    if ($testRun -eq $true) {
        $data = $data | Select-Object -first 10
        Write-Log -Message "TEST RUN: LIMITING DATA SOURCE TO TEN USERS - $($data.PersonID)"
    }


    #Check to see if there is actually any data to process
    if ($data.Process -notcontains "TRUE") {
        Throw (Write-Log -Message "Source Data: Data fetched but no users are set to process" -Level Error)
    }


    #Remove Users who do not have data in all required fields except for terminationDate
    $filteredData = @()
    foreach ($item in $data) {
        $dataCheckFailed = $null
        if ($item.Process -eq "TRUE") {
            foreach ($column in ($requiredColumnsConfig | Where-Object {$_ -ne "TerminationDate"})) {
                if (!($item.$column)) {
                    $dataCheckFailed = "yes"
                }
            }
            if ($dataCheckFailed) {
                #$skippedData += $item
                Write-Log -Message ("Skipping Person Due to Missing Data in Required Columns: " + $item.PersonID)
                Remove-Variable dataCheckFailed
            } else {
                $filteredData += $item
            }
        } else {
            #Check if data actually exists before logging - need this due to blank rows in sheet being read as objects with empty properties
            if ($item.PersonID -ne "") {
                #Remove Users where the process field is false
                #$skippedData += $item
                Write-Log -Message ("Skipping Person Due to process field set to false: " + $item.PersonID)
            }
        }
    }

    <#
    #Trim Whitespace from all string fields in the data
    foreach ($item in $filteredData) {
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Value -is [string]) {
                $item.$($property.Name) = $item.$($property.Name).Trim()
            }
        }
    }
    #>

    return $filteredData
}