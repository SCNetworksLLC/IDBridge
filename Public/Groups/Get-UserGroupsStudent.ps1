function Get-UserGroupsStudent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $building,
        [Parameter(Mandatory = $true)]
        $grade,
        [Parameter(Mandatory = $false)]
        $config
    )

    $groups = @()
    $buildingShortName = $config.buildingShortName

    foreach ($groupRule in $config.groups) {
        $addGroup = $true

        # If the group rule has a 'buildings' property, only add the group if the current building matches.
        # If not, $addGroup remains $true and the group will be added for all buildings.
        if ($groupRule.PSObject.Properties.Name -contains 'buildings') {
            $addGroup = $groupRule.buildings -contains $building
        }

        # For the "Grade Level" group, the JSON rule does NOT have a 'buildings' property.
        # So, $addGroup stays $true and the group is always added, regardless of building.
        # For other groups with a 'buildings' property, $addGroup may be false if the building doesn't match.

        if ($addGroup) {
            $label = $groupRule.label

            if ($label -like "*{buildingShortName}*") {
                $short = $buildingShortName.$building
                if ($short) {
                    $label = $label -replace "{buildingShortName}", $short
                } else {
                    $label = $label -replace "{buildingShortName}", $building
                }
            }
            if ($label -like "*{grade}*") {
                $label = $label -replace "{grade}", $grade
            }
            $groups += $label
        }
    }

    return $groups
}