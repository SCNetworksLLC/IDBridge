function Disable-IDBridgeADUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        $GroupRemovalProcessingStatus,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    #Disable the account
    try {
        Write-Log -Path $logFile -Message ("AD: Disabling account for " + $User.PersonID)
        Set-ADUser -Identity $User.ADCurrentUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm) -Enabled $false
    }
    catch {
        return $_
    }

    #Move the User to the Trash OU
    try {
        Write-Log -Path $logFile -Message ("AD: Moving user to trash: " + $User.PersonID)
        Move-ADObject -Identity $User.ADCurrentUserID -TargetPath $User.ADOrganizationalUnitTrash
    }
    catch {
        return $_
    }

    #Get all the groups and write that to the log
    if (-not [string]::IsNullOrEmpty($User.ADCurrentGroups)) {
        Write-Log -Path $logFile -Message ("AD: Current groups for " + $User.PersonID)
        Write-Log -Path $logFile -Message ($User.ADCurrentGroups -join ",")
        
        if ($GroupRemovalProcessingStatus -eq $true) {
            Write-Log -Path $logFile -Message  ("AD: Removing groups for " + $User.PersonID)
            try {
                $User.ADCurrentGroups | Remove-ADGroupMember -Members $User.ADCurrentUserID -Confirm:$false
            }
            catch {
                Write-Log -Path $logFile -Message ("AD: Error removing groups for " + $User.PersonID) -Level Error
                return $_
            }
        } else {
            Write-Log -Path $logFile -Message ("AD: Group removal processing is disabled for " + $User.PersonID + ". <No Action Taken>")
        }
    } else {
        Write-Log -Path $logFile -Message ("AD: Current groups for " + $User.PersonID + " : NONE")
    }
}