function Initialize-Logging {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $LogFileLocation
    )

    Set-Variable -Name "logDate" -Value (Get-Date -Format "yyyy-MM-dd-HH.mm.ss") -Scope global

    Set-Variable -Name "logFile" -Value $LogFileLocation -Scope global

    if ((Get-Item $logFile).Length -gt 1000000) {
        Rename-Item $logFile ((Get-Item $logfile).BaseName + "_" + $logDate + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $logDate ########" -Path $logFile
}