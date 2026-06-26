<#
.SYNOPSIS
Validate normalized source records and return only those that pass.

.DESCRIPTION
A thin, pure validator run over each source plugin's output inside Invoke-SourcePlugins.
Records built by New-IDBridgeSourceRecord already have enforced field presence and types, so
this focuses on cross-field business rules plus a safety net for records that bypass the
factory. Invalid records are dropped and logged (Warn) with the plugin name for context; the
remaining valid records are returned as an array.

.PARAMETER InputObject
The records returned by a source plugin. Null or empty is allowed (returns an empty array).

.PARAMETER PluginName
The plugin function name, used for log context.

.EXAMPLE
$sourceData += Test-IDBridgeSourceData -InputObject $pluginData -PluginName $plugin.Function

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-22
#>
function Test-IDBridgeSourceData {
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$InputObject,
        [Parameter(Mandatory)][string]$PluginName
    )

    $valid = [System.Collections.Generic.List[object]]::new()
    $total = 0

    foreach ($record in $InputObject) {
        if ($null -eq $record) { continue }
        $total++
        $reasons = [System.Collections.Generic.List[string]]::new()

        # Safety net (covers records that did not come through New-IDBridgeSourceRecord).
        if ([string]::IsNullOrWhiteSpace([string]$record.PersonID)) { $reasons.Add('missing PersonID') }
        if ($record.IDBActive -isnot [bool]) { $reasons.Add('IDBActive is not a boolean') }

        # Active Directory cross-field rules.
        if ($record.ProvisionAD -eq $true) {
            if ([string]::IsNullOrWhiteSpace([string]$record.ADOrganizationalUnit)) { $reasons.Add('ProvisionAD but ADOrganizationalUnit is empty') }
            if ([string]::IsNullOrWhiteSpace([string]$record.ADOrganizationalUnitTrash)) { $reasons.Add('ProvisionAD but ADOrganizationalUnitTrash is empty') }
            if (($record.ADKey -isnot [securestring]) -and ($record.ADPassphraseAPI -isnot [hashtable])) { $reasons.Add('ProvisionAD but no ADKey or ADPassphraseAPI') }
        }

        # Google Workspace cross-field rules.
        if ($record.ProvisionGoogle -eq $true) {
            if ([string]::IsNullOrWhiteSpace([string]$record.GoogleOrganizationalUnit)) { $reasons.Add('ProvisionGoogle but GoogleOrganizationalUnit is empty') }
            if ([string]::IsNullOrWhiteSpace([string]$record.GoogleOrganizationalUnitTrash)) { $reasons.Add('ProvisionGoogle but GoogleOrganizationalUnitTrash is empty') }
            if (($record.GoogleKey -isnot [securestring]) -and ($record.GooglePassphraseAPI -isnot [hashtable])) { $reasons.Add('ProvisionGoogle but no GoogleKey or GooglePassphraseAPI') }
        }

        if ($reasons.Count -gt 0) {
            $id = if ([string]::IsNullOrWhiteSpace([string]$record.PersonID)) { '<no PersonID>' } else { $record.PersonID }
            Write-Log -Message "Source Data: Plugin $PluginName - skipping PersonID ${id}: $($reasons -join '; ')" -Level Warn
        }
        else {
            $valid.Add($record)
        }
    }

    Write-Log -Message "Source Data: Plugin $PluginName - $($valid.Count)/$total records passed validation." -Level Trace

    return , $valid.ToArray()
}
