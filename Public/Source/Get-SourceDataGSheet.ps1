function Get-SourceDataGSheet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Student","Staff", IgnoreCase = $true)]
        [string]$personType,
        
        [Parameter(Mandatory = $true)]
        [string]$sheetID,

        [Parameter(Mandatory = $true)]
        [string]$sheetRange,

        [Parameter(Mandatory = $true)]
        [int]$userCount,

        [int]$userCountSafetyPercentage = 75,

        [bool]$testRun = $false,

        [Parameter(Mandatory = $true)]
        [string]$logFile,

        [Parameter(Mandatory = $true)]
        [PSObject]$headers
    )

    #Get Data from Spreadsheet
    try {
        $data = Get-GoogleSheetData -GoogleSheetID $sheetID -GoogleSheetRange $sheetRange -tokenInformation $headers
        Write-Log -Path $logFile -Message "Source Data $($personType): Successfully retrieved Google Sheet data"
    }
    catch {
        Throw (Write-Log -Path $logFile -Message "Source Data $($personType): Failed to Retrieve Google Sheet Data" -Level Error)
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
        "Word"
        "Process"
    )

    #Check to make sure required columns exist in the data
    $columnsReturned = $data | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Write-Log -Path $logFile -Message "Required columns not found. Columns Needed: $columnCheck" -Level Error
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }


    #Check data fetched count for safety
    if ($data.count -gt ([int]$userCount * ([int]$userCountSafetyPercentage / 100))) {
        Write-Log -Path $logFile -Message "Source Data $($personType): Successfully retrieved $($data.count) Users"
    } else {
        Throw (Write-Log -Path $logFile -Message "Source Data $($personType): $($data.count) retrieved but does not meet the threshold of $([int]$userCountSafetyPercentage / 100)" -Level Error)
    }


    #Limit data to 10 objects if Test Run is active
    if ($testRun -eq $true) {
        $data = $data | Select-Object -first 10
        Write-Log -Path $logFile -Message "TEST RUN: LIMITING DATA SOURCE TO TEN USERS - $($data.PersonID)"
    }


    #Check to see if there is actually any data to process
    if ($data.Process -notcontains "TRUE") {
        Throw (Write-Log -Path $logFile -Message "Source Data $($personType): Data fetched but no users are set to process" -Level Error)
    }

    foreach ($item in $data) {
        $item | Add-Member -MemberType NoteProperty -Name "PersonTypeGeneric" -Value "$($personType)"
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
                Write-Log -Path $logFile -Message ("Skipping Person Due to Missing Data in Required Columns: " + $item.PersonID)
                Remove-Variable dataCheckFailed
            } else {
                $filteredData += $item
            }
        } else {
            #Check if data actually exists before logging - need this due to blank rows in sheet being read as objects with empty properties
            if ($item.PersonID -ne "") {
                #Remove Users where the process field is false
                #$skippedData += $item
                Write-Log -Path $logFile -Message ("Skipping Person Due to process field set to false: " + $item.PersonID)
            }
        }
    }

    return $filteredData
}