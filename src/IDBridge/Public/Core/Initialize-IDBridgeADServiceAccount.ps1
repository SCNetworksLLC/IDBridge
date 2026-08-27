<#
.SYNOPSIS
Bootstrap the gMSA IDBridge runs as: create it, delegate its AD rights, grant it the
secrets certificate.

.DESCRIPTION
One-command AD-side setup for unattended runs — the Active Directory counterpart to
Initialize-IDBridgeGoogleServiceAccount. Run it once, elevated, on the domain-joined
machine that runs IDBridge (the account creating the gMSA and writing the OU ACL needs
the rights to do so, e.g. a domain admin). Each step is idempotent, so re-running is safe.

Steps:
  1. Creates the group Managed Service Account (default 'gMSA-IDBridge') with this
     computer's account in PrincipalsAllowedToRetrieveManagedPassword — no password is
     ever generated, stored, or typed; Windows retrieves it from AD. Requires a usable
     KDS root key in the domain (a fresh 'Add-KdsRootKey' takes ~10 hours to become
     usable; the function explains rather than creating one silently). An existing gMSA
     is kept and any missing computer principals are added.
  2. Delegates least-privilege rights on the managed root OU (AD.userRootOU by default):
       - create organizational units (CreateChild of class organizationalUnit only —
         no OU delete or modify);
       - create user objects, and full control over descendant user objects (the whole
         lifecycle IDBridge drives: update, rename, disable, move to trash);
       - modify group membership (WriteProperty on the 'member' attribute of descendant
         group objects only — no group create or delete).
     Nothing outside the target OU is touched.
  3. Grants the gMSA private-key read on the Cms secrets certificate (via
     Grant-IDBridgeCertificatePrivateKeyAccess) so scheduled runs can decrypt the vault.
     The certificate comes from -CertThumbprint, or is auto-resolved the same way
     Set-IDBridgeSecret finds it. Sites on the DpapiNG or AzKeyVault provider need no
     certificate — pass -SkipCertificateAccess (a missing certificate is otherwise a
     warning, not a failure).

Full control over user objects includes Delete — Move-ADObject (OU moves, deactivate to
trash) requires Delete on the object being moved, so "manage but never delete" cannot be
expressed in the ACL (IDBridge itself never calls Remove-ADUser). The delegation is only
as safe as the OU's population: NEVER place admin or otherwise privileged accounts under
the managed root OU (protected accounts would resist the ACL via AdminSDHolder, but the
rule stands regardless).

After this, run Register-IDBridgeScheduledTask on the IDBridge host to install the
account there and schedule the nightly run. Requires an initialized session
(Initialize-IDBridge) and the ActiveDirectory RSAT module.

.PARAMETER AccountName
gMSA name without the trailing $ (max 15 characters, a sAMAccountName limit). Defaults
to 'gMSA-IDBridge' — the name used throughout the docs.

.PARAMETER TargetOU
Distinguished name of the OU to delegate on. Defaults to AD.userRootOU from
IDBridgeConfig.psd1 — the managed root OU. Must exist.

.PARAMETER ComputerName
Computer account(s) allowed to retrieve the gMSA's password. Defaults to this computer.
Add the new host here (re-run) when IDBridge moves machines.

.PARAMETER CertThumbprint
Thumbprint of the Cms certificate in Cert:\LocalMachine\My to grant private-key read on.
When omitted, the certificate is auto-resolved (Secrets.Cms.Thumbprint, else the single
'CN=IDBridge Secrets' certificate).

.PARAMETER SkipCertificateAccess
Skip the certificate grant entirely — for sites on the DpapiNG or AzKeyVault secrets
provider, where no Cms certificate exists.

.EXAMPLE
Initialize-IDBridgeADServiceAccount

.EXAMPLE
Initialize-IDBridgeADServiceAccount -TargetOU 'OU=YourDistrict,DC=yourdomain,DC=local'

