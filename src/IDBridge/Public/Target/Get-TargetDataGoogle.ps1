<#
.SYNOPSIS
    Retrieves Google Workspace users, groups, group memberships, and organizational units.

.DESCRIPTION
    Connects to Google Workspace using the provided authentication headers and configuration.
    Returns a single object containing:
      - All users (with a CurrentGroups property listing their group memberships, and a
        CurrentLicenses property listing their license assignments unless
        Google.enableLicenseRemoval = $false)
      - All groups (excluding Google.groupsExcluded patterns; default classroom_teachers@*)
      - All organizational units

    For each group, retrieves its members and builds a hashtable mapping user emails to their group memberships.
    Each user object in the returned collection has a CurrentGroups property containing the list of groups they belong to.
    License assignments are enumerated per product (Google.licenseProductIds, default
    Workspace/Education + Teaching and Learning) via the Enterprise License Manager API so
    the deactivate step can decide and log removals without extra lookups at write time.

.OUTPUTS
    PSCustomObject
    An object with properties:
        - Users: Array of user objects, each with a CurrentGroups property.
        - Groups: Array of group objects (excluding Google.groupsExcluded patterns).
        - OrgUnits: Array of organizational unit objects.

.EXAMPLE
    $googleData = Get-TargetDataGoogle
    $googleData.Users
    $googleData.Groups
    $googleData.OrgUnits

.NOTES
    Author: Sam Cattanach
    Requires: Google API access, supporting functions (Get-GoogleData, Write-Log)
#>

