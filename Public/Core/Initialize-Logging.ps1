function Initialize-Logging {
    [cmdletbinding()]
    Param()

    $logFile = "C:\IDBridge\Logs\IDBridge.log"

    if ((Get-Item $logFile).Length -gt 50000000) {
        Rename-Item $logFile ((Get-Item $logfile).BaseName + "_" + $logDate + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $logDate ########" -Path $logFile
}