<#
.SYNOPSIS
    PowerShell GUI for ReaQta Component Cleanup

.DESCRIPTION
    This script removes ReaQta services, drivers, folders, and registry keys,
    and optionally runs SFC and DISM scans, then reboots the machine. User can
    choose which actions to perform and review the logs directly from the GUI.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: June 4, 2025
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$logPath = "C:\Logs-TEMP\RemoveRQTServices.log"
if (-not (Test-Path 'C:\Logs-TEMP')) {
    New-Item -Path 'C:\Logs-TEMP' -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $logPath -Value $entry
}

function Remove-ServiceAndFiles {
    Write-Log "Stopping and deleting ReaQta services"
    $services = @("keeper", "rqtsentry", "rqtnetsentry", "i00")
    foreach ($svc in $services) {
        try {
            sc.exe stop $svc | Out-Null
            sc.exe delete $svc | Out-Null
            Write-Log "Service '$svc' stopped and deleted."
        } catch {
            Write-Log "Failed to remove service '$svc' - $_" "WARNING"
        }
    }

    Write-Log "Deleting driver files"
    $drivers = @(
        "C:\Windows\System32\drivers\rqtsentry.sys",
        "C:\Windows\System32\drivers\rqtnetsentry.sys",
        "C:\Windows\System32\drivers\i00.sys"
    )
    foreach ($file in $drivers) {
        if (Test-Path $file) {
            try {
                Remove-Item -Path $file -Force
                Write-Log "Deleted file: $file"
            } catch {
                Write-Log "Failed to delete: $file - $_" "ERROR"
            }
        } else {
            Write-Log "File not found: $file"
        }
    }

    if (Test-Path 'C:\Program Files\ReaQta') {
        try {
            Remove-Item -Path 'C:\Program Files\ReaQta' -Recurse -Force
            Write-Log "Deleted ReaQta folder"
        } catch {
            Write-Log "Failed to delete ReaQta folder - $_" "ERROR"
        }
    } else {
        Write-Log "ReaQta folder not found"
    }

    Write-Log "Deleting registry keys"
    $keys = @(
        "HKLM:\SOFTWARE\RqtHive",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{E6686B07-5D7E-4BF6-B19C-2A5213D9E7AB}",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{BD5446C0-6BAC-4EC7-9D91-2D260DB724F9}"
    )
    foreach ($key in $keys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Log "Deleted registry key: $key"
            } catch {
                Write-Log "Failed to delete registry key: $key - $_" "WARNING"
            }
        } else {
            Write-Log "Registry key not found: $key"
        }
    }
}

function Run-SFC {
    Write-Log "Running SFC scan"
    Start-Process powershell -ArgumentList 'sfc /scannow' -Verb runAs -Wait
}

function Run-DISM {
    Write-Log "Running DISM scan"
    Start-Process powershell -ArgumentList 'dism /online /cleanup-image /restorehealth' -Verb runAs -Wait
}

function Reboot-System {
    Write-Log "Scheduling reboot in 15 seconds"
    shutdown.exe /r /t 15 /f
}

function Show-GUI {
    $form = New-Object Windows.Forms.Form
    $form.Text = "ReaQta Removal Tool"
    $form.Size = '650,600'
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $cbSFC = New-Object Windows.Forms.CheckBox
    $cbSFC.Text = "Run System File Checker (SFC)"
    $cbSFC.Location = '20,20'
    $cbSFC.Size = '300,25'
    $form.Controls.Add($cbSFC)

    $cbDISM = New-Object Windows.Forms.CheckBox
    $cbDISM.Text = "Run DISM RestoreHealth"
    $cbDISM.Location = '20,50'
    $cbDISM.Size = '300,25'
    $form.Controls.Add($cbDISM)

    $cbReboot = New-Object Windows.Forms.CheckBox
    $cbReboot.Text = "Reboot after cleanup"
    $cbReboot.Location = '20,80'
    $cbReboot.Size = '300,25'
    $cbReboot.Checked = $true
    $form.Controls.Add($cbReboot)

    $logViewer = New-Object Windows.Forms.TextBox
    $logViewer.Multiline = $true
    $logViewer.ScrollBars = 'Vertical'
    $logViewer.Size = '600,350'
    $logViewer.Location = '20,120'
    $logViewer.ReadOnly = $true
    $form.Controls.Add($logViewer)

    $btnRun = New-Object Windows.Forms.Button
    $btnRun.Text = "Start Cleanup"
    $btnRun.Location = '20,490'
    $btnRun.Size = '140,35'
    $btnRun.BackColor = 'LightGreen'
    $btnRun.Add_Click({
            Remove-ServiceAndFiles
            if ($cbSFC.Checked) { Run-SFC }
            if ($cbDISM.Checked) { Run-DISM }
            $logViewer.Lines = Get-Content -Path $logPath -ErrorAction SilentlyContinue
            if ($cbReboot.Checked) {
                [System.Windows.Forms.MessageBox]::Show("System will reboot in 15 seconds.", "Reboot", 'OK', 'Information')
                Reboot-System
            }
        })
    $form.Controls.Add($btnRun)

    $btnRefresh = New-Object Windows.Forms.Button
    $btnRefresh.Text = "Refresh Log"
    $btnRefresh.Location = '180,490'
    $btnRefresh.Size = '140,35'
    $btnRefresh.Add_Click({
            $logViewer.Lines = Get-Content -Path $logPath -ErrorAction SilentlyContinue
        })
    $form.Controls.Add($btnRefresh)

    $btnClose = New-Object Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = '340,490'
    $btnClose.Size = '140,35'
    $btnClose.BackColor = 'LightCoral'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $form.Add_Shown({ $logViewer.Lines = Get-Content -Path $logPath -ErrorAction SilentlyContinue })
    [void]$form.ShowDialog()
}

Show-GUI

# End of script
