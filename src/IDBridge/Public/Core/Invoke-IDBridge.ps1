<#
.SYNOPSIS
Top-level orchestrator: provision and synchronize AD and Google Workspace accounts from source data.

.DESCRIPTION
Entry point for an IDBridge run. Calls Initialize-IDBridge, applies the runtime switch
overrides, then runs the ordered pipeline: gather source data from the configured plugins, read
current AD/Google state, enrich and de-duplicate the source records, apply override rows, match
person IDs to existing accounts, and compute every change list (org units, deactivations,
updates/renames/moves, creates, and group membership) read-only. Before any writes it runs the
change-volume safety guard (ChangeThreshold). It then executes the AD and Google changes only
when the directory is enabled and Debug.readOnly is $false, exports the staff CSV, and (in the
finally block) pushes the run log to a Google Sheet when configured. Per-user write errors are
logged and skipped; startup/OU-creation failures and a tripped change threshold abort the run.

.PARAMETER RootPath
Base directory for Config/Auth/Logs/Exports/Plugins/Data. Defaults to C:\IDBridge.

.PARAMETER ReadOnly
Override Debug.readOnly for this run. When set, every change list is computed but nothing is written.

.PARAMETER TestRun
Override Debug.testRun; plugins process a small subset for faster iteration.

.PARAMETER SkipADCheck
Override Debug.skipADCheck; do not throw if the ActiveDirectory module fails to import.

.PARAMETER TraceLogging
Override Debug.TraceLogging; emit Trace-level logging.

.PARAMETER SkipAD
Disable all AD processing (and AD group processing) for this run.

.PARAMETER SkipGoogle
Disable all Google processing (and Google group processing) for this run.

.PARAMETER SkipChangeThreshold
Bypass the change-volume safety guard (ChangeThreshold) for this run.

.OUTPUTS
None. Side effects: AD/Google mutations (unless ReadOnly), the UserList-Staff.csv export, and log output.

.EXAMPLE
Invoke-IDBridge -ReadOnly -TraceLogging

