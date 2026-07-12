<#
.SYNOPSIS
Grant an account read access to a certificate's private key.

.DESCRIPTION
Adds a read ACE for the given account on the private-key file of a certificate in the
machine store (Cert:\LocalMachine\My). Read access is what an account needs to use the
key — e.g. letting the gMSA that runs scheduled IDBridge jobs decrypt Cms secrets, or
authenticate to Azure Key Vault with a certificate credential.

New-IDBridgeSecretCertificate -GrantRead does this at creation time; use this function
for a certificate that already exists. Machine store only (machine private keys live
under $env:ProgramData\Microsoft\Crypto). Changing the key file's ACL requires an
elevated session. Requires an initialized session (Initialize-IDBridge) because it logs
via Write-Log.

.PARAMETER Thumbprint
Thumbprint of the certificate in Cert:\LocalMachine\My.

.PARAMETER Identity
Account to grant private-key read access, e.g. 'DOMAIN\gMSA-IDBridge$'.

.EXAMPLE
Grant-IDBridgeCertificatePrivateKeyAccess -Thumbprint 'AB12CD34...' -Identity 'DOMAIN\gMSA-IDBridge$'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-10
#>
function Grant-IDBridgeCertificatePrivateKeyAccess {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Thumbprint,

        [Parameter(Mandatory)]
        [string]$Identity
    )

    $cert = Get-Item -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) { Throw "No certificate with thumbprint '$Thumbprint' found in Cert:\LocalMachine\My." }
    if (-not $cert.HasPrivateKey) { Throw "Certificate '$($cert.Subject)' (thumbprint $Thumbprint) has no private key on this machine." }

    try {
        # CNG machine private keys live under ProgramData; find this key's file and add a read ACE.
        $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        $keyFile = Get-ChildItem -Path "$env:ProgramData\Microsoft\Crypto" -Recurse -Filter $rsaKey.Key.UniqueName -ErrorAction Stop
        $acl = Get-Acl -Path $keyFile.FullName
        $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($Identity, 'Read', 'Allow'))
        Set-Acl -Path $keyFile.FullName -AclObject $acl
        Write-Log -Message "Secret: Granted private-key read on '$($cert.Subject)' (thumbprint $Thumbprint) to '$Identity'." -Level Info
    }
    catch { Throw "Granting private-key read on '$($cert.Subject)' (thumbprint $Thumbprint) to '$Identity' failed (elevated session required): $($_)" }
}
