function Merge-IDBridgeOverrideData {
    <#
    .SYNOPSIS
        Applies override data onto source data so override values win during processing.
    .DESCRIPTION
        For each source item, finds matching overrides by personID and applies any non-empty
        override property. Override values are applied unconditionally (no check for existing
        data in the target field). Empty/whitespace overrides are skipped. AddGroup/RemoveGroup
        are treated specially, mutating GroupsProposed rather than overwriting it.

        This lets override plugins reshape source data dynamically without touching the original
        source-gathering plugins.
    .OUTPUTS
        The source objects, with overrides applied (also mutated in place).
    #>
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