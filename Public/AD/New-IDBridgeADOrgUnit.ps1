function New-IDBridgeADOrgUnit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OrgUnit,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    try {
        Write-Log -Path $logFile -Message "AD: Creating Org Unit $OrgUnit"
        New-ADOrganizationalUnit -Name $OrgUnit.split(",",2)[0].replace("OU=","") -Path $OrgUnit.split(",",2)[1] -ErrorAction Stop
    }
    catch {
        return $_
    }
}