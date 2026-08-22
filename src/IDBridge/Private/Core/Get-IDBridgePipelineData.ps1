<#
.SYNOPSIS
Gather and enrich the pipeline's source and directory data (shared prologue).

.DESCRIPTION
The shared gather phase used by Invoke-IDBridge and Approve-IDBridgeNameMismatch so the
sequence lives in one place: acquire the Google bearer token via Connect-IDBridgeGoogle
(when GoogleToken.Enabled), run the configured source plugins, read current Google and AD
state, attach it to the source records (Add-TargetDataAD then Add-TargetDataGoogle),
de-duplicate personIDs, and apply the override rows. Reads the initialized config via
Get-IDBridgeConfig — callers run Initialize-IDBridge and apply their runtime overrides
first. Read-only throughout: nothing here writes to AD or Google. PersonID matching
(Get-*UsersToSetEmployeeID) is NOT done here — Invoke-IDBridge runs it after this,
while Approve-IDBridgeNameMismatch deliberately inspects the pre-matching state.

.OUTPUTS
[pscustomobject] @{ SourceData; ADData; GoogleData }. ADData/GoogleData are $null when
that directory is disabled.

.EXAMPLE
$pipelineData = Get-IDBridgePipelineData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-21
#>
function Get-IDBridgePipelineData {
    [CmdletBinding()]
    param ()

    try { $IDConfig = Get-IDBridgeConfig } catch { Throw }

    #region Google Auth
    # Gated on GoogleToken.Enabled only: -SkipGoogle runs still need headers for Sheets
    # plugins and Google Sheet logging.
    if ($IDConfig.GoogleToken.Enabled -eq $true) {
        try { Connect-IDBridgeGoogle } catch { Throw }
    } else {
        Write-Log -Message "Google API integration is disabled. Google-related functions will be skipped." -Level Trace
    }
    #endregion Google Auth




    #region Plugins
    try {
        $plugins = Invoke-SourcePlugins

        $sourceData = $plugins.SourceData
        $overrideData = $plugins.OverrideData
    }
    catch { Throw }
    #endregion Plugins




    #region Get Google Data
    if ($IDConfig.Google.enabled -eq $true) {
        try {
            $googleData = Get-TargetDataGoogle -ErrorAction Stop
        }
        catch { Throw }
    }
    #endregion Get Google Data




    #region Get Data AD
    if ($IDConfig.AD.enabled -eq $true) {
        try {
            $adData = Get-TargetDataAD -ErrorAction Stop
        }
        catch { Throw }
    }
    #endregion Get Data AD




    #region Target Data Preparation
    if ($IDConfig.AD.enabled -eq $true) {
        $sourceData = Add-TargetDataAD -SourceData $sourceData -ADData $adData
    }

    if ($IDConfig.Google.enabled -eq $true) {
        $sourceData = Add-TargetDataGoogle -SourceData $sourceData -GoogleData $googleData
    }
    #endregion Target Data Preparation




    #region Remove Duplicate IDs
    $sourceData = Remove-IDBridgeDuplicateID -SourceData $sourceData
    #endregion Remove Duplicate IDs




    #region Process Override Data
    $sourceData = Merge-IDBridgeOverrideData -SourceData $sourceData -OverrideData $overrideData
    #endregion Process Override Data

    return [PSCustomObject]@{
        SourceData = $sourceData
        ADData     = $adData
        GoogleData = $googleData
    }
}
