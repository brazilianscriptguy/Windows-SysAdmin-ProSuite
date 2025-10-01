<#
.SYNOPSIS
    Troubleshoots spooler, print queue, printers, drivers and related GPO policies.

.DESCRIPTION
    This script performs several actions to restore proper printing system functionality:
    - Clears the print queue
    - Fixes the Print Spooler service dependency (RPCSS)
    - Removes installed printers (local or network)
    - Provides GUI for selective driver removal
    - Resets printer policies (PointAndPrint) and forces gpupdate
    - Generates a full log at C:\Logs-TEMP
    - Suitable for Startup GPO or technical support use

.AUTHOR
     Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last update: 2025-10-01
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==== LOGGING ====
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logPath = Join-Path $logDir "$scriptName.log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$Level] $Message"
}

Write-Log "==== Session started ===="

# ==== HIDE CONSOLE ====
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
}
"@
    [Win]::Hide()
} catch {}

# ==== GUI BASE ====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
function Show-Info($msg) { [System.Windows.Forms.MessageBox]::Show($msg, 'Information', 'OK', 'Information') | Out-Null }
function Show-Error($msg) { [System.Windows.Forms.MessageBox]::Show($msg, 'Error', 'OK', 'Error') | Out-Null }

# ==== SERVICES ====
function Stop-Spooler {
    try {
        Stop-Service -Name Spooler -Force -ErrorAction Stop
        Write-Log "Print Spooler stopped successfully."
    } catch {
        Write-Log "Failed to stop Print Spooler: $_" 'ERROR'
    }
}
function Start-Spooler {
    try {
        Start-Service -Name Spooler -ErrorAction Stop
        Write-Log "Print Spooler started successfully."
    } catch {
        Write-Log "Failed to start Print Spooler: $_" 'ERROR'
    }
}
function Ensure-Spooler {
    try {
        $svc = Get-Service -Name Spooler -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Start-Spooler
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Log "Failed to ensure Print Spooler: $_" 'ERROR'
    }
}

# ==== CLEAR PRINT QUEUE ====
function Clear-PrintQueue {
    try {
        Stop-Spooler
        $path = "$env:SystemRoot\System32\spool\PRINTERS\*"
        if (Test-Path $path) {
            Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "Print queue files deleted."
        }
        Start-Spooler
        Show-Info "Print queue successfully cleared."
    } catch {
        Write-Log "Error while clearing queue: $_" 'ERROR'
        Show-Error "Error clearing print queue.`n$_"
    }
}

# ==== FIX SPOOLER DEPENDENCY ====
function Reset-SpoolerDependency {
    try {
        Stop-Spooler
        sc.exe config spooler depend= RPCSS | Out-Null
        Start-Spooler
        Write-Log "Spooler dependency reset successfully."
        Show-Info "Spooler dependency has been reset."
    } catch {
        Write-Log "Error resetting dependency: $_" 'ERROR'
        Show-Error "Error resetting spooler dependency.`n$_"
    }
}

# ==== REMOVE ALL PRINTERS ====
function Remove-AllPrinters {
    try {
        Ensure-Spooler
        $printers = Get-CimInstance -Class Win32_Printer

        if (-not $printers) {
            Show-Info "No printers found."
            return
        }

        foreach ($printer in $printers) {
            $name = $printer.Name
            try {
                Write-Log "Trying to remove printer: $name"

                if ($name -match "^\\\\") {
                    rundll32 printui.dll, PrintUIEntry /dn /n "$name"
                    Start-Sleep -Milliseconds 500
                }

                Remove-Printer -Name "$name" -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500

                $stillExists = Get-CimInstance -Class Win32_Printer -Filter "Name='$name'" -ErrorAction SilentlyContinue
                if ($null -eq $stillExists) {
                    Write-Log "Printer removed: $name"
                } else {
                    Write-Log "Printer still present after removal attempt: $name" 'WARN'
                }
            } catch {
                Write-Log "Error removing printer ${name}: $_" 'ERROR'
            }
        }
        Show-Info "Printer removal completed. Check the log for details."
    } catch {
        Write-Log "General failure removing printers: $_" 'ERROR'
        Show-Error "Error removing printers.`n$_"
    }
}

