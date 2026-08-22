<#
.SYNOPSIS
Interactively review and approve source/directory name mismatches so the accounts can be linked.

.DESCRIPTION
Onboarding tool, run by hand — never called by the pipeline. When EmployeeID linking finds a
source user's username already taken by an account with a different name, the pipeline logs an
error and skips it. This cmdlet gathers the same source and directory data the pipeline would
(Initialize-IDBridge, source plugins, AD/Google target data, dedupe, overrides), finds every such
mismatch, and walks them one at a time in the console showing both names side by side.

Approving records the decision to <DataRoot>\ApprovedNameMismatches.csv — nothing is written to
AD or Google here. On the next Invoke-IDBridge run the linking functions honor the approval and
link the account, and the normal update pass then sets the EmployeeID and renames the account to
the source (SIS) name under all the usual safety gates (ReadOnly, ChangeThreshold). Each approval
is saved as it is made, so quitting mid-review loses nothing. AD and Google are approved
independently (one row per directory), and an approval is honored only while the account's
username and directory name still match what was approved — a drifted account must be
re-approved (it shows up here again).

.PARAMETER RootPath
Base dir for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.

.PARAMETER SkipAD
Skip Active Directory mismatches for this review.

.PARAMETER SkipGoogle
Skip Google Workspace mismatches for this review.

.OUTPUTS
[pscustomobject] @{ Reviewed; Approved; Skipped; FilePath }.

.EXAMPLE
Approve-IDBridgeNameMismatch

