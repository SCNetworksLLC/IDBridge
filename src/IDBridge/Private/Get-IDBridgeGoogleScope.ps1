<#
.SYNOPSIS
Return the OAuth scopes IDBridge requests from Google (internal).

.DESCRIPTION
Internal helper — the scope list is a property of the module's code (which APIs it calls),
not site configuration, so it lives here instead of the config file. Returns the
space-separated scope string for the domain-wide-delegation token request:

  - Always: Admin SDK directory user/orgunit/group + Sheets.
  - apps.licensing: included unless Google.enableLicenseRemoval = $false (the feature is on
    by default) — with DWD, requesting a scope the grant doesn't include fails the whole
    token exchange, so disabling the feature also drops the scope.

-All returns every scope the module can ever use (licensing included, unconditionally) —
used by the bootstrap's domain-wide delegation checklist, so the grant is future-proof and
enabling license removal later needs no Admin-console change.

.PARAMETER All
Return the full scope set regardless of config (for DWD grants, not token requests).

.EXAMPLE
$scope = Get-IDBridgeGoogleScope

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-03
#>
function Get-IDBridgeGoogleScope {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [switch]$All
    )

    $scopes = @(
        'https://www.googleapis.com/auth/admin.directory.user'
        'https://www.googleapis.com/auth/admin.directory.orgunit'
        'https://www.googleapis.com/auth/admin.directory.group'
        'https://www.googleapis.com/auth/spreadsheets'
    )

    if ($All -or (Get-IDBridgeConfig).Google.enableLicenseRemoval -ne $false) {
        $scopes += 'https://www.googleapis.com/auth/apps.licensing'
    }

    return ($scopes -join ' ')
}
