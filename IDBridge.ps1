#### IDBridge ####
#### Created by Sam Cattanach ####

#region Import Modules
try {
    Import-Module (Get-Content "C:\IDBridge\Config\ModulePath.json" -Raw | ConvertFrom-Json) -Force -Verbose -ErrorAction Stop
}
catch {
    Throw $_
}
#endregion Import Modules

#region Set Logging
#Checks the log file size and renames it if it is larger than 1MB
Initialize-Logging
#endregion Set Logging

#region Import Configuration
try {
    #Test the configuration at C:\IDBridge - Returns True if tests pass
    Test-IDBridgeConfiguration -ErrorAction Stop

    #Import the configuration
    $IDConfig = Get-IDBridgeConfiguration -ErrorAction Stop

    #Import the Google Authentication File
    $googleJSONPath = Get-IDBridgeGoogleAuthFile -ErrorAction Stop
}
catch {
    Throw (Start-ScriptEnd -Message $_ -WriteError)
}
#endregion Import Configuration



#region Google Authorization Token
try {
    $headers = Get-GoogleApiAccessToken -ServiceAccountKeyPath $googleJSONPath -Scope $IDConfig.GoogleToken.googleAuthScope -TargetUserEmail $IDConfig.GoogleToken.adminEmail
}
catch {
    Throw (Start-ScriptEnd -Message $_ -WriteError)
}
#endregion Google Authorization Token

#region Gather Data
#region Spreadsheet Data Staff
try {
    $data = Get-SourceDataGSheet -IDConfig $IDConfig -logFile $logFile -headers $headers

    foreach ($item in $data) {
        $item | Add-Member -MemberType NoteProperty -Name "PersonTypeGeneric" -Value "Staff"
    }
}
catch {
    Throw (Start-ScriptEnd -Message $_ -WriteError)
}
#endregion Spreadsheet Data Staff

#region Get Google Data
if ($IDConfig.Google.enabled -eq $true) {
    try {
        $googleData = Get-TargetDataGoogle -logFile $logFile -headers $headers -ErrorAction Stop

        $googleUsers = $googleData.Users
        $googleGroups = $googleData.Groups
        $googleOrgUnits = $googleData.OrgUnits
    }
    catch {
        Throw (Start-ScriptEnd -Message $_ -WriteError)
    }
}
#endregion Get Google Data

#region Get Data AD
if ($IDConfig.AD.enabled -eq $true) {
    try {
        $adData = Get-TargetDataAD -logFile $logFile -ErrorAction Stop

        $ADUsers = $adData.Users
        $ADGroups = $adData.Groups
        $ADOrgUnits = $adData.OrgUnits
    }
    catch {
        Throw (Start-ScriptEnd -Message $_ -WriteError)
    }
}
#endregion Get Data AD
#endregion Gather Data

#region Validate Data
#region Test Source Data
#Check to make sure required columns exist in the data
#Remove Users who do not have data in all required fields except for terminationDate
#Remove Users where the process field is false
try {
    $filteredData = Test-SourceData -SourceData $data
}
catch {
    Throw (Start-ScriptEnd -Message $_ -WriteError)
}

#endregion Test Source Data

#region Get Duplicate IDs
if ($IDConfig.Google.enabled -eq $true) {
    $duplicateGoogleUsers = Get-DuplicateIDsGoogle -SourceData $googleUsers
}

if ($IDConfig.AD.enabled -eq $true) {
    $duplicateADUsers = Get-DuplicateIDsAD -SourceData $ADUsers
}
#endregion Get Duplicate IDs
#endregion Validate Data

#region Data Modifcation
# Build the lookup tables once to make the search faster
if ($IDConfig.Google.enabled -eq $true) {
    $googleUsersLookupByID = @{}
    foreach ($gUser in $googleUsers) {
        foreach ($extId in $gUser.externalIDs) {
            $googleUsersLookupByID[$extId.value] = $gUser
        }
    }
}

if ($IDConfig.AD.enabled -eq $true) {
    $adUsersLookupByID = @{}
    foreach ($adUser in $ADUsers) {
        $adUsersLookupByID[$adUser.EmployeeID] = $adUser
    }
}

