function Push-LogsToSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$spreadsheetId,

        [Parameter(Mandatory = $true)]
        [string]$sheetName
    )

    try {
        # Pull the structured in-memory log buffer (oldest-first)
        $logs = @(Get-IDBridgeLogs)
        if ($logs.Count -eq 0) {
            Write-Log -Message "Push-LogsToSheet: Log buffer is empty; nothing to push." -Level Warning
            return
        }

        # Google API headers (with access token)
        $headers = Get-GoogleHeaders

        # Reverse so the newest entry lands on top of the sheet
        $ordered = @($logs)
        [array]::Reverse($ordered)

        # Build rows for the inserted block
        $newRows = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $ordered) {
            $ts = if ($entry.Timestamp -is [datetime]) {
                $entry.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
            } else {
                [string]$entry.Timestamp
            }
            $newRows.Add(@($ts, [string]$entry.Level, [string]$entry.Message))
        }

        $numNew = $newRows.Count
        if ($numNew -eq 0) { return }

        # Fetch spreadsheet metadata to resolve the sheetId
        $metaUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId)?fields=sheets.properties"
        $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop

        # Find the target sheet; create it if missing
        $batchUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId):batchUpdate"
        $sheet = $meta.sheets | Where-Object { $_.properties.title -eq $sheetName }
        $sheetWasCreated = $false
        if (-not $sheet) {
            $createBody = @{ requests = @(@{ addSheet = @{ properties = @{ title = $sheetName } } }) } | ConvertTo-Json -Depth 5
            $null = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $createBody -ContentType 'application/json' -ErrorAction Stop

            $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop
            $sheet = $meta.sheets | Where-Object { $_.properties.title -eq $sheetName }
            if (-not $sheet) { throw "Push-LogsToSheet: Failed to create sheet '$sheetName'." }
            $sheetWasCreated = $true
        }

        $sheetId = $sheet.properties.sheetId

        # A brand-new sheet has no header row yet; write one before prepending entries
        if ($sheetWasCreated) {
            $headerRow = [System.Collections.Generic.List[object]]::new()
            $headerRow.Add(@('Timestamp', 'Level', 'Message'))
            $null = Set-GSheetData -TokenInformation $headers -rangeA1 'A1' -sheetName $sheetName -spreadSheetID $spreadsheetId -values $headerRow
        }

        # Insert blank rows directly under the header row (row 1)
        $insertBody = @{
            requests = @(
                @{
                    insertDimension = @{
                        range = @{
                            sheetId    = $sheetId
                            dimension  = "ROWS"
                            startIndex = 1
                            endIndex   = 1 + $numNew
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 6

        $null = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $insertBody -ContentType 'application/json' -ErrorAction Stop

        # Write the new rows into the space we just opened up (row 2, under the header)
        $null = Set-GSheetData -TokenInformation $headers -rangeA1 'A2' -sheetName $sheetName -spreadSheetID $spreadsheetId -values $newRows

        Write-Log -Message "Push-LogsToSheet: Inserted and wrote $numNew rows to '$sheetName' (sheetId=$sheetId)."
    }
    catch {
        Write-Log -Message ("Push-LogsToSheet: Failed: " + $_.Exception.Message) -Level Error
        throw
    }
}