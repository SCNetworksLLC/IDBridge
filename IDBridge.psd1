@{
    RootModule        = 'IDBridge.psm1'
    ModuleVersion     = '26.5.29.0'
    GUID              = 'a0a0c664-888e-44e2-9c12-fc8647a520c0'
    Author            = 'Sam Cattanach'
    Description       = 'IdentityBridge — automated account provisioning for Google Workspace and Active Directory from school SIS/GSheet data.'
    PowerShellVersion = '7.5'

    # Explicitly list public functions so the module surface is intentional.
    # Internal helpers (private functions called only within other functions) are NOT listed here.
    FunctionsToExport = @(
        # Source data
        'Get-SourceDataGSheet'
        'Get-SourceDataSkywardSMS'
        'Get-SourceDataInfiniteCampus'

        # Target data
        'Get-TargetDataGoogle'
        'Get-TargetDataAD'

        # AD processing
        'Get-ADOrgUnitsForProcessing'
        'Get-ADUsersToSetEmployeeID'
        'Get-ADUsersToDeactivate'
        'Get-ADUsersToUpdate'
        'Get-ADUsersToCreate'
        'Get-ADUserGroupsToUpdate'
        'New-IDBridgeADOrgUnit'
        'Disable-IDBridgeADUser'
        'Show-GroupsNotProcessedAD'

        # Google processing
        'Get-GoogleData'
        'Get-GoogleOrgUnitsForProcessing'
        'Get-GoogleUsersToSetEmployeeID'
        'Get-GoogleUsersToDeactivate'
        'Get-GoogleUsersToUpdate'
        'Get-GoogleUsersToCreate'
        'Get-GoogleUserGroupsToUpdate'
        'Get-GoogleUsersOrphaned'
        'New-IDBridgeGoogleOrgUnit'
        'New-IDBridgeGoogleUser'
        'Update-IDBridgeGoogleUser'
        'Update-GoogleGroupMembers'
        'Show-GroupsNotProcessedGoogle'

        # Google Sheets helpers
        'Get-GoogleSheetData'
        'Get-SheetIdByName'
        'Get-ColumnLetter'
        'Convert-CellToIndex'
        'Set-GSheetData'
        'Set-CheckboxesToFalse'
        'Push-LogsToSheet'

        # Auth & Config
        'Get-GoogleApiAccessToken'
        'Get-IDBridgeConfiguration'
        'Get-OverrideProperties'

        # Logging & lifecycle
        'Write-Log'
        'Start-ScriptEnd'

        # Helpers
        'Get-StudentGrade'
        'Get-RandomPassword'
        'New-Passphrase'

        # Plugins
        "Invoke-Plugin*"
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
}