<#
.SYNOPSIS
    PowerShell GUI Tool for WSUS Cleanup and Optional SUSDB Maintenance (WID-based)

.DESCRIPTION
    Allows admins to selectively perform WSUS maintenance and optional SUSDB operations
    like DBCC CHECKDB, REINDEX, and SHRINK on Windows Internal Database (WID).
    Includes real-time logging, a progress bar, and exportable logs.

.AUTHOR
    Luiz Hamilton Silva – Adapted with UX enhancements

.VERSION
    Last Updated: July 2025
#>

# Hide Console
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
"@
[Window]::Hide()

# Load Libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Setup Log
$scriptName = "Maintain-WSUS-WithGUI"
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "$scriptName-$timestamp.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$time] $Message"
    Add-Content -Path $logPath -Value $entry
    $logBox.AppendText("$entry`r`n")
}

# GUI Components
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS + SUSDB Maintenance Tool"
$form.Size = '630,640'
$form.StartPosition = 'CenterScreen'

$y = 20

# Group: WSUS Cleanup Options
$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Cleanup Options"
$groupWSUS.Size = '580,120'
$groupWSUS.Location = "20,$y"
$form.Controls.Add($groupWSUS)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline unapproved updates over 30 days"
$chkDeclineUnapproved.Location = "10,20"; $chkDeclineUnapproved.Width = 550
$groupWSUS.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline expired updates"
$chkDeclineExpired.Location = "10,45"; $chkDeclineExpired.Width = 550
$groupWSUS.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline superseded updates"
$chkDeclineSuperseded.Location = "10,70"; $chkDeclineSuperseded.Width = 550
$groupWSUS.Controls.Add($chkDeclineSuperseded)

$chkCompress = New-Object System.Windows.Forms.CheckBox
$chkCompress.Text = "Include compress updates (may take longer on large WID)"
$chkCompress.Location = "10,95"; $chkCompress.Width = 550
$groupWSUS.Controls.Add($chkCompress)

# Group: SUSDB Options
$y += 140
$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB (WID) Maintenance"
$groupSQL.Size = '580,110'
$groupSQL.Location = "20,$y"
$form.Controls.Add($groupSQL)

$chkDBCC = New-Object System.Windows.Forms.CheckBox
$chkDBCC.Text = "Run DBCC CHECKDB"
$chkDBCC.Location = "10,20"; $chkDBCC.Width = 250
$groupSQL.Controls.Add($chkDBCC)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild all indexes"
$chkReindex.Location = "10,45"; $chkReindex.Width = 250
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink SUSDB database"
$chkShrink.Location = "10,70"; $chkShrink.Width = 250
$groupSQL.Controls.Add($chkShrink)

# Group: Progress + Log
$y += 130
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = "20,$y"; $progress.Size = '580,20'
$progress.Minimum = 0; $progress.Maximum = 100
$form.Controls.Add($progress)

$y += 30
$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.Size = '580,260'
$logBox.Location = "20,$y"
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

# Buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Maintenance"
$btnRun.Size = '180,30'; $btnRun.Location = '20,580'
$form.Controls.Add($btnRun)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = '180,30'; $btnClose.Location = '420,580'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# --- FUNCTION: SQLCMD Helper ---
function Run-SQLCMD {
    param([string]$SQL)

    $sqlcmd = "$env:ProgramFiles\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe"
    if (-not (Test-Path $sqlcmd)) {
        $sqlcmd = "sqlcmd.exe"  # fallback for installed path
    }

    & $sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -Q $SQL -b -E 2>&1
}

# --- FUNCTION: Cleanup WSUS ---
function Perform-WSUSCleanup {
    try {
        [void][Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)

        if ($chkDeclineUnapproved.Checked) {
            Write-Log "Declining unapproved updates older than 30 days..."
            $updates = $wsus.SearchUpdates($scope) | Where-Object {
                (-not $_.IsApproved) -and (-not $_.IsDeclined) -and $_.CreationDate -lt (Get-Date).AddDays(-30)
            }
            $updates | ForEach-Object { $_.Decline() }
            Write-Log "Declined $($updates.Count) unapproved updates."
        }

        if ($chkDeclineExpired.Checked) {
            Write-Log "Declining expired updates..."
            $updates = $wsus.SearchUpdates($scope) | Where-Object { $_.IsExpired -and -not $_.IsDeclined }
            $updates | ForEach-Object { $_.Decline() }
            Write-Log "Declined $($updates.Count) expired updates."
        }

        if ($chkDeclineSuperseded.Checked) {
            Write-Log "Declining superseded updates..."
            $updates = $wsus.SearchUpdates($scope) | Where-Object { $_.IsSuperseded -and -not $_.IsDeclined }
            $updates | ForEach-Object { $_.Decline() }
            Write-Log "Declined $($updates.Count) superseded updates."
        }

        Write-Log "Running WSUS cleanup tasks..."
        $cleanup = $wsus.GetCleanupManager()
        $cleanupScope = New-Object Microsoft.UpdateServices.Administration.CleanupScope
        $cleanupScope.CleanupObsoleteUpdates = $true
        $cleanupScope.CleanupObsoleteComputers = $true
        $cleanupScope.CleanupExpiredUpdates = $true
        $cleanupScope.CleanupSupersededUpdates = $true
        $cleanupScope.CompressUpdates = $chkCompress.Checked

        $result = $cleanup.PerformCleanup($cleanupScope)
        Write-Log "WSUS Cleanup complete."
    } catch {
        Write-Log "WSUS Cleanup error: $_"
    }
}

# --- FUNCTION: SQL Maintenance ---
function Perform-SQLMaintenance {
    if ($chkDBCC.Checked) {
        Write-Log "Running DBCC CHECKDB..."
        Run-SQLCMD "USE SUSDB; DBCC CHECKDB;" | Write-Log
    }
    if ($chkReindex.Checked) {
        Write-Log "Rebuilding indexes on SUSDB..."
        Run-SQLCMD "USE SUSDB; EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD';" | Write-Log
    }
    if ($chkShrink.Checked) {
        Write-Log "Shrinking SUSDB database..."
        Run-SQLCMD "USE SUSDB; DBCC SHRINKDATABASE('SUSDB');" | Write-Log
    }
}

# --- Main Execution Button ---
$btnRun.Add_Click({
    $progress.Value = 5
    Write-Log "Starting WSUS maintenance..."

    Perform-WSUSCleanup
    $progress.Value = 60

    if ($chkDBCC.Checked -or $chkReindex.Checked -or $chkShrink.Checked) {
        Write-Log "Starting SUSDB maintenance..."
        Perform-SQLMaintenance
    }

    $progress.Value = 100
    Write-Log "All selected maintenance completed."
})

# Run GUI
$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
