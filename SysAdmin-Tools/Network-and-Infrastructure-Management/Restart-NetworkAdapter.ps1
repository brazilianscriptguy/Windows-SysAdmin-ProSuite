<#
.SYNOPSIS
  Network Adapter Restart and Profile Audit Tool v2.0.0 Enterprise Edition.

.DESCRIPTION
  Enterprise Windows Forms tool for auditing and safely restarting local physical
  Ethernet network adapters on Windows Server.

  The tool:
  - Supports Windows PowerShell 5.1 and Windows Server 2019
  - Hides the PowerShell console before GUI initialization
  - Requires no ActiveDirectory module
  - Inventories physical Ethernet adapters using stable InterfaceIndex/InterfaceGuid identity
  - Displays adapter status, MAC address, link speed, IPv4 address, default gateway,
    connection-profile name, network category, interface description, and driver information
  - Provides client-side filtering across every displayed column
  - Provides ascending/descending sorting by clicking column headers
  - Uses Dry Run by default
  - Revalidates InterfaceGuid immediately before a restart
  - Uses verified disable/enable state transitions rather than fixed blind sleeps
  - Resolves adapters by InterfaceIndex, validates InterfaceGuid, then passes the NetAdapter object through the pipeline to Disable-NetAdapter / Enable-NetAdapter for Windows Server 2019 compatibility
  - Verifies post-restart adapter state and refreshes IP/profile information
  - Logs connection-profile changes before and after restart
  - Warns when executed inside an RDP session because restarting the active adapter can
    terminate the administrative session
  - Produces timestamped audit logs in C:\Logs-TEMP

  IMPORTANT:
  This utility restarts a network adapter. It does not rename Windows network profiles,
  manipulate Network List Manager registry data, force DomainAuthenticated status, or
  modify VMware virtual hardware. Network profile changes are audited and reported only.

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-08-14-v2.0.1-ENTERPRISE-EDITION

.REQUIREMENTS
  - Windows PowerShell 5.1
  - Windows Server 2019
  - Local administrative privileges for adapter restart
  - NetAdapter and NetTCPIP modules available in Windows Server 2019
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

    foreach ($requiredModule in @('NetAdapter','NetTCPIP')) {
        if (-not (Get-Module -ListAvailable -Name $requiredModule)) {
            throw "Required PowerShell module '$requiredModule' is not installed or available."
        }
        Import-Module $requiredModule -ErrorAction Stop
    }
} catch {
    Write-Error "Failed to initialize required components: $($_.Exception.Message)"
    return
}

# =====================================================================================
# Globals
# =====================================================================================
$script:ScriptName        = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogRoot           = 'C:\Logs-TEMP'
$script:RunStamp          = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile           = Join-Path $script:LogRoot "$($script:ScriptName)-$($script:RunStamp).log"

$script:AdapterInventory  = @()
$script:DisplayedAdapters = @()
$script:SortColumn        = -1
$script:SortDescending    = $false

$script:listViewAdapters  = $null
$script:txtRuntimeLog     = $null
$script:statusMain        = $null
$script:statusMode        = $null
$script:chkDryRun         = $null

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

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-IsRdpSession {
    try {
        return ([string]$env:SESSIONNAME -like 'RDP-*')
    } catch {
        return $false
    }
}

function ConvertTo-DisplayValue {
    param($Value, [string]$Default = '')
    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }
    return $text
}

