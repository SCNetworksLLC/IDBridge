<#
.SYNOPSIS
Build the create list for source users that have no Google account yet.

.DESCRIPTION
Selects active, Google-provisioned source users that are not yet linked (no GoogleCurrentUserID)
and whose UPN is absent from Google, and builds a New-IDBridgeGoogleUser splat for each
(primaryEmail, personID, name, building/title, OU path, change-at-next-login, and password). The
password comes from the passphrase API (GooglePassphraseAPI -> New-Passphrase) or a pre-set
GoogleKey; a user with neither is logged and skipped.

.PARAMETER UserList
The enriched source records.

.PARAMETER GoogleUsers
All current Google users; used to skip UPNs already present in Google.

.OUTPUTS
[object[]] of @{ UPN; Splat } where Splat is the New-IDBridgeGoogleUser parameter hashtable.

.EXAMPLE
$toCreate = Get-GoogleUsersToCreate -UserList $sourceData -GoogleUsers $googleData.Users

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-06-26
#>
function Get-GoogleUsersToCreate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $UserList,

        [Parameter(Mandatory = $true)]
        $GoogleUsers
    )

    $itemList = @()

    foreach ($item in $UserList | Where-Object {$_.IDBActive -eq $true -and $_.ProvisionGoogle -eq $true -and -not $_.GoogleCurrentUserID -and $_.UPN -notin $GoogleUsers.primaryEmail}) {
        $itemCreateSplat = @{}

        $itemCreateSplat = @{
            "PrimaryEmail" = $item.UPN
            "PersonID" = $item.personID
            "FirstName" = $item.NameFirst.trim()
            "LastName" = $item.NameLast.trim()
            "Building" = $item.Building.trim()
            "JobTitle" = $item.JobTitle.trim()
            "OrgUnitPath" = $item.GoogleOrganizationalUnit
        }

        if ($item.GoogleChangePasswordAtLogon) {
            $itemCreateSplat["ChangeAtNextLogin"] = 'true'
        } else {
            $itemCreateSplat["ChangeAtNextLogin"] = 'false'
        }


        #Set AccountPassword
        if ($item.GooglePassphraseAPI) {
            try {
                $passphraseParams = @{
                    Nonce = $item.GooglePassphraseAPI.Nonce
                    Username = $item.Username
                    Mode = $item.GooglePassphraseAPI.Mode
                    WordCount = $item.GooglePassphraseAPI.WordCount
                    AuthToken = $item.GooglePassphraseAPI.AuthToken
                }

                $itemCreateSplat["Password"] = (ConvertTo-SecureString (New-Passphrase @passphraseParams) -AsPlainText -Force)
            }
            catch {
                Write-Log -Message ("Google: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  Password API Error. Skipping User Creation.") -Level "Warn"
                Write-Log -Message ("Google: Password API Error $($_)") -Level "Warn"
                Continue
            }
        } elseif ($item.GoogleKey) {
            $itemCreateSplat["Password"] = $item.GoogleKey
        } else {
            Write-Log -Message ("Google: No user found for $($item.PersonID). No Account Password could be set for $($item.PersonID).  GoogleKey is not set. Skipping User Creation.") -Level "Warn"
            Continue
        }

        Write-Log -Message ("Google: No user found for $($item.PersonID). Adding user to create list.")
        Write-Log -Message ($itemCreateSplat | ConvertTo-Json -Compress)

        $itemList += [PSCustomObject]@{
            UPN = $item.UPN
            Splat = $itemCreateSplat
        }
    }

    return $itemList
}