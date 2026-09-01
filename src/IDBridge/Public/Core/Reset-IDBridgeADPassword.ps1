<#
.SYNOPSIS
GUI tool: multi-select AD org units and reset every account's password to its Keysmith passphrase.

.DESCRIPTION
Operations tool, run by hand — never called by the pipeline. Opens a Windows Forms window with
the domain's OU tree (checkboxes; checking an OU checks everything under it), the Keysmith
settings (nonce and API token — picked from the vault by secret name, with masked manual entry
as a fallback — plus mode, word count, and an optional word-list rev to regenerate an earlier
era's passphrases; leave rev blank for the server's latest), and the run options. "Load Users"
lists every matching account in the checked OUs for review; "Reset Passwords" asks for explicit
confirmation with the exact account count, then requests the deterministic passphrases in bulk
(Get-ADUsersToResetPassword -> New-Passphrase) and applies Set-ADAccountPassword -Reset per
account, optionally also setting ChangePasswordAtLogon.

Because Keysmith passphrases are deterministic, the phrases never need to be stored — anyone
with the nonce can regenerate them at keysmith.scnlabs.net. Optionally the run can export a
username/passphrase/OU CSV to the Exports folder for handout (off by default). "Export
Passphrases" instead writes that same CSV for the loaded users WITHOUT touching AD —
regenerating what the current passwords already are, e.g. for login slips. The exported
phrases match the accounts' current passwords only when the nonce, mode, word count, and
word-list rev match what the passwords were last set with — pin the rev for accounts from an
earlier era. Passphrases are never written to the log.

This tool writes to AD when confirmed regardless of Debug.readOnly — it is interactive and gated
by its own confirmation dialog instead (the pipeline's ReadOnly/ChangeThreshold gates protect
unattended runs, which this is not). Requires Windows (WinForms), an STA session (the pwsh
default), and the ActiveDirectory module (AD.enabled).

.PARAMETER RootPath
Base dir for Config/Logs/Exports/Plugins/Data/Vault. Defaults to C:\IDBridge.

.OUTPUTS
[pscustomobject] @{ Total; Succeeded; Failed; ExportPath } for the last reset run (zeroes when
the window is closed without running one; an export-only run fills ExportPath only).

.EXAMPLE
Reset-IDBridgeADPassword