# =====================================================================================
# Adapter inventory
# =====================================================================================
function Get-AdapterRuntimeRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uint32]$InterfaceIndex
    )

    $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction Stop

    $ipConfig = $null
    try {
        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $InterfaceIndex -ErrorAction Stop
    } catch { }

    $profile = $null
    try {
        $profile = Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex -ErrorAction Stop
    } catch { }

    $advancedDriver = $null
    try {
        $advancedDriver = Get-NetAdapterAdvancedProperty -InterfaceDescription $adapter.InterfaceDescription `
            -ErrorAction SilentlyContinue | Select-Object -First 1
    } catch { }

    $ipv4 = ''
    $gateway = ''

    if ($null -ne $ipConfig) {
        if ($null -ne $ipConfig.IPv4Address) {
            $ipv4 = (@($ipConfig.IPv4Address | Select-Object -ExpandProperty IPAddress) -join ', ')
        }
        if ($null -ne $ipConfig.IPv4DefaultGateway) {
            $gateway = (@($ipConfig.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop) -join ', ')
        }
    }

    $driverVersion = ''
    try {
        $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
            Where-Object { $_.DeviceID -eq $adapter.PnPDeviceID } |
            Select-Object -First 1
        if ($null -ne $driver) {
            $driverVersion = [string]$driver.DriverVersion
        }
    } catch { }

    return [pscustomobject]@{
        Name              = [string]$adapter.Name
        InterfaceIndex    = [uint32]$adapter.InterfaceIndex
        InterfaceGuid     = [Guid]$adapter.InterfaceGuid
        Status            = [string]$adapter.Status
        MacAddress        = [string]$adapter.MacAddress
        LinkSpeed         = [string]$adapter.LinkSpeed
        IPv4Address       = $ipv4
        DefaultGateway    = $gateway
        ProfileName       = if ($null -eq $profile) { '' } else { [string]$profile.Name }
        NetworkCategory   = if ($null -eq $profile) { '' } else { [string]$profile.NetworkCategory }
        InterfaceDescription = [string]$adapter.InterfaceDescription
        DriverVersion     = $driverVersion
        PnPDeviceID       = [string]$adapter.PnPDeviceID
        MediaType         = [string]$adapter.MediaType
        PhysicalMediaType = [string]$adapter.PhysicalMediaType
    }
}

function Get-PhysicalEthernetAdapters {
    [CmdletBinding()]
    param()

    $adapters = @(
        Get-NetAdapter -Physical -ErrorAction Stop |
        Where-Object {
            $_.MediaType -eq '802.3' -or
            $_.MediaType -eq 'Ethernet' -or
            $_.InterfaceDescription -match 'Ethernet|VMXNET|E1000'
        } |
        Sort-Object InterfaceIndex
    )

    $records = New-Object System.Collections.ArrayList
    foreach ($adapter in $adapters) {
        try {
            [void]$records.Add((Get-AdapterRuntimeRecord -InterfaceIndex $adapter.InterfaceIndex))
        } catch {
            Write-AppLog -Message "Failed to inventory interface index $($adapter.InterfaceIndex): $($_.Exception.Message)" -Level ERROR
        }
    }

    Write-AppLog -Message ("Physical Ethernet adapter inventory completed. Adapters={0}" -f $records.Count) -Level SUCCESS
    return @($records)
}

function Test-AdapterIdentity {
    param(
        [Parameter(Mandatory = $true)]$Record
    )

    try {
        $current = Get-NetAdapter -InterfaceIndex $Record.InterfaceIndex -ErrorAction Stop
        return ([Guid]$current.InterfaceGuid -eq [Guid]$Record.InterfaceGuid)
    } catch {
        return $false
    }
}

# =====================================================================================
# Searchable / sortable results browser
# =====================================================================================
function Set-AdapterListViewData {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Adapters
    )

    $selectedGuids = @{}
    foreach ($item in $script:listViewAdapters.SelectedItems) {
        if ($null -ne $item.Tag) {
            $selectedGuids[[string]$item.Tag.InterfaceGuid] = $true
        }
    }

    $script:listViewAdapters.BeginUpdate()
    try {
        $script:listViewAdapters.Items.Clear()

        foreach ($adapter in $Adapters) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$adapter.Name)
            [void]$item.SubItems.Add([string]$adapter.InterfaceIndex)
            [void]$item.SubItems.Add([string]$adapter.Status)
            [void]$item.SubItems.Add([string]$adapter.MacAddress)
            [void]$item.SubItems.Add([string]$adapter.LinkSpeed)
            [void]$item.SubItems.Add([string]$adapter.IPv4Address)
            [void]$item.SubItems.Add([string]$adapter.DefaultGateway)
            [void]$item.SubItems.Add([string]$adapter.ProfileName)
            [void]$item.SubItems.Add([string]$adapter.NetworkCategory)
            [void]$item.SubItems.Add([string]$adapter.InterfaceDescription)
            [void]$item.SubItems.Add([string]$adapter.DriverVersion)
            $item.Tag = $adapter

            if ($selectedGuids.ContainsKey([string]$adapter.InterfaceGuid)) {
                $item.Selected = $true
            }

            [void]$script:listViewAdapters.Items.Add($item)
        }
    } finally {
        $script:listViewAdapters.EndUpdate()
    }
}

function Test-AdapterMatchesFilter {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return $true
    }

    $needle = $FilterText.Trim()
    $values = @(
        [string]$Adapter.Name,
        [string]$Adapter.InterfaceIndex,
        [string]$Adapter.Status,
        [string]$Adapter.MacAddress,
        [string]$Adapter.LinkSpeed,
        [string]$Adapter.IPv4Address,
        [string]$Adapter.DefaultGateway,
        [string]$Adapter.ProfileName,
        [string]$Adapter.NetworkCategory,
        [string]$Adapter.InterfaceDescription,
        [string]$Adapter.DriverVersion
    )

    foreach ($value in $values) {
        if ($null -ne $value -and
            $value.IndexOf($needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Apply-AdapterFilter {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$FilterText)

    $filtered = @(
        $script:AdapterInventory | Where-Object {
            Test-AdapterMatchesFilter -Adapter $_ -FilterText $FilterText
        }
    )

    $script:DisplayedAdapters = $filtered
    Set-AdapterListViewData -Adapters $filtered

    Set-AppStatus ("Displayed {0} of {1} adapter(s)." -f
        $filtered.Count, $script:AdapterInventory.Count)
}

function Sort-AdapterInventory {
    param(
        [Parameter(Mandatory = $true)][int]$ColumnIndex,
        [Parameter(Mandatory = $true)][bool]$Descending
    )

    switch ($ColumnIndex) {
        0  { $property = 'Name' }
        1  { $property = 'InterfaceIndex' }
        2  { $property = 'Status' }
        3  { $property = 'MacAddress' }
        4  { $property = 'LinkSpeed' }
        5  { $property = 'IPv4Address' }
        6  { $property = 'DefaultGateway' }
        7  { $property = 'ProfileName' }
        8  { $property = 'NetworkCategory' }
        9  { $property = 'InterfaceDescription' }
        10 { $property = 'DriverVersion' }
        default { $property = 'InterfaceIndex' }
    }

    $script:AdapterInventory = @(
        $script:AdapterInventory |
        Sort-Object -Property $property -Descending:$Descending
    )
}

function Get-SelectedAdapterRecord {
    if ($script:listViewAdapters.SelectedItems.Count -ne 1) {
        return $null
    }

    return $script:listViewAdapters.SelectedItems[0].Tag
}

# =====================================================================================
# Verified adapter restart
# =====================================================================================
function Wait-NetAdapterState {
    param(
        [Parameter(Mandatory = $true)][uint32]$InterfaceIndex,
        [Parameter(Mandatory = $true)][string[]]$DesiredStatus,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    do {
        try {
            $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction Stop
            if ($DesiredStatus -contains [string]$adapter.Status) {
                return $adapter
            }
        } catch { }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for interface index $InterfaceIndex to reach state: $($DesiredStatus -join ', ')."
}

function Wait-NetIPConfiguration {
    param(
        [Parameter(Mandatory = $true)][uint32]$InterfaceIndex,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        try {
            $config = Get-NetIPConfiguration -InterfaceIndex $InterfaceIndex -ErrorAction Stop
            if ($null -ne $config) {
                return $config
            }
        } catch { }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Restart-NetworkAdapterControlled {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]$Record
    )

    if (-not (Test-AdapterIdentity -Record $Record)) {
        throw 'Adapter identity no longer matches the discovered InterfaceIndex/InterfaceGuid. Refresh the inventory before retrying.'
    }

    $before = Get-AdapterRuntimeRecord -InterfaceIndex $Record.InterfaceIndex
    $target = "{0} [ifIndex={1}; GUID={2}]" -f $before.Name, $before.InterfaceIndex, $before.InterfaceGuid
    $action = 'Disable and re-enable network adapter, then verify final state'

    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        return [pscustomobject]@{
            Result          = 'SKIPPED'
            Before          = $before
            After           = $null
            ProfileChanged  = $false
            Detail          = 'ShouldProcess declined the operation.'
        }
    }

    try {
        Write-AppLog -Message ("Restart beginning: Name='{0}'; ifIndex={1}; Status={2}; IPv4='{3}'; Gateway='{4}'; Profile='{5}'; Category='{6}'." -f
            $before.Name, $before.InterfaceIndex, $before.Status, $before.IPv4Address,
            $before.DefaultGateway, $before.ProfileName, $before.NetworkCategory)

        $adapterObject = Get-NetAdapter -InterfaceIndex $before.InterfaceIndex -ErrorAction Stop
        $adapterObject | Disable-NetAdapter -Confirm:$false -ErrorAction Stop
        [void](Wait-NetAdapterState -InterfaceIndex $before.InterfaceIndex `
            -DesiredStatus @('Disabled','Disconnected') -TimeoutSeconds 30)

        Write-AppLog -Message ("Adapter '{0}' successfully reached disabled/disconnected state." -f $before.Name) -Level SUCCESS

        $adapterObject = Get-NetAdapter -InterfaceIndex $before.InterfaceIndex -ErrorAction Stop
        $adapterObject | Enable-NetAdapter -Confirm:$false -ErrorAction Stop
        [void](Wait-NetAdapterState -InterfaceIndex $before.InterfaceIndex `
            -DesiredStatus @('Up','Disconnected') -TimeoutSeconds 45)

        [void](Wait-NetIPConfiguration -InterfaceIndex $before.InterfaceIndex -TimeoutSeconds 30)
        Start-Sleep -Seconds 2

        $after = Get-AdapterRuntimeRecord -InterfaceIndex $before.InterfaceIndex

        if ([Guid]$after.InterfaceGuid -ne [Guid]$before.InterfaceGuid) {
            throw 'Post-restart InterfaceGuid differs from the pre-restart adapter identity.'
        }

        if ($after.Status -ne 'Up') {
            throw "Adapter did not return to Up state. Current status: $($after.Status)."
        }

        $profileChanged = (
            [string]$before.ProfileName -ne [string]$after.ProfileName -or
            [string]$before.NetworkCategory -ne [string]$after.NetworkCategory
        )

        if ($profileChanged) {
            Write-AppLog -Message ("Network profile changed after restart: '{0}'/{1} -> '{2}'/{3}." -f
                $before.ProfileName, $before.NetworkCategory,
                $after.ProfileName, $after.NetworkCategory) -Level WARN
        } else {
            Write-AppLog -Message ("Network profile remained stable: '{0}' / {1}." -f
                $after.ProfileName, $after.NetworkCategory) -Level SUCCESS
        }

        Write-AppLog -Message ("Restart verified: Name='{0}'; Status={1}; IPv4='{2}'; Gateway='{3}'; Profile='{4}'; Category='{5}'." -f
            $after.Name, $after.Status, $after.IPv4Address,
            $after.DefaultGateway, $after.ProfileName, $after.NetworkCategory) -Level SUCCESS

        return [pscustomobject]@{
            Result          = 'SUCCESS'
            Before          = $before
            After           = $after
            ProfileChanged  = $profileChanged
            Detail          = 'Adapter restarted and verified.'
        }
    } catch {
        Write-AppLog -Message "Adapter restart failed for '$($before.Name)': $($_.Exception.Message)" -Level ERROR

        # Fail-safe recovery attempt: if the adapter remains disabled, try to enable it.
        try {
            $current = Get-NetAdapter -InterfaceIndex $before.InterfaceIndex -ErrorAction Stop
            if ($current.Status -eq 'Disabled') {
                Write-AppLog -Message "Fail-safe recovery: attempting to re-enable '$($before.Name)'." -Level WARN
                $adapterObject = Get-NetAdapter -InterfaceIndex $before.InterfaceIndex -ErrorAction Stop
                $adapterObject | Enable-NetAdapter -Confirm:$false -ErrorAction Stop
                [void](Wait-NetAdapterState -InterfaceIndex $before.InterfaceIndex `
                    -DesiredStatus @('Up','Disconnected') -TimeoutSeconds 45)
                Write-AppLog -Message "Fail-safe recovery re-enabled '$($before.Name)'." -Level SUCCESS
            }
        } catch {
            Write-AppLog -Message "Fail-safe adapter recovery also failed: $($_.Exception.Message)" -Level ERROR
        }

        return [pscustomobject]@{
            Result          = 'FAILED'
            Before          = $before
            After           = $null
            ProfileChanged  = $false
            Detail          = $_.Exception.Message
        }
    }
}

