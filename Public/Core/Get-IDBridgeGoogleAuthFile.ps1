function Get-IDBridgeGoogleAuthFile {
    [CmdletBinding()]
    param ()

    $authPath   = "C:\IDBridge\Auth"

    # Handle the Google Auth file in the Auth folder
    $authFiles = Get-ChildItem -Path $authPath -Filter *.json -File

    if ($authFiles.Count -ne 1) {
        throw "Expected exactly one JSON file in $($authPath), but found $($authFiles.Count)."
    }

    $authFilePath = $authFiles[0].FullName

    # Validate if the file is a valid Google Service Account JSON by checking for a private key
    try {
        $googleAuthContent = Get-Content $authFilePath -Raw | ConvertFrom-Json
    }
    catch {
        Throw "Invalid Google Auth JSON file at $($authFilePath). Error: $_"
    }
    
    if ($googleAuthContent.PSObject.Properties.Name -notcontains "private_key") {
        throw "The Google Auth JSON file does not contain a valid 'private_key'."
    }

    # Return the path
    Write-Host "Loaded valid Google Auth JSON file: $($authFilePath)"
    return $authFilePath
}