<#
.SYNOPSIS
Record the outcome of one attempted directory write for the current run.

.DESCRIPTION
Internal helper: appends one structured result to the module-scoped write-result buffer
($script:WriteResults, reset by Initialize-IDBridge, lazily created here so early callers
never throw). The buffer is read at end of run to build the RunResult Applied list and the
actual-outcome telemetry counts — one record per attempted write, success or failure.

.PARAMETER Directory
Which directory the write targeted: AD or Google.

.PARAMETER Action
The write type: Create, Update, Rename, Move, Deactivate, GroupAdd, or GroupRemove.

.PARAMETER PersonID
The person the write was for (may be empty when unknown, e.g. an unmatched batch response).

.PARAMETER Target
What was written: UPN/CN for user operations, the group name for group operations.

.PARAMETER Success
Whether the write succeeded.

.PARAMETER ErrorMessage
The failure message. Omit on success.

.OUTPUTS
None. Appends to $script:WriteResults.

.EXAMPLE
Add-IDBridgeWriteResult -Directory AD -Action Create -PersonID $item.PersonID -Target $itemSplat.UserPrincipalName -Success $true

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-12
#>
function Add-IDBridgeWriteResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("AD", "Google")]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Create", "Update", "Rename", "Move", "Deactivate", "GroupAdd", "GroupRemove")]
        [string]$Action,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$PersonID,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [bool]$Success,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$ErrorMessage
    )

    if ($null -eq $script:WriteResults) {
        $script:WriteResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    $script:WriteResults.Add([PSCustomObject]@{
        Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Directory = $Directory
        Action    = $Action
        PersonID  = $PersonID
        Target    = $Target
        Success   = $Success
        Error     = if ($Success) { $null } else { $ErrorMessage }
    })
}
