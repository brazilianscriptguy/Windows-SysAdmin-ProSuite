<#
.SYNOPSIS
  Active Directory Computer Description and Info Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for auditing and updating Active Directory workstation
  computer Description and Info attributes.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before importing the ActiveDirectory module
  - Discovers all forest domains and explicitly targets the selected domain
  - Searches Windows 10 and Windows 11 computer accounts
  - Displays Name, DNSHostName, OperatingSystem, Enabled, Description, Info,
    DistinguishedName, and ObjectGUID
  - Provides client-side filtering across every displayed column
  - Provides ascending/descending sorting by clicking column headers
  - Preserves stable AD identity using DistinguishedName + ObjectGUID
  - Uses Dry Run by default
  - Provides Preview and Commit workflows
  - Supports current credentials by default and optional alternate AD credentials
  - Skips objects already compliant with the requested values
  - Revalidates ObjectGUID immediately before modification
  - Uses explicit -Server targeting on every Active Directory read/write
  - Re-reads and verifies Description and Info after each update
  - Provides accurate SUCCESS / FAILED / SKIPPED counts
  - Produces timestamped audit logs in C:\Logs-TEMP

  IMPORTANT:
  The legacy script labeled the second field "Site Information" but wrote it to the
  Active Directory "info" attribute. This version preserves that behavior explicitly.
  It does not silently redirect the value to physicalDeliveryOfficeName.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - RSAT ActiveDirectory PowerShell module
  - Network connectivity and permissions to query/modify the selected AD domain
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
$script:ScriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot          = 'C:\Logs-TEMP'
$script:RunStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile          = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:SearchResults    = @()
$script:DisplayedResults = @()
$script:CurrentDomain    = $null
$script:Credential       = $null
$script:SortColumn       = -1
$script:SortDescending   = $false

$script:listView         = $null
$script:txtRuntimeLog    = $null
$script:statusMain       = $null
$script:statusMode       = $null
$script:chkDryRun        = $null

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

    if ($script:txtRuntimeLog -and -not $script:txtRuntimeLog.IsDisposed) {
        $script:txtRuntimeLog.AppendText($line + [Environment]::NewLine)
        $script:txtRuntimeLog.SelectionStart = $script:txtRuntimeLog.Text.Length
        $script:txtRuntimeLog.ScrollToCaret()
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

function Get-ADCommonParameters {
    param([Parameter(Mandatory = $true)][string]$Server)

    $params = @{
        Server      = $Server
        ErrorAction = 'Stop'
    }

    if ($null -ne $script:Credential) {
        $params.Credential = $script:Credential
    }

    return $params
}

# =====================================================================================
# Active Directory discovery
# =====================================================================================
function Get-ForestDomains {
    try {
        $params = @{ ErrorAction = 'Stop' }
        if ($null -ne $script:Credential) {
            $params.Credential = $script:Credential
        }
        $forest = Get-ADForest @params
        return @($forest.Domains | Sort-Object)
    } catch {
        throw "Unable to discover Active Directory forest domains. $($_.Exception.Message)"
    }
}

function Test-DomainTarget {
    param([Parameter(Mandatory = $true)][string]$Server)

    try {
        $params = Get-ADCommonParameters -Server $Server
        $domain = Get-ADDomain @params
        Write-AppLog -Message ("Domain pre-flight succeeded: {0} ({1})" -f
            $domain.DNSRoot, $domain.NetBIOSName) -Level SUCCESS
        return $true
    } catch {
        Write-AppLog -Message "Domain pre-flight failed for '$Server': $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Find-ADWorkstations {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Server)

    $params = Get-ADCommonParameters -Server $Server
    $params.Filter = "OperatingSystem -like '*Windows 10*' -or OperatingSystem -like '*Windows 11*'"
    $params.Properties = @(
        'DNSHostName',
        'OperatingSystem',
        'Enabled',
        'Description',
        'Info',
        'DistinguishedName',
        'ObjectGUID'
    )

    Write-AppLog -Message "Searching '$Server' for Windows 10/11 computer accounts."

    $computers = @(
        Get-ADComputer @params |
        Sort-Object Name
    )

    Write-AppLog -Message ("Search completed. Workstations found: {0}" -f $computers.Count) -Level SUCCESS
    return $computers
}

# =====================================================================================
# Searchable / sortable results browser
# =====================================================================================
function Set-ResultListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $checkedGuids = @{}
    foreach ($item in $script:listView.CheckedItems) {
        if ($null -ne $item.Tag) {
            $checkedGuids[[string]$item.Tag.ObjectGUID] = $true
        }
    }

    $script:listView.BeginUpdate()
    try {
        $script:listView.Items.Clear()

        foreach ($computer in $Results) {
            $record = [pscustomobject]@{
                Name              = [string]$computer.Name
                DNSHostName       = [string]$computer.DNSHostName
                OperatingSystem   = [string]$computer.OperatingSystem
                Enabled           = [bool]$computer.Enabled
                Description       = [string]$computer.Description
                Info              = [string]$computer.Info
                DistinguishedName = [string]$computer.DistinguishedName
                ObjectGUID        = [Guid]$computer.ObjectGUID
            }

            $item = New-Object System.Windows.Forms.ListViewItem($record.Name)
            [void]$item.SubItems.Add($record.DNSHostName)
            [void]$item.SubItems.Add($record.OperatingSystem)
            [void]$item.SubItems.Add([string]$record.Enabled)
            [void]$item.SubItems.Add($record.Description)
            [void]$item.SubItems.Add($record.Info)
            [void]$item.SubItems.Add($record.DistinguishedName)
            $item.Tag = $record

            if ($checkedGuids.ContainsKey([string]$record.ObjectGUID)) {
                $item.Checked = $true
            }

            [void]$script:listView.Items.Add($item)
        }
    } finally {
        $script:listView.EndUpdate()
    }
}

function Test-ResultMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Result.Name,
        [string]$Result.DNSHostName,
        [string]$Result.OperatingSystem,
        [string]$Result.Enabled,
        [string]$Result.Description,
        [string]$Result.Info,
        [string]$Result.DistinguishedName
    )

    foreach ($value in $values) {
        if ($null -ne $value -and
            $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ResultsFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:SearchResults | Where-Object {
            Test-ResultMatchesFilter -Result $_ -FilterText $FilterText
        }
    )

    $script:DisplayedResults = $filtered
    Set-ResultListViewData -Results $filtered
    Set-AppStatus ("Displayed {0} of {1} workstation(s)." -f
        $filtered.Count, $script:SearchResults.Count)
}