#Add additional data to the user objects
foreach ($item in $filteredData) {
    $item = Set-AdditionalUserDataBase -IDConfig $IDConfig -userObject $item -logFile $logFile

    if ($IDConfig.Google.enabled -eq $true) {
        $item = Set-AdditionalUserDataGoogle -userObject $item -googleUsers $googleUsersLookupByID -duplicateGoogleUsers $duplicateGoogleUsers -logFile $logFile
    }
    if ($IDConfig.AD.enabled -eq $true) {
        $item = Set-AdditionalUserDataAD -userObject $item -ADUsers $adUsersLookupByID -duplicateADUsers $duplicateADUsers -logFile $logFile
    }
}
#endregion Data Modifcation

#region Groups Not Processed
#AD Checks
if ($IDConfig.AD.enabled -eq $true) {
    if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
        $checkGroupsListAD = @()

        foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true}) {
            $checkGroupsListAD += $item.GroupsAutomatic

            if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {
                $checkGroupsListAD += ($item.ApplicationGroups -split ",").trim()
            }
            
            if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
                $checkGroupsListAD += ($item.EmailGroups -split ",").trim()
            }  
        }

        foreach ($item in $checkGroupsListAD | Select-Object -Unique | Sort-Object) {
            if ($item -notin $ADGroups) {
                Write-Log -Path $logFile -Message ("AD: Not Processing Group: $item - Does Not Exist") -WhatIfLogging $IDConfig.AD.enableGroupProcessingWhatIf
            }
        }
    }
}

#Google Checks
if ($IDConfig.Google.enabled -eq $true) {
    if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
        $checkGroupsListGoogle = @()

        foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true}) {
            $checkGroupsListGoogle += $item.GroupsAutomatic

            if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
                $checkGroupsListGoogle += ($item.EmailGroups -split ",").trim()
            }
        }

        foreach ($item in $checkGroupsListGoogle | Select-Object -Unique | Sort-Object) {
            if ($item -notin $googleGroups.name) {
                Write-Log -Path $logFile -Message ("Google: Not Processing Group: $item - Does Not Exist") -WhatIfLogging $IDConfig.AD.enableGroupProcessingWhatIf
            }
        }
    }
}

#endregion Groups Not Processed





#region Processing AD
#region AD OUs
if ($IDConfig.AD.enabled -eq $true) {
    #Check and Create OUs in AD
    #Manual and Top Level OUs to Check
    $OUCheckAD = @(
        $IDConfig.AD.userRootOU
        ("OU=Student," + $IDConfig.AD.userRootOU)
        ("OU=Staff," + $IDConfig.AD.userRootOU)
        ("OU=Trash," + $IDConfig.AD.userRootOU)
        ("OU=Student,OU=Trash," + $IDConfig.AD.userRootOU)
        ("OU=Staff,OU=Trash," + $IDConfig.AD.userRootOU)
    )

    #Add the OUs to check from the personTypeGeneric and personType Fields
    $OUCheckADAuto = @()
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and $_.ADCurrentUserID}) {
        $OUCheckADAuto += $item.ADOrganizationalUnit
        $OUCheckADAuto += $item.ADOrganizationalUnitTrash
    }

    #Combine the OUs together - this is done so that the base OUs are created first
    $OUCheckAD += $OUCheckADAuto | Sort-Object -Unique

    #Create Org Units that do not exist
    foreach ($item in $OUCheckAD | Sort-Object -Unique) {
        if ($item -notin $ADOrgUnits){
            try {
                Write-Log -Path $logFile -Message "AD: Creating Org Unit $item"
                if ($IDConfig.Debug.readOnly -eq $false) {
                    New-ADOrganizationalUnit -Name $item.split(",",2)[0].replace("OU=","") -Path $item.split(",",2)[1] -ErrorAction Stop
                }
            }
            catch {
                Write-Log -Path $logFile -Message "AD: Org Unit $item does not exist and could not be created. Please check RunAS user permisisons in AD" -Level Error
                Exit 1
            }
        }
    }
}
#endregion AD OUs

