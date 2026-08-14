<#
.SYNOPSIS
  Remote Print Services Manager v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for auditing and restarting the Windows Print Spooler
  service and, when installed, the Line Printer Daemon service (LPDSVC) on remote
  Windows servers.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before GUI initialization
  - Does not require the ActiveDirectory module
  - Supports authorized DHCP-server discovery for backward compatibility with the
    legacy script, but does not misidentify DHCP authorization as print-server discovery
  - Supports manual server entry for explicit targeting
  - Audits WinRM connectivity, Spooler state, and LPDSVC state before restart
  - Provides searchable/filterable results across every displayed column
  - Provides ascending/descending sorting by clicking column headers
  - Supports multiple selected servers
  - Uses Dry Run by default
  - Preserves the pre-restart running state of dependent Spooler services
  - Restarts only dependent services that were running before the operation
  - Treats LPDSVC as optional: absence is reported as NOT INSTALLED, not as a failure
  - Verifies final Spooler and LPDSVC states after restart
  - Produces per-server SUCCESS / PARTIAL / FAILED / SKIPPED results
  - Produces timestamped audit logs in C:\Logs-TEMP

  IMPORTANT:
  The legacy script's Get-ForestServers function used Get-DhcpServerInDC. That cmdlet
  returns DHCP servers authorized in Active Directory; it is not a print-server
  discovery mechanism. This version retains that source only as an explicit legacy
  discovery option and supports manual target entry.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - PowerShell Remoting / WinRM enabled and permitted to the target server(s)
  - Administrative rights on target server(s) sufficient to restart services
  - DhcpServer PowerShell module only when using Authorized DHCP Servers discovery
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
} catch {
    Write-Error "Failed to initialize required GUI components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot          = 'C:\Logs-TEMP'
$script:RunStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile          = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:ServerInventory  = @()
$script:DisplayedServers = @()
$script:SortColumn       = -1
$script:SortDescending   = $false

$script:listViewServers  = $null
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

function ConvertTo-ServerNameList {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    return @(
        $Text -split '[,;`\r`\n\s]+' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
}

# =====================================================================================
# Server discovery
# =====================================================================================
function Get-AuthorizedDhcpServers {
    try {
        if (-not (Get-Module -ListAvailable -Name DhcpServer)) {
            throw 'The DhcpServer PowerShell module is not installed or available.'
        }

        Import-Module DhcpServer -ErrorAction Stop

        $servers = @(
            Get-DhcpServerInDC -ErrorAction Stop |
            Select-Object -ExpandProperty DNSName |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
        )

        Write-AppLog -Message ("Authorized DHCP server discovery returned {0} server(s)." -f $servers.Count) -Level SUCCESS
        return $servers
    } catch {
        throw "Unable to retrieve authorized DHCP servers: $($_.Exception.Message)"
    }
}

# =====================================================================================
# Remote service audit
# =====================================================================================
function Get-RemotePrintServiceState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ComputerName)

    $result = [ordered]@{
        ComputerName     = $ComputerName
        WinRM            = 'Unknown'
        SpoolerStatus    = 'Unknown'
        SpoolerStartType = 'Unknown'
        LPDStatus        = 'Unknown'
        LPDStartType     = 'Unknown'
        LastResult       = 'AUDIT'
        Detail           = ''
    }

    try {
        Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null
        $result.WinRM = 'Available'
    } catch {
        $result.WinRM = 'Unavailable'
        $result.LastResult = 'FAILED'
        $result.Detail = "WinRM unavailable: $($_.Exception.Message)"
        Write-AppLog -Message "Audit failed for '$ComputerName': $($result.Detail)" -Level ERROR
        return [pscustomobject]$result
    }

    try {
        $remote = Invoke-Command -ComputerName $ComputerName -ErrorAction Stop -ScriptBlock {
            $spooler = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction Stop
            $lpd = Get-CimInstance -ClassName Win32_Service -Filter "Name='LPDSVC'" -ErrorAction SilentlyContinue

            [pscustomobject]@{
                SpoolerStatus    = [string]$spooler.State
                SpoolerStartType = [string]$spooler.StartMode
                LPDStatus        = if ($null -eq $lpd) { 'NOT INSTALLED' } else { [string]$lpd.State }
                LPDStartType     = if ($null -eq $lpd) { 'N/A' } else { [string]$lpd.StartMode }
            }
        }

        $result.SpoolerStatus    = $remote.SpoolerStatus
        $result.SpoolerStartType = $remote.SpoolerStartType
        $result.LPDStatus        = $remote.LPDStatus
        $result.LPDStartType     = $remote.LPDStartType
        $result.LastResult       = 'AUDIT OK'
        $result.Detail           = 'Remote service audit completed.'

        Write-AppLog -Message ("Audit '{0}': Spooler={1}/{2}; LPDSVC={3}/{4}." -f
            $ComputerName, $result.SpoolerStatus, $result.SpoolerStartType,
            $result.LPDStatus, $result.LPDStartType) -Level SUCCESS
    } catch {
        $result.LastResult = 'FAILED'
        $result.Detail = $_.Exception.Message
        Write-AppLog -Message "Remote service audit failed for '$ComputerName': $($_.Exception.Message)" -Level ERROR
    }

    return [pscustomobject]$result
}

