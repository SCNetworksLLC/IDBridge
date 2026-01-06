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
if ($IDConfig.Staff.Enabled -eq $true) {
    try {
        $paramsStaff = @{
            personType                  = "Staff"
            sheetID                     = $IDConfig.GoogleSheet.staffSheetID
            sheetRange                  = $IDConfig.GoogleSheet.staffSheetRange
            userCount                   = $IDConfig.Staff.SafetyCheckCount
            userCountSafetyPercentage   = $IDConfig.Staff.SafetyCheckPercentage
            logFile                     = $logFile
            headers                     = $headers
        }

        $dataStaff = Get-SourceDataGSheet @paramsStaff
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError) }
}
#endregion Spreadsheet Data Staff


#region Student - GSheet
if ($IDConfig.Student.Enabled -eq $true -and $IDConfig.Student.SourceType -eq "GSheet") {
    try {
        $paramsStudent = @{
            personType                  = "Student"
            sheetID                     = $IDConfig.GoogleSheet.studentSheetID
            sheetRange                  = $IDConfig.GoogleSheet.studentSheetRange
            userCount                   = $IDConfig.Student.SafetyCheckCount
            userCountSafetyPercentage   = $IDConfig.Student.SafetyCheckPercentage
            logFile                     = $logFile
            headers                     = $headers
        }

        $dataStudent = Get-SourceDataGSheet @paramsStudent

        $dataStudent | Export-CSV -NoTypeInformation -Path "C:\IDBridge\Exports\IDBridge_StudentData_$(Get-Date -Format yyyyMMdd_HHmmss).csv" -Force
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError) }
}
#endregion Student - GSheet


#region Student - Skyward SMS
if ($IDConfig.Student.Enabled -eq $true -and $IDConfig.Student.SourceType -eq "SkywardSMS") {
    try {
        $paramsStudent = @{
            BaseUrl                 = $IDConfig.SkywardSMS.BaseUrl
            TokenUrl                = $IDConfig.SkywardSMS.TokenUrl
            ClientId                = $IDConfig.SkywardSMS.ClientId
            ClientSecret            = $IDConfig.SkywardSMS.ClientSecret
            ExcludeEntityIDs        = $IDConfig.SkywardSMS.ExcludeEntityIDs
            SafetyCheckCount        = $IDConfig.Student.SafetyCheckCount
            SafetyCheckPercentage   = $IDConfig.Student.SafetyCheckPercentage
            LogFile                 = $logFile
            VerboseLogging          = $IDConfig.Debug.verboseLogging
        }

        $dataStudentSource = Get-SourceDataSkywardSMS @paramsStudent
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError) }

    #Transform Data to be compatible with IDBridge
    $dataStudent = $dataStudentSource | ForEach-Object {
        [PSCustomObject]@{
            PersonID             = $_.DisplayId
            NameFirst            = $_.FirstName
            NameLast             = $_.LastName
            Username             = $_.DisplayId
            Building             = (Get-Culture).TextInfo.ToTitleCase($($_.SchoolName).ToLower())
            Grade                = (Get-StudentGrade -gradYear $_.GradYr -gradeAdvanceDate $IDConfig.Student.GradeAdvanceDate)
            GradYear             = $_.GradYr
            JobTitle             = "Student - Grade $(Get-StudentGrade -gradYear $_.GradYr -gradeAdvanceDate $IDConfig.Student.GradeAdvanceDate)"
            Word                 = $_.FoodServiceKeyPadNumber
        }
    }

    $dataStudent | Export-CSV -NoTypeInformation -Path "C:\IDBridge\Exports\IDBridge_StudentData_$(Get-Date -Format yyyyMMdd_HHmmss).csv" -Force
}
#endregion Student - Skyward SMS


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
        $adData = Get-TargetDataAD -logFile $logFile -VerboseLogging $IDConfig.Debug.verboseLogging -ErrorAction Stop
    }
    catch { Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message $_ -WriteError)}
}
#endregion Get Data AD
#endregion Gather Data




