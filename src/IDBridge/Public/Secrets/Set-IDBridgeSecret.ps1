<#
.SYNOPSIS
Add or change a named secret in the IDBridge secret vault.

.DESCRIPTION
The way to populate the IDBridge vault. Encrypts the value and writes it as a JSON envelope
file (<Name>.secret.json) in the vault folder (Paths.VaultRoot, <Root>\Vault). The
encryption provider comes from the Secrets.Provider config value:

  - Cms (default) : Protect-CmsMessage with the Document Encryption certificate named by
                    Secrets.Cms.Thumbprint (or the single 'CN=IDBridge Secrets' certificate).
                    Create the certificate with New-IDBridgeSecretCertificate.
  - DpapiNG       : DPAPI-NG; protected to the AD principal named by
                    Secrets.DpapiNG.ProtectionDescriptor (e.g. 'SID=<gMSA SID>') so that
                    principal can read it on any domain-joined host. When no descriptor is
                    configured the secret is protected to the current account only (logged
                    as a warning).
  - AzKeyVault    : remote — the secret is written to Azure Key Vault over REST (no local
                    envelope), under the same name. Auth is an Entra app registration with
                    a certificate credential (Secrets.AzKeyVault config block). Key Vault
                    names allow only letters, numbers, and dashes.

The envelope records which provider protected it, so Get-IDBridgeSecret reads any mix of
providers from the same vault. Re-running with the same -Name overwrites the existing value.

Requires an initialized session (Initialize-IDBridge) because it reads config and logs via
Write-Log — the same contract as Get-IDBridgeSecret.

.PARAMETER Name
The secret name to store (e.g. 'ApiKey-Passphrase').

.PARAMETER Secret
The secret value as a SecureString. When omitted (and no -InFile) you are prompted to enter
it (masked).

.PARAMETER InFile
Store the raw content of a file as the secret value — e.g. the Google service-account JSON
key: Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -InFile C:\path\key.json

.EXAMPLE
Set-IDBridgeSecret -Name 'ApiKey-Passphrase'

.EXAMPLE
Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -InFile 'C:\IDBridge\Auth\key.json'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Set-IDBridgeSecret {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name,

        [Parameter()]
        [System.Security.SecureString]$Secret,

        [Parameter()]
        [string]$InFile
    )

    $IDConfig = Get-IDBridgeConfig
    $secretsConfig = $IDConfig.Secrets

    $Provider = if ($secretsConfig -and $secretsConfig.Provider) { $secretsConfig.Provider } else { 'Cms' }

    # Resolve the value to protect: a file's raw content, the supplied SecureString, or a masked prompt.
    if ($InFile) {
        if (-not (Test-Path $InFile)) { Throw "Set-IDBridgeSecret: file not found: $InFile" }
        $plainValue = Get-Content -Path $InFile -Raw
    }
    else {
        if (-not $Secret) {
            $Secret = Read-Host -Prompt "Enter value for secret '$Name'" -AsSecureString
        }
        $plainValue = ConvertFrom-SecureString -SecureString $Secret -AsPlainText
    }

    # Remote provider: write straight to Azure Key Vault, no local envelope
    if ($Provider -eq 'AzKeyVault') {
        if ($Name -notmatch '^[0-9a-zA-Z-]+$') {
            Throw "Secret name '$Name' is not valid for Azure Key Vault: names allow only letters, numbers, and dashes."
        }
        $context = Get-IDBridgeAzKeyVaultContext

        try {
            $null = Invoke-RestMethod -Headers $context.Headers -Uri "$($context.VaultUri)secrets/${Name}?api-version=$($context.ApiVersion)" -Method Put -Body (@{ value = $plainValue } | ConvertTo-Json) -ContentType 'application/json' -ErrorAction Stop
        }
        catch { Throw "Error storing secret '$Name' in Azure Key Vault '$($context.VaultUri)' ($_). Writes need the app registration to hold a write-capable role (e.g. 'Key Vault Secrets Officer')." }

        Write-Log -Message "Secret: Stored '$Name' in Azure Key Vault '$($context.VaultUri)'." -Level Info
        return
    }

    try {
        switch ($Provider) {
            'Cms' {
                $cert = Resolve-IDBridgeCmsCertificate
                $data = Protect-CmsMessage -To $cert -Content $plainValue -ErrorAction Stop
                $protectedTo = "Thumbprint=$($cert.Thumbprint)"
            }
            'DpapiNG' {
                $descriptor = if ($secretsConfig -and $secretsConfig.DpapiNG) { $secretsConfig.DpapiNG.ProtectionDescriptor } else { $null }
                if (-not $descriptor) {
                    $descriptor = "SID=$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)"
                    Write-Log -Message "Secret: No DpapiNG ProtectionDescriptor configured; '$Name' will be protected to the current account only." -Level Warn
                }
                Import-IDBridgeDpapiNGType
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($plainValue)
                $data = [System.Convert]::ToBase64String([IDBridge.DpapiNG]::Protect($descriptor, $bytes))
                $protectedTo = $descriptor
            }
            default {
                Throw "Unknown secrets provider '$Provider'. Valid values: Cms, DpapiNG, AzKeyVault."
            }
        }
    }
    catch { Throw "Error protecting secret '$Name' with provider '$Provider': $($_)" }

    $vaultPath = $IDConfig.Paths.VaultRoot
    if (-not (Test-Path $vaultPath)) { New-Item -ItemType Directory -Path $vaultPath -Force | Out-Null }

    $envelope = [ordered]@{
        name        = $Name
        provider    = $Provider
        protectedTo = $protectedTo
        created     = (Get-Date).ToString('o')
        data        = $data
    }
    $envelopePath = Join-Path $vaultPath "$Name.secret.json"
    $envelope | ConvertTo-Json | Set-Content -Path $envelopePath -Encoding utf8

    Write-Log -Message "Secret: Stored '$Name' in vault '$vaultPath' (provider $Provider)." -Level Info
}