function Invoke-ServerInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$ComputerNames)

    $inventory = New-Object System.Collections.ArrayList

    foreach ($computer in $ComputerNames) {
        Set-AppStatus "Auditing $computer..."
        [void]$inventory.Add((Get-RemotePrintServiceState -ComputerName $computer))
    }

    return @($inventory)
}

# =====================================================================================
# Searchable / sortable results browser
# =====================================================================================
function Set-ServerListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Servers
    )

    $selectedNames = @{}
    foreach ($item in $script:listViewServers.SelectedItems) {
        if ($null -ne $item.Tag) {
            $selectedNames[[string]$item.Tag.ComputerName] = $true
        }
    }

    $script:listViewServers.BeginUpdate()
    try {
        $script:listViewServers.Items.Clear()

        foreach ($server in $Servers) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$server.ComputerName)
            [void]$item.SubItems.Add([string]$server.WinRM)
            [void]$item.SubItems.Add([string]$server.SpoolerStatus)
            [void]$item.SubItems.Add([string]$server.SpoolerStartType)
            [void]$item.SubItems.Add([string]$server.LPDStatus)
            [void]$item.SubItems.Add([string]$server.LPDStartType)
            [void]$item.SubItems.Add([string]$server.LastResult)
            [void]$item.SubItems.Add([string]$server.Detail)
            $item.Tag = $server

            if ($selectedNames.ContainsKey([string]$server.ComputerName)) {
                $item.Selected = $true
            }

            [void]$script:listViewServers.Items.Add($item)
        }
    } finally {
        $script:listViewServers.EndUpdate()
    }
}

function Test-ServerMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$Server,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Server.ComputerName,
        [string]$Server.WinRM,
        [string]$Server.SpoolerStatus,
        [string]$Server.SpoolerStartType,
        [string]$Server.LPDStatus,
        [string]$Server.LPDStartType,
        [string]$Server.LastResult,
        [string]$Server.Detail
    )

    foreach ($value in $values) {
        if ($null -ne $value -and
            $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ServerFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:ServerInventory | Where-Object {
            Test-ServerMatchesFilter -Server $_ -FilterText $FilterText
        }
    )

    $script:DisplayedServers = $filtered
    Set-ServerListViewData -Servers $filtered

    Set-AppStatus ("Displayed {0} of {1} server(s)." -f
        $filtered.Count, $script:ServerInventory.Count)
}

