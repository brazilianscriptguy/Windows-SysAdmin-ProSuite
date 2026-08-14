<#
.SYNOPSIS
  AD User Account Expiration Manager v2.0.0 Enterprise Edition - controlled account-expiration administration.

.DESCRIPTION
  Enterprise Windows Forms tool for searching Active Directory users by Title and
  previewing, applying, and verifying AccountExpirationDate changes.

  Implements:
  - Windows PowerShell 5.1 / Windows Server 2019 compatibility
  - Forest/domain discovery with explicit domain targeting
  - Safe LDAP-filter escaping for Title searches
  - Stable identity handling using DistinguishedName and ObjectGUID
  - Explicit Dry Run / Commit workflow
  - Native ShouldProcess / WhatIf support in the modification function
  - Per-user post-change verification
  - Accurate success/failure/skipped counters
  - Timestamped audit logging in C:\Logs-TEMP
  - ActiveDirectory module and domain connectivity pre-flight checks
  - Responsive WinForms layout with status and execution summary
  - Client-side filtering across all displayed result columns
  - Clickable ascending/descending column sorting
  - No silent success when one or more selected objects fail

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.2.1-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Network connectivity and permissions to query/modify the selected Active Directory domain
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# =====================================================================================
# Assemblies and process mode
# =====================================================================================
try {
    if (-not $ShowConsole) {
        try {
            Add-Type -Name Win32ShowWindowAsync -Namespace ConsoleControl -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
"@
            $consolePtr = [ConsoleControl.Win32ShowWindowAsync]::GetConsoleWindow()
            if ($consolePtr -ne [IntPtr]::Zero) {
                [void][ConsoleControl.Win32ShowWindowAsync]::ShowWindowAsync($consolePtr, 0)
            }
        } catch { }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    # ActiveDirectory is intentionally imported only after console suppression.
    # '#Requires -Modules ActiveDirectory' would load the module before script code
    # executes, preventing the script from hiding the console first.
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'The ActiveDirectory PowerShell module is not installed or available.'
    }

    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to initialize required components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot    = 'C:\Logs-TEMP'
$script:RunStamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile    = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:SearchResults = @()
$script:DisplayedResults = @()
$script:CurrentDomain = $null
$script:txtLog = $null
$script:statusMain = $null
$script:statusMode = $null
$script:chkDryRun = $null
$script:listViewUsers = $null
$script:SortColumn = -1
$script:SortDescending = $false

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

# =====================================================================================
# Basic helpers
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level = 'INFO'
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Unable to write log file: $($_.Exception.Message)"
    }

    if ($script:txtLog -and -not $script:txtLog.IsDisposed) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.Text.Length
        $script:txtLog.ScrollToCaret()
    } elseif ($ShowConsole) {
        Write-Host $line
    }
}

