#### IDBridge ####
#### Created by Sam Cattanach ####
# Get-Content -Path "C:\IDBridge\Logs\IDBridge.log" -Tail 200 -Wait
### TO DO:
### Convert Config files to PSD1

#region Import Modules
try {
    Import-Module (Get-Content "C:\IDBridge\Config\ModulePath.json" -Raw | ConvertFrom-Json) -Force -Verbose -ErrorAction Stop
} catch { Throw $_ }
#endregion Import Modules

#region Set Logging
Initialize-Logging
#endregion Set Logging

#region Import Configuration
try {
    #Import the configuration
    $IDConfig = Get-IDBridgeConfiguration -ErrorAction Stop

    #Import the Google Authentication File
    $googleJSONPath = Get-IDBridgeGoogleAuthFile -ErrorAction Stop
}
catch { Throw (Start-ScriptEnd -Message $_ -WriteError) }
#endregion Import Configuration


#region Google Authorization Token
try {
    $headers = Get-GoogleApiAccessToken -ServiceAccountKeyPath $googleJSONPath -Scope $IDConfig.GoogleToken.googleAuthScope -TargetUserEmail $IDConfig.GoogleToken.adminEmail
}
catch { Throw (Start-ScriptEnd -Message $_ -WriteError) }
#endregion Google Authorization Token


#region Gather Data
#region Spreadsheet Data Staff
try {
    $dataStaff = Get-SourceDataGSheet -personType "Staff" -sheetID $IDConfig.GoogleSheet.sheetID -sheetRange $IDConfig.GoogleSheet.sheetRange -userCount $IDConfig.General.staffCount -logFile $logFile -headers $headers

    #Make sure the data is valid and has columns
    $filteredData = Limit-SourceDataGSheet -SourceData $dataStaff
}
catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError) }
#endregion Spreadsheet Data Staff


#region Get Google Data
if ($IDConfig.Google.enabled -eq $true) {
    try {
        $googleData = Get-TargetDataGoogle -logFile $logFile -headers $headers -VerboseLogging $IDConfig.Debug.verboseLogging -ErrorAction Stop
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError) }
}
#endregion Get Google Data


#region Get Data AD
if ($IDConfig.AD.enabled -eq $true) {
    try {
        $adData = Get-TargetDataAD -logFile $logFile -ErrorAction Stop
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError)}
}
#endregion Get Data AD
#endregion Gather Data


#region Data Modifcation
#Add additional data to the user objects
foreach ($item in $filteredData) {
    $item = Set-AdditionalUserData -IDConfig $IDConfig -userObject $item -logFile $logFile

    if ($IDConfig.Google.enabled -eq $true) {
        $item = Set-AdditionalUserDataGoogle -userObject $item -googleUsers $googleData.LookupByID -duplicateGoogleUsers $googleData.DuplicateIDs -logFile $logFile
    }

    if ($IDConfig.AD.enabled -eq $true) {
        $item = Set-AdditionalUserDataAD -userObject $item -ADUsers $adData.LookupByID -duplicateADUsers $adData.DuplicateIDs -logFile $logFile
    }
}
#endregion Data Modifcation


