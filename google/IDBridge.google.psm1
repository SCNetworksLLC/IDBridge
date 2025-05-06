<#
.SYNOPSIS
    Retrieves data from a Google API using the provided headers and API URI.

.DESCRIPTION
    This function sends a GET request to a specified Google API endpoint using
    the provided authentication headers. If the API response includes paginated 
    results, it continues to fetch additional pages until all data is retrieved.

.PARAMETER GoogleHeaders
    A hashtable containing the necessary headers for authenticating the request 
    to the Google API (e.g., authorization token, content type).

.PARAMETER APIUri
    A string representing the full URI of the Google API endpoint.

.OUTPUTS
    Returns the retrieved data from the API. If the response is paginated, all pages
    are combined into a single collection before returning.

.EXAMPLE
    $headers = @{
        "Authorization" = "Bearer YOUR_ACCESS_TOKEN"
        "Accept" = "application/json"
    }
    $uri = "https://www.googleapis.com/someapi/v1/resource"

    $result = Get-GoogleData -GoogleHeaders $headers -APIUri $uri

    This example sends a request to the Google API endpoint and retrieves the
    data while handling pagination if necessary.

.NOTES
    - The function assumes that the API response contains a JSON object with 
      a property that holds the relevant data.
    - If more than 500 records exist, the function retrieves additional pages 
      using the `nextPageToken` parameter.
    - The function logs an error if no data is retrieved.
    - Input validation checks for empty headers and invalid API URIs.

    Created by: Sam Cattanach
    Modified: 02/18/2025 09:30:19 AM   
#>
function Get-GoogleData {
    param (
        [Parameter(Mandatory)]
        [hashtable]$GoogleHeaders,  # Authentication headers for the Google API request

        [Parameter(Mandatory)]
        [string]$APIUri  # The Google API endpoint URI
    )

    # Validate GoogleHeaders - Ensure it's not empty
    if (-not $GoogleHeaders -or $GoogleHeaders.Count -eq 0) {
        Write-Log -Path $logFile -Message "Google: Failed to fetch data" -Level Error
        Throw "Invalid input: GoogleHeaders cannot be empty."
    }

    # Validate APIUri - Ensure it's a valid URL format
    if ($APIUri -notmatch "^https?:\/\/[\w\-]+(\.[\w\-]+)+[/#?]?.*$") {
        Write-Log -Path $logFile -Message "Google: Failed to fetch data" -Level Error
        Throw "Invalid input: APIUri must be a valid URL: $($APIUri)"
    }

    # Send the initial request to the Google API
    try {
        $request = Invoke-RestMethod -Uri $APIUri -Headers $GoogleHeaders -Method Get
    } catch {
        Write-Log -Path $logFile -Message "Google: Failed to fetch data" -Level Error
        Throw "Failed to fetch data from Google API $($APIUri): $_"
    }

    # Identify the primary data object within the response
    $dataType = $request | Get-Member -MemberType NoteProperty | Where-Object { $_.Definition -like "Object*" } | Select-Object -ExpandProperty Name
    $data = $request.$dataType

    # Handle pagination: Fetch additional data if a nextPageToken exists
    while ($request.nextPageToken) {
        $requestUri = ($APIUri + "&pageToken=" + $request.nextPageToken)
        
        try {
            # Send a request for the next page
            $request = Invoke-RestMethod -Uri $requestUri -Headers $GoogleHeaders -Method Get
        } catch {
            Write-Host "Failed to fetch additional data from API: $_"
            return $data
        }

        # Append new data to the existing dataset
        $data += $request.$dataType
    }

    Write-Log -Path $logFile -Message "Google: Successfully retrieved $($dataType)"
    return $data
}



<#
.SYNOPSIS
    Creates a new organizational unit (OU) in Google Workspace by specifying a full path.
    This function sends a POST request to the Google Admin SDK API to create the new OU under a parent organizational unit.

.DESCRIPTION
    The New-GoogleOrganizationalUnit function allows you to create a new organizational unit (OU) in Google Workspace.
    The function accepts the full path of the new OU and makes a POST request to the Google Admin API to create it. The new OU
    is created under a parent OU, which is determined based on the provided full path. The function will also handle logging 
    of responses and errors.

