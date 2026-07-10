<#
.SYNOPSIS
Select linked Google users that should be deactivated.

.DESCRIPTION
Returns each source record that is inactive or no longer Google-provisioned (IDBActive = $false OR
ProvisionGoogle = $false) while its current Google account is not yet deactivated (neither archived
nor suspended — pre-archive suspends stay grandfathered). Each is logged for the subsequent
archive + move-to-trash step, including the paid license assignments that step will remove (from
GoogleCurrentLicenses; the base Education Fundamentals license self-releases on archive) — so
ReadOnly runs show the full license impact. Accounts that were matched by UPN+name (no personID
externalId on the Google account yet) are also flagged: the deactivate step will set the externalId
so the link persists — the update list only covers active users, so without this the same account
would be re-matched every run.

.PARAMETER UserList
The enriched source records.

.OUTPUTS
[object[]] the source records whose Google accounts should be archived.

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

        if ($item.personID -notin $item.GoogleObject.externalIds.value) {
            Write-Log -Message "Google: Deactivation will also set EmployeeID $($item.PersonID) on the Google account (matched by name, externalId not set yet)"
        }

        $itemList += $item
    }

    return $itemList
}