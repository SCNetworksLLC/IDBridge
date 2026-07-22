#PostRun Orphan Report Plugin — IDBridge plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
Reports enabled directory accounts that carry a PersonID link (AD EmployeeID / Google
externalId of type "organization") but matched no source record this run. Without a source
record the pipeline never updates or deactivates an account, so these linger enabled and
invisible — typical causes: a deleted sheet row, a student who left before LastSeen state
tracking existed, or a person removed from the SIS.

No placeholders: enable its descriptor and it runs. When orphans are found it writes
OrphanReport-<timestamp>.csv to Paths.ExportsRoot and logs a Warn with the counts.
Report-only — it never touches the accounts; offboard them by hand or via a ForceDisable
override row.
#>


function Invoke-PluginPostRunOrphanReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    #A failed run may have incomplete source data — everyone left would look orphaned
    if (-not $RunResult.Success) {
        Write-Log -Message "Orphan Report: Run failed, skipping report (source data may be incomplete)." -Level Trace
        return
    }

    #TestRun caps each source plugin at 10 records — everyone else would look orphaned
    if ($RunResult.TestRun) {
        Write-Log -Message "Orphan Report: TestRun caps source data, skipping report." -Level Trace
        return
    }

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    #Build a lookup of every PersonID the run's source plugins produced
    $sourceIDs = @{}
    foreach ($id in $RunResult.SourceData.PersonID) {
        if ($id) { $sourceIDs["$id"] = $true }
    }

    if ($sourceIDs.Count -eq 0) {
        Write-Log -Message "Orphan Report: No source PersonIDs in the RunResult, skipping report." -Level Trace
        return
    }

    $orphans = @()

    #AD: enabled accounts with an EmployeeID that no source record claimed
    if ($RunResult.AD.Enabled) {
        foreach ($user in $RunResult.AD.CurrentUsers) {
            if ($user.Enabled -eq $true -and $user.EmployeeID -and -not $sourceIDs.ContainsKey("$($user.EmployeeID)")) {
                $orphans += [PSCustomObject]@{
                    Directory = 'AD'
                    PersonID  = $user.EmployeeID
                    Account   = $user.UserPrincipalName
                    Name      = $user.DisplayName
                    Location  = $user.DistinguishedName
                }
            }
        }
    }

    #Google: non-suspended accounts with an organization externalId that no source record claimed
    if ($RunResult.Google.Enabled) {
        foreach ($user in $RunResult.Google.CurrentUsers) {
            $pkID = ($user.externalIds | Where-Object { $_.type -eq 'organization' } | Select-Object -First 1).value
            if ($user.suspended -ne $true -and $pkID -and -not $sourceIDs.ContainsKey("$pkID")) {
                $orphans += [PSCustomObject]@{
                    Directory = 'Google'
                    PersonID  = $pkID
                    Account   = $user.primaryEmail
                    Name      = $user.name.fullName
                    Location  = $user.orgUnitPath
                }
            }
        }
    }

    if ($orphans.Count -gt 0) {
        $reportPath = "$($IDConfig.Paths.ExportsRoot)\OrphanReport-$(Get-Date -Format 'yyyy-MM-dd-HH.mm.ss').csv"
        $orphans | Export-Csv -Path $reportPath -NoTypeInformation -Force

        $adCount = @($orphans | Where-Object { $_.Directory -eq 'AD' }).Count
        $googleCount = @($orphans | Where-Object { $_.Directory -eq 'Google' }).Count
        Write-Log -Message "Orphan Report: $($orphans.Count) enabled account(s) with a PersonID link but no source record (AD: $adCount, Google: $googleCount). Report: $reportPath" -Level Warn
    } else {
        Write-Log -Message "Orphan Report: No orphaned accounts found." -Level Info
    }
}