.EXAMPLE
Invoke-IDBridge -RootPath 'C:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Invoke-IDBridge {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge",

        [switch]$ReadOnly,
        [switch]$TestRun,
        [switch]$SkipADCheck,
        [switch]$TraceLogging,
        [switch]$SkipAD,
        [switch]$SkipGoogle,
        [switch]$SkipChangeThreshold
    )

    try{
        #region Import Configuration
        try { Initialize-IDBridge -RootPath $RootPath } catch { Throw }

        try { $IDConfig = Get-IDBridgeConfig } catch { Throw }
        #endregion Import Configuration

        

        #region Apply Runtime Overrides
        if ($PSBoundParameters.ContainsKey('ReadOnly'))       { $IDConfig.Debug.readOnly       = [bool]$ReadOnly }
        if ($PSBoundParameters.ContainsKey('TestRun'))        { $IDConfig.Debug.testRun        = [bool]$TestRun }
        if ($PSBoundParameters.ContainsKey('SkipADCheck'))    { $IDConfig.Debug.skipADCheck    = [bool]$SkipADCheck }
        if ($PSBoundParameters.ContainsKey('TraceLogging'))   { $IDConfig.Debug.TraceLogging   = [bool]$TraceLogging }
        if ($SkipAD)      { $IDConfig.AD.enabled     = $false; $IDConfig.AD.enableGroupProcessing     = $false }
        if ($SkipGoogle)  { $IDConfig.Google.enabled = $false; $IDConfig.Google.enableGroupProcessing = $false }
        if ($SkipChangeThreshold -and $IDConfig.ContainsKey('ChangeThreshold')) { $IDConfig.ChangeThreshold.Enabled = $false }

        foreach ($key in $PSBoundParameters.Keys | Where-Object { $_ -ne 'RootPath' }) {
            Write-Log -Message "OVERRIDE: $key = $($PSBoundParameters[$key])" -Level Info
        }
        #endregion Apply Runtime Overrides




        #region Plugins
        try {
            $plugins = Invoke-SourcePlugins
            
            $sourceData = $plugins.SourceData
            $overrideData = $plugins.OverrideData
        }
        catch { Throw }
        #endregion Plugins




        #region Get Google Data
        if ($IDConfig.Google.enabled -eq $true) {
            try {
                $googleData = Get-TargetDataGoogle -ErrorAction Stop
            }
            catch { Throw }
        }
        #endregion Get Google Data




        #region Get Data AD
        if ($IDConfig.AD.enabled -eq $true) {
            try {
                $adData = Get-TargetDataAD -ErrorAction Stop
            }
            catch { Throw }
        }
        #endregion Get Data AD




        #region Target Data Preparation
        if ($IDConfig.AD.enabled -eq $true) {
            $sourceData = Add-TargetDataAD -SourceData $sourceData -ADData $adData
        }

        if ($IDConfig.Google.enabled -eq $true) {
            $sourceData = Add-TargetDataGoogle -SourceData $sourceData -GoogleData $googleData
        }
        #endregion Target Data Preparation




        #region Remove Duplicate IDs
        $sourceData = Remove-IDBridgeDuplicateID -SourceData $sourceData
        #endregion Remove Duplicate IDs




        #region Process Override Data
        $sourceData = Merge-IDBridgeOverrideData -SourceData $sourceData -OverrideData $overrideData
        #endregion Process Override Data




        #region Groups Not Processed
        if ($IDConfig.Debug.TraceLogging -eq $true) {
            #AD Checks
            if ($IDConfig.AD.enabled -eq $true -and ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true)) {
                Write-Log -Message "AD: Checking for Groups Proposed for Processing that do not exist in the Target Data." -Level Trace
                Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $adData.Groups
            }

            #Google Checks
            if ($IDConfig.Google.enabled -eq $true -and ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true)) {
                Write-Log -Message "Google: Checking for Groups Proposed for Processing that do not exist in the Target Data." -Level Trace
                Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $googleData.Groups.name
            }
        }
        #endregion Groups Not Processed




        #region Match PersonIDs
        if ($IDConfig.AD.enabled -eq $true) {
            #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
            $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $sourceData -CurrentADUsers $adData.Users

            foreach ($item in $SourceData | Where-Object { $ADUsersToSetEmployeeID.ContainsKey($_.personID) }) {
                $matchAD = $ADUsersToSetEmployeeID[$item.personID]
                Write-Log -Message ("AD: Matched $($matchAD.User.UserPrincipalName) with EmployeeID: $($item.personID).")
                $item | Add-Member -MemberType NoteProperty -Name 'ADObject' -Value $matchAD.User -Force
                $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserID' -Value $matchAD.ID -Force
                $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentGroups' -Value $matchAD.Groups -Force
                $item | Add-Member -MemberType NoteProperty -Name 'ADCurrentUserEnabledStatus' -Value $matchAD.EnabledStatus -Force
                $ADData.LookupByID[$item.personID] = $matchAD.User
            }
        }

        if ($IDConfig.Google.enabled -eq $true) {
            #Update filteredData list and GoogleLookupByID Table with Google User Info if No EmployeeID is Set and an existing user is found that matches
            $GoogleUsersToSetEmployeeID = Get-GoogleUsersToSetEmployeeID -UserList $sourceData -GoogleUsers $googleData.Users

            foreach ($item in $SourceData | Where-Object { $GoogleUsersToSetEmployeeID.ContainsKey($_.personID) }) {
                $matchGoogle = $GoogleUsersToSetEmployeeID[$item.personID]
                Write-Log -Message ("Google: Matched $($matchGoogle.User.primaryEmail) with EmployeeID: $($item.personID).")
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleObject' -Value $matchGoogle.User -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserID' -Value $matchGoogle.ID -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentGroups' -Value $matchGoogle.Groups -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserSuspendedStatus' -Value $matchGoogle.SuspendedStatus -Force
                $googleData.LookupByID[$item.personID] = $matchGoogle.User
            }
        }
        #endregion Match PersonIDs




        #region AD Processing Lists
        if ($IDConfig.AD.enabled -eq $true) {
            #Org Units to Create
            $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $sourceData -UserRootOU $IDConfig.AD.userRootOU -CurrentOrgUnits $adData.OrgUnits
            #Users to Deactivate
            $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $sourceData
            #Users to Update
            $ADUsersToUpdate = Get-ADUsersToUpdate -UserList $sourceData -LookupByID $adData.LookupByID
            #Users to Create
            $ADUsersToCreate = Get-ADUsersToCreate -UserList $sourceData -CurrentADUsers $adData.Users
            #Groups to Update
            if ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
                $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $sourceData -CurrentADGroups $adData.Groups
            }
        }
        #endregion AD Processing Lists




        #region Google Processing Lists
        if ($IDConfig.Google.enabled -eq $true) {
            #Org Units to Create
            $GoogleOrgUnitsForProcessing = Get-GoogleOrgUnitsForProcessing -UserList $sourceData -UserRootOU $IDConfig.Google.userRootOU -CurrentOrgUnits $googleData.OrgUnits.orgUnitPath
            #Users to Update
            $GoogleUsersToUpdate = Get-GoogleUsersToUpdate -UserList $sourceData -LookupByID $googleData.LookupByID -GoogleUsers $googleData.Users
            #Users to Deactivate
            $GoogleUsersToDeactivate = Get-GoogleUsersToDeactivate -UserList $sourceData
            #Users to Create
            $GoogleUsersToCreate = Get-GoogleUsersToCreate -UserList $sourceData -GoogleUsers $googleData.Users
            #Groups to Update
            if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
                $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName
            }
        }
        #endregion Google Processing Lists




        #region Change Threshold Safety Check
        # Guard against a broken source feed mass-changing a directory: if the proposed lifecycle
        # changes exceed a percentage of the existing managed (root-OU) population, abort before any
        # writes. Bypassed by ChangeThreshold.Enabled = $false in config or the -SkipChangeThreshold switch.
        if ($IDConfig.ContainsKey('ChangeThreshold') -and $IDConfig.ChangeThreshold.Enabled -eq $true) {
            $thresholdResults = [System.Collections.Generic.List[object]]::new()

            if ($IDConfig.AD.enabled -eq $true) {
                $adManagedPopulation = @($adData.Users | Where-Object { $_.DistinguishedName -like "*,$($IDConfig.AD.userRootOU)" }).Count
                $adChangeCount = @($ADUsersToCreate).Count + @($ADUsersToDeactivate).Count +
                    @($ADUsersToUpdate.UpdateList).Count + @($ADUsersToUpdate.RenameList).Count + @($ADUsersToUpdate.MoveList).Count
                $thresholdResults.Add( (Test-IDBridgeChangeThreshold -Directory 'AD' -ChangeCount $adChangeCount -PopulationCount $adManagedPopulation -ThresholdPercent $IDConfig.ChangeThreshold.Percentage) )
            }

            if ($IDConfig.Google.enabled -eq $true) {
                $googleManagedPopulation = @($googleData.Users | Where-Object { $_.orgUnitPath -eq $IDConfig.Google.userRootOU -or $_.orgUnitPath -like "$($IDConfig.Google.userRootOU)/*" }).Count
                $googleChangeCount = @($GoogleUsersToCreate).Count + @($GoogleUsersToDeactivate).Count + @($GoogleUsersToUpdate).Count
                $thresholdResults.Add( (Test-IDBridgeChangeThreshold -Directory 'Google' -ChangeCount $googleChangeCount -PopulationCount $googleManagedPopulation -ThresholdPercent $IDConfig.ChangeThreshold.Percentage) )
            }

            $breaches = @($thresholdResults | Where-Object { $_.Exceeded })
            if ($breaches.Count -gt 0) {
                $breachSummary = ($breaches | ForEach-Object { "$($_.Directory) $($_.Percent)%" }) -join ', '
                Write-Log -Message "Change threshold exceeded ($breachSummary > $($IDConfig.ChangeThreshold.Percentage)%). Aborting run before any writes. Set ChangeThreshold.Enabled = `$false or run with -SkipChangeThreshold to override." -Level Error
                Throw "Change threshold exceeded: $breachSummary (limit $($IDConfig.ChangeThreshold.Percentage)%)."
            }
        }
        #endregion Change Threshold Safety Check




        #region Process AD Changes
        if ($IDConfig.AD.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
            #Create Org Units
            foreach ($item in $ADOrgUnitsForProcessing | Sort-Object -Unique) {
                try {
                    New-IDBridgeADOrgUnit -OrgUnit $item
                }
                catch {
                    Write-Log -Message "AD: Error Creating Org Unit. Please check RunAS user permisisons in AD or Detailed Error for more information" -Level Error
                    Throw
                }
            }

            #Disable Users
            foreach ($item in $ADUsersToDeactivate) {
                try {
                    Disable-IDBridgeADUser -User $item -GroupRemovalProcessingStatus $IDConfig.AD.enableGroupProcessingTrash
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }


            #Update Users
            foreach ($item in $ADUsersToUpdate.UpdateList) {
                try {
                    Write-Log -Message "AD: Updating User: $($item.CN) Properties: $($item.splat | ConvertTo-Json -Compress)"
                    $itemSplat = $null
                    $itemSplat = $item.splat
                    Set-ADUser @itemSplat -ErrorAction Stop
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Rename Users
            foreach ($item in $ADUsersToUpdate.RenameList) {
                try {
                    Write-Log -Message "AD: Renaming User: $($item.CN) to $($item.NewName)"
                    Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                    Rename-ADObject -Identity $item.ADUserID -NewName $item.NewName -ErrorAction Stop
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Move Users
            foreach ($item in $ADUsersToUpdate.MoveList) {
                try {
                    Write-Log -Message "AD: Moving User: $($item.CN) to $($item.NewOrgUnit)"
                    Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                    Move-ADObject -Identity $item.ADUserID -TargetPath $item.NewOrgUnit -ErrorAction Stop
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Create Users
            foreach ($item in $ADUsersToCreate) {
                try {
                    Write-Log -Message "AD: Creating User: $($item.PersonID) Properties: $($item.splat | ConvertTo-Json -Compress)"
                    $itemSplat = $null
                    $itemSplat = $item.splat
                    $newUser = New-ADUser @itemSplat -ErrorAction Stop

                    #Add the GUID to the data object
                    ($sourceData | Where-Object UPN -eq $itemSplat.UserPrincipalName).ADCurrentUserID = $newUser.ObjectGUID

                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Process Group Membership
            if ($IDConfig.AD.enableGroupProcessing -eq $true) {
                #If there are users to create, refresh the group membership updates to ensure any new users are included in the group processing
                if ($ADUsersToCreate.Count -gt 0) {
                    #Refresh AD User Groups to Update List to include newly created users
                    Write-Log -Message "AD: Refreshing User Groups to Update List to include newly created users." -Level Trace

                    $ADUserGroupsToUpdate = Get-ADUserGroupsToUpdate -UserList $sourceData -CurrentADGroups $adData.Groups
                }
                #Process Group Membership Add
                foreach ($item in $ADUserGroupsToUpdate.Add) {
                    foreach ($group in $item.Groups) {
                        try {
                            Write-Log -Message "AD: Adding Group: $group to $($item.PersonID)"
                            Add-ADPrincipalGroupMembership -Identity $item.ADCurrentUserID -MemberOf $group
                        }
                        catch {
                            Write-Log -Message $_ -Level Error
                        }
                    }
                }

                #Process Group Membership Remove
                if ($IDConfig.AD.enableGroupProcessingRemove -eq $true) {
                    foreach ($item in $ADUserGroupsToUpdate.Remove) {
                        foreach ($group in $item.Groups) {
                            try {
                                Write-Log -Message "AD: Removing Group: $group from $($item.PersonID)"
                                Remove-ADGroupMember -Identity $group -Members $item.ADCurrentUserID -Confirm:$false
                            }
                            catch {
                                Write-Log -Message $_ -Level Error
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
                    New-IDBridgeGoogleOrgUnit -OrgUnit $item 
                }
                catch {
                    Write-Log -Message "Google: Error Creating Org Unit. Please check API permissions in Google or Detailed Error for more information" -Level Error
                    Throw
                }
            }

            #Disable Users
            foreach ($item in $GoogleUsersToDeactivate) {
                try {
                    Write-Log -Message ("Google: Disabling account for " + $item.UPN)
                    Write-Log -Message  ("Google: Moving account to trash: " + $item.UPN)
                    Update-IDBridgeGoogleUser -GoogleUserID $item.GoogleCurrentUserID -OrgUnitPath $item.GoogleOrganizationalUnitTrash -Suspended 'true'
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }

                if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingTrash -eq $true) {
                    foreach ($group in $item.GoogleCurrentGroups) {
                        try {
                            Write-Log -Message ("Google: Removing Group: $group from " + $item.personID)
                            Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove"
                        }
                        catch {
                            Write-Log -Message $_ -Level Error
                        }
                    }
                }
            }

            #Update, Move, Rename Users
            foreach ($item in $GoogleUsersToUpdate) {
                try {
                    Write-Log -Message "Google: Updating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
                    $itemSplat = $null
                    $itemSplat = $item.splat
                    Update-IDBridgeGoogleUser @itemSplat
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Create Users
            foreach ($item in $GoogleUsersToCreate) {
                try {
                    Write-Log -Message "Google: Creating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
                    $itemSplat = $null
                    $itemSplat = $item.splat

                    $newUserResponse = New-IDBridgeGoogleUser @itemSplat -ErrorAction Stop

                    #Add the Google ID to the data object
                    ($sourceData | Where-Object UPN -eq $itemSplat.PrimaryEmail).GoogleCurrentUserID = $newUserResponse.ID
                }
                catch {
                    Write-Log -Message $_ -Level Error
                }
            }

            #Process Group Membership
            if ($IDConfig.Google.enableGroupProcessing -eq $true) {
                if ($GoogleUsersToCreate.Count -gt 0) {
                    #Refresh Google User Groups to Update List to include newly created users
                    Write-Log -Message "Google: Refreshing User Groups to Update List to include newly created users." -Level Trace
                    
                    $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups -GroupPrimaryDomainName $IDConfig.Google.GroupPrimaryDomainName
                }

                #Process Group Membership Add
                foreach ($item in $GoogleUserGroupsToUpdate.Add) {
                    foreach ($group in $item.Groups) {
                        try {
                            Write-Log -Message "Google: Adding Group: $group to $($item.PersonID)"
                            Update-GoogleGroupMembers -GroupEmail ($googleData.Groups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add"
                        }
                        catch {
                            Write-Log -Message $_ -Level Error
                        }
                    }
                }

                #Process Group Membership Remove
                if ($IDConfig.Google.enableGroupProcessingRemove -eq $true) {
                    foreach ($item in $GoogleUserGroupsToUpdate.Remove) {
                        foreach ($group in $item.Groups) {
                            try {
                                Write-Log -Message "Google: Removing Group: $group from $($item.PersonID)"
                                Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove"
                            }
                            catch {
                                Write-Log -Message $_ -Level Error
                            }
                        }
                    }
                }
            }
        }
        #endregion Process Google Changes




        #region Export User Staff List
        $sourceData | Where-Object {$_.PersonTypeID -ne "1"} | Export-Csv -Path "$($IDConfig.Paths.ExportsRoot)\UserList-Staff.csv" -NoTypeInformation -Force
        #endregion Export User Staff List

    } catch {
        Write-Log -Message "Invoke-IDBridge Failed" -Level Error
        Write-Log -Message $_ -Level Error
    } finally {
        Write-Log -Message "######## End of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########"

        if ($IDConfig.Logging.GoogleSheetLoggingEnabled) {
            #Push-LogsToSheet -logfile $IDConfig.Paths.LogFile -spreadsheetId $IDConfig.Logging.SheetID -sheetName 'Logs' -hasHeader
            Push-LogsToSheet -spreadsheetId $IDConfig.Logging.SheetID -sheetName 'Logs'       
        }

    }
}