#region Groups Not Processed
#AD Checks
if (($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedAD -UserList $filteredData -CurrentADGroups $adData.Groups -logFile $logFile
}

#Google Checks
if (($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedGoogle -UserList $filteredData -CurrentGoogleGroups $googleData.Groups -logFile $logFile
}
#endregion Groups Not Processed


#region Gather AD Processing Lists
if ($IDConfig.AD.enabled -eq $true) {
    #Org Units to Create
    $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $filteredData -UserRootOU $IDConfig.AD.userRootOU -CurrentOrgUnits $adData.OrgUnits -logFile $logFile

    #Users to Deactivate
    $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $filteredData -logFile $logFile
    
    #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
    $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $filteredData -CurrentADUsers $adData.Users -logFile $logFile
    foreach ($item in $filteredData) {
        if ($ADUsersToSetEmployeeID[$item.personID]) {
            Write-Log -Path $logFile -Message ("AD: Matched $($ADUsersToSetEmployeeID[$item.personID].ADUser.UserPrincipalName) with EmployeeID: $($item.personID).")
            $item.ADCurrentUserID = $ADUsersToSetEmployeeID[$item.personID].ADCurrentUserID
            $item.ADCurrentGroups = $ADUsersToSetEmployeeID[$item.personID].ADCurrentGroups
            $item.ADCurrentUserEnabledStatus = $ADUsersToSetEmployeeID[$item.personID].ADCurrentUserEnabledStatus
            $adData.LookupByID[$item.personID] = $ADUsersToSetEmployeeID[$item.personID].ADUser
        }
    }

    #Users to Update
    $ADUsersToUpdate = Get-ADUsersToUpdate -UserList $filteredData -CurrentADUsersLookupByID $adData.LookupByID -logFile $logFile

    #Users to Create
    $ADUsersToCreate = Get-ADUsersToCreate -UserList $filteredData -CurrentADUsers $adData.Users -SectretType 'Word' -logFile $logFile

    #Groups to Update
    if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
        $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $filteredData -CurrentADGroups $adData.Groups -logFile $logFile
    }

}
#endregion Gather AD Processing Lists

#region Process AD Changes
if ($IDConfig.AD.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
    #Create Orgs
    foreach ($item in $ADOrgUnitsForProcessing | Sort-Object -Unique) {
        try {
            New-IDBridgeADOrgUnit -OrgUnit $item -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message "AD: Error Creating Org Unit. Please check RunAS user permisisons in AD or Detailed Error for more information" -Level Error
            Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError)
        }  
    }

    #Disable Users
    foreach ($item in $ADUsersToDeactivate) {
        try {
            Disable-IDBridgeADUser -User $item -GroupRemovalProcessingStatus $IDConfig.AD.enableGroupProcessingTrash -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }
    

    #Update Users
    foreach ($item in $ADUsersToUpdate.UpdateList) {
        try {
            Write-Log -Path $logFile -Message "AD: Updating User: $($item.CN) Properties: $($item.splat | ConvertTo-Json -Compress)"
            $itemSplat = $null
            $itemSplat = $item.splat
            Set-ADUser @itemSplat -ErrorAction Stop
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Rename Users
    foreach ($item in $ADUsersToUpdate.RenameList) {
        try {
            Write-Log -Path $logFile -Message "AD: Renaming User: $($item.CN) to $($item.NewName)"
            Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
            Rename-ADObject -Identity $item.ADUserID -NewName $item.NewName -ErrorAction Stop
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Move Users
    foreach ($item in $ADUsersToUpdate.MoveList) {
        try {
            Write-Log -Path $logFile -Message "AD: Moving User: $($item.CN) to $($item.NewOrgUnit)"
            Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
            Move-ADObject -Identity $item.ADUserID -TargetPath $item.NewOrgUnit -ErrorAction Stop
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Create Users
    foreach ($item in $ADUsersToCreate) {
        try {
            Write-Log -Path $logFile -Message "AD: Creating User: $($item.PersonID) Properties: $($item.splat | ConvertTo-Json -Compress)"
            $itemSplat = $null
            $itemSplat = $item.splat
            $newUser = New-ADUser @itemSplat -ErrorAction Stop

            #Add the GUID to the data object
            foreach ($dataItem in $filteredData | Where-Object {$_.UPN -eq $itemSplat.UserPrincipalName}) {
                $dataItem.ADCurrentUserID = $newUser.ObjectGUID
            }
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Process Group Membership
    if ($IDConfig.AD.enableGroupProcessing -eq $true) {
        #Process Group Membership Add
        foreach ($item in $ADUserGroupsToUpdate.Add) {
            foreach ($group in $item.Groups) {
                try {
                    Write-Log -Path $logFile -Message "AD: Adding Group: $group to $($item.PersonID)"
                    Add-ADPrincipalGroupMembership -Identity $item.ADCurrentUserID -MemberOf $group
                }
                catch {
                    Write-Log -Path $logFile -Message $_ -Level Error
                }
            }
        }

        #Process Group Membership Remove
        if ($IDConfig.AD.enableGroupProcessingRemove -eq $true) {
            foreach ($item in $ADUserGroupsToUpdate.Remove) {
                foreach ($group in $item.Groups) {
                    try {
                        Write-Log -Path $logFile -Message "AD: Removing Group: $group from $($item.PersonID)"
                        Remove-ADGroupMember -Identity $group -Members $item.ADCurrentUserID -Confirm:$false
                    }
                    catch {
                        Write-Log -Path $logFile -Message $_ -Level Error
                    }
                }
            }
        }
    }
}
#endregion Process AD Changes

#region Report Non Data Users
#### NEED TO ADD ADDITIONAL OPTIONS FOR TEST RUNS BEFORE GOING LIVE WITH THIS SECTION ####
if ($IDConfig.AD.enabled -eq $true) {
    #Get all AD Users to Find Users who are not in the data file.
    $allADUsers = @()

    foreach ($item in $OUCheckAD | Where-Object {$_ -notlike "*,OU=Trash,*"}) {
        $allADUsers += Get-ADUser -Filter * -SearchBase $item -Properties EmployeeID,Surname,GivenName -searchscope 1
    }

    foreach ($item in $allADUsers) {
        if ($item.employeeID -notin $data.personID) {
            Write-Log -Path $logFile -Message "AD: $($item.GivenName) $($item.Surname) not in data file."
        }
    }
}
#endregion Report Non Data Users
#endregion Processing AD





#region Processing Google
#region Google OUs
if ($IDConfig.Google.enabled -eq $true) {
    #Manual and Top Level OUs to Check
    $OUCheckGoogle = @(
        $IDConfig.Google.userRootOU
        ($IDConfig.Google.userRootOU + "/Student")
        ($IDConfig.Google.userRootOU + "/Staff")
        ("/Trash")
        ("/Trash/Student")
        ("/Trash/Staff")
    )

    #Create the OUs to check
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true} | Select-Object -ExpandProperty GoogleOrganizationalUnit | Sort-Object -Unique) {
        $OUCheckGoogle += $item
    }

    #Create the OUs to check
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true} | Select-Object -ExpandProperty GoogleOrganizationalUnitTrash | Sort-Object -Unique) {
        $OUCheckGoogle += $item
    }

    #Create Org Units that do not exist
    foreach ($item in $OUCheckGoogle | Where-Object {$_ -notin $googleData.OrgUnits.orgUnitPath}) {
        Write-Log -Path $logFile -Message "Google: Creating org unit: $($item)"
        if ($IDConfig.Debug.readOnly -eq $false) {
            try {
                New-GoogleOrganizationalUnit -NewOrgUnitFullPath $item -tokenInformation $headers
            }
            catch {
                Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError)
            }
        }
    }
}
#endregion Google OUs

#region Deactive Google Users
if ($IDConfig.Google.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $false -and $_.GoogleCurrentUserSuspendedStatus -eq $false}) {
        if (-not [string]::IsNullOrEmpty($item.GoogleCurrentGroups)) {
            Write-Log -Path $logFile -Message "Google: Current Groups for $($item.UPN): $($item.GoogleCurrentGroups -join ",")"
            Write-Log -Path $logFile -Message ($item.GoogleCurrentGroups -join ",")

            if ($IDConfig.Google.enableGroupProcessingTrash -eq $true) {
                foreach ($group in $item.GoogleCurrentGroups) {
                    Write-Log -Path $logFile -Message ("Google: Removing Group: $group from " + $item.personID)
                    if ($IDConfig.Debug.readOnly -eq $false) {
                        Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headers
                    }
                }
            }
        } else {
            Write-Log -Path $logFile -Message ("Google: Current groups for " + $item.UPN + " : NONE")
        }

        Write-Log -Path $logFile -Message ("Google: Disabling account for " + $item.UPN)
        Write-Log -Path $logFile -Message  ("Google: Moving account to trash: " + $item.UPN)
        if ($IDConfig.Debug.readOnly -eq $false) {
            Update-GoogleUser -GoogleUserID $item.GoogleCurrentUserID -OrgUnitPath $item.GoogleOrganizationalUnitTrash -Suspended 'true' -tokenInformation $headers
        }
    }
}
#endregion Deactive Google Users

#region Set Google EmployeeID
if ($IDConfig.Google.enabled -eq $true) {
    # Set Users employeeID if not set in Google based on UPN
    # UPN has to pair with the first name and last name
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and -not $_.GoogleCurrentUserID -and -not $_.GoogleDuplicateIDStatus}) {
        Write-Log -Path $logFile -Message ("Google: No user found with EmployeeID: " + $item.personID)
        
        if ($item.UPN -in $googleData.Users.primaryEmail) {
            $googleUser = ($googleData.Users | Where-Object {$_.primaryEmail -eq $item.UPN})

            if ($googleUser.Name.familyName -eq $item.NameLast -and $googleUser.Name.givenName -eq $item.NameFirst) {
                #Update the user account employeeID with the personID
                Write-Log -Path $logFile -Message ("Google: Setting ExternalID field for: " + $item.UPN + " - " + $item.personID)

                if ($IDConfig.Debug.readOnly -eq $false) {
                    Update-GoogleUser -GoogleUserID $googleUser.ID -PersonID $item.personID -tokenInformation $headers

                    #Add the Google ID to the data object
                    $item.GoogleCurrentUserID = $googleUser.ID

                    #Add the Current Google Groups to the data object
                    $item.GoogleCurrentGroups = $googleUser.CurrentGroups
                }
            } else {
                Write-Log -Path $logFile -Message ("Google: Username: " + $item.UPN + " for " + $item.personID + " is already taken with a different name of " + $googleUser.Name.givenName + " " + $googleUser.Name.familyName) -Level Error
            }
        }

        if ($googleUser) {Remove-Variable googleUser}
    }
}
#endregion Set Google EmployeeID