function Sort-SearchResults {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property = 'Name' }
        1 { $property = 'DNSHostName' }
        2 { $property = 'OperatingSystem' }
        3 { $property = 'Enabled' }
        4 { $property = 'Description' }
        5 { $property = 'Info' }
        6 { $property = 'DistinguishedName' }
        default { $property = 'Name' }
    }

    $script:SearchResults = @(
        $script:SearchResults |
        Sort-Object -Property $property -Descending:$Descending
    )
}

function Get-CheckedComputerRecords {
    $records = New-Object System.Collections.ArrayList
    foreach ($item in $script:listView.CheckedItems) {
        if ($null -ne $item.Tag) {
            [void]$records.Add($item.Tag)
        }
    }
    return @($records)
}

# =====================================================================================
# Preview / commit / verification
# =====================================================================================
function New-ComputerUpdatePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Computers,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$Info
    )

    $preview = foreach ($record in $Computers) {
        try {
            $params = Get-ADCommonParameters -Server $Server
            $params.Identity = $record.DistinguishedName
            $params.Properties = @('Description','Info','ObjectGUID')
            $current = Get-ADComputer @params

            if ([Guid]$current.ObjectGUID -ne [Guid]$record.ObjectGUID) {
                [pscustomobject]@{
                    Name               = $record.Name
                    CurrentDescription = [string]$current.Description
                    NewDescription     = $Description
                    CurrentInfo        = [string]$current.Info
                    NewInfo            = $Info
                    Status             = 'BLOCKED'
                    Detail             = 'ObjectGUID changed since discovery.'
                }
                continue
            }

            $same = (
                [string]$current.Description -eq $Description -and
                [string]$current.Info -eq $Info
            )

            [pscustomobject]@{
                Name               = $record.Name
                CurrentDescription = [string]$current.Description
                NewDescription     = $Description
                CurrentInfo        = [string]$current.Info
                NewInfo            = $Info
                Status             = if ($same) { 'NO CHANGE' } else { 'READY' }
                Detail             = if ($same) { 'Requested values are already effective.' } else { 'Ready for update.' }
            }
        } catch {
            [pscustomobject]@{
                Name               = $record.Name
                CurrentDescription = 'Unknown'
                NewDescription     = $Description
                CurrentInfo        = 'Unknown'
                NewInfo            = $Info
                Status             = 'BLOCKED'
                Detail             = $_.Exception.Message
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
    $same = @($Preview | Where-Object { $_.Status -eq 'NO CHANGE' }).Count
    $blocked = @($Preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Execution mode : $Mode")
    $lines.Add("Ready          : $ready")
    $lines.Add("No change      : $same")
    $lines.Add("Blocked        : $blocked")
    $lines.Add('')
    foreach ($entry in $Preview) {
        $lines.Add(("{0,-22} [{1}]" -f $entry.Name, $entry.Status))
        $lines.Add(("  Description: '{0}' -> '{1}'" -f $entry.CurrentDescription, $entry.NewDescription))
        $lines.Add(("  Info       : '{0}' -> '{1}'" -f $entry.CurrentInfo, $entry.NewInfo))
        if ($entry.Detail) { $lines.Add(("  Detail     : {0}" -f $entry.Detail)) }
        $lines.Add('')
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'AD Computer Update Preview'
    $dialog.Size = New-Object System.Drawing.Size(930, 600)
    $dialog.StartPosition = 'CenterParent'

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
    $panel.Dock = 'Bottom'
    $panel.Height = 45

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Width = 100
    $close.Height = 28
    $close.Left = 795
    $close.Top = 8
    $close.Anchor = 'Right,Top'
    $close.Add_Click({ $dialog.Close() })
    $panel.Controls.Add($close)
    $dialog.Controls.Add($panel)

    [void]$dialog.ShowDialog()
}

function Set-ADComputerMetadataControlled {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][object[]]$Computers,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$Info
    )

    $results = New-Object System.Collections.ArrayList

    foreach ($record in $Computers) {
        try {
            $getParams = Get-ADCommonParameters -Server $Server
            $getParams.Identity = $record.DistinguishedName
            $getParams.Properties = @('Description','Info','ObjectGUID')
            $current = Get-ADComputer @getParams

            if ([Guid]$current.ObjectGUID -ne [Guid]$record.ObjectGUID) {
                throw 'ObjectGUID changed since discovery. Modification blocked.'
            }

            if ([string]$current.Description -eq $Description -and
                [string]$current.Info -eq $Info) {
                Write-AppLog -Message "Skipped '$($record.Name)': values already compliant." -Level INFO
                [void]$results.Add([pscustomobject]@{
                    Name   = $record.Name
                    Result = 'SKIPPED'
                    Detail = 'No change required.'
                })
                continue
            }

            $target = "$($record.Name) [$($record.DistinguishedName)]"
            $action = "Set Description='$Description' and Info='$Info'"

            if ($PSCmdlet.ShouldProcess($target, $action)) {
                $setParams = Get-ADCommonParameters -Server $Server
                $setParams.Identity = $record.DistinguishedName
                $setParams.Description = $Description
                $setParams.Replace = @{ Info = $Info }

                Set-ADComputer @setParams

                $verifyParams = Get-ADCommonParameters -Server $Server
                $verifyParams.Identity = $record.DistinguishedName
                $verifyParams.Properties = @('Description','Info','ObjectGUID')
                $verified = Get-ADComputer @verifyParams

                if ([Guid]$verified.ObjectGUID -ne [Guid]$record.ObjectGUID) {
                    throw 'Post-change ObjectGUID verification failed.'
                }

                if ([string]$verified.Description -ne $Description -or
                    [string]$verified.Info -ne $Info) {
                    throw ("Post-change verification failed. Effective Description='{0}', Info='{1}'." -f
                        $verified.Description, $verified.Info)
                }

                Write-AppLog -Message ("Updated and verified '{0}' on '{1}'." -f
                    $record.Name, $Server) -Level SUCCESS

                [void]$results.Add([pscustomobject]@{
                    Name   = $record.Name
                    Result = 'SUCCESS'
                    Detail = 'Description and Info updated and verified.'
                })
            } else {
                [void]$results.Add([pscustomobject]@{
                    Name   = $record.Name
                    Result = 'SKIPPED'
                    Detail = 'ShouldProcess declined the operation.'
                })
            }
        } catch {
            Write-AppLog -Message "Failed '$($record.Name)': $($_.Exception.Message)" -Level ERROR
            [void]$results.Add([pscustomobject]@{
                Name   = $record.Name
                Result = 'FAILED'
                Detail = $_.Exception.Message
            })
        }
    }

    return @($results)
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD Computer Description and Info Manager - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1280, 830)
$form.MinimumSize = New-Object System.Drawing.Size(1050, 720)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 62)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 38)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$domainPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$domainPanel.Dock = 'Fill'
$domainPanel.AutoSize = $true
$domainPanel.WrapContents = $false