.EXAMPLE
Initialize-IDBridgeADServiceAccount -SkipCertificateAccess   # DpapiNG/AzKeyVault site

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-27
#>
function Initialize-IDBridgeADServiceAccount {
    [CmdletBinding()]
    [OutputType('Microsoft.ActiveDirectory.Management.ADServiceAccount')]
    param (
        [Parameter()]
        [ValidateLength(1, 15)]
        [string]$AccountName = 'gMSA-IDBridge',

        [Parameter()]
        [string]$TargetOU,

        [Parameter()]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [Parameter()]
        [string]$CertThumbprint,

        [Parameter()]
        [switch]$SkipCertificateAccess
    )

    $IDConfig = Get-IDBridgeConfig

    if (-not $TargetOU) { $TargetOU = $IDConfig.AD.userRootOU }
    if ([string]::IsNullOrWhiteSpace($TargetOU)) {
        Throw "No -TargetOU was provided and AD.userRootOU is not set in IDBridgeConfig.psd1."
    }

    try { Import-Module -Name ActiveDirectory -ErrorAction Stop }
    catch { Throw "The ActiveDirectory PowerShell module (RSAT) is required: $($_)" }

    $domain = Get-ADDomain
    $gmsaIdentity = "$($domain.NetBIOSName)\$($AccountName)$"

    try { $null = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop }
    catch { Throw "The delegation target OU '$TargetOU' was not found: $($_)" }

    #region Create the gMSA (or add missing computer principals to an existing one)
    $computers = foreach ($computer in $ComputerName) {
        try { Get-ADComputer -Identity $computer -ErrorAction Stop }
        catch { Throw "Computer account '$computer' was not found in AD: $($_)" }
    }

    $gmsa = Get-ADServiceAccount -Filter "Name -eq '$AccountName'" -Properties PrincipalsAllowedToRetrieveManagedPassword -ErrorAction SilentlyContinue
    if (-not $gmsa) {
        #A gMSA needs a usable KDS root key (EffectiveTime in the past). Checked here so the
        #failure explains itself; skipped quietly where the Kds cmdlets aren't installed —
        #New-ADServiceAccount raises its own key error in that case.
        if (Get-Command -Name Get-KdsRootKey -ErrorAction SilentlyContinue) {
            $usableKeys = @(Get-KdsRootKey -ErrorAction SilentlyContinue | Where-Object { $_.EffectiveTime -le (Get-Date) })
            if ($usableKeys.Count -eq 0) {
                Throw "No usable KDS root key exists in the domain, so a gMSA cannot be created. Create one with 'Add-KdsRootKey' (run by a domain admin; it becomes usable ~10 hours later, once every DC can replicate it) and re-run."
            }
        }

        try {
            New-ADServiceAccount -Name $AccountName -DNSHostName "$($AccountName.ToLower()).$($domain.DNSRoot)" -PrincipalsAllowedToRetrieveManagedPassword $computers -Enabled $true -ErrorAction Stop
            Write-Log -Message "ADBootstrap: Created gMSA '$gmsaIdentity' (password retrievable by: $($ComputerName -join ', '))."
        }
        catch { Throw "Error creating the gMSA '$AccountName': $($_)" }
        $gmsa = Get-ADServiceAccount -Identity $AccountName -Properties PrincipalsAllowedToRetrieveManagedPassword
    } else {
        $currentPrincipals = @($gmsa.PrincipalsAllowedToRetrieveManagedPassword)
        $missing = @($computers | Where-Object { $currentPrincipals -notcontains $_.DistinguishedName })
        if ($missing) {
            try { Set-ADServiceAccount -Identity $AccountName -PrincipalsAllowedToRetrieveManagedPassword ($currentPrincipals + $missing.DistinguishedName) -ErrorAction Stop }
            catch { Throw "Error adding computer principals to the existing gMSA '$AccountName': $($_)" }
            Write-Log -Message "ADBootstrap: gMSA '$gmsaIdentity' already exists; added password retrieval for: $($missing.Name -join ', ')."
        } else {
            Write-Log -Message "ADBootstrap: gMSA '$gmsaIdentity' already exists and covers $($ComputerName -join ', '). <No Action Taken>"
        }
    }
    #endregion Create the gMSA (or add missing computer principals to an existing one)

    #region Delegate rights on the target OU
    #Schema GUIDs are constant across every AD forest.
    $ouClassGuid    = [guid]'bf967aa5-0de6-11d0-a285-00aa003049e2'   #organizationalUnit class
    $userClassGuid  = [guid]'bf967aba-0de6-11d0-a285-00aa003049e2'   #user class
    $groupClassGuid = [guid]'bf967a9c-0de6-11d0-a285-00aa003049e2'   #group class
    $memberAttrGuid = [guid]'bf9679c0-0de6-11d0-a285-00aa003049e2'   #member attribute

    $gmsaSid = [System.Security.Principal.SecurityIdentifier]$gmsa.SID
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $inheritAll = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::All
    $inheritDescendents = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::Descendents

    $delegations = @(
        @{  Description = 'create organizational units (no delete/modify)'
            Rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($gmsaSid, [System.DirectoryServices.ActiveDirectoryRights]::CreateChild, $allow, $ouClassGuid, $inheritAll) }
        @{  Description = 'create user objects'
            Rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($gmsaSid, [System.DirectoryServices.ActiveDirectoryRights]::CreateChild, $allow, $userClassGuid, $inheritAll) }
        @{  Description = 'full control over user objects (includes Delete - required for OU moves)'
            Rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($gmsaSid, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, $allow, $inheritDescendents, $userClassGuid) }
        @{  Description = 'modify group membership (member attribute only)'
            Rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new($gmsaSid, [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty, $allow, $memberAttrGuid, $inheritDescendents, $groupClassGuid) }
    )

    try {
        $aclPath = "AD:\" + $TargetOU
        $acl = Get-Acl -Path $aclPath
        $addedCount = 0
        foreach ($delegation in $delegations) {
            $rule = $delegation.Rule
            $existing = $acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.IdentityReference -eq $gmsaSid -and
                $_.ActiveDirectoryRights -eq $rule.ActiveDirectoryRights -and
                $_.AccessControlType -eq $rule.AccessControlType -and
                $_.ObjectType -eq $rule.ObjectType -and
                $_.InheritedObjectType -eq $rule.InheritedObjectType -and
                $_.InheritanceType -eq $rule.InheritanceType
            }
            if ($existing) {
                Write-Log -Message "ADBootstrap: ACE already present on '$TargetOU': $($delegation.Description). <No Action Taken>"
            } else {
                $acl.AddAccessRule($rule)
                Write-Log -Message "ADBootstrap: Adding ACE on '$TargetOU' for '$gmsaIdentity': $($delegation.Description)."
                $addedCount++
            }
        }
        if ($addedCount -gt 0) { Set-Acl -Path $aclPath -AclObject $acl }
    }
    catch { Throw "Error delegating rights on '$TargetOU' to '$gmsaIdentity': $($_)" }
    #endregion Delegate rights on the target OU

    #region Grant private-key read on the Cms certificate
    if ($SkipCertificateAccess) {
        Write-Log -Message "ADBootstrap: Certificate private-key access skipped (-SkipCertificateAccess)."
    } else {
        $cert = $null
        if ($CertThumbprint) {
            $cert = Get-Item -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction SilentlyContinue
            if (-not $cert) { Throw "No certificate with thumbprint '$CertThumbprint' found in Cert:\LocalMachine\My." }
        } else {
            try { $cert = Resolve-IDBridgeCmsCertificate }
            catch { Write-Log -Message "ADBootstrap: No Cms certificate to grant ($($_.Exception.Message)) - grant later with Grant-IDBridgeCertificatePrivateKeyAccess, or use -SkipCertificateAccess on a DpapiNG/AzKeyVault site." -Level Warn }
        }
        if ($cert -and $cert.PSParentPath -notlike '*LocalMachine*') {
            Write-Log -Message "ADBootstrap: The resolved Cms certificate (thumbprint $($cert.Thumbprint)) is in the CurrentUser store - a scheduled run needs a LocalMachine certificate. Skipping the grant." -Level Warn
            $cert = $null
        }
        if ($cert) {
            try { Grant-IDBridgeCertificatePrivateKeyAccess -Thumbprint $cert.Thumbprint -Identity $gmsaIdentity }
            catch { Throw "The gMSA and OU delegation are in place, but granting private-key read failed: $($_)" }
        }
    }
    #endregion Grant private-key read on the Cms certificate

    Write-Host "gMSA '$gmsaIdentity' is ready. Delegated on '$TargetOU': create OUs, create/manage users, modify group membership." -ForegroundColor Green
    Write-Host "Next: run Register-IDBridgeScheduledTask on the IDBridge host to install the account and schedule the run."
    return $gmsa
}
