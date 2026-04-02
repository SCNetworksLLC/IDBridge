function Get-TargetDataAD {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$logFile,

        $VerboseLogging = $false
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
        "EmployeeNumber"
        "DisplayName"
        "DistinguishedName"
        "Company"
        "Department"
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
            if ($VerboseLogging) {
                Write-Log -Path $logFile -Message "AD: Successfully fetched Users"
            }
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
            if ($VerboseLogging) {
                Write-Log -Path $logFile -Message "AD: Successfully fetched Groups"
            }
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
            if ($VerboseLogging) {
                Write-Log -Path $logFile -Message "AD: Successfully fetched Org Units"
            }
        } else {
            Throw "AD: Connected to AD but no org units fetched"
        }
    }
    catch {
        Write-Log -Path $logFile -Message "AD: No org units fetched" -Level Error
        Throw $_
    }

    #Get AD users with duplicate employeeID
    $duplicateADUsers = ($ADUsers.where{$_.employeeID} | 
        Select-Object -Property UserPrincipalName, employeeID | 
        Group-Object -Property employeeID | 
        Where-Object { $_.Count -gt 1 }
    ).group

    if ($duplicateADUsers) {
        Write-Log -Path $logFile -Message ("AD: Users found with Duplicate External IDs: " + ($duplicateADUsers | ConvertTo-Json -Compress))
    }

    # Build the lookup tables once to make the search faster
    $adUsersLookupByID = @{}
    foreach ($adUser in $ADUsers) {
        if ($adUser.EmployeeID -and ($adUser.EmployeeID -notin $duplicateADUsers.employeeID)) {
            $adUsersLookupByID[$adUser.EmployeeID] = $adUser
        }
    }

    #Return a single object with all data
    return [PSCustomObject]@{
        Users = $ADUsers
        Groups = $ADGroups.Name
        OrgUnits = $ADOrgUnits
        DuplicateUsers = $duplicateADUsers
        LookupByID = $adUsersLookupByID
    }
}