# ==== REMOVE DRIVERS ====
function Remove-PrinterDrivers-Interactive {
    try {
        Ensure-Spooler
        $drivers = Get-PrinterDriver | Sort-Object Name
        if (-not $drivers) { Show-Info "No printer drivers found."; return }

        $form = New-Object Windows.Forms.Form
        $form.Text = "Remove Printer Drivers"
        $form.Size = New-Object Drawing.Size(600, 500)
        $form.StartPosition = 'CenterScreen'

        $listBox = New-Object Windows.Forms.CheckedListBox
        $listBox.Location = '10,10'
        $listBox.Size = New-Object Drawing.Size(560, 380)
        foreach ($d in $drivers) { [void]$listBox.Items.Add($d.Name) }
        $form.Controls.Add($listBox)

        $btnRemove = New-Object Windows.Forms.Button
        $btnRemove.Text = "Remove Selected"
        $btnRemove.Size = New-Object Drawing.Size(180, 30)
        $btnRemove.Location = '10,410'
        $btnRemove.Add_Click({
                foreach ($item in $listBox.CheckedItems) {
                    try {
                        Write-Log "Removing driver: ${item}"
                        Remove-PrinterDriver -Name "${item}" -ErrorAction SilentlyContinue
                    } catch {
                        Write-Log "Error removing driver ${item}: $_" "ERROR"
                    }
                }
                Show-Info "Driver removal completed."
                $form.Close()
            })
        $form.Controls.Add($btnRemove)

        $btnCancel = New-Object Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object Drawing.Size(120, 30)
        $btnCancel.Location = '420,410'
        $btnCancel.Add_Click({ $form.Close() })
        $form.Controls.Add($btnCancel)

        [void]$form.ShowDialog()
    } catch {
        Write-Log "Error in driver interface: $_" 'ERROR'
        Show-Error "Error loading driver interface.`n$_"
    }
}

# ==== RESET PRINTER POLICIES ====
function Reset-PrinterPolicies {
    try {
        Write-Log "Deleting PointAndPrint policy key..."
        reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" /f | Out-Null
        Write-Log "PointAndPrint policy key deleted."

        Write-Log "Running gpupdate /force (silent)..."
        $gpOut = & gpupdate /force /target:computer 2>&1
        Write-Log "gpupdate output:`n$gpOut"

        Show-Info "Printer policies have been reset and GPO updated."
    } catch {
        Write-Log "Error resetting printer policies: $_" 'ERROR'
        Show-Error "Error resetting printer policies.`n$_"
    }
}

# ==== MAIN GUI ====
$formMain = New-Object System.Windows.Forms.Form
$formMain.Text = "Printing Troubleshooter"
$formMain.Size = New-Object System.Drawing.Size(600, 380)
$formMain.StartPosition = "CenterScreen"

$btn1 = New-Object System.Windows.Forms.Button
$btn1.Text = "1. Clear Print Queue"
$btn1.Location = New-Object System.Drawing.Point(20, 40)
$btn1.Size = New-Object System.Drawing.Size(540, 40)
$btn1.Add_Click({ Clear-PrintQueue })
$formMain.Controls.Add($btn1)

$btn2 = New-Object System.Windows.Forms.Button
$btn2.Text = "2. Fix Spooler Dependency"
$btn2.Location = New-Object System.Drawing.Point(20, 90)
$btn2.Size = New-Object System.Drawing.Size(540, 40)
$btn2.Add_Click({ Reset-SpoolerDependency })
$formMain.Controls.Add($btn2)

$btn3 = New-Object System.Windows.Forms.Button
$btn3.Text = "3. Remove All Printers"
$btn3.Location = New-Object System.Drawing.Point(20, 140)
$btn3.Size = New-Object System.Drawing.Size(540, 40)
$btn3.Add_Click({ Remove-AllPrinters })
$formMain.Controls.Add($btn3)

$btn4 = New-Object System.Windows.Forms.Button
$btn4.Text = "4. Remove Selected Drivers"
$btn4.Location = New-Object System.Drawing.Point(20, 190)
$btn4.Size = New-Object System.Drawing.Size(540, 40)
$btn4.Add_Click({ Remove-PrinterDrivers-Interactive })
$formMain.Controls.Add($btn4)

$btn5 = New-Object System.Windows.Forms.Button
$btn5.Text = "5. Reset Printer Policies (PointAndPrint)"
$btn5.Location = New-Object System.Drawing.Point(20, 240)
$btn5.Size = New-Object System.Drawing.Size(540, 40)
$btn5.Add_Click({ Reset-PrinterPolicies })
$formMain.Controls.Add($btn5)

$formMain.Add_FormClosing({ Write-Log "==== Session ended ====" })
[void]$formMain.ShowDialog()

# ==== END OF SCRIPT ====