function Get-TargetDataGoogle {
    [CmdletBinding()]
    param ()

    Write-Log -Message "Google: Starting Google Target Data Retrieval" -Level Info

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    #region Import Google Headers
    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }
    #endregion Import Google Headers

    #region Get Google Users
    try {
        Write-Log -Message "Google: Fetching Users" -Level Trace
        # customer must be the real ID from config — my_customer only resolves for a domain
        # user's token, and the service account authenticates as itself.
        $googleUsers = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/users?customer=$($IDConfig.Google.customerID)&maxResults=500"  -ErrorAction Stop

        Write-Log -Message "Google: Successfully fetched users" -Level Trace
    }
    catch {
        Throw $_
    }
    #endregion Get Google Users




    #region Google Groups and Memberships
    #Get Google Groups - Stores data in $googleGroups
    try {
        Write-Log -Message "Google: Fetching Groups" -Level Trace
        $googleGroups = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/groups?customer=$($IDConfig.Google.customerID)&maxResults=500" -ErrorAction Stop

        #Remove excluded groups (Google.groupsExcluded - wildcard patterns matched against the group email).
        #Excluded groups become invisible to ALL group processing: no adds, no removes, no deactivate strips.
        #When the config key is absent, the Google Classroom auto-groups stay excluded (previous hardcoded behavior).
        $groupsExcluded = if ($null -ne $IDConfig.Google.groupsExcluded) { $IDConfig.Google.groupsExcluded } else { @('classroom_teachers@*') }
        foreach ($pattern in $groupsExcluded) {
            $excludedGroups = @($googleGroups | Where-Object {$_.email -like $pattern})
            if ($excludedGroups.Count -gt 0) {
                Write-Log -Message "Google: Excluding $($excludedGroups.Count) group(s) matching '$pattern' from group processing: $($excludedGroups.email -join ', ')" -Level Trace
                $googleGroups = $googleGroups | Where-Object {$_.email -notlike $pattern}
            }
        }

        Write-Log -Message "Google: Successfully fetched groups" -Level Trace
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
        Write-Log -Message ("Google: Getting users for Group: " + $item.email) -Level Trace

        try {
            #Get group Memebers
            $groupMemberResults = $null
            $groupMemberResults = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://admin.googleapis.com/admin/directory/v1/groups/" + $item.email + "/members?customer=my_customer&maxResults=500") -ErrorAction Stop
            
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
            Throw (Write-Log -Message ("Google: No users retrieved for Group: " + $item.email) -Level Error)
        }
    }

    Write-Log -Message "Google: Successfully retrieved group memberships"
    #>




    Write-Log -Message "Google: Fetching Group Members" -Level Trace
    #Get Google Group Memberships - Stores memberships in $userGoogleGroupsCurrent
    $sharedLogs = [hashtable]::Synchronized(@{})

    foreach ($item in $googleGroups) {
        $item | Add-Member -MemberType NoteProperty -Name Headers -Value $headers -Force
        $item | Add-Member -MemberType NoteProperty -Name GetGoogleData -Value (Get-Command Get-GoogleData).Definition -Force
        $item | Add-Member -MemberType NoteProperty -Name TraceLogging -Value $IDConfig.Debug.TraceLogging -Force
    }

    #Loop through each group and retrieve its members
    $finalResults = $googleGroups | Where-Object {$_.directMembersCount -ne 0} | ForEach-Object -Parallel  {
        $null = New-Item -Path function: -Name 'Get-GoogleData' -Value ($_.GetGoogleData) -force

        $headers = $_.headers
        $email = $_.email

        if ($_.TraceLogging) {
            ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                Message    = ("Google: Getting users for Group: " + $email)
                Level      = "trace"
            }
        }

        try {
            #Get group Memebers
            $groupMemberResults = $null
            $groupMemberResults = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://admin.googleapis.com/admin/directory/v1/groups/" + $email + "/members?maxResults=500") -ErrorAction Stop

            [PSCustomObject]@{
                GroupEmail = $email
                Members    = $groupMemberResults
            }

            if ($_.TraceLogging) {
                ($using:sharedLogs).(Get-Date -Format "yyyy-MM-dd_HH:mm:ss:ffff") = [PSCustomObject]@{
                    Message    = ("Google: Received $($groupMemberResults.count) users for Group: " + $email)
                    Level      = "trace"
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
        Write-Log -Message $entry.Message -Level $entry.Level
    }

    #Check for errors during parallel processing (by entry Level, not message text)
    if ($sharedLogs.Values.Level -contains 'error') {
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
    Write-Log -Message "Google: Successfully fetched group members" -Level Trace








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




    #region Google License Assignments
    #License removal is on by default; attach each user's assignments so the deactivate
    #step can decide (and log) removals without extra lookups at write time
    $userLicensesCurrent = @{}
    if ($IDConfig.Google.enableLicenseRemoval -ne $false) {
        Write-Log -Message "Google: Fetching License Assignments" -Level Trace

        # Product IDs are a small public catalog (SKUs are discovered, not configured):
        # 101031 = Education Standard/Plus, 101037 = Teaching and Learning Upgrade. Paid
        # products only — the base license (product Google-Apps) self-releases when the
        # deactivate step archives the user, and removing it by API just fights OU
        # auto-licensing. Override with Google.licenseProductIds.
        $productIds = if ($IDConfig.Google.licenseProductIds) { $IDConfig.Google.licenseProductIds } else { @('101031', '101037') }

        foreach ($productId in $productIds) {
            try {
                $assignments = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://licensing.googleapis.com/apps/licensing/v1/product/" + [uri]::EscapeDataString($productId) + "/users?customerId=" + $IDConfig.Google.customerID + "&maxResults=1000") -ErrorAction Stop
            }
            catch {
                Write-Log -Message "Google: Error listing license assignments for product $productId. Ensure the service account's 'IDBridge' admin role includes the License Management privilege and the Enterprise License Manager API is enabled in its project, or set Google.enableLicenseRemoval = `$false." -Level Error
                Throw $_
            }

            foreach ($assignment in $assignments) {
                #Add user to hashtable, create entry if it doesn't exist
                if (-not $userLicensesCurrent.ContainsKey($assignment.userId.ToLower())) {
                    $userLicensesCurrent[$assignment.userId.ToLower()] = @()
                }

                #Add the assignment to the user's list
                $userLicensesCurrent[$assignment.userId.ToLower()] += $assignment
            }
        }
        Write-Log -Message ("Google: Fetched license assignments for $($userLicensesCurrent.Count) users") -Level Trace
    }

    #Add Licenses to User Object
    foreach ($user in $googleUsers) {
        #Check if the user is in the hashtable and add licenses if they exist
        if ($userLicensesCurrent.ContainsKey($user.primaryEmail.ToLower())) {
            $user | Add-Member -MemberType NoteProperty -Name CurrentLicenses -Value $userLicensesCurrent[$user.primaryEmail.ToLower()]
        } else {
            $user | Add-Member -MemberType NoteProperty -Name CurrentLicenses -Value @()
        }
    }
    #endregion Google License Assignments




    #region Get Google Org Units
    try {
        Write-Log -Message "Google: Fetching Org Units" -Level Trace
        $googleOrgUnits = Get-GoogleData -GoogleHeaders $headers -APIUri "https://admin.googleapis.com/admin/directory/v1/customer/$($IDConfig.Google.customerID)/orgunits?type=all&maxResults=500" -ErrorAction Stop

        Write-Log -Message ("Google: Fetched $($googleOrgUnits.count) organizational units") -Level Trace
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
        Write-Log -Message ("Google: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress))
    }
    #endregion Get Duplicate IDs




    #region Lookup Table Creation
    # Build the lookup tables once to make the search faster
    $googleUsersLookupByID = @{}
    foreach ($gUser in $googleUsers) {
        foreach ($extId in $gUser.externalIDs) {
            if ($extId.value -notin $duplicateUsers.OrgID) {
                $googleUsersLookupByID[$extId.value] = $gUser
            }
        }
    }
    #endregion Lookup Table Creation

    Write-Log -Message "Google: Finished Google Target Data Retrieval" -Level Info




    #Return a single object with all data
    return [PSCustomObject]@{
        Users             = $googleUsers
        Groups            = $googleGroups
        OrgUnits          = $googleOrgUnits
        DuplicateUsers    = $duplicateUsers
        LookupByID        = $googleUsersLookupByID
    }
}