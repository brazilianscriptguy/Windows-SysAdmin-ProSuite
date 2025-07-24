<#
.SYNOPSIS
    Enables legacy OS domain join compatibility via registry.

.DESCRIPTION
    - Applies NetJoinLegacyAccountReuse = 1
    - Enables Windows XP/7/10/11 to rejoin the domain using same hostname
    - ANSI-compatible log file
    - Friendly GUI for use by L1 teams

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.0 - June 20, 2025
#>

# Hide PowerShell console
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

# Load GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\ITSM-Logs-WKS"
$logPath = Join-Path $logDir "$scriptName.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Logging
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

# Error feedback
function Show-Error {
    param([string]$msg)
    Write-Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
}

# Apply registry change
function Apply-DomainJoinSetting {
    try {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "NetJoinLegacyAccountReuse" -Value 1 -Type DWord
        Write-Log "Registry key 'NetJoinLegacyAccountReuse' set to 1"
        [System.Windows.Forms.MessageBox]::Show(
            "Registry successfully updated. Legacy systems (Windows XP/7) can now reuse existing domain accounts.",
            "Success",
            'OK',
            'Information'
        )
    } catch {
        Show-Error "Failed to apply registry change: $($_.Exception.Message)"
    }
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = "Enable Legacy Domain Join"
$form.Size = '480,220'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "This enables Windows XP, 7, 10, and 11 systems to rejoin domains using existing computer account names."
$label.Location = '20,20'
$label.Size = '440,40'
$form.Controls.Add($label)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Registry Fix"
$btnApply.Size = '180,40'
$btnApply.Location = '140,100'
$btnApply.Add_Click({
        Apply-DomainJoinSetting
        Write-Log "User clicked Apply button"
    })
$form.Controls.Add($btnApply)

# Log and start GUI
Write-Log "===== Script started: Enable Legacy Domain Join ====="
$form.ShowDialog() | Out-Null
Write-Log "===== Script completed ====="

# End of script
