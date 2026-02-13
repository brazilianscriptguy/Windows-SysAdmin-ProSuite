<#
.SYNOPSIS
    PowerShell GUI for DHCP Reservation Creation and Duplicate Scanning

.DESCRIPTION
    This script provides a Windows Forms GUI to:
    - Create new DHCP reservations (MAC/IP validation + duplicate checks)
    - Scan for duplicate MAC/IP across scopes on a selected DHCP server
    - Discover DHCP servers via AD (Get-DhcpServerInDC), with optional manual add (IP/hostname)
    - Live log pane, progress bar, CSV export, and TXT duplicate report
    - Enterprise-friendly behavior: strict mode, admin enforcement, robust error handling, and C:\Logs-TEMP logging
    - UI layout: fixed 900x830 window, non-overlapping controls, and aligned bottom buttons

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-13 - Full functional including DHCP Type (DHCP, BOOTP or BOTH)
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- HIDE CONSOLE (comment for debugging) ---
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
}
"@ -ErrorAction Stop
    [Win]::Hide()
} catch {}

# --- Load WinForms assemblies ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- LOGGING SETUP ---
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP'

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$logPath = Join-Path $logDir "$scriptName.log"

# Default report path (server resolved later)
$script:reportPath = Join-Path $logDir "DHCP_DuplicateReservations_Report_UNKNOWN_SERVER.txt"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"

    # File log (single log file, append-only)
    try {
        Add-Content -Path $logPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {}

    # UI log (thread-safe)
    try {
        if ($script:logBox -and -not $script:logBox.IsDisposed) {
            $append = {
                param($text,$lvl)
                $this.SelectionStart = $this.TextLength
                $this.SelectionColor = switch ($lvl) {
                    'ERROR'   { [System.Drawing.Color]::Red }
                    'WARN'    { [System.Drawing.Color]::DarkOrange }
                    'SUCCESS' { [System.Drawing.Color]::Green }
                    default   { [System.Drawing.Color]::Black }
                }
                $this.AppendText($text + [Environment]::NewLine)
                $this.ScrollToCaret()
                $this.SelectionColor = [System.Drawing.Color]::Black
            }

            if ($script:logBox.InvokeRequired) {
                $null = $script:logBox.BeginInvoke($append, @($entry,$Level))
            } else {
                & $append $entry $Level
            }
        }
    } catch {}
}

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Message',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

function Set-Status {
    param(
        [Parameter(Mandatory)][string]$Text,
        [int]$ProgressValue = -1
    )
    try {
        if ($script:lblStatus -and -not $script:lblStatus.IsDisposed) { $script:lblStatus.Text = $Text }
        if ($ProgressValue -ge 0 -and $script:progress -and -not $script:progress.IsDisposed) {
            $script:progress.Value = [Math]::Max($script:progress.Minimum, [Math]::Min($ProgressValue, $script:progress.Maximum))
        }
    } catch {}
}

