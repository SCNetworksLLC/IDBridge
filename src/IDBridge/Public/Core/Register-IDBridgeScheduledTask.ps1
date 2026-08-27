<#
.SYNOPSIS
Register the scheduled task that runs Invoke-IDBridge as the gMSA.

.DESCRIPTION
Host-side follow-up to Initialize-IDBridgeADServiceAccount. Run it elevated on the
machine that runs IDBridge. Each step is idempotent, so re-running (e.g. to change the
trigger time) is safe. Steps:

  1. Installs and verifies the gMSA on this computer (Install-ADServiceAccount +
     Test-ADServiceAccount). When the computer was only just allowed to retrieve the
     password, this fails until the computer's Kerberos tickets refresh — the error says
     so ('klist -li 0x3e7 purge' or a reboot fixes it).
  2. Grants the gMSA the filesystem rights a run needs: read on the module folder and
     the runtime root (config, plugins, vault), modify on Logs, Exports, and Data.
  3. Registers (or replaces) a daily Task Scheduler task that runs
     'Invoke-IDBridge -RootPath <root>' in pwsh as the gMSA. The principal uses
     -LogonType Password — Task Scheduler retrieves the gMSA's password from AD, nothing
     is stored. A missed trigger (machine off/rebooting) runs as soon as possible after.

Task Scheduler grants the account the 'Log on as a batch job' right locally when the
task is registered; if a GPO manages that right, add the gMSA to it there or the task
will not start. Requires an initialized session (Initialize-IDBridge) and the
ActiveDirectory RSAT module.

.PARAMETER AccountName
gMSA name without the trailing $. Defaults to 'gMSA-IDBridge' — the same default
Initialize-IDBridgeADServiceAccount creates.

.PARAMETER TaskName
Name of the scheduled task. Defaults to 'IDBridge Sync'. An existing task with this name
is replaced.

.PARAMETER DailyAt
Time of day for the daily trigger. Defaults to 05:00.

.PARAMETER RootPath
Runtime root the task passes to Invoke-IDBridge -RootPath. Defaults to this session's
root (Paths.Root).

.PARAMETER ModulePath
Path to the IDBridge.psd1 manifest the task imports. Defaults to the currently loaded
module's manifest.

.EXAMPLE
Register-IDBridgeScheduledTask

.EXAMPLE
Register-IDBridgeScheduledTask -DailyAt '22:30'

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
        [datetime]$DailyAt = '05:00',

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

    $ticketHint = "If this computer was only just allowed to retrieve the password, refresh its Kerberos tickets first ('klist -li 0x3e7 purge' elevated, or reboot) and re-run."
    try { Install-ADServiceAccount -Identity $AccountName -ErrorAction Stop }
    catch { Throw "Installing gMSA '$gmsaIdentity' on $($env:COMPUTERNAME) failed. $ticketHint $($_)" }
    if (-not (Test-ADServiceAccount -Identity $AccountName)) {
        Throw "Test-ADServiceAccount failed for '$gmsaIdentity' on $($env:COMPUTERNAME). $ticketHint"
    }
    Write-Log -Message "Task: gMSA '$gmsaIdentity' is installed and usable on $($env:COMPUTERNAME)."
    #endregion Install and verify the gMSA on this computer

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
    $trigger = New-ScheduledTaskTrigger -Daily -At $DailyAt
    $principal = New-ScheduledTaskPrincipal -UserId $gmsaIdentity -LogonType Password -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    try {
        $task = Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
    }
    catch { Throw "Registering scheduled task '$TaskName' failed (elevated session required): $($_)" }

    $registeredVerb = if ($existing) { "Replaced" } else { "Registered" }
    Write-Log -Message "Task: $registeredVerb scheduled task '$TaskName' - daily at $($DailyAt.ToString('HH:mm')) as '$gmsaIdentity'."
    #endregion Register the scheduled task

    Write-Host "Scheduled task '$TaskName' runs Invoke-IDBridge daily at $($DailyAt.ToString('HH:mm')) as '$gmsaIdentity'." -ForegroundColor Green
    Write-Host "If a GPO manages 'Log on as a batch job', add '$gmsaIdentity' to it - Task Scheduler's local grant is overridden by GPO."
    Write-Host "Test it now with: Start-ScheduledTask -TaskName '$TaskName' (with Debug.ReadOnly = `$true for a safe first run)."
    return $task
}
