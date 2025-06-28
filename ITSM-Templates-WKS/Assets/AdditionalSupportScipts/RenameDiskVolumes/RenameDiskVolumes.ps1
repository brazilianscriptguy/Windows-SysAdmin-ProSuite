<#
.SYNOPSIS
    Rename local disk volumes with GUI interface.

.DESCRIPTION
    - Renames volume C:\ to the workstation's hostname.
    - Renames volume D:\ to "Personal-Files".
    - Skips removable or non-fixed disks.
    - Friendly GUI for L1 support.
    - ANSI-compatible log output to disk.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.1 - June 20, 2025
#>

# Hide PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Window]::ShowWindow([Window]::GetConsoleWindow(), 0)

# Load GUI assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Set up log directory and file
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\GSTI-Logs"
$logPath = Join-Path $logDir "$scriptName.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Log-Message {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

function Rename-Volume {
    param (
        [string]$DriveLetter,
        [string]$NewLabel
    )
    try {
        $volume = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        if ($volume.DriveType -ne 'Fixed') {
            Log-Message "Drive ${DriveLetter}: is not a fixed disk. Skipping."
            return
        }
        if ($volume.FileSystemLabel -ne $NewLabel) {
            Set-Volume -DriveLetter $DriveLetter -NewFileSystemLabel $NewLabel
            Log-Message "Volume ${DriveLetter}: renamed to '${NewLabel}'."
        } else {
            Log-Message "Volume ${DriveLetter}: already named '${NewLabel}'."
        }
    } catch {
        Log-Message "Error renaming ${DriveLetter}: $($_.Exception.Message)"
    }
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "Rename Disk Volumes"
$form.Size = New-Object System.Drawing.Size(460, 300)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "Select which volumes to rename:"
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($label)

$chkC = New-Object System.Windows.Forms.CheckBox
$chkC.Text = "Rename C:\ to $env:COMPUTERNAME"
$chkC.Location = New-Object System.Drawing.Point(40, 50)
$chkC.Size = New-Object System.Drawing.Size(380, 20)
$chkC.Checked = $true
$form.Controls.Add($chkC)

$chkD = New-Object System.Windows.Forms.CheckBox
$chkD.Text = "Rename D:\ to Personal-Files"
$chkD.Location = New-Object System.Drawing.Point(40, 80)
$chkD.Size = New-Object System.Drawing.Size(380, 20)
$chkD.Checked = $true
$form.Controls.Add($chkD)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(40, 120)
$progress.Size = New-Object System.Drawing.Size(360, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(40, 150)
$statusLabel.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($statusLabel)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Execute Rename"
$btn.Size = New-Object System.Drawing.Size(150, 40)
$btn.Location = New-Object System.Drawing.Point(150, 190)
$btn.Add_Click({
    $progress.Value = 0
    $form.Refresh()
    $statusLabel.Text = "Processing..."
    Log-Message "===== Rename Operation Started ====="

    if ($chkC.Checked) {
        Rename-Volume -DriveLetter "C" -NewLabel $env:COMPUTERNAME
        $progress.Value += 50
    }
    if ($chkD.Checked) {
        Rename-Volume -DriveLetter "D" -NewLabel "Personal-Files"
        $progress.Value += 50
    }

    $statusLabel.Text = "Operation completed."
    [System.Windows.Forms.MessageBox]::Show("Disk volume rename completed successfully.", "Finished", 'OK', 'Information')
    Log-Message "===== Rename Operation Completed ====="
})
$form.Controls.Add($btn)

$form.ShowDialog() | Out-Null

# End of script
