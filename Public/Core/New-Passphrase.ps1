#Requires -Version 5.1
<#
.SYNOPSIS
    Generates deterministic passphrases via the SC Networks Azure Function.

.DESCRIPTION
    Sends usernames to the Azure Function in chunks of up to 500 per request.
    Word lists stay hidden on the server — this script never sees them.
    Supports single-user lookup, file batch (any size), and CSV export.

    To load this function into your session:
        . .\New-Passphrase.ps1

    To use it:
        New-Passphrase -Nonce "spring2025" -Username "alice"
        New-Passphrase -Nonce "spring2025" -InputFile students.txt

.PARAMETER Nonce
    The shared secret nonce — must match what you enter in the web tool.

.PARAMETER Username
    Single username mode. Returns the passphrase to the pipeline.

.PARAMETER InputFile
    Path to a .txt file with one username per line (batch mode).

.PARAMETER OutputFile
    CSV output path for batch mode. Defaults to passphrases.csv in the
    current directory.

.PARAMETER Mode
    'phrase' (default) or 'verbnoun'.
    - phrase:    Word-word-word# format, deterministic
    - verbnoun: Verb-noun## format, deterministic

.PARAMETER WordCount
    Number of words for Word List mode. 2-6, default 3.
    For 3+ words, shorter words are included in the pool.

.PARAMETER AuthToken
    The secret token to use. Must match one of the labeled tokens in AUTH_TOKENS
    in your Function App settings (format: label:token,label:token,...).
    Falls back to $env:PASSPHRASE_AUTH_TOKEN if not supplied.

.PARAMETER FunctionUrl
    Base URL of your Azure Function App.
    Defaults to https://passphrase.azurewebsites.net

.PARAMETER ChunkSize
    Usernames per Function request. Max 500 (enforced server-side). Default 500.

.EXAMPLE
    # Single passphrase
    New-Passphrase -Nonce "spring2025" -Username "alice"

.EXAMPLE
    # Single passphrase — verb-noun mode
    New-Passphrase -Nonce "spring2025" -Username "alice" -Mode verbnoun

.EXAMPLE
    # Pipe result to clipboard
    New-Passphrase -Nonce "spring2025" -Username "alice" | Set-Clipboard

.EXAMPLE
    # Batch from file → passphrases.csv
    New-Passphrase -Nonce "spring2025" -InputFile students.txt

.EXAMPLE
    # Batch — 4 words, custom output file
    New-Passphrase -Nonce "spring2025" -InputFile students.txt -WordCount 4 -OutputFile term1.csv

.EXAMPLE
    # Auth token from environment variable (safer — not in shell history)
    $env:PASSPHRASE_AUTH_TOKEN = "your-token-from-AUTH_TOKENS"
    New-Passphrase -Nonce "spring2025" -InputFile students.txt
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
