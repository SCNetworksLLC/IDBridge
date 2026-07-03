<#
.SYNOPSIS
Locate the Document Encryption certificate the Cms secrets provider encrypts with (internal).

.DESCRIPTION
Internal helper for the IDBridge secret vault. Resolves the certificate Set-IDBridgeSecret
passes to Protect-CmsMessage:

  - When Secrets.Cms.Thumbprint is configured, that certificate is looked up in the
    LocalMachine and CurrentUser My stores.
  - Otherwise the stores are searched for exactly one unexpired 'CN=IDBridge Secrets'
    certificate with the Document Encryption EKU (as created by New-IDBridgeSecretCertificate).

Throws with a pointer at New-IDBridgeSecretCertificate (none found) or at configuring
Secrets.Cms.Thumbprint (ambiguous match).

.EXAMPLE
$cert = Resolve-IDBridgeCmsCertificate

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Resolve-IDBridgeCmsCertificate {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param ()

    $IDConfig = Get-IDBridgeConfig
    $thumbprint = if ($IDConfig.Secrets -and $IDConfig.Secrets.Cms) { $IDConfig.Secrets.Cms.Thumbprint } else { $null }
    $stores = 'Cert:\LocalMachine\My', 'Cert:\CurrentUser\My'

    if ($thumbprint) {
        foreach ($store in $stores) {
            $cert = Get-Item -Path (Join-Path $store $thumbprint) -ErrorAction SilentlyContinue
            if ($cert) { return $cert }
        }
        Throw "The CMS certificate with thumbprint '$thumbprint' (Secrets.Cms.Thumbprint) was not found in the LocalMachine or CurrentUser My store. Create one with New-IDBridgeSecretCertificate and update the config."
    }

    # No thumbprint configured: fall back to the default subject New-IDBridgeSecretCertificate uses.
    $documentEncryptionOid = '1.3.6.1.4.1.311.80.1'
    $certs = @(foreach ($store in $stores) {
        Get-ChildItem -Path $store -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -eq 'CN=IDBridge Secrets' -and $_.NotAfter -gt (Get-Date) -and $_.EnhancedKeyUsageList.ObjectId -contains $documentEncryptionOid }
    })

    if ($certs.Count -eq 0) {
        Throw "No 'CN=IDBridge Secrets' Document Encryption certificate was found. Create one with New-IDBridgeSecretCertificate, or set Secrets.Cms.Thumbprint to an existing certificate."
    }
    if ($certs.Count -gt 1) {
        Throw "Multiple 'CN=IDBridge Secrets' certificates were found ($(($certs.Thumbprint) -join ', ')). Set Secrets.Cms.Thumbprint in IDBridgeConfig.psd1 to pick one."
    }
    return $certs[0]
}
