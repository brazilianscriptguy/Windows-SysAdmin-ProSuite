<#
.SYNOPSIS
    PowerShell GUI for DHCP Reservation Creation and Duplicate Scanning

.DESCRIPTION
    - Create new DHCP reservations (with MAC/IP validation and duplicate checks)
    - Scan for duplicate MAC/IP across scopes on a selected DHCP server
    - Automatic AD-based server discovery (or manual add by IP/hostname)
    - Live log pane, progress bar, CSV export, and text report for duplicates
    - Layout fixes: 900x830 window, non-overlapping controls, proper labels
    - Robustness fixes and usability improvements throughout

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: September 30, 2025.
#>

# --- Hide Console (comment for debugging) ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
}
"@
[Window]::Hide()

# --- Load WinForms assemblies ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Import Required Modules ---
try {
    Import-Module DHCPServer -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load DHCPServer module:`n$($_.Exception.Message)", "Error", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show("Failed to load ActiveDirectory module:`n$($_.Exception.Message)", "Error", [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

# --- Logging setup ---
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\Logs-TEMP"
$logPath = Join-Path $logDir "${scriptName}.log"
$reportPath = Join-Path $logDir "DHCP_DuplicateReservations_Report.txt"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
if (Test-Path $logPath) { Remove-Item $logPath   -Force }
if (Test-Path $reportPath) { Remove-Item $reportPath -Force }

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "ERROR", "WARNING", "SUCCESS")]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    try {
        if ($logBox) {
            $logBox.SelectionStart = $logBox.TextLength
            $logBox.SelectionColor = switch ($Level) {
                "ERROR" { 'Red' }
                "WARNING" { 'DarkOrange' }
                "SUCCESS" { 'Green' }
                default { 'Black' }
            }
            $logBox.AppendText("${entry}`r`n")
            $logBox.ScrollToCaret()
        }
        $entry | Out-File -FilePath $logPath -Append -Encoding UTF8
    } catch { Write-Error "Log error: $_" }
}

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title = "Message",
        [Windows.Forms.MessageBoxIcon]$Icon = [Windows.Forms.MessageBoxIcon]::Information
    )
    [Windows.Forms.MessageBox]::Show($Message, $Title, [Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

# --- Admin privileges check ---
function Test-AdminPrivileges {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $false }
}
if (-not (Test-AdminPrivileges)) {
    Show-MessageBox "This script requires administrative privileges. Please run as Administrator." "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    Write-Log "Script requires administrative privileges" "ERROR"
    exit 1
}

# --- Validation helpers ---
function Validate-MACAddress { param([string]$macAddress) return ($macAddress -match '^[A-Fa-f0-9]{12}$') }
function Test-IPAddress { param([string]$IP) try { [Net.IPAddress]::Parse($IP) | Out-Null; $true } catch { $false } }

function Convert-IpToUInt32 {
    param([string]$ip)
    try {
        $bytes = [Net.IPAddress]::Parse($ip).GetAddressBytes()
        [Array]::Reverse($bytes); [BitConverter]::ToUInt32($bytes, 0)
    } catch { Write-Log "Invalid IP address format: ${ip}" "ERROR"; $null }
}
function Convert-UInt32ToIp {
    param([UInt32]$int)
    try {
        $bytes = [BitConverter]::GetBytes($int); [Array]::Reverse($bytes); ([Net.IPAddress]::new($bytes)).ToString()
    } catch { Write-Log "Failed to convert integer to IP: ${int}" "ERROR"; $null }
}

function Resolve-Hostname {
    param([string]$IPAddress)
    try {
        $dns = [Net.Dns]::GetHostEntry($IPAddress)
        if ($dns -and $dns.HostName) { return $dns.HostName.Split('.')[0] }
    } catch {
        try {
            $ns = & nslookup $IPAddress 2>&1
            foreach ($line in $ns) { if ($line -match "Name:\s*(.+)") { return $matches[1].Trim().Split('.')[0] } }
        } catch { Write-Log "Reverse lookup failed for ${IPAddress}" "WARNING" }
    }
    "Host-$($IPAddress -replace '\.','-')"
}

# --- Global collections ---
$script:AllScopes = @()
$script:AllReservations = @()
$script:DhcpServers = @()
$script:CheckedResSet = New-Object 'System.Collections.Generic.HashSet[string]'

# --- GUI Form ---
$form = New-Object Windows.Forms.Form -Property @{
    Text = "DHCP Reservation & Duplicate Scanner"
    Size = '900,830'
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox = $false
    Font = New-Object Drawing.Font("Segoe UI", 9)
}

# Mode panel
$panelMode = New-Object Windows.Forms.Panel -Property @{ Location = '10,10'; Size = '860,40'; BorderStyle = 'FixedSingle' }
$lblMode = New-Object Windows.Forms.Label -Property @{ Text = "Select Mode:"; Location = '10,10'; Size = '100,20' }
$comboMode = New-Object Windows.Forms.ComboBox -Property @{ Location = '110,8'; Size = '740,24'; DropDownStyle = 'DropDownList' }
$comboMode.Items.AddRange(@("Create Reservation", "Scan Duplicates")); $comboMode.SelectedIndex = 0
$panelMode.Controls.AddRange(@($lblMode, $comboMode)); $form.Controls.Add($panelMode)

# Domain/Server panel
$panelServer = New-Object Windows.Forms.Panel -Property @{ Location = '10,50'; Size = '860,90'; BorderStyle = 'FixedSingle' }
$lblDomain = New-Object Windows.Forms.Label -Property @{ Text = "Select Domain:"; Location = '10,10'; Size = '200,20' }
$comboDomain = New-Object Windows.Forms.ComboBox -Property @{ Location = '10,30'; Size = '830,24'; DropDownStyle = 'DropDownList' }

# FIXED label + combo alignment
$lblServer = New-Object Windows.Forms.Label -Property @{ 
    Text = "Select DHCP Server (or type IP/host):"; 
    Location = '10,58'; 
    Size = '250,20' 
}
$comboServer = New-Object Windows.Forms.ComboBox -Property @{ 
    Location = '270,56'; 
    Size = '570,24'; 
    DropDownStyle = 'DropDown' 
}

$panelServer.Controls.AddRange(@($lblDomain, $comboDomain, $lblServer, $comboServer))
$form.Controls.Add($panelServer)


# Create panel
$panelCreate = New-Object Windows.Forms.Panel -Property @{ Location = '10,150'; Size = '860,420'; BorderStyle = 'FixedSingle'; Visible = $true }
$lblCreateScopes = New-Object Windows.Forms.Label -Property @{ Text = "Select Scope:"; Location = '10,10'; Size = '200,20' }
$listCreateScopes = New-Object Windows.Forms.ListView -Property @{ Location = '10,30'; Size = '830,260'; View = 'Details'; CheckBoxes = $false; FullRowSelect = $true }
[void]$listCreateScopes.Columns.Add("Scope ID", 120)
[void]$listCreateScopes.Columns.Add("Name", 250)
[void]$listCreateScopes.Columns.Add("Range", 350)
$lblIP = New-Object Windows.Forms.Label -Property @{ Text = "Select Available IP:"; Location = '10,300'; Size = '140,20' }
$comboBoxIPs = New-Object Windows.Forms.ComboBox -Property @{ Location = '150,298'; Size = '690,24'; DropDownStyle = 'DropDownList' }
$lblName = New-Object Windows.Forms.Label -Property @{ Text = "Reservation Name:"; Location = '10,330'; Size = '140,20' }
$txtName = New-Object Windows.Forms.TextBox -Property @{ Location = '150,328'; Size = '690,24' }
$lblMAC = New-Object Windows.Forms.Label -Property @{ Text = "MAC Address (D8BBC1830F62):"; Location = '10,360'; Size = '200,20' }
$txtMAC = New-Object Windows.Forms.TextBox -Property @{ Location = '210,358'; Size = '630,24' }
$lblDesc = New-Object Windows.Forms.Label -Property @{ Text = "Description:"; Location = '10,390'; Size = '140,20' }
$txtDesc = New-Object Windows.Forms.TextBox -Property @{ Location = '150,388'; Size = '690,24' }
$panelCreate.Controls.AddRange(@($lblCreateScopes, $listCreateScopes, $lblIP, $comboBoxIPs, $lblName, $txtName, $lblMAC, $txtMAC, $lblDesc, $txtDesc))
$form.Controls.Add($panelCreate)

# Scan panel
$panelScan = New-Object Windows.Forms.Panel -Property @{ Location = '10,150'; Size = '860,420'; BorderStyle = 'FixedSingle'; Visible = $false }
$lblReservations = New-Object Windows.Forms.Label -Property @{ Text = "Reservations:"; Location = '10,10'; Size = '200,20' }
$chkSelectAll = New-Object Windows.Forms.CheckBox -Property @{ Text = "Select All"; Location = '760,10'; Size = '90,20' }
$listReservations = New-Object Windows.Forms.ListView -Property @{ Location = '10,30'; Size = '830,320'; View = 'Details'; CheckBoxes = $true; FullRowSelect = $true }
[void]$listReservations.Columns.Add("IP", 140)
[void]$listReservations.Columns.Add("MAC", 160)
[void]$listReservations.Columns.Add("Hostname", 200)
[void]$listReservations.Columns.Add("Scope", 120)
[void]$listReservations.Columns.Add("Server", 180)
$lblOutput = New-Object Windows.Forms.Label -Property @{ Text = "Output Folder:"; Location = '10,360'; Size = '140,20' }
$txtOutput = New-Object Windows.Forms.TextBox -Property @{ Location = '150,358'; Size = '620,24'; Text = [Environment]::GetFolderPath("MyDocuments") }
$btnBrowse = New-Object Windows.Forms.Button -Property @{ Text = "Browse"; Location = '780,357'; Size = '60,26' }
$panelScan.Controls.AddRange(@($lblReservations, $chkSelectAll, $listReservations, $lblOutput, $txtOutput, $btnBrowse))
$form.Controls.Add($panelScan)

# Log panel
$panelLog = New-Object Windows.Forms.Panel -Property @{ Location = '10,575'; Size = '860,120'; BorderStyle = 'FixedSingle' }
$lblLog = New-Object Windows.Forms.Label -Property @{ Text = "Log:"; Location = '10,10'; Size = '200,20' }
$logBox = New-Object Windows.Forms.RichTextBox -Property @{ Location = '10,30'; Size = '830,80'; ReadOnly = $true; ScrollBars = 'Vertical' }
$panelLog.Controls.AddRange(@($lblLog, $logBox)); $form.Controls.Add($panelLog)

# Footer controls
$progress = New-Object Windows.Forms.ProgressBar -Property @{ Location = '10,700'; Size = '860,15'; Minimum = 0; Maximum = 100; Value = 0 }
$lblStatus = New-Object Windows.Forms.Label -Property @{ Text = "Ready"; Location = '10,720'; Size = '860,20' }
$btnAction = New-Object Windows.Forms.Button -Property @{ Text = "Add Reservation"; Location = '10,745'; Size = '140,30' }
$btnExport = New-Object Windows.Forms.Button -Property @{ Text = "Export CSV"; Location = '160,745'; Size = '120,30'; Visible = $false }
$btnClose = New-Object Windows.Forms.Button -Property @{ Text = "Close"; Location = '290,745'; Size = '120,30' }
$btnClose.Add_Click({ $form.Close() })
$form.Controls.AddRange(@($progress, $lblStatus, $btnAction, $btnExport, $btnClose))

# --- Domain discovery ---
try {
    Write-Log "Retrieving forest domains" "INFO"
    $domains = Get-ADForest -ErrorAction Stop | Select-Object -ExpandProperty Domains
    if ($domains -and $domains.Count -gt 0) {
        $comboDomain.Items.AddRange($domains)
        $comboDomain.SelectedIndex = 0
    } else {
        Write-Log "No domains found in the forest" "ERROR"
        Show-MessageBox "No domains found in the forest." "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
} catch {
    Write-Log "Failed to retrieve forest domains: $($_.Exception.Message)" "ERROR"
    Show-MessageBox "Failed to retrieve forest domains:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
}

# --- DHCP server discovery (AD) ---
function Discover-DHCPServers {
    $comboServer.Items.Clear()
    $script:DhcpServers = @()
    try {
        $selDomain = $comboDomain.SelectedItem
        if (-not $selDomain) {
            $lblStatus.Text = "Select a domain first."
            Write-Log "Discover-DHCPServers aborted: no domain selected" "WARNING"
            return
        }
        $lblStatus.Text = "Discovering DHCP servers..."
        Write-Log "Discovering DHCP servers for domain ${selDomain}" "INFO"

        $servers = Get-DhcpServerInDC -ErrorAction Stop
        $idx = 0
        foreach ($s in $servers) {
            if ($s.DNSName -like "*$selDomain") {
                $idx++
                $obj = [PSCustomObject]@{
                    ID = $idx
                    IP = $s.IPAddress
                    Name = $s.DNSName.Split('.')[0]
                    DisplayName = "$($s.DNSName) ($($s.IPAddress))"
                }
                $script:DhcpServers += $obj
                $comboServer.Items.Add($obj.DisplayName) | Out-Null
                Write-Log "Found DHCP server: $($obj.DisplayName)" "INFO"
            }
        }

        if ($DhcpServers.Count -eq 0) {
            $lblStatus.Text = "No DHCP servers found for ${selDomain}."
            Write-Log "No DHCP servers found for domain ${selDomain}" "WARNING"
            Show-MessageBox "No DHCP servers found for the selected domain." "Warning" ([Windows.Forms.MessageBoxIcon]::Warning)
        } else {
            $comboServer.SelectedIndex = 0
            $lblStatus.Text = "$($DhcpServers.Count) DHCP server(s) found."
            Write-Log "Total DHCP servers found: $($DhcpServers.Count)" "SUCCESS"
        }
    } catch {
        $lblStatus.Text = "Error discovering DHCP servers."
        Write-Log "Discovery error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to discover DHCP servers:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
}

# --- Populate scopes for Create mode ---
function Load-CreateScopes {
    $listCreateScopes.Items.Clear()
    $script:AllScopes = @()
    try {
        $sel = $DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
        if (-not $sel) { $lblStatus.Text = "No DHCP server selected."; Write-Log "Load-CreateScopes: no server selected" "WARNING"; return }

        $scopes = Get-DhcpServerv4Scope -ComputerName $sel.IP -ErrorAction Stop
        foreach ($sc in $scopes) {
            $scopeID = $sc.ScopeId.ToString()
            $name = $sc.Name
            $range = "$($sc.StartRange)-$($sc.EndRange)"
            $script:AllScopes += [PSCustomObject]@{ ScopeID = $scopeID; Name = $name; Range = $range }
            $item = New-Object Windows.Forms.ListViewItem $scopeID
            $null = $item.SubItems.Add($name)
            $null = $item.SubItems.Add($range)
            [void]$listCreateScopes.Items.Add($item)
        }
        $lblStatus.Text = "$($AllScopes.Count) scope(s) loaded."
        Write-Log "Loaded $($AllScopes.Count) scope(s) from $($sel.DisplayName)" "SUCCESS"
    } catch {
        $lblStatus.Text = "Error loading scopes."
        Write-Log "Load-CreateScopes error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to load scopes:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
}

# --- Debounced manual server entry (IP or hostname) ---
$debounceTimer = New-Object Windows.Forms.Timer
$debounceTimer.Interval = 350
$debounceTimer.Add_Tick({
        $debounceTimer.Stop()
        $text = if ($null -ne $comboServer.Text) { $comboServer.Text.Trim() } else { "" }
        if ([string]::IsNullOrWhiteSpace($text)) { return }

        # If already present, just select it
        $existing = $DhcpServers | Where-Object { $_.DisplayName -eq $text -or $_.IP -eq $text -or $_.Name -eq $text }
        if ($existing) { $comboServer.SelectedItem = $existing.DisplayName; return }

        try {
            # Accept hostname or IP; resolve to IP + canonical name
            $resolvedIP = if (Test-IPAddress $text) {
                $text
            } else {
                ([Net.Dns]::GetHostEntry($text).AddressList |
                    Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                    Select-Object -First 1).ToString()
            }
            if (-not $resolvedIP) { 
                $lblStatus.Text = "Could not resolve server."
                Write-Log "Manual add: resolve failed for $text" "WARNING"
                return 
            }

            if (-not (Test-Connection -ComputerName $resolvedIP -Count 1 -Quiet)) {
                $lblStatus.Text = "Host unreachable: $resolvedIP"
                Write-Log "Manual add: host unreachable $resolvedIP" "ERROR"
                return
            }
            $resolvedName = try { ([Net.Dns]::GetHostEntry($resolvedIP).HostName.Split('.')[0]) } catch { "DHCP-$($resolvedIP -replace '\.','-')" }
            $obj = [PSCustomObject]@{
                ID = $DhcpServers.Count + 1
                IP = $resolvedIP
                Name = $resolvedName
                DisplayName = "$resolvedName ($resolvedIP)"
            }
            $script:DhcpServers += $obj
            $comboServer.Items.Add($obj.DisplayName) | Out-Null
            $comboServer.SelectedItem = $obj.DisplayName
            $lblStatus.Text = "Server added: $($obj.DisplayName)"
            Write-Log "Manually added DHCP server: $($obj.DisplayName)" "SUCCESS"
        } catch {
            $lblStatus.Text = "Error adding server."
            Write-Log "Manual server add error for '${text}': $($_.Exception.Message)" "ERROR"
        }
    })
$comboServer.Add_TextChanged({ $debounceTimer.Stop(); $debounceTimer.Start() })

# --- Mode switching ---
$comboMode.Add_SelectedIndexChanged({
        if ($comboMode.SelectedItem -eq "Create Reservation") {
            $panelCreate.Visible = $true; $panelScan.Visible = $false
            $btnAction.Text = "Add Reservation"; $btnExport.Visible = $false
            $lblStatus.Text = "Ready"
            Write-Log "Mode: Create Reservation" "INFO"
            if ($comboServer.SelectedItem) { Load-CreateScopes }
        } else {
            $panelCreate.Visible = $false; $panelScan.Visible = $true
            $btnAction.Text = "Scan Reservations"; $btnExport.Visible = $true
            $lblStatus.Text = "Ready"
            $listReservations.Items.Clear(); $CheckedResSet.Clear()
            Write-Log "Mode: Scan Duplicates" "INFO"
        }
    })

$comboDomain.Add_SelectedIndexChanged({ Discover-DHCPServers })
$comboServer.Add_SelectedIndexChanged({
        if ($comboMode.SelectedItem -eq "Create Reservation") { Load-CreateScopes }
    })

# --- Create: when scope clicked, load available IPs ---
$listCreateScopes.Add_SelectedIndexChanged({
        $comboBoxIPs.Items.Clear()
        if ($listCreateScopes.SelectedItems.Count -eq 0) { 
            $lblStatus.Text = "No scope selected." 
            Write-Log "No scope selected for IP load" "WARNING" 
            return 
        }
        $scopeID = $listCreateScopes.SelectedItems[0].Text
        $sel = $DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
        if (-not $sel) { 
            $lblStatus.Text = "No DHCP server selected." 
            Write-Log "No server selected for IP load" "WARNING" 
            return 
        }
        try {
            $lblStatus.Text = "Loading available IPs..."
            $ips = Get-AvailableIPs -ScopeID $scopeID -DhcpServer $sel.IP
            $progress.Value = 0; $progress.Maximum = [math]::Max(1, $ips.Count)
            foreach ($ip in $ips) { 
                [void]$comboBoxIPs.Items.Add($ip) 
                $progress.Value = [math]::Min($progress.Value + 1, $progress.Maximum) 
            }
            $lblStatus.Text = "$($ips.Count) available IP(s) found."
            Write-Log "Available IPs for scope ${scopeID}: $($ips.Count)" "SUCCESS"
        } catch {
            $lblStatus.Text = "Error loading available IPs."
            Write-Log "Available IPs load error for scope ${scopeID}: $($_.Exception.Message)" "ERROR"
            Show-MessageBox "Failed to load IPs:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
        }
    })

# --- Scan flow ---
function Update-ReservationList {
    $listReservations.BeginUpdate()
    try {
        $listReservations.Items.Clear()
        foreach ($r in $AllReservations) {
            $it = New-Object Windows.Forms.ListViewItem $r.IP
            $null = $it.SubItems.Add($r.MAC)
            $null = $it.SubItems.Add($r.Hostname)
            $null = $it.SubItems.Add($r.Scope)
            $null = $it.SubItems.Add($r.Server)
            $it.Tag = $r.UniqueID
            if ($CheckedResSet.Contains($r.UniqueID)) { $it.Checked = $true }
            [void]$listReservations.Items.Add($it)
        }
        $lblStatus.Text = "$($AllReservations.Count) reservation(s) found ($($CheckedResSet.Count) selected)."
        Write-Log "Displayed $($AllReservations.Count) reservation(s)" "INFO"
    } finally { 
        $listReservations.EndUpdate() 
    }
}

function Scan-Reservations {
    $listReservations.Items.Clear()
    $script:AllReservations = @()
    $CheckedResSet.Clear()
    try {
        $sel = $DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }
        if (-not $sel) { 
            $lblStatus.Text = "No DHCP server selected." 
            Write-Log "Scan aborted: no server selected" "WARNING" 
            return 
        }
        $lblStatus.Text = "Scanning reservations on $($sel.DisplayName)..."
        Write-Log "Scanning on $($sel.DisplayName)" "INFO"

        $scopes = Get-DhcpServerv4Scope -ComputerName $sel.IP -ErrorAction Stop
        $progress.Value = 0; $progress.Maximum = [math]::Max(1, $scopes.Count)

        foreach ($sc in $scopes) {
            $scopeID = $sc.ScopeId.ToString()
            try {
                $res = Get-DhcpServerv4Reservation -ComputerName $sel.IP -ScopeId $scopeID -ErrorAction SilentlyContinue
                foreach ($r in ($res | Where-Object { $_ })) {
                    $ip = $r.IPAddress.ToString()
                    $mac = $r.ClientId.Replace("-", "").Replace(":", "").ToUpper()
                    $macFmt = ($mac -replace '(.{2})(?!$)', '$1:').ToUpper()
                    $host = Resolve-Hostname -IPAddress $ip
                    $row = [PSCustomObject]@{
                        IP = $ip
                        MAC = $macFmt
                        Hostname = $host
                        Scope = $scopeID
                        Server = $sel.DisplayName
                        UniqueID = "$ip-$mac-$scopeID"
                    }
                    $script:AllReservations += $row
                }
            } catch {
                Write-Log "Scope scan error ($scopeID on $($sel.DisplayName)): $($_.Exception.Message)" "ERROR"
            }
            $progress.Value = [math]::Min($progress.Value + 1, $progress.Maximum)
        }

        Update-ReservationList
        Write-Report
        $lblStatus.Text = "$($AllReservations.Count) reservation(s) found."
        Write-Log "Scan completed: $($AllReservations.Count) reservation(s) on $($sel.DisplayName)" "SUCCESS"
    } catch {
        $lblStatus.Text = "Error scanning reservations."
        Write-Log "Scan error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to scan reservations:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
}

# --- Select All checkbox ---
$chkSelectAll.Add_CheckedChanged({
        $listReservations.BeginUpdate()
        try {
            foreach ($item in $listReservations.Items) {
                $item.Checked = $chkSelectAll.Checked
                if ($chkSelectAll.Checked) { 
                    $CheckedResSet.Add($item.Tag) | Out-Null 
                } else { 
                    $CheckedResSet.Remove($item.Tag) | Out-Null 
                }
            }
            $lblStatus.Text = "$($listReservations.Items.Count) reservation(s) found ($($CheckedResSet.Count) selected)."
            Write-Log "Select All = $($chkSelectAll.Checked)" "INFO"
        } finally { 
            $listReservations.EndUpdate() 
        }
    })

$listReservations.Add_ItemChecked({
        param($sender, $e)
        if ($null -eq $e.Item) { return }
        try {
            if ($e.Item.Checked) { 
                $CheckedResSet.Add($e.Item.Tag) | Out-Null 
            } else { 
                $CheckedResSet.Remove($e.Item.Tag) | Out-Null 
            }
            $lblStatus.Text = "$($listReservations.Items.Count) reservation(s) found ($($CheckedResSet.Count) selected)."
        } catch {
            $lblStatus.Text = "Selection update error."
            Write-Log "ItemChecked error for $($e.Item.Text): $($_.Exception.Message)" "ERROR"
            Show-MessageBox "Failed to update selection:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
        }
    })

# --- Duplicate report ---
function Write-Report {
    try {
        $dupMACs = $AllReservations | Group-Object MAC | Where-Object { $_.Count -gt 1 }
        $dupIPs = $AllReservations | Group-Object IP  | Where-Object { $_.Count -gt 1 }

        $sb = New-Object -TypeName System.Text.StringBuilder
        [void]$sb.AppendLine("DHCP Duplicate Reservations Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        [void]$sb.AppendLine("==================================================`r`n")

        if (($dupMACs.Count + $dupIPs.Count) -eq 0) {
            [void]$sb.AppendLine("No duplicate MAC or IP addresses found.`r`n")
        } else {
            if ($dupMACs.Count -gt 0) {
                [void]$sb.AppendLine("Duplicate MAC Addresses Found:")
                foreach ($g in $dupMACs) {
                    [void]$sb.AppendLine("MAC: $($g.Name) (Count: $($g.Count))")
                    foreach ($r in $g.Group) {
                        [void]$sb.AppendLine("  IP: $($r.IP), Hostname: $($r.Hostname), Scope: $($r.Scope), Server: $($r.Server)")
                    }
                    [void]$sb.AppendLine()
                }
            }
            if ($dupIPs.Count -gt 0) {
                [void]$sb.AppendLine("Duplicate IP Addresses Found:")
                foreach ($g in $dupIPs) {
                    [void]$sb.AppendLine("IP: $($g.Name) (Count: $($g.Count))")
                    foreach ($r in $g.Group) {
                        [void]$sb.AppendLine("  MAC: $($r.MAC), Hostname: $($r.Hostname), Scope: $($r.Scope), Server: $($r.Server)")
                    }
                    [void]$sb.AppendLine()
                }
            }
        }

        $sb.ToString() | Out-File -FilePath $reportPath -Encoding UTF8
        Show-MessageBox "Report generated:`n$reportPath" "Success" ([Windows.Forms.MessageBoxIcon]::Information)
        Write-Log "Report generated: $reportPath" "SUCCESS"
    } catch {
        Write-Log "Report generation error: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to generate report:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
    }
}

# --- Browse output folder for CSV ---
$btnBrowse.Add_Click({
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        if ($fbd.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            $txtOutput.Text = $fbd.SelectedPath
            Write-Log "Output folder set: $($fbd.SelectedPath)" "INFO"
        }
    })

# --- Action button (Create or Scan) ---
$btnAction.Add_Click({
        if ($comboMode.SelectedItem -eq "Create Reservation") {
            $scopeID = if ($listCreateScopes.SelectedItems.Count -gt 0) { $listCreateScopes.SelectedItems[0].Text } else { $null }
            $ipSel = $comboBoxIPs.SelectedItem
            $name = $txtName.Text.Trim()
            $mac = $txtMAC.Text.Trim().Replace(":", "").Replace("-", "")
            $desc = $txtDesc.Text.Trim()
            $selServer = $DhcpServers | Where-Object { $_.DisplayName -eq $comboServer.SelectedItem }

            if (-not (Validate-MACAddress -macAddress $mac)) {
                Show-MessageBox "Invalid MAC Address. Use 12 hex digits (example: D8BBC1830F62)." "Error" ([Windows.Forms.MessageBoxIcon]::Error)
                Write-Log "Invalid MAC: $mac" "ERROR"; return
            }
            if (-not $scopeID -or -not $ipSel -or -not $name -or -not $desc -or -not $selServer) {
                Show-MessageBox "Please complete all fields and select scope & server." "Warning" ([Windows.Forms.MessageBoxIcon]::Warning)
                Write-Log "Reservation failed: incomplete fields" "WARNING"; return
            }

            $dup = Check-DuplicateMAC -MACAddress $mac -ScopeID $scopeID -DhcpServer $selServer.IP
            if ($dup.Found) {
                $msg = "Duplicate MAC detected:`nMAC: $mac`nExisting IP: $($dup.IP)`nScope: $($dup.Scope)`nServer: $($dup.Server)"
                Show-MessageBox $msg "Warning" ([Windows.Forms.MessageBoxIcon]::Warning)
                Write-Log $msg "WARNING"; $lblStatus.Text = "Duplicate MAC."; return
            }
            if ($dup.Error) {
                Show-MessageBox "Error checking MAC duplicate:`n$($dup.Error)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
                $lblStatus.Text = "Error checking MAC."; return
            }

            try {
                Add-DhcpServerv4Reservation -ComputerName $selServer.IP -ScopeId $scopeID -IPAddress $ipSel -ClientId $mac -Name $name -Description $desc -ErrorAction Stop
                Show-MessageBox "Reservation added: $ipSel in scope $scopeID" "Success" ([Windows.Forms.MessageBoxIcon]::Information)
                Write-Log "Reservation added: IP=$ipSel, MAC=$mac, Scope=$scopeID, Name=$name, Desc=$desc" "SUCCESS"
                $txtName.Clear(); $txtMAC.Clear(); $txtDesc.Clear()
                $comboBoxIPs.Items.Remove($ipSel)
                $lblStatus.Text = "Reservation added."
            } catch {
                $lblStatus.Text = "Error adding reservation."
                Write-Log "Add reservation failed for IP ${ipSel}: $($_.Exception.Message)" "ERROR"
                Show-MessageBox "Failed to add reservation:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
            }
        } else {
            Scan-Reservations
        }
    })

# --- CSV export ---
$btnExport.Add_Click({
        if ($CheckedResSet.Count -eq 0) {
            Show-MessageBox "Select at least one reservation to export." "Warning" ([Windows.Forms.MessageBoxIcon]::Warning)
            Write-Log "Export aborted: no selection" "WARNING"; return
        }

        $outDir = $txtOutput.Text
        if (-not (Test-Path $outDir)) {
            Show-MessageBox "Output folder does not exist." "Error" ([Windows.Forms.MessageBoxIcon]::Error)
            Write-Log "Export aborted: invalid folder $outDir" "ERROR"; return
        }

        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvPath = Join-Path $outDir "DHCP_Reservations_$ts.csv"

        try {
            $data = foreach ($uid in $CheckedResSet) {
                $AllReservations | Where-Object { $_.UniqueID -eq $uid }
            }
            if ($data -and $data.Count -gt 0) {
                $data | Select-Object IP, MAC, Hostname, Scope, Server | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                Show-MessageBox "Export completed.`nFile: $csvPath" "Success" ([Windows.Forms.MessageBoxIcon]::Information)
                Start-Process $csvPath
                $lblStatus.Text = "Exported $($data.Count) reservation(s)."
                Write-Log "Exported $($data.Count) reservation(s) to $csvPath" "SUCCESS"
            } else {
                Show-MessageBox "No reservations selected for export." "Information" ([Windows.Forms.MessageBoxIcon]::Information)
                $lblStatus.Text = "Nothing exported."
                Write-Log "No reservations exported" "WARNING"
            }
        } catch {
            $lblStatus.Text = "CSV export error."
            Write-Log "Export error: $($_.Exception.Message)" "ERROR"
            Show-MessageBox "Failed to export CSV:`n$($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
        }
    })

# --- DHCP data helpers (placed here; PowerShell parses the whole file so order is okay) ---
function Get-AvailableIPs {
    param([string]$ScopeID, [string]$DhcpServer)
    try {
        $scope = Get-DhcpServerv4Scope -ComputerName $DhcpServer -ScopeId $ScopeID -ErrorAction Stop
        if (-not $scope) { Write-Log "Scope ID ${ScopeID} not found on ${DhcpServer}" "ERROR"; return @() }

        $leases = Get-DhcpServerv4Lease       -ComputerName $DhcpServer -ScopeId $ScopeID -ErrorAction SilentlyContinue
        $reservations = Get-DhcpServerv4Reservation -ComputerName $DhcpServer -ScopeId $ScopeID -ErrorAction SilentlyContinue

        $used = @()
        if ($leases) { $used += $leases      | ForEach-Object { $_.IPAddress.ToString() } }
        if ($reservations) { $used += $reservations | ForEach-Object { $_.IPAddress.ToString() } }
        $used = $used | Select-Object -Unique

        $startIP = $scope.StartRange.ToString()
        $endIP = $scope.EndRange.ToString()
        $startI = Convert-IpToUInt32 $startIP
        $endI = Convert-IpToUInt32 $endIP
        if ($null -eq $startI -or $null -eq $endI -or $startI -gt $endI) {
            Write-Log "Invalid scope range for ${ScopeID} (${startIP}-${endIP})" "ERROR"; return @()
        }

        $available = New-Object System.Collections.Generic.List[string]
        for ($i = $startI; $i -le $endI; $i++) {
            $ip = Convert-UInt32ToIp $i
            if (-not $ip) { continue }
            # Skip typical network/gateway/broadcast endings
            $lastOctet = [int]($ip.Split('.')[-1])
            if ($lastOctet -in 0, 255) { continue }
            if ($used -notcontains $ip) { [void]$available.Add($ip) }
        }
        return $available
    } catch {
        Write-Log "Failed to retrieve available IPs for ScopeID ${ScopeID} on ${DhcpServer}: $($_.Exception.Message)" "ERROR"
        Show-MessageBox "Failed to retrieve available IPs: $($_.Exception.Message)" "Error" ([Windows.Forms.MessageBoxIcon]::Error)
        @()
    }
}

function Check-DuplicateMAC {
    param([string]$MACAddress, [string]$ScopeID, [string]$DhcpServer)
    try {
        $res = Get-DhcpServerv4Reservation -ComputerName $DhcpServer -ScopeId $ScopeID -ErrorAction Stop
        $norm = $MACAddress.ToUpper()
        foreach ($r in $res) {
            $existing = $r.ClientId.Replace("-", "").Replace(":", "").ToUpper()
            if ($existing -eq $norm) {
                return [PSCustomObject]@{
                    Found = $true
                    IP = $r.IPAddress.ToString()
                    Scope = $ScopeID
                    Server = $DhcpServer
                }
            }
        }
        [PSCustomObject]@{ Found = $false }
    } catch {
        Write-Log "Error checking duplicate MAC ${MACAddress}: $($_.Exception.Message)" "ERROR"
        [PSCustomObject]@{ Found = $false; Error = $_.Exception.Message }
    }
}

# --- Form lifecycle ---
$form.Add_Load({
        Write-Log "Form loaded: $($form.ClientSize.Width)x$($form.ClientSize.Height)" "INFO"
        Discover-DHCPServers
    })
$form.Add_Shown({ 
        $form.Activate()
        Write-Log "Form shown. Create panel visible: $($panelCreate.Visible)" "INFO" 
    })

# --- Show the form and finish ---
[void]$form.ShowDialog()
Write-Log "Script finished" "SUCCESS"

# --- End of script ---
