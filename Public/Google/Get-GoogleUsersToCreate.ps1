function Get-GoogleUsersToCreate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $GoogleUsers,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and -not $_.GoogleCurrentUserID -and $_.UPN -notin $GoogleUsers.primaryEmail}) {
        $itemCreateSplat = @{}

        $itemCreateSplat = @{
            "PrimaryEmail" = $item.UPN
            "PersonID" = $item.personID
            "FirstName" = $item.NameFirst.trim()
            "LastName" = $item.NameLast.trim()
            "Building" = $item.Building.trim()
            "JobTitle" = $item.JobTitle.trim()
            "OrgUnitPath" = $item.GoogleOrganizationalUnit
        }

        if ($item.GoogleChangeAtNextLogin) {
            $itemCreateSplat["ChangeAtNextLogin"] = 'true'
        } else {
            $itemCreateSplat["ChangeAtNextLogin"] = 'false'
        }


        #Set AccountPassword
        if ($item.GooglePassphraseAPI) {
            try {
                $passphraseParams = @{
                    Nonce = $item.GooglePassphraseAPI.Nonce
                    Username = $item.Username
                    Mode = $item.GooglePassphraseAPI.Mode
                    WordCount = $item.GooglePassphraseAPI.WordCount
                    AuthToken = $item.GooglePassphraseAPI.AuthToken
                }

                $itemCreateSplat["Password"] = (ConvertTo-SecureString (New-Passphrase @passphraseParams) -AsPlainText -Force)
            }
            catch {
                Write-Log -Path $logFile -Message ("Google: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  Password API Error. Skipping User Creation.") -Level "Warn"
                Write-Log -Path $logFile -Message ("Google: Password API Error $($_)") -Level "Warn"
                Continue
            }
        } elseif ($item.GoogleKey) {
            $itemCreateSplat["Password"] = $item.GoogleKey
        } else {
            Write-Log -Path $logFile -Message ("Google: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  ADKey is not set. Skipping User Creation.") -Level "Warn"
            Continue
        }

        Write-Log -Path $logFile -Message ("Google: No user found for $($item.PersonID). Adding user to create list.")
        Write-Log -Path $logFile -Message ($itemCreateSplat | ConvertTo-Json -Compress)

        $itemList += [PSCustomObject]@{
            UPN = $item.UPN
            Splat = $itemCreateSplat
        }
    }

    return $itemList
}