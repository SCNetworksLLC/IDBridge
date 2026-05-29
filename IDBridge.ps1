#### IDBridge ####
#### Created by Sam Cattanach ####
# Get-Content -Path "C:\IDBridge\Logs\IDBridge.log" -Tail 200 -Wait

#region Import Modules
try {
    Import-Module "C:\GIT\IDBridge\IDBridge.psd1" -Force -ErrorAction Stop
} catch { Throw $_ }
#endregion Import Modules




#region Import Configuration
try {
    $global:IDConfig = Get-IDBridgeConfiguration -ErrorAction Stop
}
catch { Throw $_; Exit 1 }
#endregion Import Configuration




#region Google Authorization Token
try {
    $headersGoogle = Get-GoogleApiAccessToken -ServiceAccountKeyPath $IDConfig.GoogleToken.authFilePath -Scope $IDConfig.GoogleToken.googleAuthScope -TargetUserEmail $IDConfig.GoogleToken.adminEmail
}
catch { Throw (Start-ScriptEnd -Message $_ -WriteError) }
#endregion Google Authorization Token





#region Source Plugins
<#
Check for enabled plugins and if the function exists for them, if not disable the plugin and log a warning
For each plugin, run the funciton, and add the returned values to an array to be processed later in the script.
This allows for dynamic data gathering and processing based on the plugins enabled in the configuration file.
There are specific plugin types.
Source plugins gather data that is used as the basis for processing in the script, such as user lists from a SIS or HR system.
Override plugins gather data that is used to override or modify the source data before processing.
#>
$sourceData = @()
$overrideData = @()
foreach ($plugin in $IDConfig.Plugins.GetEnumerator() | Sort-Object Name) {
    if ($plugin.Value.Enabled -ne $true) {
        if ($IDConfig.Debug.verboseLogging -eq $true) {
            Write-Log -Path $logFile -Message "Plugin: $($plugin.Value.Function) is disabled in config. Skipping plugin." -Level Info
        }
        Continue
    }

    if (-not (Get-Command $plugin.Value.Function -ErrorAction SilentlyContinue)) {
        Write-Log -Path $logFile -Message "Plugin: $($plugin.Value.Function) is enabled in config but not found. Disabling plugin." -Level Warn
        $plugin.Value.Enabled = $false
        Continue
    }

    #If the plugin is enabled and the function exists, run the plugin to gather data and add it to the list of data to be processed later in the script.
    try {
        Write-Log -Path $logFile -Message "Running $($plugin.Value.Type) Plugin: $($plugin.Value.Function)" -Level Info
        $pluginData = $null
        $pluginData = & $plugin.Value.Function
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message $_ -WriteError) }

    if ($pluginData) {
        if ($plugin.Value.Type -eq "Source") {
            $sourceData += $pluginData
        }
        if ($plugin.Value.Type -eq "Override") {
            $overrideData += $pluginData
        }
    } else {
        Write-Log -Path $logFile -Message "Plugin: $($plugin.Value.Function) did not return any data." -Level Warn
    }
}

if ($sourceData.Count -eq 0) {
    Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message "No source data gathered from plugins. Please check plugin configurations and logs for details." -WriteError)
}

#endregion Source Plugins




#region Gather Data
#region Get Google Data
if ($IDConfig.Google.enabled -eq $true) {
    try {
        $googleData = Get-TargetDataGoogle -logFile $logFile -headers $headersGoogle -VerboseLogging $IDConfig.Debug.verboseLogging -ErrorAction Stop
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message $_ -WriteError) }
}
#endregion Get Google Data




#region Get Data AD
if ($IDConfig.AD.enabled -eq $true) {
    try {
        $adData = Get-TargetDataAD -logFile $logFile -VerboseLogging $IDConfig.Debug.verboseLogging -ErrorAction Stop
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message $_ -WriteError)}
}
#endregion Get Data AD
#endregion Gather Data




#region Remove Duplicate IDs
#Remove Users from Processing with Duplicate IDs from Google or AD
if ($sourceData | Where-Object {$_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus}) {
    foreach ($item in $sourceData | Where-Object {$_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus}) {
        Write-Log -Path $logFile -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - AD Duplicate Status: $($item.ADDuplicateIDStatus) - Google Duplicate Status: $($item.GoogleDuplicateIDStatus)") -Level Info
    }
    $sourceData = $sourceData | Where-Object {-not ($_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus) }
}

