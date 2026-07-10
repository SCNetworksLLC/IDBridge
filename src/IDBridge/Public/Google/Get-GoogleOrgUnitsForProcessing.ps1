<#
.SYNOPSIS
Return the Google OU paths that need creating, ordered parents-first.

.DESCRIPTION
Collects the OU paths referenced by active users (their org OU + trash OU), expands each path to
include every ancestor (e.g. /A/B/C -> /A, /A/B, /A/B/C), removes paths that already exist, and
sorts shallowest-first so parents are created before children.

.PARAMETER UserList
The enriched source records. Only active users are considered.

.PARAMETER CurrentOrgUnits
The OU paths that already exist in Google, used to filter out OUs that don't need creating.

.OUTPUTS
[string[]] the OU paths to create, parents-first.

.EXAMPLE
$ous = Get-GoogleOrgUnitsForProcessing -UserList $sourceData -CurrentOrgUnits $googleData.OrgUnits.orgUnitPath

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleOrgUnitsForProcessing {
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentOrgUnits
    )

    #Add the OUs to check from only active users
    $OUList = @()
    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true}) {
        $OUList += $item.GoogleOrganizationalUnit
        $OUList += $item.GoogleOrganizationalUnitTrash
    }

    #Expand all OUs to include every ancestor path
    $OUListExpanded = @()
    foreach ($ou in $OUList) {
        $parts = $ou.TrimStart('/').Split('/')
        for ($i = 1; $i -le $parts.Count; $i++) {
            $OUListExpanded += '/' + ($parts[0..($i-1)] -join '/')
        }
    }

    #Create list for processing - deduplicated, missing only, sorted by depth (parent-first)
    $OrgUnitsForProcessing = $OUListExpanded |
        Sort-Object -Unique |
        Where-Object { $_ -notin $CurrentOrgUnits } |
        Sort-Object { ($_ -split '/').Count }

    foreach ($item in $OrgUnitsForProcessing) {
        Write-Log -Message "Google: Adding Org Unit to Process List: Create: $($item)"
    }

    return $OrgUnitsForProcessing | Sort-Object -Unique
}