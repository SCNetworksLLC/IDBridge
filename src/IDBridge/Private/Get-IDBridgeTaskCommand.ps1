<#
.SYNOPSIS
Build the pwsh argument string the IDBridge scheduled task runs (internal).

.DESCRIPTION
Internal helper for Register-IDBridgeScheduledTask: returns the full -Argument text for the
task's pwsh action. By default the task imports IDBridge by name, so every run loads the
newest version installed for all users and Update-Module alone picks up a new release. With
-ModulePath the task imports that one manifest instead - an explicit pin. Uses no module
state or Write-Log.

.PARAMETER RootPath
Runtime root the task passes to Invoke-IDBridge -RootPath.

.PARAMETER ModulePath
Path to an IDBridge.psd1 manifest to pin the task to. Omit it to import IDBridge by name.

.OUTPUTS
[string] the pwsh argument string.

.EXAMPLE
Get-IDBridgeTaskCommand -RootPath 'C:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-09-25
#>
function Get-IDBridgeTaskCommand {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter()]
        [string]$ModulePath
    )

    $importCommand = if ($ModulePath) { "Import-Module '$ModulePath'" } else { "Import-Module IDBridge" }
    return "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$importCommand; Invoke-IDBridge -RootPath '$RootPath'`""
}
