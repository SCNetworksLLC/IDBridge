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

        [bool]$testRun = $false,

        [Parameter(Mandatory = $true)]
        [string]$logFile,

        [Parameter(Mandatory = $true)]
        [PSObject]$headers
    )

    #Get Data from Spreadsheet
    try {
        $data = Get-GoogleSheetData -GoogleSheetID $sheetID -GoogleSheetRange $sheetRange -tokenInformation $headers
        Write-Log -Path $logFile -Message "Source Data Staff: Successfully retrieved Google Sheet data"
    }
    catch {
        Throw (Write-Log -Path $logFile -Message "Source Data Staff: Failed to Retrieve Google Sheet Data" -Level Error)
    }

    #Check data fetched count for safety
    if ($data.count -gt ([int]$userCount * ([int]$userCountSafetyPercentage / 100))) {
        Write-Log -Path $logFile -Message "Source Data Staff: Successfully retrieved $($data.count) Users"
    } else {
        Throw (Write-Log -Path $logFile -Message "Source Data Staff: $($data.count) retrieved but does not meet the threshold of $([int]$userCountSafetyPercentage / 100)" -Level Error)
    }

    #Limit data to 10 objects if Test Run is active
    if ($testRun -eq $true) {
        $data = $data | Select-Object -first 10
        Write-Log -Path $logFile -Message "TEST RUN: LIMITING DATA SOURCE TO TEN USERS - $($data.PersonID)"
    }

    #Check to see if there is actually any data to process
    if ($data.Process -notcontains "TRUE") {
        Throw (Write-Log -Path $logFile -Message "Source Data: Data fetched but no users are set to process" -Level Error)
    }

    return $data
}