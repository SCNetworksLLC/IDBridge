<#
.SYNOPSIS
Convert a zero-based column index to its spreadsheet column letter(s).

.DESCRIPTION
Returns the Excel/Sheets column label for a zero-based column index (0 -> A, 25 -> Z,
26 -> AA) — the same zero-based convention the Sheets API GridRange and
Convert-CellToIndex use. Supports up to two-letter columns (through index 701 = ZZ).

.PARAMETER ColumnNumber
The zero-based column index to convert.

.OUTPUTS
[string] the column letter(s).

.EXAMPLE
Get-ColumnLetter -ColumnNumber 27   # -> AB

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