#region Data Modifcation
#Add additional data to the user objects
if ($IDConfig.Student.Enabled -eq $true) {
    foreach ($item in $dataStudent) {
        $groupsAutomatic = $null
        $groupsAutomatic = if ($IDConfig.Custom.Student.Groups -and (Test-Path Function:\Get-CustomStudentGroups)) {Get-CustomStudentGroups -building $item.Building -grade $item.Grade}

        #AD Proposed Groups
        $proposedGroupListAD = @()
        if ($groupsAutomatic) {$proposedGroupListAD += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {$proposedGroupListAD += ($item.ApplicationGroups -split ",").trim()}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupListAD += ($item.EmailGroups -split ",").trim()}

        #Google Proposed Groups
        $proposedGroupListGoogle = @()
        if ($groupsAutomatic) {$proposedGroupListAD += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupListGoogle += ($item.EmailGroups -split ",").trim()}

        $additionalUserProperties = [PSCustomObject]@{
            IDBActive                       = if ($item.IDBActive -eq $true) { $IDConfig.Student.$($item.Grade).Enabled }
            PersonTypeID                    = "1"
            UPN                             = "$($item.Username)@$($IDConfig.Student.DomainName)"
            Company                         = $IDConfig.Student.Company
            GroupsAutomatic                 = $groupsAutomatic

            Building                        = $item.Building
            JobTitle                        = $item.JobTitle
            Word                            = $item.Word

            ADOrganizationalUnit            = "OU=Grade-$($item.Grade),OU=Students,$($IDConfig.AD.userRootOU)"
            ADOrganizationalUnitTrash       = "OU=$($item.GradYear),OU=Students,OU=Trash,$($IDConfig.AD.userRootOU)"
            ADPassPrefix                    = $IDConfig.Student.$($item.Grade).AD.passPrefix
            ADChangePasswordAtLogon         = $IDConfig.Student.$($item.Grade).AD.ChangePasswordAtLogon
            ADPasswordType                  = $IDConfig.Student.$($item.Grade).AD.PasswordType
            ADGroupsProposed                = $proposedGroupListAD | Select-Object -Unique

            GoogleOrganizationalUnit        = "$($IDConfig.Google.userRootOU)/Students/Grade-$($item.Grade)"
            GoogleOrganizationalUnitTrash   = "/Trash/Students/$($item.GradYear)"
            GooglePassPrefix                = $IDConfig.Student.$($item.Grade).Google.passPrefix
            GoogleChangePasswordAtLogon     = $IDConfig.Student.$($item.Grade).Google.ChangePasswordAtLogon
            GooglePasswordType              = $IDConfig.Student.$($item.Grade).Google.PasswordType
            GoogleGroupsProposed            = $proposedGroupListGoogle | Select-Object -Unique

            ADObject                         = if ($IDConfig.AD.enabled -eq $true) {($adData.LookupByID[$item.personID])}
            ADCurrentUserID                  = if ($IDConfig.AD.enabled -eq $true) {($adData.LookupByID[$item.personID]).ObjectGUID}
            ADCurrentUserEnabledStatus       = if ($IDConfig.AD.enabled -eq $true) {($adData.LookupByID[$item.personID]).Enabled}
            ADCurrentGroups                  = if ($IDConfig.AD.enabled -eq $true) {($adData.LookupByID[$item.personID]).CurrentGroups}
            ADDuplicateIDStatus              = if ($IDConfig.AD.enabled -eq $true -and ($item.PersonID -in $adData.DuplicateUsers.employeeID)) {"DUPLICATE_ID"}

            GoogleObject                     = if ($IDConfig.Google.enabled -eq $true) {($googleData.LookupByID[$item.personID])}
            GoogleCurrentUserID              = if ($IDConfig.Google.enabled -eq $true) {($googleData.LookupByID[$item.personID]).ID}
            GoogleCurrentUserSuspendedStatus = if ($IDConfig.Google.enabled -eq $true) {($googleData.LookupByID[$item.personID]).suspended}
            GoogleCurrentGroups              = if ($IDConfig.Google.enabled -eq $true) {($googleData.LookupByID[$item.personID]).CurrentGroups}
            GoogleDuplicateIDStatus          = if ($IDConfig.Google.enabled -eq $true -and ($item.PersonID -in $googleData.DuplicateUsers.OrgID)) {"DUPLICATE_ID"}
        }

        #Custom Data Loaded from Custom Script
        if ($IDConfig.Custom.Student.DataModification -and (Test-Path Function:\Get-CustomStudentDataModification)) {
            try {
                $additionalUserProperties = Get-CustomStudentDataModification -Item $item -AdditionalUserProperties $additionalUserProperties -IDConfig $IDConfig -logFile $logFile
            }
            catch {
                Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message "Custom Student Data Modification Script Error: $_" -WriteError)
            }
        }

        #Add the additional properties to the user object
        foreach ($itemProperty in $additionalUserProperties.PSObject.Properties) {
            $item | Add-Member -MemberType NoteProperty -Name $itemProperty.Name -Value $itemProperty.Value -Force
        }
    }
}

