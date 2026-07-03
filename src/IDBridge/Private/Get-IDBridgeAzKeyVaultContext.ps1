<#
.SYNOPSIS
Resolve the Azure Key Vault connection details for the AzKeyVault secrets provider (internal).

.DESCRIPTION
Internal helper for the AzKeyVault secrets provider. Validates the Secrets.AzKeyVault config
block (VaultUri, TenantId, ClientId, CertThumbprint), acquires a bearer token via
Get-IDBridgeAzureAuthToken, and returns everything the secret functions need to call the
Key Vault REST API:

  @{ VaultUri = 'https://<vault>.vault.azure.net/'; ApiVersion = '7.4';
     Headers = @{ Authorization = 'Bearer ...' } }

The token is cached script-scoped for the session and refreshed 5 minutes before expiry.

.EXAMPLE
$context = Get-IDBridgeAzKeyVaultContext

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-02
#>
function Get-IDBridgeAzKeyVaultContext {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    $IDConfig = Get-IDBridgeConfig
    $kvConfig = if ($IDConfig.Secrets) { $IDConfig.Secrets.AzKeyVault } else { $null }

    foreach ($key in 'VaultUri', 'TenantId', 'ClientId', 'CertThumbprint') {
        if (-not $kvConfig -or -not $kvConfig.$key) {
            Throw "The AzKeyVault secrets provider requires Secrets.AzKeyVault.$key in IDBridgeConfig.psd1 (VaultUri, TenantId, ClientId, CertThumbprint)."
        }
    }

    $vaultUri = $kvConfig.VaultUri
    if (-not $vaultUri.EndsWith('/')) { $vaultUri += '/' }

    # Reuse the cached token until close to expiry
    if (-not $script:AzKeyVaultAuth -or (Get-Date) -ge $script:AzKeyVaultAuth.RefreshAfter) {
        $tokenResponse = Get-IDBridgeAzureAuthToken -ClientId $kvConfig.ClientId -TenantId $kvConfig.TenantId -CertThumbprint $kvConfig.CertThumbprint -Scope 'https://vault.azure.net/.default'
        $script:AzKeyVaultAuth = @{
            Headers      = @{ Authorization = "Bearer $($tokenResponse.access_token)" }
            RefreshAfter = (Get-Date).AddSeconds([int]$tokenResponse.expires_in - 300)
        }
    }

    return @{
        VaultUri   = $vaultUri
        ApiVersion = '7.4'
        Headers    = $script:AzKeyVaultAuth.Headers
    }
}
