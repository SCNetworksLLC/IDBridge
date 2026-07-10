<#
.SYNOPSIS
Return the email address of the IDBridge Google service account.

.DESCRIPTION
Accessor for the service account's email (client_email from the vault-stored key JSON).
Connect-IDBridgeGoogle stores it script-scoped at connect time; when called before a
connect (e.g. interactively, to know which address to share a sheet with), it falls back
to reading the 'GoogleAuth-ServiceAccount' secret from the vault and parsing the field —
so it needs an initialized session (Initialize-IDBridge) but not a live token. Throws if
the secret is missing (via Get-IDBridgeSecret).

.OUTPUTS
[string] The service account email, e.g. 'idbridge@idbridge-123456.iam.gserviceaccount.com'.

.EXAMPLE
Get-IDBridgeGoogleServiceAccountEmail   # who do I share the source sheet with?

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-10
#>
function Get-IDBridgeGoogleServiceAccountEmail {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    if (-not $script:GoogleServiceAccountEmail) {
        $keyJson = Get-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -AsPlainText
        $script:GoogleServiceAccountEmail = ($keyJson | ConvertFrom-Json).client_email
    }
    return $script:GoogleServiceAccountEmail
}
