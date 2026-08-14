<#
.SYNOPSIS
  Server Disk Space Audit Tool v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for auditing logical disk capacity and free space
  across one or more Windows servers.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before GUI initialization
  - Discovers every Domain Controller across every domain in the current AD forest
  - Uses Full Forest Domain Controllers as the default audit scope
  - Supports manual server entry and optional current computer targeting
  - Audits fixed logical disks using CIM/WMI-compatible classes
  - Captures Total GB, Free GB, Used GB, Free %, Used %, Volume Name, File System,
    and Drive Letter
  - Provides configurable warning/critical free-space thresholds
  - Provides client-side filtering across every displayed column
  - Groups displayed disk rows into visual sections by server/domain controller
  - Provides ascending/descending sorting by clicking column headers
  - Continues processing when individual servers fail
  - Reports per-server connectivity/query failures without losing successful results
  - Exports either all retrieved rows or only currently displayed rows to CSV
  - Produces timestamped audit logs in C:\Logs-TEMP
  - Performs read-only operations only

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.2.0-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - Remote management permissions to target servers
  - WinRM/CIM connectivity when auditing remote systems
  - RSAT ActiveDirectory PowerShell module for Full Forest Domain Controller discovery
#>

#Requires -Version 5.1

[CmdletBinding()]
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

    # ActiveDirectory is imported only after console suppression so GUI startup
    # does not expose a transient PowerShell console window.
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory -ErrorAction Stop
    } else {
        Write-Warning 'ActiveDirectory module is not available. Full Forest DC discovery will be unavailable; Manual/Local modes remain usable.'
    }
} catch {
    Write-Error "Failed to initialize GUI components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot          = 'C:\Logs-TEMP'
$script:RunStamp         = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile          = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:AuditResults     = @()
$script:DisplayedResults = @()
$script:SortColumn       = -1
$script:SortDescending   = $false

$script:listView         = $null
$script:txtRuntimeLog    = $null
$script:statusMain       = $null

if (-not (Test-Path -LiteralPath $script:LogRoot)) {
    New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
}

# =====================================================================================
# Logging / messaging
# =====================================================================================
function Write-AppLog {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')][string]$Level='INFO'
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
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('Information','Warning','Error')][string]$Type='Information'
    )

    switch ($Type) {
        'Error' {
            Write-AppLog -Message $Message -Level ERROR
            $icon = [System.Windows.Forms.MessageBoxIcon]::Error
        }
        'Warning' {
            Write-AppLog -Message $Message -Level WARN
            $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        }
        default {
            Write-AppLog -Message $Message -Level INFO
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message, $Type,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    )
}

function Set-AppStatus {
    param([Parameter(Mandatory=$true)][string]$Text)
    if ($script:statusMain -and -not $script:statusMain.IsDisposed) {
        $script:statusMain.Text = $Text
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function ConvertTo-ServerNameList {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text)

    return @(
        $Text -split '[,;`\r`\n\s]+' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
}

# =====================================================================================
# Active Directory forest / Domain Controller discovery
# =====================================================================================
function Get-ForestDomainControllers {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -Name ActiveDirectory)) {
        throw 'The ActiveDirectory module is required for Full Forest Domain Controller discovery.'
    }

    Write-AppLog -Message 'Discovering all Domain Controllers across the Active Directory forest.'

    $forest = Get-ADForest -ErrorAction Stop
    $servers = New-Object System.Collections.ArrayList
    $failures = New-Object System.Collections.ArrayList

    foreach ($domain in @($forest.Domains | Sort-Object)) {
        try {
            $dcs = @(
                Get-ADDomainController -Filter * -Server $domain -ErrorAction Stop |
                Sort-Object HostName
            )

            foreach ($dc in $dcs) {
                $hostName = [string]$dc.HostName
                if ([string]::IsNullOrWhiteSpace($hostName)) {
                    $hostName = [string]$dc.Name
                }

                if (-not [string]::IsNullOrWhiteSpace($hostName)) {
                    [void]$servers.Add([pscustomobject]@{
                        ComputerName = $hostName
                        DomainFQDN   = [string]$domain
                        Site         = [string]$dc.Site
                        IPv4Address  = [string]$dc.IPv4Address
                        IsGlobalCatalog = [bool]$dc.IsGlobalCatalog
                        IsReadOnly   = [bool]$dc.IsReadOnly
                    })
                }
            }

            Write-AppLog -Message ("Domain Controller discovery for '{0}' returned {1} DC(s)." -f
                $domain, $dcs.Count) -Level SUCCESS
        } catch {
            [void]$failures.Add([pscustomobject]@{
                Domain = [string]$domain
                Detail = $_.Exception.Message
            })
            Write-AppLog -Message "Domain Controller discovery failed for '$domain': $($_.Exception.Message)" -Level ERROR
        }
    }

    # Deduplicate by FQDN while preserving discovery metadata.
    $unique = @(
        $servers |
        Group-Object ComputerName |
        ForEach-Object { $_.Group | Select-Object -First 1 } |
        Sort-Object DomainFQDN, ComputerName
    )

    Write-AppLog -Message ("Forest discovery completed. Domains={0}; UniqueDCs={1}; DomainFailures={2}." -f
        $forest.Domains.Count, $unique.Count, $failures.Count) -Level SUCCESS

    return [pscustomobject]@{
        ForestName = [string]$forest.Name
        Servers    = @($unique)
        Failures   = @($failures)
    }
}

