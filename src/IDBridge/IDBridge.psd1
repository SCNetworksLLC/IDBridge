@{
    RootModule        = 'IDBridge.psm1'
    ModuleVersion     = '26.7.5.0'
    GUID              = 'a0a0c664-888e-44e2-9c12-fc8647a520c0'
    Author            = 'Sam Cattanach'
    CompanyName       = 'SC Networks LLC'
    Copyright         = '(c) 2026 SC Networks LLC. All rights reserved.'
    Description       = 'IdentityBridge — automated account provisioning for Google Workspace and Active Directory from school SIS/GSheet data.'
    PowerShellVersion = '7.5'

    # Explicitly list public functions so the module surface is intentional.
    # Internal helpers (private functions called only within other functions) are NOT listed here.
    FunctionsToExport = @(
        # Source data
        'Get-SourceDataGSheet'
        'Get-SourceDataSkywardSMS'
        'Get-SourceDataInfiniteCampus'
        'New-IDBridgeSourceRecord'
        'Test-IDBridgeSourceData'
        'Test-IDBridgeChangeThreshold'
        'Remove-IDBridgeDuplicateID'
        'Show-GroupsNotProcessed'

        # Target data
        'Get-TargetDataGoogle'
        'Add-TargetDataGoogle'
        'Get-TargetDataAD'
        'Add-TargetDataAD'

        # AD processing
        'Get-ADOrgUnitsForProcessing'
        'Get-ADUsersToSetEmployeeID'
        'Get-ADUsersToDeactivate'
        'Get-ADUsersToUpdate'
        'Get-ADUsersToCreate'
        'Get-ADUserGroupsToUpdate'
        'New-IDBridgeADOrgUnit'
        'Disable-IDBridgeADUser'

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
        'Remove-IDBridgeGoogleUserLicense'  # Deletes configured license SKUs from a user on the deactivate (trash) step.
        'Invoke-GoogleBatchRequest'  # Sends multiple Directory API calls in one multipart/mixed batch HTTP request.

        # Google Sheets helpers
        'Get-GoogleSheetData'
        'Get-SheetIdByName'
        'Get-ColumnLetter'
        'Convert-CellToIndex'
        'Set-GSheetData'
        'Set-CheckboxesToFalse'
        'Push-LogsToSheet'

        # Auth & Config
        'Invoke-IDBridge'
        'Initialize-IDBridge'
        'Get-IDBridgeConfig'  # This is the public accessor for the config object after initialization. It will throw an error if called before Initialize-IDBridge.
        'Get-IDBridgeSecret'  # Reads a named secret from the IDBridge vault (Cms/DpapiNG envelope files, or Azure Key Vault).
        'Set-IDBridgeSecret'  # Adds/changes a named secret in the IDBridge vault using the Secrets.Provider from config.
        'Get-IDBridgeSecretInfo'  # Lists vault secret names and metadata (never values).
        'Remove-IDBridgeSecret'   # Deletes a named secret from the vault.
        'New-IDBridgeSecretCertificate'  # Creates the Document Encryption certificate used by the Cms provider.

        #Auth
        'Connect-IDBridgeGoogle'   # Vault key -> DWD JWT -> bearer headers; standalone auth verification after bootstrap/DWD changes.
        'Get-GoogleApiAccessToken'
        'Get-GoogleHeaders'
        'Initialize-IDBridgeGoogleServiceAccount'  # One-command bootstrap: project, APIs, service account, key into vault, DWD checklist.

        # Logging & lifecycle
        'Write-Log'
        'Get-IDBridgeLogs' # This is the public accessor for the logs after initialization. It will throw an error if called before Initialize-IDBridge.

        # Helpers
        'Get-StudentGrade'
        'Get-RandomPassword'
        'New-Passphrase'
        'Format-IDBridgeName'

        # Plugins
        'Invoke-SourcePlugins'
        'Merge-IDBridgeOverrideData'
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('ActiveDirectory', 'GoogleWorkspace', 'Identity', 'Provisioning', 'SIS', 'Skyward', 'InfiniteCampus')
            ProjectUri   = 'https://github.com/SCNetworksLLC/IDBridge'
            LicenseUri   = 'https://github.com/SCNetworksLLC/IDBridge/blob/main/LICENSE'
            ReleaseNotes = 'See CHANGELOG.md'
        }
    }
}