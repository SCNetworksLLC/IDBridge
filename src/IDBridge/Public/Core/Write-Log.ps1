<#
.SYNOPSIS
   The IDBridge logging function: timestamped entries to the log file, the in-memory buffer, and the console.
.DESCRIPTION
   Every IDBridge log line goes through Write-Log. Each message is written to three places:
   the log file (Paths.LogFile by default, created if missing and rotated by
   Initialize-IDBridge past 5 MB), the in-memory buffer read via Get-IDBridgeLogs (used by
   Push-LogsToSheet for Google Sheet logging), and the console (Error/Warn map to the
   error/warning streams; Info/Trace to the verbose stream).

   Trace-level messages are dropped entirely unless Debug.TraceLogging is $true. Requires an
   initialized session (Initialize-IDBridge) — the config supplies the default log path.
.PARAMETER Message
   The message to log (alias LogContent). Accepts pipeline input by property name.
.PARAMETER Path
   The log file to write to (alias LogPath). Defaults to Paths.LogFile from the config.
   The path and file are created if they do not exist.
.PARAMETER Level
   Severity: Error, Warn, Info (default), or Trace. Trace is suppressed unless
   Debug.TraceLogging is enabled.
.PARAMETER NoClobber
   Throw instead of writing when the log file already exists.
.EXAMPLE
   Write-Log -Message 'AD: Fetching Users' -Level Trace
.EXAMPLE
   Write-Log -Message ($_.Exception.Message) -Level Error
.NOTES
   Based on Write-Log by Jason Wasser @wasserja; adapted for IDBridge (Trace level,
   in-memory buffer, config-derived default path).
.LINK
   https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0
#>
function Write-Log { 
    [CmdletBinding()] 
    Param 
    ( 
        [Parameter(Mandatory=$true, 
            ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias("LogContent")] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)]
        [Alias('LogPath')]
        [string]$Path,
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet("Error","Warn","Info","Trace")] 
        [string]$Level="Info", 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber
    ) 
 
    Begin 
    { 
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue' 

        #Import Configuration
        try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }

        # Apply Trace override if specified. This allows us to write trace messages without enabling verbose logging for the entire script.
        if ($Level -eq "Trace" -and (-not $IDConfig.Debug.TraceLogging -or $IDConfig.Debug.TraceLogging -eq $false)) {
            $skip = $true
            return
        }

        if ([string]::IsNullOrWhiteSpace($Path)) {
            $Path = $IDConfig.Paths.LogFile
        }

        # If the file already exists and NoClobber was specified, do not write to the log.
        if ((Test-Path $Path) -and $NoClobber) {
            throw "Log file $Path already exists and NoClobber was specified."
        }

        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        if (-not (Test-Path $Path)) {
            Write-Verbose "Creating $Path." 
            New-Item $Path -Force -ItemType File | Out-Null
        }

        # In-memory log buffer for this run (e.g. for Google Sheet logging) so we
        # don't have to re-read the file. Ordered, append-only, one object per entry.
        if ($null -eq $script:Logs) {
            $script:Logs = [System.Collections.Generic.List[PSCustomObject]]::new()
        }

    } 
    Process 
    { 
        # If verbose logging is disabled and the log level is set to Info or Trace, skip writing to the log file. This allows us to write Info messages without enabling verbose logging for the entire script.
        if ($skip) { return }

        # Format Date for our Log File 
        $MessageTime = Get-Date
        $FormattedDate = $MessageTime.ToString("yyyy-MM-dd HH:mm:ss")
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
            } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
            } 
            'Info' { 
                $LevelText = 'INFO:' 
                Write-Verbose "$($LevelText) $($Message)"
            } 
            'Trace' {
                $LevelText = 'TRACE:'
                Write-Verbose "$($LevelText) $($Message)"
            }
        }

        # Add to log variable for potential use elsewhere in the script (e.g. for Google Sheet logging) without having to read from the log file.
        $script:Logs.Add([PSCustomObject]@{
            Timestamp = $FormattedDate
            Level     = $Level
            Message   = $Message
        })
         
        # Write log entry to $Path 
        "$FormattedDate $LevelText $Message" | Out-File -FilePath $Path -Append 
    } 
    End { } 
}