function Resolve-AuditTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Scope,
        [AllowEmptyString()][string]$ManualText
    )

    switch ($Scope) {
        'Full Forest Domain Controllers' {
            $discovery = Get-ForestDomainControllers
            if (@($discovery.Servers).Count -eq 0) {
                throw 'No Domain Controllers were discovered in the forest.'
            }

            return [pscustomobject]@{
                ComputerNames = @($discovery.Servers | Select-Object -ExpandProperty ComputerName)
                Discovery     = $discovery
            }
        }

        'Manual Server(s)' {
            $servers = @(ConvertTo-ServerNameList -Text $ManualText)
            if ($servers.Count -eq 0) {
                throw 'Enter at least one server name or FQDN.'
            }

            return [pscustomobject]@{
                ComputerNames = $servers
                Discovery     = $null
            }
        }

        'Local Server' {
            return [pscustomobject]@{
                ComputerNames = @($env:COMPUTERNAME)
                Discovery     = $null
            }
        }

        default {
            throw "Unsupported audit scope '$Scope'."
        }
    }
}

# =====================================================================================
# Disk audit
# =====================================================================================
function Get-DiskSeverity {
    param(
        [Parameter(Mandatory=$true)][double]$FreePercent,
        [Parameter(Mandatory=$true)][double]$WarningThreshold,
        [Parameter(Mandatory=$true)][double]$CriticalThreshold
    )

    if ($FreePercent -le $CriticalThreshold) { return 'CRITICAL' }
    if ($FreePercent -le $WarningThreshold) { return 'WARNING' }
    return 'OK'
}

