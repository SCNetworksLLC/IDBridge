function Update-GoogleGroupMembers() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # GroupEmail is mandatory to specify the email address of the group
        [string]$GroupEmail,

        [parameter(Mandatory=$true)]  # Parameter for the user's unique person ID (mandatory)
        [string]$PersonID,

        [parameter(Mandatory=$true)]  # UpdateType is mandatory to specify adding users to the group or removing users from the group
        [ValidateSet("Add", "Remove")]
        [string]$UpdateType
    )

    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }

    $updateParams = @{}

    if ($UpdateType -eq "Add") {
        $updateParams["Uri"] = ("https://admin.googleapis.com/admin/directory/v1/groups/$GroupEmail/members")
        $updateParams["Method"] = 'Post'
        $updateParams["Headers"] = $headers
        $updateParams["ContentType"] = 'application/json'
        $updateParams["Body"] = @{
            "id" = $PersonID
            "role" = "MEMBER"
        } | ConvertTo-Json
    }

    if ($UpdateType -eq "Remove") {
        $updateParams["Uri"] = ("https://admin.googleapis.com/admin/directory/v1/groups/$GroupEmail/members/$PersonID")
        $updateParams["Method"] = 'Delete'
        $updateParams["Headers"] = $headers
    }

    # Send the API request
    try {
        $response = Invoke-RestMethod @updateParams
        Write-Log -Message "Response: $($response | ConvertTo-Json -Depth 5)"
        
    } catch {
        # Log any errors that occur during the API request
        Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
        return $_
    }
}