function Show-AppMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type = 'Information'
    )

    switch ($Type) {
        'Error' {
            Write-AppLog -Message $Message -Level ERROR
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        'Warning' {
            Write-AppLog -Message $Message -Level WARN
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Warning',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        default {
            Write-AppLog -Message $Message -Level INFO
            [void][System.Windows.Forms.MessageBox]::Show(
                $Message, 'Information',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }
}

function Set-AppStatus {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-ExecutionModeLabel {
    if ($script:chkDryRun -and -not $script:chkDryRun.IsDisposed -and $script:chkDryRun.Checked) {
        return 'DRY RUN'
    }
    return 'COMMIT'
}

function ConvertTo-LdapFilterValue {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    # RFC 4515 escaping.
    # Explicit [string] casts are intentional for Windows PowerShell 5.1:
    # they force String.Replace(string, string) and avoid overload selection
    # of String.Replace(char, char), which cannot accept LDAP escape sequences.
    $escaped = $Value.Replace([string]'\', [string]'\5c')
    $escaped = $escaped.Replace([string]'*',  [string]'\2a')
    $escaped = $escaped.Replace([string]'(',  [string]'\28')
    $escaped = $escaped.Replace([string]')',  [string]'\29')
    $escaped = $escaped.Replace([string][char]0, [string]'\00')
    return $escaped
}

function ConvertTo-DisplayExpirationDate {
    param($Date)
    if ($null -eq $Date) { return 'No Expiration' }
    return ([datetime]$Date).ToString('yyyy-MM-dd')
}

function Test-ExpirationDateInput {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ref]$ParsedDate
    )

    $value = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $Text,
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$value
    )

    if ($ok) {
        $ParsedDate.Value = $value.Date
        return $true
    }
    return $false
}

# =====================================================================================
# Validation / prerequisite functions
# =====================================================================================
function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-ForestDomains {
    try {
        $forest = Get-ADForest -ErrorAction Stop
        return @($forest.Domains | Sort-Object)
    } catch {
        throw "Unable to discover Active Directory forest domains. $($_.Exception.Message)"
    }
}

function Test-DomainTarget {
    param([Parameter(Mandatory = $true)][string]$Server)

    try {
        $domain = Get-ADDomain -Server $Server -ErrorAction Stop
        Write-AppLog -Message ("Domain pre-flight succeeded: {0} ({1})" -f $domain.DNSRoot, $domain.NetBIOSName) -Level SUCCESS
        return $true
    } catch {
        Write-AppLog -Message "Domain pre-flight failed for '$Server': $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# =====================================================================================
# AD discovery
# =====================================================================================
function Find-ADUsersByTitle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Title
    )

    $escaped = ConvertTo-LdapFilterValue -Value $Title
    $ldapFilter = "(&(objectCategory=person)(objectClass=user)(title=*$escaped*))"

    Write-AppLog -Message "Searching domain '$Server' for users whose Title contains '$Title'."

    $users = @(
        Get-ADUser -Server $Server -LDAPFilter $ldapFilter `
            -Properties Title, AccountExpirationDate, Enabled, DistinguishedName, ObjectGUID `
            -ErrorAction Stop |
        Sort-Object SamAccountName
    )

    Write-AppLog -Message ("Search completed. Users found: {0}" -f $users.Count) -Level SUCCESS
    return $users
}

function Set-UserListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Users
    )

    $script:listViewUsers.BeginUpdate()
    try {
        $script:listViewUsers.Items.Clear()

        foreach ($user in $Users) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$user.SamAccountName)
            [void]$item.SubItems.Add([string]$user.Title)
            [void]$item.SubItems.Add((ConvertTo-DisplayExpirationDate -Date $user.AccountExpirationDate))
            [void]$item.SubItems.Add([string]$user.Enabled)

            # Retain the original AD object identity discovered during search.
            $item.Tag = [pscustomobject]@{
                DistinguishedName     = [string]$user.DistinguishedName
                ObjectGUID            = [Guid]$user.ObjectGUID
                SamAccountName        = [string]$user.SamAccountName
                Title                 = [string]$user.Title
                AccountExpirationDate = $user.AccountExpirationDate
                Enabled               = [bool]$user.Enabled
            }

            [void]$script:listViewUsers.Items.Add($item)
        }
    } finally {
        $script:listViewUsers.EndUpdate()
    }
}

function Get-CheckedUserRecords {
    $records = New-Object System.Collections.ArrayList
    foreach ($item in $script:listViewUsers.CheckedItems) {
        if ($null -ne $item.Tag) {
            [void]$records.Add($item.Tag)
        }
    }
    return @($records)
}