#Remove Users from Processing with Duplicate IDs from IDBridge Sources
$duplicateIDs = $sourceData | Where-Object {-not [string]::IsNullOrWhiteSpace($_.personID)} | Group-Object -Property personID | Where-Object {$_.Count -gt 1} | Select-Object -ExpandProperty Name

if ($duplicateIDs) {
    foreach ($item in $sourceData | Where-Object { $_.personID -in $duplicateIDs }) {
        Write-Log -Path $logFile -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - IDBridge Duplicate Status: DUPLICATE_ID") -Level Info
    }
      $sourceData = $sourceData | Where-Object {$_.personID -notin $duplicateIDs}
}
#endregion Remove Duplicate IDs





#region Target Data Preparation
$sourceData = foreach ($item in $sourceData) {
    $obj = [ordered]@{}
    foreach ($property in $item.PSObject.Properties) {
        $obj[$property.Name] = $property.Value
    }

    if ($IDConfig.AD.enabled -eq $true) {
        if ($adData.LookupByID) {
            $obj["ADObject"] = ($adData.LookupByID[$item.personID])
            $obj["ADCurrentUserID"] = ($adData.LookupByID[$item.personID]).ObjectGUID
            $obj["ADCurrentUserEnabledStatus"] = ($adData.LookupByID[$item.personID]).Enabled
            $obj["ADCurrentGroups"] = ($adData.LookupByID[$item.personID]).CurrentGroups
        }
        if ($item.PersonID -in $adData.DuplicateUsers.employeeID) {
            $obj["ADDuplicateIDStatus"] = "DUPLICATE_ID"
        }    
    }

    if ($IDConfig.Google.enabled -eq $true) {
        if ($googleData.LookupByID) {
            $obj["GoogleObject"] = ($googleData.LookupByID[$item.personID])
            $obj["GoogleCurrentUserID"] = ($googleData.LookupByID[$item.personID]).ID
            $obj["GoogleCurrentUserSuspendedStatus"] = ($googleData.LookupByID[$item.personID]).suspended
            $obj["GoogleCurrentGroups"] = ($googleData.LookupByID[$item.personID]).CurrentGroups
        }
        if ($item.PersonID -in $googleData.DuplicateUsers.OrgID) {
            $obj["GoogleDuplicateIDStatus"] = "DUPLICATE_ID"
        }
    }

    [PSCustomObject]$obj
}
#endregion Target Data Preparation




#region Process Override Data
#Take the data from Data Overrides and apply it to the source data so that the override values are used in processing instead of the original source values.
#This allows for dynamic overrides of source data based on the logic in the override plugins without having to modify the original source data gathering plugins.
#Loop through the data and for each item, check if there is an override. If there is, apply it - don't check for existing data in that field. Skip empty overrides.
if ($overrideData.Count -gt 0) {
    foreach ($item in $sourceData) {
        $overrideItems = $overrideData | Where-Object { $_.personID -eq $item.personID }
        if ($overrideItems) {
            foreach ($overrideItem in $overrideItems) {
                foreach ($property in $overrideItem.PSObject.Properties) {
                    if ($property.Name -eq "PersonID") {
                        continue
                    }

                    if ($null -eq $property.Value -or [string]::IsNullOrWhiteSpace($property.Value)) {
                        continue
                    }

                    if ($property.Name -eq "AddGroup") {
                        $item | Add-Member -MemberType NoteProperty -Name GroupsProposed -Value $($item.GroupsProposed + $property.Value.Trim()) -Force
                        continue
                    }

                    if ($property.Name -eq "RemoveGroup") {
                        $item | Add-Member -MemberType NoteProperty -Name GroupsProposed -Value $(($item.GroupsProposed | Where-Object {$_ -ne $property.Value.Trim()})) -Force
                        continue
                    }

                    $item | Add-Member -MemberType NoteProperty -Name $property.Name -Value $property.Value -Force
                }
            }
        }
    }
}

