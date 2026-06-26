function Get-ADUsersToSetEmployeeID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers
    )

    #Set Users that need EmployeeID set in AD
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name

    $itemUpdateList = @{}

    foreach ($item in $UserList | Where-Object {-not $_.ADCurrentUserID}) {
        if ($item.personID -notin $CurrentADUsers.employeeID){
            Write-Log -Message ("AD: No user found with EmployeeID: " + $item.personID)
            
            if ($item.username -in $CurrentADUsers.SamAccountName) {
                $ADUser = $null

                $ADUser = ($CurrentADUsers | Where-Object {$_.SamAccountName -eq $item.username})

                if ($ADUser.Surname -eq $item.NameLast -and $ADUser.GivenName -eq $item.NameFirst) {
                    $itemUpdateList[$item.personID] = [PSCustomObject]@{
                        ID = $ADUser.ObjectGUID
                        Groups = ($ADUser.MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name)
                        EnabledStatus = $ADUser.Enabled
                        User = $ADUser
                    }
                } else {
                    Write-Log -Message ("AD: Username " + $item.username + " for " + $item.personID + " is already taken with a different name of " + $ADUser.GivenName + " " + $ADUser.Surname) -Level Error
                }
            } 
        }
    }

    return $itemUpdateList
}