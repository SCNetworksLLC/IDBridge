# Account History Plugin — IDBridge PostRun plugin template
# TemplateVersion: 1
<#
Shipped with the IDBridge module and copied to <RootPath>\Plugins by Install-IDBridge.
Set your site's address below and add the vault secret 'AccountHistory-Token' (an API
token your site issued for account history: Set-IDBridgeSecret -Name 'AccountHistory-Token')
before enabling the plugin in IDBridgeConfig.psd1 - it throws until the address is set.

After every run (failed and ReadOnly runs included) it posts the run and every write the
run attempted to your site's account history: one event per RunResult.Applied record, in
the run's order, each with what an Update, a Rename or a Move changed (the attribute, its
new value and its old value). That is per-person data - person IDs, UPNs, group names,
names and titles - sent to your own site's address over HTTPS. Never a password: a key
whose name holds "password" (but the PasswordNeverExpires flag) and any SecureString value
are left out.

Each post is written to <RootPath>\Data\AccountHistory first, then sent, oldest first. A
post your site takes is deleted; one it refuses for good (400, or 413 from a proxy that
refuses its size) is set aside in AccountHistory\refused for 30 days; anything else - the
site down, the token revoked, account history switched off, a redirect - leaves the post
for the next run to send again (a run posted twice is kept once). Unsent posts are kept 30
days and at most 3,000 of them. The sending of one run stops after 30 seconds, a slow
answer included, so a slow site can never hold the run.
#>


