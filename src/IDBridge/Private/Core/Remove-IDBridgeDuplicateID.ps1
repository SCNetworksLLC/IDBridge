<#
.SYNOPSIS
Drop source records with duplicate person IDs from the processing set.

.DESCRIPTION
Two-pass de-duplication run after target data is attached. Pass 1 removes records already
flagged with ADDuplicateIDStatus/GoogleDuplicateIDStatus (a personID that matches more than one
existing target account). Pass 2 removes every record that shares a personID with another record
in the remaining set (duplicates introduced by the source plugins). Each removal is logged at
Info. The result is always returned as an array, even for zero or one survivor, so that
downstream .Count and indexing stay safe.

.PARAMETER SourceData
The collected source records. Null or an empty collection is allowed.

.OUTPUTS
[object[]] the records that survived de-duplication.

.EXAMPLE
$sourceData = Remove-IDBridgeDuplicateID -SourceData $sourceData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Remove-IDBridgeDuplicateID {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$SourceData
    )

    # Pass 1: users already flagged as duplicates in AD or Google
    $flagged = $SourceData | Where-Object { $_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus }
    foreach ($item in $flagged) {
        Write-Log -Level Info -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - AD Duplicate Status: $($item.ADDuplicateIDStatus) - Google Duplicate Status: $($item.GoogleDuplicateIDStatus)")
    }
    if ($flagged) {
        $SourceData = $SourceData | Where-Object { -not ($_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus) }
    }

    # Pass 2: users sharing a personID within the *remaining* set - Usually indicates duplicates gathered from plugins
    $duplicateIDs = $SourceData |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.personID) } |
        Group-Object -Property personID |
        Where-Object { $_.Count -gt 1 } |
        Select-Object -ExpandProperty Name

    if ($duplicateIDs) {
        foreach ($item in $SourceData | Where-Object { $_.personID -in $duplicateIDs }) {
            Write-Log -Level Info -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - IDBridge Duplicate Status: DUPLICATE_ID")
        }
        $SourceData = $SourceData | Where-Object { $_.personID -notin $duplicateIDs }
    }


    # Guarantee an array return regardless of survivor count (0, 1, or many).
    # Bare Where-Object output unrolls a single survivor to a scalar and null on
    # zero, both of which break downstream .Count / indexing. See about_Operators.
    return ,$SourceData
}