#region Deativate AD Users
if ($IDConfig.AD.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $false -and $_.ADCurrentUserEnabledStatus -eq $true}) {
        #Disable the account
        Write-Log -Path $logFile -Message ("AD: Disabling account for " + $item.PersonID)
        if ($IDConfig.Debug.readOnly -eq $false) {
            Set-ADUser -Identity $item.ADCurrentUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm) -Enabled $false
        }

        #Move the User to the Trash OU
        Write-Log -Path $logFile -Message  ("AD: Moving user to trash: " + $item.PersonID)
        if ($IDConfig.Debug.readOnly -eq $false) {
            Move-ADObject -Identity $item.ADCurrentUserID -TargetPath $item.ADOrganizationalUnitTrash
        }

        #Get all the groups and write that to the log
        if (-not [string]::IsNullOrEmpty($item.ADCurrentGroups)) {
            Write-Log -Path $logFile -Message ("AD: Current groups for " + $item.PersonID)
            Write-Log -Path $logFile -Message ($item.ADCurrentGroups -join ",")
    
            #Remove All Groups from the user
            if ($IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
                Write-Log -Path $logFile -Message  ("WhatIf AD: Removing groups for " + $item.PersonID)
            }
            
            if ($IDConfig.AD.enableGroupProcessingTrash -eq $true) {
                Write-Log -Path $logFile -Message  ("AD: Removing groups for " + $item.PersonID)
                if ($IDConfig.Debug.readOnly -eq $false) {
                    $item.ADCurrentGroups | Remove-ADGroupMember -Members $item.ADCurrentUserID -Confirm:$false
                }
            }
        } else {
            Write-Log -Path $logFile -Message ("AD: Current groups for " + $item.PersonID + " : NONE")
        }
    }
}
#endregion Deativate AD Users

#region Set AD EmployeeID
if ($IDConfig.AD.enabled -eq $true) {
    #Set Users employeeID if not set
    #If no user exists with the employee ID, try username
    #Username has to pair with the first name and last name
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and -not $_.ADCurrentUserID -and -not $_.ADDuplicateIDStatus}) {
        if ($item.personID -notin $ADUsers.employeeID){
            Write-Log -Path $logFile -Message ("AD: No user found with EmployeeID: " + $item.personID)
            
            if ($item.username -in $ADUsers.SamAccountName) {
                $ADUser = ($ADUsers | Where-Object {$_.SamAccountName -eq $item.username})

                if ($ADUser.Surname -eq $item.NameLast -and $ADUser.GivenName -eq $item.NameFirst) {
                    #Update the user account employeeID with the personID
                    Write-Log -Path $logFile -Message ("AD: Setting EmployeeID field for: " + $item.username + " - " + $item.personID)

                    if ($IDConfig.Debug.readOnly -eq $false) {
                        $ADUser | Set-ADUser -EmployeeID $item.PersonID -Division (Get-Date -format yyyy-MM-dd-HH:mm)

                        #Add the GUID to the data object
                        $item.ADCurrentUserID = $ADUser.ObjectGUID

                        #Add the Current AD Groups to the data object
                        $item.ADCurrentGroups = ($ADUser.MemberOf | Get-ADGroup | Select-Object -ExpandProperty Name)
                    }
                } else {
                    Write-Log -Path $logFile -Message ("AD: Username " + $item.username + " for " + $item.personID + " is already taken with a different name of " + $ADUser.GivenName + " " + $ADUser.Surname) -Level Error
                }
            } 
        }
        if ($ADUser) {Remove-Variable ADUser}
    }
}
#endregion Set AD EmployeeID

