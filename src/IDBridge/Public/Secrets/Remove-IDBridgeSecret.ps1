<#
.SYNOPSIS
Delete a named secret from the IDBridge secret vault.

.DESCRIPTION
Removes the secret's envelope file (<Name>.secret.json) from the vault folder. When
Secrets.Provider is 'AzKeyVault' the secret is deleted from Azure Key Vault instead (a
soft delete when the vault has it enabled). Throws when the secret does not exist. The
value is unrecoverable after removal — re-seed with Set-IDBridgeSecret if needed.

.PARAMETER Name
The secret name to remove (e.g. 'ApiKey-Passphrase').

.EXAMPLE
Remove-IDBridgeSecret -Name 'ApiKey-Passphrase'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Remove-IDBridgeSecret {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    $IDConfig = Get-IDBridgeConfig
    $Provider = if ($IDConfig.Secrets -and $IDConfig.Secrets.Provider) { $IDConfig.Secrets.Provider } else { 'Cms' }

    if ($Provider -eq 'AzKeyVault') {
        # Remote provider: delete from Azure Key Vault
        $context = Get-IDBridgeAzKeyVaultContext

        try {
            $null = Invoke-RestMethod -Headers $context.Headers -Uri "$($context.VaultUri)secrets/${Name}?api-version=$($context.ApiVersion)" -Method Delete -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 404) {
                throw "IDBridge secret '$Name' was not found in Azure Key Vault '$($context.VaultUri)'."
            }
            throw "Error removing secret '$Name' from Azure Key Vault '$($context.VaultUri)': $($_)"
        }

        Write-Log -Message "Secret: Removed '$Name' from Azure Key Vault '$($context.VaultUri)'." -Level Info
        return
    }

    $vaultPath = $IDConfig.Paths.VaultRoot
    $envelopePath = Join-Path $vaultPath "$Name.secret.json"

    if (-not (Test-Path $envelopePath)) {
        throw "IDBridge secret '$Name' was not found in vault '$vaultPath'."
    }

    Remove-Item -Path $envelopePath -Force
    Write-Log -Message "Secret: Removed '$Name' from vault '$vaultPath'." -Level Info
}