function Get-ServerDiskAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][double]$WarningThreshold,
        [Parameter(Mandatory=$true)][double]$CriticalThreshold
    )

    $rows = New-Object System.Collections.ArrayList

    try {
        Set-AppStatus "Querying $ComputerName..."
        Write-AppLog -Message "Starting disk audit for '$ComputerName'."

        if ($ComputerName -ne $env:COMPUTERNAME -and $ComputerName -ne 'localhost' -and $ComputerName -ne '.') {
            Test-WSMan -ComputerName $ComputerName -ErrorAction Stop | Out-Null
        }

        $session = $null
        try {
            if ($ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq 'localhost' -or $ComputerName -eq '.') {
                $disks = @(
                    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
                )
            } else {
                $session = New-CimSession -ComputerName $ComputerName -ErrorAction Stop
                $disks = @(
                    Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk `
                        -Filter "DriveType=3" -ErrorAction Stop
                )
            }

            foreach ($disk in $disks) {
                [double]$size = [double]$disk.Size
                [double]$free = [double]$disk.FreeSpace

                $totalGB = if ($size -gt 0) { [math]::Round($size / 1GB, 2) } else { 0 }
                $freeGB  = if ($free -ge 0) { [math]::Round($free / 1GB, 2) } else { 0 }
                $usedGB  = [math]::Round(($size - $free) / 1GB, 2)
                $freePct = if ($size -gt 0) { [math]::Round(($free / $size) * 100, 2) } else { 0 }
                $usedPct = if ($size -gt 0) { [math]::Round(100 - $freePct, 2) } else { 0 }
                $severity = Get-DiskSeverity -FreePercent $freePct `
                    -WarningThreshold $WarningThreshold -CriticalThreshold $CriticalThreshold

                [void]$rows.Add([pscustomobject]@{
                    ComputerName = [string]$ComputerName
                    Drive        = [string]$disk.DeviceID
                    VolumeName   = [string]$disk.VolumeName
                    FileSystem   = [string]$disk.FileSystem
                    TotalGB      = [double]$totalGB
                    UsedGB       = [double]$usedGB
                    FreeGB       = [double]$freeGB
                    UsedPercent  = [double]$usedPct
                    FreePercent  = [double]$freePct
                    Severity     = [string]$severity
                    QueryStatus  = 'SUCCESS'
                    Detail       = ''
                })
            }

            Write-AppLog -Message ("Disk audit completed for '{0}'. Fixed disks={1}." -f
                $ComputerName, $disks.Count) -Level SUCCESS
        } finally {
            if ($null -ne $session) {
                Remove-CimSession -CimSession $session -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-AppLog -Message "Disk audit failed for '$ComputerName': $($_.Exception.Message)" -Level ERROR
        [void]$rows.Add([pscustomobject]@{
            ComputerName = [string]$ComputerName
            Drive        = ''
            VolumeName   = ''
            FileSystem   = ''
            TotalGB      = 0
            UsedGB       = 0
            FreeGB       = 0
            UsedPercent  = 0
            FreePercent  = 0
            Severity     = 'ERROR'
            QueryStatus  = 'FAILED'
            Detail       = $_.Exception.Message
        })
    }

    return @($rows)
}

function Invoke-DiskAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$ComputerNames,
        [Parameter(Mandatory=$true)][double]$WarningThreshold,
        [Parameter(Mandatory=$true)][double]$CriticalThreshold
    )

    $all = New-Object System.Collections.ArrayList

    foreach ($computer in $ComputerNames) {
        foreach ($row in @(Get-ServerDiskAudit -ComputerName $computer `
            -WarningThreshold $WarningThreshold -CriticalThreshold $CriticalThreshold)) {
            [void]$all.Add($row)
        }
    }

    return @($all)
}

# =====================================================================================
# Searchable / sortable results
# =====================================================================================
function Set-ResultListViewData {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Results
    )

    $script:listView.BeginUpdate()
    try {
        $script:listView.Items.Clear()
        $script:listView.Groups.Clear()
        $script:listView.ShowGroups = $true

        $groupsByServer = @{}

        foreach ($serverName in @($Results | Select-Object -ExpandProperty ComputerName -Unique)) {
            $serverRows = @($Results | Where-Object { $_.ComputerName -eq $serverName })

            $diskRows = @($serverRows | Where-Object { $_.QueryStatus -eq 'SUCCESS' })
            $criticalCount = @($diskRows | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
            $warningCount  = @($diskRows | Where-Object { $_.Severity -eq 'WARNING' }).Count
            $errorCount    = @($serverRows | Where-Object { $_.QueryStatus -eq 'FAILED' }).Count

            $header = "{0}   |   Disks: {1}   |   Critical: {2}   |   Warning: {3}   |   Query Errors: {4}" -f
                $serverName, $diskRows.Count, $criticalCount, $warningCount, $errorCount

            $group = New-Object System.Windows.Forms.ListViewGroup
            $group.Header = $header
            $group.Name = [string]$serverName
            $group.Tag = [string]$serverName

            [void]$script:listView.Groups.Add($group)
            $groupsByServer[[string]$serverName] = $group
        }

        foreach ($row in $Results) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$row.ComputerName)
            [void]$item.SubItems.Add([string]$row.Drive)
            [void]$item.SubItems.Add([string]$row.VolumeName)
            [void]$item.SubItems.Add([string]$row.FileSystem)
            [void]$item.SubItems.Add(("{0:N2}" -f $row.TotalGB))
            [void]$item.SubItems.Add(("{0:N2}" -f $row.UsedGB))
            [void]$item.SubItems.Add(("{0:N2}" -f $row.FreeGB))
            [void]$item.SubItems.Add(("{0:N2}" -f $row.UsedPercent))
            [void]$item.SubItems.Add(("{0:N2}" -f $row.FreePercent))
            [void]$item.SubItems.Add([string]$row.Severity)
            [void]$item.SubItems.Add([string]$row.QueryStatus)
            [void]$item.SubItems.Add([string]$row.Detail)

            if ($groupsByServer.ContainsKey([string]$row.ComputerName)) {
                $item.Group = $groupsByServer[[string]$row.ComputerName]
            }

            $item.Tag = $row
            [void]$script:listView.Items.Add($item)
        }
    } finally {
        $script:listView.EndUpdate()
    }
}

function Test-ResultMatchesFilter {
    param(
        [Parameter(Mandatory=$true)]$Result,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) { return $true }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Result.ComputerName,
        [string]$Result.Drive,
        [string]$Result.VolumeName,
        [string]$Result.FileSystem,
        [string]$Result.TotalGB,
        [string]$Result.UsedGB,
        [string]$Result.FreeGB,
        [string]$Result.UsedPercent,
        [string]$Result.FreePercent,
        [string]$Result.Severity,
        [string]$Result.QueryStatus,
        [string]$Result.Detail
    )

    foreach ($value in $values) {
        if ($value.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-ResultsFilter {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:AuditResults | Where-Object {
            Test-ResultMatchesFilter -Result $_ -FilterText $FilterText
        }
    )

    $script:DisplayedResults = $filtered
    Set-ResultListViewData -Results $filtered
    Set-AppStatus ("Displayed {0} of {1} row(s)." -f
        $filtered.Count, $script:AuditResults.Count)
}

function Sort-AuditResults {
    param(
        [Parameter(Mandatory=$true)][int]$ColumnIndex,
        [Parameter(Mandatory=$true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0  { $property='ComputerName' }
        1  { $property='Drive' }
        2  { $property='VolumeName' }
        3  { $property='FileSystem' }
        4  { $property='TotalGB' }
        5  { $property='UsedGB' }
        6  { $property='FreeGB' }
        7  { $property='UsedPercent' }
        8  { $property='FreePercent' }
        9  { $property='Severity' }
        10 { $property='QueryStatus' }
        11 { $property='Detail' }
        default { $property='Drive' }
    }

    if ($property -eq 'ComputerName') {
        $script:AuditResults = @(
            $script:AuditResults |
            Sort-Object -Property ComputerName -Descending:$Descending
        )
    } else {
        # Preserve visual server sections while sorting rows inside each server group.
        $script:AuditResults = @(
            $script:AuditResults |
            Sort-Object `
                @{Expression='ComputerName'; Descending=$false},
                @{Expression=$property; Descending=$Descending}
        )
    }
}

# =====================================================================================
# Export
# =====================================================================================
function Export-AuditResults {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [object[]]$Data,
        [Parameter(Mandatory=$true)][string]$SuggestedName
    )

    if ($Data.Count -eq 0) {
        Show-AppMessage -Message 'No data is available to export.' -Type Information
        return
    }

    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'CSV files (*.csv)|*.csv'
    $dialog.FileName = $SuggestedName

    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        $Data |
            Select-Object ComputerName,Drive,VolumeName,FileSystem,TotalGB,UsedGB,FreeGB,
                UsedPercent,FreePercent,Severity,QueryStatus,Detail |
            Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Delimiter ';' -Encoding UTF8

        Write-AppLog -Message ("Exported {0} row(s) to '{1}'." -f
            $Data.Count, $dialog.FileName) -Level SUCCESS
    } catch {
        Show-AppMessage -Message "Export failed: $($_.Exception.Message)" -Type Error
    }
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Server Disk Space Audit - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1320, 820)
$form.MinimumSize = New-Object System.Drawing.Size(1080, 700)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock='Fill'
$main.Padding=New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount=1
$main.RowCount=7
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',68)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',32)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$targetPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$targetPanel.Dock='Fill'; $targetPanel.AutoSize=$true; $targetPanel.WrapContents=$false

