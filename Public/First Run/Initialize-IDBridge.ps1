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