# IDBridge Telemetry & Privacy

IDBridge reports anonymous, aggregate usage statistics to SC Networks LLC so we can see
how the module is used and where it fails. This document describes exactly what is sent,
when, and how to turn it off.

**The core commitment: IDBridge telemetry never transmits student or staff data.**
No names, usernames, email addresses, UPNs, student/person IDs, group names, OU paths,
log lines, or any other directory record leave your environment — at any tier. Telemetry
is aggregate counts about the *run*, not data about *people*.

## Tiers

Set the tier in `IDBridgeConfig.psd1`:

```powershell
Telemetry = @{
    Tier = 'Basic'   # 'Basic' (default) | 'Enhanced' | 'Off'
}
```

If the `Telemetry` block is absent, the tier is `Basic`. An unrecognized value is treated
as `Off` (fail-safe). Any single run can be silenced with `Invoke-IDBridge -DisableTelemetry`.
Preview runs (`Invoke-IDBridge -Preview`) never send a telemetry event at any tier — a
review peek is not a run.

### Off
Nothing is sent. No exceptions.

### Basic (default)
One anonymous event per run containing only:

| Field | Example | Notes |
|---|---|---|
| `schemaVersion` | `1` | Payload format version |
| `tier` | `"Basic"` | |
| `moduleVersion` | `"26.7.6.0"` | |
| `psVersion` | `"7.5.1"` | PowerShell version |
| `success` | `true` | Did the run complete without a fatal error |
| `readOnly` / `testRun` | `false` | Run mode flags |
| `directories` | `"AD+Google"` | Which directory types are enabled — never *which* directory/domain |
| `managedCount` | `1250` | Number of source records processed (people — the only per-person count) |
| `createCount` / `updateCount` / `deactivateCount` | `3` | **Directory writes** that succeeded this run — one per directory, so a person provisioned to both AD and Google counts twice (actual applied outcomes — always `0` in ReadOnly) |
| `groupAddCount` / `groupRemoveCount` | `5` | Group-membership writes that succeeded this run (actual applied outcomes — `0` in ReadOnly or while a directory's group WhatIf is on; never group names) |
| `writeFailureCount` | `0` | Number of individual directory writes that failed this run — a count only; *which* users or groups failed never leaves the machine |
| `durationSeconds` | `42` | |

Basic events contain **no identifier of any kind** — not even a random one. Two runs from
the same install cannot be linked to each other, and an install cannot be linked to a
district.

### Enhanced (opt-in)
Everything in Basic, plus:

- **`siteID`** — a random GUID identifying this *install* (not a person, not a district).
  It is generated locally by `New-Guid` on first Enhanced run — never derived from your
  district name, domain, hostname, or any other real value — and lets your runs form a
  timeline you can view in the IDBridge Pulse dashboard (`pulse.scnlabs.net`) by claiming
  your SiteID there. Run `Get-IDBridgeSiteID` to see yours.
- **On failed runs only:** `errorType` (the .NET exception *class name*, e.g.
  `ADIdentityNotFoundException`) and `errorFunction` (the name of the function that
  threw). The exception *message* is never sent — messages can contain account details.

## Verify it yourself

The exact payload is logged before sending. Run with `-TraceLogging` and look for the
`Telemetry: Payload:` line in the log — that JSON is byte-for-byte what leaves your
network, sent as a single HTTPS POST to `https://pulse.scnlabs.net/api/ingest` (or the
`Telemetry.Endpoint` override from config, e.g. an egress proxy).

Telemetry is fire-and-forget with a 10-second timeout and no retries: an unreachable
endpoint (blocked egress, air-gapped network) is logged locally and never delays or
fails a sync.

## Not telemetry: the run summary file

At the end of every run that is not a `-Preview`, IDBridge writes
`<RootPath>\Data\LastRun.json` — a small local file describing how the run went, replaced
whole each time. It holds exactly these keys and nothing else: `schemaVersion`,
`moduleVersion`, `runStart`, `runEnd`, `durationSeconds`, `success`, `readOnly`, `testRun`,
`directories`, `managed`, `created`, `updated`, `deactivated`, `groupAdds`, `groupRemoves`,
`writeFailures`, `thresholdExceeded`, `errorType`, `errorFunction`, `lastSuccessAt`, and
`runId`. That is counts, mode flags, timing and the module version; the run's own ID, a
random GUID made as the run starts (it names a run, never a person, and is the one on the
run's opening log line); on a failed run the exception **class** name and the throwing
**function** name — never the exception message, which can contain UPNs/DNs. No name, username, email address, person ID, distinguished name or group
name is ever written to it.

IDBridge never sends this file anywhere: it is written to your own `Data` directory and
read by whatever you point at it. Where a district runs [Beacon](https://github.com/SCNetworksLLC/Beacon),
SC Networks' status dashboard, Beacon's collector on the same box reads it there — that
collector, not IDBridge, is what leaves the machine. The file is written regardless of the
telemetry tier (it isn't telemetry and sends nothing to SC Networks); `Preview` runs never
write it, and a write failure logs a `Warn` and never affects the run.

## Not telemetry: the account history plugin

`Invoke-PluginPostRunAccountHistory` is a PostRun plugin template that ships **disabled**
and throws until you put your own site's address in it. Nothing below happens unless you
enable it.

Enabled, it sends each run to **the address you set and nowhere else** — never to SC
Networks by IDBridge's doing — over HTTPS, with an API token your site issued (the vault
secret `AccountHistory-Token`). Unlike everything above, this is **per-person data**: for
every write the run attempted, the directory, the action, the person ID, the target (a
UPN, a name, a group), whether it worked, the error text if it did not, and for an update,
a rename or a move, each attribute changed with its new and its old value. Never a
password: a key named for one and any SecureString value are left out. Each post also
carries the run's ID, its timing, mode flags and counts, the module version, the run's
error text, and this install's **SiteID** as the install's identifier — the same GUID the
Enhanced telemetry tier uses. Enabling the plugin creates the SiteID file if it does not
exist yet; it does not change your telemetry tier or send anything to SC Networks.

Each post is written to `<RootPath>\Data\AccountHistory` before it is sent, so a run made
while your site is unreachable is sent later. A post your site takes is deleted; one it
refuses for good is kept in `AccountHistory\refused` for 30 days; unsent posts are kept at
most 30 days. Those files hold the same per-person data, under your `Data` directory's
own permissions.

## Not telemetry: the update check

Separately from telemetry, `Invoke-IDBridge` queries the **PowerShell Gallery**
(`powershellgallery.com`, a Microsoft service) at the start of each run to see whether a
newer IDBridge release exists, and logs a warning when one does. The request is a
standard gallery version lookup — it carries nothing about your install beyond the
module name, and nothing is ever downloaded or installed. It runs regardless of the
telemetry tier (it isn't telemetry and sends nothing to SC Networks); there is no
switch to disable it, but blocked or offline networks skip it silently (10-second
timeout, logged at Trace, never affects the run).

## The SiteID file

The SiteID is stored in plain text at `<RootPath>\Config\IDBridgeSiteID.json`. It is not
a secret (worst case, someone who has it can see your install's aggregate run counts) and
is deliberately kept beside the config so a server migration preserves your timeline.
**If you clone a config folder to stand up a separate install, delete
`IDBridgeSiteID.json` in the copy** so the new install generates its own.

## Retention & removal

- Enhanced per-run history is retained for 12 months; aggregate daily rollups (counts
  only, fleet-wide) are retained indefinitely.
- To have all data for a SiteID deleted, email sam@scnetworks.io with the SiteID.
- Setting `Tier = 'Off'` stops all transmission immediately; nothing new is collected.
