function Get-StudentGrade() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        [ValidateRange(2000,2099)]
        [int]$gradYear,
        [parameter(Mandatory=$true)]
        $gradeAdvanceDate
    )

    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $currentYear = Get-Date -Format "yyyy"
    $currentYearPlusOne = [int]$currentYear + 1

    if ($currentDate -lt "$currentYear-$gradeAdvanceDate") {
        $schoolYear = $currentYear
    } else {
        $schoolYear = $currentYearPlusOne
    }

    $gradeSet = @{
        ([int]$schoolYear-3) = "GD"
        ([int]$schoolYear-2) = "GD"
        ([int]$schoolYear-1) = "GD"
        [int]$schoolYear = "12"
        ([int]$schoolYear+1) = "11"
        ([int]$schoolYear+2) = "10"
        ([int]$schoolYear+3) = "09"
        ([int]$schoolYear+4) = "08"
        ([int]$schoolYear+5) = "07"
        ([int]$schoolYear+6) = "06"
        ([int]$schoolYear+7) = "05"
        ([int]$schoolYear+8) = "04"
        ([int]$schoolYear+9) = "03"
        ([int]$schoolYear+10) = "02"
        ([int]$schoolYear+11) = "01"
        ([int]$schoolYear+12) = "KG"
        ([int]$schoolYear+13) = "K4"
        ([int]$schoolYear+14) = "PK"
        ([int]$schoolYear+15) = "PK"
        ([int]$schoolYear+16) = "PK"
        ([int]$schoolYear+17) = "PK"
    }

    $gradeSet.($gradYear)
}