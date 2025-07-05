function Get-UserGroupsStudentold() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $building,
        [parameter(Mandatory=$true)]
        $grade
    )

    #Groups Included
    # - All Students (Students)
    # - Building Students (ex. HS_Students)
    # - Student Grade Level (ex. Grade-01)

    #Initialize Group Variable
    $groups = @()

    #Building Short Name for Groups
    $buildingShortName = @{
        "Grant Elementary" = "GE"
        "Lincoln Elementary" = "LE"
        "Madison Elementary" = "ME"
        "Nasonville Elementary" = "NE"
        "Washington Elementary" = "WE"
        "High School" = "HS"
        "Middle School" = "MS"
    }

    #All Students
    ######------------######
    $groups += ("Students")
    ######------------######
    
    #All Building Students
    ######------------######
    if ($building -in $groupBuildingStudent) {
        if ($buildingShortName.$building) {
            $groups += ($buildingShortName.$building + "_Students")
        }
    }
    ######------------######

    #Grade Level Groups
    ######------------######
    $groups += ("Grade-" + $grade)
    ######------------######

    $groups
}