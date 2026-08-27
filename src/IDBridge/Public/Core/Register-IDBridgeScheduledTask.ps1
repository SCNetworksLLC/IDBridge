<#
.SYNOPSIS
Register the scheduled task that runs Invoke-IDBridge as the gMSA.

.DESCRIPTION
Host-side follow-up to Initialize-IDBridgeADServiceAccount. Run it elevated on the
machine that runs IDBridge. Each step is idempotent, so re-running (e.g. to change the
interval) is safe. Steps:

  1. Installs and verifies the gMSA on this computer (Install-ADServiceAccount +
     Test-ADServiceAccount). When the computer was only just allowed to retrieve the
     password this fails on stale Kerberos tickets — the function purges the computer's
     tickets (klist -li 0x3e7 purge) and retries once before giving up (reboot if even
     that fails).
  2. Grants the gMSA the 'Log on as a batch job' right (SeBatchLogonRight) in the local
     security policy — required to start a scheduled task. When a GPO manages that
     right, the GPO's list overwrites the local grant on the next policy refresh: add
     the gMSA to the GPO instead (the function reminds you).
  3. Grants the gMSA the filesystem rights a run needs: read on the module folder and
     the runtime root (config, plugins, vault), modify on Logs, Exports, and Data.
  4. Registers (or replaces) a Task Scheduler task that runs
     'Invoke-IDBridge -RootPath <root>' in pwsh as the gMSA every -IntervalMinutes
     (default 15, aligned to midnight so runs land on predictable clock times). The
     principal uses -LogonType Password — Task Scheduler retrieves the gMSA's password
     from AD, nothing is stored. A still-running run is never overlapped (Task
     Scheduler's default), and a hung run is killed after 1 hour so the schedule
     recovers. The task is created DISABLED unless -Enabled is passed — review the
     config (Debug.ReadOnly first!), then Enable-ScheduledTask when ready.

Requires an initialized session (Initialize-IDBridge) and the ActiveDirectory RSAT
module.

.PARAMETER AccountName
gMSA name without the trailing $. Defaults to 'gMSA-IDBridge' — the same default
Initialize-IDBridgeADServiceAccount creates.

.PARAMETER TaskName
Name of the scheduled task. Defaults to 'IDBridge Sync'. An existing task with this name
is replaced.

.PARAMETER IntervalMinutes
Minutes between runs. Defaults to 15. Runs repeat indefinitely from midnight, so the
default lands on :00/:15/:30/:45.

.PARAMETER Enabled
Register the task enabled and running on schedule immediately. Without it the task is
created disabled — enable it with Enable-ScheduledTask once the config is reviewed.

.PARAMETER RootPath
Runtime root the task passes to Invoke-IDBridge -RootPath. Defaults to this session's
root (Paths.Root).

.PARAMETER ModulePath
Path to the IDBridge.psd1 manifest the task imports. Defaults to the currently loaded
module's manifest.

.EXAMPLE
Register-IDBridgeScheduledTask

.EXAMPLE
Register-IDBridgeScheduledTask -IntervalMinutes 60 -Enabled

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-27
#>
function Register-IDBridgeScheduledTask {
    [CmdletBinding()]
    [OutputType('Microsoft.Management.Infrastructure.CimInstance')]
    param (
        [Parameter()]
        [ValidateLength(1, 15)]
        [string]$AccountName = 'gMSA-IDBridge',

        [Parameter()]
        [string]$TaskName = 'IDBridge Sync',

        [Parameter()]
        [ValidateRange(5, 1440)]
        [int]$IntervalMinutes = 15,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [string]$RootPath,

        [Parameter()]
        [string]$ModulePath
    )

    $IDConfig = Get-IDBridgeConfig

    if (-not $RootPath) { $RootPath = $IDConfig.Paths.Root }
    if (-not $ModulePath) { $ModulePath = Join-Path (Get-Module -Name IDBridge).ModuleBase "IDBridge.psd1" }
    if (-not (Test-Path $ModulePath)) { Throw "Module manifest not found at '$ModulePath' - pass -ModulePath explicitly." }

    try { Import-Module -Name ActiveDirectory -ErrorAction Stop }
    catch { Throw "The ActiveDirectory PowerShell module (RSAT) is required: $($_)" }

    $domain = Get-ADDomain
    $gmsaIdentity = "$($domain.NetBIOSName)\$($AccountName)$"

    #region Install and verify the gMSA on this computer
    $gmsa = Get-ADServiceAccount -Filter "Name -eq '$AccountName'" -ErrorAction SilentlyContinue
    if (-not $gmsa) { Throw "gMSA '$AccountName' was not found in AD. Run Initialize-IDBridgeADServiceAccount first." }

    $installError = $null
    try { Install-ADServiceAccount -Identity $AccountName -ErrorAction Stop }
    catch { $installError = $_ }
    if ($installError -or -not (Test-ADServiceAccount -Identity $AccountName)) {
        #A just-created gMSA (or a just-allowed computer) fails until the computer's
        #Kerberos tickets refresh - purge them and try once more before giving up.
        Write-Log -Message "Task: gMSA '$gmsaIdentity' is not yet usable on $($env:COMPUTERNAME) - purging the computer's Kerberos tickets and retrying." -Level Warn
        & "$env:SystemRoot\System32\klist.exe" -li 0x3e7 purge | Out-Null
        try { Install-ADServiceAccount -Identity $AccountName -ErrorAction Stop }
        catch { Throw "Installing gMSA '$gmsaIdentity' on $($env:COMPUTERNAME) failed even after a Kerberos ticket purge - reboot and re-run. $($_)" }
        if (-not (Test-ADServiceAccount -Identity $AccountName)) {
            Throw "Test-ADServiceAccount still fails for '$gmsaIdentity' after a Kerberos ticket purge - reboot and re-run."
        }
    }
    Write-Log -Message "Task: gMSA '$gmsaIdentity' is installed and usable on $($env:COMPUTERNAME)."
    #endregion Install and verify the gMSA on this computer

    #Scheduled tasks need the 'Log on as a batch job' right; the grant is local, so a GPO
    #that manages the right still overrides it (noted at the end).
    Grant-IDBridgeBatchLogonRight -Identity $gmsaIdentity

    #region Grant the filesystem rights a run needs
    #Read the module and the whole runtime root (config, plugins, vault); write where a run writes.
    $fileSystemGrants = @(
        @{ Path = (Split-Path $ModulePath -Parent); Rights = 'ReadAndExecute' }
        @{ Path = $RootPath;                        Rights = 'ReadAndExecute' }
        @{ Path = (Join-Path $RootPath "Logs");     Rights = 'Modify' }
        @{ Path = (Join-Path $RootPath "Exports");  Rights = 'Modify' }
        @{ Path = (Join-Path $RootPath "Data");     Rights = 'Modify' }
    )
    foreach ($grant in $fileSystemGrants) {
        try {
            $acl = Get-Acl -Path $grant.Path
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($gmsaIdentity, $grant.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
            Set-Acl -Path $grant.Path -AclObject $acl
            Write-Log -Message "Task: Granted '$($grant.Rights)' on $($grant.Path) to '$gmsaIdentity'."
        }
        catch { Throw "Granting '$($grant.Rights)' on $($grant.Path) to '$gmsaIdentity' failed (elevated session required): $($_)" }
    }
    #endregion Grant the filesystem rights a run needs

    #region Register the scheduled task
    $pwsh = (Get-Command -Name pwsh.exe -ErrorAction SilentlyContinue).Source
    if (-not $pwsh) { Throw "pwsh.exe was not found on the PATH - IDBridge requires PowerShell 7.5+." }

    $action = New-ScheduledTaskAction -Execute $pwsh -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"Import-Module '$ModulePath'; Invoke-IDBridge -RootPath '$RootPath'`""
    #Anchored to midnight so the runs land on predictable clock times; no repetition
    #duration = repeat indefinitely.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
    $principal = New-ScheduledTaskPrincipal -UserId $gmsaIdentity -LogonType Password -RunLevel Limited
    #Task Scheduler's default already refuses to overlap a still-running instance; the
    #1-hour kill keeps a hung run from blocking the schedule for days.
    $settingsParams = @{ ExecutionTimeLimit = (New-TimeSpan -Hours 1) }
    if (-not $Enabled) { $settingsParams.Disable = $true }
    $settings = New-ScheduledTaskSettingsSet @settingsParams

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    try {
        $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
    }
    catch { Throw "Registering scheduled task '$TaskName' failed (elevated session required): $($_)" }

    $registeredVerb = if ($existing) { "Replaced" } else { "Registered" }
    $stateText = if ($Enabled) { "enabled" } else { "disabled" }
    Write-Log -Message "Task: $registeredVerb scheduled task '$TaskName' ($stateText) - every $IntervalMinutes minutes as '$gmsaIdentity'."
    #endregion Register the scheduled task

    Write-Host "Scheduled task '$TaskName' runs Invoke-IDBridge every $IntervalMinutes minutes as '$gmsaIdentity'." -ForegroundColor Green
    if (-not $Enabled) {
        Write-Host "The task is DISABLED. Review the config (start with Debug.ReadOnly = `$true), test with Start-ScheduledTask -TaskName '$TaskName', then: Enable-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Yellow
    }
    Write-Host "If a GPO manages 'Log on as a batch job', add '$gmsaIdentity' to it - the local grant is overwritten on the next policy refresh."
    return $task
}
