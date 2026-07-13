<#
.SYNOPSIS
Apply override rows onto the source records, matched by person ID.

.DESCRIPTION
For each source record, finds the override rows with the same personID and applies their
non-empty values. Scalar properties overwrite the source field unconditionally; AddGroup and
RemoveGroup mutate GroupsProposed instead of overwriting it; PersonID and null/blank values are
skipped. Records are mutated in place and also returned. Lets override plugins reshape source
data without touching the source-gathering plugins.

.PARAMETER SourceData
The source records to apply overrides to. An empty collection is allowed.

.PARAMETER OverrideData
The override rows (each a PersonID plus one or more override keys). An empty collection returns
SourceData unchanged.

.OUTPUTS
[object[]] the source records with overrides applied.

.EXAMPLE
$sourceData = Merge-IDBridgeOverrideData -SourceData $sourceData -OverrideData $overrideData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Merge-IDBridgeOverrideData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$SourceData,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$OverrideData
    )

    if ($OverrideData.Count -eq 0) {
        return $SourceData
    }

    foreach ($item in $SourceData) {
        $overrideItems = $OverrideData | Where-Object { $_.personID -eq $item.personID }
        if (-not $overrideItems) { continue }

        foreach ($overrideItem in $overrideItems) {
            foreach ($property in $overrideItem.PSObject.Properties) {
                if ($property.Name -eq 'PersonID') { continue }
                if ($null -eq $property.Value -or [string]::IsNullOrWhiteSpace($property.Value)) { continue }

                switch ($property.Name) {
                    'AddGroup' {
                        $item | Add-Member -MemberType NoteProperty -Name GroupsProposed `
                            -Value ($item.GroupsProposed + $property.Value.Trim()) -Force
                    }
                    'RemoveGroup' {
                        $item | Add-Member -MemberType NoteProperty -Name GroupsProposed `
                            -Value ($item.GroupsProposed | Where-Object { $_ -ne $property.Value.Trim() }) -Force
                    }
                    default {
                        $item | Add-Member -MemberType NoteProperty -Name $property.Name `
                            -Value $property.Value -Force
                    }
                }
            }
        }
    }

    return $SourceData
}