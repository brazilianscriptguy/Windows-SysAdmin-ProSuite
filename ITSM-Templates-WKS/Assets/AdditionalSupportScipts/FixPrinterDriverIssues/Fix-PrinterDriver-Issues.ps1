<#
.SYNOPSIS
    GUI Tool to Clear Print Queue, Reset Spooler, and Remove Printer Drivers.

.DESCRIPTION
    - Method 1: Clear print queue
    - Method 2: Reset spooler dependency
    - Method 3: List/remove installed printer drivers
    - Includes GUI feedback and ANSI log output

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.1 - June 20, 2025
#>

# Hide console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

# Load GUI libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Setup log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\ITSM-Logs-WKS"
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

function Show-Error {
    param([string]$msg)
    Write-Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
}

# Method 1
function Clear-PrintQueue {
    $statusLabel.Text = "Clearing print queue..."
    $form.Refresh()
    Write-Log "Clearing print queue..."
    try {
        Stop-Service spooler -Force
        Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -Recurse
        Start-Service spooler
        Write-Log "Print queue cleared."
        [System.Windows.Forms.MessageBox]::Show("Print queue cleared.", "Success", 'OK', 'Information')
    } catch {
        Show-Error "Failed to clear print queue: ${_}"
    }
    $statusLabel.Text = ""
}

# Method 2
function Reset-SpoolerDependency {
    $statusLabel.Text = "Resetting spooler dependency..."
    $form.Refresh()
    Write-Log "Resetting spooler dependency..."
    try {
        Stop-Service spooler -Force
        sc.exe config spooler depend= RPCSS | Out-Null
        Start-Service spooler
        Write-Log "Spooler dependency reset."
        [System.Windows.Forms.MessageBox]::Show("Spooler dependency reset.", "Success", 'OK', 'Information')
    } catch {
        Show-Error "Failed to reset spooler dependency: ${_}"
    }
    $statusLabel.Text = ""
}

# Method 3
function Remove-PrinterDrivers {
    Write-Log "Listing installed printer drivers..."
    $drivers = Get-PrinterDriver | Select-Object -ExpandProperty Name
    if (-not $drivers) {
        [System.Windows.Forms.MessageBox]::Show("No printer drivers found.", "Info", 'OK', 'Information')
        return
    }

    $formDrivers = New-Object System.Windows.Forms.Form
    $formDrivers.Text = "Remove Printer Drivers"
    $formDrivers.Size = New-Object System.Drawing.Size(400, 420)
    $formDrivers.StartPosition = 'CenterScreen'
    $formDrivers.TopMost = $true

    $listBox = New-Object System.Windows.Forms.CheckedListBox
    $listBox.Location = '20,20'
    $listBox.Size = '340,280'
    $drivers | ForEach-Object { $listBox.Items.Add($_) }
    $formDrivers.Controls.Add($listBox)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove Selected"
    $btnRemove.Location = '120,320'
    $btnRemove.Size = '140,40'
    $btnRemove.Add_Click({
            foreach ($item in $listBox.CheckedItems) {
                try {
                    Remove-PrinterDriver -Name $item -ErrorAction Stop
                    Write-Log "Removed driver: ${item}"
                } catch {
                    Show-Error "Failed to remove ${item}: ${_}"
                }
            }
            [System.Windows.Forms.MessageBox]::Show("Selected drivers removed.", "Done", 'OK', 'Information')
            $formDrivers.Close()
        })
    $formDrivers.Controls.Add($btnRemove)

    $form.TopMost = $false
    $form.Enabled = $false
    $formDrivers.ShowDialog() | Out-Null
    $form.Enabled = $true
    $form.TopMost = $true
    $form.Activate()
}

# Main GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = "Printer Troubleshooting Tool"
$form.Size = '400,280'
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$label = New-Object System.Windows.Forms.Label
$label.Text = "Choose an option:"
$label.Location = '20,20'
$label.Size = '340,20'
$form.Controls.Add($label)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "1. Clear Print Queue"
$btnClear.Location = '50,50'
$btnClear.Size = '300,40'
$btnClear.Add_Click({ Clear-PrintQueue })
$form.Controls.Add($btnClear)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "2. Reset Spooler Dependency"
$btnReset.Location = '50,100'
$btnReset.Size = '300,40'
$btnReset.Add_Click({ Reset-SpoolerDependency })
$form.Controls.Add($btnReset)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "3. Remove Printer Drivers"
$btnRemove.Location = '50,150'
$btnRemove.Size = '300,40'
$btnRemove.Add_Click({ Remove-PrinterDrivers })
$form.Controls.Add($btnRemove)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = '20,210'
$statusLabel.Size = '340,20'
$form.Controls.Add($statusLabel)

$form.ShowDialog() | Out-Null
Write-Log "Printer Troubleshooting Tool session ended."

# End of script
