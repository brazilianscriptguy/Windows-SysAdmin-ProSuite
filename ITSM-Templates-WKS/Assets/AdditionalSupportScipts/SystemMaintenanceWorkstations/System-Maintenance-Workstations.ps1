<#
.SYNOPSIS
    Enterprise Workstation System Maintenance Tool with GUI

.DESCRIPTION
    - SFC and DISM health scans
    - GPO reset (folder and registry)
    - Windows Update cleanup
    - Avatar .DAT file cleanup
    - Optional reboot
    - Logging and status feedback for L1 technicians

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.2.0 - June 20, 2025
#>

# --- Hide console window ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Window]::ShowWindow([Window]::GetConsoleWindow(), 0)

# --- Load GUI support ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Logging setup ---
$logDir = "C:\ITSM-Logs-WKS"
$logPath = Join-Path $logDir "system-maintenance-workstations.log"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

# --- Maintenance helpers ---
function Remove-GPOFolder {
    param ([string]$path)
    $expanded = [Environment]::ExpandEnvironmentVariables($path)
    if (Test-Path $expanded) {
        try {
            Remove-Item -Path $expanded -Recurse -Force -ErrorAction Stop
            Write-Log "Deleted GPO folder: ${expanded}"
        } catch {
            Write-Log "Failed to remove ${expanded}: $($_.Exception.Message)"
        }
    } else {
        Write-Log "GPO folder not found: ${expanded}"
    }
}

function Remove-DefaultAvatars {
    $avatarPath = "C:\ProgramData\Microsoft\User Account Pictures"
    if (Test-Path $avatarPath) {
        Get-ChildItem -Path $avatarPath -Filter *.dat -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item $_.FullName -Force
                Write-Log "Removed .DAT file: $($_.Name)"
            } catch {
                Write-Log "Failed to remove .DAT file: $($_.Name)"
            }
        }
    } else {
        Write-Log "Avatar path not found: $avatarPath"
    }
}

# --- GUI Setup ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "System Maintenance Utility"
$form.Size = '520,400'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = @"
This tool will perform:

- SFC and DISM system integrity scans
- GPO registry key and folder cleanup
- Windows Update cache reset and sync
- Removal of default user avatar .DAT files
- Optional automatic reboot after tasks
"@
$label.Location = '20,10'
$label.Size = '480,130'
$label.Font = 'Microsoft Sans Serif,10'
$form.Controls.Add($label)

$chkReboot = New-Object System.Windows.Forms.CheckBox
$chkReboot.Text = "Reboot immediately after maintenance"
$chkReboot.Location = '20,150'
$chkReboot.Size = '300,20'
$chkReboot.Checked = $true
$form.Controls.Add($chkReboot)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Minimum = 0
$progress.Maximum = 100
$progress.Value = 0
$progress.Location = '20,180'
$progress.Size = '460,20'
$form.Controls.Add($progress)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready to start."
$statusLabel.Location = '20,210'
$statusLabel.Size = '460,20'
$form.Controls.Add($statusLabel)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Maintenance"
$btnStart.Size = '160,40'
$btnStart.Location = '180,250'
$form.Controls.Add($btnStart)

# --- Maintenance Workflow ---
$btnStart.Add_Click({
        $progress.Value = 0
        $form.Refresh()
        Write-Log "===== Script Execution Started ====="

        # --- SFC ---
        $statusLabel.Text = "Running SFC scan..."
        $progress.Value = 10
        $form.Refresh()
        Write-Log "Running: sfc /scannow"
        $sfc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -PassThru
        Write-Log "SFC exit code: $($sfc.ExitCode)"

        # --- DISM ---
        $statusLabel.Text = "Running DISM restore..."
        $progress.Value = 20
        $form.Refresh()
        $dism = Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /restorehealth" -Wait -PassThru
        Write-Log "DISM exit code: $($dism.ExitCode)"

        # --- GPO Reset ---
        $statusLabel.Text = "Resetting GPO with templates..."
        $progress.Value = 30
        $form.Refresh()
        Start-Process -FilePath "secedit.exe" -ArgumentList "/configure /db reset.sdb /cfg `"%windir%\security\templates\setup security.inf`" /overwrite /quiet" -Wait
        Start-Process -FilePath "secedit.exe" -ArgumentList "/configure /db reset.sdb /cfg `"%windir%\inf\defltbase.inf`" /areas USER_POLICY,MACHINE_POLICY,SECURITYPOLICY /overwrite /quiet" -Wait
        Write-Log "GPO templates applied."

        # --- GPO Registry ---
        $statusLabel.Text = "Cleaning GPO registry..."
        $progress.Value = 40
        $form.Refresh()
        try {
            Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy" -Recurse -Force -ErrorAction Stop
            Write-Log "GPO registry key deleted."
        } catch {
            Write-Log "Error deleting GPO registry key: $($_.Exception.Message)"
        }

        # --- GPO Folders ---
        $statusLabel.Text = "Deleting GPO folders..."
        $progress.Value = 50
        $form.Refresh()
        Remove-GPOFolder "%windir%\System32\GroupPolicy"
        Remove-GPOFolder "%windir%\System32\GroupPolicyUsers"
        Remove-GPOFolder "%windir%\SysWOW64\GroupPolicy"
        Remove-GPOFolder "%windir%\SysWOW64\GroupPolicyUsers"

        # --- Windows Update Cache ---
        $statusLabel.Text = "Cleaning Windows Update cache..."
        $progress.Value = 65
        $form.Refresh()
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Start-Process -FilePath "wuauclt.exe" -ArgumentList "/resetauthorization /detectnow" -WindowStyle Hidden
        Write-Log "WSUS and Update cache reset completed."

        # --- Avatar Cleanup ---
        $statusLabel.Text = "Removing .DAT avatar files..."
        $progress.Value = 80
        $form.Refresh()
        Remove-DefaultAvatars

        # --- Completion ---
        $statusLabel.Text = "Maintenance complete."
        $progress.Value = 100
        Write-Log "All operations completed."

        # --- Reboot Decision ---
        if ($chkReboot.Checked) {
            [System.Windows.Forms.MessageBox]::Show("The workstation will now reboot.", "Rebooting", 'OK', 'Information')
            Write-Log "Initiating reboot by user request."
            shutdown.exe /r /f /t 60 /c "System maintenance complete. Restarting..."
        } else {
            [System.Windows.Forms.MessageBox]::Show("Maintenance complete. Reboot was canceled.", "Finished", 'OK', 'Information')
            Write-Log "Reboot skipped by user choice."
        }

        $form.Close()
    })

# --- Show GUI ---
$form.ShowDialog() | Out-Null

# End of script
