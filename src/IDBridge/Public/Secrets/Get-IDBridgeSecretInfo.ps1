<#
.SYNOPSIS
List the secrets stored in the IDBridge secret vault (names and metadata, never values).

.DESCRIPTION
Reads every envelope file (*.secret.json) in the vault folder and returns one object per
secret with its name, protecting provider, protection target, and creation time. When
Secrets.Provider is 'AzKeyVault' the secrets are listed from Azure Key Vault instead —
note that lists everything the app registration can see in that vault, not only IDBridge's
names. Use it to confirm what is stored after seeding with Set-IDBridgeSecret. Values are
never decrypted or returned — use Get-IDBridgeSecret for that.

.OUTPUTS
[PSCustomObject] with Name, Provider, ProtectedTo, Created, and Path per secret.

.EXAMPLE
Get-IDBridgeSecretInfo

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Get-IDBridgeSecretInfo {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    $IDConfig = Get-IDBridgeConfig
    $Provider = if ($IDConfig.Secrets -and $IDConfig.Secrets.Provider) { $IDConfig.Secrets.Provider } else { 'Cms' }

    if ($Provider -eq 'AzKeyVault') {
        # Remote provider: list from Azure Key Vault, following paging links
        $context = Get-IDBridgeAzKeyVaultContext
        $uri = "$($context.VaultUri)secrets?maxresults=25&api-version=$($context.ApiVersion)"

        while ($uri) {
            try { $page = Invoke-RestMethod -Headers $context.Headers -Uri $uri -Method Get -ErrorAction Stop }
            catch { Throw "Error listing secrets in Azure Key Vault '$($context.VaultUri)': $($_)" }

            foreach ($item in $page.value) {
                [PSCustomObject]@{
                    Name        = ($item.id -split '/secrets/')[-1]
                    Provider    = 'AzKeyVault'
                    ProtectedTo = $context.VaultUri
                    Created     = ([DateTimeOffset]::FromUnixTimeSeconds($item.attributes.created)).LocalDateTime.ToString('o')
                    Path        = $item.id
                }
            }
            $uri = $page.nextLink
        }
        return
    }

    $vaultPath = $IDConfig.Paths.VaultRoot
    if (-not (Test-Path $vaultPath)) { return }

    foreach ($file in (Get-ChildItem -Path $vaultPath -Filter *.secret.json -File | Sort-Object Name)) {
        $envelope = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
        [PSCustomObject]@{
            Name        = $envelope.name
            Provider    = $envelope.provider
            ProtectedTo = $envelope.protectedTo
            Created     = $envelope.created
            Path        = $file.FullName
        }
    }
}