.PARAMETER NewOrgUnitFullPath
    The full path of the new organizational unit to be created, starting with the root (e.g., "/School/Grade5"). 
    This is a mandatory parameter and must be a valid organizational unit path.

.PARAMETER tokenInformation
    A hashtable containing OAuth authentication headers. This is a mandatory parameter and is used for API request authentication.

.EXAMPLE
    New-GoogleOrganizationalUnit -NewOrgUnitFullPath "/School/Grade5" -tokenInformation $authToken

    Creates a new organizational unit "Grade5" under the "School" organizational unit in Google Workspace.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2025-03-06
    Purpose: To automate the creation of new organizational units in Google Workspace.

.LINK
    https://developers.google.com/admin-sdk/directory/reference/rest/v1/orgunits
#>

function New-GoogleOrganizationalUnit() {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]  # NewOrgUnitFullPath is mandatory to specify the full path of the new organizational unit
        [string]$NewOrgUnitFullPath,

        [parameter(Mandatory=$true)]  # Hashtable is mandatory and contains OAuth authentication headers
        [hashtable]$tokenInformation  
    )

    # Split the NewOrgUnitFullPath into parts by "/" and remove any empty entries (because the path starts with "/")
    $parts = $NewOrgUnitFullPath -split "/" | Where-Object { $_ -ne "" }

    # Determine the parent organizational unit and the last organizational unit to be created
    if ($parts.Count -gt 1) {
        $parentOU = "/" + ($parts[0..($parts.Count - 2)] -join "/")  # Join all but the last part to form the parent path
        $lastOU = $parts[-1]  # The last part of the path is the new organizational unit name
    } else {
        $parentOU = "/"  # If only one part is provided, the parent is the root
        $lastOU = $parts
    }

    Write-Log -Path $logFile -Message "Creating Google Org Unit $NewOrgUnitFullPath"

    # API URL for creating a new organizational unit
    $url = ("https://admin.googleapis.com/admin/directory/v1/customer/my_customer/orgunits")

    # Define the body for the API request, including the new OU name and the parent OU path
    $body = @{
        "name" = $lastOU
        "parentOrgUnitPath" = $parentOU
    } | ConvertTo-Json

    # Send the API request to create the new organizational unit
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $tokenInformation -Body $body -ContentType "application/json"
        Write-Log -Path $logFile -Message "Response: $($response | ConvertTo-Json -Depth 5)"
    } catch {
        # Log any errors that occur during the API request
        Write-Log -Path $logFile -Message "Error: $($_.Exception.Message)" -Level Error
        Write-Log -Path $logFile -Message "Error: $($_)" -Level Error
    }
}



<#
.SYNOPSIS
    Updates an existing user's details in Google Workspace Directory using the Admin SDK API.
    This function allows updating multiple user attributes including email, suspension status, 
    name, organization details, password, and more by sending a PUT request to the Google Admin API.

.DESCRIPTION
    The Update-GoogleUser function facilitates updating an existing user's details in Google Workspace 
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
    Update-GoogleUser -GoogleUserID "user12345" -PrimaryEmail "newemail@example.com" -Suspended "false" 
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

function Update-GoogleUser() {
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

        [parameter(Mandatory=$true)]  # Hashtable containing OAuth authentication headers
        [hashtable]$tokenInformation
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

    # If there are any fields to update, send the API request to update the user
    if ($updateFields) {
        # Construct the API URL for updating the user
        $url = ("https://admin.googleapis.com/admin/directory/v1/users/" + $GoogleUserID)

        # Convert the update fields to JSON format for the request body
        $body = $updateFields | ConvertTo-Json -Depth 10

        # Send the PUT request to the API
        try {
            $response = Invoke-RestMethod -Uri $url -Method Put -Headers $tokenInformation -Body $body -ContentType "application/json"
            Write-Log -Path $logFile -Message "Response: $($response | ConvertTo-Json -Depth 5)"
        } catch {
            # Log any errors that occur during the API request
            Write-Log -Path $logFile -Message "Error: $($_.Exception.Message)" -Level Error
            Write-Log -Path $logFile -Message "Error: $($_)" -Level Error
        }
    }
}


