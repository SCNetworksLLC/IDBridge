function Get-UserGroupsStaff() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $building,
        [parameter(Mandatory=$true)]
        $personType
    )

    #Groups Included
    # - Staff (Staff Email Group - Only used for Transport Rules)
    # - All Staff (All Staff Email Group)
    # - Building Staff (ex. High School Staff)
    # - Building Faculty (ex. High School Faculty)
    # - Building Support (ex. High School Support Staff)
    # - Admin Staff Elem
    # - Admin Staff 9-12
    # - All Principals
    # - All Admin Staff
    # - All Professional Staff
    # - All Support Staff
    # - All Assistants
    # - All Secretaries
    # - All Student Teachers
    # - Substitutes
    

    #Initialize Group Variable
    $groups = @()

    #Building Short Name for Groups
    $buildingShortName = @{
        "Grant Elementary" = "Grant"
        "Lincoln Elementary" = "Lincoln"
        "Madison Elementary" = "Madison"
        "Nasonville Elementary" = "Nasonville"
        "Washington Elementary" = "Washington"
        "Alternative High School" = "Alt School"
    }

    #Staff
    ######------------######
    $groups += ("Staff")
    ######------------######

    #All Staff
    ######------------######
    #Buildings to include
    $groupAllStaff = @(
        "Grant Elementary"
        "Lincoln Elementary"
        "Madison Elementary"
        "Nasonville Elementary"
        "Washington Elementary"
        "Middle School"
        "High School"
        "Central Office"
        "Alternative High School"
        "District Wide"
        "IT Department"
    )

    #personTypes to *NOT* include
    $groupAllStaffPersonType = @(
        "Board Member"
        "Coach-Activity Advisor"
        "Non-District Staff"
        "Substitute"
        "Substitute - Long Term"
        "Summer School Staff"
    )

    if ($building -in $groupAllStaff -and $personType -notin $groupAllStaffPersonType) {
        $groups += ("All Staff")
    }
    ######------------######
    
    #All Building Staff
    ######------------######
    #Buildings that need all staff groups
    $groupBuildingStaff = @(
        "Grant Elementary"
        "Lincoln Elementary"
        "Madison Elementary"
        "Nasonville Elementary"
        "Washington Elementary"
        "Middle School"
        "High School"
        "Central Office"
        "4K"
        "Alternative High School"
    )

    #personTypes to *NOT* include
    $groupBuildingStaffPersonType = @(
        "Board Member"
        "Coach-Activity Advisor"
        "Non-District Staff"
        "Substitute"
        "Summer School Staff"
    )

    if ($building -in $groupBuildingStaff -and $personType -notin $groupBuildingStaffPersonType) {
        if ($buildingShortName.$building) {
            $groups += ($buildingShortName.$building + " Staff")
        } else {
            $groups += ($building + " Staff")
        }
    }   
    ######------------######

    #All Building Faculty
    ######------------######
    #Buildings that need faculty groups
    $groupBuildingFaculty = @(
        "Grant Elementary"
        "Lincoln Elementary"
        "Madison Elementary"
        "Nasonville Elementary"
        "Washington Elementary"
        "Middle School"
        "High School"
    )

    #personTypes to include
    $groupBuildingFacultyPersonType = @(
        "Teacher"
        "Principal"
        "Administrator"
        "Student Teacher"
        "Substitute - Long Term"
    )

    if ($building -in $groupBuildingFaculty -and $personType -in $groupBuildingFacultyPersonType) {
        if ($buildingShortName.$building) {
            $groups += ($buildingShortName.$building + " Faculty")
        } else {
            $groups += ($building + " Faculty")
        }
    }
    ######------------######

    #All Building Support
    ######------------######
    #Buildings that need support groups
    $groupBuildingSupport = @(
        "Grant Elementary"
        "Lincoln Elementary"
        "Madison Elementary"
        "Nasonville Elementary"
        "Washington Elementary"
        "Middle School"
        "High School"
    )

    #personTypes to *NOT* include
    $groupBuildingSupportPersonType = @(
        "Teacher"
        "Board Member"
        "Coach-Activity Advisor"
        "Student Teacher"
        "Non-District Staff"
        "Substitute"
        "Substitute - Long Term"
        "Summer School Staff"
        "Superintendent"
        "Administrator"
    )

    if ($building -in $groupBuildingSupport -and $personType -notin $groupBuildingSupportPersonType) {
        if ($buildingShortName.$building) {
            $groups += ($buildingShortName.$building + " Support")
        } else {
            $groups += ($building + " Support")
        }
    }
    ######------------######
    
    #Principal Group Elementary
    ######------------######
    #Buildings to include
    $groupAdminElementary = @(
        "Grant Elementary"
        "Lincoln Elementary"
        "Madison Elementary"
        "Nasonville Elementary"
        "Washington Elementary"
        "Central Office"
    )

    #personTypes to include
    $groupAdminElementaryPersonType = @(
        "Superintendent"
        "Principal"
    )

    if ($building -in $groupAdminElementary -and $personType -in $groupAdminElementaryPersonType) {
        $groups += ("Admin Staff Elem")
    }
    ######------------######
    
    #Principal Group HS/MS
    ######------------######
    #Buildings to include
    $groupAdminSecondary = @(
        "Middle School"
        "High School"
        "Central Office"
    )

    #personTypes to include
    $groupAdminSecondaryPersonType = @(
        "Superintendent"
        "Principal"
    )

    if ($building -in $groupAdminSecondary -and $personType -in $groupAdminSecondaryPersonType) {
        $groups += ("Admin Staff 7-12")
    }
    ######------------######

    #All Principal Group
    ######------------######
    #personTypes to include
    $groupAllPrincipalPersonType = @(
        "Superintendent"
        "Principal"
    )

    if ($personType -in $groupAllPrincipalPersonType) {
        $groups += ("All Principals")
    }
    ######------------######

    #All Admin Group
    ######------------######
    #personTypes to include
    $groupAllAdminPersonType = @(
        "Superintendent"
        "Principal"
        "Administrator"
    )

    if ($personType -in $groupAllAdminPersonType) {
        $groups += ("Admin Staff")
    }
    ######------------######

    #All Professional Staff Group
    ######------------######
    #personTypes to include
    $groupAllProfessionalPersonType = @(
        "Superintendent"
        "Principal"
        "Teacher"
        "Administrator"
    )

    if ($personType -in $groupAllProfessionalPersonType) {
        $groups += ("All Professional Staff")
    }
    ######------------######

    #All Support Staff Group
    ######------------######
    #personTypes to include
    $groupAllSupportPersonType = @(
        "Assistant"
        "Custodian"
        "Custodian Lead"
        "Food Service"
        "Support Staff"
        "Secretary"
    )

    if ($personType -in $groupAllSupportPersonType) {
        $groups += ("All Support Staff")
    }
    ######------------######

    #All Assistants Group
    ######------------######
    #personTypes to include
    $groupAllAssistantsPersonType = @(
        "Assistant"
    )

    if ($personType -in $groupAllAssistantsPersonType) {
        $groups += ("All Assistants")
    }
    ######------------######

    #All Secretaries Group
    ######------------######
    #personTypes to include
    $groupAllSecretariesPersonType = @(
        "Secretary"
    )

    if ($personType -in $groupAllSecretariesPersonType) {
        $groups += ("All Secretaries")
    }
    ######------------######

    #All Student Teachers Group Group
    ######------------######
    #personTypes to include
    $groupAllStudentTeachersPersonType = @(
        "Student Teacher"
    )

    if ($personType -in $groupAllStudentTeachersPersonType) {
        $groups += ("All Student Teachers")
    }
    ######------------######

    #All Substitutes Group Group
    ######------------######
    #personTypes to include
    $groupAllSubstitutesPersonType = @(
        "Substitute"
        "Substitute - Long Term"
    )

    if ($personType -in $groupAllSubstitutesPersonType) {
        $groups += ("All Substitutes")
    }
    ######------------######
    
    $groups
}

function Get-UserGroupsStudent() {
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