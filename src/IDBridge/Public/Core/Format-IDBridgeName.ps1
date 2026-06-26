<#
.SYNOPSIS
Title-case a name, capitalizing the first letter after spaces, hyphens, and apostrophes.

.DESCRIPTION
Normalizes a name to title case, e.g. MARY-JANE -> Mary-Jane, O'BRIEN -> O'Brien,
JOSHUA MOIN -> Joshua Moin. Useful for source systems that return all-caps names.

Limitations: it cannot know intentional internal capitals — McDonald, MacLeod, DeForest,
and van der Berg become Mcdonald / Macleod / Deforest / Van Der Berg. Null/empty/whitespace
input is returned unchanged.

.PARAMETER Name
The name to format. Accepts pipeline input.

.EXAMPLE
Format-IDBridgeName 'JOSHUA MOIN'      # -> Joshua Moin

.EXAMPLE
'MARY-JANE','O''BRIEN' | Format-IDBridgeName   # -> Mary-Jane, O'Brien

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Format-IDBridgeName {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [string]$Name
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Name)) { return $Name }

        # Split before each space/hyphen/apostrophe (keeping the separator with the next token).
        ($Name.Trim() -split "(?=[-\s'])") | ForEach-Object {
            if ($_.Length -eq 0) { return }   # skip empty pieces (consecutive separators)

            $sep = ''
            $word = $_
            if ($word -match "^[-\s']") { $sep = $word[0]; $word = $word.Substring(1) }

            if ($word.Length -eq 0) { "$sep" }
            else { "$sep$($word.Substring(0, 1).ToUpper())$($word.Substring(1).ToLower())" }
        } | Join-String
    }
}