function Test-UserRecordMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$User,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$User.SamAccountName,
        [string]$User.Title,
        (ConvertTo-DisplayExpirationDate -Date $User.AccountExpirationDate),
        [string]$User.Enabled
    )

    foreach ($value in $values) {
        if ($null -ne $value -and $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ResultsFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $checkedGuids = @{}
    foreach ($item in $script:listViewUsers.CheckedItems) {
        if ($null -ne $item.Tag) {
            $checkedGuids[[string]$item.Tag.ObjectGUID] = $true
        }
    }

    $filtered = @(
        $script:SearchResults | Where-Object {
            Test-UserRecordMatchesFilter -User $_ -FilterText $FilterText
        }
    )

    $script:DisplayedResults = $filtered
    Set-UserListViewData -Users $filtered

    foreach ($item in $script:listViewUsers.Items) {
        if ($null -ne $item.Tag -and $checkedGuids.ContainsKey([string]$item.Tag.ObjectGUID)) {
            $item.Checked = $true
        }
    }

    Set-AppStatus ("Displayed {0} of {1} result(s)." -f $filtered.Count, $script:SearchResults.Count)
}

function Sort-SearchResults {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property = 'SamAccountName' }
        1 { $property = 'Title' }
        2 { $property = 'AccountExpirationDate' }
        3 { $property = 'Enabled' }
        default { $property = 'SamAccountName' }
    }

    if ($property -eq 'AccountExpirationDate') {
        $script:SearchResults = @(
            $script:SearchResults |
            Sort-Object @{ Expression = {
                if ($null -eq $_.AccountExpirationDate) { [datetime]::MaxValue }
                else { [datetime]$_.AccountExpirationDate }
            }; Descending = $Descending }
        )
    } else {
        $script:SearchResults = @(
            $script:SearchResults |
            Sort-Object -Property $property -Descending:$Descending
        )
    }
}