$labelScope = New-Object System.Windows.Forms.Label
$labelScope.Text='Audit Scope:'; $labelScope.AutoSize=$true
$labelScope.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
$targetPanel.Controls.Add($labelScope)

$comboScope = New-Object System.Windows.Forms.ComboBox
$comboScope.Width=220
$comboScope.DropDownStyle='DropDownList'
[void]$comboScope.Items.AddRange(@(
    'Full Forest Domain Controllers',
    'Manual Server(s)',
    'Local Server'
))
$comboScope.SelectedIndex=0
$targetPanel.Controls.Add($comboScope)

$labelServers = New-Object System.Windows.Forms.Label
$labelServers.Text='Manual Server(s):'; $labelServers.AutoSize=$true
$labelServers.Margin=New-Object System.Windows.Forms.Padding(20,7,3,3)
$targetPanel.Controls.Add($labelServers)

$textServers = New-Object System.Windows.Forms.TextBox
$textServers.Width=330
$textServers.Enabled=$false
$targetPanel.Controls.Add($textServers)

$labelWarn = New-Object System.Windows.Forms.Label
$labelWarn.Text='Warning %:'; $labelWarn.AutoSize=$true
$labelWarn.Margin=New-Object System.Windows.Forms.Padding(20,7,3,3)
$targetPanel.Controls.Add($labelWarn)