# --- Admin check (redundant with #Requires but keeps UX consistent) ---
function Test-AdminPrivileges {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
if (-not (Test-AdminPrivileges)) {
    Show-MessageBox -Message "This script requires administrative privileges. Please run as Administrator." -Title "Error" -Icon Error
    exit 1
}

# --- Import Required Modules ---
function Import-RequiredModule {
    param([Parameter(Mandatory)][string]$Name)
    try {
        Import-Module $Name -ErrorAction Stop
        Write-Log "Module loaded: $Name" "SUCCESS"
    } catch {
        Write-Log "Failed to load module ${Name}: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to load module '$Name':`n$($_.Exception.Message)" -Title "Error" -Icon Error
        throw
    }
}

try {
    Import-RequiredModule -Name 'DhcpServer'
    Import-RequiredModule -Name 'ActiveDirectory'
} catch { exit 1 }

Write-Log "==== Session started ====" "INFO"
Write-Log "LogPath: $logPath" "INFO"

# --- Validation helpers ---
function Normalize-MAC {
    param([Parameter(Mandatory)][string]$Mac)
    $m = $Mac.Trim().ToUpperInvariant().Replace(':','').Replace('-','').Replace('.','')
    return $m
}
function Format-MAC {
    param([Parameter(Mandatory)][string]$Mac12)
    ($Mac12 -replace '(.{2})(?!$)','$1:').ToUpperInvariant()
}
function Test-MACAddress {
    param([Parameter(Mandatory)][string]$Mac)
    $m = Normalize-MAC $Mac
    return ($m -match '^[A-F0-9]{12}$')
}
function Test-IPAddress {
    param([Parameter(Mandatory)][string]$IP)
    try { [Net.IPAddress]::Parse($IP) | Out-Null; return $true } catch { return $false }
}

function Resolve-Hostname {
    param([Parameter(Mandatory)][string]$IPAddress)
    try {
        $dns = [Net.Dns]::GetHostEntry($IPAddress)
        if ($dns -and $dns.HostName) { return $dns.HostName.Split('.')[0] }
    } catch {}
    return "Host-$($IPAddress -replace '\.','-')"
}

function Test-HostReachable {
    param([Parameter(Mandatory)][string]$ComputerNameOrIP)
    try { return (Test-Connection -ComputerName $ComputerNameOrIP -Count 1 -Quiet -ErrorAction Stop) } catch { return $false }
}

function Convert-IpToUInt32 {
    param([Parameter(Mandatory)][string]$ip)
    $bytes = [Net.IPAddress]::Parse($ip).GetAddressBytes()
    [Array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes,0)
}
function Convert-UInt32ToIp {
    param([Parameter(Mandatory)][UInt32]$int)
    $bytes = [BitConverter]::GetBytes($int)
    [Array]::Reverse($bytes)
    return ([Net.IPAddress]::new($bytes)).ToString()
}

# --- Global state ---
$script:AllScopes       = @()
$script:AllReservations = @()
$script:DhcpServers     = @()
$script:CheckedResSet   = New-Object 'System.Collections.Generic.HashSet[string]'

# NEW: keep selected server object at script scope (avoids StrictMode uninitialized var issues)
$script:SelectedDhcpServer = $null

# --- GUI Form ---
$form = New-Object System.Windows.Forms.Form -Property @{
    Text            = "DHCP Reservation & Duplicate Scanner"
    Size            = New-Object System.Drawing.Size(900,830)
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox     = $false
    Font            = New-Object System.Drawing.Font('Segoe UI',9)
}

# Mode panel
$panelMode = New-Object System.Windows.Forms.Panel -Property @{ Location='10,10'; Size='860,40'; BorderStyle='FixedSingle' }
$lblMode   = New-Object System.Windows.Forms.Label -Property @{ Text="Select Mode:"; Location='10,10'; Size='100,20' }
$comboMode = New-Object System.Windows.Forms.ComboBox -Property @{ Location='110,8'; Size='740,24'; DropDownStyle='DropDownList' }
$comboMode.Items.AddRange(@('Create Reservation','Scan Duplicates'))
$comboMode.SelectedIndex = 0
$panelMode.Controls.AddRange(@($lblMode,$comboMode))
$form.Controls.Add($panelMode)

# Domain/Server panel
$panelServer  = New-Object System.Windows.Forms.Panel -Property @{ Location='10,50'; Size='860,90'; BorderStyle='FixedSingle' }
$lblDomain    = New-Object System.Windows.Forms.Label -Property @{ Text="Select Domain:"; Location='10,10'; Size='200,20' }
$comboDomain  = New-Object System.Windows.Forms.ComboBox -Property @{ Location='10,30'; Size='830,24'; DropDownStyle='DropDownList' }
$lblServer    = New-Object System.Windows.Forms.Label -Property @{ Text="Select DHCP Server (or type IP/host):"; Location='10,58'; Size='250,20' }
$comboServer  = New-Object System.Windows.Forms.ComboBox -Property @{ Location='270,56'; Size='570,24'; DropDownStyle='DropDown' }
$panelServer.Controls.AddRange(@($lblDomain,$comboDomain,$lblServer,$comboServer))
$form.Controls.Add($panelServer)

# Create panel
$panelCreate = New-Object System.Windows.Forms.Panel -Property @{ Location='10,150'; Size='860,420'; BorderStyle='FixedSingle'; Visible=$true }
$lblCreateScopes  = New-Object System.Windows.Forms.Label -Property @{ Text="Select Scope:"; Location='10,10'; Size='200,20' }
$listCreateScopes = New-Object System.Windows.Forms.ListView -Property @{ Location='10,30'; Size='830,260'; View='Details'; CheckBoxes=$false; FullRowSelect=$true }
[void]$listCreateScopes.Columns.Add("Scope ID",120)
[void]$listCreateScopes.Columns.Add("Name",250)
[void]$listCreateScopes.Columns.Add("Range",350)

$lblIP        = New-Object System.Windows.Forms.Label -Property @{ Text="Select Available IP:"; Location='10,300'; Size='140,20' }
$comboBoxIPs  = New-Object System.Windows.Forms.ComboBox -Property @{ Location='150,298'; Size='690,24'; DropDownStyle='DropDownList' }
$lblName      = New-Object System.Windows.Forms.Label -Property @{ Text="Reservation Name:"; Location='10,330'; Size='140,20' }
$txtName      = New-Object System.Windows.Forms.TextBox -Property @{ Location='150,328'; Size='690,24' }
$lblMAC       = New-Object System.Windows.Forms.Label -Property @{ Text="MAC Address (D8BBC1830F62):"; Location='10,360'; Size='200,20' }
$txtMAC       = New-Object System.Windows.Forms.TextBox -Property @{ Location='210,358'; Size='630,24' }
$lblDesc      = New-Object System.Windows.Forms.Label -Property @{ Text="Description:"; Location='10,390'; Size='140,20' }
$txtDesc      = New-Object System.Windows.Forms.TextBox -Property @{ Location='150,388'; Size='690,24' }

# Reservation Type (DHCP / BOOTP / BOTH)
$lblResType   = New-Object System.Windows.Forms.Label -Property @{ Text = "Reservation Type:"; Location = '540,390'; Size = '110,20' }
$comboResType = New-Object System.Windows.Forms.ComboBox -Property @{ Location = '650,388'; Size = '190,24'; DropDownStyle = 'DropDownList' }
$comboResType.Items.AddRange(@('DHCP','BOOTP','BOTH'))
$comboResType.SelectedIndex = 0  # default: DHCP

# Adjust Description textbox width to make room for the Type dropdown (same row)
$txtDesc.Size = New-Object System.Drawing.Size(380,24)

# PanelCreate: add controls ONCE (remove duplicate AddRange)
$panelCreate.Controls.AddRange(@(
    $lblCreateScopes, $listCreateScopes,
    $lblIP, $comboBoxIPs,
    $lblName, $txtName,
    $lblMAC, $txtMAC,
    $lblDesc, $txtDesc,
    $lblResType, $comboResType
))
$form.Controls.Add($panelCreate)

# Scan panel
$panelScan = New-Object System.Windows.Forms.Panel -Property @{ Location='10,150'; Size='860,420'; BorderStyle='FixedSingle'; Visible=$false }
$lblReservations  = New-Object System.Windows.Forms.Label -Property @{ Text="Reservations:"; Location='10,10'; Size='200,20' }
$chkSelectAll     = New-Object System.Windows.Forms.CheckBox -Property @{ Text="Select All"; Location='760,10'; Size='90,20' }
$listReservations = New-Object System.Windows.Forms.ListView -Property @{ Location='10,30'; Size='830,320'; View='Details'; CheckBoxes=$true; FullRowSelect=$true }
[void]$listReservations.Columns.Add("IP",140)
[void]$listReservations.Columns.Add("MAC",160)
[void]$listReservations.Columns.Add("Hostname",200)
[void]$listReservations.Columns.Add("Scope",120)
[void]$listReservations.Columns.Add("Server",180)

$lblOutput = New-Object System.Windows.Forms.Label -Property @{ Text="Output Folder:"; Location='10,360'; Size='140,20' }
$txtOutput = New-Object System.Windows.Forms.TextBox -Property @{ Location='150,358'; Size='620,24'; Text=[Environment]::GetFolderPath("MyDocuments") }
$btnBrowse = New-Object System.Windows.Forms.Button -Property @{ Text="Browse"; Location='780,357'; Size='60,26' }
$panelScan.Controls.AddRange(@($lblReservations,$chkSelectAll,$listReservations,$lblOutput,$txtOutput,$btnBrowse))
$form.Controls.Add($panelScan)

# Log panel
$panelLog = New-Object System.Windows.Forms.Panel -Property @{ Location='10,575'; Size='860,120'; BorderStyle='FixedSingle' }
$lblLog   = New-Object System.Windows.Forms.Label -Property @{ Text="Log:"; Location='10,10'; Size='200,20' }
$script:logBox = New-Object System.Windows.Forms.RichTextBox -Property @{ Location='10,30'; Size='830,80'; ReadOnly=$true; ScrollBars='Vertical' }
$panelLog.Controls.AddRange(@($lblLog,$script:logBox))
$form.Controls.Add($panelLog)

# Footer controls (aligned bottom buttons)
$script:progress  = New-Object System.Windows.Forms.ProgressBar -Property @{ Location='10,700'; Size='860,15'; Minimum=0; Maximum=100; Value=0 }
$script:lblStatus = New-Object System.Windows.Forms.Label -Property @{ Text="Ready"; Location='10,720'; Size='860,20' }
$btnAction = New-Object System.Windows.Forms.Button -Property @{ Text="Add Reservation"; Location='10,745'; Size='180,30' }
$btnExport = New-Object System.Windows.Forms.Button -Property @{ Text="Export CSV"; Location='200,745'; Size='140,30'; Visible=$false }
$btnClose  = New-Object System.Windows.Forms.Button -Property @{ Text="Close"; Location='740,745'; Size='130,30' }
$btnClose.Add_Click({ $form.Close() })
$form.Controls.AddRange(@($script:progress,$script:lblStatus,$btnAction,$btnExport,$btnClose))

# --- Domain discovery ---
try {
    Write-Log "Retrieving forest domains..." "INFO"
    $domains = (Get-ADForest -ErrorAction Stop).Domains
    if ($domains -and $domains.Count -gt 0) {
        $comboDomain.Items.AddRange($domains)
        $comboDomain.SelectedIndex = 0
        Write-Log "Domains loaded: $($domains.Count)" "SUCCESS"
    } else {
        Write-Log "No domains found in the forest." "ERROR"
        Show-MessageBox -Message "No domains found in the forest." -Title "Error" -Icon Error
    }
} catch {
    Write-Log "Failed to retrieve forest domains: $($_.Exception.Message)" "ERROR"
    Show-MessageBox -Message "Failed to retrieve forest domains:`n$($_.Exception.Message)" -Title "Error" -Icon Error
}

# --- DHCP server discovery (AD) ---
function Discover-DHCPServers {
    $comboServer.Items.Clear()
    $script:DhcpServers = @()

    try {
        $selDomain = $comboDomain.SelectedItem
        if (-not $selDomain) {
            Set-Status "Select a domain first."
            Write-Log "Discover-DHCPServers aborted: no domain selected." "WARN"
            return
        }

        Set-Status "Discovering DHCP servers..."
        Write-Log "Discovering DHCP servers (filter domain suffix: $selDomain)..." "INFO"

        # NOTE: Get-DhcpServerInDC returns authorized DHCP servers visible to the current context.
        $servers = Get-DhcpServerInDC -ErrorAction Stop

        $idx = 0
        foreach ($s in $servers) {
            if ($s.DnsName -and ($s.DnsName -like "*$selDomain*")) {
                $idx++
                $obj = [PSCustomObject]@{
                    ID          = $idx
                    IP          = $s.IPAddress
                    Name        = $s.DnsName.Split('.')[0]
                    DisplayName = "$($s.DnsName) ($($s.IPAddress))"
                }
                $script:DhcpServers += $obj
                $comboServer.Items.Add($obj.DisplayName) | Out-Null
                Write-Log "Found DHCP server: $($obj.DisplayName)" "INFO"
            }
        }

        if ($script:DhcpServers.Count -eq 0) {
            Set-Status "No DHCP servers found for $selDomain."
            Write-Log "No DHCP servers found for selected domain filter: $selDomain" "WARN"
            Show-MessageBox -Message "No DHCP servers found for the selected domain." -Title "Warning" -Icon Warning
        } else {
            $comboServer.SelectedIndex = 0
            Set-Status "$($script:DhcpServers.Count) DHCP server(s) found."
            Write-Log "Total DHCP servers found: $($script:DhcpServers.Count)" "SUCCESS"
        }
    } catch {
        Set-Status "Error discovering DHCP servers."
        Write-Log "Discover-DHCPServers error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to discover DHCP servers:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
}

# --- Populate scopes for Create mode ---
function Load-CreateScopes {
    $listCreateScopes.Items.Clear()
    $script:AllScopes = @()
    $comboBoxIPs.Items.Clear()

    try {
        $sel = $script:DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
        if (-not $sel) {
            Set-Status "No DHCP server selected."
            Write-Log "Load-CreateScopes aborted: no server selected." "WARN"
            return
        }

        Set-Status "Loading scopes..."
        Write-Log "Loading scopes from $($sel.DisplayName)..." "INFO"

        $scopes = Get-DhcpServerv4Scope -ComputerName $sel.IP -ErrorAction Stop
        foreach ($sc in $scopes) {
            $scopeID = $sc.ScopeId.ToString()
            $name    = $sc.Name
            $range   = "$($sc.StartRange)-$($sc.EndRange)"
            $script:AllScopes += [PSCustomObject]@{ ScopeID=$scopeID; Name=$name; Range=$range }

            $item = New-Object System.Windows.Forms.ListViewItem $scopeID
            $null = $item.SubItems.Add($name)
            $null = $item.SubItems.Add($range)
            [void]$listCreateScopes.Items.Add($item)
        }

        Set-Status "$($script:AllScopes.Count) scope(s) loaded."
        Write-Log "Loaded $($script:AllScopes.Count) scope(s) from $($sel.DisplayName)" "SUCCESS"
    } catch {
        Set-Status "Error loading scopes."
        Write-Log "Load-CreateScopes error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to load scopes:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
}

# --- Manual DHCP server entry (debounced) ---
$debounceTimer = New-Object System.Windows.Forms.Timer
$debounceTimer.Interval = 350
$debounceTimer.Add_Tick({
    $debounceTimer.Stop()

    $text = if ($null -ne $comboServer.Text) { $comboServer.Text.Trim() } else { '' }
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    # If already present, select it
    $existing = $script:DhcpServers | Where-Object { $_.DisplayName -eq $text -or $_.IP -eq $text -or $_.Name -eq $text }
    if ($existing) { $comboServer.SelectedItem = $existing.DisplayName; return }

    try {
        # Resolve to IPv4
        $resolvedIP = if (Test-IPAddress $text) {
            $text
        } else {
            ([Net.Dns]::GetHostEntry($text).AddressList |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                Select-Object -First 1).ToString()
        }

        if (-not $resolvedIP) {
            Set-Status "Could not resolve server."
            Write-Log "Manual add failed: could not resolve '$text'." "WARN"
            return
        }

        if (-not (Test-HostReachable -ComputerNameOrIP $resolvedIP)) {
            Set-Status "Host unreachable: $resolvedIP"
            Write-Log "Manual add failed: host unreachable '$resolvedIP'." "ERROR"
            return
        }

        $resolvedName = try { ([Net.Dns]::GetHostEntry($resolvedIP).HostName.Split('.')[0]) } catch { "DHCP-$($resolvedIP -replace '\.','-')" }

        $obj = [PSCustomObject]@{
            ID          = $script:DhcpServers.Count + 1
            IP          = $resolvedIP
            Name        = $resolvedName
            DisplayName = "$resolvedName ($resolvedIP)"
        }

        $script:DhcpServers += $obj
        $comboServer.Items.Add($obj.DisplayName) | Out-Null
        $comboServer.SelectedItem = $obj.DisplayName

        Set-Status "Server added: $($obj.DisplayName)"
        Write-Log "Manually added DHCP server: $($obj.DisplayName)" "SUCCESS"

    } catch {
        Set-Status "Error adding server."
        Write-Log "Manual server add error for '$text': $($_.Exception.Message)" "ERROR"
    }
})

$comboServer.Add_SelectedIndexChanged({
    # Resolve selected server object (store globally)
    $script:SelectedDhcpServer = $script:DhcpServers | Where-Object {
        $_.DisplayName -eq $comboServer.SelectedItem
    } | Select-Object -First 1

    # Build a safe server name for the report filename
    $safeServer = 'UNKNOWN_SERVER'

    if ($script:SelectedDhcpServer -and $script:SelectedDhcpServer.Name) {
        $safeServer = ($script:SelectedDhcpServer.Name -replace '[\\/:*?"<>| ]','_')
    } elseif (-not [string]::IsNullOrWhiteSpace($comboServer.Text)) {
        $safeServer = (($comboServer.Text.Trim()) -replace '[\\/:*?"<>| ]','_')
    }

    $script:reportPath = Join-Path $logDir "DHCP_DuplicateReservations_Report_$safeServer.txt"
    Write-Log "Report path updated to: $script:reportPath" "INFO"

    # Keep existing behavior
    if ($comboMode.SelectedItem -eq 'Create Reservation') {
        Load-CreateScopes
    }
})

# --- DHCP data helpers ---
function Get-AvailableIPs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]${DhcpServer},
        [Parameter(Mandatory=$true)][ipaddress]${ScopeId},
        [Parameter(Mandatory=$false)][int]${MaxResults} = 500
    )

    try {
        # Pull scope definition
        ${scope} = Get-DhcpServerv4Scope -ComputerName ${DhcpServer} -ScopeId ${ScopeId} -ErrorAction Stop
        if (-not ${scope}) { return @() }

        # Build the "outside pool" candidate range:
        # - Start at x.x.x.11
        # - End at one IP before StartRange (pool start)
        ${startIpStr} = [string]${scope}.StartRange
        ${startOctets} = (${startIpStr}.Split('.'))[0..2] -join '.'
        ${firstAvailableIpStr} = "${startOctets}.11"

        ${poolStartInt} = Convert-IpToUInt32 -ip ${startIpStr}
        ${firstInt}     = Convert-IpToUInt32 -ip ${firstAvailableIpStr}

        if (${null} -eq ${poolStartInt} -or ${null} -eq ${firstInt}) { return @() }

        ${endInt} = ${poolStartInt} - 1
        if (${firstInt} -gt ${endInt}) { return @() }

        # Gather used IPs (leases + reservations) as strings for reliable comparisons
        ${leaseIps} = @(
            Get-DhcpServerv4Lease -ComputerName ${DhcpServer} -ScopeId ${ScopeId} -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.IPAddress }
        )

        ${reservationIps} = @(
            Get-DhcpServerv4Reservation -ComputerName ${DhcpServer} -ScopeId ${ScopeId} -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.IPAddress }
        )

        ${usedSet} = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach (${ip} in @(${leaseIps} + ${reservationIps})) {
            if (-not [string]::IsNullOrWhiteSpace(${ip})) { [void]${usedSet}.Add(${ip}) }
        }

        # Generate candidates (bounded)
        ${available} = New-Object 'System.Collections.Generic.List[string]'
        ${added} = 0

        for (${i} = ${firstInt}; ${i} -le ${endInt}; ${i}++) {
            ${candidate} = Convert-UInt32ToIp -int ${i}
            if ([string]::IsNullOrWhiteSpace(${candidate})) { continue }

            if (-not ${usedSet}.Contains(${candidate})) {
                [void]${available}.Add(${candidate})
                ${added}++
                if (${added} -ge ${MaxResults}) { break }
            }
        }

        return $available.ToArray()
    }
    catch {
        throw
    }
}