function Sort-ServerInventory {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0 { $property = 'ComputerName' }
        1 { $property = 'WinRM' }
        2 { $property = 'SpoolerStatus' }
        3 { $property = 'SpoolerStartType' }
        4 { $property = 'LPDStatus' }
        5 { $property = 'LPDStartType' }
        6 { $property = 'LastResult' }
        7 { $property = 'Detail' }
        default { $property = 'ComputerName' }
    }

    $script:ServerInventory = @(
        $script:ServerInventory |
        Sort-Object -Property $property -Descending:$Descending
    )
}

function Get-SelectedServerRecords {
    $records = New-Object System.Collections.ArrayList

    foreach ($item in $script:listViewServers.SelectedItems) {
        if ($null -ne $item.Tag) {
            [void]$records.Add($item.Tag)
        }
    }

    return @($records)
}

# =====================================================================================
# Controlled restart and verification
# =====================================================================================
function Restart-RemotePrintServices {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)][string]$ComputerName)

    $target = "$ComputerName : Spooler + optional LPDSVC"
    $action = 'Restart remote print services and verify final service state'

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return [pscustomobject]@{
            ComputerName  = $ComputerName
            Result        = 'SKIPPED'
            SpoolerStatus = 'Unknown'
            LPDStatus     = 'Unknown'
            Detail        = 'ShouldProcess declined the operation.'
        }
    }

    try {
        Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null

        $result = Invoke-Command -ComputerName $ComputerName -ErrorAction Stop -ScriptBlock {
            $ErrorActionPreference = 'Stop'

            $details = New-Object System.Collections.Generic.List[string]
            $spooler = Get-Service -Name 'Spooler' -ErrorAction Stop

            # Snapshot only dependents that were running. Stopped dependent services
            # must not be started as a side effect of restarting Spooler.
            $runningDependents = @(
                $spooler.DependentServices |
                Where-Object { $_.Status -eq 'Running' } |
                Select-Object -ExpandProperty Name
            )

            foreach ($serviceName in $runningDependents) {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $svc = Get-Service -Name $serviceName -ErrorAction Stop
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                $details.Add("Stopped dependent service '$serviceName'.")
            }

            $spooler = Get-Service -Name 'Spooler' -ErrorAction Stop
            if ($spooler.Status -ne 'Stopped') {
                Stop-Service -Name 'Spooler' -Force -ErrorAction Stop
                $spooler.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
            }

            Start-Service -Name 'Spooler' -ErrorAction Stop
            $spooler = Get-Service -Name 'Spooler' -ErrorAction Stop
            $spooler.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            $details.Add("Spooler restarted.")

            foreach ($serviceName in $runningDependents) {
                $svc = Get-Service -Name $serviceName -ErrorAction Stop
                if ($svc.StartType -ne 'Disabled') {
                    Start-Service -Name $serviceName -ErrorAction Stop
                    $svc = Get-Service -Name $serviceName -ErrorAction Stop
                    $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                    $details.Add("Restored dependent service '$serviceName'.")
                } else {
                    $details.Add("Dependent service '$serviceName' became Disabled and was not restarted.")
                }
            }

            $lpdStatus = 'NOT INSTALLED'
            $lpdResult = 'NOT INSTALLED'

            $lpd = Get-Service -Name 'LPDSVC' -ErrorAction SilentlyContinue
            if ($null -ne $lpd) {
                if ($lpd.StartType -eq 'Disabled') {
                    $lpdStatus = [string]$lpd.Status
                    $lpdResult = 'SKIPPED - DISABLED'
                    $details.Add('LPDSVC is disabled; restart skipped.')
                } else {
                    if ($lpd.Status -ne 'Stopped') {
                        Stop-Service -Name 'LPDSVC' -Force -ErrorAction Stop
                        $lpd = Get-Service -Name 'LPDSVC' -ErrorAction Stop
                        $lpd.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                    }

                    Start-Service -Name 'LPDSVC' -ErrorAction Stop
                    $lpd = Get-Service -Name 'LPDSVC' -ErrorAction Stop
                    $lpd.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))

                    $lpdStatus = [string]$lpd.Status
                    $lpdResult = 'RESTARTED'
                    $details.Add('LPDSVC restarted.')
                }
            }

            $finalSpooler = Get-Service -Name 'Spooler' -ErrorAction Stop

            [pscustomobject]@{
                SpoolerStatus = [string]$finalSpooler.Status
                LPDStatus     = $lpdStatus
                LPDResult     = $lpdResult
                Detail        = ($details -join ' ')
            }
        }

        $overall = if ($result.SpoolerStatus -eq 'Running') {
            if ($result.LPDResult -eq 'SKIPPED - DISABLED') { 'PARTIAL' } else { 'SUCCESS' }
        } else {
            'FAILED'
        }

        if ($overall -eq 'SUCCESS') {
            Write-AppLog -Message ("Restart verified on '{0}': Spooler={1}; LPDSVC={2}." -f
                $ComputerName, $result.SpoolerStatus, $result.LPDStatus) -Level SUCCESS
        } elseif ($overall -eq 'PARTIAL') {
            Write-AppLog -Message ("Restart partially completed on '{0}': {1}" -f
                $ComputerName, $result.Detail) -Level WARN
        } else {
            Write-AppLog -Message ("Restart verification failed on '{0}'." -f $ComputerName) -Level ERROR
        }

        return [pscustomobject]@{
            ComputerName  = $ComputerName
            Result        = $overall
            SpoolerStatus = $result.SpoolerStatus
            LPDStatus     = $result.LPDStatus
            Detail        = $result.Detail
        }
    } catch {
        Write-AppLog -Message "Restart failed on '$ComputerName': $($_.Exception.Message)" -Level ERROR

        return [pscustomobject]@{
            ComputerName  = $ComputerName
            Result        = 'FAILED'
            SpoolerStatus = 'Unknown'
            LPDStatus     = 'Unknown'
            Detail        = $_.Exception.Message
        }
    }
}