function Show-AdapterPreview {
    param(
        [Parameter(Mandatory = $true)]$Adapter,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    $text = @"
Execution mode    : $Mode

Adapter Name      : $($Adapter.Name)
Interface Index   : $($Adapter.InterfaceIndex)
Interface GUID    : $($Adapter.InterfaceGuid)
Status            : $($Adapter.Status)
MAC Address       : $($Adapter.MacAddress)
Link Speed        : $($Adapter.LinkSpeed)
IPv4 Address      : $($Adapter.IPv4Address)
Default Gateway   : $($Adapter.DefaultGateway)
Profile Name      : $($Adapter.ProfileName)
Network Category  : $($Adapter.NetworkCategory)
Description       : $($Adapter.InterfaceDescription)
Driver Version    : $($Adapter.DriverVersion)

The operation will disable and re-enable this adapter, then verify its status,
IP configuration, stable adapter identity, and Windows network profile.
"@

    [void][System.Windows.Forms.MessageBox]::Show(
        $text,
        'Network Adapter Restart Preview',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

# =====================================================================================
# GUI
# =====================================================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Network Adapter Restart and Profile Audit - Enterprise Edition'
$form.Size = New-Object System.Drawing.Size(1380, 830)
$form.MinimumSize = New-Object System.Drawing.Size(1120, 720)
$form.StartPosition = 'CenterScreen'

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'
$main.Padding = New-Object System.Windows.Forms.Padding(10)
$main.ColumnCount = 1
$main.RowCount = 7
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 70)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 30)))
$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
$form.Controls.Add($main)

$topPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$topPanel.Dock = 'Fill'
$topPanel.AutoSize = $true
$topPanel.WrapContents = $false

$buttonRefresh = New-Object System.Windows.Forms.Button
$buttonRefresh.Text = 'Refresh Adapters'
$buttonRefresh.Width = 120
$topPanel.Controls.Add($buttonRefresh)

$buttonPreview = New-Object System.Windows.Forms.Button
$buttonPreview.Text = 'Preview Restart'
$buttonPreview.Width = 120
$topPanel.Controls.Add($buttonPreview)

$buttonRestart = New-Object System.Windows.Forms.Button
$buttonRestart.Text = 'Restart Selected'
$buttonRestart.Width = 125
$topPanel.Controls.Add($buttonRestart)

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'Dry Run'
$chkDryRun.Checked = $true
$chkDryRun.AutoSize = $true
$chkDryRun.Margin = New-Object System.Windows.Forms.Padding(20, 6, 3, 3)
$script:chkDryRun = $chkDryRun
$topPanel.Controls.Add($chkDryRun)

$main.Controls.Add($topPanel, 0, 0)

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
$textFilter.Width = 570
$filterPanel.Controls.Add($textFilter)

$buttonClearFilter = New-Object System.Windows.Forms.Button
$buttonClearFilter.Text = 'Clear Filter'
$buttonClearFilter.Width = 100
$filterPanel.Controls.Add($buttonClearFilter)

