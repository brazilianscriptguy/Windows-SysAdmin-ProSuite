<#
.SYNOPSIS
    GUI Tool to update Kaspersky Network Agent certificate and assign KES server address.

.DESCRIPTION
    - Sets the Kaspersky agent to point to a custom Kaspersky Security Center (KES) server.
    - Verifies agent communication.
    - Optionally reboots the system.
    - Logs all actions to an ANSI-compatible .log file.
    - Provides full GUI-based interaction.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.1.0 - June 20, 2025
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

# Paths
$agentPath = "C:\Program Files (x86)\Kaspersky Lab\NetworkAgent"
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\ITSM-Logs-WKS"
$logPath = Join-Path $logDir "$scriptName.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Logging function
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

# Error display
function Show-Error {
    param ([string]$msg)
    Write-Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
}

# Info message
function Show-Info {
    param ([string]$msg, [string]$title = "Information")
    [System.Windows.Forms.MessageBox]::Show($msg, $title, 'OK', 'Information')
}

# GUI: Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Kaspersky Agent Update Tool"
$form.Size = '470,340'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

# Label for instruction
$label = New-Object System.Windows.Forms.Label
$label.Text = "Enter the Kaspersky Security Center (KES) server name:"
$label.Location = '20,20'
$label.Size = '420,20'
$form.Controls.Add($label)

# Input for server
$textKSC = New-Object System.Windows.Forms.TextBox
$textKSC.Location = '20,45'
$textKSC.Size = '420,20'
$textKSC.Text = "kes01-itsm.scriptguy.hq"
$form.Controls.Add($textKSC)

# Checkbox: Reboot
$chkReboot = New-Object System.Windows.Forms.CheckBox
$chkReboot.Text = "Reboot the system after update"
$chkReboot.Location = '20,80'
$chkReboot.Size = '300,20'
$chkReboot.Checked = $true
$form.Controls.Add($chkReboot)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = '20,110'
$progressBar.Size = '420,20'
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = '20,140'
$statusLabel.Size = '400,20'
$form.Controls.Add($statusLabel)

# Execute button
$btnExecute = New-Object System.Windows.Forms.Button
$btnExecute.Text = "Update Agent"
$btnExecute.Location = '150,190'
$btnExecute.Size = '160,40'
$form.Controls.Add($btnExecute)

# Action
$btnExecute.Add_Click({
    $progressBar.Value = 0
    $form.Refresh()
    $statusLabel.Text = "Checking agent path..."

    $KESserver = $textKSC.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($KESserver)) {
        Show-Error "Please enter a valid KES server name."
        return
    }

    if (Test-Path $agentPath) {
        Set-Location -Path $agentPath
        $progressBar.Value = 20
        $form.Refresh()
        Start-Sleep -Milliseconds 300

        try {
            $statusLabel.Text = "Reassigning Kaspersky Agent..."
            $form.Refresh()
            Write-Log "Executing: klmover -address $KESserver"
            & ".\klmover.exe" -address $KESserver | Out-Null
            $progressBar.Value = 50
            Start-Sleep -Milliseconds 400

            $statusLabel.Text = "Running agent integrity check..."
            $form.Refresh()
            Write-Log "Executing: klnagchk"
            & ".\klnagchk.exe" | Out-Null
            $progressBar.Value = 80
            Start-Sleep -Milliseconds 400

            $statusLabel.Text = "Operation completed."
            $progressBar.Value = 100
            Write-Log "Agent update and verification completed."

            Show-Info "Kaspersky agent was successfully updated and verified."

            if ($chkReboot.Checked) {
                Show-Info "System will now restart." "Reboot"
                Write-Log "Rebooting system as requested by user..."
                Restart-Computer -Force
            } else {
                Write-Log "User chose not to reboot."
                Show-Info "Update completed. System reboot was skipped."
            }

        } catch {
            Show-Error "Execution failed: $($_.Exception.Message)"
        }

    } else {
        Show-Error "Kaspersky agent path not found: $agentPath"
    }

    $form.Close()
})

# Launch GUI
Write-Log "===== Kaspersky Agent Update Tool launched ====="
$form.ShowDialog() | Out-Null
Write-Log "===== Execution ended ====="

# End of script
