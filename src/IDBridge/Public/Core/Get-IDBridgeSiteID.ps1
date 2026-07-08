<#
.SYNOPSIS
Return the install's telemetry SiteID, generating it on first use.

.DESCRIPTION
Reads the SiteID from <ConfigRoot>\IDBridgeSiteID.json, creating the file with a new
random GUID if it does not exist or is invalid. The SiteID identifies this INSTALL —
never a person or a district. It is random (New-Guid), never derived from the district
name, hostname, or any other real-world value, and it is only transmitted at the
Enhanced telemetry tier (see PRIVACY.md).

The file is intentionally stored unencrypted beside the config: the SiteID is not a
secret, and keeping it with the config means it survives a server migration along with
the rest of the install (preserving the run timeline in the Pulse dashboard). When
CLONING a config folder to stand up a separate install, delete IDBridgeSiteID.json in
the copy so it generates its own SiteID.

Districts use this value to claim their install in the Pulse dashboard.

.OUTPUTS
[string] the SiteID GUID.

.EXAMPLE
Get-IDBridgeSiteID

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-06
#>
function Get-IDBridgeSiteID {
    [CmdletBinding()]
    param ()

    $IDConfig = Get-IDBridgeConfig
    $siteIDFile = Join-Path $IDConfig.Paths.ConfigRoot "IDBridgeSiteID.json"

    if (Test-Path $siteIDFile) {
        $siteID = (Get-Content -Path $siteIDFile -Raw | ConvertFrom-Json).SiteID
        if ($siteID -as [guid]) {
            return $siteID
        }
        Write-Log -Message "Telemetry: SiteID file is invalid and will be regenerated: $siteIDFile" -Level Warn
    }

    # Generated once per install. A regeneration (missing/invalid file) starts a new timeline
    # in the Pulse dashboard, so log it to make the discontinuity explainable later.
    $siteID = (New-Guid).Guid
    @{ SiteID = $siteID; Created = (Get-Date -Format "yyyy-MM-dd-HH.mm.ss") } | ConvertTo-Json | Set-Content -Path $siteIDFile
    Write-Log -Message "Telemetry: Generated new SiteID $siteID ($siteIDFile)"

    return $siteID
}
