<#
.SYNOPSIS
Read and validate source rows from a Google Sheet.

.DESCRIPTION
Retrieves the given sheet range via Get-GoogleSheetData, verifies the required columns are
present, and enforces a safety floor on the populated row count (rows with a PersonID; blank
future-use rows in the range are excluded) — aborting if the sheet returns fewer populated rows
than userCount * userCountSafetyPercentage% (protection against a truncated or empty sheet).
Returns only rows flagged Process = 'TRUE' that have every required column populated
(TerminationDate excepted); rows missing data or not flagged to process are logged and skipped.

.PARAMETER sheetID
The Google Spreadsheet ID to read.

.PARAMETER sheetRange
The sheet name or range to read (e.g. a named range like 'Staff').

.PARAMETER userCount
The expected baseline row count used for the safety-floor calculation.

.PARAMETER userCountSafetyPercentage
The percentage of userCount that must be exceeded for the run to proceed. Default 75.

.OUTPUTS
[object[]] the validated rows flagged to process.

.EXAMPLE
Get-SourceDataGSheet -sheetID '<spreadsheet id>' -sheetRange 'Staff' -userCount 650

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-13
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

        [int]$userCountSafetyPercentage = 75
    )

    #Get Data from Spreadsheet
    try {
        $data = Get-GoogleSheetData -GoogleSheetID $sheetID -GoogleSheetRange $sheetRange
        Write-Log -Message "Source Data: Successfully retrieved Google Sheet data"
    }
    catch {
        Write-Log -Message "Source Data: Failed to Retrieve Google Sheet Data: $($_)" -Level Error
        Throw "Source Data: Failed to Retrieve Google Sheet Data: $($_)"
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
    #Blank rows in the sheet range come back as objects with empty properties - count only
    #populated rows (PersonID present) so padding rows can't mask a truncated sheet.
    $populatedCount = @($data | Where-Object { $_.PersonID -ne "" }).Count
    $safetyFloor = [int]$userCount * ([int]$userCountSafetyPercentage / 100)
    if ($populatedCount -gt $safetyFloor) {
        Write-Log -Message "Source Data: Successfully retrieved $populatedCount Users ($($data.count) rows in range)"
    } else {
        Write-Log -Message "Source Data: $populatedCount populated rows retrieved ($($data.count) rows in range) but does not meet the safety floor of $safetyFloor ($userCountSafetyPercentage% of $userCount)" -Level Error
        Throw "Source Data: $populatedCount populated rows retrieved ($($data.count) rows in range) but does not meet the safety floor of $safetyFloor ($userCountSafetyPercentage% of $userCount)"
    }


    #Check to see if there is actually any data to process
    if ($data.Process -notcontains "TRUE") {
        Write-Log -Message "Source Data: Data fetched but no users are set to process" -Level Error
        Throw "Source Data: Data fetched but no users are set to process"
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
                Write-Log -Message ("Source Data: Skipping Person Due to Missing Data in Required Columns: " + $item.PersonID)
                Remove-Variable dataCheckFailed
            } else {
                $filteredData += $item
            }
        } else {
            #Check if data actually exists before logging - need this due to blank rows in sheet being read as objects with empty properties
            if ($item.PersonID -ne "") {
                #Remove Users where the process field is false
                #$skippedData += $item
                Write-Log -Message ("Source Data: Skipping Person Due to process field set to false: " + $item.PersonID)
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