#region Update AD Users
if ($IDConfig.AD.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and $_.ADCurrentUserID}) {
        $ADUser = $ADUsers | Where-Object {$_.employeeID -eq $item.personID}

        $itemUpdateSplat = @{}

        if ($ADUser.SamAccountName -ne $item.Username) {
            try {
                Get-ADUser -Identity $item.UPN -ErrorAction Stop | Out-Null

                Write-Log -Path $logFile -Message ("AD: Another user account has the username of " + $item.Username + ". Terminating updating person: " + $item.PersonID) -Level Error

                continue
            }
            catch {
                if ($_.CategoryInfo.Reason -eq 'ADIdentityNotFoundException') {
                    Write-Log -Path $logFile -Message ("AD: Setting New Username for " + $item.PersonID + ". Old username is " + $ADUser.SamAccountName)

                    $itemUpdateSplat["SamAccountName"] = $item.Username
                    $itemUpdateSplat["UserPrincipalName"] = $item.UPN
                }
            }
        }

        if ($ADUser.Surname -ne $item.NameLast) {
            $itemUpdateSplat["Surname"] = $item.NameLast.trim()
        }

        if ($ADUser.GivenName -ne $item.NameFirst) {
            $itemUpdateSplat["GivenName"] = $item.NameFirst.trim()
        }

        if ($ADUser.DisplayName -ne ($item.NameFirst + " " + $item.NameLast)) {
            $itemUpdateSplat["DisplayName"] = ($item.NameFirst + " " + $item.NameLast)
        }

        if ($ADUser.physicalDeliveryOfficeName -ne $item.Building) {
            $itemUpdateSplat["Office"] = $item.Building
        }

        if ($ADUser.title -ne $item.JobTitle) {
            $itemUpdateSplat["Title"] = $item.JobTitle
        }

        if ($ADUser.company -ne $item.company) {
            $itemUpdateSplat["Company"] = $item.company
        }

        if ($ADUser.Enabled -ne $true) {
            $itemUpdateSplat["Enabled"] = $true
        }

        if ($ADUser.EmployeeType -ne $item.PersonTypeID -or $ADUser.extensionAttribute1 -ne $item.PersonTypeID) {
            $itemUpdateSplat["Replace"] = @{ 'EmployeeType' = ($item.PersonTypeID) ; 'extensionAttribute1' = ($item.PersonTypeID)}
        }

        if ($itemUpdateSplat.Count -gt 0) {
            $itemUpdateSplat["Identity"] = $item.ADCurrentUserID
            $itemUpdateSplat["Division"] = (Get-Date -format yyyy-MM-dd-HH:mm)

            Write-Log -Path $logFile -Message ("AD: Updating Information for: " + $item.UPN + " - " + $item.personID)
            Write-Log -Path $logFile -Message ($itemUpdateSplat | ConvertTo-Json -Compress)

            if ($IDConfig.Debug.readOnly -eq $false) {
                Set-ADUser @itemUpdateSplat
            }
        }

        if ($ADUser.CN -ne ($item.NameFirst + " " + $item.NameLast + " " + $item.PersonID)) {
            Write-Log -Path $logFile -Message ("AD: Canonical Name does not match for " + $item.PersonID + ". Updating Canonical Name")

            if ($IDConfig.Debug.readOnly -eq $false) {
                Set-ADUser -Identity $item.ADCurrentUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                Rename-ADObject -Identity $item.ADCurrentUserID -NewName ($item.NameFirst + " " + $item.NameLast + " " + $item.PersonID)
            }
        }

        if ($ADUser.DistinguishedName.split(",",2)[1] -ne $item.ADOrganizationalUnit) {
            Write-Log -Path $logFile -Message ("AD: Organization Unit does not match for " + $item.PersonID + ". Moving User to: " + $item.ADorganizationalUnit)

            if ($IDConfig.Debug.readOnly -eq $false) {
                Set-ADUser -Identity $item.ADCurrentUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                Move-ADObject -Identity $item.ADCurrentUserID -TargetPath $item.ADorganizationalUnit
            }
        }

        if ($ADUser) {Remove-Variable ADUser}
    }
}
#endregion Update AD Users

#region Create AD Users
if ($IDConfig.AD.enabled -eq $true) {
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and -not $_.ADCurrentUserID -and $_.UPN -notin $ADUsers.UserPrincipalName}) {
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
            Division              = (Get-Date -format yyyy-MM-dd-HH:mm)
            OtherAttributes       = @{ 'EmployeeType' = $item.PersonTypeID ; 'extensionAttribute1' = ($item.PersonTypeID)}
            Enabled               = $true
            ChangePasswordAtLogon = $item.ADChangePasswordAtLogon
            PasswordNeverExpires  = $false
            PassThru              = $true
            ErrorAction           = "Stop"
        }

        Write-Log -Path $logFile -Message ("AD: Creating User " + $item.NameFirst + " " + $item.NameLast + " " + $item.PersonID)
        Write-Log -Path $logFile -Message ("AD: Createing User - Information for: " + $item.UPN + " - " + $item.personID)
        Write-Log -Path $logFile -Message ($NewUserParams | ConvertTo-Json -Compress)

        try {
            #Add Password to the Params so it doesn't show up in the logs
            $NewUserParams["AccountPassword"] = (ConvertTo-SecureString ($item.ADPassPrefix + $item.Word) -AsPlainText -Force)

            # Create the new AD user with splatting
            if ($IDConfig.Debug.readOnly -eq $false) {
                $newUser = New-ADUser @NewUserParams

                #Add the GUID to the data object
                $item.ADCurrentUserID = $newUser.ObjectGUID
            }
        }
        catch {
            Write-Log -Path $logFile -Message "$($_)" -Level Error
        }
    }
}
#endregion Create AD Users

