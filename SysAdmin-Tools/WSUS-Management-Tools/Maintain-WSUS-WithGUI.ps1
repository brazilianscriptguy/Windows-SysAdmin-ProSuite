<#
.SYNOPSIS
    PowerShell GUI Tool for WSUS Maintenance (WID-Compatible)

.DESCRIPTION
    Declines outdated, expired, and superseded updates.
    Executes safe WSUS cleanup operations segmented by type.
    Includes optional checkbox for CompressUpdates.
    Logs and exports results to CSV in C:\Logs-TEMP.

.AUTHOR
    Luiz Hamilton Silva – brazilianscriptguy

.VERSION
    Last Updated: July 9, 2025
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

# Load .NET GUI types
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Load WSUS assemblies
[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

# Setup log and output paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = 'C:\Logs-TEMP'
$csvPath = Join-Path $logDir "$scriptName-Results-$timestamp.csv"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Logging function
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$Level] $Message"
    Write-Host $entry
    Add-Content -Path "$logDir\$scriptName.log" -Value $entry -Encoding UTF8
}

# Decline WSUS updates
function Decline-Updates {
    param (
        [string]$Label,
        [scriptblock]$Filter
    )
    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $scope.FromCreationDate = (Get-Date).AddDays(-365)
    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
    $results = @()

    foreach ($update in $updates) {
        try {
            $update.Decline()
            $results += [PSCustomObject]@{
                KB        = $update.KnowledgeBaseArticles -join ","
                Title     = $update.Title
                Category  = $Label
                CreatedOn = $update.CreationDate
            }
        } catch {
            Write-Log "Failed to decline update: $($update.Title)" "ERROR"
        }
    }

    Write-Log "Declined $($results.Count) updates under category: $Label"
    return $results
}

# Execute WSUS cleanup operations
function Run-WSUSCleanup {
    param (
        [string]$TaskLabel,
        [scriptblock]$ScopeFactory
    )
    try {
        $scope = & $ScopeFactory
        $cleanup = $wsus.GetCleanupManager()
        $cleanup.PerformCleanup($scope)
        Write-Log "$TaskLabel cleanup completed successfully."
    } catch {
        Write-Log "$TaskLabel cleanup failed: $($_.Exception.Message)" "ERROR"
    }
}

# Main GUI
function Show-WSUSMaintenanceForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS Maintenance Tool"
    $form.Size = New-Object System.Drawing.Size(540, 250)
    $form.StartPosition = 'CenterScreen'

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Select cleanup options and click Run Maintenance."
    $label.Location = '10,10'
    $label.Size = '500,20'
    $form.Controls.Add($label)

    $chkCompress = New-Object System.Windows.Forms.CheckBox
    $chkCompress.Text = "Include CompressUpdates (not recommended for WID)"
    $chkCompress.Location = '10,40'
    $chkCompress.Size = '500,20'
    $chkCompress.Checked = $false
    $form.Controls.Add($chkCompress)

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "Run Maintenance"
    $btnRun.Location = '10,80'
    $btnRun.Size = '240,30'
    $btnRun.Add_Click({
        try {
            $global:wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
            Write-Log ""
            Write-Log "Starting WSUS maintenance on 'localhost'..."

            $log1 = Decline-Updates "Unapproved" {
                (-not $_.IsApproved) -and (-not $_.IsDeclined) -and ($_.CreationDate -lt (Get-Date).AddDays(-30))
            }

            $log2 = Decline-Updates "Expired" {
                $_.IsExpired -and -not $_.IsDeclined
            }

            $log3 = Decline-Updates "Superseded" {
                $_.IsSuperseded -and -not $_.IsDeclined
            }

            Write-Log "Executing cleanup operations..."

            Run-WSUSCleanup "Superseded Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.DeclineSupersededUpdates = $true; return $s
            }
            Start-Sleep -Seconds 5

            Run-WSUSCleanup "Expired Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.DeclineExpiredUpdates = $true; return $s
            }
            Start-Sleep -Seconds 5

            Run-WSUSCleanup "Obsolete Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.CleanupObsoleteUpdates = $true; return $s
            }
            Start-Sleep -Seconds 5

            Run-WSUSCleanup "Obsolete Computers" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.CleanupObsoleteComputers = $true; return $s
            }
            Start-Sleep -Seconds 5

            if ($chkCompress.Checked) {
                Run-WSUSCleanup "Compress Updates" {
                    $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                    $s.CompressUpdates = $true; return $s
                }
                Start-Sleep -Seconds 5
            } else {
                Write-Log "CompressUpdates cleanup skipped by user selection."
            }

            $final = $log1 + $log2 + $log3
            if ($final.Count -gt 0) {
                $final | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                Write-Log "Maintenance completed. Report saved to: $csvPath"
                [System.Windows.Forms.MessageBox]::Show("WSUS maintenance completed. Results saved to: $csvPath","Done",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
            } else {
                Write-Log "No updates were declined. No CSV report created."
                [System.Windows.Forms.MessageBox]::Show("No updates were declined. No report created.","Info",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
            }

        } catch {
            Write-Log "Unexpected error occurred: $_" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("WSUS error: $_","Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    $form.Controls.Add($btnRun)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = '270,80'
    $btnClose.Size = '240,30'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
}

# Launch GUI
Show-WSUSMaintenanceForm

# End of script
