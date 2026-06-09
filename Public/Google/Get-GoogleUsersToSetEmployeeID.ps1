function Get-GoogleUsersToSetEmployeeID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $GoogleUsers
    )

    #Set Users that need EmployeeID set in Google
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name

    $itemUpdateList = @{}

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and -not $_.GoogleCurrentUserID}) {
        $googleUser = $null
        Write-Log -Message ("Google: No user found with EmployeeID: " + $item.personID)

        if ($item.UPN -in $GoogleUsers.primaryEmail) {
            $googleUser = ($GoogleUsers | Where-Object {$_.primaryEmail -eq $item.UPN})

            if ($googleUser.Name.familyName -eq $item.NameLast -and $googleUser.Name.givenName -eq $item.NameFirst) {
                $itemUpdateList[$item.personID] = [PSCustomObject]@{
                    ID = $googleUser.ID
                    Groups = $googleUser.CurrentGroups
                    SuspendedStatus = $googleUser.Suspended
                    User = $googleUser
                }
            } else {
                Write-Log -Message ("Google: Username: " + $item.UPN + " for " + $item.personID + " is already taken with a different name of " + $googleUser.Name.givenName + " " + $googleUser.Name.familyName) -Level Error
            }
        }
    }

    return $itemUpdateList
}