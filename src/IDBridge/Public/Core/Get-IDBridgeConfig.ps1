<#
.SYNOPSIS
Return the initialized IDBridge configuration object.

.DESCRIPTION
Accessor for the script-scoped configuration populated by Initialize-IDBridge. Use this
everywhere instead of reading the script variable directly. Throws if called before
Initialize-IDBridge has run.

.OUTPUTS
[hashtable] the IDBridge configuration, including the runtime Paths block added at startup.

.EXAMPLE
$IDConfig = Get-IDBridgeConfig

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-IDBridgeConfig {
    if (-not $script:IDBridgeConfig) {
        throw "IDBridge is not initialized. Call Initialize-IDBridge first."
    }
    return $script:IDBridgeConfig
}