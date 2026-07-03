<#
.SYNOPSIS
Retrieve a named IDBridge secret from the IDBridge secret vault.

.DESCRIPTION
Centralizes how IDBridge reads secrets (API keys, tokens, nonces, the Google service-account
key). Secrets live as encrypted JSON envelope files (<Name>.secret.json) in the vault folder
(Paths.VaultRoot, <Root>\Vault); there is no external-module dependency and no unlock step.
Use Set-IDBridgeSecret to add or change secrets.

Each envelope records the provider that protected it, so reads work for any mix of providers:

  - Cms     : decrypted with Unprotect-CmsMessage; requires the 'IDBridge Secrets'
              certificate private key on this machine (see New-IDBridgeSecretCertificate).
  - DpapiNG : decrypted with DPAPI-NG; requires running as a principal named in the
              protection descriptor (e.g. the gMSA) on a domain-joined host.

Exception: when Secrets.Provider is 'AzKeyVault' there are no local envelopes — the secret
is fetched from Azure Key Vault over REST (Secrets.AzKeyVault config block) under the same
name.

Returns a [SecureString] by default. Use -AsPlainText to get the unprotected string.

.PARAMETER Name
The secret name (e.g. 'ApiKey-Passphrase').

.PARAMETER AsPlainText
Return the secret as a plain [string] instead of a [SecureString].

.EXAMPLE
$token = Get-IDBridgeSecret -Name 'ApiKey-Passphrase'

.EXAMPLE
$secret = Get-IDBridgeSecret -Name 'ApiKey-SkywardSMS' -AsPlainText

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Get-IDBridgeSecret {
    [CmdletBinding()]
    [OutputType([securestring], [string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [switch]$AsPlainText
    )

    $IDConfig = Get-IDBridgeConfig
    $Provider = if ($IDConfig.Secrets -and $IDConfig.Secrets.Provider) { $IDConfig.Secrets.Provider } else { 'Cms' }

    if ($Provider -eq 'AzKeyVault') {
        # Remote provider: no local envelope, fetch straight from Azure Key Vault
        $context = Get-IDBridgeAzKeyVaultContext

        Write-Log -Message "Secret: Retrieving '$Name' from Azure Key Vault '$($context.VaultUri)'." -Level Trace

        try {
            $plainValue = (Invoke-RestMethod -Headers $context.Headers -Uri "$($context.VaultUri)secrets/${Name}?api-version=$($context.ApiVersion)" -Method Get -ErrorAction Stop).value
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 404) {
                throw "IDBridge secret '$Name' was not found in Azure Key Vault '$($context.VaultUri)'. Add it with: Set-IDBridgeSecret -Name '$Name'."
            }
            throw "IDBridge secret '$Name' could not be read from Azure Key Vault '$($context.VaultUri)' ($_). Check the app registration's Key Vault access (e.g. the 'Key Vault Secrets User' role)."
        }
    }
    else {
        $vaultPath = $IDConfig.Paths.VaultRoot
        $envelopePath = Join-Path $vaultPath "$Name.secret.json"

        if (-not (Test-Path $envelopePath)) {
            throw "IDBridge secret '$Name' was not found in vault '$vaultPath'. Add it with: Set-IDBridgeSecret -Name '$Name'."
        }

        try { $envelope = Get-Content -Path $envelopePath -Raw | ConvertFrom-Json }
        catch { throw "IDBridge secret '$Name' has an unreadable envelope file at '$envelopePath' ($_)." }

        Write-Log -Message "Secret: Retrieving '$Name' from vault '$vaultPath' (provider $($envelope.provider))." -Level Trace

        try {
            switch ($envelope.provider) {
                'Cms' {
                    $plainValue = Unprotect-CmsMessage -Content $envelope.data -ErrorAction Stop
                }
                'DpapiNG' {
                    Import-IDBridgeDpapiNGType
                    $bytes = [IDBridge.DpapiNG]::Unprotect([System.Convert]::FromBase64String($envelope.data))
                    $plainValue = [System.Text.Encoding]::UTF8.GetString($bytes)
                }
                default { throw "unknown provider '$($envelope.provider)' in the envelope" }
            }
        }
        catch {
            throw "IDBridge secret '$Name' could not be decrypted ($_). Cms secrets need the 'IDBridge Secrets' certificate private key on this machine; DpapiNG secrets must be read as a principal named in the protection descriptor '$($envelope.protectedTo)'."
        }
    }

    if ($AsPlainText) {
        return $plainValue
    }

    return (ConvertTo-SecureString -String $plainValue -AsPlainText -Force)
}
