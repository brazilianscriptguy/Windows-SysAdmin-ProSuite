<#
.SYNOPSIS
    PowerShell GUI Tool for WSUS Cleanup and WID SQL Maintenance

.DESCRIPTION
    - Performs segmented WSUS cleanup operations via WSUS API
    - Allows optional execution of DBCC CHECKDB, REINDEX, SHRINK on WID (SUSDB)
    - Fully GUI-driven with logging, progress bar and CSV output

.AUTHOR
    Luiz Hamilton Silva – brazilianscriptguy

.VERSION
    Last Updated: July 9, 2025
#>

# Hide console
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

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

# Logging setup
$scriptName = "Maintain-WSUS-WID"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "C:\Logs-TEMP"
$logFile = Join-Path $logDir "$scriptName.log"
$csvFile = Join-Path $logDir "$scriptName-$timestamp.csv"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param ([string]$Message, [string]$Level = "INFO")
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Run-WIDSql {
    param ([string]$SqlQuery, [string]$Description, [System.Windows.Forms.Label]$Label, [System.Windows.Forms.ProgressBar]$Bar)

    try {
        $Label.Text = "Running SQL: $Description"
        Write-Log "Executing SQL: $Description"
        $cmd = "sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -E -Q `"$SqlQuery`""
        Invoke-Expression $cmd
        Write-Log "$Description completed."
        $Bar.PerformStep()
    } catch {
        Write-Log "$Description failed: $_" "ERROR"
    }
}

function Decline-Updates {
    param ([string]$Label, [scriptblock]$Filter, $ProgressLabel, $Bar)
    $ProgressLabel.Text = "Declining updates: $Label"
    $Bar.PerformStep()

    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $scope.FromCreationDate = (Get-Date).AddDays(-365)
    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter

    $results = @()
    foreach ($u in $updates) {
        try {
            $u.Decline()
            $results += [PSCustomObject]@{
                KB        = $u.KnowledgeBaseArticles -join ","
                Title     = $u.Title
                Category  = $Label
                CreatedOn = $u.CreationDate
            }
        } catch {
            Write-Log "Failed to decline update: $($u.Title)" "ERROR"
        }
    }
    Write-Log "Declined $($results.Count) updates under: $Label"
    return $results
}

function Run-WSUSCleanup {
    param ([string]$TaskName, [scriptblock]$ScopeFactory, $Label, $Bar)
    try {
        $Label.Text = "Cleaning: $TaskName"
        $scope = & $ScopeFactory
        $wsus.GetCleanupManager().PerformCleanup($scope)
        Write-Log "$TaskName cleanup completed."
        $Bar.PerformStep()
    } catch {
        Write-Log "$TaskName cleanup failed: $_" "ERROR"
    }
}

# GUI form
function Show-MaintenanceGUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS and WID Maintenance Tool"
    $form.Size = '600,350'
    $form.StartPosition = 'CenterScreen'

    $chkCompress = New-Object System.Windows.Forms.CheckBox
    $chkCompress.Text = "Include CompressUpdates"
    $chkCompress.Location = '10,10'; $chkCompress.Size = '300,20'
    $form.Controls.Add($chkCompress)

    $chkCheckDB = New-Object System.Windows.Forms.CheckBox
    $chkCheckDB.Text = "Run DBCC CHECKDB"
    $chkCheckDB.Location = '10,35'; $chkCheckDB.Size = '300,20'
    $chkCheckDB.Checked = $true
    $form.Controls.Add($chkCheckDB)

    $chkReindex = New-Object System.Windows.Forms.CheckBox
    $chkReindex.Text = "Reindex SUSDB"
    $chkReindex.Location = '10,60'; $chkReindex.Size = '300,20'
    $chkReindex.Checked = $true
    $form.Controls.Add($chkReindex)

    $chkShrink = New-Object System.Windows.Forms.CheckBox
    $chkShrink.Text = "Shrink SUSDB"
    $chkShrink.Location = '10,85'; $chkShrink.Size = '300,20'
    $chkShrink.Checked = $false
    $form.Controls.Add($chkShrink)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Status: Idle"
    $lblStatus.Location = '10,120'
    $lblStatus.Size = '560,20'
    $form.Controls.Add($lblStatus)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = '10,150'
    $progressBar.Size = '560,25'
    $progressBar.Minimum = 0
    $progressBar.Maximum = 10
    $progressBar.Value = 0
    $progressBar.Step = 1
    $form.Controls.Add($progressBar)

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "Run Maintenance"
    $btnRun.Location = '10,200'
    $btnRun.Size = '280,30'
    $btnRun.Add_Click({
        try {
            $global:wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
            Write-Log "`nStarting WSUS Maintenance..."

            $finalLog = @()
            $finalLog += Decline-Updates "Unapproved" {
                (-not $_.IsApproved) -and (-not $_.IsDeclined) -and ($_.CreationDate -lt (Get-Date).AddDays(-30))
            } $lblStatus $progressBar

            $finalLog += Decline-Updates "Expired" {
                $_.IsExpired -and -not $_.IsDeclined
            } $lblStatus $progressBar

            $finalLog += Decline-Updates "Superseded" {
                $_.IsSuperseded -and -not $_.IsDeclined
            } $lblStatus $progressBar

            Run-WSUSCleanup "Superseded Updates" { $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope; $s.DeclineSupersededUpdates = $true; $s } $lblStatus $progressBar
            Run-WSUSCleanup "Expired Updates"    { $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope; $s.DeclineExpiredUpdates    = $true; $s } $lblStatus $progressBar
            Run-WSUSCleanup "Obsolete Updates"   { $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope; $s.CleanupObsoleteUpdates = $true; $s } $lblStatus $progressBar
            Run-WSUSCleanup "Obsolete Computers" { $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope; $s.CleanupObsoleteComputers = $true; $s } $lblStatus $progressBar

            if ($chkCompress.Checked) {
                Run-WSUSCleanup "Compress Updates" { $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope; $s.CompressUpdates = $true; $s } $lblStatus $progressBar
            }

            if ($chkCheckDB.Checked) {
                Run-WIDSql -SqlQuery "USE SUSDB; DBCC CHECKDB;" -Description "DBCC CHECKDB" -Label $lblStatus -Bar $progressBar
            }

            if ($chkReindex.Checked) {
                Run-WIDSql -SqlQuery "USE SUSDB; EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (FILLFACTOR = 80)';" -Description "Reindex" -Label $lblStatus -Bar $progressBar
            }

            if ($chkShrink.Checked) {
                Run-WIDSql -SqlQuery "USE SUSDB; DBCC SHRINKDATABASE (SUSDB);" -Description "Shrink" -Label $lblStatus -Bar $progressBar
            }

            if ($finalLog.Count -gt 0) {
                $finalLog | Export-Csv -Path $csvFile -Encoding UTF8 -NoTypeInformation
                Write-Log "Exported log to $csvFile"
            }

            $lblStatus.Text = "All tasks completed."
            [System.Windows.Forms.MessageBox]::Show("Maintenance completed.", "Done", [System.Windows.Forms.MessageBoxButtons]::OK)
        } catch {
            Write-Log "Fatal error: $_" "ERROR"
            $lblStatus.Text = "Error: Check log."
            [System.Windows.Forms.MessageBox]::Show("A fatal error occurred. Check the log.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK)
        }
    })
    $form.Controls.Add($btnRun)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = '300,200'
    $btnClose.Size = '270,30'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $form.ShowDialog()
}

Show-MaintenanceGUI

# End of script