$labelDomain = New-Object System.Windows.Forms.Label
$labelDomain.Text = 'Domain:'
$labelDomain.AutoSize = $true
$labelDomain.Margin = New-Object System.Windows.Forms.Padding(3,7,3,3)
$domainPanel.Controls.Add($labelDomain)

$comboDomain = New-Object System.Windows.Forms.ComboBox
$comboDomain.Width = 330
$comboDomain.DropDownStyle = 'DropDownList'
$domainPanel.Controls.Add($comboDomain)

$buttonSearch = New-Object System.Windows.Forms.Button
$buttonSearch.Text = 'Search Workstations'
$buttonSearch.Width = 140
$domainPanel.Controls.Add($buttonSearch)

$chkAltCred = New-Object System.Windows.Forms.CheckBox
$chkAltCred.Text = 'Use Alternate Credentials'
$chkAltCred.AutoSize = $true
$chkAltCred.Margin = New-Object System.Windows.Forms.Padding(20,6,3,3)
$domainPanel.Controls.Add($chkAltCred)

$buttonCredentials = New-Object System.Windows.Forms.Button
$buttonCredentials.Text = 'Set Credentials'
$buttonCredentials.Width = 115
$buttonCredentials.Enabled = $false
$domainPanel.Controls.Add($buttonCredentials)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(20,6,3,3)
$script:chkDryRun = $chkDryRun
$domainPanel.Controls.Add($chkDryRun)

