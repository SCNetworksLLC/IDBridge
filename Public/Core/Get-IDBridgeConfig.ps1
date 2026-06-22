function Get-IDBridgeConfig {
    if (-not $script:IDBridgeConfig) {
        throw "IDBridge is not initialized. Call Initialize-IDBridge first."
    }
    return $script:IDBridgeConfig
}