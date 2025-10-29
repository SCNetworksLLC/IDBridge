
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

    # Staff Specific Data
    if ($userObject.PersonTypeGeneric -eq "Staff") {
        $userObject | Add-Member -MemberType NoteProperty -Name PersonDomain -Value $IDConfig.General.staffDomainName -Force
        $userObject | Add-Member -MemberType NoteProperty -Name UPN -Value ($userObject.Username + "@" + $userObject.PersonDomain) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GroupsAutomatic -Value (Get-UserGroupsStaff -building $userObject.Building -personType $userObject.PersonType -config $IDConfig.GroupsStaff) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name Company -Value $IDConfig.General.company -Force
        
        if ($IDConfig.PersonTypeThree) {
            if ($userObject.PersonType -in $IDConfig.PersonTypeThree) {
                $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "3" -Force
            } else {
                $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "2" -Force
            }
        }

        #AD Specific Data
        $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnit -Value ('OU=' + $userObject.PersonType + ',OU=' + $userObject.PersonTypeGeneric + "," + $IDConfig.AD.userRootOU) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnitTrash -Value ("OU=" + (Get-Date -Format yyyy) + ",OU=" + $userObject.PersonTypeGeneric + ",OU=Trash," + $IDConfig.AD.userRootOU) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADPassPrefix -Value $IDConfig.AD.passPrefix -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADChangePasswordAtLogon -Value $IDConfig.AD.staffChangePasswordAtLogon -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADPasswordType -Value $IDConfig.AD.staffPasswordType -Force

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
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnit -Value ($IDConfig.Google.userRootOU + "/" + $userObject.PersonTypeGeneric + '/' + $userObject.PersonType) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnitTrash -Value ("/Trash/" + $userObject.PersonTypeGeneric + "/" + (Get-Date -Format yyyy)) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GooglePassPrefix -Value $IDConfig.Google.passPrefix -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleChangeAtNextLogin -Value $IDConfig.Google.staffChangePasswordAtLogon -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GooglePasswordType -Value $IDConfig.Google.staffPasswordType -Force

        #Google Proposed Groups
        $proposedGroupListGoogle = @()

        if (-not [string]::IsNullOrEmpty($item.GroupsAutomatic)) {
            $proposedGroupListGoogle += $item.GroupsAutomatic
        }

        if (-not [string]::IsNullOrEmpty($item.EmailGroups)) {
            $proposedGroupListGoogle += ($item.EmailGroups -split ",").trim()
        }

        $userObject | Add-Member -MemberType NoteProperty -Name GoogleGroupsProposed -Value ($proposedGroupListGoogle | Select-Object -Unique) -Force
    }

    #Student Specific Data
    if ($userObject.PersonTypeGeneric -eq "Student") {
        #Student Data
        $userObject | Add-Member -MemberType NoteProperty -Name PersonDomain -Value $IDConfig.General.studentDomainName -Force
        $userObject | Add-Member -MemberType NoteProperty -Name UPN -Value ($userObject.Username + "@" + $userObject.PersonDomain) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GroupsAutomatic -Value (Get-UserGroupsStudent -building $userObject.Building -grade $userObject.PersonType -config $IDConfig.GroupsStudent) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name Company -Value $IDConfig.General.company -Force

        $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "1" -Force

        $userObject | Add-Member -MemberType NoteProperty -Name grade -Value (Get-StudentGrade -gradYear $userObject.PersonType -gradeAdvanceDate $IDConfig.General.studentGradeAdvanceDate) -Force

        #AD Specific Data
        $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnit -Value ('OU=Grade-' + $userObject.grade + ',OU=' + $userObject.PersonTypeGeneric + "," + $IDConfig.AD.userRootOU) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnitTrash -Value ("OU=" + $userObject.PersonType + ",OU=" + $userObject.PersonTypeGeneric + ",OU=Trash," + $IDConfig.AD.userRootOU) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADPassPrefix -Value $IDConfig.AD.passPrefix -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADChangePasswordAtLogon -Value $IDConfig.AD.studentChangePasswordAtLogon -Force
        $userObject | Add-Member -MemberType NoteProperty -Name ADPasswordType -Value $IDConfig.AD.studentPasswordType -Force
        
        #Google Specific Data
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnit -Value ($IDConfig.Google.userRootOU + "/" + $userObject.PersonTypeGeneric + '/Grade-' + $userObject.grade) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnitTrash -Value ("/Trash/" + $userObject.PersonTypeGeneric + "/" + $userObject.PersonType) -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GooglePassPrefix -Value $IDConfig.Google.passPrefix -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GoogleChangeAtNextLogin -Value $IDConfig.Google.studentChangePasswordAtLogon -Force
        $userObject | Add-Member -MemberType NoteProperty -Name GooglePasswordType -Value $IDConfig.Google.studentPasswordType -Force
    }

    #Add Active Status
    if ($userObject.TerminationDate -and (Get-Date $userObject.TerminationDate -format "yyyy-MM-dd") -lt (Get-Date -format "yyyy-MM-dd")) {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $false -Force
    } else {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $true -Force
    }

    return $userObject
}