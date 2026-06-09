function Push-LogsToSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$headers,

        [Parameter(Mandatory=$true)]
        [string]$spreadsheetId,

        [Parameter(Mandatory=$true)]
        [string]$sheetName,

        [switch]$hasHeader
    )

    try {
        # Read log file
        $allLines = Get-Content -Path $logFile -ErrorAction Stop

        # Find the last "Begin of Script Run" line number (1-based)
        $beginMatches = Select-String -Path $logFile -Pattern 'Begin of Script Run:' -SimpleMatch -ErrorAction SilentlyContinue
        if ($beginMatches -and $beginMatches.Count -gt 0) {
            $startLine = $beginMatches[-1].LineNumber
        } else {
            $startLine = 1
        }

        $runLines = if ($allLines.Count -ge $startLine) { $allLines[($startLine - 1)..($allLines.Count - 1)] } else { @() }

        if (-not $runLines -or $runLines.Count -eq 0) {
            Write-Log -Message "Push-RunLogsToSheet: No log lines found for current run (startLine=$startLine)." -Level Warning
            return $true
        }

        # Reverse so newest entries come first
        $reversed = New-Object System.Collections.ArrayList
        for ($i = $runLines.Count - 1; $i -ge 0; $i--) { $null = $reversed.Add($runLines[$i]) }

        # Parse lines to [Timestamp, Level, Message] where possible
        $regex = '^\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+([A-Z]+):\s*(.*)$'
        $newRows = @()
        foreach ($line in $reversed) {
            if ($line -match $regex) {
                $ts = $matches[1]; $lvl = $matches[2]; $msg = $matches[3]
            } else {
                $ts = ''; $lvl = ''; $msg = $line
            }
            $newRows += ,@($ts, $lvl, $msg)
        }

        $numNew = $newRows.Count
        if ($numNew -eq 0) { return $true }

        # Helper: send a REST GET to fetch spreadsheet metadata (to find sheetId)
        $metaUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId)?fields=sheets.properties"
        $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop

        # Find sheetId for sheetName; if missing, create the sheet with batchUpdate addSheet
        $sheet = $meta.sheets | Where-Object { $_.properties.title -eq $sheetName }
        if (-not $sheet) {
            # create new sheet
            $createBody = @{ requests = @(@{ addSheet = @{ properties = @{ title = $sheetName } } }) } | ConvertTo-Json -Depth 5
            $batchUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId):batchUpdate"
            Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $createBody -ContentType 'application/json' -ErrorAction Stop

            # refetch metadata to get the new sheetId
            $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop
            $sheet = $meta.sheets | Where-Object { $_.properties.title -eq $sheetName }
            if (-not $sheet) { Throw "Push-RunLogsToSheet: Failed to create sheet '$sheetName'." }
        }

        $sheetId = $sheet.properties.sheetId

        # If we need to preserve header row, we will insert rows after header (startIndex=1)
        $insertIndex = 0
        if ($hasHeader) { $insertIndex = 1 }

        # Insert N rows at top (or after header)
        $insertBody = @{
            requests = @(
                @{
                    insertDimension = @{
                        range = @{
                            sheetId = $sheetId
                            dimension = "ROWS"
                            startIndex = $insertIndex
                            endIndex = $insertIndex + $numNew
                        }
                    }
                }
            )
        } | ConvertTo-Json -Depth 6

        $batchUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId):batchUpdate"
        Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $insertBody -ContentType 'application/json' -ErrorAction Stop

        # Prepare the values payload for only the inserted rows (we'll write starting at A{1 or 2})
        $startRow = if ($insertIndex -eq 0) { 1 } else { $insertIndex + 1 } # because A1 is row 1
        $rangeA1 = "A${startRow}"

        # Use existing Set-GSheetData helper to write only the top inserted rows.
        Set-GSheetData -TokenInformation $headers -rangeA1 $rangeA1 -sheetName $sheetName -spreadSheetID $spreadsheetId -values $newRows

        Write-Log -Message ("Push-RunLogsToSheet: Inserted and wrote $numNew rows to '$sheetName' (sheetId=$sheetId).")
        return $true
    }
    catch {
        Write-Log -Message ("Push-RunLogsToSheet: Failed: " + $_.Exception.Message) -Level Error
        throw $_
    }
}