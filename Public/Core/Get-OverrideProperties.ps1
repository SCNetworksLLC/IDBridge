function Get-OverrideProperties {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $item,
        
        [Parameter(Mandatory = $true)]
        $additionalUserProperties,
    
        [Parameter(Mandatory = $true)]
        $OverrideData,

        [Parameter(Mandatory = $true)]
        $logFile
    )



    

    $item = $dataStudent | Where-Object {$_.PersonID -eq '370008'}
    #Add Override Data if it exists for the user
    if ($dataOverride) {
        $overrideItem = $dataOverride | Where-Object {$_.PersonID -eq $item.PersonID -and $_.OverrideEndDate}
        if ($overrideItem -and (Get-Date $overrideItem.OverrideEndDate -format "yyyy-MM-dd") -gt (Get-Date -format "yyyy-MM-dd")) {
            foreach ($overrideProperty in $overrideItem.PSObject.Properties) {
                if ($overrideProperty.Value -and -not [string]::IsNullOrWhiteSpace($overrideProperty.Value) -and $overrideProperty.Name -ne "PersonID") {
                    if ($overrideProperty.Value -ne "FALSE") {
                        $item | Add-Member -MemberType NoteProperty -Name $overrideProperty.Name -Value $overrideProperty.Value -Force
                        Write-Log -Path $logFile -Message ("Applied Override for " + $overrideProperty.Name + " for PersonID: " + $item.PersonID)
                    }
                }
            }
        }
    }
    #$additionalUserProperties.IDBActive                       = $IDConfig.Student.$($item.Grade).Enabled

    #$additionalUserProperties.ADOrganizationalUnit            = "OU=Grade-$($item.Grade),OU=Students,$($IDConfig.AD.userRootOU)"
    #$additionalUserProperties.ADOrganizationalUnitTrash       = "OU=$($item.GradYear),OU=Students,OU=Trash,$($IDConfig.AD.userRootOU)"

    #$additionalUserProperties.GoogleOrganizationalUnit        = "$($IDConfig.Google.userRootOU)/Students/Grade-$($item.Grade)"
    #$additionalUserProperties.GoogleOrganizationalUnitTrash   = "/Trash/Students/$($item.GradYear)"

    #$additionalUserProperties.Building                        = $item.Building
    #$additionalUserProperties.JobTitle                        = "Student - Grade $(Get-StudentGrade -gradYear $item.GradYr -gradeAdvanceDate $IDConfig.Student.GradeAdvanceDate)"
    #$additionalUserProperties.Word                            = $item.Word

    return $additionalUserProperties
}