$main.Controls.Add($filterPanel, 0, 1)

$listViewAdapters = New-Object System.Windows.Forms.ListView
$listViewAdapters.Dock = 'Fill'
$listViewAdapters.View = 'Details'
$listViewAdapters.FullRowSelect = $true
$listViewAdapters.MultiSelect = $false
$listViewAdapters.GridLines = $true
$listViewAdapters.HideSelection = $false
[void]$listViewAdapters.Columns.Add('Name', 120)
[void]$listViewAdapters.Columns.Add('ifIndex', 65)
[void]$listViewAdapters.Columns.Add('Status', 85)
[void]$listViewAdapters.Columns.Add('MAC Address', 125)
[void]$listViewAdapters.Columns.Add('Link Speed', 90)
[void]$listViewAdapters.Columns.Add('IPv4 Address', 145)
[void]$listViewAdapters.Columns.Add('Default Gateway', 125)
[void]$listViewAdapters.Columns.Add('Profile Name', 160)
[void]$listViewAdapters.Columns.Add('Category', 120)
[void]$listViewAdapters.Columns.Add('Interface Description', 260)
[void]$listViewAdapters.Columns.Add('Driver Version', 120)
$script:listViewAdapters = $listViewAdapters
$main.Controls.Add($listViewAdapters, 0, 2)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.AutoSize = $true
$summaryLabel.Text = 'No adapter inventory loaded.'
$main.Controls.Add($summaryLabel, 0, 3)

