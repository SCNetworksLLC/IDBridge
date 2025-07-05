function Get-UserGroupsStaff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $building,
        [Parameter(Mandatory = $true)]
        $personType,
        [Parameter(Mandatory = $false)]
        $config
    )

    $groups = @()
    $buildingShortName = $config.buildingShortName

    foreach ($groupRule in $config.groups) {
        # Determine if this group applies to the building
        $inBuilding = -not ($groupRule.PSObject.Properties.Name -contains 'buildings') -or ($groupRule.buildings -contains $building)
        # Determine if this group applies to the person type
        $includePT = -not ($groupRule.PSObject.Properties.Name -contains 'includePersonTypes') -or $groupRule.includePersonTypes.Count -eq 0 -or ($personType -in $groupRule.includePersonTypes)
        # Determine if this group should be excluded for the person type
        $excludePT = -not ($groupRule.PSObject.Properties.Name -contains 'excludePersonTypes') -or $groupRule.excludePersonTypes.Count -eq 0 -or ($personType -notin $groupRule.excludePersonTypes)

        if ($inBuilding -and $includePT -and $excludePT) {
            $label = $groupRule.label
            if ($label -like "*{buildingShortName}*") {
                $short = $buildingShortName.$building
                if ($short) {
                    $label = $label -replace "{buildingShortName}", $short
                } else {
                    $label = $label -replace "{buildingShortName}", $building
                }
            }
            $groups += $label
        }
    }
    return $groups
}