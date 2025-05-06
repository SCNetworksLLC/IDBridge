function Initialize-IDBridge {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [switch]$Force
    )

    $rootPath = "C:\IDBridge"
    $subFolders = @("Auth", "Config", "Logs")
    $configPath = Join-Path $rootPath "Config"

    if (Test-Path $rootPath) {
        if ($Force) {
            $confirmation = Read-Host "The folder '$rootPath' already exists. Are you sure you want to remove and recreate it? (Y/N)"
            if ($confirmation -match '^[Yy]$') {
                try {
                    Remove-Item -Path $rootPath -Recurse -Force -ErrorAction Stop
                    Write-Host "Removed existing folder: $rootPath"
                } catch {
                    Write-Error "Failed to remove existing folder: $_"
                    return
                }
            } else {
                Write-Host "Operation cancelled by user."
                return
            }
        } else {
            Write-Warning "The folder '$rootPath' already exists. Use -Force to remove and recreate it."
            return
        }
    }

    try {
        New-Item -Path $rootPath -ItemType Directory -Force | Out-Null
        foreach ($folder in $subFolders) {
            New-Item -Path (Join-Path $rootPath $folder) -ItemType Directory -Force | Out-Null
        }

        # Define Config Data
        $googleTokenConfig = @{
            adminEmail = "ADMINEMAIL HERE"
        }

        $googleSheetConfig = @{
            sheetID = "1qrZHxMaahh3p3eogQ3tFoAROBNRdo6GaE0heKJgZbPM"
            sheetRange = "Staff"
        }

        $generalConfiguration = @{
            company = "School District of "
            staffDomainName = "marshfieldschools.org"
            studentDomainName = "my.marshfieldschools.org"
            studentGradeAdvanceDate = "06-10"
            studentCount = "3700"
            staffCount = "650"
            safetyPercentage = "75"
        }

        $googleConfiguration = @{
            enabled = $true
            customerID = "C03h0uxpa"
            staffChangePasswordAtLogon = $false
            studentChangePasswordAtLogon = $false
            passPrefix = "Mfld-"
            userRootOU = "/Marshfield"
            randomPassword = $true
            enableGroupProcessing = $true
            enableGroupProcessingRemove = $true
            enableGroupProcessingTrash = $true
            enableGroupProcessingWhatIf = $true
            GroupPrimaryDomainName = "marshfieldschools.org"
        }

        $ADConfiguration = @{
            enabled = $true
            staffChangePasswordAtLogon = $true
            studentChangePasswordAtLogon = $false
            passPrefix = "Mfld-"
            userRootOU = "OU=Marshfield,DC=sdom,DC=local"
            enableGroupProcessing = $true
            enableGroupProcessingRemove = $true
            enableGroupProcessingTrash = $true
            enableGroupProcessingWhatIf = $true
        }

        $personTypeThree = @(
            "Administrator"
            "Teacher"
            "Principal"
            "Secretary"
            "IT"
            "Superintendent"
        )

        $debugConfiguration = @{
            testRun = $false
            readOnly = $false
            skipADCheck = $true
        }
        

        # Write each configuration to its own JSON file
        $configs = @{
            "GoogleToken.json" = $googleTokenConfig
            "GoogleSheet.json" = $googleSheetConfig
            "General.json" = $generalConfiguration
            "Google.json"= $googleConfiguration
            "AD.json" = $ADConfiguration
            "PersonTypeThree.json" = $personTypeThree
            "Debug.json" = $debugConfiguration
        }

        foreach ($file in $configs.Keys) {
            $path = Join-Path $configPath $file
            $json = $configs[$file] | ConvertTo-Json -Depth 5
            $json | Set-Content -Path $path -Encoding UTF8
        }

        Write-Host "Initialized IDBridge structure and created configuration files in '$configPath'"
    } catch {
        Write-Error "Error during initialization: $_"
    }
}


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

function Get-IDBridgeConfiguration {
    [CmdletBinding()]
    param ()

    $configPath = "C:\IDBridge\Config"

    Write-Host "Importing all JSON config files from $($configPath)"

    $IDBridgeConfig = @{}

    # Load all .json config files in the Config folder
    Get-ChildItem -Path $configPath -Filter *.json -File | ForEach-Object {
        try {
            $baseName = $_.BaseName -replace ' ', '_'  # Replace spaces with underscores
            $jsonContent = Get-Content $_.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            $IDBridgeConfig[$baseName] = $jsonContent
            Write-Host "Loaded config: $($baseName)"
        }
        catch {
            Throw "Error getting JSON for file $($baseName): $_"
        }
    }

    Write-Host "All configuration files successfully loaded"

    #region Test Additional Modules
    if ($IDBridgeConfig.AD.enabled -eq $true) {
        #Test AD Module
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Write-Host "Imported Active Directory Module"
        }
        catch {
            Write-Log -Message "AD Powershell Module does not exit on the local machine: $_" -Path $logFile -Level Error
            if ($IDBridgeConfig.Debug.SkipADCHeck -ne $true) {
                Throw "AD Powershell Module does not exit on the local machine: $_"
            }
        }
    }
    #endregion Test Additional Modules

    #region Check Active IDBridge Configurations
    #Check if Read Only Mode is active
    if ($IDBridgeConfig.General.readOnly -eq $true) {
        Write-Log -Path $logFile -Message "READ ONLY MODE: NO CHANGES WILL BE MADE"
    }

    #Deactivate Groups if module isn't enabled
    if ($IDBridgeConfig.Google.enabled -eq $false) {
        $IDBridgeConfig.Google.enableGroupProcessing = $false
    }

    if ($IDBridgeConfig.AD.enabled -eq $false) {
        $IDBridgeConfig.AD.enableGroupProcessing = $false
    }
    #endregion Check Active IDBridge Configurations

    # Return the $IDBridgeConfig Variable
    return $IDBridgeConfig
}


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


function Initialize-Logging {
    [cmdletbinding()]
    Param(
        [parameter(Mandatory=$true)]
        $LogFileLocation
    )

    Set-Variable -Name "logDate" -Value (Get-Date -Format "yyyy-MM-dd-HH.mm.ss") -Scope global

    Set-Variable -Name "logFile" -Value $LogFileLocation -Scope global

    if ((Get-Item $logFile).Length -gt 1000000) {
        Rename-Item $logFile ((Get-Item $logfile).BaseName + "_" + $logDate + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $logDate ########" -Path $logFile
}
