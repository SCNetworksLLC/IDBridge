<#
.SYNOPSIS
    Bootstraps the Google service account IDBridge needs — project, APIs, service account,
    key, and the Workspace admin role — then prints the manual finish steps.

.DESCRIPTION
    Run once per district, in the DISTRICT's tenant, authenticated as their Google Workspace
    super admin. Everything it creates stays in the district's Google Cloud organization;
    SC Networks retains nothing. Pure Invoke-RestMethod — no external modules.

    Steps (each idempotent, so re-running is safe):
      1. Bootstrap token, tried in order:
           -AccessToken parameter;
           gcloud (print-access-token, running 'gcloud auth login' if needed);
           OAuth Playground (browser opens; paste the token when prompted).
      2. Finds the district's GCP organization (organizations:search). If none exists yet
         and -CreateProject is set, opens the Cloud console for the one-time terms
         acceptance that provisions it, and waits for the org to appear.
      3. -CreateProject: creates the project (display name 'IDBridge') under the org.
      4. Enables the APIs IDBridge uses: Admin SDK, Sheets, Enterprise License Manager, IAM.
      5. Creates the service account and reads its uniqueId — the identity the admin role
         is assigned to.
      6. Creates the JSON key and seeds it STRAIGHT INTO THE VAULT as
         'GoogleAuth-ServiceAccount' — the key never touches disk.
         If key creation is blocked by the iam.disableServiceAccountKeyCreation org policy,
         the function self-grants the admin roles/orgpolicy.policyAdmin (a Workspace super
         admin may grant org roles), sets a project-level exemption, retries, and then
         revokes the temporary role.
      7. Creates the 'IDBridge' custom Workspace admin role (user, org-unit, group, and
         license management privileges — discovered from privileges.list, not hardcoded)
         and assigns it to the service account. The service account then authenticates as
         ITSELF: no domain-wide delegation, no admin impersonation, no admin user account.
         These Admin SDK calls need the admin.directory.rolemanagement scope, which
         cloud-platform bootstrap tokens don't carry — when that happens the function
         prompts for a second OAuth Playground token with just that scope.
      8. Prints the finish checklist: share the source/log sheets with the service
         account's email (it accesses Sheets as itself), then verify.

    Manual prerequisites (see docs/google-bootstrap.md):
      - The Google Cloud Platform additional service must be ON for the admin in the
        district's Google Admin console (auth fails with an admin-policy error otherwise).
      - Requires an initialized session (Initialize-IDBridge — safe on a fresh install:
        Google auth is acquired by Invoke-IDBridge at run time, not at initialization).

.PARAMETER ProjectId
    Globally-unique GCP project ID (lowercase letters/digits/hyphens). With -CreateProject
    it defaults to 'idbridge-<random>'; without it, the ID of the existing project to use.

.PARAMETER ProjectName
    Display name for a created project. Defaults to 'IDBridge'.

