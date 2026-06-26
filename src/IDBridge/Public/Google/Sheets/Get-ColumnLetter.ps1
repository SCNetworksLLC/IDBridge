<#
.SYNOPSIS
Convert a 1-based column number to its spreadsheet column letter(s).

.DESCRIPTION
Returns the Excel/Sheets column label for a 1-based column number (1 -> A, 26 -> Z, 27 -> AA).

.PARAMETER ColumnNumber
The 1-based column number to convert.

.OUTPUTS
[string] the column letter(s).

.EXAMPLE
Get-ColumnLetter -ColumnNumber 28   # -> AB

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-ColumnLetter {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ColumnNumber
    )

    [string]$columnLetter = ''
    # Get the multiple of 26
    [int]$prefix = [math]::Floor($ColumnNumber / 26)
    if($prefix -gt 0){
        # Add prefix column
        $columnLetter += [char]$($prefix + 64)
        $ColumnNumber = $ColumnNumber - $($prefix * 26) + 65
    }
    else{
        $ColumnNumber += 65
    }
    # Get column letter
    $columnLetter += [char]$ColumnNumber
    $columnLetter
}