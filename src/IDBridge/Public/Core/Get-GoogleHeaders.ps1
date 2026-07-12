<#
.SYNOPSIS
Return the Google API authorization headers acquired at startup.

.DESCRIPTION
Accessor for the script-scoped Google headers (bearer token + Accept) set by
Connect-IDBridgeGoogle (called by Invoke-IDBridge at run start when GoogleToken.Enabled).
Used by all Google API calls. Throws if Google authentication has not run
(e.g. GoogleToken.Enabled is $false or auth failed).

.OUTPUTS
[hashtable] @{ Authorization = 'Bearer <token>'; Accept = 'application/json' }.

.EXAMPLE
$headers = Get-GoogleHeaders

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleHeaders {
    if (-not $script:GoogleHeaders) {
        throw "Google token is not initialized. Call Initialize-IDBridge first."
    }
    return $script:GoogleHeaders
}