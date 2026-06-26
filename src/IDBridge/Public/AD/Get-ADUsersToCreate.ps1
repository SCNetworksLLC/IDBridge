function Get-ADUsersToCreate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADUsers,

        $Nonce
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionAD -eq $true -and -not $_.ADCurrentUserID -and $_.UPN -notin $CurrentADUsers.UserPrincipalName}) {
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
            PasswordNeverExpires  = $item.PasswordNeverExpires
            PassThru              = $true
            ErrorAction           = "Stop"
        }

        #Set EmployeeNumber if InternalID is present
        if ($item.InternalID) {
            $NewUserParams["EmployeeNumber"] = $item.InternalID
        }

        #Set optional attributes only when provided (set-but-don't-clear)
        if ($item.Description)         { $NewUserParams["Description"]  = $item.Description }
        if ($item.TelephoneNumber)     { $NewUserParams["OfficePhone"]  = $item.TelephoneNumber }
        if ($item.EmailAddress)        { $NewUserParams["EmailAddress"] = $item.EmailAddress }
        if ($item.ExtensionAttribute2) { $NewUserParams.OtherAttributes['extensionAttribute2'] = $item.ExtensionAttribute2 }
        if ($item.ExtensionAttribute3) { $NewUserParams.OtherAttributes['extensionAttribute3'] = $item.ExtensionAttribute3 }
        if ($item.ExtensionAttribute4) { $NewUserParams.OtherAttributes['extensionAttribute4'] = $item.ExtensionAttribute4 }

        #Set AccountPassword
        if ($item.ADPassphraseAPI) {
            try {
                $passphraseParams = @{
                    Nonce = $item.ADPassphraseAPI.Nonce
                    Username = $item.Username
                    Mode = $item.ADPassphraseAPI.Mode
                    WordCount = $item.ADPassphraseAPI.WordCount
                    AuthToken = $item.ADPassphraseAPI.AuthToken
                }

                $NewUserParams["AccountPassword"] = (ConvertTo-SecureString (New-Passphrase @passphraseParams) -AsPlainText -Force)
            }
            catch {
                Write-Log -Message ("AD: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  Password API Error. Skipping User Creation.") -Level "Warn"
                Write-Log -Message ("AD: Password API Error $($_)") -Level "Warn"
                Continue
            }
        } elseif ($item.ADKey) {
            $NewUserParams["AccountPassword"] = $item.ADKey
        } else {
            Write-Log -Message ("AD: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  ADKey is not set. Skipping User Creation.") -Level "Warn"
            Continue
        }
        

        Write-Log -Message ("AD: No user found for $($item.PersonID). Adding user to create list.")
        Write-Log -Message ($NewUserParams | ConvertTo-Json -Compress)

        $itemList += [PSCustomObject]@{
            PersonID = $item.PersonID
            Splat = $NewUserParams
        }
    }

    return $itemList
}