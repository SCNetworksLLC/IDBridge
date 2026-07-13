<#
.SYNOPSIS
    Creates a new organizational unit (OU) in Google Workspace by specifying a full path.
    This function sends a POST request to the Google Admin SDK API to create the new OU under a parent organizational unit.

.DESCRIPTION
    The New-IDBridgeGoogleOrgUnit function allows you to create a new organizational unit (OU) in Google Workspace.
    The function accepts the full path of the new OU and makes a POST request to the Google Admin API to create it. The new OU
    is created under a parent OU, which is determined based on the provided full path. The function will also handle logging 
    of responses and errors.

.PARAMETER OrgUnit
    The full path of the new organizational unit to be created, starting with the root (e.g., "/School/Grade5").
    This is a mandatory parameter and must be a valid organizational unit path.

.EXAMPLE
    New-IDBridgeGoogleOrgUnit -OrgUnit "/School/Grade5"

    Creates a new organizational unit "Grade5" under the "School" organizational unit in Google Workspace.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2025-03-06
    Purpose: To automate the creation of new organizational units in Google Workspace.

.LINK
    https://developers.google.com/admin-sdk/directory/reference/rest/v1/orgunits
#>

function New-IDBridgeGoogleOrgUnit() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # OrgUnit is mandatory to specify the full path of the new organizational unit
        [string]$OrgUnit
    )

    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }

    # Split the NewOrgUnitFullPath into parts by "/" and remove any empty entries (because the path starts with "/")
    $parts = $OrgUnit -split "/" | Where-Object { $_ -ne "" }

    # Determine the parent organizational unit and the last organizational unit to be created
    if ($parts.Count -gt 1) {
        $parentOU = "/" + ($parts[0..($parts.Count - 2)] -join "/")  # Join all but the last part to form the parent path
        $lastOU = $parts[-1]  # The last part of the path is the new organizational unit name
    } else {
        $parentOU = "/"  # If only one part is provided, the parent is the root
        $lastOU = $parts
    }

    Write-Log -Message "Google: Applying: Creating Org Unit $OrgUnit"

    # API URL for creating a new organizational unit (real customer ID from config —
    # my_customer doesn't resolve for the service account's own token)
    $url = ("https://admin.googleapis.com/admin/directory/v1/customer/$($IDConfig.Google.customerID)/orgunits")

    # Define the body for the API request, including the new OU name and the parent OU path
    $body = @{
        "name" = $lastOU
        "parentOrgUnitPath" = $parentOU
    } | ConvertTo-Json

    # Send the API request to create the new organizational unit
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json"
        Write-Log -Message "Response: $($response | ConvertTo-Json -Depth 5)"
    } catch {
        # Log the error, then rethrow - Invoke-IDBridge treats a failed OU creation as fatal
        Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
        Throw
    }
}