<#
.SYNOPSIS
Resolve a student's current grade code from their graduation year.

.DESCRIPTION
Determines the active school year by comparing today's date against the grade-advance rollover
date, then maps the supplied graduation year to a grade code. Returns 12..01 for K-12,
KG/K4/PK for the early grades, or GD for years that have already graduated. A graduation year
outside the known range returns $null.

.PARAMETER gradYear
The student's expected graduation year (2000-2099).

.PARAMETER gradeAdvanceDate
The month-day the school year rolls forward, formatted MM-dd (e.g. '08-01'). Before this date
the current calendar year is treated as the school year; on or after it, the next year is used.

.OUTPUTS
[string] grade code (e.g. '12', 'KG', 'PK', 'GD'), or $null when the year is out of range.

.EXAMPLE
Get-StudentGrade -gradYear 2030 -gradeAdvanceDate '08-01'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
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