.EXAMPLE
Reset-IDBridgeADPassword -RootPath 'C:\IDBridge'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-31
#>
function Reset-IDBridgeADPassword {
    [CmdletBinding()]
    param (
        [string]$RootPath = "C:\IDBridge"
    )

    #region Environment Guards
    if (-not $IsWindows) {
        Throw "Reset-IDBridgeADPassword requires Windows - the GUI uses Windows Forms."
    }

    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Throw "Reset-IDBridgeADPassword requires an STA session (the pwsh default). Start pwsh without -MTA."
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        Throw "Reset-IDBridgeADPassword could not load Windows Forms: $_"
    }
    #endregion Environment Guards



    #region Import Configuration
    try { Initialize-IDBridge -RootPath $RootPath } catch { Throw }

    try { $IDConfig = Get-IDBridgeConfig } catch { Throw }

    if ($IDConfig.AD.enabled -ne $true -or -not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
        Write-Log -Message "Reset: AD is disabled or the ActiveDirectory module is unavailable - nothing to reset." -Level Error
        Throw "Reset: AD is disabled or the ActiveDirectory module is unavailable - nothing to reset."
    }
    #endregion Import Configuration



    #region Fetch Org Units
    try {
        Write-Log -Message "Reset: Fetching Org Units" -Level Trace
        $orgUnits = @(Get-ADOrganizationalUnit -LDAPFilter '(name=*)' | Select-Object -ExpandProperty DistinguishedName)

        if ($orgUnits.Count -eq 0) {
            Throw "Reset: Connected to AD but no org units fetched"
        }
    }
    catch {
        Write-Log -Message "Reset: No org units fetched" -Level Error
        Throw $_
    }
    #endregion Fetch Org Units



    #region Build Form
    $ManualEntry = '(enter manually)'

    #Shared mutable state for the event handlers (a hashtable so handlers can write to it -
    #plain variable assignment inside a handler would only create a handler-local copy)
    $state = @{
        Users     = @()
        ItemByDN  = @{}
        Total     = 0
        Succeeded = 0
        Failed    = 0
        ExportPath = $null
    }

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "IDBridge - AD Password Reset"
    $form.Size = [System.Drawing.Size]::new(1010, 680)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    $lblTree = [System.Windows.Forms.Label]::new()
    $lblTree.Text = "Check the org units to reset:"
    $lblTree.Location = [System.Drawing.Point]::new(10, 10)
    $lblTree.AutoSize = $true
    $form.Controls.Add($lblTree)

    $treeView = [System.Windows.Forms.TreeView]::new()
    $treeView.Location = [System.Drawing.Point]::new(10, 32)
    $treeView.Size = [System.Drawing.Size]::new(375, 600)
    $treeView.CheckBoxes = $true
    $form.Controls.Add($treeView)

    #Checking an OU checks everything under it. Programmatic sets re-fire AfterCheck with
    #Action Unknown, which the guard skips - only the user's own click propagates.
    $treeView.add_AfterCheck({
        param($senderObj, $e)
        if ($e.Action -ne [System.Windows.Forms.TreeViewAction]::Unknown) {
            $stack = [System.Collections.Stack]::new()
            $stack.Push($e.Node)
            while ($stack.Count -gt 0) {
                foreach ($child in $stack.Pop().Nodes) {
                    $child.Checked = $e.Node.Checked
                    $stack.Push($child)
                }
            }
        }
    })

    #Build the OU tree from the DN list - parents first (sorted by DN depth), each node keyed
    #by DN so children find their parent; an OU whose parent is not an OU (domain root,
    #containers) becomes a top-level node. The first-RDN regex honors escaped commas.
    $nodeByDN = @{}
    foreach ($dn in ($orgUnits | Sort-Object { ($_ -split '(?<!\\),').Count }, { $_ })) {
        $node = [System.Windows.Forms.TreeNode]::new()
        $node.Text = ([regex]::Match($dn, '^OU=((?:\\.|[^,\\])*)').Groups[1].Value -replace '\\(.)', '$1')
        $node.Tag = $dn

        $parentDN = $dn -replace '^OU=(?:\\.|[^,\\])*,', ''
        if ($nodeByDN.ContainsKey($parentDN)) {
            $nodeByDN[$parentDN].Nodes.Add($node) | Out-Null
        } else {
            $treeView.Nodes.Add($node) | Out-Null
        }
        $nodeByDN[$dn] = $node
    }

    #Keysmith settings
    $grpKeysmith = [System.Windows.Forms.GroupBox]::new()
    $grpKeysmith.Text = "Keysmith"
    $grpKeysmith.Location = [System.Drawing.Point]::new(400, 10)
    $grpKeysmith.Size = [System.Drawing.Size]::new(590, 165)
    $form.Controls.Add($grpKeysmith)

    $lblNonce = [System.Windows.Forms.Label]::new()
    $lblNonce.Text = "Nonce secret:"
    $lblNonce.Location = [System.Drawing.Point]::new(10, 28)
    $lblNonce.AutoSize = $true
    $grpKeysmith.Controls.Add($lblNonce)

    $cboNonce = [System.Windows.Forms.ComboBox]::new()
    $cboNonce.Location = [System.Drawing.Point]::new(120, 24)
    $cboNonce.Size = [System.Drawing.Size]::new(255, 23)
    $cboNonce.Items.AddRange(@('ApiKey-PassphraseNonceStudent', 'ApiKey-PassphraseNonceStaff', $ManualEntry))
    $cboNonce.SelectedIndex = 0
    $grpKeysmith.Controls.Add($cboNonce)

    $txtNonce = [System.Windows.Forms.TextBox]::new()
    $txtNonce.Location = [System.Drawing.Point]::new(120, 54)
    $txtNonce.Size = [System.Drawing.Size]::new(255, 23)
    $txtNonce.UseSystemPasswordChar = $true
    $txtNonce.Enabled = $false
    $grpKeysmith.Controls.Add($txtNonce)

    $lblToken = [System.Windows.Forms.Label]::new()
    $lblToken.Text = "Token secret:"
    $lblToken.Location = [System.Drawing.Point]::new(10, 92)
    $lblToken.AutoSize = $true
    $grpKeysmith.Controls.Add($lblToken)

    $cboToken = [System.Windows.Forms.ComboBox]::new()
    $cboToken.Location = [System.Drawing.Point]::new(120, 88)
    $cboToken.Size = [System.Drawing.Size]::new(255, 23)
    $cboToken.Items.AddRange(@('ApiKey-Passphrase', $ManualEntry))
    $cboToken.SelectedIndex = 0
    $grpKeysmith.Controls.Add($cboToken)

    $txtToken = [System.Windows.Forms.TextBox]::new()
    $txtToken.Location = [System.Drawing.Point]::new(120, 118)
    $txtToken.Size = [System.Drawing.Size]::new(255, 23)
    $txtToken.UseSystemPasswordChar = $true
    $txtToken.Enabled = $false
    $grpKeysmith.Controls.Add($txtToken)

    #The manual textboxes only unlock when '(enter manually)' is picked; any other text is
    #treated as a vault secret name (the defaults are what the shipped plugins use)
    $cboNonce.add_TextChanged({ $txtNonce.Enabled = ($cboNonce.Text -eq $ManualEntry) })
    $cboToken.add_TextChanged({ $txtToken.Enabled = ($cboToken.Text -eq $ManualEntry) })

    $lblMode = [System.Windows.Forms.Label]::new()
    $lblMode.Text = "Mode:"
    $lblMode.Location = [System.Drawing.Point]::new(400, 28)
    $lblMode.AutoSize = $true
    $grpKeysmith.Controls.Add($lblMode)

    $cboMode = [System.Windows.Forms.ComboBox]::new()
    $cboMode.Location = [System.Drawing.Point]::new(480, 24)
    $cboMode.Size = [System.Drawing.Size]::new(100, 23)
    $cboMode.DropDownStyle = 'DropDownList'
    $cboMode.Items.AddRange(@('words', 'verbnoun'))
    $cboMode.SelectedIndex = 0
    $grpKeysmith.Controls.Add($cboMode)

    $lblWordCount = [System.Windows.Forms.Label]::new()
    $lblWordCount.Text = "Words:"
    $lblWordCount.Location = [System.Drawing.Point]::new(400, 60)
    $lblWordCount.AutoSize = $true
    $grpKeysmith.Controls.Add($lblWordCount)

    $numWordCount = [System.Windows.Forms.NumericUpDown]::new()
    $numWordCount.Location = [System.Drawing.Point]::new(480, 56)
    $numWordCount.Size = [System.Drawing.Size]::new(100, 23)
    $numWordCount.Minimum = 2
    $numWordCount.Maximum = 6
    $numWordCount.Value = 3
    $grpKeysmith.Controls.Add($numWordCount)

    $cboMode.add_SelectedIndexChanged({ $numWordCount.Enabled = ($cboMode.Text -eq 'words') })

    $lblRev = [System.Windows.Forms.Label]::new()
    $lblRev.Text = "Rev (blank = latest):"
    $lblRev.Location = [System.Drawing.Point]::new(400, 92)
    $lblRev.AutoSize = $true
    $grpKeysmith.Controls.Add($lblRev)

    $txtRev = [System.Windows.Forms.TextBox]::new()
    $txtRev.Location = [System.Drawing.Point]::new(520, 88)
    $txtRev.Size = [System.Drawing.Size]::new(60, 23)
    $grpKeysmith.Controls.Add($txtRev)

    #Run options
    $grpOptions = [System.Windows.Forms.GroupBox]::new()
    $grpOptions.Text = "Options"
    $grpOptions.Location = [System.Drawing.Point]::new(400, 185)
    $grpOptions.Size = [System.Drawing.Size]::new(590, 105)
    $form.Controls.Add($grpOptions)

    $chkSubOUs = [System.Windows.Forms.CheckBox]::new()
    $chkSubOUs.Text = "Include sub-OUs"
    $chkSubOUs.Location = [System.Drawing.Point]::new(10, 25)
    $chkSubOUs.AutoSize = $true
    $chkSubOUs.Checked = $true
    $grpOptions.Controls.Add($chkSubOUs)

    $chkEnabledOnly = [System.Windows.Forms.CheckBox]::new()
    $chkEnabledOnly.Text = "Enabled accounts only"
    $chkEnabledOnly.Location = [System.Drawing.Point]::new(10, 50)
    $chkEnabledOnly.AutoSize = $true
    $chkEnabledOnly.Checked = $true
    $grpOptions.Controls.Add($chkEnabledOnly)

    $chkChangeAtLogon = [System.Windows.Forms.CheckBox]::new()
    $chkChangeAtLogon.Text = "Require password change at next logon"
    $chkChangeAtLogon.Location = [System.Drawing.Point]::new(300, 25)
    $chkChangeAtLogon.AutoSize = $true
    $grpOptions.Controls.Add($chkChangeAtLogon)

    $chkExport = [System.Windows.Forms.CheckBox]::new()
    $chkExport.Text = "Export username/passphrase CSV to Exports"
    $chkExport.Location = [System.Drawing.Point]::new(300, 50)
    $chkExport.AutoSize = $true
    $grpOptions.Controls.Add($chkExport)

    #Load + result list
    $btnLoad = [System.Windows.Forms.Button]::new()
    $btnLoad.Text = "Load Users"
    $btnLoad.Location = [System.Drawing.Point]::new(400, 300)
    $btnLoad.Size = [System.Drawing.Size]::new(120, 30)
    $form.Controls.Add($btnLoad)

    $lblCount = [System.Windows.Forms.Label]::new()
    $lblCount.Text = "No users loaded."
    $lblCount.Location = [System.Drawing.Point]::new(535, 308)
    $lblCount.AutoSize = $true
    $form.Controls.Add($lblCount)

    $listView = [System.Windows.Forms.ListView]::new()
    $listView.Location = [System.Drawing.Point]::new(400, 340)
    $listView.Size = [System.Drawing.Size]::new(590, 250)
    $listView.View = 'Details'
    $listView.FullRowSelect = $true
    $listView.Columns.Add("User", 150) | Out-Null
    $listView.Columns.Add("Username", 110) | Out-Null
    $listView.Columns.Add("Org Unit", 180) | Out-Null
    $listView.Columns.Add("Status", 130) | Out-Null
    $form.Controls.Add($listView)

    $btnReset = [System.Windows.Forms.Button]::new()
    $btnReset.Text = "Reset Passwords"
    $btnReset.Location = [System.Drawing.Point]::new(400, 600)
    $btnReset.Size = [System.Drawing.Size]::new(150, 32)
    $btnReset.Enabled = $false
    $form.Controls.Add($btnReset)

    $btnExport = [System.Windows.Forms.Button]::new()
    $btnExport.Text = "Export Passphrases"
    $btnExport.Location = [System.Drawing.Point]::new(560, 600)
    $btnExport.Size = [System.Drawing.Size]::new(160, 32)
    $btnExport.Enabled = $false
    $form.Controls.Add($btnExport)

    $btnClose = [System.Windows.Forms.Button]::new()
    $btnClose.Text = "Close"
    $btnClose.Location = [System.Drawing.Point]::new(870, 600)
    $btnClose.Size = [System.Drawing.Size]::new(120, 32)
    $btnClose.add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)
    #endregion Build Form



    #region Load Users Handler
    $btnLoad.add_Click({
        $checkedDNs = @()
        $stack = [System.Collections.Stack]::new()
        foreach ($node in $treeView.Nodes) { $stack.Push($node) }
        while ($stack.Count -gt 0) {
            $node = $stack.Pop()
            if ($node.Checked) { $checkedDNs += $node.Tag }
            foreach ($child in $node.Nodes) { $stack.Push($child) }
        }

        if ($checkedDNs.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show($form, "Check at least one org unit first.", "IDBridge", 'OK', 'Information') | Out-Null
            return
        }

        $scope = 'OneLevel'
        if ($chkSubOUs.Checked) {
            $scope = 'Subtree'
            #Checking a parent auto-checks its children - drop DNs already covered by a
            #checked ancestor so each subtree is only searched once
            $checkedDNs = @($checkedDNs | Where-Object {
                $dn = $_
                -not ($checkedDNs | Where-Object { $dn -ne $_ -and $dn.EndsWith(",$_") })
            })
        }

        $filter = '*'
        if ($chkEnabledOnly.Checked) { $filter = "Enabled -eq 'True'" }

        try {
            $found = @{}
            foreach ($dn in $checkedDNs) {
                foreach ($adUser in @(Get-ADUser -SearchBase $dn -SearchScope $scope -Filter $filter -Properties DisplayName)) {
                    $found[$adUser.DistinguishedName] = $adUser
                }
            }
        }
        catch {
            Write-Log -Message ("Reset: Failed to load users: $($_.Exception.Message)") -Level Error
            [System.Windows.Forms.MessageBox]::Show($form, "Failed to load users: $($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            return
        }

        $state.Users = @($found.Values | Sort-Object SamAccountName)
        $state.ItemByDN = @{}

        $listView.BeginUpdate()
        $listView.Items.Clear()
        foreach ($adUser in $state.Users) {
            $item = [System.Windows.Forms.ListViewItem]::new($adUser.DisplayName)
            $item.SubItems.Add($adUser.SamAccountName) | Out-Null
            $item.SubItems.Add(($adUser.DistinguishedName -replace '^CN=(?:\\.|[^,\\])*,', '')) | Out-Null
            $item.SubItems.Add("") | Out-Null
            $listView.Items.Add($item) | Out-Null
            $state.ItemByDN[$adUser.DistinguishedName] = $item
        }
        $listView.EndUpdate()

        Write-Log -Message "Reset: Loaded $($state.Users.Count) user(s) from $($checkedDNs.Count) org unit(s) for review."
        $lblCount.Text = "$($state.Users.Count) user(s) loaded from $($checkedDNs.Count) org unit(s)."
        $btnReset.Enabled = ($state.Users.Count -gt 0)
        $btnExport.Enabled = ($state.Users.Count -gt 0)
    })
    #endregion Load Users Handler



    #region Resolve Keysmith Settings
    #Shared by the reset and export handlers: nonce/token from the vault by secret name (or
    #the masked manual entry) plus the optional rev. Returns the PassphraseAPI hashtable, or
    #$null after showing the error - the caller just returns.
    $getKeysmithApi = {
        try {
            if ($cboNonce.Text -eq $ManualEntry) {
                if ([string]::IsNullOrWhiteSpace($txtNonce.Text)) { Throw "Enter the nonce, or pick a vault secret name." }
                $nonce = ConvertTo-SecureString $txtNonce.Text -AsPlainText -Force
            } else {
                $nonce = Get-IDBridgeSecret -Name $cboNonce.Text
            }

            if ($cboToken.Text -eq $ManualEntry) {
                if ([string]::IsNullOrWhiteSpace($txtToken.Text)) { Throw "Enter the API token, or pick a vault secret name." }
                $token = ConvertTo-SecureString $txtToken.Text -AsPlainText -Force
            } else {
                $token = Get-IDBridgeSecret -Name $cboToken.Text
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, "Keysmith settings error: $($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            return $null
        }

        $rev = 0
        if (-not [string]::IsNullOrWhiteSpace($txtRev.Text)) {
            if (-not [int]::TryParse($txtRev.Text, [ref]$rev) -or $rev -lt 1 -or $rev -gt 99) {
                [System.Windows.Forms.MessageBox]::Show($form, "Rev must be a number from 1 to 99, or blank for the server's latest.", "IDBridge", 'OK', 'Error') | Out-Null
                return $null
            }
        }

        $passphraseAPI = @{
            Nonce = $nonce
            AuthToken = $token
            Mode = $cboMode.Text
            WordCount = [int]$numWordCount.Value
        }
        if ($rev -gt 0) { $passphraseAPI.Rev = $rev }

        return $passphraseAPI
    }
    #endregion Resolve Keysmith Settings



    #region Reset Passwords Handler
    $btnReset.add_Click({
        $passphraseAPI = & $getKeysmithApi
        if (-not $passphraseAPI) { return }

        $confirmText = "$($state.Users.Count) AD account password(s) will be RESET to their Keysmith passphrase.`n`nThis cannot be undone. Continue?"
        $answer = [System.Windows.Forms.MessageBox]::Show($form, $confirmText, "IDBridge - Confirm Password Reset", 'YesNo', 'Warning', 'Button2')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        #Decide: fetch every passphrase up front - any Keysmith failure aborts before a single write
        try {
            $resets = @(Get-ADUsersToResetPassword -UserList $state.Users -PassphraseAPI $passphraseAPI)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, "Keysmith request failed - no passwords were changed.`n`n$($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            return
        }

        #Act: apply the resets
        Write-Log -Message "Reset: Applying password reset for $($resets.Count) user(s)."
        $state.Total = $resets.Count
        $state.Succeeded = 0
        $state.Failed = 0
        $state.ExportPath = $null
        $succeededItems = @()

        foreach ($resetItem in $resets) {
            $item = $state.ItemByDN[$resetItem.DistinguishedName]

            try {
                $itemSplat = $resetItem.Splat
                Set-ADAccountPassword @itemSplat
                Write-Log -Message "Reset: Applying: Reset password for $($resetItem.SamAccountName) ($($resetItem.DistinguishedName))."
            }
            catch {
                Write-Log -Message ($_.Exception.Message) -Level Error
                $item.SubItems[3].Text = "Failed: $($_.Exception.Message)"
                $state.Failed++
                continue
            }

            $item.SubItems[3].Text = "Reset"

            #The password is already reset - a failed flag write is a warning, not a failure
            if ($chkChangeAtLogon.Checked) {
                try {
                    Set-ADUser -Identity $resetItem.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop
                }
                catch {
                    Write-Log -Message ("Reset: Password reset for $($resetItem.SamAccountName) but ChangePasswordAtLogon could not be set: $($_.Exception.Message)") -Level Warn
                    $item.SubItems[3].Text = "Reset (logon flag failed)"
                }
            }

            $state.Succeeded++
            $succeededItems += $resetItem
        }

        #Optional handout CSV - the only place a passphrase leaves this run
        if ($chkExport.Checked -and $succeededItems.Count -gt 0) {
            try {
                $state.ExportPath = Join-Path $IDConfig.Paths.ExportsRoot ("ADPasswordReset_" + (Get-Date -Format "yyyy-MM-dd-HH.mm.ss") + ".csv")
                $succeededItems | Select-Object SamAccountName, Passphrase, @{n = 'OrgUnit'; e = { $_.DistinguishedName -replace '^CN=(?:\\.|[^,\\])*,', '' }} | Export-Csv -Path $state.ExportPath -NoTypeInformation
                Write-Log -Message "Reset: Exported $($succeededItems.Count) passphrase(s) to $($state.ExportPath). Delete the file after handout."
            }
            catch {
                Write-Log -Message ("Reset: Passphrase export failed: $($_.Exception.Message)") -Level Error
                [System.Windows.Forms.MessageBox]::Show($form, "Passphrase export failed: $($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            }
        }

        Write-Log -Message "Reset: Password reset finished - $($state.Succeeded) succeeded, $($state.Failed) failed."

        $summary = "Password reset finished.`n`nSucceeded: $($state.Succeeded)`nFailed: $($state.Failed)"
        if ($state.ExportPath) { $summary += "`n`nPassphrases exported to:`n$($state.ExportPath)" }
        [System.Windows.Forms.MessageBox]::Show($form, $summary, "IDBridge", 'OK', 'Information') | Out-Null

        #Force a fresh Load Users before another run - the list now shows results, not a plan
        $btnReset.Enabled = $false
    })
    #endregion Reset Passwords Handler



    #region Export Passphrases Handler
    #Export-only: regenerate the loaded users' deterministic passphrases and write them to a
    #CSV with each user's OU - NOTHING is written to AD. Matches the accounts' current
    #passwords only when nonce/mode/word count/rev match what they were last set with.
    $btnExport.add_Click({
        $passphraseAPI = & $getKeysmithApi
        if (-not $passphraseAPI) { return }

        $confirmText = "$($state.Users.Count) passphrase(s) will be generated and written in PLAIN TEXT to the Exports folder.`n`nNo passwords are changed. Continue?"
        $answer = [System.Windows.Forms.MessageBox]::Show($form, $confirmText, "IDBridge - Confirm Passphrase Export", 'YesNo', 'Warning', 'Button2')
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        try {
            $resets = @(Get-ADUsersToResetPassword -UserList $state.Users -PassphraseAPI $passphraseAPI -ExportOnly)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show($form, "Keysmith request failed - nothing was exported.`n`n$($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            return
        }

        try {
            $state.ExportPath = Join-Path $IDConfig.Paths.ExportsRoot ("ADPasswordExport_" + (Get-Date -Format "yyyy-MM-dd-HH.mm.ss") + ".csv")
            $resets | Select-Object SamAccountName, Passphrase, @{n = 'OrgUnit'; e = { $_.DistinguishedName -replace '^CN=(?:\\.|[^,\\])*,', '' }} | Export-Csv -Path $state.ExportPath -NoTypeInformation
        }
        catch {
            Write-Log -Message ("Reset: Passphrase export failed: $($_.Exception.Message)") -Level Error
            [System.Windows.Forms.MessageBox]::Show($form, "Passphrase export failed: $($_.Exception.Message)", "IDBridge", 'OK', 'Error') | Out-Null
            return
        }

        foreach ($resetItem in $resets) {
            $state.ItemByDN[$resetItem.DistinguishedName].SubItems[3].Text = "Exported"
        }

        Write-Log -Message "Reset: Exported $($resets.Count) passphrase(s) to $($state.ExportPath) without resetting. Delete the file after handout."

        [System.Windows.Forms.MessageBox]::Show($form, "Exported $($resets.Count) passphrase(s) - no passwords were changed.`n`n$($state.ExportPath)", "IDBridge", 'OK', 'Information') | Out-Null
    })
    #endregion Export Passphrases Handler



    #region Show
    Write-Log -Message "Reset: Opening the AD password reset window."
    $form.ShowDialog() | Out-Null
    $form.Dispose()
    #endregion Show

    return [PSCustomObject]@{
        Total     = $state.Total
        Succeeded = $state.Succeeded
        Failed    = $state.Failed
        ExportPath = $state.ExportPath
    }
}
