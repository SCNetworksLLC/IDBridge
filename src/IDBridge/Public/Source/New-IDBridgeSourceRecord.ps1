<#
.SYNOPSIS
Build a canonical IDBridge source record from a normalized set of fields.

.DESCRIPTION
Source plugins call this factory instead of hand-building a PSCustomObject, so every source
record has the same properties, in the same order, with enforced types and defaults. The core
identity/org fields are Mandatory and typed; the AD and Google blocks default so a plugin only
supplies what applies to it. Cross-field rules (e.g. "AD enabled requires an OU and a key or
passphrase") are enforced separately by Test-IDBridgeSourceData.

Designed to be splatted from a plugin's existing field hashtable:
    $record = New-IDBridgeSourceRecord @recordFields

.PARAMETER PersonID
Unique person identifier (the universal join key). Required.

.PARAMETER PersonTypeID
Person tier: '1' = student, '2'/'3' = staff. Drives the staff CSV export filter.

.PARAMETER IDBActive
Whether the person is currently active (drives create/update vs deactivate). Must be a boolean.

.PARAMETER GroupsProposed
Desired group names (strings). A null value is normalized to an empty array.

.PARAMETER Description
Optional AD Description. Applied only when non-empty (set-but-don't-clear).

.PARAMETER TelephoneNumber
Optional AD telephoneNumber (Set/New-ADUser -OfficePhone). Applied only when non-empty.

.PARAMETER EmailAddress
Optional AD mail attribute (Set/New-ADUser -EmailAddress). Applied only when non-empty.

.PARAMETER PasswordNeverExpires
AD passwordNeverExpires flag (boolean). Defaults to $false.

.PARAMETER ExtensionAttribute2
Optional AD extensionAttribute2 (extensionAttribute1 is set from PersonTypeID by the AD
code). Applied only when non-empty. Reserved for future use.

.PARAMETER ExtensionAttribute3
Optional AD extensionAttribute3. Applied only when non-empty. Reserved for future use.

.PARAMETER ExtensionAttribute4
Optional AD extensionAttribute4. Applied only when non-empty. Reserved for future use.

.PARAMETER ForceDisable
Override-driven flag (boolean) to force-disable/suspend an active user. Defaults to $false.

.PARAMETER GoogleOUOverride
Override-driven flag (boolean) to skip the Google OU move. Defaults to $false.

.PARAMETER ProvisionAD
Whether this person should have an Active Directory account (per-user targeting). With
IDBActive, drives create/update vs. deactivate for AD. Distinct from the global config switch.

.PARAMETER ProvisionGoogle
Whether this person should have a Google Workspace account (per-user targeting). With
IDBActive, drives create/update vs. deactivate for Google. Distinct from the global config switch.

.PARAMETER ADKey
AD account password as a SecureString, or $null when using ADPassphraseAPI.

.PARAMETER GoogleKey
Google account password as a SecureString, or $null when using GooglePassphraseAPI.

.EXAMPLE
$record = New-IDBridgeSourceRecord @recordFields

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-25
#>
function New-IDBridgeSourceRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # --- Core identity / org (always required) ---
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PersonID,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NameFirst,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$NameLast,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Username,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UPN,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Building,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$JobTitle,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Company,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$PersonType,
        [Parameter(Mandatory)][ValidateSet('1', '2', '3')][string]$PersonTypeID,
        [Parameter(Mandatory)][bool]$IDBActive,

        # --- Optional core (defaulted) ---
        [AllowNull()][string]$Department = $null,
        [AllowNull()][string]$InternalID = $null,
        [AllowNull()][string]$Description = $null,
        [AllowNull()][string]$TelephoneNumber = $null,
        [AllowNull()][string]$EmailAddress = $null,
        [AllowNull()][string[]]$GroupsProposed = @(),

        # --- Control flags ---
        [bool]$ForceDisable = $false,
        [bool]$GoogleOUOverride = $false,

        # --- Active Directory ---
        [Parameter(Mandatory)][bool]$ProvisionAD,
        [string]$ADOrganizationalUnit = '',
        [string]$ADOrganizationalUnitTrash = '',
        [bool]$ADChangePasswordAtLogon = $false,
        [bool]$PasswordNeverExpires = $false,
        [AllowNull()][string]$ExtensionAttribute2 = $null,
        [AllowNull()][string]$ExtensionAttribute3 = $null,
        [AllowNull()][string]$ExtensionAttribute4 = $null,
        [AllowNull()][hashtable]$ADPassphraseAPI = $null,
        [AllowNull()][securestring]$ADKey = $null,

        # --- Google Workspace ---
        [Parameter(Mandatory)][bool]$ProvisionGoogle,
        [string]$GoogleOrganizationalUnit = '',
        [string]$GoogleOrganizationalUnitTrash = '',
        [bool]$GoogleChangePasswordAtLogon = $false,
        [AllowNull()][hashtable]$GooglePassphraseAPI = $null,
        [AllowNull()][securestring]$GoogleKey = $null
    )

    # Normalize a null group list to an empty array so the shape is uniform.
    if ($null -eq $GroupsProposed) { $GroupsProposed = @() }

    # Typed [string] params coerce $null -> ''. Normalize empty optional strings back to $null
    # so blank fields read as absent (and don't churn unconditionally-synced attributes).
    $nz = { param([string]$v) if ([string]::IsNullOrWhiteSpace($v)) { $null } else { $v } }

    [PSCustomObject][ordered]@{
        PersonID                      = $PersonID
        NameFirst                     = $NameFirst
        NameLast                      = $NameLast
        Username                      = $Username
        Building                      = $Building
        JobTitle                      = $JobTitle
        Company                       = $Company
        Department                    = (& $nz $Department)
        Description                   = (& $nz $Description)
        TelephoneNumber               = (& $nz $TelephoneNumber)
        EmailAddress                  = (& $nz $EmailAddress)
        UPN                           = $UPN
        PersonTypeID                  = $PersonTypeID
        InternalID                    = (& $nz $InternalID)
        IDBActive                     = $IDBActive
        GroupsProposed                = [string[]]@($GroupsProposed)
        PersonType                    = $PersonType
        ForceDisable                  = $ForceDisable
        GoogleOUOverride              = $GoogleOUOverride
        ProvisionAD                   = $ProvisionAD
        ADOrganizationalUnit          = $ADOrganizationalUnit
        ADOrganizationalUnitTrash     = $ADOrganizationalUnitTrash
        ADChangePasswordAtLogon       = $ADChangePasswordAtLogon
        PasswordNeverExpires          = $PasswordNeverExpires
        ExtensionAttribute2           = (& $nz $ExtensionAttribute2)
        ExtensionAttribute3           = (& $nz $ExtensionAttribute3)
        ExtensionAttribute4           = (& $nz $ExtensionAttribute4)
        ADPassphraseAPI               = $ADPassphraseAPI
        ADKey                         = $ADKey
        ProvisionGoogle               = $ProvisionGoogle
        GoogleOrganizationalUnit      = $GoogleOrganizationalUnit
        GoogleOrganizationalUnitTrash = $GoogleOrganizationalUnitTrash
        GoogleChangePasswordAtLogon   = $GoogleChangePasswordAtLogon
        GooglePassphraseAPI           = $GooglePassphraseAPI
        GoogleKey                     = $GoogleKey
    }
}
