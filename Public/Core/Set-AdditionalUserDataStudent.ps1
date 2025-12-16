
function Set-AdditionalUserDataStudent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $IDConfig,
        [Parameter(Mandatory = $true)]
        $userObject,
        [Parameter(Mandatory = $true)]
        $logFile
    )

    #Student Data
    if ($userObject.GradYear -and !($userObject.Grade)) {
        $userObject | Add-Member -MemberType NoteProperty -Name grade -Value (Get-StudentGrade -gradYear $userObject.GradYear -gradeAdvanceDate $IDConfig.Student.GradeAdvanceDate) -Force
    }

    $userObject | Add-Member -MemberType NoteProperty -Name PersonDomain -Value $IDConfig.Student.DomainName -Force
    $userObject | Add-Member -MemberType NoteProperty -Name UPN -Value ($userObject.Username + "@" + $userObject.PersonDomain) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GroupsAutomatic -Value (Get-UserGroupsStudent -building $userObject.Building -grade $userObject.Grade -config $IDConfig.GroupsStudent) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name Company -Value $IDConfig.Student.company -Force

    $userObject | Add-Member -MemberType NoteProperty -Name PersonTypeID -Value "1" -Force


    #AD Specific Data
    $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnit -Value ('OU=Grade-' + $userObject.grade + ',OU=Students,' + $IDConfig.AD.userRootOU) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADOrganizationalUnitTrash -Value ("OU=" + $userObject.GradYear + ",OU=Students,OU=Trash," + $IDConfig.AD.userRootOU) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADPassPrefix -Value $IDConfig.Student.$($userObject.grade).AD.passPrefix -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADChangePasswordAtLogon -Value $IDConfig.Student.$($userObject.grade).AD.ChangePasswordAtLogon -Force
    $userObject | Add-Member -MemberType NoteProperty -Name ADPasswordType -Value $IDConfig.Student.$($userObject.grade).AD.PasswordType -Force
    
    #Google Specific Data
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnit -Value ($IDConfig.Google.userRootOU + '/Students/Grade-' + $userObject.grade) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleOrganizationalUnitTrash -Value ("/Trash/Students/" + $userObject.PersonType) -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GooglePassPrefix -Value $IDConfig.Student.$($userObject.grade).Google.passPrefix -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GoogleChangeAtNextLogin -Value $IDConfig.Student.$($userObject.grade).Google.ChangePasswordAtLogon -Force
    $userObject | Add-Member -MemberType NoteProperty -Name GooglePasswordType -Value $IDConfig.Student.$($userObject.grade).Google.PasswordType -Force

    #Add Active Status
    if ($userObject.TerminationDate -and (Get-Date $userObject.TerminationDate -format "yyyy-MM-dd") -lt (Get-Date -format "yyyy-MM-dd")) {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $false -Force
    } else {
        $userObject | Add-Member -MemberType NoteProperty -Name IDBActive -Value $true -Force
    }

    return $userObject
}