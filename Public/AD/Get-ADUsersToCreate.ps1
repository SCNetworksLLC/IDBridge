function Get-ADUsersToCreate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and -not $_.ADCurrentUserID -and $_.UPN -notin $CurrentADUsers.UserPrincipalName}) {
        $NewUserParams = @{
            Path                  = $item.ADorganizationalUnit
            Name                  = ($item.NameFirst.trim() + " " + $item.NameLast.trim() + " " + $item.PersonID)
            DisplayName           = ($item.NameFirst.trim() + " " + $item.NameLast.trim())
            SamAccountName        = $item.Username
            UserPrincipalName     = $item.UPN
            GivenName             = $item.NameFirst.trim()
            Surname               = $item.NameLast.trim()
            EmployeeID            = $item.PersonID
            Title                 = $item.JobTitle
            Office                = $item.Building
            Company               = $item.Company
            Department            = $item.Department
            Division              = (Get-Date -format yyyy-MM-dd-HH:mm)
            OtherAttributes       = @{ 'EmployeeType' = $item.PersonTypeID ; 'extensionAttribute1' = ($item.PersonTypeID)}
            Enabled               = $true
            ChangePasswordAtLogon = $item.ADChangePasswordAtLogon
            PasswordNeverExpires  = $false
            PassThru              = $true
            ErrorAction           = "Stop"
        }

        #Set EmployeeNumber if InternalID is present
        if ($item.InternalID) {
            $NewUserParams["EmployeeNumber"] = $item.InternalID
        }

        if ($item.ADPasswordType -eq "Random") {
            $NewUserParams["AccountPassword"] = (ConvertTo-SecureString (New-Guid).Guid -AsPlainText -Force)
        } elseif ($item.ADPasswordType -eq "FSPIN") {
            $NewUserParams["AccountPassword"] = (ConvertTo-SecureString ($item.ADPassPrefix + $item.FSPIN) -AsPlainText -Force)
        } elseif ($item.ADPasswordType -eq "Word") {
            $NewUserParams["AccountPassword"] = (ConvertTo-SecureString ($item.ADPassPrefix + $item.Word) -AsPlainText -Force)
        } else {
            $NewUserParams["AccountPassword"] = (ConvertTo-SecureString (New-Guid).Guid -AsPlainText -Force)
        }
        

        Write-Log -Path $logFile -Message ("AD: No user found for $($item.PersonID). Adding user to create list.")
        Write-Log -Path $logFile -Message ($NewUserParams | ConvertTo-Json -Compress)

        $itemList += [PSCustomObject]@{
            PersonID = $item.PersonID
            Splat = $NewUserParams
        }
    }

    return $itemList
}