function Show-RestartPreview {
    param(
        [Parameter(Mandatory = $true)][object[]]$Servers,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Execution mode : $Mode")
    $lines.Add("Selected       : $($Servers.Count)")
    $lines.Add('')
    $lines.Add(("{0,-32} {1,-12} {2,-12} {3,-16}" -f 'SERVER','WINRM','SPOOLER','LPDSVC'))
    $lines.Add(('-' * 82))

    foreach ($server in $Servers) {
        $lines.Add(("{0,-32} {1,-12} {2,-12} {3,-16}" -f
            $server.ComputerName, $server.WinRM, $server.SpoolerStatus, $server.LPDStatus))
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Print Services Restart Preview'
    $dialog.Size = New-Object System.Drawing.Size(800, 500)
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

    $close = New-Object System.Windows.Forms.Button
    $close.Text = 'Close'
    $close.Width = 100
    $close.Height = 28
    $close.Left = 665
    $close.Top = 8
    $close.Anchor = 'Right,Top'
    $close.Add_Click({ $dialog.Close() })
    $panel.Controls.Add($close)
    $dialog.Controls.Add($panel)

    [void]$dialog.ShowDialog()
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Remote Print Services Manager - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1280, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1060, 720)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 8
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 65)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 35)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$sourcePanel = New-Object System.Windows.Forms.FlowLayoutPanel
$sourcePanel.Dock = 'Fill'
$sourcePanel.AutoSize = $true
$sourcePanel.WrapContents = $false

$labelSource = New-Object System.Windows.Forms.Label
$labelSource.Text = 'Server Source:'
$labelSource.AutoSize = $true
$labelSource.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
$sourcePanel.Controls.Add($labelSource)

$comboSource = New-Object System.Windows.Forms.ComboBox
$comboSource.Width = 230
$comboSource.DropDownStyle = 'DropDownList'
[void]$comboSource.Items.AddRange(@('Manual Server(s)','Authorized DHCP Servers (Legacy)'))
$comboSource.SelectedIndex = 0
$sourcePanel.Controls.Add($comboSource)

