function Get-GoogleOrgUnitsForProcessing {
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $UserRootOU,

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