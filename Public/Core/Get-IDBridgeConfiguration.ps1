function Get-IDBridgeConfiguration {
    [CmdletBinding()]
    param (
        [string]$ConfigPath = "C:\IDBridge\Config"
    )

    Write-Host "Importing config file from $($configPath)"

    try {
        if (Test-Path $configPath) {
            $IDBridgeConfig = Import-PowerShellDataFile -Path (Join-Path $configPath "IDBridgeConfig.psd1") -ErrorAction Stop
            Write-Host "Successfully imported IDBridgeConfig.psd1" -ForegroundColor Green
        } else {
            Throw "Config path not found: $configPath"
        }
    }
    catch {
        Throw "Error importing config file: $_"
    }



    #region Validate Paths
    foreach ($path in $IDBridgeConfig.Paths.GetEnumerator()) {
        if (-not (Test-Path $path.Value)) {
            New-Item -ItemType Directory -Path $path.Value -Force | Out-Null
            Write-Host "Created missing directory: $($path.Value)" -ForegroundColor Yellow
        }
    }
    #endregion Validate Paths


    #region Set Logging
    Set-Variable -Name "logFile" -Value "$($IDBridgeConfig.Paths.LogsRoot)\IDBridge.log" -Scope global

    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 50000000) {
        Rename-Item $logFile ((Get-Item $logfile).BaseName + "_" + $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) + ".log")
    }

    Write-Log -Message "######## Begin of Script Run: $((Get-Date -Format "yyyy-MM-dd-HH.mm.ss")) ########" -Path $logFile

    if ($IDBridgeConfig.Debug.verboseLogging -eq $true) {
        Write-Log -Message "Verbose logging is ENABLED" -Path $logFile
        $Global:VerboseLogging = $true
    }
    #endregion Set Logging

  


    #region JSON Google Auth
    # Check for exactly 1 JSON file in the Auth folder
    try {
        if (Test-Path $IDBridgeConfig.Paths.AuthRoot) {
            $authJsonFiles = Get-ChildItem -Path $IDBridgeConfig.Paths.AuthRoot -Filter *.json -File
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
    }
    catch {
        Throw $_
    }

    # Get the full path to the single JSON file found in the Auth folder
    $authFilePath = $authJsonFiles[0].FullName
    
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

    # Add the path to the config object hashtable for use in other functions
    Write-Host "Loaded valid Google Auth JSON file: $($authFilePath)" -ForegroundColor Green
    $IDBridgeConfig.GoogleToken.authFilePath = $authFilePath

    #endregion JSON Google Auth



    #region User Secrets Path
    $userSecretsPath = Join-Path $IDBridgeConfig.Paths.AuthRoot $env:USERNAME
    if (-not (Test-Path $userSecretsPath)) {
        New-Item -ItemType Directory -Path $userSecretsPath -Force | Out-Null
        Write-Host "Created user secrets directory for $env:USERNAME" -ForegroundColor Green
    }

    $IDBridgeConfig.Paths.UserSecretsRoot = $userSecretsPath
    Write-Log -Message "User secrets path set to: $userSecretsPath" -Path $logFile
    #endregion User Secrets Path




    #region Test Additional Modules
    if ($IDBridgeConfig.AD.enabled -eq $true) {
        #Test AD Module
        try {
            Import-Module -Name ActiveDirectory -ErrorAction Stop
            Write-Host "Imported Active Directory Module"
        }
        catch {
            Write-Host "AD Powershell Module does not exit on the local machine: $($_)" -ForegroundColor Red
            if ($IDBridgeConfig.Debug.SkipADCHeck -ne $true) {
                Throw "AD Powershell Module does not exit on the local machine: $_"
            }
        }
    }
    #endregion Test Additional Modules



    #region Check Active IDBridge Configurations
    #Check if Read Only Mode is active
    if ($IDBridgeConfig.Debug.readOnly -eq $true) {
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