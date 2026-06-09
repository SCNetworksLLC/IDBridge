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