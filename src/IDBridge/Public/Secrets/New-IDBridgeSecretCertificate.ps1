<#
.SYNOPSIS
Create the self-signed Document Encryption certificate used by the Cms secrets provider.

.DESCRIPTION
Creates the certificate Protect-CmsMessage/Unprotect-CmsMessage need (Document Encryption
EKU 1.3.6.1.4.1.311.80.1, KeyEncipherment + DataEncipherment key usage, RSA 3072,
non-exportable private key) using the in-box PKI module — no external dependency.

By default the certificate goes in the computer store (Cert:\LocalMachine\My), which
requires an elevated session; only SYSTEM and Administrators can decrypt until -GrantRead
adds a private-key read ACL for another principal (e.g. the gMSA that runs scheduled
IDBridge jobs). Use -StoreLocation CurrentUser for a per-user certificate on a dev machine
(no elevation needed).

Put the returned thumbprint in Secrets.Cms.Thumbprint in IDBridgeConfig.psd1. Requires an
initialized session (Initialize-IDBridge) because it logs via Write-Log.

.PARAMETER Subject
Certificate subject. Defaults to 'CN=IDBridge Secrets', which Set-IDBridgeSecret finds
automatically when no thumbprint is configured.

.PARAMETER StoreLocation
'LocalMachine' (default; requires elevation) or 'CurrentUser'.

.PARAMETER ValidityYears
Certificate lifetime in years (default 10). Protect-CmsMessage refuses an expired
certificate; decryption of existing secrets keeps working.

.PARAMETER GrantRead
Account to grant private-key read access, e.g. 'DOMAIN\gMSA-IDBridge$'. Machine store only.

.EXAMPLE
New-IDBridgeSecretCertificate

.EXAMPLE
New-IDBridgeSecretCertificate -GrantRead 'SDOM\gMSA-IDBridge$'

.EXAMPLE
New-IDBridgeSecretCertificate -StoreLocation CurrentUser   # dev machine, no elevation

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function New-IDBridgeSecretCertificate {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter()]
        [string]$Subject = 'CN=IDBridge Secrets',

        [Parameter()]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation = 'LocalMachine',

        [Parameter()]
        [int]$ValidityYears = 10,

        [Parameter()]
        [string]$GrantRead
    )

    $certParams = @{
        Type              = 'DocumentEncryptionCert'
        Subject           = $Subject
        CertStoreLocation = "Cert:\$StoreLocation\My"
        KeyExportPolicy   = 'NonExportable'
        KeyAlgorithm      = 'RSA'
        KeyLength         = 3072
        KeyUsage          = 'KeyEncipherment', 'DataEncipherment'
        NotAfter          = (Get-Date).AddYears($ValidityYears)
        ErrorAction       = 'Stop'
    }
    try { $cert = New-SelfSignedCertificate @certParams }
    catch { Throw "Error creating the CMS certificate in Cert:\$StoreLocation\My (LocalMachine requires an elevated session): $($_)" }

    Write-Log -Message "Secret: Created CMS certificate '$Subject' in Cert:\$StoreLocation\My (thumbprint $($cert.Thumbprint), expires $($cert.NotAfter.ToString('yyyy-MM-dd')))." -Level Info

    if ($GrantRead) {
        try {
            # CNG machine private keys live under ProgramData; find this key's file and add a read ACE.
            $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
            $keyFile = Get-ChildItem -Path "$env:ProgramData\Microsoft\Crypto" -Recurse -Filter $rsaKey.Key.UniqueName -ErrorAction Stop
            $acl = Get-Acl -Path $keyFile.FullName
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($GrantRead, 'Read', 'Allow'))
            Set-Acl -Path $keyFile.FullName -AclObject $acl
            Write-Log -Message "Secret: Granted private-key read on '$Subject' to '$GrantRead'." -Level Info
        }
        catch { Throw "Certificate created (thumbprint $($cert.Thumbprint)) but granting private-key read to '$GrantRead' failed: $($_)" }
    }

    Write-Host "Certificate created. Set Secrets.Cms.Thumbprint = '$($cert.Thumbprint)' in IDBridgeConfig.psd1" -ForegroundColor Green
    return $cert
}