if ($IDConfig.Staff.Enabled -eq $true) {
    foreach ($item in $dataStaff) {
        $groupsAutomatic = $null
        $groupsAutomatic = if ($IDConfig.Custom.Staff.Groups -and (Test-Path Function:\Get-CustomStaffGroups)) {Get-CustomStaffGroups -building $item.Building -personType $item.PersonType}

        #AD Proposed Groups
        $proposedGroupListAD = @()
        if ($groupsAutomatic) {$proposedGroupListAD += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {$proposedGroupListAD += ($item.ApplicationGroups -split ",").trim()}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupListAD += ($item.EmailGroups -split ",").trim()}

        #Google Proposed Groups
        $proposedGroupListGoogle = @()
        if ($groupsAutomatic) {$proposedGroupListGoogle += $groupsAutomatic}
        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {$proposedGroupListGoogle += ($item.EmailGroups -split ",").trim()}

        $additionalUserProperties = [PSCustomObject]@{
            IDBActive                       = if ($item.TerminationDate -and (Get-Date $item.TerminationDate -format "yyyy-MM-dd") -lt (Get-Date -format "yyyy-MM-dd")) {$false} else {$true}
            PersonTypeID                    = if ($item.PersonType -in $IDConfig.PersonTypeThree) {"3"} else {"2"}
            UPN                             = "$($item.Username)@$($IDConfig.Staff.DomainName)"
            Company                         = $IDConfig.Staff.Company
            GroupsAutomatic                 = $groupsAutomatic
            
            Building                        = $item.Building
            JobTitle                        = $item.JobTitle
            Word                            = $item.Word

            ADOrganizationalUnit            = "OU=$($item.PersonType),OU=Staff,$($IDConfig.AD.userRootOU)"
            ADOrganizationalUnitTrash       = "OU=$(Get-Date -Format yyyy),OU=Staff,OU=Trash,$($IDConfig.AD.userRootOU)"
            ADPassPrefix                    = $IDConfig.Staff.AD.passPrefix
            ADChangePasswordAtLogon         = $IDConfig.Staff.AD.ChangePasswordAtLogon
            ADPasswordType                  = $IDConfig.Staff.AD.PasswordType
            ADGroupsProposed                = $proposedGroupListAD | Select-Object -Unique

            GoogleOrganizationalUnit        = "$($IDConfig.Google.userRootOU)/Staff/$($item.PersonType)"
            GoogleOrganizationalUnitTrash   = "/Trash/Staff/$(Get-Date -Format yyyy)"
            GooglePassPrefix                = $IDConfig.Staff.Google.passPrefix
            GoogleChangePasswordAtLogon     = $IDConfig.Staff.Google.ChangePasswordAtLogon
            GooglePasswordType              = $IDConfig.Staff.Google.PasswordType
            GoogleGroupsProposed            = $proposedGroupListGoogle | Select-Object -Unique

            ADObject                         = if ($IDConfig.AD.enabled -eq $true -and $adData.LookupByID) {($adData.LookupByID[$item.personID])}
            ADCurrentUserID                  = if ($IDConfig.AD.enabled -eq $true -and $adData.LookupByID) {($adData.LookupByID[$item.personID]).ObjectGUID}
            ADCurrentUserEnabledStatus       = if ($IDConfig.AD.enabled -eq $true -and $adData.LookupByID) {($adData.LookupByID[$item.personID]).Enabled}
            ADCurrentGroups                  = if ($IDConfig.AD.enabled -eq $true -and $adData.LookupByID) {($adData.LookupByID[$item.personID]).CurrentGroups}
            ADDuplicateIDStatus              = if ($IDConfig.AD.enabled -eq $true -and ($item.PersonID -in $adData.DuplicateUsers.employeeID)) {"DUPLICATE_ID"}

            GoogleObject                     = if ($IDConfig.Google.enabled -eq $true -and $googleData.LookupByID) {($googleData.LookupByID[$item.personID])}
            GoogleCurrentUserID              = if ($IDConfig.Google.enabled -eq $true -and $googleData.LookupByID) {($googleData.LookupByID[$item.personID]).ID}
            GoogleCurrentUserSuspendedStatus = if ($IDConfig.Google.enabled -eq $true -and $googleData.LookupByID) {($googleData.LookupByID[$item.personID]).suspended}
            GoogleCurrentGroups              = if ($IDConfig.Google.enabled -eq $true -and $googleData.LookupByID) {($googleData.LookupByID[$item.personID]).CurrentGroups}
            GoogleDuplicateIDStatus          = if ($IDConfig.Google.enabled -eq $true -and ($item.PersonID -in $googleData.DuplicateUsers.OrgID)) {"DUPLICATE_ID"}
        }

        #Custom Data Loaded from Custom Script
        if ($IDConfig.Custom.Staff.DataModification -and (Test-Path Function:\Get-CustomStaffDataModification)) {
            try {
                $additionalUserProperties = Get-CustomStaffDataModification -Item $item -AdditionalUserProperties $additionalUserProperties -IDConfig $IDConfig -logFile $logFile
            }
            catch {
                Throw (Start-ScriptEnd -UploadLogsSheetID $IDConfig.GoogleSheet.logSheetID -GoogleHeaders $headers -Message "Custom Staff Data Modification Script Error: $_" -WriteError)
            }
        }

        #Add the additional properties to the user object
        foreach ($itemProperty in $additionalUserProperties.PSObject.Properties) {
            $item | Add-Member -MemberType NoteProperty -Name $itemProperty.Name -Value $itemProperty.Value -Force
        }
    }
}
#endregion Data Modifcation




