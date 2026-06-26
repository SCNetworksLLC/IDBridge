<#
.SYNOPSIS
Convert an A1-style cell reference to zero-based row/column indexes.

.DESCRIPTION
Parses a cell reference like 'A1' or 'B2' and returns a hashtable with zero-based row and column
indexes (suitable for a Sheets API GridRange). Throws on an invalid cell format.

.PARAMETER cell
The A1-style cell reference (e.g. 'A1', 'M63').

.OUTPUTS
[hashtable] @{ row; column } (both zero-based).

.EXAMPLE
Convert-CellToIndex -cell 'B2'   # -> @{ row = 1; column = 1 }

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Convert-CellToIndex {
    param (
        [string]$cell
    )

    # Extract column letters and row numbers
    if ($cell -match "^([A-Z]+)(\d+)$") {
        $columnLetters = $matches[1]
        $rowNumber = [int]$matches[2]

        # Convert column letters to zero-based index
        $columnIndex = 0
        foreach ($char in $columnLetters.ToCharArray()) {
            $columnIndex = $columnIndex * 26 + ([int][char]$char - [int][char]'A' + 1)
        }
        $columnIndex-- # Convert to zero-based index

        # Convert row to zero-based index
        $rowIndex = $rowNumber - 1

        return @{
            row = $rowIndex
            column = $columnIndex
        }
    }
    else {
        throw "Invalid cell format. Use format like 'A1', 'B2', etc."
    }
}