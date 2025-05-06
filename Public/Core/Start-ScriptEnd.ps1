<#
.SYNOPSIS
Start-ScriptEnd logs the end of the script

.DESCRIPTION
Start-ScriptEnd writes to the log file that the script finished

.EXAMPLE
Start-ScriptEnd

.NOTES
   Created by: Sam Cattanach 
   Modified: 2025-04-12 9:47 PM CST
#>
function Start-ScriptEnd {
    [cmdletbinding()]
    Param(
        [string]$Message,
        [switch]$WriteError
    )
    
    if ($Message) {
        if ($WriteError) {
            Write-Log -Message $Message -Path $logFile -Level Error
        } else {
            Write-Log -Message $Message -Path $logFile
        }
    }

    Write-Log -Message "######## End of Script Run: $logDate ########" -Path $logFile

    if ($Message) {
        Return $Message
    }
}