.PARAMETER CreateProject
    Create the project (under the district's organization when one exists).

.PARAMETER ServiceAccountName
    Service account ID (6-30 chars, lowercase). Defaults to 'idbridge'.

.PARAMETER AccessToken
    A cloud-platform-scoped access token as a SecureString, skipping the interactive tiers
    (e.g. from 'gcloud auth print-access-token' on another machine). The admin-role steps
    need the admin.directory.rolemanagement scope, which cloud-platform tokens don't carry
    — expect a one-time prompt for a second OAuth Playground token during those steps.

.EXAMPLE
    Initialize-IDBridgeGoogleServiceAccount -CreateProject

    Full bootstrap for a new district: browser sign-in, new 'IDBridge' project, service
    account, key seeded to the vault, checklist printed.

.EXAMPLE
    Initialize-IDBridgeGoogleServiceAccount -ProjectId 'idbridge-123456'

    Re-run against an existing project (e.g. to re-create the key after a vault loss).

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2026-07-02
    Purpose: One-command Google-side setup for new IDBridge deployments.

.LINK
    https://developers.google.com/oauthplayground
#>

function Initialize-IDBridgeGoogleServiceAccount() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$false)]
        [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')]
        [string]$ProjectId,

        [parameter(Mandatory=$false)]
        [string]$ProjectName = 'IDBridge',

        [parameter(Mandatory=$false)]
        [switch]$CreateProject,

        [parameter(Mandatory=$false)]
        [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')]
        [string]$ServiceAccountName = 'idbridge',

        [parameter(Mandatory=$false)]
        [securestring]$AccessToken
    )

    # Fail fast if the session isn't initialized — the vault seeding at the end needs it,
    # and by then the token prompt and Google-side creation have already happened.
    $null = Get-IDBridgeConfig

    if ($CreateProject -and -not $ProjectId) {
        $ProjectId = "idbridge-$(Get-Random -Minimum 100000 -Maximum 999999)"
    }
    if (-not $ProjectId) {
        Throw "Provide -ProjectId (an existing project) or -CreateProject to make a new one."
    }

    #region Helper functions

    # Invoke a Google API call with the bootstrap token, unwrapping Google's error JSON.
    function Invoke-BootstrapApi {
        param([string]$Method, [string]$Uri, $Body)
        $params = @{ Method = $Method; Uri = $Uri; Headers = $script:BootstrapHeaders; ErrorAction = 'Stop' }
        if ($null -ne $Body) {
            $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
            $params['ContentType'] = 'application/json'
        }
        Invoke-RestMethod @params
    }

    # Poll a long-running operation URL until done (project creation, API enablement).
    function Wait-BootstrapOperation {
        param([string]$OperationUri)
        for ($i = 0; $i -lt 30; $i++) {
            $operation = Invoke-BootstrapApi -Method Get -Uri $OperationUri
            if ($operation.done) {
                if ($operation.error) { Throw "Operation failed: $($operation.error.message)" }
                return $operation
            }
            Start-Sleep -Seconds 2
        }
        Throw "Timed out waiting for operation: $OperationUri"
    }

    # Best available error text from a failed Invoke-RestMethod (Google's JSON body when present).
    function Get-BootstrapError {
        param($ErrorRecord)
        if (-not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) { return $ErrorRecord.ErrorDetails.Message }
        return $ErrorRecord.Exception.Message
    }

    # Invoke an Admin SDK call, prompting once for a role-management-scoped token if the
    # bootstrap token can't carry it (cloud-platform tokens from gcloud/-AccessToken can't).
    function Invoke-BootstrapAdminApi {
        param([string]$Method, [string]$Uri, $Body)
        try { Invoke-BootstrapApi -Method $Method -Uri $Uri -Body $Body }
        catch {
            if ($_.ErrorDetails.Message -notmatch 'ACCESS_TOKEN_SCOPE_INSUFFICIENT|[Ii]nsufficient') { Throw }
            Write-Host "The bootstrap token does not carry the Admin SDK role-management scope." -ForegroundColor Yellow
            Write-Host "Opening the OAuth 2.0 Playground: authorize the scope" -ForegroundColor Cyan
            Write-Host "  https://www.googleapis.com/auth/admin.directory.rolemanagement" -ForegroundColor Cyan
            Write-Host "(Step 1 -> Authorize APIs -> sign in as the district super admin -> Step 2 -> Exchange authorization code), then copy the access_token." -ForegroundColor Cyan
            Start-Process 'https://developers.google.com/oauthplayground/'
            $pastedToken = Read-Host -Prompt "Paste the access token" -AsSecureString
            $script:BootstrapHeaders = @{ Authorization = "Bearer $(ConvertFrom-SecureString -SecureString $pastedToken -AsPlainText)" }
            Invoke-BootstrapApi -Method $Method -Uri $Uri -Body $Body
        }
    }

    # Flatten the Admin SDK privilege tree (privileges nest via childPrivileges).
    function Expand-BootstrapPrivilege {
        param($Privileges)
        foreach ($privilege in $Privileges) {
            $privilege
            if ($privilege.childPrivileges) { Expand-BootstrapPrivilege -Privileges $privilege.childPrivileges }
        }
    }

    #endregion Helper functions


    #region Resolve the bootstrap token
    $plainToken = $null

    if ($AccessToken) {
        $plainToken = ConvertFrom-SecureString -SecureString $AccessToken -AsPlainText
        Write-Log -Message "Bootstrap: Using the supplied access token." -Level Trace
    }
    elseif (Get-Command gcloud -ErrorAction SilentlyContinue) {
        $plainToken = (& gcloud auth print-access-token 2>$null)
        if (-not $plainToken) {
            Write-Host "Opening a browser via 'gcloud auth login' - sign in as the DISTRICT's super admin." -ForegroundColor Cyan
            & gcloud auth login --quiet 2>$null | Out-Null
            $plainToken = (& gcloud auth print-access-token 2>$null)
        }
        if (-not $plainToken) { Throw "gcloud could not produce an access token. Run 'gcloud auth login' manually and retry." }
        Write-Log -Message "Bootstrap: Acquired token via gcloud." -Level Trace
    }
    else {
        Write-Host "Opening the OAuth 2.0 Playground: authorize BOTH scopes (space-separated, in 'Input your own scopes')" -ForegroundColor Cyan
        Write-Host "  https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/admin.directory.rolemanagement" -ForegroundColor Cyan
        Write-Host "(the second scope covers the admin-role steps - one token does the whole bootstrap)" -ForegroundColor Cyan
        Write-Host "(Step 1 -> Authorize APIs -> sign in as the district super admin -> Step 2 -> Exchange authorization code), then copy the access_token." -ForegroundColor Cyan
        Start-Process 'https://developers.google.com/oauthplayground/'
        $pastedToken = Read-Host -Prompt "Paste the access token" -AsSecureString
        $plainToken = ConvertFrom-SecureString -SecureString $pastedToken -AsPlainText
    }

    $script:BootstrapHeaders = @{ Authorization = "Bearer $plainToken" }
    #endregion Resolve the bootstrap token


    #region Find the organization
    $orgName = $null
    try {
        $orgSearch = Invoke-BootstrapApi -Method Get -Uri 'https://cloudresourcemanager.googleapis.com/v3/organizations:search'
        if ($orgSearch.organizations) {
            $orgName = $orgSearch.organizations[0].name    # 'organizations/<number>'
            Write-Log -Message "Bootstrap: Found organization $orgName ($($orgSearch.organizations[0].displayName))."
        }
    }
    catch {
        Write-Log -Message "Bootstrap: Organization search failed ($($_.Exception.Message)); continuing without an organization parent." -Level Warn
    }

    if (-not $orgName -and $CreateProject) {
        # A brand-new domain has no org until someone accepts the Cloud console terms — a
        # deliberate human step with no API. Open the console and wait for the org to appear.
        Write-Host "No Google Cloud organization exists for this domain yet." -ForegroundColor Yellow
        Write-Host "Opening the Cloud console - sign in as the district super admin and accept the terms, then leave this window open." -ForegroundColor Cyan
        Start-Process 'https://console.cloud.google.com/'

        for ($i = 0; $i -lt 30 -and -not $orgName; $i++) {
            Start-Sleep -Seconds 10
            try {
                $orgSearch = Invoke-BootstrapApi -Method Get -Uri 'https://cloudresourcemanager.googleapis.com/v3/organizations:search'
                if ($orgSearch.organizations) { $orgName = $orgSearch.organizations[0].name }
            } catch { }
        }
        if ($orgName) { Write-Log -Message "Bootstrap: Organization provisioned: $orgName." }
        else { Write-Log -Message "Bootstrap: No organization appeared after 5 minutes; creating the project without a parent." -Level Warn }
    }
    #endregion Find the organization


    #region Create the project
    if ($CreateProject) {
        $projectBody = @{ projectId = $ProjectId; displayName = $ProjectName }
        if ($orgName) { $projectBody['parent'] = $orgName }

        try {
            $operation = Invoke-BootstrapApi -Method Post -Uri 'https://cloudresourcemanager.googleapis.com/v3/projects' -Body $projectBody
            $null = Wait-BootstrapOperation -OperationUri "https://cloudresourcemanager.googleapis.com/v3/$($operation.name)"
            Write-Log -Message "Bootstrap: Created project '$ProjectId' (display name '$ProjectName')."
        }
        catch {
            if ($_.ErrorDetails.Message -match 'ALREADY_EXISTS|alreadyExists') {
                Write-Log -Message "Bootstrap: Project '$ProjectId' already exists; continuing." -Level Warn
            }
            else { Throw "Error creating project '$ProjectId': $(Get-BootstrapError $_)" }
        }
    }
    #endregion Create the project


    #region Enable APIs
    $apiIds = @('admin.googleapis.com', 'sheets.googleapis.com', 'licensing.googleapis.com', 'iam.googleapis.com')
    try {
        $operation = Invoke-BootstrapApi -Method Post -Uri "https://serviceusage.googleapis.com/v1/projects/$ProjectId/services:batchEnable" -Body @{ serviceIds = $apiIds }
        if ($operation.name -and $operation.name -ne 'operations/noop') {
            $null = Wait-BootstrapOperation -OperationUri "https://serviceusage.googleapis.com/v1/$($operation.name)"
        }
        Write-Log -Message "Bootstrap: Enabled APIs on '$ProjectId': $($apiIds -join ', ')."
    }
    catch { Throw "Error enabling APIs on '$ProjectId': $(Get-BootstrapError $_)" }
    #endregion Enable APIs


    #region Create the service account
    $serviceAccountEmail = "$ServiceAccountName@$ProjectId.iam.gserviceaccount.com"
    try {
        $serviceAccount = Invoke-BootstrapApi -Method Post -Uri "https://iam.googleapis.com/v1/projects/$ProjectId/serviceAccounts" -Body @{
            accountId      = $ServiceAccountName
            serviceAccount = @{ displayName = 'IDBridge' }
        }
        Write-Log -Message "Bootstrap: Created service account $($serviceAccount.email)."
    }
    catch {
        if ($_.ErrorDetails.Message -match 'ALREADY_EXISTS|alreadyExists') {
            $serviceAccount = Invoke-BootstrapApi -Method Get -Uri "https://iam.googleapis.com/v1/projects/$ProjectId/serviceAccounts/$serviceAccountEmail"
            Write-Log -Message "Bootstrap: Service account $($serviceAccount.email) already exists; continuing." -Level Warn
        }
        else { Throw "Error creating service account '$ServiceAccountName': $(Get-BootstrapError $_)" }
    }
    #endregion Create the service account


    #region Create the key (with the org-policy dance only if actually blocked)
    $keyUri = "https://iam.googleapis.com/v1/projects/$ProjectId/serviceAccounts/$($serviceAccount.email)/keys"
    $keyJson = $null
    $grantedPolicyAdmin = $false
    $adminMember = $null

    try {
        $key = Invoke-BootstrapApi -Method Post -Uri $keyUri -Body @{}
        $keyJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.privateKeyData))
    }
    catch {
        if ($_.ErrorDetails.Message -notmatch 'disableServiceAccountKeyCreation|Key creation is not allowed') {
            Throw "Error creating the service account key: $(Get-BootstrapError $_)"
        }

        # Blocked by the org policy. Self-grant Organization Policy Administrator (a Workspace
        # super admin may grant org roles), exempt this project, retry, then revoke below.
        Write-Log -Message "Bootstrap: Key creation is blocked by iam.disableServiceAccountKeyCreation; attempting a project-level exemption." -Level Warn
        if (-not $orgName) { Throw "Key creation is blocked by org policy but no organization is visible to this account. Ask the district's GCP admin to exempt project '$ProjectId' from iam.disableServiceAccountKeyCreation." }

        # Identify the admin for the IAM binding (email is in the token when our OAuth flow ran)
        try { $tokenInfo = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/tokeninfo?access_token=$plainToken" -ErrorAction Stop } catch { $tokenInfo = $null }
        $adminEmail = $tokenInfo.email
        if (-not $adminEmail) { $adminEmail = Read-Host -Prompt "Enter the email of the admin you signed in as (for the temporary role grant)" }
        $adminMember = "user:$adminEmail"

        try {
            $orgPolicy = Invoke-BootstrapApi -Method Post -Uri "https://cloudresourcemanager.googleapis.com/v3/$($orgName):getIamPolicy" -Body @{}
            $binding = $orgPolicy.bindings | Where-Object { $_.role -eq 'roles/orgpolicy.policyAdmin' }
            if ($binding -and $binding.members -notcontains $adminMember) { $binding.members += $adminMember }
            elseif (-not $binding) {
                $orgPolicy.bindings += [PSCustomObject]@{ role = 'roles/orgpolicy.policyAdmin'; members = @($adminMember) }
            }
            $null = Invoke-BootstrapApi -Method Post -Uri "https://cloudresourcemanager.googleapis.com/v3/$($orgName):setIamPolicy" -Body @{ policy = $orgPolicy }
            $grantedPolicyAdmin = $true
            Write-Log -Message "Bootstrap: Temporarily granted roles/orgpolicy.policyAdmin to $adminEmail."
        }
        catch {
            Throw "Could not grant the Organization Policy Administrator role ($(Get-BootstrapError $_)). Ask the district's GCP admin to run: gcloud org-policies reset iam.disableServiceAccountKeyCreation --project=$ProjectId"
        }

        # Set the exemption and retry the key — IAM grants can take a minute to propagate.
        $exemptionBody = @{
            name = "projects/$ProjectId/policies/iam.disableServiceAccountKeyCreation"
            spec = @{ rules = @(@{ enforce = $false }) }
        }
        for ($i = 0; $i -lt 9 -and -not $keyJson; $i++) {
            try {
                try { $null = Invoke-BootstrapApi -Method Post -Uri "https://orgpolicy.googleapis.com/v2/projects/$ProjectId/policies" -Body $exemptionBody }
                catch {
                    if ($_.ErrorDetails.Message -match 'ALREADY_EXISTS|alreadyExists') {
                        $null = Invoke-BootstrapApi -Method Patch -Uri "https://orgpolicy.googleapis.com/v2/projects/$ProjectId/policies/iam.disableServiceAccountKeyCreation" -Body $exemptionBody
                    } else { Throw }
                }
                $key = Invoke-BootstrapApi -Method Post -Uri $keyUri -Body @{}
                $keyJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($key.privateKeyData))
            }
            catch { Start-Sleep -Seconds 10 }
        }
        if (-not $keyJson) { Throw "Key creation still blocked after the org-policy exemption. Wait a few minutes and re-run with -ProjectId '$ProjectId' (everything so far is idempotent)." }
    }
    Write-Log -Message "Bootstrap: Created a key for $($serviceAccount.email) (kept in memory only)."
    #endregion Create the key


    #region Seed the vault and clean up
    Set-IDBridgeSecret -Name 'GoogleAuth-ServiceAccount' -Secret (ConvertTo-SecureString $keyJson -AsPlainText -Force)
    $keyJson = $null

    if ($grantedPolicyAdmin) {
        try {
            $orgPolicy = Invoke-BootstrapApi -Method Post -Uri "https://cloudresourcemanager.googleapis.com/v3/$($orgName):getIamPolicy" -Body @{}
            foreach ($binding in ($orgPolicy.bindings | Where-Object { $_.role -eq 'roles/orgpolicy.policyAdmin' })) {
                $binding.members = @($binding.members | Where-Object { $_ -ne $adminMember })
            }
            $orgPolicy.bindings = @($orgPolicy.bindings | Where-Object { $_.members.Count -gt 0 })
            $null = Invoke-BootstrapApi -Method Post -Uri "https://cloudresourcemanager.googleapis.com/v3/$($orgName):setIamPolicy" -Body @{ policy = $orgPolicy }
            Write-Log -Message "Bootstrap: Revoked the temporary roles/orgpolicy.policyAdmin grant."
        }
        catch { Write-Log -Message "Bootstrap: Could not revoke the temporary policyAdmin role — remove $adminMember from roles/orgpolicy.policyAdmin on $orgName manually. ($($_.Exception.Message))" -Level Warn }
    }
    #endregion Seed the vault and clean up


    #region Create the IDBridge admin role and assign it to the service account
    # The service account authenticates as ITSELF — a custom Workspace admin role (not
    # domain-wide delegation) authorizes its Admin SDK calls. Privileges are resolved from
    # privileges.list at run time because their serviceIds vary per customer.
    $adminApiBase = 'https://admin.googleapis.com/admin/directory/v1/customer/my_customer'

    try {
        $privilegeCatalog = Invoke-BootstrapAdminApi -Method Get -Uri "$adminApiBase/roles/ALL/privileges"
    }
    catch { Throw "Error listing Admin SDK privileges: $(Get-BootstrapError $_)" }
    $allPrivileges = Expand-BootstrapPrivilege -Privileges $privilegeCatalog.items

    # Licensing privileges are optional (feature-gated by Google.enableLicenseRemoval); the
    # rest are required. LICENSING covers Enterprise License Manager writes and
    # LICENSING_READ the per-run assignment reads (catalog names — the Admin console calls
    # this "License Management").
    $requiredPrivilegeNames = @('USERS_ALL', 'ORGANIZATION_UNITS_ALL', 'GROUPS_ALL')
    $optionalPrivilegeNames = @('LICENSING', 'LICENSING_READ')
    $rolePrivileges = @()
    foreach ($privilegeName in ($requiredPrivilegeNames + $optionalPrivilegeNames)) {
        $match = $allPrivileges | Where-Object { $_.privilegeName -eq $privilegeName } | Select-Object -First 1
        if ($match) {
            $rolePrivileges += @{ privilegeName = $match.privilegeName; serviceId = $match.serviceId }
        }
        elseif ($privilegeName -in $requiredPrivilegeNames) {
            Throw "Privilege '$privilegeName' was not found in this customer's privileges list — cannot build the IDBridge admin role."
        }
        else {
            Write-Log -Message "Bootstrap: Privilege '$privilegeName' not found; the role is created without it (license removal will need it later)." -Level Warn
        }
    }

    # Find or create the role (roleName is unique per customer); patch privileges when it
    # already exists so a re-run converges an older role to the current set.
    $role = $null
    $rolesUri = "$adminApiBase/roles?maxResults=100"
    do {
        $rolesPage = Invoke-BootstrapAdminApi -Method Get -Uri $rolesUri
        $role = $rolesPage.items | Where-Object { $_.roleName -eq 'IDBridge' } | Select-Object -First 1
        $rolesUri = if ($rolesPage.nextPageToken) { "$adminApiBase/roles?maxResults=100&pageToken=$($rolesPage.nextPageToken)" }
    } while (-not $role -and $rolesUri)

    try {
        if ($role) {
            $role = Invoke-BootstrapAdminApi -Method Patch -Uri "$adminApiBase/roles/$($role.roleId)" -Body @{ rolePrivileges = $rolePrivileges }
            Write-Log -Message "Bootstrap: Admin role 'IDBridge' already exists; privileges converged ($($rolePrivileges.privilegeName -join ', '))." -Level Warn
        }
        else {
            $role = Invoke-BootstrapAdminApi -Method Post -Uri "$adminApiBase/roles" -Body @{
                roleName        = 'IDBridge'
                roleDescription = 'IDBridge service account - user, org unit, group, and license management'
                rolePrivileges  = $rolePrivileges
            }
            Write-Log -Message "Bootstrap: Created admin role 'IDBridge' ($($rolePrivileges.privilegeName -join ', '))."
        }
    }
    catch { Throw "Error creating/updating the 'IDBridge' admin role: $(Get-BootstrapError $_)" }

    # Assign the role to the service account (assignedTo = the SA's IAM uniqueId).
    $assignment = $null
    $assignmentsUri = "$adminApiBase/roleassignments?roleId=$($role.roleId)&maxResults=200"
    do {
        $assignmentsPage = Invoke-BootstrapAdminApi -Method Get -Uri $assignmentsUri
        $assignment = $assignmentsPage.items | Where-Object { $_.assignedTo -eq $serviceAccount.uniqueId } | Select-Object -First 1
        $assignmentsUri = if ($assignmentsPage.nextPageToken) { "$adminApiBase/roleassignments?roleId=$($role.roleId)&maxResults=200&pageToken=$($assignmentsPage.nextPageToken)" }
    } while (-not $assignment -and $assignmentsUri)

    if ($assignment) {
        Write-Log -Message "Bootstrap: Role 'IDBridge' is already assigned to $($serviceAccount.email); continuing." -Level Warn
    }
    else {
        try {
            $null = Invoke-BootstrapAdminApi -Method Post -Uri "$adminApiBase/roleassignments" -Body @{
                roleId     = $role.roleId
                assignedTo = $serviceAccount.uniqueId
                scopeType  = 'CUSTOMER'
            }
            Write-Log -Message "Bootstrap: Assigned admin role 'IDBridge' to $($serviceAccount.email)."
        }
        catch { Throw "Error assigning the 'IDBridge' role to $($serviceAccount.email): $(Get-BootstrapError $_)" }
    }
    #endregion Create the IDBridge admin role and assign it to the service account


    #region Finish checklist
    Write-Host ""
    Write-Host "================ MANUAL FINISH STEPS (no API exists for these) ================" -ForegroundColor Green
    Write-Host "1. Share the Google Sheets IDBridge uses (staff source sheet, log sheet) with:" -ForegroundColor Green
    Write-Host "     $($serviceAccount.email)" -ForegroundColor Cyan
    Write-Host "   (Editor access - the service account reads sources and writes logs as itself.)"
    Write-Host "2. Verify the auth chain (no pipeline run): Connect-IDBridgeGoogle"
    Write-Host "   (Role assignments can take a few minutes to propagate; a 403 right away is normal.)"
    Write-Host "3. Full verification: Invoke-IDBridge -ReadOnly"
    Write-Host "4. If this deployment previously used domain-wide delegation, remove the grant" -ForegroundColor Yellow
    Write-Host "   AFTER step 3 passes: https://admin.google.com/ac/owl/domainwidedelegation" -ForegroundColor Yellow
    Write-Host "==============================================================================" -ForegroundColor Green

    return [PSCustomObject]@{
        ProjectId           = $ProjectId
        ServiceAccountEmail = $serviceAccount.email
        ClientId            = $serviceAccount.uniqueId
        RoleId              = $role.roleId
    }
    #endregion Finish checklist
}