$labelManual = New-Object System.Windows.Forms.Label
$labelManual.Text = 'Server(s):'
$labelManual.AutoSize = $true
$labelManual.Margin = New-Object System.Windows.Forms.Padding(20, 7, 3, 3)
$sourcePanel.Controls.Add($labelManual)

$textServers = New-Object System.Windows.Forms.TextBox
$textServers.Width = 430
$sourcePanel.Controls.Add($textServers)

$buttonAudit = New-Object System.Windows.Forms.Button
$buttonAudit.Text = 'Audit Services'
$buttonAudit.Width = 120
$sourcePanel.Controls.Add($buttonAudit)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(20, 6, 3, 3)
$script:chkDryRun = $chkDryRun
$sourcePanel.Controls.Add($chkDryRun)

$main.Controls.Add($sourcePanel, 0, 0)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock = 'Fill'
$filterPanel.AutoSize = $true
$filterPanel.WrapContents = $false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text = 'Filter displayed columns:'
$labelFilter.AutoSize = $true
$labelFilter.Margin = New-Object System.Windows.Forms.Padding(3, 7, 3, 3)
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

$main.Controls.Add($filterPanel, 0, 1)

$actionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$actionPanel.Dock = 'Fill'
$actionPanel.AutoSize = $true
$actionPanel.WrapContents = $false

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview Restart'
$buttonPreview.Width = 130
$actionPanel.Controls.Add($buttonPreview)

$buttonRestart = New-Object System.Windows.Forms.Button
$buttonRestart.Text = 'Restart Selected'
$buttonRestart.Width = 130
$actionPanel.Controls.Add($buttonRestart)

$buttonRefreshSelected = New-Object System.Windows.Forms.Button
$buttonRefreshSelected.Text = 'Re-Audit Selected'
$buttonRefreshSelected.Width = 130
$actionPanel.Controls.Add($buttonRefreshSelected)

$main.Controls.Add($actionPanel, 0, 2)

$listViewServers = New-Object System.Windows.Forms.ListView
$listViewServers.Dock = 'Fill'
$listViewServers.View = 'Details'
$listViewServers.FullRowSelect = $true
$listViewServers.MultiSelect = $true
$listViewServers.GridLines = $true
$listViewServers.HideSelection = $false
[void]$listViewServers.Columns.Add('Server', 190)
[void]$listViewServers.Columns.Add('WinRM', 95)
[void]$listViewServers.Columns.Add('Spooler', 90)
[void]$listViewServers.Columns.Add('Spooler Start', 105)
[void]$listViewServers.Columns.Add('LPDSVC', 110)
[void]$listViewServers.Columns.Add('LPD Start', 100)
[void]$listViewServers.Columns.Add('Result', 110)
[void]$listViewServers.Columns.Add('Detail', 420)
$script:listViewServers = $listViewServers
$main.Controls.Add($listViewServers, 0, 3)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize = $true
$summaryLabel.Text = 'No service audit has been run.'
$main.Controls.Add($summaryLabel, 0, 4)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize = $true
$noteLabel.MaximumSize = New-Object System.Drawing.Size(1200, 0)
$noteLabel.Text = 'Authorized DHCP Servers is retained only as a legacy discovery source. DHCP authorization does not prove that a server is a print server. Use Manual Server(s) for explicit print-server targeting.'
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
# GUI event handlers
# =====================================================================================
$comboSource.Add_SelectedIndexChanged({
    $isManual = ($comboSource.SelectedItem -eq 'Manual Server(s)')
    $textServers.Enabled = $isManual
})

$chkDryRun.Add_CheckedChanged({
    $script:statusMode.Text = 'Mode: ' + (Get-ExecutionModeLabel)
})

$textFilter.Add_TextChanged({
    try {
        Apply-ServerFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedServers.Count) | Total audited: $($script:ServerInventory.Count)"
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Display filter failed.'
    }
})