# =====================================================================================
# Preview / commit / verification
# =====================================================================================
function New-ExpirationChangePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Users,
        [Parameter(Mandatory = $true)][datetime]$ExpirationDate,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $preview = foreach ($user in $Users) {
        $current = $null
        try {
            $current = Get-ADUser -Identity $user.DistinguishedName -Server $Server `
                -Properties AccountExpirationDate, ObjectGUID -ErrorAction Stop

            if ([Guid]$current.ObjectGUID -ne [Guid]$user.ObjectGUID) {
                [pscustomobject]@{
                    SamAccountName = $user.SamAccountName
                    Current        = ConvertTo-DisplayExpirationDate -Date $current.AccountExpirationDate
                    Requested      = $ExpirationDate.ToString('yyyy-MM-dd')
                    Status         = 'BLOCKED'
                    Detail         = 'ObjectGUID changed since discovery.'
                }
                continue
            }

            $sameDate = ($null -ne $current.AccountExpirationDate -and
                         ([datetime]$current.AccountExpirationDate).Date -eq $ExpirationDate.Date)

            [pscustomobject]@{
                SamAccountName = $user.SamAccountName
                Current        = ConvertTo-DisplayExpirationDate -Date $current.AccountExpirationDate
                Requested      = $ExpirationDate.ToString('yyyy-MM-dd')
                Status         = if ($sameDate) { 'NO CHANGE' } else { 'READY' }
                Detail         = if ($sameDate) { 'Requested expiration date is already effective.' } else { 'Ready for update.' }
            }
        } catch {
            [pscustomobject]@{
                SamAccountName = $user.SamAccountName
                Current        = 'Unknown'
                Requested      = $ExpirationDate.ToString('yyyy-MM-dd')
                Status         = 'BLOCKED'
                Detail         = $_.Exception.Message
            }
        }
    }

    return @($preview)
}

function Show-PreviewDialog {
    param(
        [Parameter(Mandatory = $true)][object[]]$Preview,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $ready = @($Preview | Where-Object { $_.Status -eq 'READY' }).Count
    $noChange = @($Preview | Where-Object { $_.Status -eq 'NO CHANGE' }).Count
    $blocked = @($Preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Execution mode : $Mode")
    $lines.Add("Ready          : $ready")
    $lines.Add("No change      : $noChange")
    $lines.Add("Blocked        : $blocked")
    $lines.Add('')
    foreach ($entry in $Preview) {
        $lines.Add(("{0,-24} {1,-10} -> {2,-10} [{3}]" -f
            $entry.SamAccountName, $entry.Current, $entry.Requested, $entry.Status))
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Expiration Change Preview'
    $dialog.Size = New-Object System.Drawing.Size(760, 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = 'Both'
    $box.WordWrap = $false
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $box.Dock = 'Fill'
    $box.Text = ($lines -join [Environment]::NewLine)
    $dialog.Controls.Add($box)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Height = 45
    $panel.Dock = 'Bottom'

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Close'
    $ok.Width = 100
    $ok.Height = 28
    $ok.Left = 630
    $ok.Top = 8
    $ok.Anchor = 'Right,Top'
    $ok.Add_Click({ $dialog.Close() })
    $panel.Controls.Add($ok)
    $dialog.Controls.Add($panel)

    [void]$dialog.ShowDialog()
}

function Set-ADUserExpirationControlled {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][object[]]$Users,
        [Parameter(Mandatory = $true)][datetime]$ExpirationDate,
        [Parameter(Mandatory = $true)][string]$Server
    )

    $results = New-Object System.Collections.ArrayList

    foreach ($record in $Users) {
        try {
            $current = Get-ADUser -Identity $record.DistinguishedName -Server $Server `
                -Properties AccountExpirationDate, ObjectGUID -ErrorAction Stop

            if ([Guid]$current.ObjectGUID -ne [Guid]$record.ObjectGUID) {
                throw 'ObjectGUID changed since discovery. Modification blocked.'
            }

            if ($null -ne $current.AccountExpirationDate -and
                ([datetime]$current.AccountExpirationDate).Date -eq $ExpirationDate.Date) {

                Write-AppLog -Message "Skipped '$($record.SamAccountName)': requested date is already effective." -Level WARN
                [void]$results.Add([pscustomobject]@{
                    SamAccountName = $record.SamAccountName
                    Result = 'SKIPPED'
                    Detail = 'No change required.'
                })
                continue
            }

            $target = "$($record.SamAccountName) [$($record.DistinguishedName)]"
            $action = "Set AccountExpirationDate to $($ExpirationDate.ToString('yyyy-MM-dd'))"

            if ($PSCmdlet.ShouldProcess($target, $action)) {
                Set-ADUser -Identity $record.DistinguishedName -Server $Server `
                    -AccountExpirationDate $ExpirationDate -ErrorAction Stop

                $verified = Get-ADUser -Identity $record.DistinguishedName -Server $Server `
                    -Properties AccountExpirationDate, ObjectGUID -ErrorAction Stop

                if ([Guid]$verified.ObjectGUID -ne [Guid]$record.ObjectGUID) {
                    throw 'Post-change verification detected an ObjectGUID mismatch.'
                }

                if ($null -eq $verified.AccountExpirationDate -or
                    ([datetime]$verified.AccountExpirationDate).Date -ne $ExpirationDate.Date) {
                    throw ("Post-change verification failed. Effective value: {0}" -f
                        (ConvertTo-DisplayExpirationDate -Date $verified.AccountExpirationDate))
                }

                Write-AppLog -Message ("Updated and verified '{0}' -> {1} on '{2}'." -f
                    $record.SamAccountName, $ExpirationDate.ToString('yyyy-MM-dd'), $Server) -Level SUCCESS

                [void]$results.Add([pscustomobject]@{
                    SamAccountName = $record.SamAccountName
                    Result = 'SUCCESS'
                    Detail = 'Updated and verified.'
                })
            } else {
                [void]$results.Add([pscustomobject]@{
                    SamAccountName = $record.SamAccountName
                    Result = 'SKIPPED'
                    Detail = 'ShouldProcess declined the operation.'
                })
            }
        } catch {
            Write-AppLog -Message "Failed '$($record.SamAccountName)': $($_.Exception.Message)" -Level ERROR
            [void]$results.Add([pscustomobject]@{
                SamAccountName = $record.SamAccountName
                Result = 'FAILED'
                Detail = $_.Exception.Message
            })
        }
    }

    return @($results)
}

