<#
.SYNOPSIS
Select linked AD users that should be deactivated.

.DESCRIPTION
Returns each source record that is inactive or no longer AD-provisioned (IDBActive = $false OR
ProvisionAD = $false) while its current AD account is still enabled. Each is logged (with its
current groups) for the subsequent disable + move-to-trash step.

.PARAMETER UserList
The enriched source records.

.OUTPUTS
[object[]] the source records whose AD accounts should be disabled.

.EXAMPLE
$toDeactivate = Get-ADUsersToDeactivate -UserList $sourceData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-ADUsersToDeactivate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {(($_.IDBActive -eq $false) -or ($_.ProvisionAD -eq $false)) -and $_.ADCurrentUserEnabledStatus -eq $true}) {
        $itemList += $item

        Write-Log -Message ("AD: Proposed: Deactivate User: $($item.PersonID)")

        if ($item.ADCurrentGroups) {
            Write-Log -Message ("AD: Current groups for " + $item.PersonID)
            Write-Log -Message ($item.ADCurrentGroups -join ",")
        }
    }

    return $itemList
}