$main.Controls.Add($domainPanel, 0, 0)

$valuePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$valuePanel.Dock = 'Fill'
$valuePanel.AutoSize = $true
$valuePanel.WrapContents = $false

$labelDesc = New-Object System.Windows.Forms.Label
$labelDesc.Text = 'New Description:'
$labelDesc.AutoSize = $true
$labelDesc.Margin = New-Object System.Windows.Forms.Padding(3,7,3,3)
$valuePanel.Controls.Add($labelDesc)

$textDesc = New-Object System.Windows.Forms.TextBox
$textDesc.Width = 300
$valuePanel.Controls.Add($textDesc)

$labelInfo = New-Object System.Windows.Forms.Label
$labelInfo.Text = 'New Info attribute:'
$labelInfo.AutoSize = $true
$labelInfo.Margin = New-Object System.Windows.Forms.Padding(20,7,3,3)
$valuePanel.Controls.Add($labelInfo)

$textInfo = New-Object System.Windows.Forms.TextBox
$textInfo.Width = 300
$valuePanel.Controls.Add($textInfo)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview'
$buttonPreview.Width = 90
$valuePanel.Controls.Add($buttonPreview)

$buttonExecute = New-Object System.Windows.Forms.Button
$buttonExecute.Text = 'Execute'
$buttonExecute.Width = 90
$valuePanel.Controls.Add($buttonExecute)

$main.Controls.Add($valuePanel, 0, 1)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.WrapContents = $false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text = 'Filter displayed columns:'
$labelFilter.AutoSize = $true
$labelFilter.Margin = New-Object System.Windows.Forms.Padding(3,7,3,3)
$filterPanel.Controls.Add($labelFilter)