<#
.SYNOPSIS
    Creates a new user in Google Workspace Directory using the Admin SDK API.
    This function constructs the necessary fields for a new user and sends a POST request 
    to the Google Admin API to create the user, including their email, name, department, job title, 
    and other relevant information. Optionally, it can set the password to be changed on the user's 
    next login.

.DESCRIPTION
    The New-GoogleUser function facilitates the creation of a new user in the Google Workspace 
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

.PARAMETER tokenInformation
    A hashtable containing OAuth authentication headers for the API request. This is a mandatory parameter.

.EXAMPLE
    New-GoogleUser -PrimaryEmail "newuser@example.com" -PersonID "12345" -FirstName "John" -LastName "Doe" 
                        -OrgUnitPath "/students" -Password "SecurePassword123" -tokenInformation $authToken

    Creates a new user with the specified details in the "/students" organizational unit, 
    using the provided OAuth token for authentication.

.NOTES
    Version: 1.0
    Author: Sam Cattanach
    Date: 2025-03-06
    Purpose: To automate the creation of new users in Google Workspace Directory.

.LINK
    https://developers.google.com/admin-sdk/directory/reference/rest/v1/users
#>
function New-GoogleUser() {
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
        [String]$ChangeAtNextLogin, # Optional parameter to force password change at the next login
        
        [parameter(Mandatory=$true)]
        [hashtable]$tokenInformation # Mandatory hashtable parameter for OAuth token headers
    )

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
            $response = Invoke-RestMethod -Uri $url -Method Post -Headers $tokenInformation -Body $body -ContentType "application/json"
            
            # Log the response for debugging or tracking purposes
            Write-Log -Path $logFile -Message "Response: $($response | ConvertTo-Json -Depth 5)"
            return $response
        } catch {
            # In case of an error, log the error details
            Write-Log -Path $logFile -Message "Error: $($_.Exception.Message)" -Level Error
            Write-Log -Path $logFile -Message "Error: $($_)" -Level Error
        }
    }
}


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



function Get-ColumnLetter {
    param(
        [Parameter(Mandatory = $true)]
        [int]$ColumnNumber
    )

    [string]$columnLetter = ''
    # Get the multiple of 26
    [int]$prefix = [math]::Floor($ColumnNumber / 26)
    if($prefix -gt 0){
        # Add prefix column
        $columnLetter += [char]$($prefix + 64)
        $ColumnNumber = $ColumnNumber - $($prefix * 26) + 65
    }
    else{
        $ColumnNumber += 65
    }
    # Get column letter
    $columnLetter += [char]$ColumnNumber
    $columnLetter
}


function Set-GSheetData{
    <#
    .Synopsis
        Set values in sheet in specific cell locations or append data to a sheet

    .DESCRIPTION
        Set json data values on a sheet in specific cell ranges, specific cells, or append a new row to a sheet
        Original work by UMN - https://github.com/umn-microsoft-automation/UMN-Google/blob/master/UMN-Google.psm1

    .PARAMETER TokenInformation
        Headers used for authentication.

    .PARAMETER append
        Switch option to append data. See rangeA1 if not appending

    .PARAMETER contenttype
        The contenttype specifies the content type of the web request. Default value is 'application/json'.

    .PARAMETER rangeA1
        Range in A1 notation https://msdn.microsoft.com/en-us/library/bb211395(v=office.12).aspx . The dimensions of the $values you put in MUST fit within this range

    .PARAMETER sheetName
        Name of sheet to set data in

    .PARAMETER spreadSheetID
        ID for the target Spreadsheet.

    .PARAMETER valueInputOption
        Default to RAW. Optionally, you can specify if you want it processed as a formula and so forth.

    .PARAMETER values
        The values to write to the sheet. This should be an array list.  Each list array represents one ROW on the sheet.

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -rangeA1 'A1:B2' -sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values @(@("a","b"),@("c","D"))

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -append 'Append'-sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values $arrayValues

    .EXAMPLE
        Set-GSheetData -TokenInformation $headers -rangeA1 "B2" -sheetName 'My Sheet' -spreadSheetID $spreadSheetID -values @(@('only_one_updated_cell'),@())
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory)]
        [hashtable]$TokenInformation,

        [Parameter(ParameterSetName='Append')]
        [switch]$append,

        [Parameter(ParameterSetName='set')]
        [string]$rangeA1,

        [Parameter(Mandatory)]
        [string]$sheetName,

        [Parameter(Mandatory)]
        [string]$spreadSheetID,

        [string]$valueInputOption = 'RAW',

        [Parameter(Mandatory)]
        [System.Collections.ArrayList]$values,

        [string]$contenttype = 'application/json'
    )

    Begin
    {
        if ($append)
            {
                $method = 'POST'
                $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID/values/$sheetName"+":append?valueInputOption=$valueInputOption"
            }
        else
            {
                $method = 'PUT'
                $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID/values/$sheetName!$rangeA1"+"?valueInputOption=$valueInputOption"
            }
    }

    Process
    {
        $json = @{values=$values} | ConvertTo-Json
        Invoke-RestMethod -Method $method -Uri $uri -Body $json -ContentType $contenttype -Headers $TokenInformation
    }

    End{}
}


