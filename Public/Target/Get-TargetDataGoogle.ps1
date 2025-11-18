<#
.SYNOPSIS
    Retrieves Google Workspace users, groups, group memberships, and organizational units.

.DESCRIPTION
    Connects to Google Workspace using the provided authentication headers and configuration.
    Returns a single object containing:
      - All users (with a CurrentGroups property listing their group memberships)
      - All groups (excluding "classroom_teachers")
      - All organizational units

    For each group, retrieves its members and builds a hashtable mapping user emails to their group memberships.
    Each user object in the returned collection has a CurrentGroups property containing the list of groups they belong to.

.PARAMETER logFile
    (Required) The path to the log file for error and process logging.

.PARAMETER headers
    (Required) The authentication headers for Google API requests.

.OUTPUTS
    PSCustomObject
    An object with properties:
        - Users: Array of user objects, each with a CurrentGroups property.
        - Groups: Array of group objects (excluding "classroom_teachers").
        - OrgUnits: Array of organizational unit objects.

.EXAMPLE
    $googleData = Get-TargetDataGoogle -logFile $logFile -headers $headers
    $googleData.Users
    $googleData.Groups
    $googleData.OrgUnits

.NOTES
    Author: Sam Cattanach
    Requires: Google API access, supporting functions (Get-GoogleData, Write-Log)
#>

