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




#region AD Processing Lists
if ($IDConfig.AD.enabled -eq $true) {
    #Org Units to Create
    $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $filteredData -UserRootOU $IDConfig.AD.userRootOU -CurrentOrgUnits $adData.OrgUnits -logFile $logFile

    #Users to Deactivate
    $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $filteredData -logFile $logFile
    
    #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
    $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $filteredData -CurrentADUsers $adData.Users -logFile $logFile
    foreach ($item in $filteredData) {
        if ($ADUsersToSetEmployeeID[$item.personID]) {
            Write-Log -Path $logFile -Message ("AD: Matched $($ADUsersToSetEmployeeID[$item.personID].User.UserPrincipalName) with EmployeeID: $($item.personID).")
            $item.ADCurrentUserID = $ADUsersToSetEmployeeID[$item.personID].ID
            $item.ADCurrentGroups = $ADUsersToSetEmployeeID[$item.personID].Groups
            $item.ADCurrentUserEnabledStatus = $ADUsersToSetEmployeeID[$item.personID].EnabledStatus
            $adData.LookupByID[$item.personID] = $ADUsersToSetEmployeeID[$item.personID].User
        }
    }

    #Users to Update
    $ADUsersToUpdate = Get-ADUsersToUpdate -UserList $filteredData -LookupByID $adData.LookupByID -logFile $logFile

    #Users to Create
    $ADUsersToCreate = Get-ADUsersToCreate -UserList $filteredData -CurrentADUsers $adData.Users -logFile $logFile

    #Groups to Update
    if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
        $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $filteredData -CurrentADGroups $adData.Groups -logFile $logFile
    }
}
#endregion AD Processing Lists




#region Google Processing Lists
if ($IDConfig.Google.enabled -eq $true) {
    #Org Units to Create
    $GoogleOrgUnitsForProcessing = Get-GoogleOrgUnitsForProcessing -UserList $filteredData -UserRootOU $IDConfig.Google.userRootOU -CurrentOrgUnits $googleData.OrgUnits.orgUnitPath -logFile $logFile

    #Users to Deactivate
    $GoogleUsersToDeactivate = Get-GoogleUsersToDeactivate -UserList $filteredData -logFile $logFile
    
    #Update filteredData list and GoogleLookupByID Table with Google User Info if No EmployeeID is Set and an existing user is found that matches
    $GoogleUsersToSetEmployeeID = Get-GoogleUsersToSetEmployeeID -UserList $filteredData -GoogleUsers $googleData.Users -logFile $logFile
    foreach ($item in $filteredData) {
        if ($GoogleUsersToSetEmployeeID[$item.personID]) {
            Write-Log -Path $logFile -Message ("Google: Matched $($GoogleUsersToSetEmployeeID[$item.personID].User.primaryEmail) with EmployeeID: $($item.personID).")
            $item.GoogleCurrentUserID = $GoogleUsersToSetEmployeeID[$item.personID].ID
            $item.GoogleCurrentGroups = $GoogleUsersToSetEmployeeID[$item.personID].Groups
            $item.GoogleCurrentUserSuspendedStatus = $GoogleUsersToSetEmployeeID[$item.personID].EnabledStatus
            $googleData.LookupByID[$item.personID] = $GoogleUsersToSetEmployeeID[$item.personID].User
        }
    }

    #Users to Update
    $GoogleUsersToUpdate = Get-GoogleUsersToUpdate -UserList $filteredData -LookupByID $googleData.LookupByID -GoogleUsers $googleData.Users -logFile $logFile

    #Users to Create
    $GoogleUsersToCreate = Get-GoogleUsersToCreate -UserList $filteredData -GoogleUsers $googleData.Users -logFile $logFile

    #Groups to Update
    if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
        $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $filteredData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName -logFile $logFile
    }
}
#endregion Google Processing Lists