#endregion Process Override Data




#region Groups Not Processed
#AD Checks
if ($IDConfig.AD.enabled -eq $true -and ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedAD -UserList $sourceData -CurrentADGroups $adData.Groups -logFile $logFile
}

#Google Checks
if ($IDConfig.Google.enabled -eq $true -and ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedGoogle -UserList $sourceData -CurrentGoogleGroups $googleData.Groups -logFile $logFile
}
#endregion Groups Not Processed




#region AD Processing Lists
if ($IDConfig.AD.enabled -eq $true) {
    #Org Units to Create
    $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $sourceData -UserRootOU $IDConfig.AD.userRootOU -CurrentOrgUnits $adData.OrgUnits -logFile $logFile
    
    #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
    $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $sourceData -CurrentADUsers $adData.Users -logFile $logFile
    foreach ($item in $sourceData | Where-Object {$ADUsersToSetEmployeeID.ContainsKey($_.personID)}) {
            Write-Log -Path $logFile -Message ("AD: Matched $($ADUsersToSetEmployeeID[$item.personID].User.UserPrincipalName) with EmployeeID: $($item.personID).")
            $item | Add-Member -MemberType NoteProperty -Name 'ADObject' -Value ($ADUsersToSetEmployeeID[$item.personID].User) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserID' -Value ($ADUsersToSetEmployeeID[$item.personID].ID) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentGroups' -Value ($ADUsersToSetEmployeeID[$item.personID].Groups) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserEnabledStatus' -Value ($ADUsersToSetEmployeeID[$item.personID].EnabledStatus) -Force
            $adData.LookupByID[$item.personID] = ($ADUsersToSetEmployeeID[$item.personID].User)
    }

    #Users to Deactivate
    $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $sourceData -logFile $logFile

    #Users to Update
    $ADUsersToUpdate = Get-ADUsersToUpdate -UserList $sourceData -LookupByID $adData.LookupByID -logFile $logFile

    #Users to Create
    $ADUsersToCreate = Get-ADUsersToCreate -UserList $sourceData -CurrentADUsers $adData.Users -logFile $logFile

    #Groups to Update
    if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
        $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $sourceData -CurrentADGroups $adData.Groups -logFile $logFile
    }
}
#endregion AD Processing Lists




