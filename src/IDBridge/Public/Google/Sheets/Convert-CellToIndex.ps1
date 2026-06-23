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