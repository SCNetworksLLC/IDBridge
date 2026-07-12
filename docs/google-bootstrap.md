# Bootstrapping the Google Service Account

`Initialize-IDBridgeGoogleServiceAccount` automates the Google-side setup of a new IDBridge
deployment as far as Google's APIs allow. Run it **once per district, in the district's
tenant, signed in as their Google Workspace super admin**. Everything it creates lives in
the district's Google Cloud organization — SC Networks retains nothing afterward.

```powershell
Install-Module IDBridge -Scope CurrentUser   # from the PowerShell Gallery
Import-Module IDBridge
Initialize-IDBridge          # loads config/paths/logging; Google auth happens at run time, not here
Initialize-IDBridgeGoogleServiceAccount -CreateProject
```

The service account authenticates **as itself** — it holds a custom Google Workspace
admin role named `IDBridge` (user, org-unit, group, and license management privileges).
There is **no domain-wide delegation and no admin impersonation**: no human or service
*user* account is involved at run time, and Super Admin is never needed after the
bootstrap. Sheets access comes from **sharing the sheets with the service account's
email** (`Get-IDBridgeGoogleServiceAccountEmail` prints it any time).

What it does (re-running is safe):

| Step | Automated? | Notes |
|------|------------|-------|
| Bootstrap sign-in | browser opens automatically | See [token tiers](#how-the-bootstrap-token-is-acquired). |
| Find/provision the GCP organization | semi | No API can accept the Cloud console terms; for a brand-new domain the function opens the console, the admin accepts, and it waits for the org to appear. |
| Create the project (`IDBridge`) | yes (`-CreateProject`) | Placed under the district's org; ID defaults to `idbridge-<random>`. |
| Enable APIs | yes | Admin SDK, Sheets, Enterprise License Manager, IAM. |
| Create the service account | yes | Display name `IDBridge`; the `uniqueId` is what the admin role is assigned to. |
| Create the JSON key | yes | Seeded **straight into the vault** as `GoogleAuth-ServiceAccount` — never written to disk. |
| Org-policy exemption | yes, when needed | Only if key creation is blocked (see below). |
| Create + assign the `IDBridge` admin role | yes | Privileges resolved from `privileges.list` (never hardcoded serviceIds); re-runs converge an existing role's privileges. Needs the `admin.directory.rolemanagement` scope — the function prompts for a second OAuth Playground token if the bootstrap token lacks it. |
| **Share the sheets with the SA** | **NO — manual, always** | Drive sharing has no place in the bootstrap token's scopes; the checklist prints the exact email. |

## Prerequisites

- **Google Cloud Platform must be ON for the admin** in the district's Google Admin
  console: *Apps → Additional Google services → Google Cloud Platform*. There is no API to
  check or change this; if it's off, the sign-in fails with an admin-policy error and the
  function says exactly this.
- The person signing in should be the district's **Workspace super admin** (creating and
  assigning admin roles requires it, and super admins can grant org-level roles if the
  org-policy dance is needed). This is the **only** point Super Admin is required — the
  service account itself runs with the scoped `IDBridge` role.
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
   1. Step 1 → type both scopes (space-separated) into **"Input your own scopes"** →
      **Authorize APIs** (leave the gear-icon defaults alone):
      ```
      https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/admin.directory.rolemanagement
      ```
      (the second scope covers the admin-role steps; gcloud/`-AccessToken` tokens can't
      carry it, so those tiers get a one-time playground prompt for it later instead).
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

## The `IDBridge` admin role (created + assigned automatically)

The bootstrap creates a custom Workspace admin role named `IDBridge` and assigns it to the
service account at customer scope. Privileges (resolved from `privileges.list` at run
time, since serviceIds vary per customer):

| Privilege | Used for |
|-----------|----------|
| `USERS_ALL`              | User create/update/suspend/move/rename |
| `ORGANIZATION_UNITS_ALL` | OU creation + reads |
| `GROUPS_ALL`             | Group membership processing |
| `LICENSING` + `LICENSING_READ` | License assignment reads each run + removal on deactivate (the Admin console's "License Management"; optional — the role is created without them if not found, with a warning) |

The OAuth **scopes** in the token request (`Get-IDBridgeGoogleScope`) are unchanged —
scopes say which APIs the token may call; the admin role is what *authorizes* the calls.
Sheets is not an admin-role privilege: the service account reads source sheets and writes
the log sheet **as itself**, so those sheets must be shared with it.

## The forever-manual finish (printed as a checklist)

1. **Share the sheets** — share the staff source spreadsheet and the log spreadsheet
   (Editor) with the printed service-account email (also available any time via
   `Get-IDBridgeGoogleServiceAccountEmail`).
2. Verify the auth chain without a pipeline run: `Connect-IDBridgeGoogle` — success means
   the vault and key are right. A `403` on subsequent API calls means the role assignment
   hasn't propagated yet (typically minutes) or is missing; a Sheets `403` means a sheet
   isn't shared with the service account.
3. Full verification: `Invoke-IDBridge -ReadOnly`.
4. **Migrating from a pre-role deployment:** only after step 3 passes, delete the old
   domain-wide delegation entry (Admin console → Security → API controls →
   [Domain-wide delegation](https://admin.google.com/ac/owl/domainwidedelegation)) and
   remove `GoogleToken.adminEmail` from the config (the key is no longer read).

## Recovery scenarios

- **Lost vault / new server:** re-run with `-ProjectId <existing id>` — it reuses the
  project, service account, and role assignment, and mints a fresh key into the vault.
  Delete the old key in the console (IAM → Service accounts → Keys) at leisure.
- **District offboarding:** the district removes the `IDBridge` role assignment or deletes
  the role (Admin console → Account → Admin roles — instant kill switch) and/or deletes
  the project. Nothing else exists anywhere.
