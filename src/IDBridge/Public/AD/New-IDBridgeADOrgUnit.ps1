<#
.SYNOPSIS
Create a single Active Directory organizational unit from its distinguished name.

.DESCRIPTION
Parses the supplied OU distinguished name into its leaf name and parent path and creates it with
New-ADOrganizationalUnit. Intended to be called for each OU in the parents-first list from
Get-ADOrgUnitsForProcessing. On error the error record is returned rather than thrown.

.PARAMETER OrgUnit
The full distinguished name of the OU to create (e.g. 'OU=Staff,OU=Marshfield,DC=sdom,DC=local').

.EXAMPLE
New-IDBridgeADOrgUnit -OrgUnit 'OU=Staff,OU=Marshfield,DC=sdom,DC=local'

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
        Write-Log -Message "AD: Creating Org Unit $OrgUnit"
        New-ADOrganizationalUnit -Name $OrgUnit.split(",",2)[0].replace("OU=","") -Path $OrgUnit.split(",",2)[1] -ErrorAction Stop
    }
    catch {
        return $_
    }
}