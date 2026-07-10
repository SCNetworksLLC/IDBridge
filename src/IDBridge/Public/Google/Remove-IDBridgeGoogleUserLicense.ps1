<#
.SYNOPSIS
    Removes a user's Google Workspace license assignments via the Enterprise License
    Manager API.

.DESCRIPTION
    Deletes the license assignments passed in — one DELETE per assignment. The assignments
    come from the target snapshot (Get-TargetDataGoogle attaches each user's licenses as
    CurrentLicenses, flowing to the source records as GoogleCurrentLicenses), so nothing is
    looked up at write time and the decide phase / ReadOnly runs already logged exactly
    what would be removed.

    Called by Invoke-IDBridge during the full deactivation (suspend + move-to-trash) step —
    NOT on a ForceDisable update. On by default; set Google.enableLicenseRemoval = $false
    to disable. Every removed license is logged by SKU name; an error on one assignment
    doesn't stop the rest.

    Requires the https://www.googleapis.com/auth/apps.licensing scope (requested
    automatically while the feature is enabled) and the License Management privilege on
    the service account's 'IDBridge' admin role.

.PARAMETER UserEmail
    The user's current primary email address (the Licensing API user key).

.PARAMETER Assignments
    The user's license assignment objects (productId + skuId, optionally skuName) as
    attached by Get-TargetDataGoogle. An empty or missing list is a no-op.

.EXAMPLE
    Remove-IDBridgeGoogleUserLicense -UserEmail $item.GoogleObject.primaryEmail -Assignments $item.GoogleCurrentLicenses

.NOTES
    Version: 2.0
    Author: Sam Cattanach
    Date: 2026-07-03
    Purpose: Free paid licenses when accounts are deactivated.

.LINK
    https://developers.google.com/workspace/admin/licensing/reference/rest
#>

function Remove-IDBridgeGoogleUserLicense() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # The user's primary email is the Licensing API user key
        [string]$UserEmail,

        [parameter(Mandatory=$false)]  # License assignments from the target snapshot (GoogleCurrentLicenses)
        [AllowEmptyCollection()]
        $Assignments
    )

    if (-not $Assignments) {
        Write-Log -Message "Google: No licenses to remove for $UserEmail." -Level Trace
        return
    }

    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }

    foreach ($assignment in $Assignments) {
        $skuLabel = if ($assignment.skuName) { "$($assignment.skuName) ($($assignment.skuId))" } else { $assignment.skuId }
        $url = "https://licensing.googleapis.com/apps/licensing/v1/product/$([uri]::EscapeDataString($assignment.productId))/sku/$([uri]::EscapeDataString($assignment.skuId))/user/$([uri]::EscapeDataString($UserEmail))"

        try {
            $null = Invoke-RestMethod -Uri $url -Method Delete -Headers $headers -ErrorAction Stop
            Write-Log -Message "Google: Removed license $skuLabel from $UserEmail"
        }
        catch {
            Write-Log -Message "Google: Error removing license $skuLabel from $($UserEmail): $($_.Exception.Message)" -Level Error
        }
    }
}
