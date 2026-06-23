function Add-TargetDataGoogle {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        $SourceData,

        [Parameter(Mandatory)]
        $GoogleData
    )

    foreach ($item in $SourceData) {
        $obj = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            $obj[$property.Name] = $property.Value
        }

        if ($GoogleData.LookupByID) {
            $googleObject = $GoogleData.LookupByID[$item.PersonID]
            $obj["GoogleObject"]                     = $googleObject
            $obj["GoogleCurrentUserID"]              = $googleObject.ID
            $obj["GoogleCurrentUserSuspendedStatus"] = $googleObject.suspended
            $obj["GoogleCurrentGroups"]              = $googleObject.CurrentGroups
        }
        if ($item.PersonID -in $GoogleData.DuplicateUsers.OrgID) {
            $obj["GoogleDuplicateIDStatus"] = "DUPLICATE_ID"
        }

        [PSCustomObject]$obj
    }
}