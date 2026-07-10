<#
.SYNOPSIS
Return the OAuth scopes IDBridge requests from Google (internal).

.DESCRIPTION
Internal helper — the scope list is a property of the module's code (which APIs it calls),
not site configuration, so it lives here instead of the config file. Returns the
space-separated scope string for the service account's token request (the token is issued
to the service account itself; authorization comes from its assigned admin role):

  - Always: Admin SDK directory user/orgunit/group + Sheets.
  - apps.licensing: included unless Google.enableLicenseRemoval = $false (the feature is on
    by default).

.EXAMPLE
$scope = Get-IDBridgeGoogleScope

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-10
#>
function Get-IDBridgeGoogleScope {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    $scopes = @(
        'https://www.googleapis.com/auth/admin.directory.user'
        'https://www.googleapis.com/auth/admin.directory.orgunit'
        'https://www.googleapis.com/auth/admin.directory.group'
        'https://www.googleapis.com/auth/spreadsheets'
    )

    if ((Get-IDBridgeConfig).Google.enableLicenseRemoval -ne $false) {
        $scopes += 'https://www.googleapis.com/auth/apps.licensing'
    }

    return ($scopes -join ' ')
}