function Get-TargetDataGoogle {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$logFile,

        [Parameter(Mandatory = $true)]
        [PSObject]$headers,

        $VerboseLogging = $false
    )

    #region Get Google Users
    try {
        $googleUsers = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/users?customer=my_customer&maxResults=500" -VerboseLogging $VerboseLogging -ErrorAction Stop
        if ($VerboseLogging) {
            Write-Log -Path $logFile -Message "Google: Successfully retrieved users"
        }
    }
    catch {
        Throw $_
    }
    #endregion Get Google Users

    #region Google Groups and Memberships
    #Get Google Groups - Stores data in $googleGroups
    try {
        $googleGroups = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/groups?customer=my_customer&maxResults=500" -VerboseLogging $VerboseLogging -ErrorAction Stop

        #Remove Classroom Teachers Group
        $googleGroups = $googleGroups | Where-Object {$_.email -notlike "classroom_teachers@*"}
        if ($VerboseLogging) {
            Write-Log -Path $logFile -Message "Google: Successfully retrieved groups"
        }
    }
    catch {
        Throw $_
    }





    <# This section has been modified to use ForEach-Object -Parallel for better performance
    #Get Google Group Memberships - Stores memberships in $userGoogleGroupsCurrent
    #Hashtable to store users and their groups
    $userGoogleGroupsCurrent = @{}

    #Loop through each group and retrieve its members
    foreach ($item in $googleGroups | Where-Object {$_.directMembersCount -ne 0}) {
        if ($VerboseLogging) {
            Write-Log -Path $logFile -Message ("Google: Getting users for Group: " + $item.email)
        }
        try {
            #Get group Memebers
            $groupMemberResults = $null
            $groupMemberResults = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://admin.googleapis.com/admin/directory/v1/groups/" + $item.email + "/members?customer=my_customer&maxResults=500") -VerboseLogging $VerboseLogging -ErrorAction Stop
            
            foreach ($member in $groupMemberResults) {
                #Add user to hashtable, create entry if it doesn't exist
                if (-not $userGoogleGroupsCurrent.ContainsKey($member.email)) {
                    $userGoogleGroupsCurrent[$member.email] = @()
                }

                #Add the group to the user's list
                $userGoogleGroupsCurrent[$member.email] += $item.email
            }            
        }
        catch {
            Throw (Write-Log -Path $logFile -Message ("Google: No users retrieved for Group: " + $item.email) -Level Error)
        }
    }

    Write-Log -Path $logFile -Message "Google: Successfully retrieved group memberships"
    #>





    #Get Google Group Memberships - Stores memberships in $userGoogleGroupsCurrent
    $sharedLogs = [hashtable]::Synchronized(@{})

    foreach ($item in $googleGroups) {
        $item | Add-Member -MemberType NoteProperty -Name Headers -Value $headers -Force
        $item | Add-Member -MemberType NoteProperty -Name GetGoogleData -Value (Get-Command Get-GoogleData).Definition -Force
        $item | Add-Member -MemberType NoteProperty -Name VerboseLogging -Value $IDConfig.Debug.verboseLogging -Force
    }

    #Loop through each group and retrieve its members
    $finalResults = $googleGroups | Where-Object {$_.directMembersCount -ne 0} | ForEach-Object -Parallel  {
        $null = New-Item -Path function: -Name 'Get-GoogleData' -Value ($_.GetGoogleData) -force

        $headers = $_.headers
        $email = $_.email

        if ($_.VerboseLogging) {
            ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                Message    = ("Google: Getting users for Group: " + $email)
                Level      = "info"
            }
        }

        try {
            #Get group Memebers
            $groupMemberResults = $null
            $groupMemberResults = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://admin.googleapis.com/admin/directory/v1/groups/" + $email + "/members?customer=my_customer&maxResults=500") -ErrorAction Stop

            [PSCustomObject]@{
                GroupEmail = $email
                Members    = $groupMemberResults
            }

            if ($_.VerboseLogging) {
                ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                    Message    = ("Google: Received $($groupMemberResults.count) users for Group: " + $email)
                    Level      = "info"
                }
            }
        }
        catch {
            ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                Message    = ("Google: No users retrieved for Group: " + $email)
                Level      = "error"
            }

            ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                Message    = $_
                Level      = "error"
            }
        }
    } -ThrottleLimit 10

    #Write Logs from Parallel Processing
    foreach ($logEntry in $sharedLogs.GetEnumerator() | Sort-Object Name) {
        $entry = $logEntry.Value
        Write-Log -Path $logFile -Message $entry.Message -Level $entry.Level
    }

    #Check for errors during parallel processing
    if ($sharedLogs.GetEnumerator() -like "*error*") {
        Throw "Errors occurred while retrieving group memberships. Check the log for details."
    }

    #Process final results into hashtable
    $userGoogleGroupsCurrent = @{}
    foreach ($item in $finalResults) {
        foreach ($member in $item.Members) {
            #Add user to hashtable, create entry if it doesn't exist
            if (-not $userGoogleGroupsCurrent.ContainsKey($member.email)) {
                $userGoogleGroupsCurrent[$member.email] = @()
            }

            #Add the group to the user's list
            $userGoogleGroupsCurrent[$member.email] += $item.GroupEmail
        }
    }









    #Add Groups to User Object
    foreach ($user in $googleUsers) {
        #Check if the user is in the hashtable and add groups if they exist
        if ($userGoogleGroupsCurrent.ContainsKey($user.primaryEmail)) {
            $user | Add-Member -MemberType NoteProperty -Name CurrentGroups -Value $userGoogleGroupsCurrent[$user.primaryEmail]
        } else {
            $user | Add-Member -MemberType NoteProperty -Name CurrentGroups -Value @()
        }
    }
    #endregion Google Groups and Memberships

    #region Get Google Org Units
    try {
        $googleOrgUnits = Get-GoogleData -GoogleHeaders $headers -APIUri "https://admin.googleapis.com/admin/directory/v1/customer/my_customer/orgunits?type=all&maxResults=500" -VerboseLogging $VerboseLogging -ErrorAction Stop
        if ($VerboseLogging) {
            Write-Log -Path $logFile -Message ("Google: Retrieved $($googleOrgUnits.count) organizational units")
        }
    }
    catch {
        Throw $_
    }
    #endregion Get Google Org Units


    #region Get Duplicate IDs
    #Get Google users with duplicate organization external ID
    $duplicateUsers = ($googleUsers | ForEach-Object {
        $pkID = ($_.externalIds | Where-Object { $_.Type -eq "organization" }).value
        if ($pkID) {
            [PSCustomObject]@{
                UPN = $_.primaryEmail
                FullName = $_.name.fullName
                OrgID = $pkID
            }
        }
    } | Group-Object -Property OrgID | Where-Object { $_.Count -gt 1 }).group

    if ($duplicateUsers) {
        Write-Log -Path $logFile -Message ("Google: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress)) -Level Error
    }
    #endregion Get Duplicate IDs


    #region Lookup Table Creation
    # Build the lookup tables once to make the search faster
    $googleUsersLookupByID = @{}
    foreach ($gUser in $googleUsers) {
        foreach ($extId in $gUser.externalIDs) {
            $googleUsersLookupByID[$extId.value] = $gUser
        }
    }
    #endregion Lookup Table Creation


    #Return a single object with all data
    return [PSCustomObject]@{
        Users             = $googleUsers
        Groups            = $googleGroups
        OrgUnits          = $googleOrgUnits
        DuplicateIDs      = $duplicateUsers
        LookupByID        = $googleUsersLookupByID
    }
}