<#
.SYNOPSIS
    Creates a new user in Google Workspace Directory using the Admin SDK API.
    This function constructs the necessary fields for a new user and sends a POST request 
    to the Google Admin API to create the user, including their email, name, department, job title, 
    and other relevant information. Optionally, it can set the password to be changed on the user's 
    next login.

.DESCRIPTION
    The New-IDBridgeGoogleUser function facilitates the creation of a new user in the Google Workspace 
    Directory by sending a POST request to the Google Admin API. The function accepts parameters such 
    as primary email, person ID, first name, last name, organizational unit path, and password.
    Optionally, you can provide the user's building (department), job title, and a flag to indicate 
    whether the password should be changed on the next login.

.PARAMETER PrimaryEmail
    The primary email address of the user being created. It is mandatory and must be a valid email address.

.PARAMETER PersonID
    The unique ID of the person in your organization. This is a mandatory field and will be assigned 
    as the external ID for the user.

.PARAMETER FirstName
    The first name of the user. This is a mandatory parameter.

.PARAMETER LastName
    The last name of the user. This is a mandatory parameter.

.PARAMETER Building
    (Optional) The building or department of the user. This will be assigned to the "department" field 
    in the organizations section if provided.

.PARAMETER JobTitle
    (Optional) The job title of the user. This will be assigned to the "title" field in the organizations 
    section if provided.

.PARAMETER OrgUnitPath
    The organizational unit path where the user will be created. This is a mandatory parameter.

.PARAMETER Password
    The password for the new user. This is a mandatory secure string parameter.

.PARAMETER ChangeAtNextLogin
    (Optional) A flag to indicate if the user should be prompted to change their password at the next login.
    If specified, the user's password will be flagged for change.

.EXAMPLE
    New-IDBridgeGoogleUser -PrimaryEmail "newuser@example.com" -PersonID "12345" -FirstName "John" -LastName "Doe" 
                        -OrgUnitPath "/students" -Password "SecurePassword123" -tokenInformation $authToken

    Creates a new user with the specified details in the "/students" organizational unit, 
    using the provided OAuth token for authentication.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2026-06-13
    Purpose: To automate the creation of new users in Google Workspace Directory.

.LINK
    https://developers.google.com/admin-sdk/directory/reference/rest/v1/users
#>
function New-IDBridgeGoogleUser() {
    [cmdletbinding()]
    Param(
        
        [parameter(Mandatory=$true)]
        [string]$PrimaryEmail, # Parameter for the user's primary email (mandatory)
        
        [parameter(Mandatory=$true)]
        [string]$PersonID, # Parameter for the user's unique person ID (mandatory)
        
        [parameter(Mandatory=$true)]
        [string]$FirstName, # Parameter for the user's first name (mandatory)
        
        [parameter(Mandatory=$true)]
        [string]$LastName, # Parameter for the user's last name (mandatory)     
        
        [parameter(Mandatory=$false)]
        [string]$Building, # Optional parameter for the building (department) of the user
                
        [parameter(Mandatory=$false)]
        [string]$JobTitle, # Optional parameter for the user's job title
        
        [parameter(Mandatory=$true)]
        [string]$OrgUnitPath, # Mandatory parameter for the organizational unit path
        
        [parameter(Mandatory=$true)]
        [SecureString]$Password, # Mandatory parameter for the user's password (secure string)
        
        [parameter(Mandatory=$false)]
        [ValidateSet("true", "false")]
        [String]$ChangeAtNextLogin # Optional parameter to force password change at the next login
    )

    #Import Google API Headers (with access token)
    try { $headers = Get-GoogleHeaders } catch { Throw $_ }

    # Create a hashtable to store the new user's details
    $newUserFields = @{}

    # Add the user's primary email to the user fields (ensure it's in lowercase and trimmed)
    $newUserFields["primaryEmail"] = ($PrimaryEmail).ToLower().Trim()

    # Add the user's external ID (PersonID) to the user fields
    $newUserFields["externalIds"] = @(
        @{
            "value" = $PersonID
            "type" = "organization"
        }
    )

    # Add the user's name to the user fields (first name and last name)
    $newUserFields["name"] = @(
        @{
            "givenName" = "$FirstName"
            "familyName" = "$LastName"
        }
    )

    # If building or job title is provided, include them in the user's organization details
    if ($Building -or $JobTitle) {
        if ($Building -and $JobTitle) {
            # Add both department (building) and title (job title)
            $newUserFields["organizations"] = @(
                @{
                    "department" = $Building
                    "title" = $JobTitle
                }
            )
        } elseif ($Building) {
            # Add only the department (building)
            $newUserFields["organizations"] = @(
                @{
                    "department" = $Building
                }
            )
        } elseif ($JobTitle) {
            # Add only the title (job title)
            $newUserFields["organizations"] = @(
                @{
                    "title" = $JobTitle
                }
            )
        }
    }

    # Set the user's organizational unit path
    $newUserFields["orgUnitPath"] = $OrgUnitPath

    # Convert the password from SecureString to plain text and add it to the user fields
    $newUserFields["password"] = $Password | ConvertFrom-SecureString -AsPlainText

    # If the 'ChangeAtNextLogin' flag is set, add this to the user fields
    if ($ChangeAtNextLogin) {
        $newUserFields["changePasswordAtNextLogin"] = $ChangeAtNextLogin
    }

    # If there are any user fields to send, proceed with the API request
    if ($newUserFields) {
        # Define the API URL for creating a new user
        $url = ("https://admin.googleapis.com/admin/directory/v1/users/")

        # Convert the user fields hashtable to JSON format
        $body = $newUserFields | ConvertTo-Json -Depth 10

        # Send the POST request to the Google Admin API
        try {
            # Attempt to invoke the API request with the provided token headers and body
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json"
            
            # Log the response for debugging or tracking purposes
            Write-Log -Message "Response: $($response | ConvertTo-Json -Depth 5)"
            return $response
        } catch {
            # In case of an error, log the error details
            Write-Log -Message "Error: $($_.Exception.Message)" -Level Error
            return $_
        }
    }
}