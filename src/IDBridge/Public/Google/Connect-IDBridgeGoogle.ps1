<#
.SYNOPSIS
Acquire the Google Workspace bearer token for this session from the vault-stored
service-account key.

.DESCRIPTION
Reads the service-account key JSON from the IDBridge secret vault (secret
'GoogleAuth-ServiceAccount'; no file fallback), validates it contains a private_key, and
exchanges a domain-wide-delegation JWT for a bearer token via Get-GoogleApiAccessToken
(impersonating GoogleToken.adminEmail). The scopes come from the module itself
(Get-IDBridgeGoogleScope) — directory user/orgunit/group + Sheets, plus apps.licensing
unless Google.enableLicenseRemoval = $false. The resulting auth headers are stored
script-scoped and read everywhere via Get-GoogleHeaders.

Invoke-IDBridge calls this at the start of every run (when GoogleToken.Enabled). It is
also useful standalone: after seeding the key or granting domain-wide delegation, running
it verifies the whole Google auth chain without a pipeline run — an 'unauthorized_client'
error means the DWD grant (client ID or scopes) doesn't match.

Requires an initialized session (Initialize-IDBridge). Throws on any failure — a run that
cannot authenticate to Google fails rather than degrading.

.OUTPUTS
None. Sets the script-scoped Google auth headers (read via Get-GoogleHeaders).

.EXAMPLE
Connect-IDBridgeGoogle   # verify auth end-to-end after bootstrap/DWD changes

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-03
#>
function Connect-IDBridgeGoogle {
    [CmdletBinding()]
    param ()

    $IDConfig = Get-IDBridgeConfig

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

    try {
        $paramsGoogleHeaders = @{
            ServiceAccountKeyJson = $googleAuthJson
            Scope                 = Get-IDBridgeGoogleScope
            TargetUserEmail      = $IDConfig.GoogleToken.adminEmail
        }

        $script:GoogleHeaders = Get-GoogleApiAccessToken @paramsGoogleHeaders
    }
    catch { Throw }

    Write-Log -Message "Google: Connected (token acquired for $($IDConfig.GoogleToken.adminEmail))." -Level Trace
}