function Find-DuplicateMACAcrossServer {
    param(
        [Parameter(Mandatory)][string]$Mac12,
        [Parameter(Mandatory)][string]$DhcpServerIP
    )

    $norm = (Normalize-MAC $Mac12)
    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $DhcpServerIP -ErrorAction Stop
        foreach ($sc in $scopes) {
            $sid = $sc.ScopeId.ToString()
            $res = Get-DhcpServerv4Reservation -ComputerName $DhcpServerIP -ScopeId $sid -ErrorAction SilentlyContinue
            foreach ($r in ($res | Where-Object { $_ })) {
                $existing = (Normalize-MAC $r.ClientId)
                if ($existing -eq $norm) {
                    return [PSCustomObject]@{
                        Found  = $true
                        IP     = $r.IPAddress.ToString()
                        Scope  = $sid
                        Server = $DhcpServerIP
                    }
                }
            }
        }
        return [PSCustomObject]@{ Found = $false }
    } catch {
        return [PSCustomObject]@{ Found = $false; Error = $_.Exception.Message }
    }
}

function Find-DuplicateIPAcrossServer {
    param(
        [Parameter(Mandatory)][string]$IPAddress,
        [Parameter(Mandatory)][string]$DhcpServerIP
    )

    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $DhcpServerIP -ErrorAction Stop
        foreach ($sc in $scopes) {
            $sid = $sc.ScopeId.ToString()
            $res = Get-DhcpServerv4Reservation -ComputerName $DhcpServerIP -ScopeId $sid -ErrorAction SilentlyContinue
            foreach ($r in ($res | Where-Object { $_ })) {
                if ($r.IPAddress.ToString() -eq $IPAddress) {
                    $mac12 = Normalize-MAC $r.ClientId
                    return [PSCustomObject]@{
                        Found  = $true
                        MAC    = (Format-MAC $mac12)
                        Scope  = $sid
                        Server = $DhcpServerIP
                    }
                }
            }
        }
        return [PSCustomObject]@{ Found = $false }
    } catch {
        return [PSCustomObject]@{ Found = $false; Error = $_.Exception.Message }
    }
}

