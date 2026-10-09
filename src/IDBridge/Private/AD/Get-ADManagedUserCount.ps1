<#
.SYNOPSIS
Count the enabled AD accounts IDBridge has linked - the change-volume guard's population.

.DESCRIPTION
The change-volume guard's denominator for AD (Invoke-IDBridge, ChangeThreshold). A user counts
when it carries an EmployeeID - the personID link IDBridge writes on create, link and deactivate -
and is enabled. Where the account sits in the domain doesn't matter: disabled accounts in the
trash OU and accounts IDBridge never linked (service, admin, hand-made accounts) never count, and
AD.userRootOU plays no part (it is only the service account's delegation OU). The count reads
directory state only: a broken source feed cannot shrink its own denominator. Nothing is linked on
a fresh domain, so the count is 0 and Test-IDBridgeChangeThreshold skips the check with a Warn.
Assumes nothing else populates EmployeeID in the domain (e.g. an HR sync) - those accounts would
count too. Mirrors Get-GoogleManagedUserCount.

.PARAMETER Users
The AD users (from Get-TargetDataAD .Users). Null or empty allowed.

.OUTPUTS
[int] the managed user count.

.EXAMPLE
$population = Get-ADManagedUserCount -Users $adData.Users

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-10-09
#>
function Get-ADManagedUserCount {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Users
    )

    return @($Users | Where-Object { $_.Enabled -eq $true -and $_.EmployeeID }).Count
}
