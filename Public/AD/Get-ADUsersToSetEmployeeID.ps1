function Get-ADUsersToSetEmployeeID {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    #Set Users that need EmployeeID set in AD
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name
    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and -not $_.ADCurrentUserID -and -not $_.ADDuplicateIDStatus}) {
        if ($item.personID -notin $CurrentADUsers.employeeID){
            Write-Log -Path $logFile -Message ("AD: No user found with EmployeeID: " + $item.personID)
            
            if ($item.username -in $CurrentADUsers.SamAccountName) {
                $ADUser = $null
                $ADUser = ($CurrentADUsers | Where-Object {$_.SamAccountName -eq $item.username})

                if ($ADUser.Surname -eq $item.NameLast -and $ADUser.GivenName -eq $item.NameFirst) {
                    #Add the GUID to the data object
                    $item.ADCurrentUserID = $ADUser.ObjectGUID

                    #Add the Current AD Groups to the data object
                    $item.ADCurrentGroups = ($ADUser.MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name)
                } else {
                    Write-Log -Path $logFile -Message ("AD: Username " + $item.username + " for " + $item.personID + " is already taken with a different name of " + $ADUser.GivenName + " " + $ADUser.Surname) -Level Error
                }
            } 
        }
    }

    return $UserList
}