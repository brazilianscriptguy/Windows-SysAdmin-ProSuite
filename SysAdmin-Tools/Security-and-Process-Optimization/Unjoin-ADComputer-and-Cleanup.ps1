<#
.SYNOPSIS
    Domain Unjoin and Cleanup Utility with GUI and Logging

.DESCRIPTION
    - Unjoins the system from Active Directory
    - Clears DNS cache and domain environment variables
    - Removes inactive domain profiles
    - Optionally reboots after cleanup
    - All actions logged in ANSI .log file

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.0 - June 20, 2025
#>

# Hide console
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Win32]::ShowWindow([Win32]::GetConsoleWindow(), 0)

# GUI support
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs-WKS'
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# ANSI logging
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

Write-Log "===== Script execution started ====="

# GUI form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Domain Unjoin and Cleanup Utility"
$form.Size = '550,360'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

# Info label
$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "This tool will perform:`r`n`r`n- Unjoin from Active Directory`r`n- Clear DNS cache and environment variables`r`n- Remove old domain profiles`r`n- Optional restart after cleanup"
$infoLabel.Location = '20,20'
$infoLabel.Size = '500,110'
$form.Controls.Add($infoLabel)

# Restart checkbox
$chkReboot = New-Object System.Windows.Forms.CheckBox
$chkReboot.Text = "Restart automatically after cleanup"
$chkReboot.Location = '20,130'
$chkReboot.Size = '300,20'
$chkReboot.Checked = $true
$form.Controls.Add($chkReboot)

# Check if system is domain-joined
function Is-DomainJoined {
    return (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain
}

# Unjoin from domain
function Unjoin-Domain {
    if (-not (Is-DomainJoined)) {
        [System.Windows.Forms.MessageBox]::Show("This system is not currently joined to a domain.", "Not Joined", 'OK', 'Information')
        Write-Log "System is not part of any domain."
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to unjoin this system from the domain?", "Confirm Unjoin", 'YesNo', 'Question')
    if ($confirm -eq 'Yes') {
        try {
            $cred = Get-Credential -Message "Enter domain admin credentials"
            Write-Log "Attempting to unjoin domain..."
            Remove-Computer -UnjoinDomainCredential $cred -Force -Restart
        } catch {
            Write-Log "Error unjoining domain: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show("Unjoin failed: $($_.Exception.Message)", "Error", 'OK', 'Error')
        }
    }
}

# Cleanup tasks
function Perform-Cleanup {
    Write-Log "===== Cleanup tasks started ====="

    # Clear DNS
    try {
        Clear-DnsClientCache
        Write-Log "DNS cache cleared."
    } catch {
        Write-Log "Error clearing DNS: $($_.Exception.Message)"
    }

    # Remove old domain profiles
    try {
        Get-WmiObject -Class Win32_UserProfile | Where-Object {
            $_.Special -eq $false -and $_.Loaded -eq $false -and $_.LocalPath -like '*\Users\*'
        } | ForEach-Object {
            Write-Log "Removing profile: $($_.LocalPath)"
            $_ | Remove-WmiObject
        }
        Write-Log "Old domain profiles removed."
    } catch {
        Write-Log "Failed to remove profiles: $($_.Exception.Message)"
    }

    # Clear environment vars
    try {
        [Environment]::SetEnvironmentVariable("LOGONSERVER", $null, 'Machine')
        [Environment]::SetEnvironmentVariable("USERDOMAIN", $null, 'Machine')
        [Environment]::SetEnvironmentVariable("USERDNSDOMAIN", $null, 'Machine')
        Write-Log "Domain-related environment variables cleared."
    } catch {
        Write-Log "Error clearing environment variables: $($_.Exception.Message)"
    }

    # Restart
    if ($chkReboot.Checked) {
        Write-Log "Restarting system in 15 seconds..."
        [System.Windows.Forms.MessageBox]::Show("Cleanup complete. Restarting system in 15 seconds.", "Restart", 'OK', 'Information')
        Start-Sleep -Seconds 2
        shutdown.exe /r /f /t 15 /c "System will reboot to complete cleanup."
    } else {
        Write-Log "Cleanup complete. Reboot was not selected."
        [System.Windows.Forms.MessageBox]::Show("Cleanup complete. No reboot will be performed.", "Finished", 'OK', 'Information')
    }

    Write-Log "===== Cleanup tasks finished ====="
}

# Buttons
$btnUnjoin = New-Object System.Windows.Forms.Button
$btnUnjoin.Text = "1. Unjoin from Domain"
$btnUnjoin.Size = '460,40'
$btnUnjoin.Location = '40,160'
$btnUnjoin.Add_Click({ Unjoin-Domain })
$form.Controls.Add($btnUnjoin)

$btnCleanup = New-Object System.Windows.Forms.Button
$btnCleanup.Text = "2. Perform Cleanup Tasks"
$btnCleanup.Size = '460,40'
$btnCleanup.Location = '40,210'
$btnCleanup.Add_Click({ Perform-Cleanup })
$form.Controls.Add($btnCleanup)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = '100,30'
$btnClose.Location = '420,270'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# Show GUI
$form.ShowDialog() | Out-Null
Write-Log "===== Script execution completed ====="

# End of Script