#region Update Google Users
if ($IDConfig.Google.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and $_.GoogleCurrentUserID}) {
        $googleUser = $googleData.LookupByID[$item.personID]

        $itemUpdateSplat = @{}

        if ($googleUser.primaryEmail -ne $item.UPN) {
            if ($item.UPN -notin ($googleData.Users.emails | Select-Object -ExpandProperty address)) {
                $itemUpdateSplat["PrimaryEmail"] = $item.UPN
            } else {
                Write-Log -Path $logFile -Message ("Google: Failed to Update User: " + $item.personID + " with new UPN: " + $item.UPN + ". New UPN already in use.") -Level Error
                continue
            }
        }

        if ($googleUser.Name.givenName -ne $item.NameFirst -or $googleUser.Name.familyName -ne $item.NameLast) {
            $itemUpdateSplat["FirstName"] = $item.NameFirst.trim()
            $itemUpdateSplat["LastName"] = $item.NameLast.trim()
        }

        if ($googleUser.organizations.department -ne $item.Building -or $googleUser.organizations.title -ne $item.JobTitle) {
            $itemUpdateSplat["Building"] = $item.Building
            $itemUpdateSplat["JobTitle"] = $item.JobTitle
        }

        if ($googleUser.suspended -ne $false) {
            $itemUpdateSplat["Suspended"] = 'false'
        }

        if ($googleUser.orgUnitPath -ne $item.GoogleOrganizationalUnit) {
            $itemUpdateSplat["OrgUnitPath"] = $item.GoogleOrganizationalUnit
        }

        #Update the user account information if needed
        if ($itemUpdateSplat.Count -gt 0) {
            $itemUpdateSplat["GoogleUserID"] = $item.GoogleCurrentUserID

            Write-Log -Path $logFile -Message ("Google: Updating Information for: " + $item.UPN + " - " + $item.personID)
            Write-Log -Path $logFile -Message ($itemUpdateSplat | ConvertTo-Json -Compress)

            $itemUpdateSplat["tokenInformation"] = $headers

            if ($IDConfig.Debug.readOnly -eq $false) {
                Update-GoogleUser @itemUpdateSplat
            }
        }

        if ($googleUser) {Remove-Variable googleUser}
    }
}
#endregion Update Google Users

