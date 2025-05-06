function Get-DuplicateIDsGoogle {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $SourceData
    )

    #Get Google users with duplicate organization external ID
    $duplicateUsers = ($SourceData | ForEach-Object {
        $pkID = ($_.externalIds | Where-Object { $_.Type -eq "organization" }).value
        if ($pkID) {
            [PSCustomObject]@{
                UPN = $_.primaryEmail
                FullName = $_.name.fullName
                OrgID = $pkID
            }
        }
    } | Group-Object -Property OrgID | Where-Object { $_.Count -gt 1 }).group

    if ($duplicateUsers) {
        Write-Log -Path $logFile -Message ("Google: Users found with Duplicate External IDs: " + ($duplicateUsers | ConvertTo-Json -Compress)) -Level Error
    }

    return $duplicateUsers
}