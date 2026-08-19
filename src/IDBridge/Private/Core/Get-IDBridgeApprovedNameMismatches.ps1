<#
.SYNOPSIS
Load the persisted name-mismatch approvals from the Data directory.

.DESCRIPTION
Reads <DataRoot>\ApprovedNameMismatches.csv - the decisions recorded by
Approve-IDBridgeNameMismatch - and returns them as a lookup keyed "<Directory>|<PersonID>"
(e.g. "AD|10108134"). Each value is the raw CSV row (PersonID, Directory, Account,
SourceName, DirectoryName, ApprovedDate). Returns an empty hashtable when the file does
not exist. Consumed by Get-ADUsersToSetEmployeeID and Get-GoogleUsersToSetEmployeeID to
link an existing account whose name differs from the source when that mismatch was
explicitly approved.

.OUTPUTS
[hashtable] "<Directory>|<PersonID>" -> approval row.

.EXAMPLE
$approvedMismatches = Get-IDBridgeApprovedNameMismatches

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-19
#>
function Get-IDBridgeApprovedNameMismatches {
    [CmdletBinding()]
    param ()

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    $approved = @{}

    $path = "$($IDConfig.Paths.DataRoot)\ApprovedNameMismatches.csv"
    if (Test-Path $path) {
        foreach ($row in (Import-Csv -Path $path)) {
            if ($row.PersonID -and $row.Directory) {
                $approved["$($row.Directory)|$($row.PersonID)"] = $row
            }
        }

        if ($approved.Count -gt 0) {
            Write-Log -Message "Approved name mismatches: Loaded $($approved.Count) approval(s) from $path" -Level Trace
        }
    }

    return $approved
}
