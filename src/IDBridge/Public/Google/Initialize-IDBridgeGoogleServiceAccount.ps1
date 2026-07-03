<#
.SYNOPSIS
    Bootstraps the Google service account IDBridge needs — project, APIs, service account,
    and key — as far as Google's APIs allow, then prints the manual finish steps.

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
      5. Creates the service account and reads its uniqueId — the client ID for the
         domain-wide delegation grant.
      6. Creates the JSON key and seeds it STRAIGHT INTO THE VAULT as
         'GoogleAuth-ServiceAccount' — the key never touches disk.
         If key creation is blocked by the iam.disableServiceAccountKeyCreation org policy,
         the function self-grants the admin roles/orgpolicy.policyAdmin (a Workspace super
         admin may grant org roles), sets a project-level exemption, retries, and then
         revokes the temporary role.
      7. Prints the finish checklist: the domain-wide delegation screen (no API exists for
         it), client ID, and the exact scope list from the config.

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
    (e.g. from 'gcloud auth print-access-token' on another machine).

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

    $IDConfig = Get-IDBridgeConfig

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
        Write-Host "Opening the OAuth 2.0 Playground: authorize the scope" -ForegroundColor Cyan
        Write-Host "  https://www.googleapis.com/auth/cloud-platform" -ForegroundColor Cyan
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


    #region Finish checklist
    # Grant the full module scope set (licensing included) so enabling features later
    # never needs another Admin-console visit; token requests stay feature-gated.
    $scopeList = ((Get-IDBridgeGoogleScope -All) -split ' ') -join ",`n  "

    Write-Host ""
    Write-Host "================ MANUAL FINISH STEPS (no API exists for these) ================" -ForegroundColor Green
    Write-Host "1. Domain-wide delegation - as the district super admin, open:" -ForegroundColor Green
    Write-Host "     https://admin.google.com/ac/owl/domainwidedelegation"
    Write-Host "   Add new, with:"
    Write-Host "     Client ID: $($serviceAccount.uniqueId)" -ForegroundColor Cyan
    Write-Host "     Scopes:    $scopeList" -ForegroundColor Cyan
    Write-Host "2. Set GoogleToken.adminEmail in IDBridgeConfig.psd1 to a super admin in the district's domain."
    Write-Host "3. Verify the auth chain (no pipeline run): Connect-IDBridgeGoogle"
    Write-Host "4. Full verification: Invoke-IDBridge -ReadOnly"
    Write-Host "==============================================================================" -ForegroundColor Green

    return [PSCustomObject]@{
        ProjectId           = $ProjectId
        ServiceAccountEmail = $serviceAccount.email
        ClientId            = $serviceAccount.uniqueId
    }
    #endregion Finish checklist
}
