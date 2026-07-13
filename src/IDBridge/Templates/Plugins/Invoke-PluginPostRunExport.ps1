# User List CSV Export Plugin — IDBridge PostRun plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
Works out of the box — just set Enabled = $true on its descriptor in IDBridgeConfig.psd1.

Writes the user list CSVs defined in $exportFiles below to <RootPath>\Exports, for feeding
downstream systems. Each entry is one output file mapped to the PersonTypeIDs it carries
('1' = student, '2'/'3' = staff) — one file can combine multiple IDs. Edit $exportFiles to
change the files and $exportColumns to change what each row carries.

Exports are skipped on a failed run (a partial dataset must not overwrite the last good
export) and on TestRun (the subset would overwrite the full export the same way). Files
are overwritten on every successful full run, so each CSV is always the latest state.
#>


function Invoke-PluginPostRunExport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    if ($RunResult.Success -ne $true) {
        Write-Log -Message "Plugin: Invoke-PluginPostRunExport skipped - run did not complete successfully." -Level Warn
        return
    }

    if ($RunResult.TestRun -eq $true) {
        Write-Log -Message "Plugin: Invoke-PluginPostRunExport skipped - TestRun subset would overwrite the full exports."
        return
    }

    #Files to write: file name -> the PersonTypeIDs it carries. One file can combine
    #multiple IDs. Edit to suit your downstream systems.
    $exportFiles = [ordered]@{
        'UserList-Staff.csv'    = @('2', '3')
        'UserList-Students.csv' = @('1')
    }

    #Columns written to every export file - edit to suit your downstream systems.
    #SecureStrings (ADKey/GoogleKey) are already scrubbed from the RunResult before plugins run.
    $exportColumns = @(
        'PersonID'
        'NameFirst'
        'NameLast'
        'Username'
        'UPN'
        'EmailAddress'
        'Building'
        'Department'
        'JobTitle'
        'Company'
        'PersonType'
        'PersonTypeID'
        'InternalID'
        'IDBActive'
    )

    foreach ($fileName in $exportFiles.Keys) {
        $personTypeIDs = @($exportFiles[$fileName])
        $exportPath = "$($IDConfig.Paths.ExportsRoot)\$fileName"

        $typeUsers = @($RunResult.SourceData | Where-Object { $_.PersonTypeID -in $personTypeIDs })
        if ($typeUsers.Count -eq 0) {
            Write-Log -Message "Plugin: Invoke-PluginPostRunExport - no users matched PersonTypeIDs $($personTypeIDs -join ', ') - $fileName not written." -Level Warn
            continue
        }

        $typeUsers | Select-Object $exportColumns | Export-Csv -Path $exportPath -NoTypeInformation -Force

        Write-Log -Message "Plugin: Invoke-PluginPostRunExport wrote $($typeUsers.Count) users to $exportPath"
    }
}
