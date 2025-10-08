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
        [PSObject]$headers
    )

    #region Get Google Users
    try {
        $googleUsers = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/users?customer=my_customer&maxResults=500" -ErrorAction Stop
    }
    catch {
        Throw $_
    }
    #endregion Get Google Users

    #region Google Groups and Memberships
    #Get Google Groups - Stores data in $googleGroups
    try {
        $googleGroups = Get-GoogleData -GoogleHeaders $headers -APIUri "https://www.googleapis.com/admin/directory/v1/groups?customer=my_customer&maxResults=500" -ErrorAction Stop

        #Remove Classroom Teachers Group
        $googleGroups = $googleGroups | Where-Object {$_.email -notlike "classroom_teachers@*"}
    }
    catch {
        Throw $_
    }

    #Get Google Group Memberships - Stores memberships in $userGoogleGroupsCurrent
    #Hashtable to store users and their groups
    $userGoogleGroupsCurrent = @{}

    #Loop through each group and retrieve its members
    foreach ($item in $googleGroups | Where-Object {$_.directMembersCount -ne 0}) {
        Write-Log -Path $logFile -Message ("Google: Getting users for Group: " + $item.email)
        try {
            #Get group Memebers
            $groupMemberResults = Get-GoogleData -GoogleHeaders $headers -APIUri ("https://admin.googleapis.com/admin/directory/v1/groups/" + $item.email + "/members?customer=my_customer&maxResults=500") -ErrorAction Stop
            
            foreach ($member in $groupMemberResults) {
                #Add user to hashtable, create entry if it doesn't exist
                if (-not $userGoogleGroupsCurrent.ContainsKey($member.email)) {
                    $userGoogleGroupsCurrent[$member.email] = @()
                }

                #Add the group to the user's list
                $userGoogleGroupsCurrent[$member.email] += $item.email
            }

            if ($groupMemberResults) {Remove-Variable groupMemberResults}
        }
        catch {
            Throw (Write-Log -Path $logFile -Message ("Google: No users retrieved for Group: " + $item.email) -Level Error)
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
        $googleOrgUnits = Get-GoogleData -GoogleHeaders $headers -APIUri "https://admin.googleapis.com/admin/directory/v1/customer/my_customer/orgunits?type=all&maxResults=500" -ErrorAction Stop
    }
    catch {
        Throw $_
    }
    #endregion Get Google Org Units

    #Return a single object with all data
    return [PSCustomObject]@{
        Users             = $googleUsers
        Groups            = $googleGroups
        OrgUnits          = $googleOrgUnits
    }
}