$noteLabel = New-Object System.Windows.Forms.Label
$noteLabel.AutoSize = $true
$noteLabel.MaximumSize = New-Object System.Drawing.Size(1300, 0)
$noteLabel.Text = 'This tool audits but does not force a network profile name/category. If Windows changes SEDE.TJAP to an unidentified or numbered network profile after the restart, the before/after state is recorded in the execution log for root-cause analysis.'
$main.Controls.Add($noteLabel, 0, 4)

$txtRuntimeLog = New-Object System.Windows.Forms.TextBox
$txtRuntimeLog.Dock = 'Fill'
$txtRuntimeLog.Multiline = $true
$txtRuntimeLog.ReadOnly = $true
$txtRuntimeLog.ScrollBars = 'Vertical'
$txtRuntimeLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$script:txtRuntimeLog = $txtRuntimeLog
$main.Controls.Add($txtRuntimeLog, 0, 5)

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

$main.Controls.Add($statusStrip, 0, 6)

# =====================================================================================
# GUI event handlers
# =====================================================================================
function Refresh-AdapterInventory {
    try {
        Set-AppStatus 'Refreshing physical Ethernet adapter inventory...'
        $textFilter.Clear()
        $script:AdapterInventory = @(Get-PhysicalEthernetAdapters)
        $script:DisplayedAdapters = @($script:AdapterInventory)
        Set-AdapterListViewData -Adapters $script:DisplayedAdapters
        $summaryLabel.Text = "Physical Ethernet adapters: $($script:AdapterInventory.Count)"
        Set-AppStatus ("Loaded {0} adapter(s)." -f $script:AdapterInventory.Count)
    } catch {
        Show-AppMessage -Message "Adapter inventory failed: $($_.Exception.Message)" -Type Error
        Set-AppStatus 'Adapter inventory failed.'
    }
}

$chkDryRun.Add_CheckedChanged({
    $script:statusMode.Text = 'Mode: ' + (Get-ExecutionModeLabel)
})

$buttonRefresh.Add_Click({
    Refresh-AdapterInventory
})

$textFilter.Add_TextChanged({
    try {
        Apply-AdapterFilter -FilterText $textFilter.Text
        $summaryLabel.Text = "Displayed: $($script:DisplayedAdapters.Count) | Total adapters: $($script:AdapterInventory.Count)"
    } catch {
        Write-AppLog -Message "Adapter filter failed: $($_.Exception.Message)" -Level ERROR
        Set-AppStatus 'Adapter filter failed.'
    }
})

$buttonClearFilter.Add_Click({
    $textFilter.Clear()
})

$listViewAdapters.Add_ColumnClick({
    param($sender, $eventArgs)

    if ($script:SortColumn -eq $eventArgs.Column) {
        $script:SortDescending = -not $script:SortDescending
    } else {
        $script:SortColumn = $eventArgs.Column
        $script:SortDescending = $false
    }

    Sort-AdapterInventory -ColumnIndex $script:SortColumn -Descending $script:SortDescending
    Apply-AdapterFilter -FilterText $textFilter.Text
})

$buttonPreview.Add_Click({
    $selected = Get-SelectedAdapterRecord
    if ($null -eq $selected) {
        Show-AppMessage -Message 'Select exactly one network adapter.' -Type Warning
        return
    }

    Show-AdapterPreview -Adapter $selected -Mode (Get-ExecutionModeLabel)
})