#region Combine Data
#Combining this way so that blank datasets don't cause issues
$filteredData = $(if($dataStaff) { $dataStaff }) + $(if($dataStudent) { $dataStudent })
#endregion Combine Data




#region Remove Duplicate IDs
#Remove Users from Processing with Duplicate IDs from Google or AD
if ($filteredData | Where-Object {$_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus}) {
    foreach ($item in $filteredData | Where-Object {$_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus}) {
        Write-Log -Path $logFile -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - AD Duplicate Status: $($item.ADDuplicateIDStatus) - Google Duplicate Status: $($item.GoogleDuplicateIDStatus)") -Level Info
    }
    $filteredData = $filteredData | Where-Object {-not ($_.ADDuplicateIDStatus -or $_.GoogleDuplicateIDStatus) }
}

#Remove Users from Processing with Duplicate IDs from IDBridge Sources
$duplicateIDs = $filteredData | Where-Object {-not [string]::IsNullOrWhiteSpace($_.personID)} | Group-Object -Property personID | Where-Object {$_.Count -gt 1} | Select-Object -ExpandProperty Name

if ($duplicateIDs) {
    foreach ($item in $filteredData | Where-Object { $_.personID -in $duplicateIDs }) {
        Write-Log -Path $logFile -Message ("Removing User from Processing with Duplicate Person ID: $($item.personID) - UPN: $($item.UPN) - IDBridge Duplicate Status: DUPLICATE_ID") -Level Info
    }
      $filteredData = $filteredData | Where-Object {$_.personID -notin $duplicateIDs}
}
#endregion Remove Duplicate IDs




