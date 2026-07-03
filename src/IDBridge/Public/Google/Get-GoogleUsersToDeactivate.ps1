<#
.SYNOPSIS
Select linked Google users that should be deactivated.

.DESCRIPTION
Returns each source record that is inactive or no longer Google-provisioned (IDBActive = $false OR
ProvisionGoogle = $false) while its current Google account is not yet suspended. Each is logged for
the subsequent suspend + move-to-trash step, including the license assignments that step will
remove (from GoogleCurrentLicenses) — so ReadOnly runs show the full license impact.

.PARAMETER UserList
The enriched source records.

.OUTPUTS
[object[]] the source records whose Google accounts should be suspended.

.EXAMPLE
$toDeactivate = Get-GoogleUsersToDeactivate -UserList $sourceData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleUsersToDeactivate {
    param (
        [Parameter(Mandatory = $true)]
        $UserList
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {(($_.IDBActive -eq $false) -or ($_.ProvisionGoogle -eq $false)) -and $_.GoogleCurrentUserSuspendedStatus -eq $false}) {
        Write-Log -Message "Google: Adding User to Process List: Deactivate: $($item.PersonID)"

        if ($item.GoogleCurrentLicenses) {
            $skuNames = ($item.GoogleCurrentLicenses | ForEach-Object { if ($_.skuName) { $_.skuName } else { $_.skuId } }) -join ', '
            Write-Log -Message "Google: Deactivation will remove licenses from $($item.PersonID): $skuNames"
        }

        $itemList += $item
    }

    return $itemList
}