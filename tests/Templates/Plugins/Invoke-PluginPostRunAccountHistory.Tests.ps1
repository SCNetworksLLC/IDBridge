<#
.SYNOPSIS
Unit tests for the account history PostRun plugin template (Invoke-PluginPostRunAccountHistory).

.DESCRIPTION
The post is a wire contract with the site's receiver, so its shape is pinned from a
RunResult: the header, the local times turned UTC, one event per Applied record with its
n, the changes an Update, a Rename and a Move carried (never a password), the text bounds
and the parts a large run is split into. The sending is pinned by what each answer does
to the spooled file: a 200 deletes it, a 400 sets it aside, anything else keeps it and
stops - and by the clock, the spool's bounds and a missing token. The one call that sends
a post is also run for real against a loopback listener: a stalled answer comes back
within its timeout, a 200 comes back as 200, and the sending never follows a redirect. The template is
dot-sourced (an edited copy, where a test needs its address set); Write-Log, the config,
the vault, the SiteID and the web call are mocked, and the spool lives under TestDrive.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest

    $templatePath = Join-Path $PSScriptRoot '..' '..' '..' 'src' 'IDBridge' 'Templates' 'Plugins' 'Invoke-PluginPostRunAccountHistory.ps1'
    . $templatePath

    # An edited copy of the template with its address set, as a district would make it.
    function New-EditedPlugin {
        param ([string]$Address)
        $path = Join-Path $TestDrive "Invoke-PluginPostRunAccountHistory-$([guid]::NewGuid().ToString()).ps1"
        (Get-Content -Path $templatePath -Raw).Replace('$siteAddress = "https://YOUR-SITE-ADDRESS"', "`$siteAddress = `"$Address`"") | Set-Content -Path $path -Encoding utf8
        return $path
    }

    # The plugin's own conversion, so the expectation holds in any time zone.
    function ConvertTo-ExpectedUtc {
        param ([datetime]$Time)
        $Time.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
    }

    function New-TestApplied {
        param ([string]$Directory, [string]$Action, [string]$PersonID, [string]$Target, [bool]$Success = $true, [string]$ErrorText = $null, [string]$Timestamp = '2026-11-17 08:00:20')
        [PSCustomObject]@{
            Timestamp = $Timestamp
            Directory = $Directory
            Action    = $Action
            PersonID  = $PersonID
            Target    = $Target
            Success   = $Success
            Error     = if ($Success) { $null } else { $ErrorText }
        }
    }

    function New-TestAccountHistoryRun {
        param (
            $Applied = @(),
            $UpdateList = @(),
            $RenameList = @(),
            $MoveList = @(),
            $GoogleUpdates = @(),
            $SourceData = @(),
            [bool]$ReadOnly = $false,
            $RunError = $null,
            $RunId = '3F2B8C1E-6D1A-4F0E-9B7A-2C5D8E9F0A1B',
            $SchemaVersion = 1
        )
        $runResult = [PSCustomObject]@{
            SchemaVersion   = $SchemaVersion
            ModuleVersion   = '26.11.20.0'
            RunId           = $RunId
            Success         = (-not $RunError)
            RunError        = $RunError
            RunStart        = [datetime]::new(2026, 11, 17, 8, 0, 2, [DateTimeKind]::Local)
            RunEnd          = [datetime]::new(2026, 11, 17, 8, 0, 41, [DateTimeKind]::Local)
            DurationSeconds = 39
            ReadOnly        = $ReadOnly
            TestRun         = $false
            Counts          = [PSCustomObject]@{ Managed = 1840; Create = 2; Update = 5; Deactivate = 1; GroupAdd = 3; GroupRemove = 1; Failed = 0 }
            Applied         = @($Applied)
            SourceData      = @($SourceData)
            AD              = [PSCustomObject]@{
                Enabled       = $true
                UsersToUpdate = [PSCustomObject]@{ UpdateList = @($UpdateList); RenameList = @($RenameList); MoveList = @($MoveList) }
            }
            Google          = [PSCustomObject]@{
                Enabled       = $true
                UsersToUpdate = @($GoogleUpdates)
            }
        }
        if ($null -eq $RunId) { $runResult.PSObject.Properties.Remove('RunId') }
        return $runResult
    }

    # A run with one write of every action, and an Update, a Rename and a Move in the
    # change lists for person 10001 (a Google Update too).
    function New-TestFullRun {
        $secret = ConvertTo-SecureString 'Hunter2!' -AsPlainText -Force
        $record = New-TestSourceRecord -PersonID '10001' `
            -ADObject (New-TestADUser -title 'Aide' -physicalDeliveryOfficeName 'Main' -DistinguishedName 'CN=Test User 10001,OU=Staff,DC=example,DC=org') `
            -GoogleObject (New-TestGoogleUser -suspended $true -GivenName 'Test')

        $updateList = @([PSCustomObject]@{
            CN       = 'Test User 10001'
            PersonID = '10001'
            Splat    = @{
                Identity             = 'guid-10001'
                Division             = '2026-11-17-08:00'
                Title                = 'Teacher'
                Office               = 'North'
                Enabled              = $true
                PasswordNeverExpires = $true
                AccountPassword      = $secret
                Password             = 'Hunter2!'
                Description          = $secret
                Replace              = @{ extensionAttribute2 = 'Coach'; EmployeeType = 'STAFF' }
            }
        })
        $renameList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; ADUserID = 'guid-10001'; NewName = 'Testy User 10001' })
        $moveList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; ADUserID = 'guid-10001'; NewOrgUnit = 'OU=Teachers,DC=example,DC=org' })
        $googleUpdates = @([PSCustomObject]@{
            UPN      = 'testy@example.org'
            PersonID = '10001'
            Splat    = @{
                GoogleUserID = 'g-tuser'
                PrimaryEmail = 'testy@example.org'
                RemoveAlias  = 'testy@example.org'
                FirstName    = 'Testy'
                Suspended    = 'false'
                OrgUnitPath  = '/Teachers'
            }
        })
        $applied = @(
            New-TestApplied -Directory AD -Action Create -PersonID '10002' -Target 'new@example.org'
            New-TestApplied -Directory AD -Action Update -PersonID '10001' -Target 'Test User 10001'
            New-TestApplied -Directory AD -Action Rename -PersonID '10001' -Target 'Testy User 10001'
            New-TestApplied -Directory AD -Action Move -PersonID '10001' -Target 'Test User 10001'
            New-TestApplied -Directory AD -Action Deactivate -PersonID '10003' -Target 'gone@example.org'
            New-TestApplied -Directory Google -Action GroupAdd -PersonID '10001' -Target 'Staff - High School' -Success $false -ErrorText '(404) Resource Not Found: groupKey'
            New-TestApplied -Directory AD -Action GroupRemove -PersonID '10001' -Target 'Aides'
            New-TestApplied -Directory Google -Action Update -PersonID '10001' -Target 'testy@example.org' -Timestamp '2026-11-17 08:00:30'
        )
        New-TestAccountHistoryRun -Applied $applied -UpdateList $updateList -RenameList $renameList -MoveList $moveList -GoogleUpdates $googleUpdates -SourceData @($record)
    }

    function Get-TestChange {
        param ($Event, [string]$Name)
        @($Event.changes | Where-Object { $_.name -eq $Name })
    }
}

Describe 'ConvertTo-AccountHistoryPost' {
    BeforeAll {
        $runResult = New-TestFullRun
        $posts = @(ConvertTo-AccountHistoryPost -RunResult $runResult -Install '9a7c5e3b-1d2f-4a6b-8c0d-e1f2a3b4c5d6')
        $post = $posts[0]
        $json = $post | ConvertTo-Json -Depth 6 -Compress
    }

    It 'builds one post with the header fields' {
        $posts.Count | Should -Be 1
        @($post.Keys) | Should -Be @('schema', 'run_id', 'install', 'version', 'started', 'ended', 'success', 'error', 'read_only', 'test_run', 'counts', 'events')
        $post.schema | Should -Be 1
        $post.run_id | Should -Be '3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b'
        $post.install | Should -Be '9a7c5e3b-1d2f-4a6b-8c0d-e1f2a3b4c5d6'
        $post.version | Should -Be '26.11.20.0'
        $post.success | Should -BeTrue
        $post.error | Should -Be ''
        $post.read_only | Should -BeFalse
        $post.test_run | Should -BeFalse
        $post.counts.managed | Should -Be 1840
        @($post.counts.Keys) | Should -Be @('managed', 'create', 'update', 'deactivate', 'group_add', 'group_remove', 'failed')
        $post.counts.group_add | Should -Be 3
    }

    It 'turns the run''s local times and each write''s local stamp into UTC' {
        $post.started | Should -Be (ConvertTo-ExpectedUtc $runResult.RunStart)
        $post.ended | Should -Be (ConvertTo-ExpectedUtc $runResult.RunEnd)
        $post.started | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
        $post.events[0].at | Should -Be (ConvertTo-ExpectedUtc ([datetime]::new(2026, 11, 17, 8, 0, 20, [DateTimeKind]::Local)))
        $post.events[7].at | Should -Be (ConvertTo-ExpectedUtc ([datetime]::new(2026, 11, 17, 8, 0, 30, [DateTimeKind]::Local)))
    }

    It 'makes one event per Applied record, in order, n from 0' {
        $post.events.Count | Should -Be 8
        @($post.events | ForEach-Object { $_.n }) | Should -Be @(0, 1, 2, 3, 4, 5, 6, 7)
        @($post.events | ForEach-Object { $_.action }) | Should -Be @('Create', 'Update', 'Rename', 'Move', 'Deactivate', 'GroupAdd', 'GroupRemove', 'Update')
        $post.events[5].directory | Should -Be 'Google'
        $post.events[5].person_id | Should -Be '10001'
        $post.events[5].target | Should -Be 'Staff - High School'
        $post.events[5].success | Should -BeFalse
        $post.events[5].error | Should -Be '(404) Resource Not Found: groupKey'
        $post.events[0].error | Should -Be ''
    }

    It 'gives an AD update its changes with to and from, a Replace entry included and the left-out keys absent' {
        $update = $post.events[1]
        @($update.changes.name) | Should -Be @('Enabled', 'Office', 'PasswordNeverExpires', 'EmployeeType', 'extensionAttribute2', 'Title')

        $title = Get-TestChange $update 'Title'
        $title.to | Should -Be 'Teacher'
        $title.from | Should -Be 'Aide'

        # Office is compared against physicalDeliveryOfficeName - that is where from is read
        (Get-TestChange $update 'Office').from | Should -Be 'Main'
        (Get-TestChange $update 'Office').to | Should -Be 'North'

        (Get-TestChange $update 'Enabled').to | Should -Be 'true'
        (Get-TestChange $update 'Enabled').from | Should -Be 'true'

        # A Replace entry is a change under its own name; an attribute the object lacks reads ""
        (Get-TestChange $update 'extensionAttribute2').to | Should -Be 'Coach'
        (Get-TestChange $update 'extensionAttribute2').from | Should -Be ''
        (Get-TestChange $update 'EmployeeType').from | Should -Be 'STAFF'

        # PasswordNeverExpires is a flag, not a password: sent, from the same-named property
        (Get-TestChange $update 'PasswordNeverExpires').to | Should -Be 'true'
        (Get-TestChange $update 'PasswordNeverExpires').from | Should -Be 'false'

        foreach ($leftOut in 'Identity', 'Division', 'Replace', 'Description', 'AccountPassword', 'Password') {
            Get-TestChange $update $leftOut | Should -BeNullOrEmpty
        }
    }

    It 'gives a rename and a move their one change' {
        $rename = $post.events[2]
        $rename.changes.Count | Should -Be 1
        $rename.changes[0].name | Should -Be 'Name'
        $rename.changes[0].to | Should -Be 'Testy User 10001'
        $rename.changes[0].from | Should -Be 'Test User 10001'

        $move = $post.events[3]
        $move.changes.Count | Should -Be 1
        $move.changes[0].name | Should -Be 'OrganizationalUnit'
        $move.changes[0].to | Should -Be 'OU=Teachers,DC=example,DC=org'
        $move.changes[0].from | Should -Be 'OU=Staff,DC=example,DC=org'
    }

    It 'reads a move''s old OU past a comma the name escapes' {
        $record = New-TestSourceRecord -PersonID '007' -ADObject (New-TestADUser -DistinguishedName 'CN=Ann Smith\, Jr. 007,OU=Staff,DC=x')
        $moveRun = New-TestAccountHistoryRun -SourceData @($record) `
            -MoveList @([PSCustomObject]@{ CN = 'Ann Smith, Jr. 007'; PersonID = '007'; ADUserID = 'g'; NewOrgUnit = 'OU=Teachers,DC=x' }) `
            -Applied @(New-TestApplied -Directory AD -Action Move -PersonID '007' -Target 'Ann Smith, Jr. 007')

        $move = @(ConvertTo-AccountHistoryPost -RunResult $moveRun -Install 'i')[0].events[0]

        $move.changes[0].from | Should -Be 'OU=Staff,DC=x'
    }

    It 'reads a write''s stamp in the box''s culture first, so another calendar keeps its year' {
        $local = [datetime]::new(2026, 11, 17, 8, 0, 20, [DateTimeKind]::Local)
        $savedCulture = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('th-TH')
            # As the core writes it there: the Thai Buddhist year
            $stamp = $local.ToString('yyyy-MM-dd HH:mm:ss')
            $thaiRun = New-TestAccountHistoryRun -Applied @(New-TestApplied -Directory AD -Action Create -PersonID '1' -Target 'x' -Timestamp $stamp)

            $at = @(ConvertTo-AccountHistoryPost -RunResult $thaiRun -Install 'i')[0].events[0].at
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $savedCulture
        }

        $stamp | Should -BeLike '2569-*'
        $at | Should -Be (ConvertTo-ExpectedUtc $local)
    }

    It 'gives a Google update its changes from the fields they were compared against, plumbing left out' {
        $update = $post.events[7]
        @($update.changes.name) | Should -Be @('FirstName', 'OrgUnitPath', 'PrimaryEmail', 'Suspended')

        (Get-TestChange $update 'PrimaryEmail').from | Should -Be 'tuser@example.org'
        (Get-TestChange $update 'PrimaryEmail').to | Should -Be 'testy@example.org'
        (Get-TestChange $update 'FirstName').from | Should -Be 'Test'
        (Get-TestChange $update 'OrgUnitPath').from | Should -Be '/Staff'
        (Get-TestChange $update 'Suspended').to | Should -Be 'false'
        (Get-TestChange $update 'Suspended').from | Should -Be 'true'

        Get-TestChange $update 'GoogleUserID' | Should -BeNullOrEmpty
        Get-TestChange $update 'RemoveAlias' | Should -BeNullOrEmpty
    }

    It 'never carries a password key or a SecureString' {
        # The one name holding "password" that is sent is the PasswordNeverExpires flag
        ($json -replace 'PasswordNeverExpires', '') | Should -Not -Match '(?i)password'
        $json | Should -Not -Match 'SecureString'
        $json | Should -Not -Match 'Hunter2'
    }

    It 'gives a write with no change-list item an empty list' {
        foreach ($index in 0, 4, 5, 6) {
            $post.events[$index].changes.Count | Should -Be 0
        }
        $json | Should -Match '"n":0,[^{}]*"changes":\[\]'
    }

    It 'leaves the RunResult as it was' {
        $runResult.AD.UsersToUpdate.UpdateList[0].Splat.ContainsKey('Identity') | Should -BeTrue
        $runResult.RunId | Should -Be '3F2B8C1E-6D1A-4F0E-9B7A-2C5D8E9F0A1B'
    }

    It 'cuts text to its bound on a UTF-8 boundary' {
        $longTarget = 'a' + ([string]::new([char]0x00E9, 300))   # 601 bytes; 512 falls inside an e-acute
        $applied = @(New-TestApplied -Directory AD -Action Create -PersonID ('9' * 100) -Target $longTarget -Success $false -ErrorText ('x' * 70000))
        $updateList = @([PSCustomObject]@{ CN = 'x'; PersonID = ('9' * 100); Splat = @{ Identity = 'g'; Title = ('t' * 2000) } })
        $applied += New-TestApplied -Directory AD -Action Update -PersonID ('9' * 100) -Target 'x'
        $cutRun = New-TestAccountHistoryRun -Applied $applied -UpdateList $updateList -RunError ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('e' * 70000), 'Test', 'NotSpecified', $null))

        $cut = @(ConvertTo-AccountHistoryPost -RunResult $cutRun -Install 'i')[0]
        $utf8 = [System.Text.Encoding]::UTF8

        $utf8.GetByteCount($cut.events[0].target) | Should -Be 511
        $cut.events[0].target | Should -Be ('a' + [string]::new([char]0x00E9, 255))
        $cut.events[0].person_id.Length | Should -Be 64
        $utf8.GetByteCount($cut.events[0].error) | Should -Be 65536
        $utf8.GetByteCount($cut.error) | Should -Be 65536
        (Get-TestChange $cut.events[1] 'Title').to.Length | Should -Be 1024
    }

    It 'posts a read-only run with no events' {
        $readOnlyPosts = @(ConvertTo-AccountHistoryPost -RunResult (New-TestAccountHistoryRun -ReadOnly $true) -Install 'i')
        $readOnlyPosts.Count | Should -Be 1
        $readOnlyPosts[0].read_only | Should -BeTrue
        $readOnlyPosts[0].events.Count | Should -Be 0
        ($readOnlyPosts[0] | ConvertTo-Json -Depth 6 -Compress) | Should -Match '"events":\[\]'
    }
}

Describe 'ConvertTo-AccountHistoryPost parts' {
    It 'splits a run of more than 10,000 writes into posts whose n run on without a gap or a repeat' {
        $applied = for ($i = 0; $i -lt 10001; $i++) {
            [PSCustomObject]@{ Timestamp = '2026-11-17 08:00:20'; Directory = 'AD'; Action = 'GroupAdd'; PersonID = "$i"; Target = 'Students'; Success = $true; Error = $null }
        }
        $posts = @(ConvertTo-AccountHistoryPost -RunResult (New-TestAccountHistoryRun -Applied $applied) -Install 'i')

        $posts.Count | Should -Be 2
        $posts[0].events.Count | Should -Be 10000
        $posts[1].events.Count | Should -Be 1
        $posts[1].run_id | Should -Be $posts[0].run_id
        $posts[1].started | Should -Be $posts[0].started
        $allN = @($posts | ForEach-Object { $_.events } | ForEach-Object { $_.n })
        $allN.Count | Should -Be 10001
        ($allN -join ',') | Should -Be ((0..10000) -join ',')
    }

    It 'splits a post before it reaches 6 MB' {
        $applied = for ($i = 0; $i -lt 100; $i++) {
            [PSCustomObject]@{ Timestamp = '2026-11-17 08:00:20'; Directory = 'AD'; Action = 'Create'; PersonID = "$i"; Target = 'x'; Success = $false; Error = ('e' * 65536) }
        }
        $posts = @(ConvertTo-AccountHistoryPost -RunResult (New-TestAccountHistoryRun -Applied $applied) -Install 'i')

        $posts.Count | Should -Be 2
        foreach ($post in $posts) {
            [System.Text.Encoding]::UTF8.GetByteCount(($post | ConvertTo-Json -Depth 6 -Compress)) | Should -BeLessThan 6MB
        }
        (@($posts | ForEach-Object { $_.events } | ForEach-Object { $_.n }) -join ',') | Should -Be ((0..99) -join ',')
    }
}

Describe 'Send-AccountHistorySpool' {
    BeforeEach {
        $spool = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $refused = Join-Path $spool 'refused'
        New-Item -Path $spool -ItemType Directory | Out-Null
        $files = foreach ($name in 'a-001.json', 'b-001.json', 'c-001.json') {
            $path = Join-Path $spool $name
            Set-Content -Path $path -Value '{}'
            Get-Item -LiteralPath $path
        }
        $script:sent = [System.Collections.Generic.List[string]]::new()
        $script:statusByName = @{ 'a-001.json' = 200; 'b-001.json' = 200; 'c-001.json' = 200 }
        Mock Write-Log {}
        Mock Send-AccountHistoryPost {
            $name = Split-Path $Path -Leaf
            $script:sent.Add($name)
            $script:statusByName[$name]
        }
    }

    It 'sends in the order given and deletes each file a 200 took' {
        $result = Send-AccountHistorySpool -Files $files -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused

        @($script:sent) | Should -Be @('a-001.json', 'b-001.json', 'c-001.json')
        $result.Sent | Should -Be 3
        @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File).Count | Should -Be 0
        Should -Invoke Send-AccountHistoryPost -Times 3 -Exactly -ParameterFilter {
            $TimeoutSeconds -eq 10 -and $Token -eq 'tok' -and $Uri -eq 'https://accounts.example.org/api/accounts/runs' -and $Client -is [System.Net.Http.HttpClient]
        }
    }

    It 'moves a file refused with <Status> to refused\ and goes on' -ForEach @(
        @{ Status = 400 }, @{ Status = 413 }
    ) {
        $script:statusByName['a-001.json'] = $Status

        $result = Send-AccountHistorySpool -Files $files -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused

        $result.Refused | Should -Be 1
        $result.Sent | Should -Be 2
        Test-Path (Join-Path $refused 'a-001.json') | Should -BeTrue
        Test-Path (Join-Path $spool 'a-001.json') | Should -BeFalse
        @($script:sent).Count | Should -Be 3
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like "*refused (status $Status)*" }
    }

    It 'keeps the file and stops on <Status>, the next file not tried' -ForEach @(
        @{ Status = 503 }, @{ Status = 404 }, @{ Status = 401 }, @{ Status = 302 }
    ) {
        $script:statusByName['b-001.json'] = $Status

        $result = Send-AccountHistorySpool -Files $files -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused

        @($script:sent) | Should -Be @('a-001.json', 'b-001.json')
        $result.Sent | Should -Be 1
        Test-Path (Join-Path $spool 'b-001.json') | Should -BeTrue
        Test-Path (Join-Path $spool 'c-001.json') | Should -BeTrue
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like "*status $Status*" }
    }

    It 'keeps the file and stops when the web call throws' {
        Mock Send-AccountHistoryPost {
            $script:sent.Add((Split-Path $Path -Leaf))
            throw [System.Net.Http.HttpRequestException]::new('No such host is known.')
        }

        $result = Send-AccountHistorySpool -Files $files -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused

        @($script:sent) | Should -Be @('a-001.json')
        $result.Sent | Should -Be 0
        @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File).Count | Should -Be 3
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*HttpRequestException*' }
    }

    It 'stops sending once its 30 seconds are spent' {
        $script:clockStart = [datetime]::new(2026, 11, 17, 8, 0, 0)
        $script:clockCalls = 0
        # The deadline, then the first file's check, are at the start; the second file's is 31 s on.
        Mock Get-Date {
            $script:clockCalls++
            if ($script:clockCalls -le 2) { $script:clockStart } else { $script:clockStart.AddSeconds(31) }
        }

        $result = Send-AccountHistorySpool -Files $files -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused

        @($script:sent) | Should -Be @('a-001.json')
        $result.Sent | Should -Be 1
        Test-Path (Join-Path $spool 'b-001.json') | Should -BeTrue
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*after 30 seconds*' }
    }

    It 'never waits past the 30 seconds on one request' {
        $script:clockStart = [datetime]::new(2026, 11, 17, 8, 0, 0)
        $script:clockCalls = 0
        Mock Get-Date {
            $script:clockCalls++
            if ($script:clockCalls -le 1) { $script:clockStart } else { $script:clockStart.AddSeconds(26) }
        }

        Send-AccountHistorySpool -Files @($files[0]) -Uri 'https://accounts.example.org/api/accounts/runs' -Token 'tok' -RefusedFolder $refused | Out-Null

        Should -Invoke Send-AccountHistoryPost -Times 1 -Exactly -ParameterFilter { $TimeoutSeconds -eq 4 }
    }
}

Describe 'Invoke-PluginPostRunAccountHistory' {
    BeforeEach {
        $dataRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $dataRoot -ItemType Directory | Out-Null
        $spool = Join-Path $dataRoot 'AccountHistory'
        $script:sent = [System.Collections.Generic.List[string]]::new()
        $script:status = 200

        Mock Write-Log {}
        Mock Get-IDBridgeConfig { @{ Paths = @{ DataRoot = $dataRoot } } }
        Mock Get-IDBridgeSiteID { '9a7c5e3b-1d2f-4a6b-8c0d-e1f2a3b4c5d6' }
        Mock Get-IDBridgeSecret { 'tok-SECRET-4711' }
        Mock Send-AccountHistoryPost {
            $script:sent.Add((Split-Path $Path -Leaf))
            $script:status
        }
    }

    It 'throws while the address is the placeholder' {
        { Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun) } | Should -Throw '*placeholder*'
        Should -Invoke Send-AccountHistoryPost -Times 0 -Exactly
    }

    It 'refuses an address that is not https:// and leaves the run spooled' {
        . (New-EditedPlugin -Address 'http://accounts.example.org')

        { Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun) } | Should -Not -Throw

        Should -Invoke Send-AccountHistoryPost -Times 0 -Exactly
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*https://*' }
        @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File).Count | Should -Be 1
    }

    It 'does not post a RunResult with <Case>' -ForEach @(
        @{ Case = 'no RunId'; RunId = $null; SchemaVersion = 1; Expected = '*no RunId*' }
        @{ Case = 'SchemaVersion 2'; RunId = '3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b'; SchemaVersion = 2; Expected = '*SchemaVersion is 2*' }
    ) {
        . (New-EditedPlugin -Address 'https://accounts.example.org')

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestAccountHistoryRun -RunId $RunId -SchemaVersion $SchemaVersion)

        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like $Expected }
        Should -Invoke Write-Log -Times 1 -Exactly
        Should -Invoke Send-AccountHistoryPost -Times 0 -Exactly
        Test-Path $spool | Should -BeFalse
    }

    It 'spools the run as UTF-8 without a BOM, sends it, and deletes it on a 200' {
        . (New-EditedPlugin -Address 'https://accounts.example.org/')

        $output = Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        $output | Should -BeNullOrEmpty
        $stamp = ([datetime]::new(2026, 11, 17, 8, 0, 2, [DateTimeKind]::Local)).ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture)
        @($script:sent) | Should -Be @("$stamp-3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b-001.json")
        Should -Invoke Send-AccountHistoryPost -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://accounts.example.org/api/accounts/runs' }
        @(Get-ChildItem -LiteralPath $spool -File).Count | Should -Be 0
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Message -like '*sent 1 run post(s), set aside 0, 0 waiting*' }
    }

    It 'writes the spooled file as UTF-8 without a byte-order mark' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        $script:status = 503

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        $file = @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File)[0]
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $bytes[0] | Should -Be ([byte][char]'{')
        ([System.IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json).run_id | Should -Be '3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b'
        @(Get-ChildItem -LiteralPath $spool -Filter '*.tmp' -File).Count | Should -Be 0
    }

    It 'sends the oldest spooled post first and the new run last' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        New-Item -Path $spool -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $spool '20261116T080002Z-bbbbbbbb-0000-0000-0000-000000000000-001.json') -Value '{}'
        Set-Content -Path (Join-Path $spool '20261115T080002Z-aaaaaaaa-0000-0000-0000-000000000000-001.json') -Value '{}'
        # Spooled under a start later than the new run's (a clock moved back) - still before the new run
        Set-Content -Path (Join-Path $spool '20991231T000000Z-cccccccc-0000-0000-0000-000000000000-001.json') -Value '{}'

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        $script:sent.Count | Should -Be 4
        $script:sent[0] | Should -Be '20261115T080002Z-aaaaaaaa-0000-0000-0000-000000000000-001.json'
        $script:sent[1] | Should -Be '20261116T080002Z-bbbbbbbb-0000-0000-0000-000000000000-001.json'
        $script:sent[2] | Should -Be '20991231T000000Z-cccccccc-0000-0000-0000-000000000000-001.json'
        $script:sent[3] | Should -BeLike '*-3f2b8c1e-6d1a-4f0e-9b7a-2c5d8e9f0a1b-001.json'
    }

    It 'deletes the posts past 30 days and the oldest beyond 3,000, with one Warn' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        Mock Get-IDBridgeSecret { throw "IDBridge secret 'AccountHistory-Token' was not found in vault." }
        New-Item -Path $spool -ItemType Directory | Out-Null

        $expired = Join-Path $spool '20260901T000000Z-eeeeeeee-0000-0000-0000-000000000000-001.json'
        Set-Content -Path $expired -Value '{}'
        (Get-Item -LiteralPath $expired).LastWriteTime = (Get-Date).AddDays(-31)
        for ($i = 0; $i -lt 3001; $i++) {
            [System.IO.File]::WriteAllText((Join-Path $spool ('20261001T{0:D6}Z-dddddddd-0000-0000-0000-000000000000-001.json' -f $i)), '{}')
        }

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        $left = @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File)
        $left.Count | Should -Be 3000
        Test-Path -LiteralPath $expired | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $spool '20261001T000000Z-dddddddd-0000-0000-0000-000000000000-001.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $spool '20261001T000001Z-dddddddd-0000-0000-0000-000000000000-001.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $spool '20261001T000002Z-dddddddd-0000-0000-0000-000000000000-001.json') | Should -BeTrue
        @($left | Where-Object { $_.Name -like '*-3f2b8c1e-*' }).Count | Should -Be 1
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*deleted 3 unsent run post(s)*' }
    }

    It 'deletes a half-written post a previous run left behind, with one Trace line' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        New-Item -Path $spool -ItemType Directory | Out-Null
        Set-Content -Path (Join-Path $spool '20261116T080002Z-aaaaaaaa-0000-0000-0000-000000000000-001.json.tmp') -Value '{"sch'
        Set-Content -Path (Join-Path $spool '20261116T081502Z-bbbbbbbb-0000-0000-0000-000000000000-001.json.tmp') -Value '{"sch'

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        @(Get-ChildItem -LiteralPath $spool -Filter '*.tmp' -File).Count | Should -Be 0
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Trace' -and $Message -like '*deleted 2 half-written run post(s)*' }
        $script:sent.Count | Should -Be 1
    }

    It 'deletes refused posts older than 30 days' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        $refused = Join-Path $spool 'refused'
        New-Item -Path $refused -ItemType Directory -Force | Out-Null
        $old = Join-Path $refused 'old-001.json'
        $recent = Join-Path $refused 'recent-001.json'
        Set-Content -Path $old -Value '{}'
        Set-Content -Path $recent -Value '{}'
        (Get-Item -LiteralPath $old).LastWriteTime = (Get-Date).AddDays(-31)

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        Test-Path -LiteralPath $old | Should -BeFalse
        Test-Path -LiteralPath $recent | Should -BeTrue
    }

    It 'leaves the run spooled with a Warn naming the secret when the token is missing' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        Mock Get-IDBridgeSecret { throw "IDBridge secret 'AccountHistory-Token' was not found in vault." }

        { Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun) } | Should -Not -Throw

        Should -Invoke Send-AccountHistoryPost -Times 0 -Exactly
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like "*'AccountHistory-Token'*" }
        @(Get-ChildItem -LiteralPath $spool -Filter '*.json' -File).Count | Should -Be 1
    }

    It 'puts the token in no log line and no spooled file' {
        . (New-EditedPlugin -Address 'https://accounts.example.org')
        $script:status = 503

        Invoke-PluginPostRunAccountHistory -RunResult (New-TestFullRun)

        Should -Invoke Get-IDBridgeSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'AccountHistory-Token' -and $AsPlainText }
        Should -Invoke Send-AccountHistoryPost -Times 1 -Exactly -ParameterFilter { $Token -eq 'tok-SECRET-4711' }
        Should -Invoke Write-Log -Times 0 -Exactly -ParameterFilter { $Message -like '*tok-SECRET-4711*' }
        @(Get-ChildItem -LiteralPath $spool -Recurse -File).Count | Should -BeGreaterThan 0
        Get-ChildItem -LiteralPath $spool -Recurse -File | Select-String -SimpleMatch 'tok-SECRET-4711' | Should -BeNullOrEmpty
    }
}

Describe 'Send-AccountHistoryPost against a loopback listener' {
    BeforeAll {
        # A listener on a free loopback port, answering in a runspace of its own (the test's
        # thread is blocked in the send). Respond is passed as text: a scriptblock is bound
        # to the runspace that made it.
        function Start-TestListener {
            param ([string]$Respond, [int]$Requests = 1)

            $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $probe.Start()
            $port = $probe.LocalEndpoint.Port
            $probe.Stop()

            $listener = [System.Net.HttpListener]::new()
            $listener.Prefixes.Add("http://127.0.0.1:$port/")
            $listener.Start()

            $seen = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            $runspace = [powershell]::Create()
            $null = $runspace.AddScript({
                param ($listener, $respond, $requests, $seen)
                for ($i = 0; $i -lt $requests; $i++) {
                    $context = $listener.GetContext()
                    $reader = [System.IO.StreamReader]::new($context.Request.InputStream)
                    $null = $seen.Add([PSCustomObject]@{
                        Path          = $context.Request.Url.AbsolutePath
                        Authorization = $context.Request.Headers['Authorization']
                        ContentType   = $context.Request.ContentType
                        Body          = $reader.ReadToEnd()
                    })
                    & ([scriptblock]::Create($respond)) $context
                }
            }).AddArgument($listener).AddArgument($Respond).AddArgument($Requests).AddArgument($seen)
            $handle = $runspace.BeginInvoke()

            [PSCustomObject]@{ BaseUri = "http://127.0.0.1:$port"; Listener = $listener; Runspace = $runspace; Handle = $handle; Seen = $seen }
        }

        function Stop-TestListener {
            param ($Server)
            $Server.Listener.Close()
            $Server.Runspace.Stop()
            $Server.Runspace.Dispose()
        }

        function New-TestClient {
            $handler = [System.Net.Http.HttpClientHandler]::new()
            $handler.AllowAutoRedirect = $false
            [System.Net.Http.HttpClient]::new($handler)
        }

        $postPath = Join-Path $TestDrive 'post-001.json'
        [System.IO.File]::WriteAllText($postPath, '{"schema":1}', [System.Text.UTF8Encoding]::new($false))
    }

    It 'comes back within its timeout when the site sends its headers and then stalls' {
        $server = Start-TestListener -Respond {
            param ($context)
            $context.Response.StatusCode = 200
            $context.Response.ContentLength64 = 1000
            $context.Response.OutputStream.Write([byte[]]::new(10), 0, 10)
            $context.Response.OutputStream.Flush()
            Start-Sleep -Seconds 30
        }.ToString()
        $client = New-TestClient
        try {
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $thrown = $null
            try {
                Send-AccountHistoryPost -Client $client -Uri "$($server.BaseUri)/api/accounts/runs" -Token 'tok' -Path $postPath -TimeoutSeconds 2 | Out-Null
            }
            catch { $thrown = $_ }
            $clock.Stop()

            $thrown | Should -Not -BeNullOrEmpty
            $clock.Elapsed.TotalSeconds | Should -BeLessThan 5
            $server.Seen.Count | Should -Be 1
        }
        finally {
            $client.Dispose()
            Stop-TestListener $server
        }
    }

    It 'returns 200 for a 200 with a small body, the file''s bytes sent with the bearer token' {
        $server = Start-TestListener -Respond {
            param ($context)
            $body = [System.Text.Encoding]::UTF8.GetBytes('{"run":"kept","events":{"kept":0,"held":0,"skipped":0},"reasons":{}}')
            $context.Response.StatusCode = 200
            $context.Response.ContentType = 'application/json'
            $context.Response.ContentLength64 = $body.Length
            $context.Response.OutputStream.Write($body, 0, $body.Length)
            $context.Response.Close()
        }.ToString()
        $client = New-TestClient
        try {
            $status = Send-AccountHistoryPost -Client $client -Uri "$($server.BaseUri)/api/accounts/runs" -Token 'tok' -Path $postPath -TimeoutSeconds 2

            $status | Should -Be 200
            $server.Seen[0].Path | Should -Be '/api/accounts/runs'
            $server.Seen[0].Authorization | Should -Be 'Bearer tok'
            $server.Seen[0].ContentType | Should -Be 'application/json'
            $server.Seen[0].Body | Should -Be '{"schema":1}'
        }
        finally {
            $client.Dispose()
            Stop-TestListener $server
        }
    }

    It 'never follows a redirect: the sending keeps the post on a 302' {
        # Two requests allowed: a followed redirect would reach /followed and take a 200.
        $server = Start-TestListener -Requests 2 -Respond {
            param ($context)
            if ($context.Request.Url.AbsolutePath -eq '/followed') {
                $context.Response.StatusCode = 200
            }
            else {
                $context.Response.StatusCode = 302
                $context.Response.RedirectLocation = '/followed'
            }
            $context.Response.Close()
        }.ToString()
        $spool = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $spool -ItemType Directory | Out-Null
        $file = Join-Path $spool 'a-001.json'
        [System.IO.File]::WriteAllText($file, '{}')
        Mock Write-Log {}
        try {
            Send-AccountHistorySpool -Files @(Get-Item -LiteralPath $file) -Uri "$($server.BaseUri)/api/accounts/runs" -Token 'tok' -RefusedFolder (Join-Path $spool 'refused') | Out-Null

            Test-Path -LiteralPath $file | Should -BeTrue
            $server.Seen.Count | Should -Be 1
            Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*status 302*' }
        }
        finally {
            Stop-TestListener $server
        }
    }
}
