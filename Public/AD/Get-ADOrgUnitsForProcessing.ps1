<#
.SYNOPSIS
    Returns missing AD OUs sorted so parents come before children.

.DESCRIPTION
    Collects every OU path needed by active users, expands each path to include
    all ancestor OUs, filters out ones that already exist, then sorts by depth
    so parents are always created before their children.

.PARAMETER UserList
    Full user list from the identity database. Only active users are processed.

.PARAMETER UserRootOU
    Root OU for users. Retained for consistency but not directly used since
    ancestor expansion covers it automatically.

.PARAMETER CurrentOrgUnits
    OUs that already exist in AD, used to filter out OUs that don't need creating.

.PARAMETER logFile
    Path to the log file.
#>

function Get-ADOrgUnitsForProcessing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $UserRootOU,

        [Parameter(Mandatory = $true)]
        $CurrentOrgUnits,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    # Collect every OU path referenced by active users (active OU + trash OU)
    $OUList = @()
    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true}) {
        $OUList += $item.ADOrganizationalUnit
        $OUList += $item.ADOrganizationalUnitTrash
    }

    # Expand each OU to include all ancestor paths.
    # AD DNs are leaf-first, so "OU=Child,OU=Parent,DC=domain,DC=local" expands to:
    #   OU=Parent,DC=domain,DC=local
    #   OU=Child,OU=Parent,DC=domain,DC=local
    # Using a Generic List instead of += on arrays for better performance.
    $OUListExpanded = [System.Collections.Generic.List[string]]::new()
    foreach ($ou in $OUList) {
        $components  = $ou -split ','
        $ouComponents = $components | Where-Object { $_ -match '^OU=' }
        $baseDC       = $components | Where-Object { $_ -notmatch '^OU=' }

        for ($i = $ouComponents.Count; $i -ge 1; $i--) {
            $ancestor = $ouComponents[($ouComponents.Count - $i)..($ouComponents.Count - 1)]
            $OUListExpanded.Add(($ancestor + $baseDC) -join ',')
        }
    }

    # Use a HashSet for O(1) lookups when filtering out existing OUs
    $currentOUSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$CurrentOrgUnits,
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # Deduplicate, remove existing, sort parents before children
    $OrgUnitsForProcessing = $OUListExpanded |
        Sort-Object -Unique |
        Where-Object { -not $currentOUSet.Contains($_) } |
        Sort-Object { ($_ -split ',OU=').Count }

    foreach ($item in $OrgUnitsForProcessing) {
        Write-Log -Path $logFile -Message "AD: Adding Org Unit to Process List: Create: $($item)"
    }

    return $OrgUnitsForProcessing
}