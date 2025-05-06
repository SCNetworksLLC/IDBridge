function Test-IDBridgeConfiguration {
    [CmdletBinding()]
    param ()

    $basePath = "C:\IDBridge"
    $configPath = Join-Path $basePath "Config"
    $authPath = Join-Path $basePath "Auth"

    $expectedConfigFiles = @(
        "GoogleToken.json",
        "GoogleSheet.json",
        "General.json",
        "Google.json",
        "AD.json",
        "PersonTypeThree.json"
    )

    Write-Host "Checking IDBridge configuration folder structure..." -ForegroundColor Cyan

    if (-not (Test-Path $basePath)) {
        Throw "'Base' folder not found at C:\IDBridge"
    }

    # Check each config file
    if (Test-Path $configPath) {
        foreach ($file in $expectedConfigFiles) {
            $filePath = Join-Path $configPath $file
            if (-Not (Test-Path $filePath)) {
                Throw "Missing config file: $file"
            } else {
                Write-Host "Found config file: $file" -ForegroundColor Green
            }
        }
    } else {
        Throw "'Config' folder not found"
    }

    # Check for exactly 1 JSON file in the Auth folder
    if (Test-Path $authPath) {
        $authJsonFiles = Get-ChildItem -Path $authPath -Filter *.json -File
        if ($authJsonFiles.Count -eq 1) {
            Write-Host "Found 1 authentication JSON file: $($authJsonFiles[0].Name)" -ForegroundColor Green
        } elseif ($authJsonFiles.Count -eq 0) {
            Throw "No authentication JSON file found in 'Auth'"
        } else {
            Throw "Multiple authentication JSON files found in 'Auth'"
        }
    } else {
        Throw "'Auth' folder not found"
    }
    
    Write-Host "All required configuration files are present." -ForegroundColor Green


}