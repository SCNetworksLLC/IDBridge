<#
.SYNOPSIS
Initializes and rotates the IDBridge log file and writes the run bootstrap entry.

.DESCRIPTION
Performs log-file bootstrapping for the IDBridge runner. By default the function:
 - Ensures the log file exists at C:\IDBridge\Logs\IDBridge.log (creates it if missing).
 - Checks the file size and renames the existing file when it exceeds 50 MB.
   The rotated name format is "<BaseName>_yyyy-MM-dd-HH.mm.ss.log".
 - Writes a "Begin of Script Run" entry with a timestamp to the log.

The function is intentionally parameterless in this repository to match the
existing runner usage. Consider adding parameters (e.g. -LogFile, -MaxBytes)
if you want to make it configurable.

.PARAMETER None
This implementation accepts no parameters. See REMARKS for customization notes.

.EXAMPLE
Initialize-Logging

Ensures the log file exists, rotates it if larger than 50 MB, and appends the
run header line such as:
######## Begin of Script Run: 2025-10-19-14.32.05 ########

.INPUTS
None. (The function does not accept pipeline input.)

.OUTPUTS
None. The function writes to the log file and sets the global variable `logFile`.

.REMARKS
- Default log path: C:\IDBridge\Logs\IDBridge.log
- Rotation threshold: 50,000,000 bytes (50 MB)
- Rotation timestamp format used in the filename and header: yyyy-MM-dd-HH.mm.ss
- The function sets a global variable named `logFile` to the default path to
  preserve compatibility with other scripts that reference `$logFile`.
- The function will create the log file if it does not already exist.
- If you want explicit control, modify the function to add parameters:
    -LogFile <string> and -MaxBytes <int>
  which makes the function easier to test and reuse.

.NOTES
Author: SCNetworksLLC (Sam Cattanach)
File: Public/Core/Initialize-Logging.ps1
#>

function Initialize-Logging {
    [cmdletbinding()]
    Param()

    Set-Variable -Name "logFile" -Value "C:\IDBridge\Logs\IDBridge.log" -Scope global

    $logFile = "C:\IDBridge\Logs\IDBridge.log"

    if (!(Test-Path $logFile)) {
        New-Item -Path $logFile -ItemType File -Force | Out-Null
    }

    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 50000000) {
        Rename-Item $logFile ((Get-Item $logfile).BaseName + "_" + $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########" -Path $logFile
}