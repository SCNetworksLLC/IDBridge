<#
.SYNOPSIS
Create a single Active Directory organizational unit from its distinguished name.

.DESCRIPTION
Parses the supplied OU distinguished name into its leaf name and parent path and creates it with
New-ADOrganizationalUnit. Intended to be called for each OU in the parents-first list from
Get-ADOrgUnitsForProcessing. Throws on error — Invoke-IDBridge treats a failed OU creation as
fatal and aborts the run (a missing OU would cascade into user create/move failures).

.PARAMETER OrgUnit
The full distinguished name of the OU to create (e.g. 'OU=Staff,OU=YourDistrict,DC=yourdomain,DC=local').

.EXAMPLE
New-IDBridgeADOrgUnit -OrgUnit 'OU=Staff,OU=YourDistrict,DC=yourdomain,DC=local'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function New-IDBridgeADOrgUnit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OrgUnit
    )

    try {
        Write-Log -Message "AD: Applying: Creating Org Unit $OrgUnit"
        New-ADOrganizationalUnit -Name $OrgUnit.split(",",2)[0].replace("OU=","") -Path $OrgUnit.split(",",2)[1] -ErrorAction Stop
    }
    catch {
        Throw
    }
}