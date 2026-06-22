function Get-GoogleHeaders {
    if (-not $script:GoogleHeaders) {
        throw "Google token is not initialized. Call Initialize-IDBridge first."
    }
    return $script:GoogleHeaders
}