$buttonClearFilter.Add_Click({
    $textFilter.Clear()
})

$buttonSelectAll.Add_Click({
    foreach ($item in $script:listViewServers.Items) {
        $item.Selected = $true
    }
    Set-AppStatus ("Selected {0} displayed server(s)." -f $script:listViewServers.Items.Count)
})

$listViewServers.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-ServerInventory -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ServerFilter -FilterText $textFilter.Text
})

$buttonAudit.Add_Click({
    try {
        $source = [string]$comboSource.SelectedItem

        if ($source -eq 'Manual Server(s)') {
            $servers = @(ConvertTo-ServerNameList -Text $textServers.Text)
            if ($servers.Count -eq 0) {
                Show-AppMessage -Message 'Enter at least one server name or FQDN.' -Type Warning
                return
            }
        } else {
            Set-AppStatus 'Discovering authorized DHCP servers...'
            $servers = @(Get-AuthorizedDhcpServers)
            if ($servers.Count -eq 0) {
                Show-AppMessage -Message 'No authorized DHCP servers were returned.' -Type Warning
                return
            }
        }

        Write-AppLog -Message ("Starting remote print-service audit. Source='{0}'; Servers={1}" -f
            $source, ($servers -join ', '))

        $textFilter.Clear()
        $script:ServerInventory = @(Invoke-ServerInventory -ComputerNames $servers)
        $script:DisplayedServers = @($script:ServerInventory)
        Set-ServerListViewData -Servers $script:DisplayedServers

        $failed = @($script:ServerInventory | Where-Object { $_.LastResult -eq 'FAILED' }).Count
        $summaryLabel.Text = "Audited: $($script:ServerInventory.Count) | Audit failures: $failed"

        if ($failed -gt 0) {
            Write-AppLog -Message ("Audit completed with {0} failed server(s)." -f $failed) -Level WARN
        } else {
            Write-AppLog -Message ("Audit completed successfully for {0} server(s)." -f
                $script:ServerInventory.Count) -Level SUCCESS
        }

        Set-AppStatus ("Audit completed: {0} server(s)." -f $script:ServerInventory.Count)
    } catch {
        Show-AppMessage -Message "Audit failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Audit failed.'
    }
})

$buttonPreview.Add_Click({
    $selected = @(Get-SelectedServerRecords)
    if ($selected.Count -eq 0) {
        Show-AppMessage -Message 'Select at least one audited server.' -Type Warning
        return
    }

    Show-RestartPreview -Servers $selected -Mode (Get-ExecutionModeLabel)
})

$buttonRefreshSelected.Add_Click({
    try {
        $selected = @(Get-SelectedServerRecords)
        if ($selected.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one audited server.' -Type Warning
            return
        }

        $names = @($selected | Select-Object -ExpandProperty ComputerName)
        $fresh = @(Invoke-ServerInventory -ComputerNames $names)

        $freshByName = @{}
        foreach ($row in $fresh) {
            $freshByName[[string]$row.ComputerName] = $row
        }

        $updated = foreach ($row in $script:ServerInventory) {
            if ($freshByName.ContainsKey([string]$row.ComputerName)) {
                $freshByName[[string]$row.ComputerName]
            } else {
                $row
            }
        }

        $script:ServerInventory = @($updated)
        Apply-ServerFilter -FilterText $textFilter.Text
        Set-AppStatus ("Re-audited {0} selected server(s)." -f $names.Count)
    } catch {
        Show-AppMessage -Message "Re-audit failed: $($_.Exception.Message)" -Type Error
    }
})

