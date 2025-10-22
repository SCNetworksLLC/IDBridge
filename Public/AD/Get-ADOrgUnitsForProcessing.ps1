function Get-ADOrgUnitsForProcessing {
    [CmdletBinding()]
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
    $OUCheckAD = @(
        $UserRootOU
        ("OU=Student," + $UserRootOU)
        ("OU=Staff," + $UserRootOU)
        ("OU=Trash," + $UserRootOU)
        ("OU=Student,OU=Trash," + $UserRootOU)
        ("OU=Staff,OU=Trash," + $UserRootOU)
    )

    #Add the OUs to check from only active users
    $OUCheckADAuto = @()
    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true}) {
        $OUCheckADAuto += $item.ADOrganizationalUnit
        $OUCheckADAuto += $item.ADOrganizationalUnitTrash
    }

    #Combine the OUs together - this is done so that the base OUs are created first
    $OUCheckAD += $OUCheckADAuto | Sort-Object -Unique

    #Create list for processing
    $OrgUnitsForProcessingAD = $OUCheckAD | Sort-Object -Unique | Where-Object {$_ -notin $CurrentOrgUnits}

    return $OrgUnitsForProcessingAD
}