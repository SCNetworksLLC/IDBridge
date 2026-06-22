<# 
.Synopsis 
   Write-Log writes a message to a specified log file with the current time stamp. 
.DESCRIPTION 
   The Write-Log function is designed to add logging capability to other scripts. 
   In addition to writing output and/or verbose you can write to a log file for 
   later debugging. 
.NOTES 
   Created by: Jason Wasser @wasserja 
   Modified: 11/24/2015 09:30:19 AM   
 
   Changelog: 
    * Code simplification and clarification - thanks to @juneb_get_help 
    * Added documentation. 
    * Renamed LogPath parameter to Path to keep it standard - thanks to @JeffHicks 
    * Revised the Force switch to work as it should - thanks to @JeffHicks 
 
   To Do: 
    * Add error handling if trying to create a log file in a inaccessible location. 
    * Add ability to write $Message to $Verbose or $Error pipelines to eliminate 
      duplicates. 
.PARAMETER Message 
   Message is the content that you wish to add to the log file.  
.PARAMETER Path 
   The path to the log file to which you would like to write. By default the function will  
   create the path and file if it does not exist.  
.PARAMETER Level 
   Specify the criticality of the log information being written to the log (i.e. Error, Warning, Informational) 
.PARAMETER NoClobber 
   Use NoClobber if you do not wish to overwrite an existing file. 
.EXAMPLE 
   Write-Log -Message 'Log message'  
   Writes the message to c:\Logs\PowerShellLog.log. 
.EXAMPLE 
   Write-Log -Message 'Restarting Server.' -Path c:\Logs\Scriptoutput.log 
   Writes the content to the specified log file and creates the path and file specified.  
.EXAMPLE 
   Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error 
   Writes the message to the specified log file as an error message, and writes the message to the error pipeline. 
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