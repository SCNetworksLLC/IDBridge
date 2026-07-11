# IDBridge Secrets

IDBridge needs a few secrets at run time (SIS API keys, the passphrase-API token and nonces,
and the Google service-account key). These are stored in the **IDBridge secret vault**: a
folder of encrypted JSON envelope files (`<Name>.secret.json`) at `C:\IDBridge\Vault`
(runtime `Paths.VaultRoot`, `<Root>\Vault`). The vault is built entirely on in-box Windows
crypto — **no external modules, no vault registration, no unlock step**, and no file-based
fallback.

Each envelope records the provider that protected it, so **reads are provider-agnostic**:
`Get-IDBridgeSecret -Name <name>` decrypts any mix of providers from the same vault. The
provider configured in `Secrets.Provider` (see
[configuration.md](configuration.md#secrets)) matters at **write** time only:

| Provider | Backed by | Use it for |
|----------|-----------|------------|
| `Cms` *(default)* | `Protect-CmsMessage` + a Document Encryption certificate | Any machine, domain or not. Decryption needs the certificate's private key. |
| `DpapiNG`         | DPAPI-NG (`ncrypt.dll`, built-in wrapper)                | Production / unattended — protect secrets to an AD principal (e.g. a **gMSA**); decryptable by that principal on any domain-joined host. |
| `AzKeyVault`      | Azure Key Vault REST + Entra certificate auth            | Central/remote storage shared across hosts. **The remote exception:** no local envelopes — all secret functions go to the Key Vault. |

All secret reads go through **`Get-IDBridgeSecret`**
([reference](functions.md#get-idbridgesecret)):

```powershell
$token = Get-IDBridgeSecret -Name 'ApiKey-Passphrase'              # SecureString
$plain = Get-IDBridgeSecret -Name 'ApiKey-SkywardSMS' -AsPlainText # string
```

It **throws** when the secret is missing (telling you to run `Set-IDBridgeSecret`) or cannot
be decrypted (naming the certificate/principal required). Inspect the vault with
`Get-IDBridgeSecretInfo` (names and metadata only, never values) and delete entries with
`Remove-IDBridgeSecret`.

## Cms provider (default): certificate setup

One-time, on the machine that runs IDBridge (elevated session for the machine store):

```powershell
Initialize-IDBridge               # loads config; safe on a fresh install (no Google auth here)
New-IDBridgeSecretCertificate     # creates the cert in Cert:\LocalMachine\My, prints the thumbprint
```

This creates a self-signed **Document Encryption** certificate (`CN=IDBridge Secrets`, EKU
`1.3.6.1.4.1.311.80.1`, non-exportable RSA 3072, 10-year validity). Put the thumbprint in
`Secrets.Cms.Thumbprint` (or leave it empty — the single `CN=IDBridge Secrets` cert is found
automatically). On a dev machine without elevation, use
`New-IDBridgeSecretCertificate -StoreLocation CurrentUser`.

Then add each secret with **`Set-IDBridgeSecret`**:

```powershell
Set-IDBridgeSecret -Name 'ApiKey-Passphrase'              # prompts for the value (masked)
Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStaff'
Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStudent'
Set-IDBridgeSecret -Name 'ApiKey-SkywardSMS'

# The Google service-account key is stored from its JSON file:
Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -InFile 'C:\path\to\key.json'

Get-IDBridgeSecretInfo                                    # confirm what's stored
```

Re-running `Set-IDBridgeSecret` with the same `-Name` overwrites the value.

**Decryption access.** With the machine store, only SYSTEM and Administrators can use the
private key by default. For scheduled runs under a service account (e.g. a gMSA), grant it
read on the key when creating the cert:

```powershell
New-IDBridgeSecretCertificate -GrantRead 'DOMAIN\gMSA-IDBridge$'
```

For a certificate that already exists (or to add another account later), grant the same
access by thumbprint (elevated session):

```powershell
Grant-IDBridgeCertificatePrivateKeyAccess -Thumbprint '<thumbprint>' -Identity 'DOMAIN\gMSA-IDBridge$'
```

**Recovery.** The private key is non-exportable by design: if the machine (or the cert) is
lost, re-create the certificate and re-seed the secrets — every secret is a re-issuable API
key or a re-downloadable JSON key.

## Production alternative: gMSA + DPAPI-NG provider

For unattended runs under a **group Managed Service Account** on domain-joined hosts, use the
`DpapiNG` provider. DPAPI-NG protects each secret to an AD **protection descriptor** (a SID),
so an admin can seed secrets that the gMSA later decrypts on any domain-joined host — without
the admin ever being the gMSA, and with nothing to run as the gMSA beforehand.

1. **KDS root key** must exist in the domain (already true if the gMSA exists).
2. Configure the provider in `IDBridgeConfig.psd1`:
   ```powershell
   Secrets = @{
       Provider = 'DpapiNG'
       DpapiNG  = @{ ProtectionDescriptor = 'SID=<gMSA SID> OR SID=<IDBridge admins group SID>' }
   }
   ```
   The `OR` clause is recommended: admins can then also read/verify secrets, and the vault
   survives a gMSA re-creation. Omitting the descriptor protects to the current account only
   (logged as a warning).
3. **Seed the secrets** as an admin (same `Set-IDBridgeSecret` commands as above). Seeding and
   reading both need a reachable domain controller.

The DPAPI-NG calls are made through a small built-in P/Invoke wrapper over `ncrypt.dll`
(`NCryptProtectSecret` / `NCryptUnprotectSecret`) — no module to install anywhere.

> **Note:** `SID=` descriptors only work on AD domain-joined machines. On a non-domain dev
> machine, use the `Cms` provider (or a `LOCAL=user` descriptor for throwaway testing).

## Remote alternative: Azure Key Vault provider

With `Provider = 'AzKeyVault'` the secrets live in an Azure Key Vault instead of local
envelope files — one central store shared by every host. Access is pure REST
(`Invoke-RestMethod`), authenticated as an **Entra app registration with a certificate
credential** (OAuth client-credentials flow with a self-built JWT assertion) — still no
external modules.

One-time Azure setup:

1. **App registration** in Entra ID; note the client ID and tenant.
2. **Certificate credential**: upload the public key (`.cer`) of a certificate whose private
   key is on the IDBridge host (any cert works — `New-IDBridgeSecretCertificate` output is
   fine, or a dedicated one). The account running IDBridge needs private-key read.
3. **Key Vault access** for the app: role `Key Vault Secrets User` for runtime reads;
   seeding/removing also needs `Key Vault Secrets Officer` (or equivalent access-policy
   permissions).
4. Configure the `Secrets.AzKeyVault` block (see
   [configuration.md](configuration.md#secrets)): `VaultUri`, `TenantId`, `ClientId`, and
   `CertThumbprint`.

Behavior notes:

- Secrets are stored under their IDBridge names as-is (e.g. `ApiKey-SkywardSMS`,
  `GoogleAuth-ServiceAccount`). In a vault shared with other scripts the namespace is
  shared too — `Get-IDBridgeSecretInfo` lists everything the app can see, and name
  collisions are possible; prefer a dedicated vault for IDBridge.
- Key Vault secret names allow only **letters, numbers, and dashes** — all shipped secret
  names qualify. Multi-line values (the Google service-account JSON, ~2–3 KB against the
  25 KB value limit) are fine.
- The bearer token is cached for the session and refreshed automatically before expiry.
- Seeding uses the exact same commands (`Set-IDBridgeSecret`, `-InFile`, etc.); switching an
  existing install to `AzKeyVault` means re-seeding into the vault (local envelopes are not
  read while the provider is `AzKeyVault`, and vice versa).

## Secret names

These names are used by the shipped code/plugins — store secrets under the **same names**:

| Name | Purpose |
|------|---------|
| `GoogleAuth-ServiceAccount`    | Google service-account key JSON (always required when `GoogleToken.Enabled`; **no file fallback**). Seeded by hand (`-InFile`) or end-to-end by [`Initialize-IDBridgeGoogleServiceAccount`](google-bootstrap.md) |
| `ApiKey-SkywardSMS`            | Skyward SMS OneRoster client secret (always required by the students plugin) |
| `ApiKey-Passphrase`            | Passphrase-API bearer token (only when a password type is `API-PASSPHRASE`) |
| `ApiKey-PassphraseNonceStaff`  | Passphrase nonce for staff (only when staff use `API-PASSPHRASE`) |
| `ApiKey-PassphraseNonceStudent`| Passphrase nonce for students (only when a grade uses `API-PASSPHRASE`) |

> Plugins fetch the passphrase secrets **only when a password type actually uses the passphrase
> API**, so a run that uses `WORD`/`RANDOM`/`FSPIN` passwords never needs them in the vault.

## Hygiene

- The vault folder holds only **encrypted** envelopes, but it lives outside the repo and must
  **never** be committed; restrict NTFS access to the accounts that run IDBridge.
- `Cms` secrets are decryptable wherever the certificate private key is (per machine, since
  the key is non-exportable). `DpapiNG` secrets are decryptable by the descriptor's
  principal(s) on any domain-joined host.
- Nothing sensitive is ever written to the log — secret values never leave
  `Get-IDBridgeSecret` unencrypted except as its return value.