function Invoke-PluginPostRunAccountHistory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult
    )

    $siteAddress = "https://YOUR-SITE-ADDRESS"   # your site's address, e.g. https://accounts.yourdistrict.org

    if ($siteAddress -eq "https://YOUR-SITE-ADDRESS") {
        Throw "Invoke-PluginPostRunAccountHistory: this plugin template still has placeholder values. Edit $($PSCommandPath) for your district before enabling it."
    }

    #A receiver typed to RunResult v1 cannot read another shape, and RunId is what keeps a
    #run posted twice once - without it a resend would be a second run
    if ($RunResult.SchemaVersion -ne 1) {
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory not posting - RunResult SchemaVersion is $($RunResult.SchemaVersion), not 1." -Level Warn
        return
    }
    if (-not $RunResult.RunId) {
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory not posting - the RunResult has no RunId." -Level Warn
        return
    }

    #region Import Configuration
    try { $IDConfig = Get-IDBridgeConfig } catch { Throw $_ }
    #endregion Import Configuration

    $spoolFolder = Join-Path $IDConfig.Paths.DataRoot 'AccountHistory'
    $refusedFolder = Join-Path $spoolFolder 'refused'
    if (-not (Test-Path -LiteralPath $spoolFolder)) {
        New-Item -ItemType Directory -Path $spoolFolder -Force | Out-Null
    }

    #A run is alone under the run lock, so a half-written post found now was left by a run
    #that died writing it
    $orphanTemps = @(Get-ChildItem -LiteralPath $spoolFolder -Filter '*.tmp' -File)
    if ($orphanTemps.Count -gt 0) {
        $orphanTemps | Remove-Item -Force
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory deleted $($orphanTemps.Count) half-written run post(s) a previous run left behind." -Level Trace
    }

    #region Spool This Run
    #Written beside and renamed into place, so the sender never reads a half-written post.
    #Names sort oldest first: the run's start in UTC, then its ID, then the part.
    $posts = @(ConvertTo-AccountHistoryPost -RunResult $RunResult -Install (Get-IDBridgeSiteID))
    $stamp = $RunResult.RunStart.ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture)
    $newFiles = @()
    for ($part = 1; $part -le $posts.Count; $part++) {
        $path = Join-Path $spoolFolder ('{0}-{1}-{2:D3}.json' -f $stamp, $posts[$part - 1].run_id, $part)
        $tempPath = "$path.tmp"
        [System.IO.File]::WriteAllText($tempPath, ($posts[$part - 1] | ConvertTo-Json -Depth 6 -Compress), [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tempPath -Destination $path -Force
        $newFiles += Get-Item -LiteralPath $path
    }
    #endregion Spool This Run

    #region Spool Bounds
    #The older posts in name order, then this run's - so the new run is always sent last
    $olderFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new([System.IO.FileInfo[]]@(Get-ChildItem -LiteralPath $spoolFolder -Filter '*.json' -File | Where-Object { $_.Extension -eq '.json' -and $_.FullName -notin $newFiles.FullName }))
    $olderFiles.Sort({ param ($x, $y) [string]::CompareOrdinal($x.Name, $y.Name) })
    $queue = @($olderFiles) + $newFiles

    $cutoff = (Get-Date).AddDays(-30)
    $dropped = @($queue | Where-Object { $_.LastWriteTime -lt $cutoff })
    $queue = @($queue | Where-Object { $_.LastWriteTime -ge $cutoff })
    #Every run spools a post, so the count bound sits well past 30 days of runs on a
    #15-minute schedule - the age is the bound that normally applies
    $maxPosts = 3000
    if ($queue.Count -gt $maxPosts) {
        $dropped += $queue[0..($queue.Count - $maxPosts - 1)]
        $queue = $queue[($queue.Count - $maxPosts)..($queue.Count - 1)]
    }
    if ($dropped.Count -gt 0) {
        $dropped | Remove-Item -Force
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory deleted $($dropped.Count) unsent run post(s) past the spool's bounds (30 days, 3,000 posts)." -Level Warn
    }

    if (Test-Path -LiteralPath $refusedFolder) {
        $expiredRefused = @(Get-ChildItem -LiteralPath $refusedFolder -Filter '*.json' -File | Where-Object { $_.LastWriteTime -lt $cutoff })
        if ($expiredRefused.Count -gt 0) {
            $expiredRefused | Remove-Item -Force
            Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory deleted $($expiredRefused.Count) refused run post(s) older than 30 days." -Level Trace
        }
    }
    #endregion Spool Bounds

    if ($siteAddress -notmatch '^https://') {
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory not sending - the site's address must start with https://. $($queue.Count) run post(s) waiting." -Level Warn
        return
    }

    try {
        $token = Get-IDBridgeSecret -Name 'AccountHistory-Token' -AsPlainText
    }
    catch {
        Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory not sending - vault secret 'AccountHistory-Token' could not be read ($($_.Exception.GetType().Name)). $($queue.Count) run post(s) waiting." -Level Warn
        return
    }

    $sendResult = Send-AccountHistorySpool -Files $queue -Uri "$($siteAddress.TrimEnd('/'))/api/accounts/runs" -Token $token -RefusedFolder $refusedFolder

    Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory sent $($sendResult.Sent) run post(s), set aside $($sendResult.Refused), $($queue.Count - $sendResult.Sent - $sendResult.Refused) waiting."
}


function ConvertTo-AccountHistoryPost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject]$RunResult,

        [Parameter(Mandatory = $true)]
        [string]$Install
    )

    # Builds the account history posts for one run, as ordered dictionaries ready for
    # ConvertTo-Json: one post, or several sharing one header when the run has more than
    # 10,000 writes or the post would reach 6 MB. Reads the RunResult and changes nothing.

    #Text past the receiver's bound is cut, on a UTF-8 character boundary
    function Limit-AccountHistoryText {
        param ([AllowNull()][string]$Text, [int]$MaxBytes)

        $encoding = [System.Text.Encoding]::UTF8
        if ($encoding.GetByteCount("$Text") -le $MaxBytes) { return "$Text" }
        $bytes = $encoding.GetBytes($Text)
        $length = $MaxBytes
        #Step back over continuation bytes (10xxxxxx) so the cut never splits a character
        while ($length -gt 0 -and ($bytes[$length] -band 0xC0) -eq 0x80) { $length-- }
        return $encoding.GetString($bytes, 0, $length)
    }

    #A value as text: a string as it is, a boolean true/false, a list joined, nothing as ""
    function ConvertTo-AccountHistoryText {
        param ($Value)

        if ($null -eq $Value) { return '' }
        if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [System.Collections.IEnumerable]) {
            return (@($Value | ForEach-Object { ConvertTo-AccountHistoryText -Value $_ }) -join ', ')
        }
        return [string]::Format([cultureinfo]::InvariantCulture, '{0}', $Value)
    }

    function ConvertTo-AccountHistoryUtc {
        param ([datetime]$Time)

        return $Time.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
    }

    #One change, unless it is a password or holds a SecureString (already scrubbed by the
    #core; not relied on here). PasswordNeverExpires is a flag, not a password, and is sent.
    function Add-AccountHistoryChange {
        param ($List, [string]$Name, $To, $From)

        if ($Name -match 'password' -and $Name -cne 'PasswordNeverExpires') { return }
        if (@($To) + @($From) | Where-Object { $_ -is [System.Security.SecureString] }) { return }
        $List.Add([ordered]@{
            name = Limit-AccountHistoryText -Text $Name -MaxBytes 64
            to   = Limit-AccountHistoryText -Text (ConvertTo-AccountHistoryText -Value $To) -MaxBytes 1024
            from = Limit-AccountHistoryText -Text (ConvertTo-AccountHistoryText -Value $From) -MaxBytes 1024
        })
    }

    #region Change Lists
    #Matched directory objects by PersonID - where an old value is read from
    $sourceByID = @{}
    foreach ($record in @($RunResult.SourceData).Where({ $null -ne $_ })) {
        if ($record.PersonID -and -not $sourceByID.ContainsKey("$($record.PersonID)")) { $sourceByID["$($record.PersonID)"] = $record }
    }

    #Splat keys that are not an attribute change: the account written to, and the Division
    #stamp every update carries
    $adLeftOut = @('Identity', 'Division')
    #The ADObject property a splat key is compared against, where the names differ
    $adFromProperty = @{ Office = 'physicalDeliveryOfficeName' }

    #Splat keys that are plumbing: the account written to, and the alias taken off ANOTHER
    #account before this one takes the address (the change is PrimaryEmail)
    $googleLeftOut = @('GoogleUserID', 'RemoveAlias')
    #The GoogleObject field each splat key is compared against
    $googleFrom = @{
        PrimaryEmail = { param ($googleObject) $googleObject.primaryEmail }
        PersonID     = { param ($googleObject) @($googleObject.externalIds | Where-Object { $_.type -eq 'organization' }).value }
        FirstName    = { param ($googleObject) $googleObject.Name.givenName }
        LastName     = { param ($googleObject) $googleObject.Name.familyName }
        Building     = { param ($googleObject) $googleObject.organizations.department }
        JobTitle     = { param ($googleObject) $googleObject.organizations.title }
        Suspended    = { param ($googleObject) $googleObject.suspended }
        Archived     = { param ($googleObject) $googleObject.archived }
        OrgUnitPath  = { param ($googleObject) $googleObject.orgUnitPath }
    }

    #"<Directory>|<Action>|<PersonID>" -> its changes (a run holds at most one of each for a person)
    $changeIndex = @{}

    foreach ($item in @($RunResult.AD.UsersToUpdate.UpdateList).Where({ $null -ne $_ })) {
        $adObject = $sourceByID["$($item.PersonID)"].ADObject
        $changes = [System.Collections.Generic.List[object]]::new()
        foreach ($key in @($item.Splat.Keys | Sort-Object)) {
            if ($key -in $adLeftOut) { continue }
            if ($key -eq 'Replace') {
                foreach ($replaceKey in @($item.Splat.Replace.Keys | Sort-Object)) {
                    Add-AccountHistoryChange -List $changes -Name $replaceKey -To $item.Splat.Replace[$replaceKey] -From $adObject.$replaceKey
                }
                continue
            }
            $fromProperty = if ($adFromProperty.ContainsKey($key)) { $adFromProperty[$key] } else { $key }
            Add-AccountHistoryChange -List $changes -Name $key -To $item.Splat[$key] -From $adObject.$fromProperty
        }
        $changeIndex["AD|Update|$($item.PersonID)"] = $changes
    }

    foreach ($item in @($RunResult.AD.UsersToUpdate.RenameList).Where({ $null -ne $_ })) {
        $changes = [System.Collections.Generic.List[object]]::new()
        Add-AccountHistoryChange -List $changes -Name 'Name' -To $item.NewName -From $item.CN
        $changeIndex["AD|Rename|$($item.PersonID)"] = $changes
    }

    foreach ($item in @($RunResult.AD.UsersToUpdate.MoveList).Where({ $null -ne $_ })) {
        $adObject = $sourceByID["$($item.PersonID)"].ADObject
        #The OU is what follows the DN's first comma that a backslash does not escape
        #(CN=Ann Smith\, Jr. 007,OU=Staff,DC=x -> OU=Staff,DC=x)
        $distinguishedName = "$($adObject.DistinguishedName)"
        $fromOrgUnit = ''
        for ($i = 0; $i -lt $distinguishedName.Length; $i++) {
            if ($distinguishedName[$i] -eq '\') { $i++; continue }
            if ($distinguishedName[$i] -eq ',') { $fromOrgUnit = $distinguishedName.Substring($i + 1); break }
        }
        $changes = [System.Collections.Generic.List[object]]::new()
        Add-AccountHistoryChange -List $changes -Name 'OrganizationalUnit' -To $item.NewOrgUnit -From $fromOrgUnit
        $changeIndex["AD|Move|$($item.PersonID)"] = $changes
    }

    foreach ($item in @($RunResult.Google.UsersToUpdate).Where({ $null -ne $_ })) {
        $googleObject = $sourceByID["$($item.PersonID)"].GoogleObject
        $changes = [System.Collections.Generic.List[object]]::new()
        foreach ($key in @($item.Splat.Keys | Sort-Object)) {
            if ($key -in $googleLeftOut) { continue }
            $from = if ($googleFrom.ContainsKey($key) -and $googleObject) { & $googleFrom[$key] $googleObject } else { $null }
            Add-AccountHistoryChange -List $changes -Name $key -To $item.Splat[$key] -From $from
        }
        $changeIndex["Google|Update|$($item.PersonID)"] = $changes
    }
    #endregion Change Lists

    #region Events
    $events = [System.Collections.Generic.List[object]]::new()
    $applied = @($RunResult.Applied).Where({ $null -ne $_ })
    for ($n = 0; $n -lt $applied.Count; $n++) {
        $record = $applied[$n]

        #The write's local "yyyy-MM-dd HH:mm:ss" stamp, as local time, to UTC. The core
        #formats it in the box's culture, so that culture is read first (on a box with
        #another calendar the invariant read would take the wrong year), the invariant
        #after; a stamp that reads as neither goes as "" and the receiver skips that event.
        $at = ''
        $parsed = [datetime]::MinValue
        foreach ($culture in @([cultureinfo]::CurrentCulture, [cultureinfo]::InvariantCulture)) {
            if ([datetime]::TryParseExact("$($record.Timestamp)", 'yyyy-MM-dd HH:mm:ss', $culture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
                $at = ConvertTo-AccountHistoryUtc -Time $parsed
                break
            }
        }

        $changes = @()
        $changeKey = "$($record.Directory)|$($record.Action)|$($record.PersonID)"
        if ($changeIndex.ContainsKey($changeKey)) {
            $changes = @($changeIndex[$changeKey] | Select-Object -First 50)
        }

        $events.Add([ordered]@{
            n         = $n
            at        = $at
            directory = "$($record.Directory)"
            action    = "$($record.Action)"
            person_id = Limit-AccountHistoryText -Text "$($record.PersonID)" -MaxBytes 64
            target    = Limit-AccountHistoryText -Text "$($record.Target)" -MaxBytes 512
            success   = [bool]$record.Success
            error     = Limit-AccountHistoryText -Text "$($record.Error)" -MaxBytes 65536
            changes   = [object[]]$changes
        })
    }
    #endregion Events

    #region Parts
    $header = [ordered]@{
        schema    = 1
        run_id    = "$($RunResult.RunId)".ToLowerInvariant()
        install   = $Install
        version   = Limit-AccountHistoryText -Text "$($RunResult.ModuleVersion)" -MaxBytes 32
        started   = ConvertTo-AccountHistoryUtc -Time $RunResult.RunStart
        ended     = ConvertTo-AccountHistoryUtc -Time $RunResult.RunEnd
        success   = [bool]$RunResult.Success
        error     = Limit-AccountHistoryText -Text $(if ($RunResult.RunError) { "$($RunResult.RunError)" } else { '' }) -MaxBytes 65536
        read_only = [bool]$RunResult.ReadOnly
        test_run  = [bool]$RunResult.TestRun
        counts    = [ordered]@{
            managed      = [int]$RunResult.Counts.Managed
            create       = [int]$RunResult.Counts.Create
            update       = [int]$RunResult.Counts.Update
            deactivate   = [int]$RunResult.Counts.Deactivate
            group_add    = [int]$RunResult.Counts.GroupAdd
            group_remove = [int]$RunResult.Counts.GroupRemove
            failed       = [int]$RunResult.Counts.Failed
        }
    }

    #At most 10,000 events a post, and under 6 MB as compressed JSON: the header with an
    #empty events list, plus each event and the comma before it
    $maxEvents = 10000
    $maxBytes = 6MB
    $encoding = [System.Text.Encoding]::UTF8
    $emptyPost = [ordered]@{}
    foreach ($key in $header.Keys) { $emptyPost[$key] = $header[$key] }
    $emptyPost['events'] = @()
    $headerBytes = $encoding.GetByteCount(($emptyPost | ConvertTo-Json -Depth 6 -Compress))

    $partEvents = [System.Collections.Generic.List[object]]::new()
    $partBytes = $headerBytes
    $parts = [System.Collections.Generic.List[object]]::new()
    foreach ($event in $events) {
        $eventBytes = $encoding.GetByteCount(($event | ConvertTo-Json -Depth 5 -Compress)) + 1
        if ($partEvents.Count -gt 0 -and ($partEvents.Count -ge $maxEvents -or ($partBytes + $eventBytes) -ge $maxBytes)) {
            $parts.Add($partEvents.ToArray())
            $partEvents.Clear()
            $partBytes = $headerBytes
        }
        $partEvents.Add($event)
        $partBytes += $eventBytes
    }
    #A run with no writes (a ReadOnly run, a run that changed nothing) is still one post
    $parts.Add($partEvents.ToArray())

    foreach ($partEventList in $parts) {
        $post = [ordered]@{}
        foreach ($key in $header.Keys) { $post[$key] = $header[$key] }
        $post['events'] = [object[]]$partEventList
        $post
    }
    #endregion Parts
}


function Send-AccountHistorySpool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]]$Files,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$RefusedFolder
    )

    # Sends the spooled posts in the order given. 200 deletes a post; 400, and 413 from a
    # proxy that refuses its size, set it aside in RefusedFolder; any other answer (a
    # redirect included - a post never follows one), or none, stops the sending and leaves
    # the rest for the next run, so the order is kept. The whole sending stops after 30
    # seconds - nothing times a plugin out, and a hung one would hold the run's lock. The
    # token goes in the Authorization header only: never a log line or a file.

    $sent = 0
    $refused = 0
    $deadline = (Get-Date).AddSeconds(30)

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    try {
        foreach ($file in $Files) {
            $remainingSeconds = [int][math]::Floor(($deadline - (Get-Date)).TotalSeconds)
            if ($remainingSeconds -lt 1) {
                Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory stopped sending after 30 seconds - the rest wait for the next run." -Level Warn
                break
            }

            try {
                $statusCode = Send-AccountHistoryPost -Client $client -Uri $Uri -Token $Token -Path $file.FullName -TimeoutSeconds ([math]::Min(10, $remainingSeconds))
            }
            catch {
                Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory send failed ($($_.Exception.GetType().Name)) - kept to send again next run." -Level Warn
                break
            }

            if ($statusCode -eq 200) {
                Remove-Item -LiteralPath $file.FullName -Force
                $sent++
            }
            elseif ($statusCode -in @(400, 413)) {
                #The site (or a proxy in front of it) will refuse this post every time -
                #sending it again cannot help, and it would block every post behind it
                if (-not (Test-Path -LiteralPath $RefusedFolder)) {
                    New-Item -ItemType Directory -Path $RefusedFolder -Force | Out-Null
                }
                Move-Item -LiteralPath $file.FullName -Destination (Join-Path $RefusedFolder $file.Name) -Force
                $refused++
                Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory run post refused (status $statusCode) - set aside in $RefusedFolder." -Level Warn
            }
            else {
                Write-Log -Message "Plugin: Invoke-PluginPostRunAccountHistory send failed (status $statusCode) - kept to send again next run." -Level Warn
                break
            }
        }
    }
    finally {
        #Disposes the handler with it
        $client.Dispose()
    }

    return [PSCustomObject]@{
        Sent    = $sent
        Refused = $refused
    }
}


function Send-AccountHistoryPost {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpClient]$Client,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Token,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    # One post: the file's bytes as the body, and its answer's status code. Throws when
    # there is no answer in TimeoutSeconds. The timeout covers the whole exchange - the
    # answer's body is read under the same token - so a site that sends its headers and
    # then stalls cannot hold the call past it.

    $cancel = [System.Threading.CancellationTokenSource]::new([timespan]::FromSeconds($TimeoutSeconds))
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $Uri)
    try {
        $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
        $request.Content = [System.Net.Http.ByteArrayContent]::new([System.IO.File]::ReadAllBytes($Path))
        $request.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/json')

        $response = $Client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseContentRead, $cancel.Token).GetAwaiter().GetResult()
        try {
            return [int]$response.StatusCode
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        #Disposes the content with it
        $request.Dispose()
        $cancel.Dispose()
    }
}