#region Create Google Users
if ($IDConfig.Google.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and -not $_.GoogleCurrentUserID -and $_.UPN -notin $googleData.Users.primaryEmail}) {
        $itemCreateSplat = @{
            "PrimaryEmail" = $item.UPN
            "PersonID" = $item.personID
            "FirstName" = $item.NameFirst.trim()
            "LastName" = $item.NameLast.trim()
            "Building" = $item.Building
            "JobTitle" = $item.JobTitle
            "OrgUnitPath" = $item.GoogleOrganizationalUnit
        }

        if ($item.GoogleChangeAtNextLogin) {
            $itemCreateSplat["ChangeAtNextLogin"] = 'true'
        } else {
            $itemCreateSplat["ChangeAtNextLogin"] = 'false'
        }
        
        Write-Log -Path $logFile -Message ("Google: Creating User: " + $item.UPN + " - " + $item.personID)
        Write-Log -Path $logFile -Message ($itemCreateSplat | ConvertTo-Json -Compress)

        if ($IDConfig.Google.randomPassword) {
            $itemCreateSplat["Password"] = (New-Guid).Guid | ConvertTo-SecureString -AsPlainText -Force
        } else {
            $itemCreateSplat["Password"] = ($item.GooglePassPrefix + $item.word) | ConvertTo-SecureString -AsPlainText -Force
        }
        
        $itemCreateSplat["tokenInformation"] = $headers

        if ($IDConfig.Debug.readOnly -eq $false) {
            $newUserResponse = New-GoogleUser @itemCreateSplat

            #Add the Google ID to the data object
            if ($newUserResponse.ID) {
                $item.GoogleCurrentUserID = $newUserResponse.ID
            }
        }

        if ($itemCreateSplat) {Remove-Variable itemCreateSplat}
    }
}
#endregion Create Google Users