$numWarn = New-Object System.Windows.Forms.NumericUpDown
$numWarn.Minimum=1; $numWarn.Maximum=99; $numWarn.Value=20; $numWarn.Width=60
$targetPanel.Controls.Add($numWarn)

$labelCrit = New-Object System.Windows.Forms.Label
$labelCrit.Text='Critical %:'; $labelCrit.AutoSize=$true
$labelCrit.Margin=New-Object System.Windows.Forms.Padding(10,7,3,3)
$targetPanel.Controls.Add($labelCrit)

$numCrit = New-Object System.Windows.Forms.NumericUpDown
$numCrit.Minimum=1; $numCrit.Maximum=99; $numCrit.Value=10; $numCrit.Width=60
$targetPanel.Controls.Add($numCrit)

$buttonAudit = New-Object System.Windows.Forms.Button
$buttonAudit.Text='Run Audit'; $buttonAudit.Width=100
$targetPanel.Controls.Add($buttonAudit)

$main.Controls.Add($targetPanel,0,0)

$filterPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$filterPanel.Dock='Fill'; $filterPanel.AutoSize=$true; $filterPanel.WrapContents=$false

$labelFilter = New-Object System.Windows.Forms.Label
$labelFilter.Text='Filter displayed columns:'; $labelFilter.AutoSize=$true
$labelFilter.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
$filterPanel.Controls.Add($labelFilter)

$textFilter = New-Object System.Windows.Forms.TextBox
$textFilter.Width=520
$filterPanel.Controls.Add($textFilter)

$buttonClear = New-Object System.Windows.Forms.Button
$buttonClear.Text='Clear Filter'; $buttonClear.Width=100
$filterPanel.Controls.Add($buttonClear)

$buttonExportDisplayed = New-Object System.Windows.Forms.Button
$buttonExportDisplayed.Text='Export Displayed'; $buttonExportDisplayed.Width=120
$filterPanel.Controls.Add($buttonExportDisplayed)

$buttonExportAll = New-Object System.Windows.Forms.Button
$buttonExportAll.Text='Export All'; $buttonExportAll.Width=100
$filterPanel.Controls.Add($buttonExportAll)

$main.Controls.Add($filterPanel,0,1)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock='Fill'; $listView.View='Details'; $listView.FullRowSelect=$true
$listView.GridLines=$true; $listView.HideSelection=$false; $listView.ShowGroups=$true
[void]$listView.Columns.Add('Server',190)
[void]$listView.Columns.Add('Drive',60)
[void]$listView.Columns.Add('Volume',120)
[void]$listView.Columns.Add('FS',70)
[void]$listView.Columns.Add('Total GB',85)
[void]$listView.Columns.Add('Used GB',85)
[void]$listView.Columns.Add('Free GB',85)
[void]$listView.Columns.Add('Used %',75)
[void]$listView.Columns.Add('Free %',75)
[void]$listView.Columns.Add('Severity',90)
[void]$listView.Columns.Add('Query',80)
[void]$listView.Columns.Add('Detail',320)
$script:listView=$listView
$main.Controls.Add($listView,0,2)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize=$true; $summaryLabel.Text='No disk audit has been run.'
$main.Controls.Add($summaryLabel,0,3)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize=$true; $noteLabel.MaximumSize=New-Object System.Drawing.Size(1240,0)
$noteLabel.Text='Default scope is Full Forest Domain Controllers: every domain in the current forest is enumerated and every discovered DC is audited. Results are grouped into one visual section per server/DC. Severity is based on Free %: CRITICAL at or below the Critical threshold, WARNING at or below the Warning threshold, otherwise OK. This tool performs read-only disk queries.'
$main.Controls.Add($noteLabel,0,4)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock='Fill'; $txtRuntimeLog.Multiline=$true; $txtRuntimeLog.ReadOnly=$true
$txtRuntimeLog.ScrollBars='Vertical'; $txtRuntimeLog.Font=New-Object System.Drawing.Font('Consolas',8.5)
$script:txtRuntimeLog=$txtRuntimeLog
$main.Controls.Add($txtRuntimeLog,0,5)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusMain = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusMain.Spring=$true; $statusMain.TextAlign='MiddleLeft'; $statusMain.Text='Ready'
$script:statusMain=$statusMain
[void]$statusStrip.Items.Add($statusMain)

