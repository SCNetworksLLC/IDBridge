<#
.SYNOPSIS
    Generate deterministic passphrase(s) for one or more usernames via Keysmith (SC Networks).

.DESCRIPTION
    POSTs the nonce and username(s) to Keysmith's /api/generate endpoint and returns the
    generated phrase(s). Word lists stay on the server — this function never sees them. The same
    nonce + username + mode always yields the same phrase (deterministic), so a user's passphrase
    can be regenerated without storing it. One or many usernames may be supplied in a single call.
    The token is sent in the x-api-key header — the Static Web App proxy overwrites Authorization
    before it reaches the API.

.PARAMETER Nonce
    The shared secret nonce as a SecureString. Must match the nonce configured for the tool.

.PARAMETER Username
    One or more usernames to generate phrases for. Returns the phrase(s) in the same order.

.PARAMETER Mode
    Generation mode: 'words' (word-word-word# style) or 'verbnoun' (verb-noun## style). Required.

.PARAMETER WordCount
    Number of words for 'words' mode. 2-6, default 3.

.PARAMETER AuthToken
    Keysmith API token as a SecureString authorizing the call (minted per school in the
    Keysmith admin UI). Throws when not supplied.

.PARAMETER Rev
    Word-list revision to derive against. Omit to use the server's latest (normal for
    account creation). Pass a specific rev only to regenerate passphrases from an
    earlier era — the rev used is written to the log on every call.

.PARAMETER FunctionUrl
    Base URL of the Keysmith site. Defaults to https://keysmith.scnlabs.net.

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

        [ValidateRange(1, 99)]
        [int]$Rev,

        [string]$FunctionUrl = "https://keysmith.scnlabs.net"
    )

    # ── Resolve auth token ────────────────────────────────────────────────────
    if (-not $AuthToken) {
        throw "AuthToken is required. Pass -AuthToken as a SecureString."
    }

    $FunctionUrl = $FunctionUrl.TrimEnd('/')
    $GenerateUrl = "$FunctionUrl/api/generate"

    $Mode = $Mode.ToLower()

    # x-api-key is the auth header — the SWA proxy overwrites Authorization
    # before it reaches the API
    $Headers = @{
        'x-api-key'    = $(ConvertFrom-SecureString $AuthToken -AsPlainText)
        'Content-Type' = 'application/json'
    }

    $bodyTable = @{
        nonce     = $(ConvertFrom-SecureString $Nonce -AsPlainText)
        usernames = $Username
        mode      = $Mode
        wordCount = $WordCount
    }
    if ($PSBoundParameters.ContainsKey('Rev')) { $bodyTable.rev = $Rev }
    $body = $bodyTable | ConvertTo-Json -Compress

    try {
        $generateParams = @{
            Uri             = $GenerateUrl
            Method          = 'Post'
            Headers         = $Headers
            Body            = $body
            UseBasicParsing = $true
        }

        $generate = Invoke-RestMethod @generateParams

        # Record the word-list rev so logs show which era these passphrases
        # belong to — regeneration later needs the same nonce + rev
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log -Message ("Keysmith: generated $(@($generate.results).Count) passphrase(s) — word-list rev $($generate.rev)") -Level "Info"
        }

        return $generate.results.phrase
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $detail = $_.ErrorDetails.Message
        throw "Function request failed (HTTP $status): $detail"
    }
}
