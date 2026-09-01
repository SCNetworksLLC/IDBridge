# Keysmith Integration

IDBridge sets initial account passwords by calling **Keysmith**
(`https://keysmith.scnlabs.net`) — SC Networks' deterministic passphrase
generator. Same nonce + username + word-list rev always produces the same
passphrase, so a student's password can be regenerated at any time without ever
being stored. The module's exported `New-Passphrase` function does the API call;
the AD and Google create paths use it when a record carries an
`ADPassphraseAPI` / `GooglePassphraseAPI` block (populated by the school's
source plugin from config).

## Registering a school with Keysmith

Each district gets its own Keysmith organization, API token, and nonce:

1. **SC Networks issues an invite** from the Keysmith admin page
   (Invites → New Invite): org slug, display name, and the district's email
   domain(s). The invite is a single-use link that expires in 14 days.
2. **The district's tech contact opens the link and signs in** with their school
   Microsoft account — this creates the org, claims its domains, and makes them
   the org's admin. From then on, district staff who sign in at
   `keysmith.scnlabs.net` can request access themselves, and the district admin
   approves them. No SC Networks involvement needed for day-to-day staff access.
3. **SC Networks mints the district's API token** (Keysmith admin → API Tokens,
   label = the org slug). The token is shown once.
4. **Provision the token and the district's nonce(s) into the IDBridge vault** on
   the school's server (each command prompts for the value, masked):

   ```powershell
   Set-IDBridgeSecret -Name 'ApiKey-Passphrase'              # the Keysmith API token
   Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStaff'    # staff nonce
   Set-IDBridgeSecret -Name 'ApiKey-PassphraseNonceStudent'  # student nonce
   ```

   (These are the names the shipped plugins read — see
   [secrets.md](secrets.md#secret-names); a custom plugin can use its own names. The
   plugin reads them and builds the `*PassphraseAPI` block per record.)

## Operational rules

- **One token and one nonce per district.** Both live only in that district's
  vault, so a compromise at one school never exposes another. Revoking a school
  is one row in the Keysmith admin UI.
- **Record the word-list rev.** Every `New-Passphrase` call logs
  `Keysmith: generated N passphrase(s) — word-list rev R`. Regenerating a
  passphrase later requires the same nonce **and the same rev** (pass `-Rev` to
  `New-Passphrase` or the standalone client; new account creation should omit it
  and take the server's latest).
- **Auth header.** The token is sent as `x-api-key` — the Static Web App proxy
  overwrites `Authorization` before it reaches the API. `New-Passphrase`
  handles this; don't hand-roll calls with Bearer headers.
- **Bulk resets.** `Reset-IDBridgeADPassword` (GUI, run by hand) resets every AD
  account in the checked OUs back to its deterministic passphrase using these same
  vault secrets — see [functions.md](functions.md#reset-idbridgeadpassword).
- **Annual renewal.** Keysmith users and tokens expire each August 1 by default.
  Token renewal/regeneration is done by SC Networks; a regenerated token must be
  re-provisioned into the school's vault.

Full Keysmith documentation lives in the
[Keysmith repository](https://github.com/SCNetworksLLC/Keysmith) (`docs/`).
