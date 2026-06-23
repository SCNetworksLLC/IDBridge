<#
.SYNOPSIS
Retrieve a named IDBridge secret, preferring a SecretManagement vault and falling back to the per-user file store.

.DESCRIPTION
Centralizes how IDBridge reads secrets (API keys, tokens, nonces). Resolution order:

1. SecretManagement vault - if the Microsoft.PowerShell.SecretManagement module is available
   and a vault is configured (via -VaultName, or the Secrets.VaultName config key) that
   contains a secret named <Name>, that value is returned.
2. File fallback - otherwise the secret is read from "<UserSecretsRoot>\<Name>.txt" (a
   SecureString exported with ConvertFrom-SecureString), which is the historical IDBridge
   behavior. This keeps existing deployments working with no changes.

Returns a [SecureString] by default. Use -AsPlainText to get the unprotected string.

.PARAMETER Name
The secret name. For the file fallback this is the file base name (e.g. 'ApiKey-Passphrase'
resolves to 'ApiKey-Passphrase.txt'). For the vault path this is the SecretManagement secret name.

.PARAMETER VaultName
Optional SecretManagement vault to read from. Defaults to the Secrets.VaultName config value
when present. Ignored if SecretManagement or the named vault is unavailable.

.PARAMETER AsPlainText
Return the secret as a plain [string] instead of a [SecureString].

.EXAMPLE
$token = Get-IDBridgeSecret -Name 'ApiKey-Passphrase'

.EXAMPLE
$secret = Get-IDBridgeSecret -Name 'ApiKey-SkywardSMS' -AsPlainText

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-22
#>
function Get-IDBridgeSecret {
    [CmdletBinding()]
    [OutputType([securestring], [string])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$VaultName,

        [Parameter()]
        [switch]$AsPlainText
    )

    $IDConfig = Get-IDBridgeConfig

    # Resolve vault name: explicit parameter wins, then the optional Secrets config block.
    if (-not $VaultName -and $IDConfig.Secrets) {
        $VaultName = $IDConfig.Secrets.VaultName
    }

    $secureValue = $null

    # 1) SecretManagement vault (best effort).
    if ($VaultName -and (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
        try {
            Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
            if (Get-SecretInfo -Name $Name -Vault $VaultName -ErrorAction SilentlyContinue) {
                Write-Log -Message "Secret: Retrieving '$Name' from vault '$VaultName'." -Level Trace
                $secureValue = Get-Secret -Name $Name -Vault $VaultName -ErrorAction Stop
            }
        }
        catch {
            Write-Log -Message "Secret: Vault lookup for '$Name' in '$VaultName' failed ($_). Falling back to file store." -Level Warn
        }
    }

    # 2) File fallback (historical behavior).
    if (-not $secureValue) {
        $secretPath = Join-Path $IDConfig.Paths.UserSecretsRoot "$Name.txt"
        if (-not (Test-Path -Path $secretPath -PathType Leaf)) {
            throw "IDBridge secret '$Name' not found in vault '$VaultName' or file '$secretPath'."
        }
        Write-Log -Message "Secret: Retrieving '$Name' from file store." -Level Trace
        $secureValue = Get-Content -Path $secretPath | ConvertTo-SecureString
    }

    # Some vaults return a plain string for string secrets; normalize to SecureString.
    if ($secureValue -is [string]) {
        $secureValue = ConvertTo-SecureString -String $secureValue -AsPlainText -Force
    }

    if ($AsPlainText) {
        return (ConvertFrom-SecureString -SecureString $secureValue -AsPlainText)
    }

    return $secureValue
}
