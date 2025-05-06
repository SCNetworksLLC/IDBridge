function Update-GoogleGroupMembers() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # GroupEmail is mandatory to specify the email address of the group
        [string]$GroupEmail,

        [parameter(Mandatory=$true)]  # Parameter for the user's unique person ID (mandatory)
        [string]$PersonID,

        [parameter(Mandatory=$true)]  # UpdateType is mandatory to specify adding users to the group or removing users from the group
        [ValidateSet("Add", "Remove")]
        [string]$UpdateType,

        [parameter(Mandatory=$true)]  # Hashtable is mandatory and contains OAuth authentication headers
        [hashtable]$tokenInformation  
    )

    $updateParams = @{}

    if ($UpdateType -eq "Add") {
        $updateParams["Uri"] = ("https://admin.googleapis.com/admin/directory/v1/groups/$GroupEmail/members")
        $updateParams["Method"] = 'Post'
        $updateParams["Headers"] = $tokenInformation
        $updateParams["ContentType"] = 'application/json'
        $updateParams["Body"] = @{
            "id" = $PersonID
            "role" = "MEMBER"
        } | ConvertTo-Json
    }

    if ($UpdateType -eq "Remove") {
        $updateParams["Uri"] = ("https://admin.googleapis.com/admin/directory/v1/groups/$GroupEmail/members/$PersonID")
        $updateParams["Method"] = 'Delete'
        $updateParams["Headers"] = $tokenInformation
    }

    # Send the API request
    try {
        $response = Invoke-RestMethod @updateParams
        Write-Log -Path $logFile -Message "Response: $($response | ConvertTo-Json -Depth 5)"
        
    } catch {
        # Log any errors that occur during the API request
        Write-Log -Path $logFile -Message "Error: $($_.Exception.Message)" -Level Error
        Write-Log -Path $logFile -Message "Error: $($_)" -Level Error
    }
}