$buttonRestart.Add_Click({
    try {
        $selected = Get-SelectedAdapterRecord
        if ($null -eq $selected) {
            Show-AppMessage -Message 'Select exactly one network adapter.' -Type Warning
            return
        }

        if (-not (Test-IsAdministrator)) {
            Show-AppMessage -Message 'Restarting a network adapter requires local administrative privileges. Run the tool elevated.' -Type Error
            return
        }

        if (-not (Test-AdapterIdentity -Record $selected)) {
            Show-AppMessage -Message 'The selected adapter no longer matches its discovered InterfaceIndex/InterfaceGuid. Refresh the inventory and select it again.' -Type Error
            return
        }

        if ($chkDryRun.Checked) {
            Show-AdapterPreview -Adapter $selected -Mode 'DRY RUN'
            Write-AppLog -Message ("DRY RUN: Adapter '{0}' [ifIndex={1}] selected; no state changed." -f
                $selected.Name, $selected.InterfaceIndex)
            Show-AppMessage -Message 'Dry Run completed. The selected adapter would be disabled and re-enabled; no network state was changed.' -Type Information
            Set-AppStatus 'Dry Run completed; no changes committed.'
            return
        }

        $rdpWarning = ''
        if (Test-IsRdpSession) {
            $rdpWarning = @"

WARNING: This tool is running inside an RDP session.
Restarting the active network adapter can immediately disconnect this session.
"@
        }

        $confirmation = @"
COMMIT network adapter restart?

Adapter: $($selected.Name)
Interface Index: $($selected.InterfaceIndex)
Status: $($selected.Status)
IPv4: $($selected.IPv4Address)
Gateway: $($selected.DefaultGateway)
Profile: $($selected.ProfileName)
Category: $($selected.NetworkCategory)
$rdpWarning
The adapter will be disabled and re-enabled, then its identity, state,
IP configuration, and Windows network profile will be verified.
"@

        $answer = [System.Windows.Forms.MessageBox]::Show(
            $confirmation,
            'Confirm Network Adapter Restart',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2
        )

        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-AppLog -Message 'Network adapter restart cancelled by operator.' -Level WARN
            Set-AppStatus 'Commit cancelled.'
            return
        }

        Set-AppStatus "Restarting $($selected.Name)..."
        $result = Restart-NetworkAdapterControlled -Record $selected -Confirm:$false

        Refresh-AdapterInventory

        if ($result.Result -eq 'SUCCESS') {
            $message = @"
Network adapter restarted and verified successfully.

Before:
  Status: $($result.Before.Status)
  IPv4: $($result.Before.IPv4Address)
  Profile: $($result.Before.ProfileName)
  Category: $($result.Before.NetworkCategory)

After:
  Status: $($result.After.Status)
  IPv4: $($result.After.IPv4Address)
  Profile: $($result.After.ProfileName)
  Category: $($result.After.NetworkCategory)

Profile changed: $($result.ProfileChanged)
"@
            [void][System.Windows.Forms.MessageBox]::Show(
                $message,
                'Restart Verified',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Set-AppStatus 'Adapter restart completed and verified.'
        } else {
            Show-AppMessage -Message ("Adapter restart failed: {0}" -f $result.Detail) -Type Error
            Set-AppStatus 'Adapter restart failed.'
        }
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
    Write-AppLog -Message ("Host PowerShell: {0}; OS: {1}; Session='{2}'" -f
        $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, $env:SESSIONNAME)

    if (-not (Test-IsAdministrator)) {
        Write-AppLog -Message 'Process is not elevated. Inventory is available, but adapter restart will be blocked until the tool is run elevated.' -Level WARN
    }

    if (Test-IsRdpSession) {
        Write-AppLog -Message 'RDP session detected. Restarting the active adapter may terminate the administrative session.' -Level WARN
    }

    Refresh-AdapterInventory
    [void]$form.ShowDialog()
} catch {
    Write-AppLog -Message "Fatal startup error: $($_.Exception.Message)" -Level ERROR
    [void][System.Windows.Forms.MessageBox]::Show(
        "Fatal startup error:`r`n$($_.Exception.Message)",
        'Network Adapter Restart and Profile Audit',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
} finally {
    Write-AppLog -Message "Closing $($script:ScriptName)."
}

# End of script
