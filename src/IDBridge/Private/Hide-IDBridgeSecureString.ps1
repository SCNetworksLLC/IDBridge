<#
.SYNOPSIS
Replace every SecureString value in an object graph with $null, in place.

.DESCRIPTION
Internal helper for the PostRun plugin payload. Walks the RunResult object graph and nulls
out any value that is a [SecureString] — no named-field list, so new credential fields are
covered automatically (ADKey/GoogleKey, PassphraseAPI Nonce/AuthToken, create-splat
passwords, and anything added later).

Recurses into hashtables/IDictionary values, IList/array elements, and PSCustomObject
properties only. Other typed objects (ADUser, Google API responses' typed members, etc.)
are not walked — they are large graphs, hold no SecureStrings, and their properties are
often read-only. A reference-equality visited set makes the walk cycle-safe (source records
reference shared PassphraseAPI hashtables and appear in multiple change lists).

Mutates the input in place; called only at end of run, after all writes, when nothing
downstream needs the SecureStrings anymore.

.PARAMETER InputObject
The root of the object graph to scrub.

.OUTPUTS
None. The input object graph is modified in place.

.EXAMPLE
Hide-IDBridgeSecureString -InputObject $runResult

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-12
#>
function Hide-IDBridgeSecureString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $InputObject
    )

    $visited = [System.Collections.Generic.HashSet[object]]::new(
        [System.Collections.Generic.ReferenceEqualityComparer]::Instance
    )

    # Local recursive walker. Only containers we can both inspect and assign into are
    # traversed; everything else is a leaf.
    function Invoke-Scrub {
        param ($Node)

        if ($null -eq $Node -or $Node -is [string] -or $Node.GetType().IsValueType) { return }
        if (-not $visited.Add($Node)) { return }

        if ($Node -is [System.Collections.IDictionary]) {
            # Copy the key list first - we assign into the dictionary while iterating.
            foreach ($key in @($Node.Keys)) {
                if ($Node[$key] -is [System.Security.SecureString]) {
                    $Node[$key] = $null
                } else {
                    Invoke-Scrub -Node $Node[$key]
                }
            }
            return
        }

        if ($Node -is [System.Collections.IList]) {
            for ($i = 0; $i -lt $Node.Count; $i++) {
                if ($Node[$i] -is [System.Security.SecureString]) {
                    try { $Node[$i] = $null } catch { } # read-only/fixed collections: leave as-is
                } else {
                    Invoke-Scrub -Node $Node[$i]
                }
            }
            return
        }

        if ($Node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($property in $Node.PSObject.Properties) {
                if ($property.Value -is [System.Security.SecureString]) {
                    if ($property.IsSettable) { $property.Value = $null }
                } else {
                    Invoke-Scrub -Node $property.Value
                }
            }
        }
    }

    Invoke-Scrub -Node $InputObject
}
