<#
.SYNOPSIS
Read the TemplateVersion marker from a shipped or installed template file.

.DESCRIPTION
Internal helper for Install-IDBridge: returns the integer from the first
'# TemplateVersion: <n>' comment line in the file, or $null when the file has no marker
(site copies made before template versioning existed, or copies whose header was edited
away). Uses no module state or Write-Log - Install-IDBridge runs before initialization.

.PARAMETER Path
The template file to read.

.OUTPUTS
[int] the template version, or $null when the file has no marker.

.EXAMPLE
Get-IDBridgeTemplateVersion -Path 'C:\IDBridge\Plugins\Invoke-PluginPostRunReport.ps1'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-13
#>
function Get-IDBridgeTemplateVersion {
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $match = Select-String -Path $Path -Pattern '^#\s*TemplateVersion:\s*(\d+)' -List
    if ($match) {
        return [int]$match.Matches[0].Groups[1].Value
    }
    return $null
}
