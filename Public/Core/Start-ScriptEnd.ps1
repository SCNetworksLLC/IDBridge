<#
.SYNOPSIS
Start-ScriptEnd logs the end of the script

.DESCRIPTION
Start-ScriptEnd writes to the log file that the script finished

.EXAMPLE
Start-ScriptEnd

.NOTES
   Created by: Sam Cattanach 
   Modified: 2025-10-16
#>
function Start-ScriptEnd {
    [cmdletbinding()]
    Param(
        [string]$Message,
        [switch]$WriteError,
        [string]$UploadLogsSheetID,
        [hashtable]$GoogleHeaders  # Authentication headers for the Google API request
    )
    
    if ($Message) {
        if ($WriteError) {
            Write-Log -Message $Message -Path $logFile -Level Error
        } else {
            Write-Log -Message $Message -Path $logFile
        }
    }

    Write-Log -Message "######## End of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########" -Path $logFile

    #Upload Logs to Google Sheets
    if ($UploadLogsSheetID -and $GoogleHeaders) {
        Push-LogsToSheet -logFile 'C:\IDBridge\Logs\IDBridge.log' -headers $GoogleHeaders -spreadsheetId $UploadLogsSheetID -sheetName 'Logs' -hasHeader
    }

    if ($Message) {
        Return $Message
    }
}