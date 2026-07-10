<#
.SYNOPSIS
Acquire the Google Workspace bearer token for this session from the vault-stored
service-account key.

.DESCRIPTION
Reads the service-account key JSON from the IDBridge secret vault (secret
'GoogleAuth-ServiceAccount'; no file fallback), validates it contains a private_key, and
exchanges a JWT for a bearer token via Get-GoogleApiAccessToken. The token is issued to
the service account ITSELF — no user impersonation or domain-wide delegation. Admin SDK
calls are authorized by the Google Workspace admin role assigned to the service account
(created by Initialize-IDBridgeGoogleServiceAccount); Sheets access comes from sharing
the sheets with the service account's email. The scopes come from the module itself
(Get-IDBridgeGoogleScope) — directory user/orgunit/group + Sheets, plus apps.licensing
unless Google.enableLicenseRemoval = $false. The resulting auth headers are stored
script-scoped and read everywhere via Get-GoogleHeaders; the service account's email
(client_email from the key) is stored alongside and read via
Get-IDBridgeGoogleServiceAccountEmail.

Invoke-IDBridge calls this at the start of every run (when GoogleToken.Enabled). It is
also useful standalone: after seeding the key or assigning the admin role, running it
verifies the whole Google auth chain without a pipeline run. A 403 on later API calls
means the role assignment is missing or hasn't propagated yet; a Sheets 403 usually means
the sheet isn't shared with the service account.

Requires an initialized session (Initialize-IDBridge). Throws on any failure — a run that
cannot authenticate to Google fails rather than degrading.

.OUTPUTS
None. Sets the script-scoped Google auth headers (read via Get-GoogleHeaders).

.EXAMPLE
Connect-IDBridgeGoogle   # verify auth end-to-end after bootstrap/role changes

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-03
#>
function Connect-IDBridgeGoogle {
    [CmdletBinding()]
    param ()

    # Read the service-account key JSON from the IDBridge secret vault (no file fallback)
    try {
        $googleAuthJson = Get-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -AsPlainText
    }
    catch {
        Throw "The Google service-account key could not be read from the secret vault. Seed it with: Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -InFile <key.json>. ($_)"
    }

    # Validate it is a valid Google Service Account JSON by checking for a private key
    try {
        $googleAuthContent = $googleAuthJson | ConvertFrom-Json
    }
    catch {
        Throw "The 'GoogleAuth-ServiceAccount' secret is not valid JSON. Error: $_"
    }

    if ($googleAuthContent.PSObject.Properties.Name -notcontains "private_key") {
        throw "The Google Auth JSON does not contain a valid 'private_key'."
    }

    Write-Log -Message "Loaded Google service-account key from secret 'GoogleAuth-ServiceAccount'" -Level Trace

    $script:GoogleServiceAccountEmail = $googleAuthContent.client_email

    try {
        $paramsGoogleHeaders = @{
            ServiceAccountKeyJson = $googleAuthJson
            Scope                 = Get-IDBridgeGoogleScope
        }

        $script:GoogleHeaders = Get-GoogleApiAccessToken @paramsGoogleHeaders
    }
    catch { Throw }

    Write-Log -Message "Google: Connected (token acquired for $($script:GoogleServiceAccountEmail))." -Level Trace
}