#region Google Processing Lists
if ($IDConfig.Google.enabled -eq $true) {
    #Org Units to Create
    $GoogleOrgUnitsForProcessing = Get-GoogleOrgUnitsForProcessing -UserList $sourceData -UserRootOU $IDConfig.Google.userRootOU -CurrentOrgUnits $googleData.OrgUnits.orgUnitPath -logFile $logFile
    
    #Update filteredData list and GoogleLookupByID Table with Google User Info if No EmployeeID is Set and an existing user is found that matches
    $GoogleUsersToSetEmployeeID = Get-GoogleUsersToSetEmployeeID -UserList $sourceData -GoogleUsers $googleData.Users -logFile $logFile
    foreach ($item in $sourceData | Where-Object {$GoogleUsersToSetEmployeeID.ContainsKey($_.personID)}) {
            Write-Log -Path $logFile -Message ("Google: Matched $($GoogleUsersToSetEmployeeID[$item.personID].User.primaryEmail) with EmployeeID: $($item.personID).")
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleObject' -Value ($GoogleUsersToSetEmployeeID[$item.personID].User) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserID' -Value ($GoogleUsersToSetEmployeeID[$item.personID].ID) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentGroups' -Value ($GoogleUsersToSetEmployeeID[$item.personID].Groups) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserSuspendedStatus' -Value ($GoogleUsersToSetEmployeeID[$item.personID].SuspendedStatus) -Force
            $googleData.LookupByID[$item.personID] = ($GoogleUsersToSetEmployeeID[$item.personID].User)
    }

    #Users to Update
    $GoogleUsersToUpdate = Get-GoogleUsersToUpdate -UserList $sourceData -LookupByID $googleData.LookupByID -GoogleUsers $googleData.Users -logFile $logFile

    #Users to Deactivate
    $GoogleUsersToDeactivate = Get-GoogleUsersToDeactivate -UserList $sourceData -logFile $logFile

    #Users to Create
    $GoogleUsersToCreate = Get-GoogleUsersToCreate -UserList $sourceData -GoogleUsers $googleData.Users -logFile $logFile

    #Groups to Update
    if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
        $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName -logFile $logFile
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
            Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message $_ -WriteError)
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
            ($sourceData | Where-Object UPN -eq $itemSplat.UserPrincipalName).ADCurrentUserID = $newUser.ObjectGUID
            
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Process Group Membership
    if ($IDConfig.AD.enableGroupProcessing -eq $true) {
        #
        if ($ADUsersToCreate.Count -gt 0) {
            #Refresh AD User Groups to Update List to include newly created users
            if ($IDConfig.Debug.verboseLogging -eq $true) {
                Write-Log -Path $logFile -Message "AD: Refreshing AD User Groups to Update List to include newly created users." -Level Info
            }
            $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $sourceData -CurrentADGroups $adData.Groups -logFile $logFile
        }
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




#region Process Google Changes
if ($IDConfig.Google.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
    #Create Org Units
    foreach ($item in $GoogleOrgUnitsForProcessing) {
        try {
            New-IDBridgeGoogleOrgUnit -OrgUnit $item -tokenInformation $headersGoogle -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message "Google: Error Creating Org Unit. Please check API permissions in Google or Detailed Error for more information" -Level Error
            Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle -Message $_ -WriteError)
        }
    }

    #Disable Users
    foreach ($item in $GoogleUsersToDeactivate) {
        try {
            Write-Log -Path $logFile -Message ("Google: Disabling account for " + $item.UPN)
            Write-Log -Path $logFile -Message  ("Google: Moving account to trash: " + $item.UPN)
            Update-IDBridgeGoogleUser -GoogleUserID $item.GoogleCurrentUserID -OrgUnitPath $item.GoogleOrganizationalUnitTrash -Suspended 'true' -tokenInformation $headersGoogle -logFile $logFile
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }

        if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingTrash -eq $true) {
            foreach ($group in $item.GoogleCurrentGroups) {
                try {
                    Write-Log -Path $logFile -Message ("Google: Removing Group: $group from " + $item.personID)
                    Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headersGoogle -logFile $logFile
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
            Update-IDBridgeGoogleUser @itemSplat -tokenInformation $headersGoogle -logFile $logFile
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
            
            $newUserResponse = New-IDBridgeGoogleUser @itemSplat -tokenInformation $headersGoogle -logFile $logFile -ErrorAction Stop

            #Add the Google ID to the data object
            ($sourceData | Where-Object UPN -eq $itemSplat.PrimaryEmail).GoogleCurrentUserID = $newUserResponse.ID
        }
        catch {
            Write-Log -Path $logFile -Message $_ -Level Error
        }
    }

    #Process Group Membership
    if ($IDConfig.Google.enableGroupProcessing -eq $true) {
        if ($GoogleUsersToCreate.Count -gt 0) {
            #Refresh Google User Groups to Update List to include newly created users
            if ($IDConfig.Debug.verboseLogging -eq $true) {
                Write-Log -Path $logFile -Message "Google: Refreshing AD User Groups to Update List to include newly created users." -Level Info
            }
            $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName -logFile $logFile
        }

        #Process Group Membership Add
        foreach ($item in $GoogleUserGroupsToUpdate.Add) {
            foreach ($group in $item.Groups) {
                try {
                    Write-Log -Path $logFile -Message "Google: Adding Group: $group to $($item.PersonID)"
                    Update-GoogleGroupMembers -GroupEmail ($googleData.Groups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add" -TokenInformation $headersGoogle -logFile $logFile
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
                        Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -TokenInformation $headersGoogle -logFile $logFile
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




#region Export User Staff List
$sourceData | Where-Object {$_.PersonTypeID -ne "1"} | Export-Csv -Path "$($IDconfig.Paths.ExportsRoot)\UserList-Staff.csv" -NoTypeInformation -Force
#endregion Export User Staff List




Start-ScriptEnd -UploadLogsSheetID $IDConfig.Logging.SheetID -GoogleHeaders $headersGoogle