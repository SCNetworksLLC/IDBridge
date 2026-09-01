<#
.SYNOPSIS
Build the Set-ADAccountPassword reset list for a set of AD users from Keysmith passphrases.

.DESCRIPTION
Decide-phase helper for Reset-IDBridgeADPassword. Requests a deterministic passphrase for every
user's SamAccountName via New-Passphrase — one batched call per 500 users, the Keysmith
server-side maximum per request — and builds a Set-ADAccountPassword -Reset splat for each.
Phrases come back in request order, so each user is paired with their phrase by position; an API
failure or a returned-count mismatch throws, since a reset with missing passphrases must not
proceed. The plaintext phrase rides along on each item for the caller's optional export and is
never logged here.

.PARAMETER UserList
The AD user objects to reset. Each needs SamAccountName and DistinguishedName.

.PARAMETER PassphraseAPI
Hashtable with Nonce (SecureString), AuthToken (SecureString), Mode, WordCount, and optional
Rev — the same shape as a source record's ADPassphraseAPI block, forwarded to New-Passphrase.

.PARAMETER ExportOnly
The caller is only exporting the passphrases, not resetting — the per-user proposed line logs
"Export passphrase" instead of "Reset password". Output is identical either way.

.OUTPUTS
[object[]] of @{ SamAccountName; DistinguishedName; Passphrase; Splat } where Splat is the
Set-ADAccountPassword parameter hashtable.

.EXAMPLE
$resets = Get-ADUsersToResetPassword -UserList $users -PassphraseAPI $api

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-31
#>
function Get-ADUsersToResetPassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        [hashtable]$PassphraseAPI,

        [switch]$ExportOnly
    )

    $UserList = @($UserList)

    #One batched API call per 500 users - the Keysmith server-side max per request
    $phrases = @()
    for ($offset = 0; $offset -lt $UserList.Count; $offset += 500) {
        $chunk = @($UserList[$offset..([Math]::Min($offset + 499, $UserList.Count - 1))])

        try {
            $passphraseParams = @{
                Nonce = $PassphraseAPI.Nonce
                Username = @($chunk.SamAccountName)
                Mode = $PassphraseAPI.Mode
                WordCount = $PassphraseAPI.WordCount
                AuthToken = $PassphraseAPI.AuthToken
            }
            if ($PassphraseAPI.Rev) { $passphraseParams.Rev = $PassphraseAPI.Rev }

            $phrases += @(New-Passphrase @passphraseParams)
        }
        catch {
            Write-Log -Message ("AD: Password reset aborted. No passwords were changed.  Password API Error $($_)") -Level "Error"
            Throw $_
        }
    }

    if (@($phrases).Count -ne $UserList.Count) {
        Write-Log -Message ("AD: Password reset aborted. No passwords were changed.  Keysmith returned $(@($phrases).Count) passphrase(s) for $($UserList.Count) user(s).") -Level "Error"
        Throw "Keysmith returned $(@($phrases).Count) passphrase(s) for $($UserList.Count) user(s)."
    }

    $itemList = @()

    $proposedAction = if ($ExportOnly) { "Export passphrase" } else { "Reset password" }

    for ($i = 0; $i -lt $UserList.Count; $i++) {
        $item = $UserList[$i]

        Write-Log -Message ("AD: Proposed: $proposedAction for $($item.SamAccountName) ($($item.DistinguishedName)).")

        $itemList += [PSCustomObject]@{
            SamAccountName = $item.SamAccountName
            DistinguishedName = $item.DistinguishedName
            Passphrase = $phrases[$i]
            Splat = @{
                Identity = $item.DistinguishedName
                Reset = $true
                NewPassword = (ConvertTo-SecureString $phrases[$i] -AsPlainText -Force)
                ErrorAction = "Stop"
            }
        }
    }

    return $itemList
}
