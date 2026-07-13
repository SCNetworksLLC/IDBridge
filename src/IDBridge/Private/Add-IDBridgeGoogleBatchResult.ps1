<#
.SYNOPSIS
Record write results for one Google batch from its requests and responses.

.DESCRIPTION
Internal helper: after Invoke-GoogleBatchRequest runs, matches each request descriptor to
its response part by ContentId and records one write result per request via
Add-IDBridgeWriteResult:

  - no matching response part  ⇒ failure ("No batch response - batch chunk failed"; this is
    what a whole-chunk HTTP failure looks like, since a failed chunk produces no parts),
  - response StatusCode >= 400 ⇒ failure with the API error message,
  - otherwise                  ⇒ success.

Who the request was for comes from the IdentityMap built while collecting the descriptors -
the ContentId alone only carries a Google user ID or "<PersonID>|<group>" pair.

.PARAMETER Action
The write type these requests represent (Create, Update, Deactivate, GroupAdd, GroupRemove).

.PARAMETER Requests
The request descriptors that were passed to Invoke-GoogleBatchRequest (each has a ContentId).

.PARAMETER Responses
The response objects Invoke-GoogleBatchRequest returned (@{ ContentId; StatusCode; Body }).

.PARAMETER IdentityMap
Hashtable of ContentId -> @{ PersonID; Target } identifying who/what each request was for.

.OUTPUTS
None. Appends one result per request to $script:WriteResults.

.EXAMPLE
Add-IDBridgeGoogleBatchResult -Action Update -Requests $googleBatchRequests -Responses $responses -IdentityMap $identityMap

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-12
#>
function Add-IDBridgeGoogleBatchResult {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("Create", "Update", "Deactivate", "GroupAdd", "GroupRemove")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [object[]]$Requests,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$Responses,

        [Parameter(Mandatory = $true)]
        [hashtable]$IdentityMap
    )

    # Index responses by ContentId for the lookup below
    $responsesById = @{}
    foreach ($response in @($Responses)) {
        if ($null -ne $response -and $null -ne $response.ContentId) {
            $responsesById["$($response.ContentId)"] = $response
        }
    }

    foreach ($request in $Requests) {
        $contentId = "$($request.ContentId)"
        $identity = $IdentityMap[$contentId]

        $resultSplat = @{
            Directory = 'Google'
            Action    = $Action
            PersonID  = "$($identity.PersonID)"
            Target    = "$($identity.Target)"
        }

        $response = $responsesById[$contentId]
        if ($null -eq $response) {
            Add-IDBridgeWriteResult @resultSplat -Success $false -ErrorMessage "No batch response - batch chunk failed"
        }
        elseif ($response.StatusCode -ge 400) {
            Add-IDBridgeWriteResult @resultSplat -Success $false -ErrorMessage "($($response.StatusCode)) $($response.Body.error.message)"
        }
        else {
            Add-IDBridgeWriteResult @resultSplat -Success $true
        }
    }
}
