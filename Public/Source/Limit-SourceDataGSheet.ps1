function Limit-SourceDataGSheet {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )

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

    #Remove Users who do not have data in all required fields except for terminationDate
    #Remove Users where the process field is false
    $filteredData = @()
    $skippedData = @()

    foreach ($item in $SourceData) {
        if ($item.Process -eq "TRUE") {
            foreach ($column in ($requiredColumnsConfig | Where-Object {$_ -ne "TerminationDate"})) {
                if (!($item.$column)) {
                    $dataCheckFailed = "yes"
                }
            }

            if ($dataCheckFailed) {
                $skippedData += $item
                Write-Log -Path $logFile -Message ("Skipping Person Due to Missing Data in Required Columns: " + $item.PersonID)
                Remove-Variable dataCheckFailed
            } else {
                $filteredData += $item
            }
        } else {
            $skippedData += $item
            Write-Log -Path $logFile -Message ("Skipping Person Due to process field set to false: " + $item.PersonID)
        }
    }

    return $filteredData
}