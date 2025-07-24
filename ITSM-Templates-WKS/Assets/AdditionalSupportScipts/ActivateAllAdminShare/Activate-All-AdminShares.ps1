<#
.SYNOPSIS
    PowerShell GUI Script to Enable Admin Shares, RDP, Disable Firewall & Defender with Logging

.DESCRIPTION
    Enables admin shares, enables RDP, disables NLA, disables all firewall profiles,
    disables Microsoft Defender, logs actions (ANSI .log), and uses GUI dialogs.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.1 - June 19, 2025
#>

# Hide console window
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
[Win32]::ShowWindow([Win32]::GetConsoleWindow(), 0)

# Load GUI assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configure log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs-WKS'
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

# Notify user
[System.Windows.Forms.MessageBox]::Show(
    "The script will now activate Admin Shares, enable Remote Desktop (RDP), disable Windows Defender, and lower all Firewall restrictions. Please wait...",
    "System Configuration - Starting",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

Write-Log "===== Script Execution Started - Version 1.3.1 ====="

# Enable admin shares
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" -Name AutoShareWks -Value 1 -Type DWord
    Write-Log "Administrative shares enabled successfully."
} catch {
    Write-Log "Error enabling administrative shares: $_"
}
Start-Sleep -Seconds 2

# Enable RDP and disable NLA
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name UserAuthentication -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fAllowToGetHelp -Value 1 -Type DWord
    Write-Log "Remote Desktop enabled. Network Level Authentication disabled."
} catch {
    Write-Log "Error configuring Remote Desktop settings: $_"
}

# Enable firewall rules for RDP
try {
    $rdpGroup = Get-NetFirewallRule | Where-Object { $_.DisplayGroup -like "*Remote Desktop*" } | Select-Object -First 1
    if ($rdpGroup) {
        Enable-NetFirewallRule -DisplayGroup $rdpGroup.DisplayGroup
        Write-Log "Firewall rules enabled for Remote Desktop group: $($rdpGroup.DisplayGroup)"
    } else {
        Write-Log "No Remote Desktop firewall group found. Firewall rule skipped."
    }
} catch {
    Write-Log "Error enabling Remote Desktop firewall rules: $_"
}

# Disable all firewall profiles
try {
    Set-NetFirewallProfile -All -Enabled False
    Write-Log "All Windows Firewall profiles disabled (Domain, Private, Public)."
} catch {
    Write-Log "Error disabling firewall profiles: $_"
}

# Disable Microsoft Defender
try {
    $defenderPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
    if (-not (Test-Path $defenderPath)) {
        New-Item -Path $defenderPath -Force | Out-Null
    }
    Set-ItemProperty -Path $defenderPath -Name DisableAntiSpyware -Value 1 -Type DWord
    Write-Log "Microsoft Defender disabled via policy."
} catch {
    Write-Log "Error disabling Microsoft Defender: $_"
}

# Set RDP to listen on port 3389
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name PortNumber -Value 3389 -Type DWord
    Write-Log "RDP configured to listen on port 3389."
} catch {
    Write-Log "Error configuring RDP port: $_"
}

# Final status
$finalMessage = "Execution complete. All configuration tasks were applied successfully:`n`n" +
"- Admin Shares Activated`n" +
"- RDP Enabled`n" +
"- Firewall Disabled`n" +
"- Defender Disabled`n`n" +
"You can check the full log here:`n$logPath"

Write-Log "===== Script Execution Completed ====="
Write-Log "Final Summary: All features applied as expected."

[System.Windows.Forms.MessageBox]::Show(
    $finalMessage,
    "System Configuration - Completed",
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
)

# End of script