$statusLog = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLog.Text="Log: $($script:LogFile)"
[void]$statusStrip.Items.Add($statusLog)
$main.Controls.Add($statusStrip,0,6)

# =====================================================================================
# GUI events
# =====================================================================================
$comboScope.Add_SelectedIndexChanged({
    $textServers.Enabled = ($comboScope.SelectedItem -eq 'Manual Server(s)')
})

$textFilter.Add_TextChanged({
    try {
        Apply-ResultsFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedResults.Count) | Total rows: $($script:AuditResults.Count)"
    } catch {
        Write-AppLog -Message "Display filter failed: $($_.Exception.Message)" -Level ERROR
    }
})

$buttonClear.Add_Click({ $textFilter.Clear() })

$listView.Add_ColumnClick({
    param($sender,$eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-AuditResults -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-ResultsFilter -FilterText $textFilter.Text
})

$buttonAudit.Add_Click({
    try {
        $scope = [string]$comboScope.SelectedItem
        $targets = Resolve-AuditTargets -Scope $scope -ManualText $textServers.Text
        $servers = @($targets.ComputerNames)

        [double]$warning = [double]$numWarn.Value
        [double]$critical = [double]$numCrit.Value

        if ($critical -ge $warning) {
            Show-AppMessage -Message 'Critical threshold must be lower than the Warning threshold.' -Type Warning
            return
        }

        Write-AppLog -Message ("Starting disk audit. Scope='{0}'; Servers={1}; Warning={2}%; Critical={3}%." -f
            $scope, ($servers -join ', '), $warning, $critical)

        $textFilter.Clear()
        $script:AuditResults = @(Invoke-DiskAudit -ComputerNames $servers `
            -WarningThreshold $warning -CriticalThreshold $critical)
        $script:DisplayedResults = @($script:AuditResults)
        Set-ResultListViewData -Results $script:DisplayedResults

        $diskRows = @($script:AuditResults | Where-Object { $_.QueryStatus -eq 'SUCCESS' })
        $failRows = @($script:AuditResults | Where-Object { $_.QueryStatus -eq 'FAILED' })
        $criticalRows = @($diskRows | Where-Object { $_.Severity -eq 'CRITICAL' })
        $warningRows = @($diskRows | Where-Object { $_.Severity -eq 'WARNING' })

        if ($scope -eq 'Full Forest Domain Controllers' -and $null -ne $targets.Discovery) {
            $domainFailures = @($targets.Discovery.Failures).Count
            $summaryLabel.Text = "Forest: $($targets.Discovery.ForestName) | DCs: $($servers.Count) | Disk rows: $($diskRows.Count) | Critical: $($criticalRows.Count) | Warning: $($warningRows.Count) | Query failures: $($failRows.Count) | Domain discovery failures: $domainFailures"
        } else {
            $summaryLabel.Text = "Servers: $($servers.Count) | Disk rows: $($diskRows.Count) | Critical: $($criticalRows.Count) | Warning: $($warningRows.Count) | Query failures: $($failRows.Count)"
        }
        Write-AppLog -Message ("Audit summary: DiskRows={0}; Critical={1}; Warning={2}; QueryFailures={3}." -f
            $diskRows.Count,$criticalRows.Count,$warningRows.Count,$failRows.Count) -Level SUCCESS
        Set-AppStatus 'Disk audit completed.'
    } catch {
        Show-AppMessage -Message "Disk audit failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Disk audit failed.'
    }
})

$buttonExportDisplayed.Add_Click({
    $name = "$($script:ScriptName)-DISPLAYED-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    Export-AuditResults -Data @($script:DisplayedResults) -SuggestedName $name
})

$buttonExportAll.Add_Click({
    $name = "$($script:ScriptName)-ALL-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    Export-AuditResults -Data @($script:AuditResults) -SuggestedName $name
})

# =====================================================================================
# Main
# =====================================================================================
try {
    Write-AppLog -Message "Starting $($script:ScriptName)."
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}" -f
        $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString)

    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Server Disk Space Audit',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
