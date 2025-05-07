<#
.SYNOPSIS
    Retrieves Active Directory organizational units, groups, and users.

.DESCRIPTION
    Connects to Active Directory using the provided configuration.
    Returns a single object containing:
      - All organizational units (Distinguished Names)
      - All group names
      - All users with specified properties

.PARAMETER IDConfig
    The configuration object containing Active Directory and script settings.

.PARAMETER logFile
    The path to the log file for error and process logging.

.OUTPUTS
    PSCustomObject
    An object with properties: ADOrgUnits, ADGroups, ADUsers.

.EXAMPLE
    $adData = Get-TargetDataAD -IDConfig $IDConfig -logFile $logFile
    $adData.ADOrgUnits
    $adData.ADGroups
    $adData.ADUsers

.NOTES
    Author: Sam Cattanach
    Requires: ActiveDirectory module, supporting functions (Write-Log)
#>

function Get-TargetDataAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$IDConfig,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    #User Properties to load
    $userPropertyAD = @(
        "UserPrincipalName"
        "Title"
        "Surname"
        "SamAccountName"
        "physicalDeliveryOfficeName"
        "Name"
        "GivenName"
        "employeeType"
        "EmployeeID"
        "DisplayName"
        "DistinguishedName"
        "Company"
        "CN"
        "CanonicalName"
        "MemberOf"
        "objectGUID"
        "extensionAttribute1"
        "extensionAttribute2"
        "extensionAttribute3"
        "extensionAttribute4"
        "extensionAttribute5"
    )

    #Get all OUs from AD
    try {
        $ADOrgUnits = Get-ADOrganizationalUnit -LDAPFilter '(name=*)' -SearchBase $IDConfig.AD.userRootOU | Select-Object -ExpandProperty DistinguishedName

        if ($ADOrgUnits) {
            Write-Log -Path $logFile -Message "AD: Successfully fetched Org Units"
        } else {
            Throw "AD: Connected to AD but no org units fetched"
        }
    }
    catch {
        Write-Log -Path $logFile -Message "AD: No org units fetched" -Level Error
        Throw $_
    }

    #Get all Groups from AD
    try {
        $ADGroups = Get-ADGroup -Filter * | Select-Object -ExpandProperty Name

        if ($ADGroups) {
            Write-Log -Path $logFile -Message "AD: Successfully fetched Groups"
        } else {
            Throw "AD: Connected to AD but no groups fetched"
        }
    }
    catch {
        Write-Log -Path $logFile -Message "AD: No groups fetched" -Level Error
        Throw $_
    }

    #Get all Users from AD
    try {
        $ADUsers = Get-ADUser -Filter * -Properties $userPropertyAD

        if ($ADUsers) {
            Write-Log -Path $logFile -Message "AD: Successfully fetched Users"
        } else {
            Throw "AD: Connected to AD but no users fetched"
        }
    }
    catch {
        Write-Log -Path $logFile -Message "AD: No users fetched" -Level Error
        Throw $_
    }

    #Return a single object with all data
    return [PSCustomObject]@{
        ADOrgUnits = $ADOrgUnits
        ADGroups = $ADGroups
        ADUsers = $ADUsers
    }
}