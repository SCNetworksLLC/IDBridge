function Get-GoogleOrgUnitsForProcessing {
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $UserRootOU,

        [Parameter(Mandatory = $true)]
        $CurrentOrgUnits,

        [Parameter(Mandatory = $true)]
        [string]$logFile
    )

    #Manual and Top Level OUs to Check
    $OUList = @(
        $UserRootOU
        ($UserRootOU + "/Student")
        ($UserRootOU + "/Staff")
        ("/Trash")
        ("/Trash/Student")
        ("/Trash/Staff")
    )

    #Add the OUs to check from only active users
    $OUListAuto = @()
    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true}) {
        $OUListAuto += $item.GoogleOrganizationalUnit
        $OUListAuto += $item.GoogleOrganizationalUnitTrash
    }

    #Combine Base and OU Lists - This is needed to be done this way so that the base OUs get processed first
    $OUList += $OUListAuto | Sort-Object -Unique

    #Create list for processing
    $OrgUnitsForProcessing = $OUList | Where-Object {$_ -notin $CurrentOrgUnits}

    foreach ($item in $OrgUnitsForProcessing) {
        Write-Log -Path $logFile -Message "Google: Adding Org Unit to Process List: Create: $($item)"
    }

    return $OrgUnitsForProcessing | Sort-Object -Unique
}