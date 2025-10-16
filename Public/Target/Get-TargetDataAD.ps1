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
    (Required) The configuration object containing Active Directory and script settings.

.PARAMETER logFile
    (Required) The path to the log file for error and process logging.

.OUTPUTS
    PSCustomObject
    An object with properties: OrgUnits, Groups, Users.

.EXAMPLE
    $adData = Get-TargetDataAD -logFile $logFile
    $adData.Users
    $adData.Groups
    $adData.OrgUnits

.NOTES
    Author: Sam Cattanach
    Requires: ActiveDirectory module, supporting functions (Write-Log)
#>

function Get-TargetDataAD {
    [CmdletBinding()]
    param (
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

    #Get all Groups from AD
    try {
        $ADGroups = Get-ADGroup -Filter * -Properties DistinguishedName | Select-Object Name, DistinguishedName

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

    # Build a hashtable mapping DistinguishedName -> Group Name to avoid repeated Get-ADGroup calls
    $groupDnToName = @{}
    foreach ($item in $ADGroups) {
        if ($item.DistinguishedName) {
            $groupDnToName[$item.DistinguishedName] = $item.Name
        }
    }

    #Add the groups to the users
    foreach ($user in $ADUsers) {
        #Add groups if they exist
        if ($user.MemberOf) {
            foreach ($item in $user.MemberOf) {
                if ($groupDnToName.ContainsKey($item)) {
                    $user.CurrentGroups += $groupDnToName[$item]
                }
            }
        } else {
            $user.CurrentGroups = $null
        }
    }

    #Get all OUs from AD
    try {
        $ADOrgUnits = Get-ADOrganizationalUnit -LDAPFilter '(name=*)' | Select-Object -ExpandProperty DistinguishedName

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

    #Return a single object with all data
    return [PSCustomObject]@{
        Users = $ADUsers
        Groups = $ADGroups.Name
        OrgUnits = $ADOrgUnits
    }
}