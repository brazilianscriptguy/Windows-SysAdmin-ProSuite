<#
.SYNOPSIS
    PowerShell GUI for WSUS Cleanup and WID Database Maintenance

.DESCRIPTION
    - Declines superseded/expired/unapproved updates
    - Runs segmented WSUS cleanup via WSUS API
    - Adds SQL maintenance: DBCC CHECKDB, REINDEX, SHRINK for WID
    - Optional CompressUpdates toggle
    - All operations are GUI-driven with logging

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

# Load GUI libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Load WSUS API
[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")

# Setup log
$scriptName = "Maintain-WSUS-WID"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = "C:\Logs-TEMP"
$logFile = Join-Path $logDir "$scriptName.log"
$csvFile = Join-Path $logDir "$scriptName-$timestamp.csv"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

# SQL WID Execution
function Run-WIDSql {
    param (
        [string]$SqlQuery,
        [string]$Description
    )
    try {
        $cmd = @"
sqlcmd -S np:\\.\pipe\MICROSOFT##WID\tsql\query -E -Q "$SqlQuery"
"@
        Write-Log "Executing SQL: $Description"
        Invoke-Expression $cmd
        Write-Log "$Description completed."
    } catch {
        Write-Log "$Description failed: $_" "ERROR"
    }
}

# WSUS Cleanup logic
function Decline-Updates {
    param (
        [string]$Label,
        [scriptblock]$Filter
    )
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
    param (
        [string]$TaskName,
        [scriptblock]$ScopeFactory
    )
    try {
        $scope = & $ScopeFactory
        $wsus.GetCleanupManager().PerformCleanup($scope)
        Write-Log "$TaskName cleanup completed."
    } catch {
        Write-Log "$TaskName cleanup failed: $_" "ERROR"
    }
}

# GUI
function Show-MaintenanceGUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS and WID Maintenance Tool"
    $form.Size = '600,300'
    $form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choose your WSUS cleanup options:"
    $lbl.Location = '10,10'
    $lbl.Size = '550,20'
    $form.Controls.Add($lbl)

    $chkCompress = New-Object System.Windows.Forms.CheckBox
    $chkCompress.Text = "Include CompressUpdates (optional)"
    $chkCompress.Location = '10,40'
    $chkCompress.Size = '550,20'
    $form.Controls.Add($chkCompress)

    $chkReindex = New-Object System.Windows.Forms.CheckBox
    $chkReindex.Text = "Reindex WID SUSDB database"
    $chkReindex.Location = '10,70'
    $chkReindex.Size = '550,20'
    $chkReindex.Checked = $true
    $form.Controls.Add($chkReindex)

    $chkShrink = New-Object System.Windows.Forms.CheckBox
    $chkShrink.Text = "Shrink WID SUSDB database"
    $chkShrink.Location = '10,100'
    $chkShrink.Size = '550,20'
    $chkShrink.Checked = $false
    $form.Controls.Add($chkShrink)

    $chkCheckDB = New-Object System.Windows.Forms.CheckBox
    $chkCheckDB.Text = "Run DBCC CHECKDB on SUSDB"
    $chkCheckDB.Location = '10,130'
    $chkCheckDB.Size = '550,20'
    $chkCheckDB.Checked = $true
    $form.Controls.Add($chkCheckDB)

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = "Run Maintenance"
    $btnRun.Location = '10,180'
    $btnRun.Size = '280,30'
    $btnRun.Add_Click({
        try {
            $global:wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer("localhost", $false, 8530)
            Write-Log ""
            Write-Log "Starting WSUS maintenance..."

            $log1 = Decline-Updates "Unapproved" {
                (-not $_.IsApproved) -and (-not $_.IsDeclined) -and ($_.CreationDate -lt (Get-Date).AddDays(-30))
            }

            $log2 = Decline-Updates "Expired" {
                $_.IsExpired -and -not $_.IsDeclined
            }

            $log3 = Decline-Updates "Superseded" {
                $_.IsSuperseded -and -not $_.IsDeclined
            }

            Run-WSUSCleanup "Superseded Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.DeclineSupersededUpdates = $true; return $s
            }
            Start-Sleep -Seconds 2

            Run-WSUSCleanup "Expired Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.DeclineExpiredUpdates = $true; return $s
            }

            Run-WSUSCleanup "Obsolete Updates" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.CleanupObsoleteUpdates = $true; return $s
            }

            Run-WSUSCleanup "Obsolete Computers" {
                $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                $s.CleanupObsoleteComputers = $true; return $s
            }

            if ($chkCompress.Checked) {
                Run-WSUSCleanup "Compress Updates" {
                    $s = New-Object Microsoft.UpdateServices.Administration.CleanupScope
                    $s.CompressUpdates = $true; return $s
                }
            }

            if ($chkCheckDB.Checked) {
                Run-WIDSql -Description "DBCC CHECKDB" -SqlQuery "USE SUSDB; DBCC CHECKDB;"
            }

            if ($chkReindex.Checked) {
                Run-WIDSql -Description "Reindex" -SqlQuery "
USE SUSDB;
EXEC sp_MSforeachtable 'ALTER INDEX ALL ON ? REBUILD WITH (FILLFACTOR = 80);'
"
            }

            if ($chkShrink.Checked) {
                Run-WIDSql -Description "Shrink" -SqlQuery "
USE SUSDB;
DBCC SHRINKDATABASE (SUSDB)
"
            }

            $final = $log1 + $log2 + $log3
            if ($final.Count -gt 0) {
                $final | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
                Write-Log "Exported results to $csvFile"
            }

            [System.Windows.Forms.MessageBox]::Show("Maintenance completed. Review the logs and output.","Done",[System.Windows.Forms.MessageBoxButtons]::OK)
        } catch {
            Write-Log "Fatal error: $_" "ERROR"
            [System.Windows.Forms.MessageBox]::Show("A fatal error occurred. Check log.","Error",[System.Windows.Forms.MessageBoxButtons]::OK)
        }
    })
    $form.Controls.Add($btnRun)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "Close"
    $btnClose.Location = '310,180'
    $btnClose.Size = '250,30'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
}

Show-MaintenanceGUI

# End of script