function Convert-CellToIndex {
    param (
        [string]$cell
    )

    # Extract column letters and row numbers
    if ($cell -match "^([A-Z]+)(\d+)$") {
        $columnLetters = $matches[1]
        $rowNumber = [int]$matches[2]

        # Convert column letters to zero-based index
        $columnIndex = 0
        foreach ($char in $columnLetters.ToCharArray()) {
            $columnIndex = $columnIndex * 26 + ([int][char]$char - [int][char]'A' + 1)
        }
        $columnIndex-- # Convert to zero-based index

        # Convert row to zero-based index
        $rowIndex = $rowNumber - 1

        return @{
            row = $rowIndex
            column = $columnIndex
        }
    }
    else {
        throw "Invalid cell format. Use format like 'A1', 'B2', etc."
    }
}


# Function to get sheet ID by sheet name
function Get-SheetIdByName {
    param (
        [string]$spreadSheetID,      # Spreadsheet ID
        [string]$sheetName,          # Sheet name
        [hashtable]$TokenInformation # Authentication token headers
    )

    $uri = "https://sheets.googleapis.com/v4/spreadsheets/$spreadSheetID"
    $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $TokenInformation

    # Search for the sheet by name and get its ID
    $sheet = $response.sheets | Where-Object { $_.properties.title -eq $sheetName }
    if ($sheet) {
        return $sheet.properties.sheetId
    } else {
        throw "Sheet '$sheetName' not found."
    }
}

function Set-CheckboxesToFalse {
    param (
        $cells,           # Array of cell references like ["M63", "M65"]
        [string]$spreadSheetID,      # The spreadsheet ID
        [string]$sheetName,         # The sheet name (e.g., "Staff")
        [hashtable]$TokenInformation # Authentication token headers
    )

    # Get the sheet ID from the sheet name
    $sheetId = Get-SheetIdByName -spreadSheetID $spreadSheetID -sheetName $sheetName -TokenInformation $TokenInformation

    $requests = @()

    # Convert each cell into the corresponding request format
    foreach ($cell in $cells) {
        $cellIndexes = Convert-CellToIndex $cell
        $startRowIndex = $cellIndexes.row
        $startColumnIndex = $cellIndexes.column
        $endRowIndex = $startRowIndex + 1
        $endColumnIndex = $startColumnIndex + 1

        $request = @{
            repeatCell = @{
                range = @{
                    sheetId = $sheetId
                    startRowIndex = $startRowIndex
                    startColumnIndex = $startColumnIndex
                    endRowIndex = $endRowIndex
                    endColumnIndex = $endColumnIndex
                }
                cell = @{
                    userEnteredValue = @{
                        boolValue = $false # Uncheck checkbox
                    }
                }
                fields = "userEnteredValue"
            }
        }

        $requests += $request
    }

    # Build the body for the batchUpdate API request
    $body = @{
        requests = $requests
    } | ConvertTo-Json -Depth 10

    # Send the request to the Google Sheets API
    $uri = "https://sheets.googleapis.com/v4/spreadsheets/$($spreadSheetID):batchUpdate"
    Invoke-RestMethod -Method POST -Uri $uri -Body $body -ContentType "application/json" -Headers $TokenInformation
}