#region Process AD Changes
if ($IDConfig.AD.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
    #Create Org Units
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
                #Add AD User ID to the data object
                $dataItem.ADCurrentUserID = $newUser.ObjectGUID

                #Add AD User Groups to the data object
                $ADUserGroupsToUpdate.Add += [PSCustomObject]@{
                    PersonID = $item.PersonID
                    ADCurrentUserID = $item.ADCurrentUserID
                    Groups = $item.ADGroupsProposed
                }
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



#region Process Google Changes
if ($IDConfig.Google.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
    #Create Org Units
    foreach ($item in $GoogleOrgUnitsForProcessing) {
        try {
            New-IDBridgeGoogleOrgUnit -OrgUnit $item -tokenInformation $headers -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message "Google: Error Creating Org Unit. Please check API permissions in Google or Detailed Error for more information" -Level Error
            Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError)
        }
    }

    #Disable Users
    foreach ($item in $GoogleUsersToDeactivate) {
        try {
            Write-Log -Path $logFile -Message ("Google: Disabling account for " + $item.UPN)
            Write-Log -Path $logFile -Message  ("Google: Moving account to trash: " + $item.UPN)
            Update-IDBridgeGoogleUser -GoogleUserID $item.GoogleCurrentUserID -OrgUnitPath $item.GoogleOrganizationalUnitTrash -Suspended 'true' -tokenInformation $headers -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }

        if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingTrash -eq $true) {
            foreach ($group in $item.GoogleCurrentGroups) {
                try {
                    Write-Log -Path $logFile -Message ("Google: Removing Group: $group from " + $item.personID)
                    Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headers -logFile $logFile
                }
                catch {
                    Write-Log -Path $logFile -Message $_ -Level Error
                }
            }
        }
    }

    #Update, Move, Rename Users
    foreach ($item in $GoogleUsersToUpdate) {
        try {
            Write-Log -Path $logFile -Message "Google: Updating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
            $itemSplat = $null
            $itemSplat = $item.splat
            Update-IDBridgeGoogleUser @itemSplat -tokenInformation $headers -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Create Users
    foreach ($item in $GoogleUsersToCreate) {
        try {
            Write-Log -Path $logFile -Message "Google: Creating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
            $itemSplat = $null
            $itemSplat = $item.splat
            
            $newUserResponse = New-IDBridgeGoogleUser @itemSplat -tokenInformation $headers -logFile $logFile -ErrorAction Stop

            #Add the Google ID to the data object
            foreach ($dataItem in $filteredData | Where-Object {$_.UPN -eq $itemSplat.PrimaryEmail}) {
                #Add Google User ID to the data object
                $dataItem.GoogleCurrentUserID = $newUserResponse.ID

                #Add Google User Groups to the data object
                $GoogleUserGroupsToUpdate.Add += [PSCustomObject]@{
                    PersonID = $dataItem.PersonID
                    GoogleCurrentUserID = $item.GoogleCurrentUserID
                    Groups = $item.GoogleGroupsProposed
                }
            }
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Process Group Membership
    if ($IDConfig.Google.enableGroupProcessing -eq $true) {
        #Process Group Membership Add
        foreach ($item in $GoogleUserGroupsToUpdate.Add) {
            foreach ($group in $item.Groups) {
                try {
                    Write-Log -Path $logFile -Message "Google: Adding Group: $group to $($item.PersonID)"
                    Update-GoogleGroupMembers -GroupEmail ($googleData.Groups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add" -TokenInformation $headers -logFile $logFile
                }
                catch {
                    Write-Log -Path $logFile -Message $_ -Level Error
                }
            }
        }

        #Process Group Membership Remove
        if ($IDConfig.Google.enableGroupProcessingRemove -eq $true) {
            foreach ($item in $GoogleUserGroupsToUpdate.Remove) {
                foreach ($group in $item.Groups) {
                    try {
                        Write-Log -Path $logFile -Message "Google: Removing Group: $group from $($item.PersonID)"
                        Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headers -logFile $logFile
                    }
                    catch {
                        Write-Log -Path $logFile -Message $_ -Level Error
                    }
                }
            }
        }
    }
}
#endregion Process Google Changes




#region Export User List
$filteredData | Export-Csv -Path "C:\IDBridge\Exports\UserList-Staff.csv" -NoTypeInformation -Force
#endregion Export User List




Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers