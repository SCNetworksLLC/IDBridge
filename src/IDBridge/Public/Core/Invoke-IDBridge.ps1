<#
.SYNOPSIS
Top-level orchestrator: provision and synchronize AD and Google Workspace accounts from source data.

.DESCRIPTION
Entry point for an IDBridge run. Calls Initialize-IDBridge, applies the runtime switch
overrides, then runs the ordered pipeline: the shared gather phase (Get-IDBridgePipelineData -
Google auth, source plugins, current AD/Google state, enrichment, de-duplication, override
rows), matches person IDs to existing accounts, and computes every change list (org units,
deactivations, updates/renames/moves, creates, and group membership) read-only. Before any
writes it runs the change-volume safety guard (ChangeThreshold). It then executes the AD and
Google changes only when the directory is enabled and Debug.readOnly is $false, and (in the
finally block) sends usage telemetry, runs the configured PostRun plugins with the RunResult
object (user list CSV exports live in the Invoke-PluginPostRunExport plugin), and pushes the
run log to a Google Sheet when configured. Per-user write errors are
logged and skipped; startup/OU-creation failures and a tripped change threshold abort the run.

Only one run per RootPath executes at a time: a machine-wide mutex is taken before
initialization and a second run aborts immediately, telling you a run is already in
progress. ReadOnly and Preview runs take the same lock — they still write the shared log
file and the Data state files, and a preview racing a live run would show half-applied
state. The lock is process-bound, so it can never go stale: the OS releases it if a run
dies holding it (including Task Scheduler's execution time limit kill).

With -Preview the run stops after the plan phase and emits the proposed changes as flat row
objects (Directory, Action, PersonID, Name, Account, Building, OrgUnit, Password, Changes)
for review with Format-Table / Where-Object / Out-GridView - no CSV export needed. Preview
forces ReadOnly and stays quiet: no telemetry, no PostRun plugins, no Google Sheet log push,
and a tripped change threshold logs a warning instead of aborting (so the changes that would
trip it can be reviewed). Passwords for pending creates are decoded into the Password column
only with -ShowPasswords - Keysmith passphrases are deterministic, so the previewed password
is the one the real run will set.

.PARAMETER RootPath
Base directory for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.

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

.PARAMETER DisableTelemetry
Disable usage telemetry for this run (overrides Telemetry.Tier). See PRIVACY.md.

.PARAMETER Preview
Review mode: forces ReadOnly, computes every change list, and emits the proposed changes as
flat row objects instead of applying anything. Quiet - skips telemetry, PostRun plugins, and
the Google Sheet log push; a tripped change threshold warns instead of aborting.

.PARAMETER ShowPasswords
With -Preview, decode the pending creates' passwords into the Password column. The values are
emitted to the pipeline only - never logged. No effect without -Preview.

.OUTPUTS
None, unless -Preview: then the proposed change rows
(@{ Directory; Action; PersonID; Name; Account; Building; OrgUnit; Password; Changes }).
Side effects: AD/Google mutations (unless ReadOnly), PostRun plugin output, and log output.

.EXAMPLE
Invoke-IDBridge -ReadOnly -TraceLogging

.EXAMPLE
Invoke-IDBridge -RootPath 'C:\IDBridge'

.EXAMPLE
Invoke-IDBridge -Preview | Format-Table

.EXAMPLE
Invoke-IDBridge -Preview -ShowPasswords | Where-Object Action -eq 'Create' | Format-Table

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-21
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
        [switch]$SkipChangeThreshold,
        [switch]$DisableTelemetry,
        [switch]$Preview,
        [switch]$ShowPasswords
    )

    $runStart = Get-Date

    #region Single-Run Lock
    # One run per root at a time, machine-wide ('Global\' spans the console and the scheduled
    # task's session 0). Taken BEFORE Initialize-IDBridge so nothing shared - the log file
    # included, which initialization already writes - is touched while another run is in
    # flight. ReadOnly/Preview runs hold the lock too: they share the log and Data state
    # files, and a preview racing a live run would show half-applied state. A mutex (not a
    # lock file) so the OS releases it if a run dies holding it - it can never go stale.
    $runMutexName = 'Global\IDBridge-' + ($RootPath -replace '[^A-Za-z0-9]', '-')
    $runMutex = $null
    $runMutexHeld = $false
    try {
        $runMutex = [System.Threading.Mutex]::new($false, $runMutexName)
        try { $runMutexHeld = $runMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $runMutexHeld = $true }   #previous holder died mid-run; the lock is ours
    }
    catch [System.UnauthorizedAccessException] { }   #held by another account's run (e.g. the gMSA task) - not acquirable, so busy
    if (-not $runMutexHeld) {
        if ($runMutex) { $runMutex.Dispose() }
        Throw "Another IDBridge run against '$RootPath' is already in progress (ReadOnly and Preview runs hold the run lock too). Try again when it finishes."
    }
    #endregion Single-Run Lock

    try{
        #region Import Configuration
        #-SkipADCheck/-SkipAD are forwarded so they land before the AD module import;
        #the remaining switch overrides are applied after initialization below
        $initializeSplat = @{ RootPath = $RootPath }
        if ($SkipADCheck) { $initializeSplat.SkipADCheck = $true }
        if ($SkipAD)      { $initializeSplat.SkipAD = $true }
        try { Initialize-IDBridge @initializeSplat } catch { Throw }

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
        if ($DisableTelemetry) { $IDConfig.Telemetry = @{ Tier = 'Off' } }
        #Preview computes everything and writes nothing - the apply phase is gated on readOnly
        if ($Preview) { $IDConfig.Debug.readOnly = $true }

        foreach ($key in $PSBoundParameters.Keys | Where-Object { $_ -ne 'RootPath' }) {
            Write-Log -Message "OVERRIDE: $key = $($PSBoundParameters[$key])" -Level Info
        }
        #endregion Apply Runtime Overrides




        #region Update Check
        # Notify-only: a newer gallery release logs a warning, nothing is ever auto-installed.
        # Fully self-contained - offline or gallery-blocked environments can never affect the run.
        try { Test-IDBridgeUpdateAvailable | Out-Null } catch { Write-Log -Message "Update check: Skipped ($($_.Exception.GetType().Name))." -Level Trace }
        #endregion Update Check




        Write-Log -Message "######## Phase: Gather Source & Directory Data ########"

        #region Gather Source & Directory Data
        # Shared with Approve-IDBridgeNameMismatch: Google auth (acquired here, not in
        # Initialize-IDBridge, so setup sessions initialize cleanly before the key secret
        # exists), source plugins, AD/Google target data, enrichment, dedupe, override merge.
        try {
            $pipelineData = Get-IDBridgePipelineData

            $sourceData = $pipelineData.SourceData
            $adData     = $pipelineData.ADData
            $googleData = $pipelineData.GoogleData
        }
        catch { Throw }
        #endregion Gather Source & Directory Data




        #region Groups Not Processed
        if ($IDConfig.Debug.TraceLogging -eq $true) {
            #AD Checks
            if ($IDConfig.AD.enabled -eq $true -and ($IDConfig.AD.enableGroupProcessing -eq $true -or $IDConfig.AD.enableGroupProcessingWhatIf -eq $true)) {
                Write-Log -Message "AD: Checking for Groups Proposed for Processing that do not exist in the Target Data." -Level Trace
                Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $adData.Groups -Directory 'AD'
            }

            #Google Checks
            if ($IDConfig.Google.enabled -eq $true -and ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true)) {
                Write-Log -Message "Google: Checking for Groups Proposed for Processing that do not exist in the Target Data." -Level Trace
                Show-GroupsNotProcessed -ProposedGroups $sourceData.GroupsProposed -TargetGroups $googleData.Groups.name -Directory 'Google'
            }
        }
        #endregion Groups Not Processed




        #region Match PersonIDs
        if ($IDConfig.AD.enabled -eq $true) {
            #Update filteredData list and ADLookupByID Table with AD User Info if No EmployeeID is Set and an existing user is found that matches
            $ADUsersToSetEmployeeID = Get-ADUsersToSetEmployeeID -UserList $sourceData -CurrentADUsers $adData.Users

            foreach ($item in $SourceData | Where-Object { $ADUsersToSetEmployeeID.ContainsKey($_.personID) }) {
                $matchAD = $ADUsersToSetEmployeeID[$item.personID]
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
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleObject' -Value $matchGoogle.User -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserID' -Value $matchGoogle.ID -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentGroups' -Value $matchGoogle.Groups -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentUserSuspendedStatus' -Value $matchGoogle.SuspendedStatus -Force
                $item | Add-Member -MemberType NoteProperty -Name 'GoogleCurrentLicenses' -Value $matchGoogle.User.CurrentLicenses -Force
                $googleData.LookupByID[$item.personID] = $matchGoogle.User
            }
        }
        #endregion Match PersonIDs




        Write-Log -Message "######## Phase: Plan Changes ########"

        #region AD Processing Lists
        if ($IDConfig.AD.enabled -eq $true) {
            #Org Units to Create
            $ADOrgUnitsForProcessing = Get-ADOrgUnitsForProcessing -UserList $sourceData -CurrentOrgUnits $adData.OrgUnits
            #Users to Deactivate
            $ADUsersToDeactivate = Get-ADUsersToDeactivate -UserList $sourceData
            #Users to Update
            $ADUsersToUpdate = Get-ADUsersToUpdate -UserList $sourceData -LookupByID $adData.LookupByID -CurrentADUsers $adData.Users
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
            $GoogleOrgUnitsForProcessing = Get-GoogleOrgUnitsForProcessing -UserList $sourceData -CurrentOrgUnits $googleData.OrgUnits.orgUnitPath
            #Users to Update
            $GoogleUsersToUpdate = Get-GoogleUsersToUpdate -UserList $sourceData -LookupByID $googleData.LookupByID -GoogleUsers $googleData.Users
            #Users to Deactivate
            $GoogleUsersToDeactivate = Get-GoogleUsersToDeactivate -UserList $sourceData
            #Users to Create
            $GoogleUsersToCreate = Get-GoogleUsersToCreate -UserList $sourceData -GoogleUsers $googleData.Users
            #Groups to Update
            if ($IDConfig.Google.enableGroupProcessing -eq $true -or $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
                $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups
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
                # Count distinct affected users: a single user needing update+rename+move is one change,
                # not three (so the ratio is comparable to Google's per-user count). CN uniquely identifies the user.
                # Wrap each list in @() so a single-element list (scalar string) concatenates as an
                # array rather than via string addition.
                $adModifiedUsers = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]]@(@($ADUsersToUpdate.UpdateList.CN) + @($ADUsersToUpdate.RenameList.CN) + @($ADUsersToUpdate.MoveList.CN) | Where-Object { $_ })
                )
                $adChangeCount = @($ADUsersToCreate).Count + @($ADUsersToDeactivate).Count + $adModifiedUsers.Count
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
                #A preview exists to review exactly this - warn and keep going instead of aborting
                if ($Preview) {
                    Write-Log -Message "Change threshold exceeded ($breachSummary > $($IDConfig.ChangeThreshold.Percentage)%). A live run would abort here - continuing because this is a Preview." -Level Warn
                } else {
                    Write-Log -Message "Change threshold exceeded ($breachSummary > $($IDConfig.ChangeThreshold.Percentage)%). Aborting run before any writes. Set ChangeThreshold.Enabled = `$false or run with -SkipChangeThreshold to override." -Level Error
                    Throw "Change threshold exceeded: $breachSummary (limit $($IDConfig.ChangeThreshold.Percentage)%)."
                }
            }
        }
        #endregion Change Threshold Safety Check




        #region Preview Output
        # Emit the proposed changes as flat rows for table review. Lists for a disabled
        # directory (or disabled group processing) were never assigned and pass as $null.
        if ($Preview) {
            $previewSplat = @{
                SourceData    = $sourceData
                ShowPasswords = $ShowPasswords
            }

            if ($IDConfig.AD.enabled -eq $true) {
                $previewSplat.ADUsersToCreate      = $ADUsersToCreate
                $previewSplat.ADUsersToUpdate      = $ADUsersToUpdate
                $previewSplat.ADUsersToDeactivate  = $ADUsersToDeactivate
                $previewSplat.ADUserGroupsToUpdate = $ADUserGroupsToUpdate
                $previewSplat.ADOrgUnitsToCreate   = $ADOrgUnitsForProcessing
            }

            if ($IDConfig.Google.enabled -eq $true) {
                $previewSplat.GoogleUsersToCreate      = $GoogleUsersToCreate
                $previewSplat.GoogleUsersToUpdate      = $GoogleUsersToUpdate
                $previewSplat.GoogleUsersToDeactivate  = $GoogleUsersToDeactivate
                $previewSplat.GoogleUserGroupsToUpdate = $GoogleUserGroupsToUpdate
                $previewSplat.GoogleOrgUnitsToCreate   = $GoogleOrgUnitsForProcessing
            }

            $previewRows = @(ConvertTo-IDBridgePreviewRow @previewSplat)

            Write-Log -Message "Preview: Emitting $($previewRows.Count) proposed change row(s). Nothing was written."

            $previewRows
        }
        #endregion Preview Output




        if ($IDConfig.Debug.readOnly -eq $true) {
            Write-Log -Message "######## Phase: Apply Changes (skipped - ReadOnly mode) ########"
        } else {
            Write-Log -Message "######## Phase: Apply Changes ########"
        }

        #region Process AD Changes
        if ($IDConfig.AD.enabled -eq $true -and $IDConfig.Debug.readOnly -eq $false) {
            #Create Org Units (Get-ADOrgUnitsForProcessing already returns these deduped and parents-first)
            foreach ($item in $ADOrgUnitsForProcessing) {
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
                    #Disable-IDBridgeADUser returns the ErrorRecord on failure instead of throwing
                    $disableResult = Disable-IDBridgeADUser -User $item -GroupRemovalProcessingStatus $IDConfig.AD.enableGroupProcessingTrash
                    Add-IDBridgeWriteResult -Directory AD -Action Deactivate -PersonID $item.PersonID -Target $item.UPN -Success ($null -eq $disableResult) -ErrorMessage "$($disableResult)"
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory AD -Action Deactivate -PersonID $item.PersonID -Target $item.UPN -Success $false -ErrorMessage $_.Exception.Message
                }
            }


            #Update Users
            foreach ($item in $ADUsersToUpdate.UpdateList) {
                try {
                    Write-Log -Message "AD: Applying: Updating User: $($item.CN) Properties: $($item.splat | ConvertTo-Json -Compress)"
                    $itemSplat = $item.splat
                    Set-ADUser @itemSplat -ErrorAction Stop
                    Add-IDBridgeWriteResult -Directory AD -Action Update -PersonID $item.PersonID -Target $item.CN -Success $true
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory AD -Action Update -PersonID $item.PersonID -Target $item.CN -Success $false -ErrorMessage $_.Exception.Message
                }
            }

            #Rename Users
            foreach ($item in $ADUsersToUpdate.RenameList) {
                try {
                    Write-Log -Message "AD: Applying: Renaming User: $($item.CN) to $($item.NewName)"
                    Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                    Rename-ADObject -Identity $item.ADUserID -NewName $item.NewName -ErrorAction Stop
                    Add-IDBridgeWriteResult -Directory AD -Action Rename -PersonID $item.PersonID -Target $item.NewName -Success $true
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory AD -Action Rename -PersonID $item.PersonID -Target $item.NewName -Success $false -ErrorMessage $_.Exception.Message
                }
            }

            #Move Users
            foreach ($item in $ADUsersToUpdate.MoveList) {
                try {
                    Write-Log -Message "AD: Applying: Moving User: $($item.CN) to $($item.NewOrgUnit)"
                    Set-ADUser -Identity $item.ADUserID -Division (Get-Date -format yyyy-MM-dd-HH:mm)
                    Move-ADObject -Identity $item.ADUserID -TargetPath $item.NewOrgUnit -ErrorAction Stop
                    Add-IDBridgeWriteResult -Directory AD -Action Move -PersonID $item.PersonID -Target $item.CN -Success $true
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory AD -Action Move -PersonID $item.PersonID -Target $item.CN -Success $false -ErrorMessage $_.Exception.Message
                }
            }

            #Create Users
            foreach ($item in $ADUsersToCreate) {
                $itemCreated = $false
                try {
                    Write-Log -Message "AD: Applying: Creating User: $($item.PersonID) Properties: $($item.splat | ConvertTo-Json -Compress)"
                    $itemSplat = $item.splat
                    $newUser = New-ADUser @itemSplat -ErrorAction Stop
                    #Recorded before the GUID match-back below, which can fail independently of the create
                    $itemCreated = $true
                    Add-IDBridgeWriteResult -Directory AD -Action Create -PersonID $item.PersonID -Target $itemSplat.UserPrincipalName -Success $true

                    #Add the GUID to the data object
                    ($sourceData | Where-Object UPN -eq $itemSplat.UserPrincipalName).ADCurrentUserID = $newUser.ObjectGUID

                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    if (-not $itemCreated) {
                        Add-IDBridgeWriteResult -Directory AD -Action Create -PersonID $item.PersonID -Target $itemSplat.UserPrincipalName -Success $false -ErrorMessage $_.Exception.Message
                    }
                }
            }

            #Process Group Membership (enableGroupProcessingWhatIf suppresses the writes - the change lists were already logged above)
            if ($IDConfig.AD.enableGroupProcessing -eq $true -and $IDConfig.AD.enableGroupProcessingWhatIf -eq $true) {
                Write-Log -Message "AD: Group processing WhatIf is enabled - group changes were logged but NOT applied."
            }
            if ($IDConfig.AD.enableGroupProcessing -eq $true -and $IDConfig.AD.enableGroupProcessingWhatIf -ne $true) {
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
                            Write-Log -Message "AD: Applying: Adding Group: $group to $($item.PersonID)"
                            Add-ADPrincipalGroupMembership -Identity $item.ADCurrentUserID -MemberOf $group
                            Add-IDBridgeWriteResult -Directory AD -Action GroupAdd -PersonID $item.PersonID -Target $group -Success $true
                        }
                        catch {
                            Write-Log -Message ($_.Exception.Message) -Level Error
                            Add-IDBridgeWriteResult -Directory AD -Action GroupAdd -PersonID $item.PersonID -Target $group -Success $false -ErrorMessage $_.Exception.Message
                        }
                    }
                }

                #Process Group Membership Remove
                if ($IDConfig.AD.enableGroupProcessingRemove -eq $true) {
                    foreach ($item in $ADUserGroupsToUpdate.Remove) {
                        foreach ($group in $item.Groups) {
                            try {
                                Write-Log -Message "AD: Applying: Removing Group: $group from $($item.PersonID)"
                                Remove-ADGroupMember -Identity $group -Members $item.ADCurrentUserID -Confirm:$false
                                Add-IDBridgeWriteResult -Directory AD -Action GroupRemove -PersonID $item.PersonID -Target $group -Success $true
                            }
                            catch {
                                Write-Log -Message ($_.Exception.Message) -Level Error
                                Add-IDBridgeWriteResult -Directory AD -Action GroupRemove -PersonID $item.PersonID -Target $group -Success $false -ErrorMessage $_.Exception.Message
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

            #Disable Users (archive + move to trash sent as one batch; groups/licenses follow per user)
            #Archiving (not suspending) self-releases the base Education Fundamentals license;
            #paid add-on licenses are removed below. Pre-archive suspended users are grandfathered.
            $googleBatchRequests = @()
            $identityMap = @{}
            foreach ($item in $GoogleUsersToDeactivate) {
                try {
                    Write-Log -Message ("Google: Applying: Archiving account for $($item.UPN)")
                    Write-Log -Message  ("Google: Applying: Moving account to trash: $($item.UPN)")
                    $deactivateSplat = @{
                        GoogleUserID = $item.GoogleCurrentUserID
                        OrgUnitPath  = $item.GoogleOrganizationalUnitTrash
                        Archived     = 'true'
                    }

                    #Persist the personID link on accounts matched by name - the update list only covers active users, so without this the account is re-matched every run
                    if ($item.personID -notin $item.GoogleObject.externalIds.value) {
                        $deactivateSplat['PersonID'] = $item.personID
                    }

                    $googleBatchRequests += Update-IDBridgeGoogleUser @deactivateSplat -AsBatchRequest
                    $identityMap["$($item.GoogleCurrentUserID)"] = @{ PersonID = $item.personID; Target = $item.UPN }
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory Google -Action Deactivate -PersonID $item.personID -Target $item.UPN -Success $false -ErrorMessage $_.Exception.Message
                }
            }
            if ($googleBatchRequests.Count -gt 0) {
                $batchResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                Add-IDBridgeGoogleBatchResult -Action Deactivate -Requests $googleBatchRequests -Responses $batchResponses -IdentityMap $identityMap
            }

            #Strip group memberships on deactivate (batched) and remove licenses
            $googleBatchRequests = @()
            $identityMap = @{}
            foreach ($item in $GoogleUsersToDeactivate) {
                if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingTrash -eq $true) {
                    foreach ($group in $item.GoogleCurrentGroups) {
                        try {
                            Write-Log -Message ("Google: Applying: Removing Group: $group from $($item.personID)")
                            $googleBatchRequests += Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -AsBatchRequest -ContentId "$($item.personID)|$group"
                            $identityMap["$($item.personID)|$group"] = @{ PersonID = $item.personID; Target = $group }
                        }
                        catch {
                            Write-Log -Message ($_.Exception.Message) -Level Error
                            Add-IDBridgeWriteResult -Directory Google -Action GroupRemove -PersonID $item.personID -Target $group -Success $false -ErrorMessage $_.Exception.Message
                        }
                    }
                }

                #Remove licenses (full deactivate path only, never on ForceDisable updates; on by default)
                if ($IDConfig.Google.enableLicenseRemoval -ne $false) {
                    Remove-IDBridgeGoogleUserLicense -UserEmail $item.GoogleObject.primaryEmail -Assignments $item.GoogleCurrentLicenses
                }
            }
            if ($googleBatchRequests.Count -gt 0) {
                $batchResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                Add-IDBridgeGoogleBatchResult -Action GroupRemove -Requests $googleBatchRequests -Responses $batchResponses -IdentityMap $identityMap
            }

            #Update, Move, Rename Users (batched; any RemoveAlias pre-step runs immediately at collect time)
            $googleBatchRequests = @()
            $identityMap = @{}
            foreach ($item in $GoogleUsersToUpdate) {
                try {
                    Write-Log -Message "Google: Applying: Updating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
                    $itemSplat = $item.splat
                    $itemRequest = Update-IDBridgeGoogleUser @itemSplat -AsBatchRequest

                    #A failed RemoveAlias pre-step returns an ErrorRecord instead of a descriptor - skip those
                    if ($itemRequest -is [hashtable]) {
                        $googleBatchRequests += $itemRequest
                        $identityMap["$($itemRequest.ContentId)"] = @{ PersonID = $item.PersonID; Target = $item.UPN }
                    } else {
                        Add-IDBridgeWriteResult -Directory Google -Action Update -PersonID "$($item.PersonID)" -Target $item.UPN -Success $false -ErrorMessage "RemoveAlias pre-step failed: $($itemRequest)"
                    }
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory Google -Action Update -PersonID "$($item.PersonID)" -Target $item.UPN -Success $false -ErrorMessage $_.Exception.Message
                }
            }
            if ($googleBatchRequests.Count -gt 0) {
                $batchResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                Add-IDBridgeGoogleBatchResult -Action Update -Requests $googleBatchRequests -Responses $batchResponses -IdentityMap $identityMap
            }

            #Create Users (batched; new Google IDs are matched back by primaryEmail from each batch response)
            $googleBatchRequests = @()
            $identityMap = @{}
            foreach ($item in $GoogleUsersToCreate) {
                try {
                    Write-Log -Message "Google: Applying: Creating User: $($item.UPN) Properties: $($item.Splat | ConvertTo-Json -Compress)"
                    $itemSplat = $item.splat
                    $googleBatchRequests += New-IDBridgeGoogleUser @itemSplat -AsBatchRequest -ErrorAction Stop
                    $identityMap["$($item.UPN)"] = @{ PersonID = $item.PersonID; Target = $item.UPN }
                }
                catch {
                    Write-Log -Message ($_.Exception.Message) -Level Error
                    Add-IDBridgeWriteResult -Directory Google -Action Create -PersonID "$($item.PersonID)" -Target $item.UPN -Success $false -ErrorMessage $_.Exception.Message
                }
            }
            if ($googleBatchRequests.Count -gt 0) {
                $newUserResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                Add-IDBridgeGoogleBatchResult -Action Create -Requests $googleBatchRequests -Responses $newUserResponses -IdentityMap $identityMap

                #Add the Google IDs to the data objects
                foreach ($newUserResponse in $newUserResponses | Where-Object { $_.StatusCode -lt 400 -and $_.Body.id }) {
                    ($sourceData | Where-Object UPN -eq $newUserResponse.Body.primaryEmail).GoogleCurrentUserID = $newUserResponse.Body.id
                }
            }

            #Process Group Membership (enableGroupProcessingWhatIf suppresses the writes - the change lists were already logged above)
            if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingWhatIf -eq $true) {
                Write-Log -Message "Google: Group processing WhatIf is enabled - group changes were logged but NOT applied."
            }
            if ($IDConfig.Google.enableGroupProcessing -eq $true -and $IDConfig.Google.enableGroupProcessingWhatIf -ne $true) {
                if ($GoogleUsersToCreate.Count -gt 0) {
                    #Refresh Google User Groups to Update List to include newly created users
                    Write-Log -Message "Google: Refreshing User Groups to Update List to include newly created users." -Level Trace
                    
                    $GoogleUserGroupsToUpdate = Get-GoogleUserGroupsToUpdate -UserList $sourceData -GoogleGroups $googleData.Groups
                }

                #Process Group Membership Add (batched; adds and removes stay in separate batches since batch execution order is not guaranteed)
                $googleBatchRequests = @()
                $identityMap = @{}
                foreach ($item in $GoogleUserGroupsToUpdate.Add) {
                    foreach ($group in $item.Groups) {
                        try {
                            Write-Log -Message "Google: Applying: Adding Group: $group to $($item.PersonID)"
                            $googleBatchRequests += Update-GoogleGroupMembers -GroupEmail ($googleData.Groups | Where-Object {$_.name -eq $group}).email -PersonID $item.GoogleCurrentUserID -UpdateType "Add" -AsBatchRequest -ContentId "$($item.PersonID)|$group"
                            $identityMap["$($item.PersonID)|$group"] = @{ PersonID = $item.PersonID; Target = $group }
                        }
                        catch {
                            Write-Log -Message ($_.Exception.Message) -Level Error
                            Add-IDBridgeWriteResult -Directory Google -Action GroupAdd -PersonID $item.PersonID -Target $group -Success $false -ErrorMessage $_.Exception.Message
                        }
                    }
                }
                if ($googleBatchRequests.Count -gt 0) {
                    $batchResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                    Add-IDBridgeGoogleBatchResult -Action GroupAdd -Requests $googleBatchRequests -Responses $batchResponses -IdentityMap $identityMap
                }

                #Process Group Membership Remove (batched)
                if ($IDConfig.Google.enableGroupProcessingRemove -eq $true) {
                    $googleBatchRequests = @()
                    $identityMap = @{}
                    foreach ($item in $GoogleUserGroupsToUpdate.Remove) {
                        foreach ($group in $item.Groups) {
                            try {
                                Write-Log -Message "Google: Applying: Removing Group: $group from $($item.PersonID)"
                                $googleBatchRequests += Update-GoogleGroupMembers -GroupEmail $group -PersonID $item.GoogleCurrentUserID -UpdateType "Remove" -AsBatchRequest -ContentId "$($item.PersonID)|$group"
                                $identityMap["$($item.PersonID)|$group"] = @{ PersonID = $item.PersonID; Target = $group }
                            }
                            catch {
                                Write-Log -Message ($_.Exception.Message) -Level Error
                                Add-IDBridgeWriteResult -Directory Google -Action GroupRemove -PersonID $item.PersonID -Target $group -Success $false -ErrorMessage $_.Exception.Message
                            }
                        }
                    }
                    if ($googleBatchRequests.Count -gt 0) {
                        $batchResponses = Invoke-GoogleBatchRequest -Requests $googleBatchRequests
                        Add-IDBridgeGoogleBatchResult -Action GroupRemove -Requests $googleBatchRequests -Responses $batchResponses -IdentityMap $identityMap
                    }
                }
            }
        }
        #endregion Process Google Changes




        #region Run Summary
        # Per-directory totals from the computed change lists. In ReadOnly these are PROPOSED (nothing
        # was written); otherwise APPLIED (best-effort - any per-user failures were logged inline above).
        $summaryMode = if ($IDConfig.Debug.readOnly -eq $true) { 'PROPOSED (ReadOnly)' } else { 'APPLIED' }
        Write-Log -Message "Run Summary [$summaryMode]:"

        # Group-update lists are only assigned when group processing is on; .Where filters the lone
        # $null that @() wraps when the variable is unset, so a disabled group sync reports 0 (not 1).
        if ($IDConfig.AD.enabled -eq $true) {
            Write-Log -Message ("AD: Create={0} Update={1} Rename={2} Move={3} Deactivate={4} GroupAdd={5} GroupRemove={6}" -f `
                @($ADUsersToCreate).Count, @($ADUsersToUpdate.UpdateList).Count, @($ADUsersToUpdate.RenameList).Count, `
                @($ADUsersToUpdate.MoveList).Count, @($ADUsersToDeactivate).Count, `
                @($ADUserGroupsToUpdate.Add.Groups).Where({ $null -ne $_ }).Count, @($ADUserGroupsToUpdate.Remove.Groups).Where({ $null -ne $_ }).Count)
        }

        if ($IDConfig.Google.enabled -eq $true) {
            Write-Log -Message ("Google: Create={0} Update={1} Deactivate={2} GroupAdd={3} GroupRemove={4}" -f `
                @($GoogleUsersToCreate).Count, @($GoogleUsersToUpdate).Count, @($GoogleUsersToDeactivate).Count, `
                @($GoogleUserGroupsToUpdate.Add.Groups).Where({ $null -ne $_ }).Count, @($GoogleUserGroupsToUpdate.Remove.Groups).Where({ $null -ne $_ }).Count)
        }

        if ($thresholdResults) {
            foreach ($result in $thresholdResults) {
                $pct = if ($result.Skipped) { 'skipped (no managed population)' } else { "$($result.Percent)% of $($result.PopulationCount) (limit $($IDConfig.ChangeThreshold.Percentage)%)" }
                Write-Log -Message "$($result.Directory) change volume: $pct"
            }
        }
        #endregion Run Summary




    } catch {
        $runError = $_

        # Write-Log needs an initialized config; if the failure happened before/at config load it would
        # throw again here, so fall back to Write-Error in that case.
        try {
            Write-Log -Message "Invoke-IDBridge Failed" -Level Error
            Write-Log -Message ($_ | Out-String) -Level Error
        }
        catch {
            Write-Error "Invoke-IDBridge Failed: $($_.Exception.Message)"
        }
    } finally {
        # $IDConfig is only set once the config loads successfully; guard so a pre-config failure
        # doesn't throw out of the finally block.
        if ($IDConfig) {
            #region Build Run Result
            # One end-of-run report, consumed by both telemetry and the PostRun plugins. Built
            # defensively: on a failed run most change-list variables were never assigned, so every
            # list is wrapped @(...).Where({ $null -ne $_ }) to filter the lone $null @() wraps.
            $runResult = $null
            try {
                # Counts are ACTUAL applied outcomes, aggregated from the per-write results the
                # write phases recorded via Add-IDBridgeWriteResult. The old gates (ReadOnly,
                # group WhatIf, remove-off) are implicit now: nothing attempted = nothing
                # recorded, so those runs still report zeros.
                $appliedResults = if ($script:WriteResults) { @($script:WriteResults) } else { @() }
                $appliedOk = @($appliedResults | Where-Object { $_.Success })
                $runCounts = @{
                    Create      = @($appliedOk | Where-Object { $_.Action -eq 'Create' }).Count
                    # Update aggregates Update+Rename+Move, matching the historical definition
                    Update      = @($appliedOk | Where-Object { $_.Action -in @('Update', 'Rename', 'Move') }).Count
                    Deactivate  = @($appliedOk | Where-Object { $_.Action -eq 'Deactivate' }).Count
                    GroupAdd    = @($appliedOk | Where-Object { $_.Action -eq 'GroupAdd' }).Count
                    GroupRemove = @($appliedOk | Where-Object { $_.Action -eq 'GroupRemove' }).Count
                    Failed      = @($appliedResults | Where-Object { -not $_.Success }).Count
                }

                # See docs/plugins.md for the published schema. Grow this additively only - PostRun
                # plugins in the field depend on these property names.
                $runResult = [PSCustomObject]@{
                    SchemaVersion    = 1
                    ModuleVersion    = "$($MyInvocation.MyCommand.Module.Version)"
                    Success          = (-not $runError)
                    RunError         = $runError
                    RunStart         = $runStart
                    RunEnd           = (Get-Date)
                    DurationSeconds  = [int]((Get-Date) - $runStart).TotalSeconds
                    ReadOnly         = ($IDConfig.Debug.readOnly -eq $true)
                    TestRun          = ($IDConfig.Debug.testRun -eq $true)
                    Counts           = [PSCustomObject]@{
                        Managed     = @($sourceData).Where({ $null -ne $_ }).Count
                        Create      = $runCounts.Create
                        Update      = $runCounts.Update
                        Deactivate  = $runCounts.Deactivate
                        GroupAdd    = $runCounts.GroupAdd
                        GroupRemove = $runCounts.GroupRemove
                        Failed      = $runCounts.Failed
                    }
                    Applied          = $appliedResults
                    SourceData       = @($sourceData).Where({ $null -ne $_ })
                    ThresholdResults = @($thresholdResults).Where({ $null -ne $_ })
                    AD               = [PSCustomObject]@{
                        Enabled           = ($IDConfig.AD.enabled -eq $true)
                        UsersToCreate     = @($ADUsersToCreate).Where({ $null -ne $_ })
                        UsersToUpdate     = $ADUsersToUpdate
                        UsersToDeactivate = @($ADUsersToDeactivate).Where({ $null -ne $_ })
                        GroupsToUpdate    = $ADUserGroupsToUpdate
                        OrgUnitsToCreate  = @($ADOrgUnitsForProcessing).Where({ $null -ne $_ })
                        CurrentUsers      = @($adData.Users).Where({ $null -ne $_ })
                    }
                    Google           = [PSCustomObject]@{
                        Enabled           = ($IDConfig.Google.enabled -eq $true)
                        UsersToCreate     = @($GoogleUsersToCreate).Where({ $null -ne $_ })
                        UsersToUpdate     = @($GoogleUsersToUpdate).Where({ $null -ne $_ })
                        UsersToDeactivate = @($GoogleUsersToDeactivate).Where({ $null -ne $_ })
                        GroupsToUpdate    = $GoogleUserGroupsToUpdate
                        OrgUnitsToCreate  = @($GoogleOrgUnitsForProcessing).Where({ $null -ne $_ })
                        CurrentUsers      = @($googleData.Users).Where({ $null -ne $_ })
                    }
                }
            }
            catch {
                Write-Log -Message "Run Result: Build failed ($($_.Exception.GetType().Name)) - telemetry and PostRun plugins skipped." -Level Warn
            }
            #endregion Build Run Result

            #region Telemetry
            # Usage telemetry (see PRIVACY.md) - fully self-contained: any failure here is swallowed
            # and logged locally so it can never mask the run's real outcome or throw out of finally.
            # Preview runs stay quiet - a review peek is not a run.
            try {
                if ($runResult -and -not $Preview) {
                    $telemetrySplat = @{
                        Success           = $runResult.Success
                        DurationSeconds   = $runResult.DurationSeconds
                        ManagedCount      = $runResult.Counts.Managed
                        CreateCount       = $runResult.Counts.Create
                        UpdateCount       = $runResult.Counts.Update
                        DeactivateCount   = $runResult.Counts.Deactivate
                        GroupAddCount     = $runResult.Counts.GroupAdd
                        GroupRemoveCount  = $runResult.Counts.GroupRemove
                        WriteFailureCount = $runResult.Counts.Failed
                    }
                    if ($runError) { $telemetrySplat.RunError = $runError }

                    Send-IDBridgeTelemetry @telemetrySplat
                }
            }
            catch {
                Write-Log -Message "Telemetry: Skipped ($($_.Exception.GetType().Name))." -Level Trace
            }
            #endregion Telemetry

            #region PostRun Plugins
            # SecureStrings (account keys, passphrase API secrets) are scrubbed from the report
            # before any plugin sees it - the run is over, nothing downstream needs them. Isolated
            # like telemetry: a PostRun failure can never mask the run's real outcome.
            # Preview runs stay quiet - no PostRun side effects for a review peek.
            try {
                if ($runResult -and -not $Preview) {
                    Hide-IDBridgeSecureString -InputObject $runResult
                    Invoke-PostRunPlugins -RunResult $runResult
                }
            }
            catch {
                Write-Log -Message "PostRun Plugins: Skipped ($($_.Exception.GetType().Name))." -Level Warn
            }
            #endregion PostRun Plugins

            Write-Log -Message "######## End of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########"

            #Preview runs stay quiet - don't push the log sheet for a review peek
            if ($IDConfig.Logging.GoogleSheetLoggingEnabled -and -not $Preview) {
                Push-LogsToSheet -spreadsheetId $IDConfig.Logging.SheetID -sheetName 'Logs'
            }
        }

        #Release the single-run lock last (process death would release it too)
        if ($runMutexHeld) { $runMutex.ReleaseMutex() }
        if ($runMutex) { $runMutex.Dispose() }
    }
}