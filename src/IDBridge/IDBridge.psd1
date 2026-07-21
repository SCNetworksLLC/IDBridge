@{
    RootModule        = 'IDBridge.psm1'
    ModuleVersion     = '26.7.21.2'
    GUID              = 'a0a0c664-888e-44e2-9c12-fc8647a520c0'
    Author            = 'Sam Cattanach'
    CompanyName       = 'SC Networks LLC'
    Copyright         = '(c) 2026 SC Networks LLC. All rights reserved.'
    Description       = 'IdentityBridge — automated account provisioning for Google Workspace and Active Directory from school SIS/GSheet data.'
    PowerShellVersion = '7.5'

    # Explicitly list public functions so the module surface is intentional: only what a
    # district admin or a plugin author calls directly. The sync pipeline internals
    # (change-list planners, target-data readers, directory writers) live in Private\ and
    # are NOT exported - they are free to change between releases.
    FunctionsToExport = @(
        # Run & setup
        'Invoke-IDBridge'
        'Initialize-IDBridge'
        'Install-IDBridge'  # First-run scaffold: creates the folder tree + a default all-features-off config. Never overwrites an existing config.
        'Get-IDBridgeConfig'  # This is the public accessor for the config object after initialization. It will throw an error if called before Initialize-IDBridge.
        'Export-IDBridgeDirectoryToSheet'  # Onboarding tool: seeds the staff source sheet from current AD + Google state (new tab, Process=FALSE).

        # Secrets
        'Get-IDBridgeSecret'  # Reads a named secret from the IDBridge vault (Cms/DpapiNG envelope files, or Azure Key Vault).
        'Set-IDBridgeSecret'  # Adds/changes a named secret in the IDBridge vault using the Secrets.Provider from config.
        'Get-IDBridgeSecretInfo'  # Lists vault secret names and metadata (never values).
        'Remove-IDBridgeSecret'   # Deletes a named secret from the vault.
        'New-IDBridgeSecretCertificate'  # Creates the Document Encryption certificate used by the Cms provider.
        'Grant-IDBridgeCertificatePrivateKeyAccess'  # Grants an account read on a machine-store certificate's private key (e.g. the gMSA, after the cert exists).

        # Google auth
        'Connect-IDBridgeGoogle'   # Vault key -> JWT (as the SA itself, no impersonation) -> bearer headers; standalone auth verification after bootstrap/role changes.
        'Get-GoogleHeaders'
        'Get-IDBridgeGoogleServiceAccountEmail'  # SA email (client_email) from connect-time state or the vault key; the address to share sheets with.
        'Get-IDBridgeGoogleProjectId'  # GCP project ID (project_id) from connect-time state or the vault key; locates the install's Cloud project.
        'Initialize-IDBridgeGoogleServiceAccount'  # One-command bootstrap: project, APIs, service account, key into vault, admin role created + assigned.

        # Plugin toolkit: source data
        'Get-SourceDataGSheet'
        'Get-SourceDataSkywardSMS'
        'Get-SourceDataInfiniteCampus'
        'New-IDBridgeSourceRecord'
        'Test-IDBridgeSourceData'

        # Plugin toolkit: Google Sheets helpers
        'Get-GoogleSheetData'
        'Get-SheetIdByName'
        'Get-ColumnLetter'
        'Convert-CellToIndex'
        'Set-GSheetData'
        'Set-CheckboxesToFalse'

        # Plugin toolkit: helpers
        'Get-StudentGrade'
        'New-Passphrase'
        'Format-IDBridgeName'

        # Logging
        'Write-Log'
        'Get-IDBridgeLogs' # This is the public accessor for the logs after initialization. It will throw an error if called before Initialize-IDBridge.

        # Diagnostics
        'Get-GoogleUsersOrphaned'  # Standalone check: target users under the managed OU absent from source data.
        'Get-IDBridgeSiteID'       # Returns (creating on first use) the install's random telemetry SiteID; used to claim the install in the Pulse dashboard.
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