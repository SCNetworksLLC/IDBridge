<#
.SYNOPSIS
Attach current Active Directory state to each source record.

.DESCRIPTION
For every source record, looks up the matching AD user in ADData.LookupByID by PersonID and, when
found, adds ADObject, ADCurrentUserID (ObjectGUID), ADCurrentUserEnabledStatus, and
ADCurrentGroups. Records whose PersonID matches a duplicate EmployeeID are flagged with
ADDuplicateIDStatus = 'DUPLICATE_ID'. Emits a new enriched record per input record.

.PARAMETER SourceData
The source records to enrich. An empty collection is allowed.

.PARAMETER ADData
The AD target snapshot from Get-TargetDataAD (uses its LookupByID and DuplicateUsers).

.OUTPUTS
[PSCustomObject] one enriched record per source record.

.EXAMPLE
$sourceData = Add-TargetDataAD -SourceData $sourceData -ADData $adData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
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