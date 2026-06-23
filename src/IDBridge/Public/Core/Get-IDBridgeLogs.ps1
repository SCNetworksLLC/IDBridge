function Get-IDBridgeLogs {
    if ($null -eq $script:Logs) {
        throw "IDBridge is not initialized. Call Initialize-IDBridge first."
    }
    return $script:Logs
}