#region Groups Not Processed
#AD Checks
if ($IDConfig.AD.enabled -eq $true -and ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedAD -UserList $filteredData -CurrentADGroups $adData.Groups -logFile $logFile
}

#Google Checks
if ($IDConfig.Google.enabled -eq $true -and ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) -and $IDConfig.Debug.verboseLogging -eq $true) {
    Show-GroupsNotProcessedGoogle -UserList $filteredData -CurrentGoogleGroups $googleData.Groups -logFile $logFile
}
#endregion Groups Not Processed




#region AD Processing Lists
if ($IDConfig.AD.enabled -eq $true) {
    #Org Units to Create
    $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $filteredData -UserRootOU $IDConfig.AD.userRootOU -CurrentOrgUnits $adData.OrgUnits -logFile $logFile
    
    #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
    $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $filteredData -CurrentADUsers $adData.Users -logFile $logFile
    foreach ($item in $filteredData | Where-Object {$ADUsersToSetEmployeeID.ContainsKey($_.personID)}) {
            Write-Log -Path $logFile -Message ("AD: Matched $($ADUsersToSetEmployeeID[$item.personID].User.UserPrincipalName) with EmployeeID: $($item.personID).")
            $item | Add-Member -MemberType NoteProperty -Name 'ADObject' -Value ($ADUsersToSetEmployeeID[$item.personID].User) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserID' -Value ($ADUsersToSetEmployeeID[$item.personID].ID) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentGroups' -Value ($ADUsersToSetEmployeeID[$item.personID].Groups) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserEnabledStatus' -Value ($ADUsersToSetEmployeeID[$item.personID].EnabledStatus) -Force
            $adData.LookupByID[$item.personID] = ($ADUsersToSetEmployeeID[$item.personID].User)
    }

    #Users to Deactivate
    $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $filteredData -logFile $logFile

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
    
    #Update filteredData list and GoogleLookupByID Table with Google User Info if No EmployeeID is Set and an existing user is found that matches
    $GoogleUsersToSetEmployeeID = Get-GoogleUsersToSetEmployeeID -UserList $filteredData -GoogleUsers $googleData.Users -logFile $logFile
    foreach ($item in $filteredData | Where-Object {$GoogleUsersToSetEmployeeID.ContainsKey($_.personID)}) {
            Write-Log -Path $logFile -Message ("Google: Matched $($GoogleUsersToSetEmployeeID[$item.personID].User.primaryEmail) with EmployeeID: $($item.personID).")
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleObject' -Value ($GoogleUsersToSetEmployeeID[$item.personID].User) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserID' -Value ($GoogleUsersToSetEmployeeID[$item.personID].ID) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentGroups' -Value ($GoogleUsersToSetEmployeeID[$item.personID].Groups) -Force
            $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserSuspendedStatus' -Value ($GoogleUsersToSetEmployeeID[$item.personID].SuspendedStatus) -Force
            $googleData.LookupByID[$item.personID] = ($GoogleUsersToSetEmployeeID[$item.personID].User)
    }

    #Users to Update
    $GoogleUsersToUpdate = Get-GoogleUsersToUpdate -UserList $filteredData -LookupByID $googleData.LookupByID -GoogleUsers $googleData.Users -logFile $logFile

    #Users to Deactivate
    $GoogleUsersToDeactivate = Get-GoogleUsersToDeactivate -UserList $filteredData -logFile $logFile

    #Users to Create
    $GoogleUsersToCreate = Get-GoogleUsersToCreate -UserList $filteredData -GoogleUsers $googleData.Users -logFile $logFile

    #Groups to Update
    if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
        $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $filteredData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName -logFile $logFile
    }
}
#endregion Google Processing Lists




