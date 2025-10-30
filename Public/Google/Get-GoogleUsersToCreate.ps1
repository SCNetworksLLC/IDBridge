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

        #Pass additional attributes if they exist`
        if ($item.GooglePasswordType -eq "Random") {
            $itemCreateSplat["Password"] = (ConvertTo-SecureString (New-Guid).Guid -AsPlainText -Force)
        } elseif ($item.GooglePasswordType -eq "FSPIN") {
            $itemCreateSplat["Password"] = (ConvertTo-SecureString ($item.GooglePassPrefix + $item.FSPIN) -AsPlainText -Force)
        } elseif ($item.GooglePasswordType -eq "Word") {
            $itemCreateSplat["Password"] = (ConvertTo-SecureString ($item.GooglePassPrefix + $item.Word) -AsPlainText -Force)
        } else {
            $itemCreateSplat["Password"] = (ConvertTo-SecureString (New-Guid).Guid -AsPlainText -Force)
        }

        Write-Log -Path $logFile -Message ("Google: No user found for $($item.PersonID). Adding user to create list.")
        Write-Log -Path $logFile -Message ($NewUserParams | ConvertTo-Json -Compress)

        $itemList += [PSCustomObject]@{
            UPN = $item.UPN
            Splat = $itemCreateSplat
        }
    }

    return $itemList
}