$textFilter = New-Object System.Windows.Forms.TextBox
$textFilter.Width = 540
$filterPanel.Controls.Add($textFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text = 'Clear Filter'
$buttonClearFilter.Width = 100
$filterPanel.Controls.Add($buttonClearFilter)

$buttonSelectAll = New-Object System.Windows.Forms.Button
$buttonSelectAll.Text = 'Select All'
$buttonSelectAll.Width = 100
$filterPanel.Controls.Add($buttonSelectAll)

$main.Controls.Add($filterPanel, 0, 2)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = 'Fill'
$listView.View = 'Details'
$listView.CheckBoxes = $true
$listView.FullRowSelect = $true
$listView.MultiSelect = $true
$listView.GridLines = $true
$listView.HideSelection = $false
[void]$listView.Columns.Add('Name', 130)
[void]$listView.Columns.Add('DNSHostName', 190)
[void]$listView.Columns.Add('Operating System', 190)
[void]$listView.Columns.Add('Enabled', 70)
[void]$listView.Columns.Add('Description', 210)
[void]$listView.Columns.Add('Info', 210)
[void]$listView.Columns.Add('DistinguishedName', 430)
$script:listView = $listView
$main.Controls.Add($listView, 0, 3)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize = $true
$summaryLabel.Text = 'No workstation search has been run.'
$main.Controls.Add($summaryLabel, 0, 4)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize = $true
$noteLabel.MaximumSize = New-Object System.Drawing.Size(1200, 0)
$noteLabel.Text = 'The second value is written to the AD "info" attribute, matching the legacy script. It is not physicalDeliveryOfficeName.'
$main.Controls.Add($noteLabel, 0, 5)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock = 'Fill'
$txtRuntimeLog.Multiline = $true
$txtRuntimeLog.ReadOnly = $true
$txtRuntimeLog.ScrollBars = 'Vertical'
$txtRuntimeLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:txtRuntimeLog = $txtRuntimeLog
$main.Controls.Add($txtRuntimeLog, 0, 6)

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

# =====================================================================================
# GUI events
# =====================================================================================
$chkAltCred.Add_CheckedChanged({
    $buttonCredentials.Enabled = $chkAltCred.Checked
    if (-not $chkAltCred.Checked) {
        $script:Credential = $null
        Write-AppLog -Message 'Alternate credentials disabled; current security context will be used.'
    }
})

$buttonCredentials.Add_Click({
    try {
        $cred = Get-Credential -Message 'Enter credentials for Active Directory operations'
        if ($null -ne $cred) {
            $script:Credential = $cred
            Write-AppLog -Message ("Alternate credentials configured for user '{0}'." -f $cred.UserName) -Level SUCCESS
        }
    } catch {
        Show-AppMessage -Message "Unable to obtain credentials: $($_.Exception.Message)" -Type Error
    }
})

$chkDryRun.Add_CheckedChanged({
    $script:statusMode.Text = 'Mode: ' + (Get-ExecutionModeLabel)
})

$textFilter.Add_TextChanged({
    try {
        Apply-ResultsFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedResults.Count) | Total workstations: $($script:SearchResults.Count)"
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Display filter failed.'
    }
})

$buttonClearFilter.Add_Click({ $textFilter.Clear() })

$buttonSelectAll.Add_Click({
    foreach ($item in $script:listView.Items) {
        $item.Checked = $true
    }
    Set-AppStatus ("Selected {0} displayed workstation(s)." -f $script:listView.Items.Count)
})

$listView.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-SearchResults -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ResultsFilter -FilterText $textFilter.Text
})

$buttonSearch.Add_Click({
    try {
        $domain = [string]$comboDomain.SelectedItem
        if ([string]::IsNullOrWhiteSpace($domain)) {
            Show-AppMessage -Message 'Select an Active Directory domain.' -Type Warning
            return
        }

        if ($chkAltCred.Checked -and $null -eq $script:Credential) {
            Show-AppMessage -Message 'Alternate credentials are enabled but no credentials have been configured.' -Type Warning
            return
        }

        if (-not (Test-DomainTarget -Server $domain)) {
            Show-AppMessage -Message "The selected domain '$domain' is not reachable with the current credential context." -Type Error
            return
        }

        Set-AppStatus 'Searching Active Directory workstations...'
        $script:CurrentDomain = $domain
        $script:SearchResults = @(Find-ADWorkstations -Server $domain)
        $script:DisplayedResults = @($script:SearchResults)
        $textFilter.Clear()
        Set-ResultListViewData -Results $script:DisplayedResults

        $summaryLabel.Text = "Workstations found: $($script:SearchResults.Count)"
        Set-AppStatus ("Search completed: {0} workstation(s)." -f $script:SearchResults.Count)
    } catch {
        Show-AppMessage -Message "Workstation search failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Search failed.'
    }
})

