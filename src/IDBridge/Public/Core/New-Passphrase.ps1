<#
.SYNOPSIS
    Generate deterministic passphrase(s) for one or more usernames via the SC Networks Azure Function.

.DESCRIPTION
    POSTs the nonce and username(s) to the Azure Function's /api/generate endpoint and returns the
    generated phrase(s). Word lists stay on the server — this function never sees them. The same
    nonce + username + mode always yields the same phrase (deterministic), so a user's passphrase
    can be regenerated without storing it. One or many usernames may be supplied in a single call.

.PARAMETER Nonce
    The shared secret nonce as a SecureString. Must match the nonce configured for the tool.

.PARAMETER Username
    One or more usernames to generate phrases for. Returns the phrase(s) in the same order.

.PARAMETER Mode
    Generation mode: 'words' (word-word-word# style) or 'verbnoun' (verb-noun## style). Required.

.PARAMETER WordCount
    Number of words for 'words' mode. 2-6, default 3.

.PARAMETER AuthToken
    Bearer token as a SecureString authorizing the Function call. Falls back to
    $env:PASSPHRASE_AUTH_TOKEN when not supplied; throws if neither is present.

.PARAMETER FunctionUrl
    Base URL of the Azure Function App. Defaults to https://passphrase.azurewebsites.net.

.OUTPUTS
    [string] (or [string[]]) the generated passphrase(s).

.EXAMPLE
    New-Passphrase -Nonce $nonce -Username 'alice' -Mode words

.EXAMPLE
    New-Passphrase -Nonce $nonce -Username 'alice' -Mode verbnoun

.EXAMPLE
    New-Passphrase -Nonce $nonce -Username @('alice','bob') -Mode words -WordCount 4

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>

function New-Passphrase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Nonce,

        [Parameter(Mandatory = $true)]
        [array]$Username,

        [ValidateSet('words', 'verbnoun')]
        [Parameter(Mandatory = $true)]
        [string]$Mode,

        [ValidateRange(2, 6)]
        [int]$WordCount = 3,

        [Parameter(Mandatory = $false)]
        [System.Security.SecureString]$AuthToken,

        [string]$FunctionUrl = "https://passphrase.azurewebsites.net"
    )

    # ── Resolve auth token ────────────────────────────────────────────────────
    if (-not $AuthToken) {
        if ($env:PASSPHRASE_AUTH_TOKEN) {
            $AuthToken = $env:PASSPHRASE_AUTH_TOKEN
        } else {
            throw "AuthToken is required. Pass -AuthToken or set `$env:PASSPHRASE_AUTH_TOKEN."
        }
    }

    $FunctionUrl = $FunctionUrl.TrimEnd('/')
    $GenerateUrl = "$FunctionUrl/api/generate"

    $Mode = $Mode.ToLower()

    $Headers = @{
        'Authorization' = "Bearer $(ConvertFrom-SecureString $AuthToken -AsPlainText)"
        'Content-Type'  = 'application/json'
    }

    $body = @{
        nonce     = $(ConvertFrom-SecureString $Nonce -AsPlainText)
        usernames = $Username
        mode      = $Mode
        wordCount = $WordCount
    } | ConvertTo-Json -Compress

    try {
        $generateParams = @{
            Uri             = $GenerateUrl
            Method          = 'Post'
            Headers         = $Headers
            Body            = $body
            UseBasicParsing = $true
        }

        $generate = Invoke-RestMethod @generateParams

        return $generate.results.phrase
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $detail = $_.ErrorDetails.Message
        throw "Function request failed (HTTP $status): $detail"
    }
}
