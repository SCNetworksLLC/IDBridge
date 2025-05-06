function Test-SourceData {
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

    #Check to make sure required columns exist in the data
    $columnsReturned = $SourceData | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Write-Log -Path $logFile -Message "Required columns not found. Columns Needed: $columnCheck" -Level Error
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }

    <# Not needed anymore due to checking files with Test-IDBridgeConfiguration
    #Validate Required Variables are set
    if (!($IDConfig.PersonTypeThree)) {
        Write-Log -Path $logFile -Message "Staff personTypeThree variable needs to be configured" -Level Error
        Throw "Staff personTypeThree variable needs to be configured"
    }
    #>

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