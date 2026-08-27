# Bootstrapping the AD Service Account and Scheduled Run

Two functions take a working interactive install to an unattended nightly sync — the
Active Directory counterpart to [google-bootstrap.md](google-bootstrap.md). Run both
**elevated, on the domain-joined machine that runs IDBridge**, as an account that can
create the gMSA and write the managed OU's ACL (e.g. a domain admin). Both are
idempotent — re-running is safe and is how you add a second host or change the trigger
time later.

```powershell
Import-Module IDBridge
Initialize-IDBridge                    # loads config/paths/logging
Initialize-IDBridgeADServiceAccount    # gMSA + OU delegation + cert private-key read
Register-IDBridgeScheduledTask         # install account on this host + daily task
```

The account is a **group Managed Service Account** (default `gMSA-IDBridge`): no
password is ever generated, stored, or typed — this computer's account is allowed to
retrieve it from AD, and Task Scheduler does so at run time (`-LogonType Password`).
The scheduled run is therefore confined to the delegation below even when the host
itself is a tier-0 machine.

## `Initialize-IDBridgeADServiceAccount` — account and rights

| Step | Notes |
|------|-------|
| Create the gMSA | `PrincipalsAllowedToRetrieveManagedPassword` = this computer (add hosts via `-ComputerName` on a re-run). Existing account is kept; missing principals are added. |
| Delegate on the managed root OU | `-TargetOU`, defaulting to `AD.userRootOU` from config. The exact ACEs are below; nothing outside the OU is touched. |
| Grant the Cms certificate's private key | Read ACE for the gMSA on the key file, via [`Grant-IDBridgeCertificatePrivateKeyAccess`](functions.md#grant-idbridgecertificateprivatekeyaccess). Certificate from `-CertThumbprint`, else auto-resolved (`Secrets.Cms.Thumbprint`, else the single `CN=IDBridge Secrets` cert). `-SkipCertificateAccess` for DpapiNG/AzKeyVault sites — see [secrets.md](secrets.md). |

### The delegation (ACEs on the target OU)

| IDBridge does | ACE granted |
|---------------|-------------|
| Create missing OUs (never delete or modify them) | `CreateChild`, object type `organizationalUnit`, this OU and all descendants |
| Create users | `CreateChild`, object type `user`, this OU and all descendants |
| Update / rename / disable / move users | `GenericAll` (full control) on descendant `user` objects |
| Add / remove group members (never create or delete groups) | `WriteProperty` on the `member` attribute of descendant `group` objects |

Two things to understand about the user ACE:

- **Full control includes Delete — deliberately.** `Move-ADObject` (OU moves, and
  deactivation's move to the Trash OU) requires the Delete right on the object being
  moved, so "manage everything except delete" cannot be expressed in an ACL. IDBridge
  itself never calls `Remove-ADUser`.
- **Never place admin or otherwise privileged accounts under the managed root OU.**
  The delegation is only as safe as the OU's population; the gMSA has full control over
  every user object under it. (Protected accounts would resist the ACL via
  AdminSDHolder, but the rule stands regardless.)

### Prerequisite: a usable KDS root key

Creating any gMSA requires a KDS root key in the domain. If none exists the function
stops and says so — create one as a domain admin with `Add-KdsRootKey` and re-run
**~10 hours later** (the key is usable once every DC can have replicated it; the
well-known `-EffectiveTime ((Get-Date).AddHours(-10))` shortcut is safe only in a
single-DC lab).

## `Register-IDBridgeScheduledTask` — running as it

| Step | Notes |
|------|-------|
| Install + verify the gMSA on this host | `Install-ADServiceAccount` / `Test-ADServiceAccount`. Right after the account is created (or this host newly allowed), stale Kerberos tickets make this fail — the function purges the computer's tickets (`klist -li 0x3e7 purge`) and retries once on its own; only if that also fails does it ask for a reboot. |
| Grant "Log on as a batch job" | `SeBatchLogonRight` in the local security policy (LSA API — no cmdlet exists), required to start a scheduled task. **GPO caveat:** if a GPO manages that right, the GPO's list overwrites the local grant on the next policy refresh — add the gMSA to the GPO instead. |
| Grant filesystem rights | Read on the module folder and the runtime root (config, plugins, vault); modify on `Logs`, `Exports`, `Data`. |
| Register the task | Every `-IntervalMinutes` (default 15, anchored to midnight so runs land on :00/:15/:30/:45), named `-TaskName` (default `IDBridge Sync`, replaced if present): `pwsh -NoProfile -NonInteractive -Command "Import-Module '<manifest>'; Invoke-IDBridge -RootPath '<root>'"` as the gMSA. A still-running run is never overlapped; a hung run is killed after 1 hour. **Created disabled** unless `-Enabled` is passed. |

## Secrets for the scheduled run

The run decrypts the vault as the gMSA, which works out of the box on either provider:

- **Cms** (default): the bootstrap granted the gMSA read on the certificate's private
  key — nothing more to do.
- **DpapiNG**: run the bootstrap with `-SkipCertificateAccess` and include the gMSA's
  SID in `Secrets.DpapiNG.ProtectionDescriptor`, then (re-)seed the secrets. See
  [secrets.md](secrets.md#production-alternative-gmsa--dpapi-ng-provider).

## Verify, then enable

The task is registered **disabled** so nothing runs before the config is reviewed:

1. `Start-ScheduledTask -TaskName 'IDBridge Sync'` — with `Debug.ReadOnly = $true` in
   the config for a safe first run (a disabled task still runs when started by hand).
2. Check `<Root>\Logs\IDBridge.log` for the run: Google auth succeeded (vault read as
   the gMSA worked) and the AD phases planned without permission errors.
3. `Enable-ScheduledTask -TaskName 'IDBridge Sync'` — the schedule goes live.
4. A `0x80070569` task start failure is the batch-logon right (the GPO caveat above);
   an `Access is denied` inside the AD apply phase means the delegation OU doesn't
   cover the object being written (check the plugin's OUs sit under `AD.userRootOU`).

## Recovery / changes

- **New IDBridge host:** re-run `Initialize-IDBridgeADServiceAccount -ComputerName <new host>`
  (adds the principal), then `Register-IDBridgeScheduledTask` on the new machine.
- **Change the cadence:** re-run `Register-IDBridgeScheduledTask -IntervalMinutes <n>` —
  the task is replaced in place (pass `-Enabled` to keep it live, the replacement is
  otherwise disabled again).
- **Offboarding:** disable or delete the task and the gMSA
  (`Remove-ADServiceAccount`); the OU ACEs name the account's SID and die with it
  (remove them from the OU's Security tab at leisure).
