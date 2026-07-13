<#
.SYNOPSIS
    Sends multiple Google Directory API calls in a single multipart/mixed batch request.

.DESCRIPTION
    The Invoke-GoogleBatchRequest function takes a list of request descriptors (method, path,
    body, content ID) and sends them to the Google Admin SDK Directory API batch endpoint in
    chunks. Each chunk is one HTTP round trip containing up to the chunk size of individual
    API calls, which substantially reduces wall-clock time on large runs. Note batching does
    NOT reduce quota usage - every inner call still counts against the Directory API rate
    limit - and Google does not guarantee execution order of the calls inside one batch, so
    only order-independent calls (e.g. all of one change type) should share a batch.

    The multipart response is parsed manually (Invoke-RestMethod cannot parse multipart/mixed):
    each part's inner HTTP status and JSON body are extracted and returned keyed by the
    Content-ID supplied on the matching request. Per-item failures are logged as errors and
    included in the results; they do not stop the remaining items or chunks.

.PARAMETER Requests
    An array of request descriptors. Each descriptor is a hashtable with:
      Method    - the HTTP method of the inner call (e.g. "PUT", "POST")
      Path      - the API path relative to the host (e.g. "/admin/directory/v1/users/123")
      Body      - (optional) the JSON request body as a string
      ContentId - an identifier echoed back on the matching response part
    New-IDBridgeGoogleUser and Update-IDBridgeGoogleUser produce these with -AsBatchRequest.

.PARAMETER BatchUri
    The batch endpoint to post to. Defaults to the Admin SDK Directory API batch endpoint.

.OUTPUTS
    [PSCustomObject[]] one per inner call: @{ ContentId; StatusCode; Body } where Body is the
    parsed JSON response (or raw text if not JSON). StatusCode >= 400 indicates that item failed.

.EXAMPLE
    $requests = $GoogleUsersToUpdate | ForEach-Object { $s = $_.Splat; Update-IDBridgeGoogleUser @s -AsBatchRequest }
    $results = Invoke-GoogleBatchRequest -Requests $requests

    Sends all pending user updates in batches and returns the per-user results.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2026-07-05
    Purpose: To reduce run time by batching Google Directory API write calls.

.LINK
    https://developers.google.com/admin-sdk/directory/v1/guides/batch
#>
function Invoke-GoogleBatchRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Requests,

        [Parameter(Mandatory = $false)]
        [string]$BatchUri = "https://admin.googleapis.com/batch/admin/directory_v1"
    )

    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }

    # Google allows up to 1000 calls per batch, but large write batches are known to trigger
    # rate limiting (503s); 50 per batch is the size Google recommends.
    $batchSize = 50

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    for ($offset = 0; $offset -lt $Requests.Count; $offset += $batchSize) {
        $chunk = $Requests[$offset..([Math]::Min($offset + $batchSize, $Requests.Count) - 1)]
        $boundary = "batch_" + [guid]::NewGuid().ToString("N")

        # Build the multipart/mixed request body: one application/http part per inner call
        $bodyBuilder = [System.Text.StringBuilder]::new()
        foreach ($request in $chunk) {
            [void]$bodyBuilder.Append("--$boundary`r`n")
            [void]$bodyBuilder.Append("Content-Type: application/http`r`n")
            [void]$bodyBuilder.Append("Content-ID: <$($request.ContentId)>`r`n`r`n")
            [void]$bodyBuilder.Append("$($request.Method) $($request.Path)`r`n")
            if ($request.Body) {
                [void]$bodyBuilder.Append("Content-Type: application/json`r`n`r`n")
                [void]$bodyBuilder.Append("$($request.Body)`r`n")
            } else {
                [void]$bodyBuilder.Append("`r`n")
            }
        }
        [void]$bodyBuilder.Append("--$boundary--`r`n")

        Write-Log -Message "Google: Sending batch request with $($chunk.Count) calls" -Level Trace

        try {
            # Body is passed as UTF-8 bytes so names with non-ASCII characters survive intact
            $response = Invoke-WebRequest -Uri $BatchUri -Method Post -Headers $headers -ContentType "multipart/mixed; boundary=$boundary" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyBuilder.ToString()))
        } catch {
            Write-Log -Message "Google: Batch request failed: $($_.Exception.Message)" -Level Error
            continue
        }

        # The response uses its own boundary - read it from the response Content-Type header
        $responseContentType = [string]$response.Headers.'Content-Type'
        if ($responseContentType -notmatch 'boundary=(\S+)') {
            Write-Log -Message "Google: Batch response was not multipart (Content-Type: $responseContentType)" -Level Error
            continue
        }
        $responseBoundary = $Matches[1]

        # multipart/mixed is not a text type Invoke-WebRequest decodes, so Content arrives as bytes
        $responseContent = if ($response.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }

        foreach ($part in ($responseContent -split "--$([regex]::Escape($responseBoundary))")) {
            if ([string]::IsNullOrWhiteSpace($part) -or $part.Trim() -eq '--') { continue }

            # Each part is: outer headers (incl. Content-ID) / inner HTTP status line + headers / body
            $contentId = if ($part -match 'Content-ID:\s*<?response-([^>\r\n]+)>?') { $Matches[1] } else { $null }
            $statusCode = if ($part -match 'HTTP/\d\.\d\s+(\d{3})') { [int]$Matches[1] } else { 0 }

            $sections = $part -split "`r`n`r`n", 3
            $partBody = $null
            if ($sections.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($sections[2])) {
                try { $partBody = $sections[2] | ConvertFrom-Json } catch { $partBody = $sections[2].Trim() }
            }

            if ($statusCode -ge 400) {
                Write-Log -Message "Google: Batch item $contentId failed ($statusCode): $($partBody.error.message)" -Level Error
            } else {
                Write-Log -Message "Google: Batch Response ($statusCode) for $($contentId): $($partBody | ConvertTo-Json -Depth 5 -Compress)"
            }

            $results.Add([PSCustomObject]@{
                ContentId  = $contentId
                StatusCode = $statusCode
                Body       = $partBody
            })
        }
    }

    return $results
}
