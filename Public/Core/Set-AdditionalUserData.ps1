
function Set-AdditionalUserData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $IDConfig,
        [Parameter(Mandatory = $true)]
        $userObject,
        [Parameter(Mandatory = $true)]
        $logFile
    )

    $userObject | Add-Member -MemberType NoteProperty -Name PersonDomain -Value $IDConfig.Staff.DomainName -Force
    $userObject | Add-Member -MemberType NoteProperty -Name UPN -Value ($userObject.Username + "@" + $userObject.PersonDomain) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GroupsAutomatic -Value (Get-UserGroupsStaff -building $userObject.Building -personType $userObject.PersonType -config $IDConfig.GroupsStaff) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name Company -Value $IDConfig.Staff.Company -Force
    
    if ($IDConfig.PersonTypeThree) {
        if ($userObject.PersonType -in $IDConfig.PersonTypeThree) {
            $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "3" -Force
        } else {
            $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "2" -Force
        }
    }

    #AD Specific Data
    $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnit -Value ('OU=' + $userObject.PersonType + ',OU=Staff,' + $IDConfig.AD.userRootOU) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnitTrash -Value ("OU=" + (Get-Date -Format yyyy) + ",OU=Staff,OU=Trash," + $IDConfig.AD.userRootOU) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADPassPrefix -Value $IDConfig.Staff.AD.passPrefix -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADChangePasswordAtLogon -Value $IDConfig.Staff.AD.ChangePasswordAtLogon -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADPasswordType -Value $IDConfig.Staff.AD.PasswordType -Force

    #AD Proposed Groups
    $proposedGroupListAD = @()

    if ($item.GroupsAutomatic) {
        $proposedGroupListAD += $item.GroupsAutomatic
    }

    if (-not [string]::IsNullOrEmpty($item.ApplicationGroups)) {
        $proposedGroupListAD += ($item.ApplicationGroups -split ",").trim()
    }

    if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
        $proposedGroupListAD += ($item.EmailGroups -split ",").trim()
    }

    $userObject | Add-Member -MemberType NoteProperty -Name ADGroupsProposed -Value ($proposedGroupListAD | Select-Object -Unique) -Force

    #Google Specific Data
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnit -Value ($IDConfig.Google.userRootOU + "/Staff/" + $userObject.PersonType) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnitTrash -Value ("/Trash/Staff/" + (Get-Date -Format yyyy)) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GooglePassPrefix -Value $IDConfig.Staff.Google.passPrefix -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleChangeAtNextLogin -Value $IDConfig.Staff.Google.ChangePasswordAtLogon -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GooglePasswordType -Value $IDConfig.Staff.Google.PasswordType -Force

    #Google Proposed Groups
    $proposedGroupListGoogle = @()

    if (-not [string]::IsNullOrEmpty($item.GroupsAutomatic)) {
        $proposedGroupListGoogle += $item.GroupsAutomatic
    }

    if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
        $proposedGroupListGoogle += ($item.EmailGroups -split ",").trim()
    }

    $userObject | Add-Member -MemberType NoteProperty -Name GoogleGroupsProposed -Value ($proposedGroupListGoogle | Select-Object -Unique) -Force

    #Add Active Status
    if ($userObject.TerminationDate -and (Get-Date $userObject.TerminationDate -format "yyyy-MM-dd") -lt (Get-Date -format "yyyy-MM-dd")) {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $false -Force
    } else {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $true -Force
    }

    return $userObject
}