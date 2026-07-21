<#
.SYNOPSIS
Write the in-memory run log to a Google Sheet, newest entries on top.

.DESCRIPTION
Pulls the structured log buffer (Get-IDBridgeLogs), reverses it so the newest entry lands first, and
writes it to the named sheet. Resolves the target sheet's id — creating the sheet if it doesn't
exist — then applies one atomic batchUpdate that writes the Timestamp/Level/Message header (new
sheets only), inserts blank rows under the header, fills them with the entries, and trims the
oldest rows from the bottom once the sheet passes 50,000 rows (keeping the newest 25,000).
batchUpdate applies its requests in order and all-or-nothing, so a failure leaves the sheet
untouched. Throws on failure. Typically called from the Invoke-IDBridge finally block when
Logging.GoogleSheetLoggingEnabled is set.

.PARAMETER spreadsheetId
The target spreadsheet id.

.PARAMETER sheetName
The sheet/tab name to write to (created if missing).

.EXAMPLE
Push-LogsToSheet -spreadsheetId $IDConfig.Logging.SheetID -sheetName 'Logs'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-21
#>
function Push-LogsToSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$spreadsheetId,

        [Parameter(Mandatory = $true)]
        [string]$sheetName
    )

    #Row cap: once the sheet grid passes maxRows, trim the oldest (bottom) rows, keeping the newest trimToRows
    $maxRows = 50000
    $trimToRows = 25000

    try {
        # Pull the structured in-memory log buffer (oldest-first)
        $logs = @(Get-IDBridgeLogs)
        if ($logs.Count -eq 0) {
            Write-Log -Message "Push-LogsToSheet: Log buffer is empty; nothing to push." -Level Warn
            return
        }

        # Google API headers (with access token)
        $headers = Get-GoogleHeaders

        # Build cell rows for the inserted block, newest entry first (the buffer is oldest-first).
        # userEnteredValue.stringValue keeps cells as literal strings (same as valueInputOption=RAW).
        $newRows = [System.Collections.Generic.List[object]]::new()
        for ($i = $logs.Count - 1; $i -ge 0; $i--) {
            $entry = $logs[$i]
            $ts = if ($entry.Timestamp -is [datetime]) {
                $entry.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
            } else {
                [string]$entry.Timestamp
            }
            $newRows.Add(@{ values = @(
                @{ userEnteredValue = @{ stringValue = $ts } },
                @{ userEnteredValue = @{ stringValue = [string]$entry.Level } },
                @{ userEnteredValue = @{ stringValue = [string]$entry.Message } }
            ) })
        }

        $numNew = $newRows.Count

        # Fetch spreadsheet metadata to resolve the sheetId and current row count
        $metaUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId)?fields=sheets.properties"
        $meta = Invoke-RestMethod -Method Get -Uri $metaUri -Headers $headers -ErrorAction Stop

        # Find the target sheet; create it if missing (the reply carries the new sheet's properties)
        $batchUri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadsheetId):batchUpdate"
        $sheet = $meta.sheets | Where-Object { $_.properties.title -eq $sheetName }
        $sheetWasCreated = $false
        if (-not $sheet) {
            $createBody = @{ requests = @(@{ addSheet = @{ properties = @{ title = $sheetName } } }) } | ConvertTo-Json -Depth 5
            $createReply = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $createBody -ContentType 'application/json' -ErrorAction Stop
            $sheet = $createReply.replies[0].addSheet
            $sheetWasCreated = $true
        }

        $sheetId = $sheet.properties.sheetId
        $rowCount = [int]$sheet.properties.gridProperties.rowCount

        # One atomic batchUpdate: header (new sheets), insert blank rows under the header (row 1),
        # write the entries into them, and trim past the row cap. Requests apply in order; if any
        # request fails, none apply.
        $requests = @()

        # A brand-new sheet has no header row yet; write one before prepending entries
        if ($sheetWasCreated) {
            $requests += @{
                updateCells = @{
                    rows   = @(@{ values = @(
                        @{ userEnteredValue = @{ stringValue = 'Timestamp' } },
                        @{ userEnteredValue = @{ stringValue = 'Level' } },
                        @{ userEnteredValue = @{ stringValue = 'Message' } }
                    ) })
                    fields = 'userEnteredValue'
                    start  = @{ sheetId = $sheetId; rowIndex = 0; columnIndex = 0 }
                }
            }
        }

        $requests += @{
            insertDimension = @{
                range = @{
                    sheetId    = $sheetId
                    dimension  = "ROWS"
                    startIndex = 1
                    endIndex   = 1 + $numNew
                }
            }
        }

        $requests += @{
            updateCells = @{
                rows   = @($newRows)
                fields = 'userEnteredValue'
                start  = @{ sheetId = $sheetId; rowIndex = 1; columnIndex = 0 }
            }
        }

        # Oldest entries live at the bottom (newest-on-top), so trim from the bottom up
        $trimmed = 0
        $newRowCount = $rowCount + $numNew
        if ($newRowCount -gt $maxRows) {
            $trimmed = $newRowCount - (1 + $trimToRows)
            $requests += @{
                deleteDimension = @{
                    range = @{
                        sheetId    = $sheetId
                        dimension  = "ROWS"
                        startIndex = 1 + $trimToRows
                        endIndex   = $newRowCount
                    }
                }
            }
        }

        $body = @{ requests = $requests } | ConvertTo-Json -Depth 12 -Compress
        $null = Invoke-RestMethod -Method Post -Uri $batchUri -Headers $headers -Body $body -ContentType 'application/json' -ErrorAction Stop

        if ($trimmed -gt 0) {
            Write-Log -Message "Push-LogsToSheet: Inserted and wrote $numNew rows to '$sheetName' (sheetId=$sheetId); trimmed $trimmed bottom rows to keep the newest $trimToRows."
        } else {
            Write-Log -Message "Push-LogsToSheet: Inserted and wrote $numNew rows to '$sheetName' (sheetId=$sheetId)."
        }
    }
    catch {
        Write-Log -Message ("Push-LogsToSheet: Failed: " + $_.Exception.Message) -Level Error
        throw
    }
}