#region Google Orphaned List
#Get Orphaned Google Users for Deactivation
if ($IDConfig.Staff.OrphanedUserDeactivation.Google.Enabled -eq $true -or $IDConfig.Debug.OrphanedUsersStaff -eq $true) {

    if ($IDConfig.Staff.OrphanedUserDeactivation.Google.TrashOUPathIncludesYear -eq $true) {
        $trashOU = "$($IDConfig.Staff.OrphanedUserDeactivation.Google.TrashOUPath)/$(Get-Date -Format yyyy)"
    } else {
        $trashOU = $IDConfig.Staff.OrphanedUserDeactivation.Google.TrashOUPath
    }

    $GoogleUsersOrphanedStaff = Get-GoogleUsersOrphaned -UserList $filteredData -GoogleUsers $googleData.Staff -TrashOU $trashOU -logFile $logFile
}

if ($IDConfig.Student.OrphanedUserDeactivation.Google.Enabled -eq $true -or $IDConfig.Debug.OrphanedUsersStudent -eq $true) {
    if ($IDConfig.Student.OrphanedUserDeactivation.Google.TrashOUPathIncludesYear -eq $true) {
        $trashOU = "$($IDConfig.Student.OrphanedUserDeactivation.Google.TrashOUPath)/$(Get-Date -Format yyyy)"
    } else {
        $trashOU = $IDConfig.Student.OrphanedUserDeactivation.Google.TrashOUPath
    }
    
    $GoogleUsersOrphanedStudent = Get-GoogleUsersOrphaned -UserList $filteredData -GoogleUsers $googleData.Students -TrashOU $trashOU -logFile $logFile
}
#endregion Google Orphaned List




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
            ($filteredData | Where-Object UPN -eq $itemSplat.UserPrincipalName).ADCurrentUserID = $newUser.ObjectGUID
            
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
            $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $filteredData -CurrentADGroups $adData.Groups -logFile $logFile
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



#region Report Non Data Users
#### NEED TO ADD ADDITIONAL OPTIONS FOR TEST RUNS BEFORE GOING LIVE WITH THIS SECTION ####
if ($IDConfig.AD.enabled -eq $true -and $IDConfig.Debug.verboseLogging -eq $true) {
    #Get all AD Users to Find Users who are not in the data file.
    $allADUsers = @()

    #Manual and Top Level OUs to Check
    $OUList = @(
        $IDConfig.AD.userRootOU
        ("OU=Student," + $IDConfig.AD.userRootOU)
        ("OU=Staff," + $IDConfig.AD.userRootOU)
        ("OU=Trash," + $IDConfig.AD.userRootOU)
        ("OU=Student,OU=Trash," + $IDConfig.AD.userRootOU)
        ("OU=Staff,OU=Trash," + $IDConfig.AD.userRootOU)
    )

    #Add the OUs to check from only active users
    $OUListAuto = @()
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true}) {
        $OUListAuto += $item.ADOrganizationalUnit
        $OUListAuto += $item.ADOrganizationalUnitTrash
    }

    #Combine Base and OU Lists - This is needed to be done this way so that the base OUs get processed first
    $OUList += $OUListAuto | Sort-Object -Unique

    foreach ($item in $OUList | Where-Object {$_ -notlike "*,OU=Trash,*"}) {
        $allADUsers += Get-ADUser -Filter * -SearchBase $item -Properties EmployeeID,Surname,GivenName -searchscope 1
    }

    foreach ($item in $allADUsers) {
        if ($item.employeeID -notin $filteredData.personID) {
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
            ($filteredData | Where-Object UPN -eq $itemSplat.PrimaryEmail).GoogleCurrentUserID = $newUserResponse.ID
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
            $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $filteredData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName -logFile $logFile
        }

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