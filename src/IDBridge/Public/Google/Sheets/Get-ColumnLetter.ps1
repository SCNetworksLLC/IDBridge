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