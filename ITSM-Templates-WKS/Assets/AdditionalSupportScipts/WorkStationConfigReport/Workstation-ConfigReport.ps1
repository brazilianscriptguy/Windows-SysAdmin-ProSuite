<#
.SYNOPSIS
    Collects system, BIOS, and network information and saves it to CSV.

.DESCRIPTION
    - Gathers machine name, BIOS serial, manufacturer, network info, etc.
    - Saves the report to CSV in the script directory.
    - Logs all operations in ANSI format to C:\ITSM-Logs-WKS.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.0 - June 20, 2025
#>

# Load GUI libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide PowerShell console window for GUI-based script
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# 0 = SW_HIDE
[Win32]::ShowWindow([Win32]::GetConsoleWindow(), 0)

# Log setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs-WKS'
$logPath = Join-Path $logDir "$scriptName.log"
$csvPath = Join-Path $PSScriptRoot "Workstation-Data-Report.csv"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

function Show-Error {
    param ([string]$msg)
    Write-Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
}

function Get-SystemInfo {
    try {
        $hostname = $env:COMPUTERNAME
        $bios = Get-CimInstance Win32_BIOS
        $serial = $bios.SerialNumber
        $cs = Get-CimInstance Win32_ComputerSystem
        $model = $cs.Model
        $manufacturer = $cs.Manufacturer
        $domain = $cs.Domain
        $mem = [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB, 2)
        $cpu = (Get-CimInstance Win32_Processor).Name

        $nic = Get-CimInstance Win32_NetworkAdapter -Filter "NetConnectionStatus = 2 AND PhysicalAdapter = True" | Select-Object -First 1
        $nicConf = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True AND MACAddress = '$($nic.MACAddress)'" | Select-Object -First 1

        $ipv4 = ($nicConf.IPAddress | Where-Object { $_ -like "*.*" }) -join ","
        $ipv6 = ($nicConf.IPAddress | Where-Object { $_ -like "*:*" }) -join ","
        $subnet = $nicConf.IPSubnet[0]
        $dns = $nicConf.DNSServerSearchOrder[0]
        $mac = $nic.MACAddress

        $obj = [pscustomobject]@{
            Timestamp     = Get-Date
            Hostname      = $hostname
            SerialNumber  = $serial
            Manufacturer  = $manufacturer
            Model         = $model
            MemorySizeGB  = $mem
            Processor     = $cpu
            IPv4Address   = $ipv4
            IPv6Addresses = $ipv6
            SubnetMask    = $subnet
            DNSServer     = $dns
            MACAddress    = $mac
            Domain        = $domain
        }

        if (-not (Test-Path $csvPath)) {
            $obj | Export-Csv -Path $csvPath -NoTypeInformation -Encoding Default
            Write-Log "CSV created: $csvPath"
        } else {
            $obj | Export-Csv -Path $csvPath -NoTypeInformation -Append -Encoding Default
            Write-Log "CSV appended: $csvPath"
        }

        [System.Windows.Forms.MessageBox]::Show("System information has been saved to:`n$csvPath", "Information Collected", 'OK', 'Information')
    } catch {
        Show-Error "Failed to retrieve system info: $($_.Exception.Message)"
    }
}

# GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "Workstation Info Collection"
$form.Size = '500,320'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "This utility will collect system and network details:"
$lbl.Location = '20,20'
$lbl.Size = '440,20'
$form.Controls.Add($lbl)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = '20,50'
$listBox.Size = '440,100'
$listBox.Items.Add("✔️ BIOS and Serial Number")
$listBox.Items.Add("✔️ Manufacturer, Model, RAM, CPU")
$listBox.Items.Add("✔️ IPv4, IPv6, DNS, MAC")
$listBox.Items.Add("✔️ Domain affiliation")
$listBox.Items.Add("✔️ Save to ANSI-compatible CSV")
$form.Controls.Add($listBox)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Run Collection"
$btn.Location = '150,170'
$btn.Size = '180,40'
$btn.Add_Click({
    Write-Log "System collection started"
    Get-SystemInfo
    Write-Log "System collection finished"
})
$form.Controls.Add($btn)

$form.ShowDialog()

# End of script
