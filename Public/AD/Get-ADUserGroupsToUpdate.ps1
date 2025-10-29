function Get-ADUserGroupsToUpdate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $CurrentADGroups,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    $itemListAdd = @()
    $itemListRemove = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ADCurrentUserID}) {
        #Create list for adding groups
        $userGroupsAdd = @()

        foreach ($groupAdd in $item.ADGroupsProposed | Where-Object {$_ -in $CurrentADGroups}) {
            if ($groupAdd -notin $item.ADCurrentGroups) {
                $userGroupsAdd += $groupAdd
            }
        }

        if ($userGroupsAdd.Count -gt 0) {
            Write-Log -Path $logFile -Message "AD: Information that needs updating - Add Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsAdd -join ', ')"
            $itemListAdd += [PSCustomObject]@{
                PersonID = $item.PersonID
                ADCurrentUserID = $item.ADCurrentUserID
                Groups = $userGroupsAdd
            }
        }

        #Create list for removing groups
        $userGroupsRemove = @()

        foreach ($groupCurrent in $item.ADCurrentGroups) {
            if ($groupCurrent -notin $item.ADGroupsProposed) {
                $userGroupsRemove += $groupCurrent
            }
        }

        if ($userGroupsRemove.Count -gt 0) {
            Write-Log -Path $logFile -Message "AD: Information that needs updating - Remove Groups: $($item.personID) $($item.NameFirst) $($item.NameLast): $($userGroupsRemove -join ', ')"
            $itemListRemove += [PSCustomObject]@{
                PersonID = $item.PersonID
                ADCurrentUserID = $item.ADCurrentUserID
                Groups = $userGroupsRemove
            }
        }
    }

    return [PSCustomObject]@{
        Add = $itemListAdd
        Remove = $itemListRemove
    }
}