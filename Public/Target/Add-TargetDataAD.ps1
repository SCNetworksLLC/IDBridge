function Add-TargetDataAD {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $SourceData,

        [Parameter(Mandatory)]
        $ADData
    )

    foreach ($item in $SourceData) {
        $obj = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            $obj[$property.Name] = $property.Value
        }

        if ($ADData.LookupByID) {
            $adObject = $ADData.LookupByID[$item.PersonID]
            $obj["ADObject"]                   = $adObject
            $obj["ADCurrentUserID"]            = $adObject.ObjectGUID
            $obj["ADCurrentUserEnabledStatus"] = $adObject.Enabled
            $obj["ADCurrentGroups"]            = $adObject.CurrentGroups
        }
        if ($item.PersonID -in $ADData.DuplicateUsers.employeeID) {
            $obj["ADDuplicateIDStatus"] = "DUPLICATE_ID"
        }

        [PSCustomObject]$obj
    }
}