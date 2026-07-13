# Spreadsheet Data Staff Override Plugin — IDBridge plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
Set the spreadsheet ID (normally the same spreadsheet as the staff source plugin, 'Override'
tab) before enabling the plugin in IDBridgeConfig.psd1 — it throws until the ID is set.
#>


function Invoke-PluginStaffOverride {
    [CmdletBinding()]
    param ()

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    $GoogleSheetConfig = @{
        SheetID        = "YOUR-SPREADSHEET-ID"   # From the sheet URL: docs.google.com/spreadsheets/d/<this part>/edit
        SheetRange     = 'Override'
    }

    if ($GoogleSheetConfig.SheetID -eq "YOUR-SPREADSHEET-ID") {
        Throw "Invoke-PluginStaffOverride: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    $overrideTypes = @(
        "NameFirst"
        "NameLast"
        "Username"
        "ForceDisable"
        "GoogleOUOverride"
        "AddGroup"
        "RemoveGroup"
    )

    try {
        $params = @{
            GoogleSheetID               = $GoogleSheetConfig.SheetID
            GoogleSheetRange            = $GoogleSheetConfig.SheetRange
        }

        $data = Get-GoogleSheetData @params
        Write-Log -Message "Plugin: Invoke-PluginStaffOverride successfully retrieved data from Google Sheet."
    }
    catch { Throw "Error retrieving data from Google Sheet: $($_)" }

    #Required Columns in the Google Sheet
    $requiredColumnsConfig = @(
        "PersonID"
        "Type"
        "Value"
        "StartDate"
        "EndDate"
    )

    #Check to make sure required columns exist in the data
    $columnsReturned = $data | Get-member -MemberType 'NoteProperty' | Select-Object -ExpandProperty 'Name'

    $columnCheck = Compare-Object $columnsReturned $requiredColumnsConfig | Where-Object{$_.SideIndicator -eq '=>'} | Select-Object -ExpandProperty InputObject

    if($columnCheck) {
        Throw "Required columns not found. Columns Needed: $columnCheck"
    }

    #Normalize Data
    $dataNormalized = foreach ($item in $data) {
        # Start with ordered hashtable (important for consistent output)
        $obj = [ordered]@{
            PersonID = $null
        }

        foreach ($type in $overrideTypes) {
            $obj[$type] = $null
        }

        Write-Log -Message "Processing override entry for PersonID '$($item.PersonID)' with Type '$($item.Type)' and Value '$($item.Value)'." -Level Trace

        if ($item.Type -and $item.Type -notin $overrideTypes) {
            Write-Log -Message "Invalid override type '$($item.Type)' for PersonID '$($item.PersonID)'. Skipping entry." -Level Warn
            continue
        }

        if ($item.StartDate -and ([datetime]$item.StartDate -gt (Get-Date))) {
            Write-Log -Message "Override for PersonID '$($item.PersonID)' has a future start date of '$($item.StartDate)'. Skipping entry until start date is reached." -Level Trace
            continue
        }

        if ($item.EndDate -and ([datetime]$item.EndDate -lt (Get-Date))) {
            Write-Log -Message "Override for PersonID '$($item.PersonID)' has an end date of '$($item.EndDate)' that has already passed. Skipping entry." -Level Trace
            continue
        }

        $obj["PersonID"] = $item.PersonID

        $obj[$item.Type] = $item.Value.Trim()

        if ($item.Type -eq "ForceDisable") {
            $obj[$item.Type] = $true
        }

        if ($item.Type -eq "GoogleOUOverride") {
            $obj[$item.Type] = $true
        }

        [PSCustomObject]$obj
    }

    return $dataNormalized
}



<#
Sample Data Returned by Invoke-PluginStaffOverride:

PersonID         : 999999
NameFirst        :
NameLast         :
Username         :
ForceDisable     : True
GoogleOUOverride :
AddGroup         :
RemoveGroup      :

PersonID         : 999999
NameFirst        :
NameLast         :
Username         : Tester
ForceDisable     :
GoogleOUOverride :
AddGroup         :
RemoveGroup      :


#>
