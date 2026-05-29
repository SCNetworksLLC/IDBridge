@{
    RootModule        = 'IDBridge.psm1'
    ModuleVersion     = '26.4.1.0'
    GUID              = 'a0a0c664-888e-44e2-9c12-fc8647a520c0'
    Author            = 'Sam Cattanach'
    Description       = 'IdentityBridge — automated account provisioning for Google Workspace and Active Directory from school SIS/GSheet data.'
    PowerShellVersion = '7.5'

    # Explicitly list public functions so the module surface is intentional.
    # Internal helpers (private functions called only within other functions) are NOT listed here.
    FunctionsToExport = @(
        # Orchestration (called from IDBridge.ps1)
        'Get-IDBridgeSourceData'
        'Get-IDBridgeTargetData'
        'Build-IDBridgeUserData'
        'Get-IDBridgeProcessingLists'
        'Invoke-IDBridgeADChanges'
        'Invoke-IDBridgeGoogleChanges'
        'Remove-IDBridgeDuplicateUsers'

        # Source data
        'Get-SourceDataGSheet'
        'Get-SourceDataSkywardSMS'
        'Convert-SkywardSMSToIDBridge'

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
        'Get-GoogleOrgUnitsForProcessing'
        'Get-GoogleUsersToSetEmployeeID'
        'Get-GoogleUsersToDeactivate'
        'Get-GoogleUsersToUpdate'
        'Get-GoogleUsersToCreate'
        'Get-GoogleUserGroupsToUpdate'
        'Get-GoogleUsersOrphaned'
        'New-IDBridgeGoogleOrgUnit'
        'Update-IDBridgeGoogleUser'
        'New-IDBridgeGoogleUser'
        'Update-GoogleGroupMembers'
        'Show-GroupsNotProcessedGoogle'

        # Auth & Config
        'Get-GoogleApiAccessToken'
        'Get-IDBridgeConfiguration'
        'Get-IDBridgeGoogleAuthFile'

        # Logging & lifecycle
        'Initialize-Logging'
        'Write-Log'
        'Start-ScriptEnd'

        # Helpers
        'Get-StudentGrade'
        'Add-IDBridgePersonProperties'
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()
}