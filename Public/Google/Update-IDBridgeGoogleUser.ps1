<#
.SYNOPSIS
    Updates an existing user's details in Google Workspace Directory using the Admin SDK API.
    This function allows updating multiple user attributes including email, suspension status, 
    name, organization details, password, and more by sending a PUT request to the Google Admin API.

.DESCRIPTION
    The Update-IDBridgeGoogleUser function facilitates updating an existing user's details in Google Workspace 
    Directory. The function accepts parameters for user-specific information such as primary email, suspension status,
    person ID, first name, last name, organizational unit path, password, and more. The function sends the updated 
    user information via a PUT request to the Google Admin API.

.PARAMETER GoogleUserID
    The unique Google user ID of the user being updated. This is a mandatory parameter and is used to identify 
    the user for updating.

.PARAMETER PrimaryEmail
    (Optional) The primary email address of the user. If provided, it will update the user's email to this value.

.PARAMETER Suspended
    (Optional) A value indicating whether the user is suspended. Accepts "true" or "false" values.

.PARAMETER PersonID
    (Optional) The unique person ID of the user. If provided, it will be added as the external ID for the user.

.PARAMETER FirstName
    (Optional) The first name of the user. If provided along with the last name, it will update the user's name.

.PARAMETER LastName
    (Optional) The last name of the user. If provided along with the first name, it will update the user's name.

.PARAMETER Building
    (Optional) The department or building of the user. If provided, it will be added to the organization's field.

.PARAMETER JobTitle
    (Optional) The job title of the user. If provided, it will be added to the organization's field.

.PARAMETER OrgUnitPath
    (Optional) The organizational unit path where the user will be moved. If provided, it will update the user's 
    organizational unit path.

.PARAMETER Password
    (Optional) The password for the user. If provided, it will update the user's password.

.PARAMETER ChangeAtNextLogin
    (Optional) A flag to indicate if the user should be prompted to change their password at the next login. 
    Accepts "true" or "false".

.PARAMETER tokenInformation
    A hashtable containing OAuth authentication headers for the API request. This is a mandatory parameter and is 
    used for authenticating the request to the Google Admin API.

.EXAMPLE
    Update-IDBridgeGoogleUser -GoogleUserID "user12345" -PrimaryEmail "newemail@example.com" -Suspended "false" 
                           -FirstName "John" -LastName "Doe" -Password "NewPassword123" -tokenInformation $authToken

    Updates the user with the Google user ID "user12345", changing the email to "newemail@example.com", 
    un-suspending the user, updating the user's name, and setting a new password.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2025-03-06
    Purpose: To automate the process of updating user information in Google Workspace Directory.

.LINK
    https://developers.google.com/admin-sdk/directory/reference/rest/v1/users
#>

