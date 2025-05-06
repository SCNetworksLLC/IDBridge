function Get-DuplicateIDsAD {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )
    #Get AD users with duplicate employeeID
    $duplicateUsers = ($SourceData.where{$_.employeeID} | 
        Select-Object -Property UserPrincipalName, employeeID | 
        Group-Object -Property employeeID | 
        Where-Object { $_.Count -gt 1 }
        ).group

    if ($duplicateUsers) {
        Write-Log -Path $logFile -Message ("AD: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress)) -Level Error
    }

    return $duplicateUsers
}