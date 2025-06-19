<#
.SYNOPSIS
    GUI Tool to Set Time Zone and Synchronize System Clock

.DESCRIPTION
    - Lets technicians choose a system time zone from a dropdown list
    - Supports syncing with either the domain controller or a custom NTP server
    - ANSI-compatible logging and error handling
    - GUI optimized for L1 support usage

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.4.0 - June 20, 2025
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

# Load GUI types
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Logging setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\ITSM-Logs-WKS'
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param ([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] [$Level] $Message" -Encoding Default
}

# Form Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "🕒 Time Synchronization Utility"
$form.Size = New-Object System.Drawing.Size(620, 320)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

# Label: Time zone
$lblZone = New-Object System.Windows.Forms.Label
$lblZone.Text = "Select a Time Zone:"
$lblZone.Location = "20,20"
$lblZone.Size = "580,20"
$lblZone.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblZone)

# Time zone dropdown
$comboZone = New-Object System.Windows.Forms.ComboBox
$comboZone.Location = "20,45"
$comboZone.Size = "560,25"
$comboZone.DropDownWidth = 580
$comboZone.DropDownStyle = 'DropDownList'
[System.TimeZoneInfo]::GetSystemTimeZones() | ForEach-Object {
    $comboZone.Items.Add("$($_.DisplayName) [ID: $($_.Id)]")
}
$form.Controls.Add($comboZone)

# Radio buttons
$rbDomain = New-Object System.Windows.Forms.RadioButton
$rbDomain.Text = "Use Domain Time Server"
$rbDomain.Location = "20,85"
$rbDomain.Size = "220,20"
$rbDomain.Checked = $true
$form.Controls.Add($rbDomain)

$rbCustom = New-Object System.Windows.Forms.RadioButton
$rbCustom.Text = "Use Custom NTP Server"
$rbCustom.Location = "20,115"
$rbCustom.Size = "220,20"
$form.Controls.Add($rbCustom)

# Custom NTP input
$txtNTP = New-Object System.Windows.Forms.TextBox
$txtNTP.Location = "250,112"
$txtNTP.Size = "330,23"
$txtNTP.Enabled = $false
$form.Controls.Add($txtNTP)

# Toggle field based on selection
$rbDomain.Add_CheckedChanged({ $txtNTP.Enabled = $false })
$rbCustom.Add_CheckedChanged({ 
    $txtNTP.Enabled = $true
    $txtNTP.Focus()
})

# Apply & Sync Button
$btnSync = New-Object System.Windows.Forms.Button
$btnSync.Text = "✅ Apply and Sync"
$btnSync.Location = "20,160"
$btnSync.Size = "560,40"
$btnSync.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnSync)

# Exit Button
$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Location = "500,220"
$btnExit.Size = "80,30"
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

# Button Click Logic
$btnSync.Add_Click({
    $selected = $comboZone.SelectedItem
    if (-not $selected) {
        [System.Windows.Forms.MessageBox]::Show("Please select a time zone.", "Missing Input", 'OK', 'Warning')
        return
    }

    if ($selected -match "\[ID: (.+?)\]") {
        $tzId = $Matches[1]
    } else {
        [System.Windows.Forms.MessageBox]::Show("Invalid time zone selection format.", "Error", 'OK', 'Error')
        return
    }

    try {
        tzutil /s $tzId
        Write-Log "Time zone set to $tzId"
    } catch {
        Write-Log "Failed to set time zone: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Failed to apply time zone: $tzId", "Error", 'OK', 'Error')
        return
    }

    if ($rbCustom.Checked -and [string]::IsNullOrWhiteSpace($txtNTP.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a valid custom time server.", "Missing Input", 'OK', 'Warning')
        return
    }

    $ntpServer = if ($rbDomain.Checked) { $env:USERDNSDOMAIN } else { $txtNTP.Text.Trim() }

    try {
        w32tm /config /manualpeerlist:$ntpServer /syncfromflags:manual /reliable:yes /update | Out-Null
        w32tm /resync /rediscover | Out-Null
        Write-Log "Time synced successfully using: $ntpServer"
        [System.Windows.Forms.MessageBox]::Show("Time has been synchronized with: $ntpServer", "Success", 'OK', 'Information')
    } catch {
        Write-Log "Time sync failed with: $ntpServer - $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Failed to sync with $ntpServer", "Error", 'OK', 'Error')
    }
})

$form.Add_Shown({ $form.Activate() })
$form.ShowDialog() | Out-Null
Write-Log "Session closed."

# End of script