function Update-IDBridgeGoogleUser() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # Google User ID is required to identify which user to update
        [string]$GoogleUserID,

        [parameter(Mandatory=$false)]  # Primary email is optional and will update the user's email if provided
        [string]$PrimaryEmail,

        [parameter(Mandatory=$false)]  # Suspension status is optional; set to "true" or "false"
        [ValidateSet("true", "false")]
        [string]$Suspended,

        [parameter(Mandatory=$false)]  # PersonID is optional; provides an external ID for the user
        [string]$PersonID,

        [parameter(Mandatory=$false)]  # First name is optional, but both first and last name are needed together
        [string]$FirstName,
        
        [parameter(Mandatory=$false)]  # Last name is optional, but both first and last name are needed together
        [string]$LastName,
                
        [parameter(Mandatory=$false)]  # Building (department) is optional
        [string]$Building,
                
        [parameter(Mandatory=$false)]  # Job title is optional
        [string]$JobTitle,

        [parameter(Mandatory=$false)]  # Organizational unit path is optional
        [string]$OrgUnitPath,

        [parameter(Mandatory=$false)]  # Password is optional and will update the user's password if provided
        [SecureString]$Password,
        
        [parameter(Mandatory=$false)]  # Change password at next login is optional
        [ValidateSet("true", "false")]
        [String]$ChangeAtNextLogin,

        [parameter(Mandatory=$false)]  # RemoveAlias is optional; if provided, it will remove the alias defined here
        [string]$RemoveAlias,

        [parameter(Mandatory=$true)]  # Hashtable containing OAuth authentication headers
        [hashtable]$tokenInformation,

        [parameter(Mandatory=$true)]
        $logFile
    )

    # Create an empty hashtable to store fields that will be updated
    $updateFields = @{}

    # If PrimaryEmail is provided, add it to the update fields and ensure it's in lowercase and trimmed
    if ($PrimaryEmail) {
        $updateFields["primaryEmail"] = ($PrimaryEmail).ToLower().Trim()
    }

    # If Suspended status is provided, add it to the update fields
    if ($Suspended) {
        $updateFields["suspended"] = $Suspended
    }

    # If PersonID is provided, add it to the external IDs
    if ($PersonID){
        $updateFields["externalIds"] = @(
            @{
                "value" = $PersonID
                "type" = "organization"
            }
        )
    }

    # If either FirstName or LastName is provided, update the user's name
    if ($FirstName -or $LastName) {
        if ($FirstName -and $LastName) {
            $updateFields["name"] = @(
                @{
                    "givenName" = "$FirstName"
                    "familyName" = "$LastName"
                }
            )
        } else {
            Write-Log -Path $logFile -Message "Error: Please specify both first AND last name" -Level Error
            return
        }
    }

    # If either Building or JobTitle is provided, update the organization's fields
    if ($Building -or $JobTitle) {
        if ($Building -and $JobTitle) {
            $updateFields["organizations"] = @(
                @{
                    "department" = $Building
                    "title" = $JobTitle
                }
            )
        } elseif ($Building) {
            $updateFields["organizations"] = @(
                @{
                    "department" = $Building
                }
            )
        } elseif ($JobTitle) {
            $updateFields["organizations"] = @(
                @{
                    "title" = $JobTitle
                }
            )
        }
    }

    # If OrgUnitPath is provided, update the user's organizational unit path
    if ($OrgUnitPath) {
        $updateFields["orgUnitPath"] = $OrgUnitPath
    }

    # If ChangeAtNextLogin is provided, add it to the update fields
    if ($ChangeAtNextLogin) {
        $updateFields["changePasswordAtNextLogin"] = $ChangeAtNextLogin
    }

    # If Password is provided, convert it from SecureString to plain text and add to the update fields
    if ($Password) {
        $updateFields["password"] = $Password | ConvertFrom-SecureString -AsPlainText
    }

    if ($RemoveAlias) {
        try {
            #Get the user that currently has the alias
            $aliasLookupUri = "https://admin.googleapis.com/admin/directory/v1/users/$($RemoveAlias)"
            $aliasUser = Invoke-RestMethod -Uri $aliasLookupUri -Headers $tokenInformation -Method GET
            Write-Log -Path $logFile -Message "Google: Remove Alias User: $($aliasUser | ConvertTo-Json -Depth 5)"

            if ($aliasUser -and $RemoveAlias -ne $aliasUser.primaryEmail) {
                #Remove alias from current owner
                $removeAliasUri = "https://admin.googleapis.com/admin/directory/v1/users/$($aliasUser.id)/aliases/$($RemoveAlias)"
                Invoke-RestMethod -Uri $removeAliasUri -Headers $tokenInformation -Method DELETE -ErrorAction Stop
                Write-Log -Path $logFile -Message "Google: Alias: $($RemoveAlias) Removed from user $($aliasUser.primaryEmail)"
            } elseif ($RemoveAlias -eq $aliasUser.primaryEmail) {
                Write-Log -Path $logFile -Message "Google: Can't Remove Alias $($RemoveAlias) - Alias is a primary email for $($aliasUser.name | ConvertTo-Json -Depth 5)" -Level Error
            } else {
                Write-Log -Path $logFile -Message "Google: No alias user found for alias $RemoveAlias" -Level Warn
            }
        }
        catch {
            return $_
        }
    }

    # If there are any fields to update, send the API request to update the user
    if ($updateFields) {
        # Construct the API URL for updating the user
        $url = ("https://admin.googleapis.com/admin/directory/v1/users/" + $GoogleUserID)

        # Convert the update fields to JSON format for the request body
        $body = $updateFields | ConvertTo-Json -Depth 10

        # Send the PUT request to the API
        try {
            $response = Invoke-RestMethod -Uri $url -Method Put -Headers $tokenInformation -Body $body -ContentType "application/json"
            Write-Log -Path $logFile -Message "Google: Update Response: $($response | ConvertTo-Json -Depth 5)"
        } catch {
            # Log any errors that occur during the API request
            Write-Log -Path $logFile -Message "Google: $($_.Exception.Message)" -Level Error
            return $_
        }
    }
}