.EXAMPLE
Approve-IDBridgeNameMismatch -RootPath 'C:\IDBridge' -SkipGoogle

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-21
#>
function Approve-IDBridgeNameMismatch {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge",

        [switch]$SkipAD,
        [switch]$SkipGoogle
    )

    #region Import Configuration
    try { Initialize-IDBridge -RootPath $RootPath } catch { Throw }

    try { $IDConfig = Get-IDBridgeConfig } catch { Throw }
    #endregion Import Configuration



    #region Apply Runtime Overrides
    if ($SkipAD)      { $IDConfig.AD.enabled     = $false }
    if ($SkipGoogle)  { $IDConfig.Google.enabled = $false }

    if ($IDConfig.AD.enabled -ne $true -and $IDConfig.Google.enabled -ne $true) {
        Write-Log -Message "Approve: Both AD and Google are disabled - nothing to review." -Level Error
        Throw "Approve: Both AD and Google are disabled - nothing to review."
    }

    #TestRun caps each source plugin at 10 records - the mismatch set would be incomplete
    if ($IDConfig.Debug.testRun -eq $true) {
        Write-Log -Message "Approve: Debug.testRun is enabled - source data is capped at 10 records per plugin, so this review may miss mismatches." -Level Warn
    }
    #endregion Apply Runtime Overrides



    #region Gather Source & Directory Data
    # Shared with Invoke-IDBridge: Google auth, source plugins, AD/Google target data,
    # enrichment, dedupe, override merge. PersonID matching deliberately does NOT happen
    # here - the mismatch detection below inspects the unlinked (pre-matching) state.
    Write-Log -Message "Approve: Gathering source and directory data for name-mismatch review."

    try {
        $pipelineData = Get-IDBridgePipelineData

        $sourceData = $pipelineData.SourceData
        $adData     = $pipelineData.ADData
        $googleData = $pipelineData.GoogleData
    }
    catch { Throw }
    #endregion Gather Source & Directory Data



    #region Find Mismatches
    #Same detection as the linking functions: unlinked source user whose username is taken by an
    #account with a different name. A mismatch with a still-valid approval is excluded; one whose
    #approval went stale (account renamed since) is included so it can be re-approved.
    $approvedMismatches = Get-IDBridgeApprovedNameMismatches

    $mismatches = @()

    if ($IDConfig.AD.enabled -eq $true) {
        foreach ($item in $sourceData | Where-Object {-not $_.ADCurrentUserID}) {
            if ($item.personID -notin $adData.Users.employeeID -and $item.username -in $adData.Users.SamAccountName) {
                $ADUser = ($adData.Users | Where-Object {$_.SamAccountName -eq $item.username})

                if ($ADUser.Surname -ne $item.NameLast -or $ADUser.GivenName -ne $item.NameFirst) {
                    $directoryName = $ADUser.GivenName + " " + $ADUser.Surname
                    $approval = $approvedMismatches["AD|$($item.personID)"]

                    if (-not ($approval -and $approval.Account -eq $item.username -and $approval.DirectoryName -eq $directoryName)) {
                        $mismatches += [PSCustomObject]@{
                            Directory     = 'AD'
                            PersonID      = $item.personID
                            Account       = $item.username
                            Display       = $ADUser.UserPrincipalName
                            SourceName    = $item.NameFirst + " " + $item.NameLast
                            DirectoryName = $directoryName
                        }
                    }
                }
            }
        }
    }

    if ($IDConfig.Google.enabled -eq $true) {
        foreach ($item in $sourceData | Where-Object {-not $_.GoogleCurrentUserID}) {
            if ($item.UPN -in $googleData.Users.primaryEmail) {
                $googleUser = ($googleData.Users | Where-Object {$_.primaryEmail -eq $item.UPN})

                if ($googleUser.Name.familyName -ne $item.NameLast -or $googleUser.Name.givenName -ne $item.NameFirst) {
                    $directoryName = $googleUser.Name.givenName + " " + $googleUser.Name.familyName
                    $approval = $approvedMismatches["Google|$($item.personID)"]

                    if (-not ($approval -and $approval.Account -eq $item.UPN -and $approval.DirectoryName -eq $directoryName)) {
                        $mismatches += [PSCustomObject]@{
                            Directory     = 'Google'
                            PersonID      = $item.personID
                            Account       = $item.UPN
                            Display       = $googleUser.primaryEmail
                            SourceName    = $item.NameFirst + " " + $item.NameLast
                            DirectoryName = $directoryName
                        }
                    }
                }
            }
        }
    }
    #endregion Find Mismatches



    #region Review
    $approvalFilePath = "$($IDConfig.Paths.DataRoot)\ApprovedNameMismatches.csv"

    if ($mismatches.Count -eq 0) {
        Write-Log -Message "Approve: No unapproved name mismatches found - nothing to review."
        Write-Host "No unapproved name mismatches found - nothing to review." -ForegroundColor Green

        return [PSCustomObject]@{
            Reviewed = 0
            Approved = 0
            Skipped  = 0
            FilePath = $approvalFilePath
        }
    }

    Write-Log -Message "Approve: $($mismatches.Count) name mismatch(es) to review."

    #Existing rows are kept in memory so each approval rewrites the full file; a re-approval
    #replaces the old row for that Directory+PersonID instead of duplicating it
    $approvalRows = @()
    if (Test-Path $approvalFilePath) {
        $approvalRows = @(Import-Csv -Path $approvalFilePath)
    }

    Write-Host ""
    Write-Host "$($mismatches.Count) name mismatch(es) to review." -ForegroundColor Cyan
    Write-Host "Approving records the decision to $approvalFilePath - no directory writes happen here."
    Write-Host "On the next Invoke-IDBridge run an approved account is linked and RENAMED to the source (SIS) name." -ForegroundColor Yellow
    Write-Host ""

    $approvedCount = 0
    $skippedCount = 0
    $reviewedCount = 0

    foreach ($mismatch in $mismatches) {
        $reviewedCount++

        Write-Host ("[{0}/{1}] {2}  PersonID {3}  ({4})" -f $reviewedCount, $mismatches.Count, $mismatch.Directory, $mismatch.PersonID, $mismatch.Display) -ForegroundColor Cyan
        Write-Host ("  Source (SIS) name:  " + $mismatch.SourceName)
        Write-Host ("  {0} name:{1}  {2}" -f $mismatch.Directory, (" " * (12 - $mismatch.Directory.Length)), $mismatch.DirectoryName)

        $answer = $null
        while ($answer -notin @('A', 'S', 'Q')) {
            $answer = (Read-Host "Approve link? [A]pprove / [S]kip / [Q]uit").Trim().ToUpper()
        }

        if ($answer -eq 'Q') {
            $reviewedCount--
            Write-Host "Quitting review - decisions already made are saved." -ForegroundColor Yellow
            break
        }

        if ($answer -eq 'A') {
            #Replace any prior (stale) approval for this Directory+PersonID, then save
            #immediately so quitting mid-review loses nothing
            $approvalRows = @($approvalRows | Where-Object { -not ($_.Directory -eq $mismatch.Directory -and $_.PersonID -eq $mismatch.PersonID) })
            $approvalRows += [PSCustomObject]@{
                PersonID      = $mismatch.PersonID
                Directory     = $mismatch.Directory
                Account       = $mismatch.Account
                SourceName    = $mismatch.SourceName
                DirectoryName = $mismatch.DirectoryName
                ApprovedDate  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }

            if (-not (Test-Path "$($IDConfig.Paths.DataRoot)")) {
                New-Item -Path "$($IDConfig.Paths.DataRoot)" -ItemType Directory -Force | Out-Null
            }

            $approvalRows | Export-Csv -Path $approvalFilePath -NoTypeInformation -Force

            Write-Log -Message ("Approve: $($mismatch.Directory): Name mismatch approved for $($mismatch.PersonID) ($($mismatch.Account)) - source name " + $mismatch.SourceName + ", directory name " + $mismatch.DirectoryName + ".")
            Write-Host "  Approved." -ForegroundColor Green
            $approvedCount++
        } else {
            Write-Log -Message ("Approve: $($mismatch.Directory): Name mismatch skipped for $($mismatch.PersonID) ($($mismatch.Account)).") -Level Trace
            Write-Host "  Skipped." -ForegroundColor Yellow
            $skippedCount++
        }

        Write-Host ""
    }

    $remainingCount = $mismatches.Count - $reviewedCount

    Write-Log -Message "Approve: Review finished - $approvedCount approved, $skippedCount skipped, $remainingCount not reviewed."
    Write-Host ("Review finished: {0} approved, {1} skipped, {2} not reviewed." -f $approvedCount, $skippedCount, $remainingCount) -ForegroundColor Cyan
    if ($approvedCount -gt 0) {
        Write-Host "Approved accounts will be linked on the next Invoke-IDBridge run."
    }
    #endregion Review

    return [PSCustomObject]@{
        Reviewed = $reviewedCount
        Approved = $approvedCount
        Skipped  = $skippedCount
        FilePath = $approvalFilePath
    }
}
