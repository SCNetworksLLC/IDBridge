# IDBridge Secrets

IDBridge needs a few secrets at run time (SIS API keys, the passphrase-API token, and its
nonces). Historically these were stored as per-user encrypted text files; IDBridge now also
supports **PowerShell SecretManagement** vaults, with the file store kept as an automatic
fallback so nothing breaks during migration.

All secret access should go through **`Get-IDBridgeSecret`**
([reference](functions.md#get-idbridgesecret)):

```powershell
$token = Get-IDBridgeSecret -Name 'ApiKey-Passphrase'             # SecureString
$plain = Get-IDBridgeSecret -Name 'ApiKey-SkywardSMS' -AsPlainText # string
```

## Resolution order

1. **SecretManagement vault** — used when the `Microsoft.PowerShell.SecretManagement` module
   is installed **and** a vault is configured (via `-VaultName` or the `Secrets.VaultName`
   config key) that contains a secret with the requested name.
2. **File fallback** — otherwise the value is read from
   `"<UserSecretsRoot>\<Name>.txt"`, i.e. `C:\IDBridge\Auth\<username>\<Name>.txt`
   (a `SecureString` exported with `ConvertFrom-SecureString`). This is the original behavior.

If neither source has the secret, `Get-IDBridgeSecret` throws.

## Secret names

These names are used by the shipped code/plugins — register vault secrets under the **same
names** so the file store and vault are interchangeable:

| Name | Purpose |
|------|---------|
| `ApiKey-SkywardSMS`            | Skyward SMS OneRoster client secret |
| `ApiKey-Passphrase`            | Passphrase-API bearer token |
| `ApiKey-PassphraseNonceStaff`  | Passphrase nonce for staff |
| `ApiKey-PassphraseNonceStudent`| Passphrase nonce for students |

> The **Google service-account JSON key stays file-based** — it is the single `*.json` file in
> `C:\IDBridge\Auth\`, discovered by `Initialize-IDBridge`, not a SecretManagement secret.

## Enabling a vault (optional)

```powershell
# One-time setup
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name IDBridge -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault

# Add secrets (use the names above)
Set-Secret -Name 'ApiKey-Passphrase' -Secret (Read-Host 'Passphrase token' -AsSecureString)
```

Then point IDBridge at the vault via the optional `Secrets` block in
[`IDBridgeConfig.psd1`](configuration.md#secrets-optional):

```powershell
Secrets = @{ UseSecretManagement = $true; VaultName = 'IDBridge' }
```

With no `Secrets` block (or no vault), IDBridge keeps using the `*.txt` file store exactly as
before.

## Migrating existing file secrets into a vault

```powershell
$src = Join-Path (Get-IDBridgeConfig).Paths.UserSecretsRoot 'ApiKey-Passphrase.txt'
$sec = Get-Content $src | ConvertTo-SecureString
Set-Secret -Name 'ApiKey-Passphrase' -Secret $sec -Vault IDBridge
```

Repeat per secret. Once verified in the vault, the original `.txt` files can be removed.

## Hygiene

- Secrets live under `C:\IDBridge\Auth\<username>\` (outside the repo) and must **never** be
  committed. `.gitignore` plus the out-of-repo location keep them out of git.
- File-based secrets are encrypted with Windows DPAPI and are **per user and per machine** —
  they must be created by (and are only readable by) the account that runs IDBridge.
