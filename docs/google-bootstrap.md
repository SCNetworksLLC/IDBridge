# Bootstrapping the Google Service Account

`Initialize-IDBridgeGoogleServiceAccount` automates the Google-side setup of a new IDBridge
deployment as far as Google's APIs allow. Run it **once per district, in the district's
tenant, signed in as their Google Workspace super admin**. Everything it creates lives in
the district's Google Cloud organization — SC Networks retains nothing afterward.

```powershell
Import-Module C:\GIT\IDBridge\src\IDBridge\IDBridge.psd1
Initialize-IDBridge          # loads config/paths/logging; Google auth happens at run time, not here
Initialize-IDBridgeGoogleServiceAccount -CreateProject
```

What it does (idempotent — re-running is safe):

| Step | Automated? | Notes |
|------|------------|-------|
| Bootstrap sign-in | browser opens automatically | See [token tiers](#how-the-bootstrap-token-is-acquired). |
| Find/provision the GCP organization | semi | No API can accept the Cloud console terms; for a brand-new domain the function opens the console, the admin accepts, and it waits for the org to appear. |
| Create the project (`IDBridge`) | yes (`-CreateProject`) | Placed under the district's org; ID defaults to `idbridge-<random>`. |
| Enable APIs | yes | Admin SDK, Sheets, Enterprise License Manager, IAM. |
| Create the service account | yes | Display name `IDBridge`; the `uniqueId` is the DWD client ID. |
| Create the JSON key | yes | Seeded **straight into the vault** as `GoogleAuth-ServiceAccount` — never written to disk. |
| Org-policy exemption | yes, when needed | Only if key creation is blocked (see below). |
| **Domain-wide delegation** | **NO — manual, always** | Google provides no API; the function prints the exact client ID + scope list to paste. |

## Prerequisites

- **Google Cloud Platform must be ON for the admin** in the district's Google Admin
  console: *Apps → Additional Google services → Google Cloud Platform*. There is no API to
  check or change this; if it's off, the sign-in fails with an admin-policy error and the
  function says exactly this.
- The person signing in should be the district's **Workspace super admin** (they also make
  the DWD grant, and super admins can grant org-level roles if the org-policy dance is
  needed).
- An initialized IDBridge session (`Initialize-IDBridge`). Google auth is acquired by
  `Invoke-IDBridge` at run time, so initializing on a fresh install works before the key
  secret exists.

## How the bootstrap token is acquired

Tried in order; the first available tier wins:

1. **`-AccessToken`** — paste a `cloud-platform`-scoped token from anywhere
   (e.g. `gcloud auth print-access-token` on another machine).
2. **gcloud**, if installed — uses the existing login or runs `gcloud auth login`.
3. **OAuth Playground** *(the default path — Google's own verified app, so a normal
   consent screen)*. The function opens the playground and waits at a masked paste prompt;
   in the browser:
   1. Step 1 → type `https://www.googleapis.com/auth/cloud-platform` into **"Input your
      own scopes"** → **Authorize APIs** (leave the gear-icon defaults alone).
   2. Sign in as the **district's super admin** and approve the consent.
   3. Step 2 → **Exchange authorization code for tokens** → copy the **`access_token`**
      (`ya29....`, not the refresh token) → paste it into the PowerShell prompt.

The token is the district admin's, lives ~1 hour, is held only in memory, and no refresh
token is ever requested or stored. Treat it like a domain-admin password for that hour —
paste it straight from browser to prompt, nowhere else. Rare gotcha: playground tokens
attribute API quota to Google's own playground project; if a call fails with an
"API not enabled" error, use the gcloud tier instead.

## The org-policy dance (newer GCP orgs)

Newer organizations enforce `iam.disableServiceAccountKeyCreation` by default, which blocks
step "create key". The function only reacts if the block actually fires:

1. Temporarily grants the signed-in admin `roles/orgpolicy.policyAdmin` at the org (a
   Workspace super admin may grant org roles — Google's documented recovery power).
2. Sets a **project-level** exemption (`enforce: false`) on the IDBridge project only.
3. Retries key creation (IAM grants can take a minute to propagate).
4. **Revokes the temporary role** — the org is left as found, plus one project.

If the role grant itself fails, the function prints the one-liner for the district's GCP
admin: `gcloud org-policies reset iam.disableServiceAccountKeyCreation --project=<id>`.

## The forever-manual finish (printed as a checklist)

1. **Domain-wide delegation** — Admin console → Security → API controls →
   [Domain-wide delegation](https://admin.google.com/ac/owl/domainwidedelegation) → Add new:
   the printed **Client ID** and the module's full scope set, comma-separated (also needed
   when updating a pre-existing grant by hand):

   ```
   https://www.googleapis.com/auth/admin.directory.user,https://www.googleapis.com/auth/admin.directory.orgunit,https://www.googleapis.com/auth/admin.directory.group,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/apps.licensing
   ```

   | Scope | Used for |
   |-------|----------|
   | `admin.directory.user`    | User create/update/suspend/move |
   | `admin.directory.orgunit` | OU creation |
   | `admin.directory.group`   | Group membership processing |
   | `spreadsheets`            | GSheet source plugins + sheet logging |
   | `apps.licensing`          | License removal on deactivate (on by default; scope not requested when `enableLicenseRemoval = $false`) |
2. Set `GoogleToken.adminEmail` in the config to a super admin in the district's domain.
3. Verify the auth chain without a pipeline run: `Connect-IDBridgeGoogle` — success means
   vault, key, DWD client ID, and scopes are all right (`unauthorized_client` means the
   DWD grant doesn't match yet; grants can take a few minutes to propagate).
4. Full verification: `Invoke-IDBridge -ReadOnly`.

## Recovery scenarios

- **Lost vault / new server:** re-run with `-ProjectId <existing id>` — it reuses the
  project and service account, mints a fresh key into the vault. Delete the old key in the
  console (IAM → Service accounts → Keys) at leisure.
- **District offboarding:** the district deletes the DWD entry (instant kill switch) and/or
  the project. Nothing else exists anywhere.
