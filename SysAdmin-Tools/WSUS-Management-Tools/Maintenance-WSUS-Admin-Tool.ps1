<#
.SYNOPSIS
    WSUS Maintenance GUI Tool with WID SQL Options

.DESCRIPTION
    A complete GUI-driven script to maintain WSUS and optionally perform
    SQL maintenance tasks on the SUSDB (Windows Internal Database).

.AUTHOR
    Luiz Hamilton Silva - brazilianscriptguy

.VERSION
    Last Updated: July 2025
#>

# Hide Console Window
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
[System.Windows.Forms.Application]::EnableVisualStyles()

# Logging setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "C:\Logs-TEMP"
$logFile = "$logDir\$scriptName-$timestamp.log"
$csvFile = "$logDir\$scriptName-Declined-$timestamp.csv"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param ([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$time] $Message"
}

# --- Maintenance Functions ---

function Decline-Updates {
    param (
        [string]$Type,
        [scriptblock]$Filter
    )

    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($wsusServer, $false, 8530)
    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $scope.FromCreationDate = (Get-Date).AddDays(-365)

    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
    $log = @()

    foreach ($update in $updates) {
        try {
            $update.Decline()
            $log += [PSCustomObject]@{
                KB     = $update.KnowledgeBaseArticles -join ","
                Title  = $update.Title
                Type   = $Type
                Date   = $update.CreationDate
            }
        } catch {
            Write-Log "Failed to decline: $($update.Title)"
        }
    }

    return $log
}

function Run-WSUSCleanup {
    param ([bool]$IncludeCompress)

    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($wsusServer, $false, 8530)
    $cleanup = $wsus.GetCleanupManager()

    $steps = @(
        "SupersededUpdates",
        "ExpiredUpdates",
        "ObsoleteUpdates",
        "ObsoleteComputers"
    )

    if ($IncludeCompress) {
        $steps += "CompressUpdates"
    }

    foreach ($step in $steps) {
        try {
            $scope = [Microsoft.UpdateServices.Administration.CleanupScope]::$step
            $cleanup.PerformCleanup($scope)
            Write-Log "Cleanup '$step' completed."
        } catch {
            Write-Log "Warning: Cleanup '$step' failed: $_"
        }
    }
}

function Run-WIDMaintenance {
    param (
        [bool]$DoCheckDB,
        [bool]$DoReindex,
        [bool]$DoShrink
    )

    $sqlcmd = "sqlcmd -S np:\\.\pipe\MSSQL$MICROSOFT##WID\tsql\query -E -d SUSDB -Q "

    if ($DoCheckDB) {
        Write-Log "Running DBCC CHECKDB..."
        Invoke-Expression "$sqlcmd `"DBCC CHECKDB`""
    }

    if ($DoReindex) {
        Write-Log "Rebuilding all indexes..."
        Invoke-Expression "$sqlcmd `"EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (FILLFACTOR = 80)'`""
    }

    if ($DoShrink) {
        Write-Log "Shrinking SUSDB..."
        Invoke-Expression "$sqlcmd `"DBCC SHRINKDATABASE (SUSDB, 10)`""
    }
}

# ---------------- GUI ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS and WID Maintenance Tool"
$form.Size = '620,540'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# WSUS Group
$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Maintenance Options"
$groupWSUS.Size = '570,120'
$groupWSUS.Location = '20,20'
$form.Controls.Add($groupWSUS)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline unapproved updates (older than 30 days)"
$chkDeclineUnapproved.Location = '15,25'
$chkDeclineUnapproved.Width = 540
$groupWSUS.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline expired updates"
$chkDeclineExpired.Location = '15,50'
$chkDeclineExpired.Width = 540
$groupWSUS.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline superseded updates"
$chkDeclineSuperseded.Location = '15,75'
$chkDeclineSuperseded.Width = 540
$groupWSUS.Controls.Add($chkDeclineSuperseded)

$chkCompress = New-Object System.Windows.Forms.CheckBox
$chkCompress.Text = "Include compress updates (WID may take longer)"
$chkCompress.Location = '15,100'
$chkCompress.Width = 540
$groupWSUS.Controls.Add($chkCompress)

# SQL Group
$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB (WID) SQL Maintenance"
$groupSQL.Size = '570,100'
$groupSQL.Location = '20,150'
$form.Controls.Add($groupSQL)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = '15,25'
$chkCheckDB.Width = 540
$groupSQL.Controls.Add($chkCheckDB)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild indexes"
$chkReindex.Location = '15,50'
$chkReindex.Width = 540
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink database"
$chkShrink.Location = '15,75'
$chkShrink.Width = 540
$groupSQL.Controls.Add($chkShrink)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '20,270'; $progress.Size = '570,20'
$progress.Minimum = 0; $progress.Maximum = 100
$form.Controls.Add($progress)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = '20,295'; $statusLabel.Size = '570,20'
$statusLabel.Text = "Ready to execute..."
$form.Controls.Add($statusLabel)

# Execute button
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Maintenance"
$btnRun.Size = '270,35'; $btnRun.Location = '20,340'
$form.Controls.Add($btnRun)

# Close button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = '270,35'; $btnClose.Location = '320,340'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# Run Maintenance Logic
$btnRun.Add_Click({
    $progress.Value = 0
    $statusLabel.Text = "Starting maintenance..."
    $global:wsusServer = "localhost"

    [void][Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

    $declined = @()

    if ($chkDeclineUnapproved.Checked) {
        $statusLabel.Text = "Declining unapproved updates..."
        $progress.Value = 10
        $declined += Decline-Updates "Unapproved" { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) }
    }

    if ($chkDeclineExpired.Checked) {
        $statusLabel.Text = "Declining expired updates..."
        $progress.Value = 20
        $declined += Decline-Updates "Expired" { $_.IsExpired -and -not $_.IsDeclined }
    }

    if ($chkDeclineSuperseded.Checked) {
        $statusLabel.Text = "Declining superseded updates..."
        $progress.Value = 30
        $declined += Decline-Updates "Superseded" { $_.IsSuperseded -and -not $_.IsDeclined }
    }

    $statusLabel.Text = "Running WSUS cleanup..."
    $progress.Value = 50
    Run-WSUSCleanup -IncludeCompress:$chkCompress.Checked

    if ($chkCheckDB.Checked -or $chkReindex.Checked -or $chkShrink.Checked) {
        $statusLabel.Text = "Running SUSDB (WID) maintenance..."
        $progress.Value = 75
        Run-WIDMaintenance -DoCheckDB:$chkCheckDB.Checked -DoReindex:$chkReindex.Checked -DoShrink:$chkShrink.Checked
    }

    if ($declined.Count -gt 0) {
        $declined | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-Log "Declined updates exported to $csvFile"
    }

    $progress.Value = 100
    $statusLabel.Text = "Maintenance completed. Log saved to $logFile"
    [System.Windows.Forms.MessageBox]::Show("WSUS maintenance completed.`nLog saved to:`n$logFile", "Completed", 'OK', 'Information')
})

# Show the GUI
[void]$form.ShowDialog()

# Enf of script
