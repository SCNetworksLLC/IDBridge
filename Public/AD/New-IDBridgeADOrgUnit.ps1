function New-IDBridgeADOrgUnit {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $OrgUnit,

        [Parameter(Mandatory = $true)]
        $ReadOnly,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    try {
        Write-Log -Path $logFile -Message "AD: Creating Org Unit $OrgUnit"
        if ($ReadOnly -eq $false) {
            New-ADOrganizationalUnit -Name $OrgUnit.split(",",2)[0].replace("OU=","") -Path $OrgUnit.split(",",2)[1] -ErrorAction Stop
        } else {
            Write-Log -Path $logFile -Message "AD: ReadOnly mode is enabled. Org Unit $OrgUnit will not be created." -Level Warning
        }
    }
    catch {
        return $_
    }
}