<#
.SYNOPSIS
Attach current Google Workspace state to each source record.

.DESCRIPTION
For every source record, looks up the matching Google user in GoogleData.LookupByID by PersonID
and, when found, adds GoogleObject, GoogleCurrentUserID (ID), GoogleCurrentUserSuspendedStatus,
GoogleCurrentGroups, and GoogleCurrentLicenses. Records whose PersonID matches a duplicate
externalId are flagged with GoogleDuplicateIDStatus = 'DUPLICATE_ID'. Emits a new enriched
record per input record.

.PARAMETER SourceData
The source records to enrich. An empty collection is allowed.

.PARAMETER GoogleData
The Google target snapshot from Get-TargetDataGoogle (uses its LookupByID and DuplicateUsers).

.OUTPUTS
[PSCustomObject] one enriched record per source record.

.EXAMPLE
$sourceData = Add-TargetDataGoogle -SourceData $sourceData -GoogleData $googleData

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
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
            # Deactivated = suspended OR archived (archive is the deactivation state; pre-archive
            # suspends are grandfathered). Stays $null when there is no Google account — that null
            # is what keeps accountless users out of the deactivate list.
            $obj["GoogleCurrentUserSuspendedStatus"] = if ($googleObject) { $googleObject.suspended -or $googleObject.archived } else { $null }
            $obj["GoogleCurrentGroups"]              = $googleObject.CurrentGroups
            $obj["GoogleCurrentLicenses"]            = $googleObject.CurrentLicenses
        }
        if ($item.PersonID -in $GoogleData.DuplicateUsers.OrgID) {
            $obj["GoogleDuplicateIDStatus"] = "DUPLICATE_ID"
        }

        [PSCustomObject]$obj
    }
}