<#
.SYNOPSIS
Check the PowerShell Gallery for a newer IDBridge release and log a warning if one exists.

.DESCRIPTION
Internal helper: queries the PowerShell Gallery for the latest stable IDBridge version
(prereleases excluded) and compares it to the running module version. A newer release logs
a Warn ("Update available... Run Update-Module IDBridge -Scope AllUsers", and the one-time
re-registration a task from before 26.9.25.0 needs) so it surfaces in the log file,
console, and Google Sheet log; an up-to-date install logs at Trace. Notify-only — nothing
is ever downloaded or installed. The gallery call has a 10 second timeout and any failure
throws to the caller, which is expected to swallow it (offline or gallery-blocked
environments must never affect the run).

.OUTPUTS
[bool] $true when a newer version is available, otherwise $false.

.EXAMPLE
try { Test-IDBridgeUpdateAvailable | Out-Null } catch { }

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-09-25
#>
function Test-IDBridgeUpdateAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $installedVersion = $MyInvocation.MyCommand.Module.Version

    #Gallery OData v2: IsLatestVersion returns the single latest stable release (no prereleases)
    $galleryUri = "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='IDBridge'&`$filter=IsLatestVersion"
    $response = Invoke-RestMethod -Uri $galleryUri -TimeoutSec 10 -ErrorAction Stop
    $latestVersion = [version](@($response)[0].properties.Version)

    if ($latestVersion -gt $installedVersion) {
        Write-Log -Message "Update available: IDBridge $latestVersion is on the PowerShell Gallery (installed: $installedVersion). Run Update-Module IDBridge -Scope AllUsers (elevated), then restart the session. A task registered before 26.9.25.0 imports one pinned version - run Register-IDBridgeScheduledTask -Enabled once after updating so it follows new releases on its own." -Level Warn
        return $true
    }

    Write-Log -Message "Update check: installed version $installedVersion is current." -Level Trace
    return $false
}