# --- Scan flow ---
function Update-ReservationList {
    $listReservations.BeginUpdate()
    try {
        $listReservations.Items.Clear()

        foreach ($r in $script:AllReservations) {
            $it = New-Object System.Windows.Forms.ListViewItem $r.IP
            $null = $it.SubItems.Add($r.MAC)
            $null = $it.SubItems.Add($r.Hostname)
            $null = $it.SubItems.Add($r.Scope)
            $null = $it.SubItems.Add($r.Server)
            $it.Tag = $r.UniqueID

            if ($script:CheckedResSet.Contains($r.UniqueID)) { $it.Checked = $true }
            [void]$listReservations.Items.Add($it)
        }

        Set-Status "$($script:AllReservations.Count) reservation(s) found ($($script:CheckedResSet.Count) selected)."
        Write-Log "Displayed $($script:AllReservations.Count) reservation(s)." "INFO"
    } finally {
        $listReservations.EndUpdate()
    }
}

function Write-Report {
    try {
        $all = @($script:AllReservations)

        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("DHCP Duplicate Reservations Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        [void]$sb.AppendLine("==================================================")
        [void]$sb.AppendLine("Server: $($comboServer.SelectedItem)")
        [void]$sb.AppendLine("Total reservations collected: $($all.Count)")
        [void]$sb.AppendLine("")

        if ($all.Count -eq 0) {
            [void]$sb.AppendLine("No reservations were collected in this scan.")
            [void]$sb.AppendLine("")
            Set-Content -Path $script:reportPath -Value $sb.ToString() -Encoding UTF8
            Write-Log "Report generated: $script:reportPath" "SUCCESS"
            return
        }

        # Force arrays so Count is always safe
        $dupMACs = @($all | Group-Object MAC | Where-Object { $_.Count -gt 1 })
        $dupIPs  = @($all | Group-Object IP  | Where-Object { $_.Count -gt 1 })

        [void]$sb.AppendLine("Duplicate MAC groups: $($dupMACs.Count)")
        [void]$sb.AppendLine("Duplicate IP groups : $($dupIPs.Count)")
        [void]$sb.AppendLine("")

        if (($dupMACs.Count + $dupIPs.Count) -eq 0) {
            [void]$sb.AppendLine("No duplicate MAC or IP addresses found.")
            [void]$sb.AppendLine("")
        } else {

            if ($dupMACs.Count -gt 0) {
                [void]$sb.AppendLine("=== DUPLICATE MAC ADDRESSES ===")
                foreach ($g in $dupMACs) {
                    [void]$sb.AppendLine("MAC: $($g.Name) (Count: $($g.Count))")
                    foreach ($r in $g.Group) {
                        [void]$sb.AppendLine("  IP: $($r.IP) | Hostname: $($r.Hostname) | Scope: $($r.Scope) | Server: $($r.Server)")
                    }
                    [void]$sb.AppendLine("")
                }
            }

            if ($dupIPs.Count -gt 0) {
                [void]$sb.AppendLine("=== DUPLICATE IP ADDRESSES ===")
                foreach ($g in $dupIPs) {
                    [void]$sb.AppendLine("IP: $($g.Name) (Count: $($g.Count))")
                    foreach ($r in $g.Group) {
                        [void]$sb.AppendLine("  MAC: $($r.MAC) | Hostname: $($r.Hostname) | Scope: $($r.Scope) | Server: $($r.Server)")
                    }
                    [void]$sb.AppendLine("")
                }
            }
        }

        Set-Content -Path $reportPath -Value $sb.ToString() -Encoding UTF8
        Write-Log "Report generated: $reportPath" "SUCCESS"
    } catch {
        Write-Log "Report generation error: $($_.Exception.Message)" "ERROR"
    }
}

function Scan-Reservations {
    $listReservations.Items.Clear()
    $script:AllReservations = @()
    $script:CheckedResSet.Clear()

    try {
        $sel = $script:DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
        if (-not $sel) {
            Set-Status "No DHCP server selected."
            Write-Log "Scan aborted: no server selected." "WARN"
            return
        }

        Set-Status "Scanning reservations on $($sel.DisplayName)..."
        Write-Log "Scanning reservations on $($sel.DisplayName)..." "INFO"

        $scopes = Get-DhcpServerv4Scope -ComputerName $sel.IP -ErrorAction Stop
        $script:progress.Value = 0
        $script:progress.Maximum = [Math]::Max(1, $scopes.Count)

        foreach ($sc in $scopes) {
            $scopeID = $sc.ScopeId.ToString()
            try {
                $res = Get-DhcpServerv4Reservation -ComputerName $sel.IP -ScopeId $scopeID -ErrorAction SilentlyContinue
                foreach ($r in ($res | Where-Object { $_ })) {
                    $ip  = $r.IPAddress.ToString()
                    $mac12 = Normalize-MAC $r.ClientId
                    $macFmt = Format-MAC $mac12
                    $hostName = Resolve-Hostname -IPAddress $ip

                    $script:AllReservations += [PSCustomObject]@{
                        IP       = $ip
                        MAC      = $macFmt
                        Hostname = $hostName
                        Scope    = $scopeID
                        Server   = $sel.DisplayName
                        UniqueID = "$ip-$mac12-$scopeID"
                    }
                }
            } catch {
                Write-Log "Scope scan error (Scope=$scopeID Server=$($sel.DisplayName)): $($_.Exception.Message)" "ERROR"
            }

            $script:progress.Value = [Math]::Min($script:progress.Value + 1, $script:progress.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }

        Update-ReservationList
        Write-Report

        Set-Status "$($script:AllReservations.Count) reservation(s) found."
        Write-Log "Scan completed: $($script:AllReservations.Count) reservation(s) on $($sel.DisplayName)" "SUCCESS"

        # Notify report path only after generation
        Show-MessageBox -Message "Scan completed.`nReport generated at:`n$script:reportPath" -Title "Success" -Icon Information

    } catch {
        Set-Status "Error scanning reservations."
        Write-Log "Scan error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to scan reservations:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
}

# --- Select All checkbox ---
$chkSelectAll.Add_CheckedChanged({
    $listReservations.BeginUpdate()
    try {
        foreach ($item in $listReservations.Items) {
            $item.Checked = $chkSelectAll.Checked
            if ($chkSelectAll.Checked) { $null = $script:CheckedResSet.Add([string]$item.Tag) }
            else { $null = $script:CheckedResSet.Remove([string]$item.Tag) }
        }
        Set-Status "$($listReservations.Items.Count) reservation(s) found ($($script:CheckedResSet.Count) selected)."
        Write-Log "Select All set to: $($chkSelectAll.Checked)" "INFO"
    } finally {
        $listReservations.EndUpdate()
    }
})

$listReservations.Add_ItemChecked({
    param($sender,$e)
    if ($null -eq $e.Item) { return }
    try {
        $tag = [string]$e.Item.Tag
        if ($e.Item.Checked) { $null = $script:CheckedResSet.Add($tag) }
        else { $null = $script:CheckedResSet.Remove($tag) }
        Set-Status "$($listReservations.Items.Count) reservation(s) found ($($script:CheckedResSet.Count) selected)."
    } catch {
        Set-Status "Selection update error."
        Write-Log "ItemChecked error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to update selection:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
})

# --- Browse output folder for CSV ---
$btnBrowse.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text = $fbd.SelectedPath
        Write-Log "Output folder set: $($fbd.SelectedPath)" "INFO"
    }
})

# --- Mode switching ---
$comboMode.Add_SelectedIndexChanged({
    if ($comboMode.SelectedItem -eq 'Create Reservation') {
        $panelCreate.Visible = $true
        $panelScan.Visible   = $false
        $btnAction.Text      = 'Add Reservation'
        $btnExport.Visible   = $false
        Set-Status "Ready"
        Write-Log "Mode selected: Create Reservation" "INFO"
        if ($comboServer.SelectedItem) { Load-CreateScopes }
    } else {
        $panelCreate.Visible = $false
        $panelScan.Visible   = $true
        $btnAction.Text      = 'Scan Reservations'
        $btnExport.Visible   = $true
        $listReservations.Items.Clear()
        $script:CheckedResSet.Clear()
        Set-Status "Ready"
        Write-Log "Mode selected: Scan Duplicates" "INFO"
    }
})

$comboDomain.Add_SelectedIndexChanged({
    $safeDomain = ([string]$comboDomain.SelectedItem) -replace '[\\/:*?"<>| ]','_'

    if ([string]::IsNullOrWhiteSpace($safeDomain)) {
        $safeDomain = 'UNKNOWN_DOMAIN'
    }

    $script:reportPath = Join-Path $logDir "DHCP_DuplicateReservations_Report_$safeDomain.txt"
    Write-Log "Report path updated to: $script:reportPath" "INFO"

    Discover-DHCPServers
})

# --- Create: when scope selected, load available IPs ---
$listCreateScopes.Add_SelectedIndexChanged({
    $comboBoxIPs.Items.Clear()

    if ($listCreateScopes.SelectedItems.Count -eq 0) {
        Set-Status "No scope selected."
        Write-Log "IP load skipped: no scope selected." "WARN"
        return
    }

    $scopeID = $listCreateScopes.SelectedItems[0].Text
    $sel     = $script:DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
    if (-not $sel) {
        Set-Status "No DHCP server selected."
        Write-Log "IP load skipped: no server selected." "WARN"
        return
    }

    try {
        Set-Status "Loading available IPs..."
        Write-Log "Loading available IPs (Scope=$scopeID Server=$($sel.DisplayName))..." "INFO"

        $ips = @(
            Get-AvailableIPs -ScopeID $scopeID -DhcpServer $sel.IP -MaxResults 512
        )

        $comboBoxIPs.Items.Clear()

        if (@($ips).Count -le 0) {
            [void]$comboBoxIPs.Items.Add("[No available IPs found]")
            $comboBoxIPs.SelectedIndex = 0
            $comboBoxIPs.Enabled = $false
            $script:progress.Value = 0
            $script:progress.Maximum = 1
        } else {
            $comboBoxIPs.Enabled = $true
            [void]$comboBoxIPs.Items.Add("[Select an available IP]")
            $comboBoxIPs.Items.AddRange([object[]]@($ips))
            $comboBoxIPs.SelectedIndex = 0

            $script:progress.Value = 0
            $script:progress.Maximum = [Math]::Max(1, @($ips).Count)
            $script:progress.Value = $script:progress.Maximum
        }

        Set-Status "$($ips.Count) available IP(s) loaded."
        Write-Log "Available IPs loaded: $($ips.Count) (Scope=$scopeID)" "SUCCESS"
    } catch {
        Set-Status "Error loading available IPs."
        Write-Log "Available IPs load error (Scope=$scopeID): $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to load IPs:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
})

# --- Action button (Create or Scan) ---
$btnAction.Add_Click({
    try {
        if ($comboMode.SelectedItem -ne 'Create Reservation') {
            Scan-Reservations
            return
        }

        # -------------------------
        # 1) Collect UI inputs first
        # -------------------------
        $scopeID = if ($listCreateScopes.SelectedItems.Count -gt 0) { [string]$listCreateScopes.SelectedItems[0].Text } else { $null }
        $ipSel   = if ($comboBoxIPs.SelectedItem) { [string]$comboBoxIPs.SelectedItem } else { '' }
        $name    = if ($txtName.Text) { $txtName.Text.Trim() } else { '' }
        $macRaw  = if ($txtMAC.Text)  { $txtMAC.Text.Trim()  } else { '' }
        $desc    = if ($txtDesc.Text) { $txtDesc.Text.Trim() } else { '' }

        # Selected reservation type (default DHCP)
        $typeSel = if ($comboResType.SelectedItem) { [string]$comboResType.SelectedItem } else { 'DHCP' }
        $dhcpResType = switch ($typeSel.ToUpperInvariant()) {
            'BOOTP' { 'Bootp' }
            'BOTH'  { 'Both'  }
            default { 'Dhcp'  }
        }

        # -------------------------
        # 2) Resolve selected server safely (StrictMode-safe)
        # -------------------------
        $selServer = $script:SelectedDhcpServer
        if (-not $selServer) {
            $selServer = $script:DhcpServers |
                Where-Object { $_.DisplayName -eq $comboServer.SelectedItem } |
                Select-Object -First 1
        }

        if (-not $selServer) {
            Show-MessageBox -Message "Select a DHCP server first." -Title "Warning" -Icon Warning
            Write-Log "Create aborted: no DHCP server selected." "WARN"
            return
        }

        # -------------------------
        # 3) Validate inputs (no exceptions)
        # -------------------------
        if ([string]::IsNullOrWhiteSpace($scopeID)) {
            Show-MessageBox -Message "Select a scope first." -Title "Warning" -Icon Warning
            Write-Log "Create aborted: no scope selected." "WARN"
            return
        }

        if ([string]::IsNullOrWhiteSpace($ipSel) -or -not (Test-IPAddress $ipSel)) {
            Show-MessageBox -Message "Select a valid available IP." -Title "Warning" -Icon Warning
            Write-Log "Create aborted: invalid/missing IP selection." "WARN"
            return
        }

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($desc)) {
            Show-MessageBox -Message "Please fill Name and Description." -Title "Warning" -Icon Warning
            Write-Log "Create aborted: missing Name/Description." "WARN"
            return
        }

        if (-not (Test-MACAddress $macRaw)) {
            Show-MessageBox -Message "Invalid MAC address. Use 12 hex digits (example: D8BBC1830F62) or common formats (AA:BB:CC:DD:EE:FF)." -Title "Error" -Icon Error
            Write-Log "Create aborted: invalid MAC input '$macRaw'." "ERROR"
            return
        }

        $mac12 = Normalize-MAC $macRaw

        # -------------------------
        # 4) Duplicate checks (protected)
        # -------------------------
        Set-Status "Checking duplicates..."
        Write-Log "Duplicate check started (Server=$($selServer.DisplayName) Scope=$scopeID IP=$ipSel MAC=$mac12 Type=$typeSel)..." "INFO"

        $dupMac = Find-DuplicateMACAcrossServer -Mac12 $mac12 -DhcpServerIP $selServer.IP
        $dupMacErr = if ($dupMac -and ($dupMac.PSObject.Properties.Name -contains 'Error')) { [string]$dupMac.Error } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($dupMacErr)) {
            Show-MessageBox -Message "Error checking MAC duplicates:`n$dupMacErr" -Title "Error" -Icon Error
            Write-Log "Duplicate MAC check error: $dupMacErr" "ERROR"
            Set-Status "Duplicate check error."
            return
        }
        if ($dupMac -and $dupMac.Found) {
            $msg = "Duplicate MAC detected on server $($selServer.DisplayName):`nMAC: $(Format-MAC $mac12)`nExisting IP: $($dupMac.IP)`nScope: $($dupMac.Scope)"
            Show-MessageBox -Message $msg -Title "Warning" -Icon Warning
            Write-Log $msg "WARN"
            Set-Status "Duplicate MAC detected."
            return
        }

        $dupIP = Find-DuplicateIPAcrossServer -IPAddress $ipSel -DhcpServerIP $selServer.IP
        $dupIPErr = if ($dupIP -and ($dupIP.PSObject.Properties.Name -contains 'Error')) { [string]$dupIP.Error } else { $null }
        if (-not [string]::IsNullOrWhiteSpace($dupIPErr)) {
            Show-MessageBox -Message "Error checking IP duplicates:`n$dupIPErr" -Title "Error" -Icon Error
            Write-Log "Duplicate IP check error: $dupIPErr" "ERROR"
            Set-Status "Duplicate check error."
            return
        }
        if ($dupIP -and $dupIP.Found) {
            $msg = "Duplicate IP detected on server $($selServer.DisplayName):`nIP: $ipSel`nExisting MAC: $($dupIP.MAC)`nScope: $($dupIP.Scope)"
            Show-MessageBox -Message $msg -Title "Warning" -Icon Warning
            Write-Log $msg "WARN"
            Set-Status "Duplicate IP detected."
            return
        }

        # -------------------------
        # 5) Add reservation (single call, inside try)
        # -------------------------
        Set-Status "Adding reservation..."
        Add-DhcpServerv4Reservation `
            -ComputerName $selServer.IP `
            -ScopeId $scopeID `
            -IPAddress $ipSel `
            -ClientId $mac12 `
            -Name $name `
            -Description $desc `
            -Type $dhcpResType `
            -ErrorAction Stop

        $msgOk = "Reservation added successfully:`nServer: $($selServer.DisplayName)`nScope: $scopeID`nIP: $ipSel`nMAC: $(Format-MAC $mac12)`nType: $typeSel"
        Show-MessageBox -Message $msgOk -Title "Success" -Icon Information

        Write-Log "Reservation added: Server=$($selServer.DisplayName) Scope=$scopeID IP=$ipSel MAC=$mac12 Type=$typeSel Name='$name' Desc='$desc'" "SUCCESS"
        Set-Status "Reservation added."

        # cleanup UI
        $txtName.Clear()
        $txtMAC.Clear()
        $txtDesc.Clear()
        if ($comboBoxIPs.Items.Contains($ipSel)) { $null = $comboBoxIPs.Items.Remove($ipSel) }

    } catch {
        # This catch is the "JIT killer" for any unexpected runtime exception in the click handler
        Set-Status "Unexpected error."
        Write-Log "JIT-guard caught error in Create handler: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Unexpected error while creating reservation:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
})

# --- CSV export ---
$btnExport.Add_Click({
    if ($script:CheckedResSet.Count -eq 0) {
        Show-MessageBox -Message "Select at least one reservation to export." -Title "Warning" -Icon Warning
        Write-Log "Export aborted: no selection." "WARN"
        return
    }

    $outDir = $txtOutput.Text
    if (-not (Test-Path $outDir)) {
        Show-MessageBox -Message "Output folder does not exist." -Title "Error" -Icon Error
        Write-Log "Export aborted: invalid folder '$outDir'." "ERROR"
        return
    }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $csvPath = Join-Path $outDir "DHCP_Reservations_$ts.csv"

    try {
        $data = foreach ($uid in $script:CheckedResSet) {
            $script:AllReservations | Where-Object { $_.UniqueID -eq $uid }
        }

        if ($data -and $data.Count -gt 0) {
            $data |
                Select-Object IP,MAC,Hostname,Scope,Server |
                Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

            Write-Log "Exported $($data.Count) reservation(s) to $csvPath" "SUCCESS"
            Set-Status "Exported $($data.Count) reservation(s)."

            Show-MessageBox -Message "Export completed.`nFile:`n$csvPath" -Title "Success" -Icon Information
            try { Start-Process $csvPath } catch {}

        } else {
            Write-Log "Export skipped: no rows resolved from selection set." "WARN"
            Set-Status "Nothing exported."
            Show-MessageBox -Message "No reservations selected for export." -Title "Information" -Icon Information
        }
    } catch {
        Set-Status "CSV export error."
        Write-Log "Export error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox -Message "Failed to export CSV:`n$($_.Exception.Message)" -Title "Error" -Icon Error
    }
})

# --- Form lifecycle ---
$form.Add_Load({
    Write-Log "Form loaded: $($form.ClientSize.Width)x$($form.ClientSize.Height)" "INFO"
    Discover-DHCPServers
})

$form.Add_Shown({
    $form.Activate()
    Write-Log "Form shown. Current mode: $($comboMode.SelectedItem)" "INFO"
})

$form.Add_FormClosing({
    Write-Log "==== Session ended ====" "INFO"
})

# --- Show GUI ---
[void]$form.ShowDialog()
Write-Log "Script finished." "SUCCESS"

# --- End of Script