#region Process AD Groups
if ($IDConfig.AD.enabled -eq $true) {
    if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
        foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and $_.ADCurrentUserID}) {
            $proposedGroupList = @()

            if ($item.GroupsAutomatic) {
                $proposedGroupList += $item.GroupsAutomatic
            }

            if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {
                $proposedGroupList += ($item.ApplicationGroups -split ",").trim()
            }

            if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
                $proposedGroupList += ($item.EmailGroups -split ",").trim()
            }

            #Filter out duplicates
            $proposedGroupList = $proposedGroupList | Select-Object -Unique

            #Add groups from Users - Only run if enableGroupProcessing is Enabled
            foreach ($groupAdd in $proposedGroupList | Where-Object {$_ -in $ADGroups}) {
                if ($groupAdd -notin $item.ADCurrentGroups) {
                    Write-Log -Path $logFile -Message "AD: Adding Group: $groupAdd to $($item.personID) $($item.NameFirst) $($item.NameLast)" -WhatIfLogging $IDConfig.AD.enableGroupProcessingWhatIf

                    if ($IDConfig.AD.enableGroupProcessing -eq $true) {
                        if ($IDConfig.Debug.readOnly -eq $false) {
                            Add-ADPrincipalGroupMembership -Identity $item.ADCurrentUserID -MemberOf $groupAdd
                        }
                    }
                }
            }

            #Remove groups from Users - Only run if enableGroupProcessingRemove is Enabled
            foreach ($groupCurrent in $item.ADCurrentGroups) {
                if ($groupCurrent -notin $proposedGroupList) {
                    Write-Log -Path $logFile -Message "AD: Removing Extra Group: $groupCurrent from $($item.personID) $($item.NameFirst) $($item.NameLast)" -WhatIfLogging $IDConfig.AD.enableGroupProcessingWhatIf

                    if ($IDConfig.AD.enableGroupProcessingRemove -eq $true) {
                        if ($IDConfig.Debug.readOnly -eq $false) {
                            Remove-ADGroupMember -Identity $groupCurrent -Members $item.ADCurrentUserID -Confirm:$false
                        }
                    }
                }
            }
        }
    }
}
#endregion Process AD Groups

#region Report Non Data Users
if ($IDConfig.AD.enabled -eq $true) {
    #Get all AD Users to Find Users who are not in the data file.
    $allADUsers = @()

    foreach ($item in $OUCheckAD | Where-Object {$_ -notlike "*,OU=Trash,*"}) {
        $allADUsers += Get-ADUser -Filter * -SearchBase $item -Properties $userPropertyAD -searchscope 1
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
    foreach ($item in $OUCheckGoogle | Where-Object {$_ -notin $googleOrgUnits.orgUnitPath}) {
        Write-Log -Path $logFile -Message "Google: Creating org unit: $($item)"
        if ($IDConfig.Debug.readOnly -eq $false) {
            New-GoogleOrganizationalUnit -NewOrgUnitFullPath $item -tokenInformation $headers
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
        
        if ($item.UPN -in $googleUsers.primaryEmail) {
            $googleUser = ($googleUsers | Where-Object {$_.primaryEmail -eq $item.UPN})

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
        $googleUser = $googleUsers | Where-Object {$_.externalIDs.value -eq $item.personID}

        $itemUpdateSplat = @{}

        if ($googleUser.primaryEmail -ne $item.UPN) {
            if ($item.UPN -notin ($googleUsers.emails | Select-Object -ExpandProperty address)) {
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
    foreach ($item in $filteredData | Where-Object {$_.IDBActive -eq $true -and -not $_.GoogleCurrentUserID -and $_.UPN -notin $googleUsers.primaryEmail}) {
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
            foreach ($group in $proposedGroupList | Where-Object {$_ -in $googleGroups.name}) {
                if (("$group@$($IDConfig.Google.GroupPrimaryDomainName)") -notin $item.GoogleCurrentGroups) {
                    Write-Log -Path $logFile -Message ("Google: Adding Group: $group to " + $item.personID) -WhatIfLogging $IDConfig.Google.enableGroupProcessingWhatIf

                    if ($IDConfig.Google.enableGroupProcessing -eq $true) {
                        if ($IDConfig.Debug.readOnly -eq $false) {
                            Update-GoogleGroupMembers -GroupEmail ($googleGroups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add" -TokenInformation $headers
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


Write-Log -Message "######## End of Script Run: $logDate ########" -Path $logFile