<#
.SYNOPSIS
Return the GCP project ID of the IDBridge Google service account.

.DESCRIPTION
Accessor for the service account's GCP project ID (project_id from the vault-stored key
JSON). Connect-IDBridgeGoogle stores it script-scoped at connect time; when called before a
connect (e.g. interactively, to find the project in the Cloud console or to re-run
Initialize-IDBridgeGoogleServiceAccount against it), it falls back to reading the
'GoogleAuth-ServiceAccount' secret from the vault and parsing the field — so it needs an
initialized session (Initialize-IDBridge) but not a live token. Throws if the secret is
missing (via Get-IDBridgeSecret).

.OUTPUTS
[string] The GCP project ID, e.g. 'idbridge-123456'.

.EXAMPLE
Get-IDBridgeGoogleProjectId   # which GCP project does this install use?

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-10
#>
function Get-IDBridgeGoogleProjectId {
    [CmdletBinding()]
    [OutputType([string])]
    param ()

    if (-not $script:GoogleProjectId) {
        $keyJson = Get-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -AsPlainText
        $script:GoogleProjectId = ($keyJson | ConvertFrom-Json).project_id
    }
    return $script:GoogleProjectId
}