$buttonRestart.Add_Click({
    try {
        $selected = @(Get-SelectedServerRecords)
        if ($selected.Count -eq 0) {
            Show-AppMessage -Message 'Select at least one audited server.' -Type Warning
            return
        }

        if ($chkDryRun.Checked) {
            Show-RestartPreview -Servers $selected -Mode 'DRY RUN'
            Write-AppLog -Message ("DRY RUN: {0} server(s) selected; no services restarted." -f $selected.Count)
            Show-AppMessage -Message ("Dry Run completed. {0} selected server(s) would be processed; no service state was changed." -f $selected.Count) -Type Information
            Set-AppStatus 'Dry Run completed; no changes committed.'
            return
        }

        $unreachable = @($selected | Where-Object { $_.WinRM -ne 'Available' })
        if ($unreachable.Count -gt 0) {
            Show-AppMessage -Message ("Commit blocked: {0} selected server(s) do not have working WinRM connectivity. Re-audit or remove them from the selection." -f $unreachable.Count) -Type Error
            return
        }

        $confirmation = @"
COMMIT restart of remote print services?

Selected servers: $($selected.Count)

The operation will:
- Restart Spooler.
- Temporarily stop and restore only Spooler dependent services that are currently running.
- Restart LPDSVC when installed and not disabled.
- Verify final service state.
"@

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmation,
            'Confirm Remote Service Restart',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'Remote print-service restart cancelled by operator.' -Level WARN
            Set-AppStatus 'Commit cancelled.'
            return
        }

        $operationResults = New-Object System.Collections.ArrayList

        foreach ($server in $selected) {
            Set-AppStatus "Restarting print services on $($server.ComputerName)..."
            [void]$operationResults.Add(
                (Restart-RemotePrintServices -ComputerName $server.ComputerName -Confirm:$false)
            )
        }

        $success = @($operationResults | Where-Object { $_.Result -eq 'SUCCESS' }).Count
        $partial = @($operationResults | Where-Object { $_.Result -eq 'PARTIAL' }).Count
        $failed  = @($operationResults | Where-Object { $_.Result -eq 'FAILED' }).Count
        $skipped = @($operationResults | Where-Object { $_.Result -eq 'SKIPPED' }).Count

        # Re-audit all selected targets so the table reflects actual post-operation state.
        $names = @($selected | Select-Object -ExpandProperty ComputerName)
        $fresh = @(Invoke-ServerInventory -ComputerNames $names)
        $freshByName = @{}
        foreach ($row in $fresh) {
            $freshByName[[string]$row.ComputerName] = $row
        }

        $resultByName = @{}
        foreach ($row in $operationResults) {
            $resultByName[[string]$row.ComputerName] = $row
        }

        $updatedInventory = foreach ($row in $script:ServerInventory) {
            $name = [string]$row.ComputerName
            if ($freshByName.ContainsKey($name)) {
                $new = $freshByName[$name]
                if ($resultByName.ContainsKey($name)) {
                    $op = $resultByName[$name]
                    $new.LastResult = $op.Result
                    $new.Detail = $op.Detail
                }
                $new
            } else {
                $row
            }
        }

        $script:ServerInventory = @($updatedInventory)
        Apply-ServerFilter -FilterText $textFilter.Text

        $summary = @"
Execution completed.

Success: $success
Partial: $partial
Failed: $failed
Skipped: $skipped

Log: $($script:LogFile)
"@

        if ($failed -gt 0 -or $partial -gt 0) {
            Show-AppMessage -Message $summary -Type Warning
        } else {
            Write-AppLog -Message ("Restart summary: Success={0}; Partial={1}; Failed={2}; Skipped={3}" -f
                $success, $partial, $failed, $skipped) -Level SUCCESS

            [void][System.Windows.Forms.MessageBox]::Show(
                $summary,
                'Execution Summary',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }

        Set-AppStatus ("Completed: Success={0}, Partial={1}, Failed={2}, Skipped={3}" -f
            $success, $partial, $failed, $skipped)
    } catch {
        Show-AppMessage -Message "Restart execution failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Restart execution failed.'
    }
})

# =====================================================================================
# Main execution
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString)

    Write-AppLog -Message 'ActiveDirectory module is intentionally not required; the legacy import was unused.' -Level INFO

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Remote Print Services Manager',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