function Update-ListViewExpirationFromAD {
    param([Parameter(Mandatory = $true)][string]$Server)

    foreach ($item in $script:listViewUsers.Items) {
        if ($null -eq $item.Tag) { continue }
        try {
            $user = Get-ADUser -Identity $item.Tag.DistinguishedName -Server $Server `
                -Properties AccountExpirationDate -ErrorAction Stop
            $item.SubItems[2].Text = ConvertTo-DisplayExpirationDate -Date $user.AccountExpirationDate
            $item.Tag.AccountExpirationDate = $user.AccountExpirationDate
        } catch {
            Write-AppLog -Message "Unable to refresh '$($item.Text)': $($_.Exception.Message)" -Level WARN
        }
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD User Account Expiration Manager - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(900, 650)
$form.MinimumSize = New-Object System.Drawing.Size(820, 600)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 60)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 40)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$domainPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$domainPanel.Dock = 'Fill'
$domainPanel.AutoSize = $true
$domainPanel.WrapContents = $false

$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Domain:'
$labelDomain.AutoSize = $true
$labelDomain.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$domainPanel.Controls.Add($labelDomain)

$comboBoxDomain = New-Object System.Windows.Forms.ComboBox
$comboBoxDomain.Width = 330
$comboBoxDomain.DropDownStyle = 'DropDownList'
$domainPanel.Controls.Add($comboBoxDomain)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(25, 6, 3, 3)
$script:chkDryRun = $chkDryRun
$domainPanel.Controls.Add($chkDryRun)

$main.Controls.Add($domainPanel, 0, 0)

$searchPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$searchPanel.Dock = 'Fill'
$searchPanel.AutoSize = $true
$searchPanel.WrapContents = $false

$labelDescription = New-Object System.Windows.Forms.Label
$labelDescription.Text = 'Title contains:'
$labelDescription.AutoSize = $true
$labelDescription.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$searchPanel.Controls.Add($labelDescription)

$textboxTitle = New-Object System.Windows.Forms.TextBox
$textboxTitle.Width = 430
$searchPanel.Controls.Add($textboxTitle)

$buttonSearch = New-Object System.Windows.Forms.Button
$buttonSearch.Text = 'Search'
$buttonSearch.Width = 100
$searchPanel.Controls.Add($buttonSearch)

$buttonSelectAll = New-Object System.Windows.Forms.Button
$buttonSelectAll.Text = 'Select All'
$buttonSelectAll.Width = 100
$searchPanel.Controls.Add($buttonSelectAll)

$main.Controls.Add($searchPanel, 0, 1)

$datePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$datePanel.Dock = 'Fill'
$datePanel.AutoSize = $true
$datePanel.WrapContents = $false

$labelExpirationDate = New-Object System.Windows.Forms.Label
$labelExpirationDate.Text = 'Expiration date (yyyy-MM-dd):'
$labelExpirationDate.AutoSize = $true
$labelExpirationDate.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$datePanel.Controls.Add($labelExpirationDate)

$textboxExpirationDate = New-Object System.Windows.Forms.TextBox
$textboxExpirationDate.Width = 140
$datePanel.Controls.Add($textboxExpirationDate)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview'
$buttonPreview.Width = 100
$datePanel.Controls.Add($buttonPreview)

$buttonExecute = New-Object System.Windows.Forms.Button
$buttonExecute.Text = 'Execute'
$buttonExecute.Width = 100
$datePanel.Controls.Add($buttonExecute)

$main.Controls.Add($datePanel, 0, 2)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.WrapContents = $false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text = 'Filter displayed columns:'
$labelFilter.AutoSize = $true
$labelFilter.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$filterPanel.Controls.Add($labelFilter)

$textboxFilter = New-Object System.Windows.Forms.TextBox
$textboxFilter.Width = 430
$filterPanel.Controls.Add($textboxFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text = 'Clear Filter'
$buttonClearFilter.Width = 100
$filterPanel.Controls.Add($buttonClearFilter)

$main.Controls.Add($filterPanel, 0, 3)

$listViewUsers = New-Object System.Windows.Forms.ListView
$listViewUsers.Dock = 'Fill'
$listViewUsers.View = 'Details'
$listViewUsers.CheckBoxes = $true
$listViewUsers.FullRowSelect = $true
$listViewUsers.GridLines = $true
[void]$listViewUsers.Columns.Add('SamAccountName', 170)
[void]$listViewUsers.Columns.Add('Title', 410)
[void]$listViewUsers.Columns.Add('Expiration Date', 120)
[void]$listViewUsers.Columns.Add('Enabled', 80)
$script:listViewUsers = $listViewUsers
$main.Controls.Add($listViewUsers, 0, 4)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Text = 'Runtime log:'
$summaryLabel.AutoSize = $true
$main.Controls.Add($summaryLabel, 0, 5)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Dock = 'Fill'
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:txtLog = $txtLog
$main.Controls.Add($txtLog, 0, 6)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring = $true
$statusMain.TextAlign = 'MiddleLeft'
$statusMain.Text = 'Ready'
$script:statusMain = $statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusMode = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMode.Text = 'Mode: DRY RUN'
$script:statusMode = $statusMode
[void]$statusStrip.Items.Add($statusMode)
$main.Controls.Add($statusStrip, 0, 7)

$chkDryRun.Add_CheckedChanged({
    $script:statusMode.Text = 'Mode: ' + (Get-ExecutionModeLabel)
})

$textboxFilter.Add_TextChanged({
    try {
        Apply-ResultsFilter -FilterText $textboxFilter.Text
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Display filter failed.'
    }
})

$buttonClearFilter.Add_Click({
    $textboxFilter.Clear()
})

$listViewUsers.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-SearchResults -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ResultsFilter -FilterText $textboxFilter.Text
})

$buttonSelectAll.Add_Click({
    foreach ($item in $script:listViewUsers.Items) {
        $item.Checked = $true
    }
    Set-AppStatus ("Selected {0} displayed user(s)." -f $script:listViewUsers.Items.Count)
})

$buttonSearch.Add_Click({
    try {
        $domain = [string]$comboBoxDomain.SelectedItem
        $title = $textboxTitle.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($domain)) {
            Show-AppMessage -Message 'Select an Active Directory domain.' -Type Warning
            return
        }
        if ([string]::IsNullOrWhiteSpace($title)) {
            Show-AppMessage -Message 'Enter text to search in the Title attribute.' -Type Warning
            return
        }
        if (-not (Test-DomainTarget -Server $domain)) {
            Show-AppMessage -Message "The selected domain '$domain' is not reachable through the ActiveDirectory module." -Type Error
            return
        }

        Set-AppStatus 'Searching Active Directory...'
        $script:CurrentDomain = $domain
        $script:SearchResults = @(Find-ADUsersByTitle -Server $domain -Title $title)
        $script:DisplayedResults = @($script:SearchResults)
        $textboxFilter.Clear()
        Set-UserListViewData -Users $script:DisplayedResults

        if ($script:SearchResults.Count -eq 0) {
            Show-AppMessage -Message 'No users matched the requested Title text.' -Type Information
        }
        Set-AppStatus ("Search completed: {0} user(s)." -f $script:SearchResults.Count)
    } catch {
        Show-AppMessage -Message "Search failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Search failed.'
    }
})

$buttonPreview.Add_Click({
    try {
        $users = @(Get-CheckedUserRecords)
        if ($users.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one user.' -Type Warning
            return
        }

        $parsedDate = [datetime]::MinValue
        if (-not (Test-ExpirationDateInput -Text $textboxExpirationDate.Text.Trim() -ParsedDate ([ref]$parsedDate))) {
            Show-AppMessage -Message 'Invalid date. Use the exact format yyyy-MM-dd.' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)) {
            Show-AppMessage -Message 'Run a search before previewing changes.' -Type Warning
            return
        }

        Set-AppStatus 'Building preview...'
        $preview = @(New-ExpirationChangePreview -Users $users -ExpirationDate $parsedDate -Server $script:CurrentDomain)
        Show-PreviewDialog -Preview $preview -Mode (Get-ExecutionModeLabel)
        Set-AppStatus ("Preview completed: {0} selected user(s)." -f $users.Count)
    } catch {
        Show-AppMessage -Message "Preview failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Preview failed.'
    }
})

$buttonExecute.Add_Click({
    try {
        $users = @(Get-CheckedUserRecords)
        if ($users.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one user.' -Type Warning
            return
        }

        $parsedDate = [datetime]::MinValue
        if (-not (Test-ExpirationDateInput -Text $textboxExpirationDate.Text.Trim() -ParsedDate ([ref]$parsedDate))) {
            Show-AppMessage -Message 'Invalid date. Use the exact format yyyy-MM-dd.' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)) {
            Show-AppMessage -Message 'Run a search before executing changes.' -Type Warning
            return
        }

        $preview = @(New-ExpirationChangePreview -Users $users -ExpirationDate $parsedDate -Server $script:CurrentDomain)
        $ready = @($preview | Where-Object { $_.Status -eq 'READY' }).Count
        $blocked = @($preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count

        if ($blocked -gt 0) {
            Show-PreviewDialog -Preview $preview -Mode (Get-ExecutionModeLabel)
            Show-AppMessage -Message "$blocked selected object(s) failed pre-commit validation. Resolve the blocked entries before execution." -Type Error
            return
        }

        if ($chkDryRun.Checked) {
            Write-AppLog -Message ("DRY RUN: {0} selected; {1} would change." -f $users.Count, $ready) -Level INFO
            Show-PreviewDialog -Preview $preview -Mode 'DRY RUN'
            Show-AppMessage -Message ("Dry Run completed. {0} user(s) would be changed; no Active Directory objects were modified." -f $ready) -Type Information
            Set-AppStatus 'Dry Run completed; no changes committed.'
            return
        }

        if ($ready -eq 0) {
            Show-AppMessage -Message 'No selected users require a change.' -Type Information
            return
        }

        $confirmText = "COMMIT account expiration changes?`r`n`r`nDomain: $($script:CurrentDomain)`r`nSelected: $($users.Count)`r`nChanges required: $ready`r`nNew expiration date: $($parsedDate.ToString('yyyy-MM-dd'))"
        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmText,
            'Confirm Active Directory Change',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'Commit cancelled by operator.' -Level WARN
            Set-AppStatus 'Commit cancelled.'
            return
        }

        Set-AppStatus 'Applying and verifying changes...'
        $results = @(Set-ADUserExpirationControlled -Users $users -ExpirationDate $parsedDate -Server $script:CurrentDomain -Confirm:$false)

        $success = @($results | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $failed  = @($results | Where-Object { $_.Result -eq 'FAILED' }).Count
        $skipped = @($results | Where-Object { $_.Result -eq 'SKIPPED' }).Count

        Update-ListViewExpirationFromAD -Server $script:CurrentDomain

        $summary = "Execution completed.`r`n`r`nSucceeded: $success`r`nFailed: $failed`r`nSkipped: $skipped`r`n`r`nLog: $($script:LogFile)"
        if ($failed -gt 0) {
            Show-AppMessage -Message $summary -Type Warning
        } else {
            Write-AppLog -Message ("Commit summary: Success={0}; Failed={1}; Skipped={2}" -f $success, $failed, $skipped) -Level SUCCESS
            [void][System.Windows.Forms.MessageBox]::Show(
                $summary, 'Execution Summary',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }

        Set-AppStatus ("Completed: Success={0}, Failed={1}, Skipped={2}" -f $success, $failed, $skipped)
    } catch {
        Show-AppMessage -Message "Execution failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Execution failed.'
    }
})

# =====================================================================================
# Main execution
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    if (-not (Test-IsAdministrator)) {
        Write-AppLog -Message 'Process is not elevated. AD modification may still succeed with delegated rights; elevation is not assumed to equal AD authorization.' -Level WARN
    }

    $domains = @(Get-ForestDomains)
    foreach ($domain in $domains) {
        [void]$comboBoxDomain.Items.Add($domain)
    }

    if ($comboBoxDomain.Items.Count -gt 0) {
        $comboBoxDomain.SelectedIndex = 0
    } else {
        throw 'No Active Directory domains were discovered.'
    }

    Write-AppLog -Message ("Discovered forest domains: {0}" -f ($domains -join ', ')) -Level SUCCESS
    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'AD User Account Expiration Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