$buttonPreview.Add_Click({
    try {
        $records = @(Get-CheckedComputerRecords)
        if ($records.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one workstation.' -Type Warning
            return
        }

        $description = $textDesc.Text.Trim()
        $info = $textInfo.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($description)) {
            Show-AppMessage -Message 'Enter the new Description value.' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace($info)) {
            Show-AppMessage -Message 'Enter the new Info attribute value.' -Type Warning
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:CurrentDomain)) {
            Show-AppMessage -Message 'Search the domain before previewing changes.' -Type Warning
            return
        }

        Set-AppStatus 'Building update preview...'
        $preview = @(New-ComputerUpdatePreview -Computers $records -Server $script:CurrentDomain `
            -Description $description -Info $info)
        Show-PreviewDialog -Preview $preview -Mode (Get-ExecutionModeLabel)
        Set-AppStatus 'Preview completed.'
    } catch {
        Show-AppMessage -Message "Preview failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Preview failed.'
    }
})

$buttonExecute.Add_Click({
    try {
        $records = @(Get-CheckedComputerRecords)
        if ($records.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one workstation.' -Type Warning
            return
        }

        $description = $textDesc.Text.Trim()
        $info = $textInfo.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($description) -or
            [string]::IsNullOrWhiteSpace($info)) {
            Show-AppMessage -Message 'Both Description and Info values are required.' -Type Warning
            return
        }

        $preview = @(New-ComputerUpdatePreview -Computers $records -Server $script:CurrentDomain `
            -Description $description -Info $info)

        $blocked = @($preview | Where-Object { $_.Status -eq 'BLOCKED' }).Count
        $ready = @($preview | Where-Object { $_.Status -eq 'READY' }).Count

        if ($blocked -gt 0) {
            Show-PreviewDialog -Preview $preview -Mode (Get-ExecutionModeLabel)
            Show-AppMessage -Message "$blocked selected object(s) failed pre-commit validation." -Type Error
            return
        }

        if ($chkDryRun.Checked) {
            Show-PreviewDialog -Preview $preview -Mode 'DRY RUN'
            Write-AppLog -Message ("DRY RUN: Selected={0}; WouldChange={1}; Description='{2}'; Info='{3}'." -f
                $records.Count, $ready, $description, $info)
            Show-AppMessage -Message ("Dry Run completed. {0} workstation(s) would be changed; Active Directory was not modified." -f $ready) -Type Information
            Set-AppStatus 'Dry Run completed; no changes committed.'
            return
        }

        if ($ready -eq 0) {
            Show-AppMessage -Message 'All selected workstations already contain the requested values.' -Type Information
            return
        }

        $confirmation = @"
COMMIT Active Directory computer metadata changes?

Domain: $($script:CurrentDomain)
Selected: $($records.Count)
Changes required: $ready

Description: $description
Info: $info
"@

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmation,
            'Confirm Active Directory Computer Update',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'Commit cancelled by operator.' -Level WARN
            Set-AppStatus 'Commit cancelled.'
            return
        }

        Set-AppStatus 'Updating and verifying computer accounts...'
        $results = @(Set-ADComputerMetadataControlled -Computers $records -Server $script:CurrentDomain `
            -Description $description -Info $info -Confirm:$false)

        $success = @($results | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $failed = @($results | Where-Object { $_.Result -eq 'FAILED' }).Count
        $skipped = @($results | Where-Object { $_.Result -eq 'SKIPPED' }).Count

        # Refresh from AD after commit.
        $script:SearchResults = @(Find-ADWorkstations -Server $script:CurrentDomain)
        Apply-ResultsFilter -FilterText $textFilter.Text

        $summary = @"
Execution completed.

Success: $success
Failed: $failed
Skipped: $skipped

Log: $($script:LogFile)
"@

        if ($failed -gt 0) {
            Show-AppMessage -Message $summary -Type Warning
        } else {
            Write-AppLog -Message ("Commit summary: Success={0}; Failed={1}; Skipped={2}" -f
                $success, $failed, $skipped) -Level SUCCESS
            [void][System.Windows.Forms.MessageBox]::Show(
                $summary,
                'Execution Summary',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }

        Set-AppStatus ("Completed: Success={0}, Failed={1}, Skipped={2}" -f
            $success, $failed, $skipped)
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
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    $domains = @(Get-ForestDomains)
    foreach ($domain in $domains) {
        [void]$comboDomain.Items.Add($domain)
    }

    if ($comboDomain.Items.Count -eq 0) {
        throw 'No Active Directory domains were discovered.'
    }

    $comboDomain.SelectedIndex = 0
    Write-AppLog -Message ("Discovered forest domains: {0}" -f ($domains -join ', ')) -Level SUCCESS

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'AD Computer Description and Info Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