#region Process Google Groups
if ($IDConfig.Google.enabled -eq $true) {
    if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
        foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and $_.GoogleCurrentUserID}) {
            $proposedGroupList = @()

            if (-not [string]::IsNullOrEmpty($item.GroupsAutomatic)) {
                $proposedGroupList += $item.GroupsAutomatic
            }

            if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
                $proposedGroupList += ($item.EmailGroups -split ",").trim()
            }

            #Filter out duplicates
            $proposedGroupList = $proposedGroupList | Select-Object -Unique

            #Add groups from Users - Only run if enableGroupProcessing is Enabled
            foreach ($group in $proposedGroupList | Where-Object {$_ -in $googleData.Groups.name}) {
                if (("$group@$($IDConfig.Google.GroupPrimaryDomainName)") -notin $item.GoogleCurrentGroups) {
                    Write-Log -Path $logFile -Message ("Google: Adding Group: $group to " + $item.personID) -WhatIfLogging $IDConfig.Google.enableGroupProcessingWhatIf

                    if ($IDConfig.Google.enableGroupProcessing -eq $true) {
                        if ($IDConfig.Debug.readOnly -eq $false) {
                            Update-GoogleGroupMembers -GroupEmail ($googleData.Groups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add" -TokenInformation $headers
                        }
                    }
                }
            }

            #Remove groups from Users - Only run if enableGroupProcessingRemove is Enabled
            foreach ($group in $item.GoogleCurrentGroups) {
                if ($group.Split("@")[0] -notin $proposedGroupList) {
                    Write-Log -Path $logFile -Message ("Google: Removing Extra Group: $group from " + $item.personID) -WhatIfLogging $IDConfig.Google.enableGroupProcessingWhatIf

                    if ($IDConfig.Google.enableGroupProcessingRemove -eq $true) {
                        if ($IDConfig.Debug.readOnly -eq $false) {
                            Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headers
                        }
                    }
                }
            }

            if ($proposedGroupList) {Remove-Variable proposedGroupList}
        }
    }
}
#endregion Process Google Groups
#endregion Processing Google

#region Export User List
$filteredData | Export-Csv -Path "C:\IDBridge\Exports\UserList-Staff.csv" -NoTypeInformation -Force
#endregion Export User List


Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers