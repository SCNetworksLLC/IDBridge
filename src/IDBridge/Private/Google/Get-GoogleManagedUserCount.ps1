<#
.SYNOPSIS
Count the active Google accounts IDBridge has linked - the change-volume guard's population.

.DESCRIPTION
The change-volume guard's denominator for Google (Invoke-IDBridge, ChangeThreshold). A user
counts when it carries an IDBridge personID link - an 'organization' externalId with a value,
which IDBridge writes on create, link and deactivate - and is neither suspended nor archived.
Where the account sits in the OU tree doesn't matter, so no OU setting can drift from where the
source plugins actually place users, and accounts IDBridge never linked (admins, kiosks,
hand-made accounts) never count. The count reads directory state only: a broken source feed
cannot shrink its own denominator. Nothing is linked on a fresh tenant, so the count is 0 and
Test-IDBridgeChangeThreshold skips the check with a Warn.

.PARAMETER Users
The Google users (from Get-TargetDataGoogle .Users). Null or empty allowed.

.OUTPUTS
[int] the managed user count.

.EXAMPLE
$population = Get-GoogleManagedUserCount -Users $googleData.Users

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-10-09
#>
function Get-GoogleManagedUserCount {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $Users
    )

    return @($Users | Where-Object {
        $_.suspended -ne $true -and $_.archived -ne $true -and
        @($_.externalIds | Where-Object { $_.type -eq 'organization' -and $_.value }).Count -gt 0
    }).Count
}
