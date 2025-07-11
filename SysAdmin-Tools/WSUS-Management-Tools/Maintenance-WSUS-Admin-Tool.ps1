<#
.SYNOPSIS
    WSUS Update Source and Proxy Configuration Script

.DESCRIPTION
    A PowerShell script designed to configure the WSUS (Windows Server Update Services) server to utilize Microsoft Update as the upstream update source. 
    Optionally enables and configures proxy server settings for efficient update downloads. Requires the WSUS Administration Console components to be installed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 11, 2025
    Version: 1.0
#>

# Logging function (moved to top to ensure availability)
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$time] [$Level] $Message"
    $logDir = Join-Path $env:ProgramData "WSUS-GUI\Logs"
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $logDir "$scriptName-$timestamp.log"
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    if ($txtLog -and $txtLog.IsHandleCreated) {
        $txtLog.Invoke([Action]{ $txtLog.AppendText("$logMessage`r`n"); $txtLog.SelectionStart = $txtLog.TextLength; $txtLog.ScrollToCaret() })
    }
    if ($Level -in @("WARNING", "ERROR")) {
        $eventSource = "WSUSMaintenanceTool"
        if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
            New-EventLog -LogName Application -Source $eventSource
        }
        Write-EventLog -LogName Application -Source $eventSource -EventId 1000 -EntryType $Level -Message $logMessage
    }
}

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

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Attempt to load WSUS administration assembly
$wsusAssemblyPath = "C:\Windows\Microsoft.Net\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration\v4.0_4.0.0.0__31bf3856ad364e35\Microsoft.UpdateServices.Administration.dll"
try {
    $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
    if ($assembly) {
        Write-Log "WSUS Administration assembly loaded successfully from GAC." -Level INFO
    } else {
        throw "Assembly not loaded from GAC."
    }
} catch {
    Write-Log "Failed to load WSUS assembly from GAC: $_" -Level WARNING
    if (Test-Path $wsusAssemblyPath) {
        try {
            Add-Type -Path $wsusAssemblyPath -ErrorAction Stop
            Write-Log "WSUS Administration assembly loaded successfully from $wsusAssemblyPath." -Level INFO
        } catch {
            Write-Log "Error: Failed to load WSUS assembly from ${wsusAssemblyPath}: $_" -Level ERROR
            [System.Windows.Forms.MessageBox]::Show("Failed to load WSUS assembly. Ensure the WSUS Administration Console is installed.`nDetails: $_", "Error", 'OK', 'Error')
            exit 1
        }
    } else {
        Write-Log "Error: WSUS assembly not found at ${wsusAssemblyPath}. Ensure the WSUS Administration Console is installed." -Level ERROR
        [System.Windows.Forms.MessageBox]::Show("WSUS assembly not found at ${wsusAssemblyPath}. Ensure the WSUS Administration Console is installed.", "Error", 'OK', 'Error')
        exit 1
    }
}

# Verify AdminProxy type is available
if (-not ([Microsoft.UpdateServices.Administration.AdminProxy])) {
    Write-Log "Error: AdminProxy type not found after loading assembly." -Level ERROR
    [System.Windows.Forms.MessageBox]::Show("AdminProxy type not found. The WSUS Administration assembly may be corrupted or incompatible.", "Error", 'OK', 'Error')
    exit 1
}

# Logging and settings setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logDir = Join-Path $env:ProgramData "WSUS-GUI\Logs"
$logFile = Join-Path $logDir "$scriptName-$timestamp.log"
$csvFile = Join-Path $logDir "$scriptName-Declined-$timestamp.csv"
$backupDir = Join-Path $env:ProgramData "WSUS-GUI\Backups"
$settingsFile = Join-Path $env:APPDATA "WSUS-GUI\settings.json"
$sqlScriptDir = "C:\Scripts"  # Corrected to match your path
# Resolve sqlcmd.exe path from environment variables
$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
if (-not $sqlcmdPath) {
    Write-Log "sqlcmd.exe not found in environment variables. Please specify the full path manually." -Level ERROR
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Please install SQL Server tools or specify the path.", "Error", 'OK', 'Error')
    exit 1
}
Write-Log "Using sqlcmd.exe path: $sqlcmdPath" -Level INFO

# Ensure directories exist
foreach ($dir in @($logDir, $backupDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# Save and load settings
function Save-Settings {
    $settings = @{
        DeclineUnapproved   = $chkDeclineUnapproved.Checked
        DeclineExpired     = $chkDeclineExpired.Checked
        DeclineSuperseded  = $chkDeclineSuperseded.Checked
        CompressUpdates    = $chkCompress.Checked
        PurgeUnassigned    = $chkPurge.Checked
        RemoveClassifications = $chkRemoveClassifications.Checked
        CheckDB            = $chkCheckDB.Checked
        CheckFragmentation = $chkCheckFragmentation.Checked
        Reindex            = $chkReindex.Checked
        ShrinkDB           = $chkShrink.Checked
        BackupDB           = $chkBackup.Checked
        SelectedServer     = $comboServer.SelectedItem
    }
    $settings | ConvertTo-Json | Set-Content -Path $settingsFile -Force
}

function Load-Settings {
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        $chkDeclineUnapproved.Checked = $settings.DeclineUnapproved
        $chkDeclineExpired.Checked = $settings.DeclineExpired
        $chkDeclineSuperseded.Checked = $settings.DeclineSuperseded
        $chkCompress.Checked = $settings.CompressUpdates
        $chkPurge.Checked = $settings.PurgeUnassigned
        $chkRemoveClassifications.Checked = $settings.RemoveClassifications
        $chkCheckDB.Checked = $settings.CheckDB
        $chkCheckFragmentation.Checked = $settings.CheckFragmentation
        $chkReindex.Checked = $settings.Reindex
        $chkShrink.Checked = $settings.ShrinkDB
        $chkBackup.Checked = $settings.BackupDB
        if ($comboServer.Items.Contains($settings.SelectedServer)) {
            $comboServer.SelectedItem = $settings.SelectedServer
        }
    }
}

# Auto-discover WSUS servers
function Get-WSUSServers {
    $servers = @("localhost")
    try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $wsusServers = Get-ADObject -Filter {objectClass -eq "microsoftWSUS"} -Properties dNSHostName |
                       Select-Object -ExpandProperty dNSHostName
        if ($wsusServers) {
            $servers += $wsusServers
        }
        Write-Log "Discovered WSUS servers: $($servers -join ', ')" -Level INFO
    } catch {
        Write-Log "Failed to discover WSUS servers via AD: $_" -Level WARNING
    }
    return $servers
}

# Check WSUS connection
function Test-WSUSConnection {
    param (
        [string]$ServerName = "localhost",
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
        Write-Log "Successfully connected to WSUS server: $ServerName" -Level INFO
        return $wsus
    } catch {
        Write-Log "Failed to connect to WSUS server ($ServerName): $_" -Level ERROR
        throw
    }
}

# Maintenance function: Decline updates
function Decline-Updates {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Type,
        [Parameter(Mandatory=$true)]
        [scriptblock]$Filter,
        [Parameter(Mandatory=$true)]
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)

        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter

        if ($updates.Count -eq 0) {
            Write-Log "$Type updates: None found matching criteria." -Level INFO
            return @()
        }

        Write-Log "$Type updates: Found $($updates.Count) updates. Declining..." -Level INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Write-Log "Declined $Type update: $($update.Title)" -Level INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = $Type
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Write-Log "Failed to decline $Type update: $($update.Title) - $_" -Level ERROR
            }
        }
        return $log
    } catch {
        Write-Log "Error in Decline-Updates ($Type): $_" -Level ERROR
        throw
    }
}

# Maintenance function: Decline updates by classification
function Decline-ByClassification {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)

        $classifications = @("Itanium", "Windows XP")
        $updates = $wsus.SearchUpdates($scope) | Where-Object {
            $_.IsDeclined -eq $false -and ($_.Title -match ($classifications -join "|") -or $_.Description -match ($classifications -join "|"))
        }

        if ($updates.Count -eq 0) {
            Write-Log "Classification-based updates: None found matching criteria." -Level INFO
            return @()
        }

        Write-Log "Classification-based updates: Found $($updates.Count) updates. Declining..." -Level INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Write-Log "Declined classification-based update: $($update.Title)" -Level INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = "Classification"
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Write-Log "Failed to decline classification-based update: $($update.Title) - $_" -Level ERROR
            }
        }
        return $log
    } catch {
        Write-Log "Error in Decline-ByClassification: $_" -Level ERROR
        throw
    }
}

# Maintenance function: WSUS cleanup
function Run-WSUSCleanup {
    param (
        [Parameter(Mandatory=$true)]
        [bool]$IncludeCompress,
        [Parameter(Mandatory=$true)]
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $cleanup = $wsus.GetCleanupManager()
        $steps = @(
            [Microsoft.UpdateServices.Administration.CleanupScope]::SupersededUpdates,
            [Microsoft.UpdateServices.Administration.CleanupScope]::ExpiredUpdates,
            [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteUpdates,
            [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteComputers
        )
        if ($IncludeCompress) { $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::CompressUpdates }

        foreach ($step in $steps) {
            try {
                Write-Log "Running cleanup step: $step" -Level INFO
                $cleanup.PerformCleanup($step)
                Write-Log "Cleanup step '$step' completed." -Level INFO
            } catch {
                Write-Log "Cleanup step '$step' failed: $_" -Level ERROR
            }
        }
    } catch {
        Write-Log "Error in Run-WSUSCleanup: $_" -Level ERROR
        throw
    }
}

# Maintenance function: Purge unassigned files
function Purge-UnassignedFiles {
    param (
        [string]$WsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    )
    try {
        if (-not (Test-Path $WsusUtilPath)) {
            Write-Log "wsusutil.exe not found at $WsusUtilPath" -Level ERROR
            throw "wsusutil.exe not found"
        }
        Write-Log "Running wsusutil.exe reset to purge unassigned files..." -Level INFO
        $output = & $WsusUtilPath reset 2>&1
        Write-Log "wsusutil.exe reset output: $output" -Level INFO
    } catch {
        Write-Log "Error in Purge-UnassignedFiles: $_" -Level ERROR
        throw
    }
}

# Maintenance function: SQL WID operations
function Run-WIDMaintenance {
    param (
        [bool]$DoCheckDB,
        [bool]$DoCheckFragmentation,
        [bool]$DoReindex,
        [bool]$DoShrink,
        [bool]$DoBackup
    )
    try {
        $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"

        if ($DoBackup) {
            $backupFile = Join-Path $backupDir "SUSDB-Backup-$timestamp.bak"
            Write-Log "Backing up SUSDB to $backupFile..." -Level INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
            $output = & $sqlcmdPath $args 2>&1
            Write-Log "Backup output: $output" -Level INFO
        }

        if ($DoCheckDB) {
            Write-Log "Running DBCC CHECKDB..." -Level INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
            $output = & $sqlcmdPath $args 2>&1
            Write-Log "DBCC CHECKDB output: $output" -Level INFO
        }

        if ($DoCheckFragmentation) {
            $fragmentationScript = Join-Path $sqlScriptDir "wsus-verify-fragmentation.sql"
            if (Test-Path $fragmentationScript) {
                Write-Log "Checking index fragmentation with $fragmentationScript..." -Level INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Write-Log "Fragmentation check output: $output" -Level INFO
            } else {
                Write-Log "Fragmentation script not found at $fragmentationScript" -Level ERROR
            }
        }

        if ($DoReindex) {
            $reindexScript = Join-Path $sqlScriptDir "wsus-reindex.sql"
            if (Test-Path $reindexScript) {
                Write-Log "Reindexing with $reindexScript..." -Level INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Write-Log "Reindex output: $output" -Level INFO
            } else {
                Write-Log "Reindex script not found at $reindexScript" -Level ERROR
            }
        }

        if ($DoShrink) {
            Write-Log "Shrinking SUSDB..." -Level INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
            $output = & $sqlcmdPath $args 2>&1
            Write-Log "Shrink database output: $output" -Level INFO
        }
    } catch {
        Write-Log "Error in Run-WIDMaintenance: $_" -Level ERROR
        throw
    }
}

# Create scheduled task
function Create-ScheduledTask {
    try {
        $taskName = "WSUSMaintenanceTask"
        $scriptPath = $PSCommandPath
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "2:00AM"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Weekly WSUS Maintenance" -Force
        Write-Log "Scheduled task '$taskName' created successfully." -Level INFO
        [System.Windows.Forms.MessageBox]::Show("Scheduled task '$taskName' created successfully.", "Success", 'OK', 'Information')
    } catch {
        Write-Log "Failed to create scheduled task: $_" -Level ERROR
        [System.Windows.Forms.MessageBox]::Show("Failed to create scheduled task: $_", "Error", 'OK', 'Error')
    }
}

# GUI Window setup
$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS and WID Maintenance Tool"
$form.Size = New-Object System.Drawing.Size(620, 700)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)

# WSUS server selection
$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = "WSUS Server:"
$lblServer.Location = New-Object System.Drawing.Point(20, 20)
$lblServer.Size = New-Object System.Drawing.Size(100, 20)
$form.Controls.Add($lblServer)

$comboServer = New-Object System.Windows.Forms.ComboBox
$comboServer.Location = New-Object System.Drawing.Point(120, 20)
$comboServer.Size = New-Object System.Drawing.Size(470, 20)
$comboServer.DropDownStyle = 'DropDownList'
$comboServer.Items.AddRange((Get-WSUSServers))
$comboServer.SelectedIndex = 0
$form.Controls.Add($comboServer)

# WSUS maintenance group
$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Maintenance Options"
$groupWSUS.Size = New-Object System.Drawing.Size(570, 200)
$groupWSUS.Location = New-Object System.Drawing.Point(20, 50)
$form.Controls.Add($groupWSUS)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline unapproved updates (older than 30 days)"
$chkDeclineUnapproved.Location = New-Object System.Drawing.Point(15, 25)
$chkDeclineUnapproved.Width = 540
$groupWSUS.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline expired updates"
$chkDeclineExpired.Location = New-Object System.Drawing.Point(15, 50)
$chkDeclineExpired.Width = 540
$groupWSUS.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline superseded updates"
$chkDeclineSuperseded.Location = New-Object System.Drawing.Point(15, 75)
$chkDeclineSuperseded.Width = 540
$groupWSUS.Controls.Add($chkDeclineSuperseded)

$chkCompress = New-Object System.Windows.Forms.CheckBox
$chkCompress.Text = "Include compress updates (may take longer)"
$chkCompress.Location = New-Object System.Drawing.Point(15, 100)
$chkCompress.Width = 540
$groupWSUS.Controls.Add($chkCompress)

$chkPurge = New-Object System.Windows.Forms.CheckBox
$chkPurge.Text = "Purge unassigned update files (wsusutil reset)"
$chkPurge.Location = New-Object System.Drawing.Point(15, 125)
$chkPurge.Width = 540
$groupWSUS.Controls.Add($chkPurge)

$chkRemoveClassifications = New-Object System.Windows.Forms.CheckBox
$chkRemoveClassifications.Text = "Decline Itanium/Windows XP updates"
$chkRemoveClassifications.Location = New-Object System.Drawing.Point(15, 150)
$chkRemoveClassifications.Width = 540
$groupWSUS.Controls.Add($chkRemoveClassifications)

# SQL maintenance group
$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB (WID) SQL Maintenance"
$groupSQL.Size = New-Object System.Drawing.Size(570, 150)
$groupSQL.Location = New-Object System.Drawing.Point(20, 260)
$form.Controls.Add($groupSQL)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = "Backup SUSDB database"
$chkBackup.Location = New-Object System.Drawing.Point(15, 25)
$chkBackup.Width = 540
$groupSQL.Controls.Add($chkBackup)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = New-Object System.Drawing.Point(15, 50)
$chkCheckDB.Width = 540
$groupSQL.Controls.Add($chkCheckDB)

$chkCheckFragmentation = New-Object System.Windows.Forms.CheckBox
$chkCheckFragmentation.Text = "Check index fragmentation"
$chkCheckFragmentation.Location = New-Object System.Drawing.Point(15, 75)
$chkCheckFragmentation.Width = 540
$groupSQL.Controls.Add($chkCheckFragmentation)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild indexes with script"
$chkReindex.Location = New-Object System.Drawing.Point(15, 100)
$chkReindex.Width = 540
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink database"
$chkShrink.Location = New-Object System.Drawing.Point(15, 125)
$chkShrink.Width = 540
$groupSQL.Controls.Add($chkShrink)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 420)
$progress.Size = New-Object System.Drawing.Size(570, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 450)
$statusLabel.Size = New-Object System.Drawing.Size(570, 20)
$statusLabel.Text = "Ready to execute..."
$form.Controls.Add($statusLabel)

# Log output textbox
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 470)
$txtLog.Size = New-Object System.Drawing.Size(570, 100)
$txtLog.Multiline = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.ReadOnly = $true
$form.Controls.Add($txtLog)

# Execute button
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Maintenance"
$btnRun.Size = New-Object System.Drawing.Size(180, 35)
$btnRun.Location = New-Object System.Drawing.Point(20, 580)
$btnRun.Enabled = $true
$form.Controls.Add($btnRun)

# Schedule button
$btnSchedule = New-Object System.Windows.Forms.Button
$btnSchedule.Text = "Schedule Task"
$btnSchedule.Size = New-Object System.Drawing.Size(180, 35)
$btnSchedule.Location = New-Object System.Drawing.Point(220, 580)
$btnSchedule.Add_Click({ Create-ScheduledTask })
$form.Controls.Add($btnSchedule)

# Close button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = New-Object System.Drawing.Size(180, 35)
$btnClose.Location = New-Object System.Drawing.Point(410, 580)
$btnClose.Add_Click({ Save-Settings; $form.Close() })
$form.Controls.Add($btnClose)

# Runspace pool for background execution
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 4)
$runspacePool.Open()

# Execution logic
$btnRun.Add_Click({
    try {
        $btnRun.Enabled = $false
        $btnSchedule.Enabled = $false
        $progress.Value = 0
        $statusLabel.Text = "Starting WSUS maintenance..."
        $txtLog.Clear()
        Write-Log "Starting WSUS maintenance..." -Level INFO
        Save-Settings

        $selectedServer = $comboServer.SelectedItem
        # Pre-check WSUS connectivity
        Write-Log "Testing WSUS connection to $selectedServer..." -Level INFO
        $wsus = Test-WSUSConnection -ServerName $selectedServer
        Write-Log "WSUS connection test passed." -Level INFO

        $tasks = @()
        if ($chkDeclineUnapproved.Checked) { $tasks += "DeclineUnapproved" }
        if ($chkDeclineExpired.Checked) { $tasks += "DeclineExpired" }
        if ($chkDeclineSuperseded.Checked) { $tasks += "DeclineSuperseded" }
        if ($chkRemoveClassifications.Checked) { $tasks += "RemoveClassifications" }
        if ($chkCompress.Checked -or $tasks.Count -gt 0) { $tasks += "WSUSCleanup" }
        if ($chkPurge.Checked) { $tasks += "PurgeUnassigned" }
        if ($chkBackup.Checked) { $tasks += "BackupDB" }
        if ($chkCheckDB.Checked) { $tasks += "CheckDB" }
        if ($chkCheckFragmentation.Checked) { $tasks += "CheckFragmentation" }
        if ($chkReindex.Checked) { $tasks += "Reindex" }
        if ($chkShrink.Checked) { $tasks += "ShrinkDB" }

        $totalTasks = $tasks.Count
        if ($totalTasks -eq 0) {
            Write-Log "No tasks selected." -Level WARNING
            $statusLabel.Text = "No tasks selected."
            [System.Windows.Forms.MessageBox]::Show("Please select at least one maintenance task.", "Warning", 'OK', 'Warning')
            return
        }

        $progress.Maximum = $totalTasks * 100
        $progressStep = 100 / $totalTasks
        $currentStep = 0
        $declined = @()

        # Define runspace script block with all required functions
        $runspace = [PowerShell]::Create().AddScript({
            param($Tasks, $SelectedServer, $ChkCompress, $ChkPurge, $ChkRemoveClassifications, $ChkBackup, $ChkCheckDB, $ChkCheckFragmentation, $ChkReindex, $ChkShrink, $CsvFile, $LogFile, $BackupDir, $SqlScriptDir, $SqlcmdPath, $WsusAssemblyPath)

            # Load WSUS assembly in runspace
            try {
                $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
                if (-not $assembly) {
                    throw "Failed to load assembly from GAC."
                }
                Write-Log "WSUS Administration assembly loaded in runspace from GAC." -Level INFO
            } catch {
                Write-Log "Failed to load WSUS assembly from GAC in runspace: $_" -Level WARNING
                if (Test-Path $WsusAssemblyPath) {
                    try {
                        Add-Type -Path $WsusAssemblyPath -ErrorAction Stop
                        Write-Log "WSUS Administration assembly loaded in runspace from $WsusAssemblyPath." -Level INFO
                    } catch {
                        Write-Log "Error: Failed to load WSUS assembly from ${WsusAssemblyPath} in runspace: $_" -Level ERROR
                        throw
                    }
                } else {
                    Write-Log "Error: WSUS assembly not found at ${WsusAssemblyPath} in runspace." -Level ERROR
                    throw
                }
            }

            # Define Write-Log within runspace
            function Write-Log {
                param (
                    [Parameter(Mandatory=$true)]
                    [string]$Message,
                    [ValidateSet("INFO", "WARNING", "ERROR")]
                    [string]$Level = "INFO"
                )
                $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $logMessage = "[$time] [$Level] $Message"
                Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
            }

            # Define Test-WSUSConnection
            function Test-WSUSConnection {
                param (
                    [string]$ServerName = "localhost",
                    [int]$Port = 8530,
                    [bool]$UseSSL = $false
                )
                try {
                    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
                    Write-Log "Successfully connected to WSUS server: $ServerName" -Level INFO
                    return $wsus
                } catch {
                    Write-Log "Failed to connect to WSUS server ($ServerName): $_" -Level ERROR
                    throw
                }
            }

            # Define Decline-Updates
            function Decline-Updates {
                param (
                    [Parameter(Mandatory=$true)]
                    [string]$Type,
                    [Parameter(Mandatory=$true)]
                    [scriptblock]$Filter,
                    [Parameter(Mandatory=$true)]
                    [string]$ServerName,
                    [int]$Port = 8530,
                    [bool]$UseSSL = $false
                )
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)

                    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter

                    if ($updates.Count -eq 0) {
                        Write-Log "$Type updates: None found matching criteria." -Level INFO
                        return @()
                    }

                    Write-Log "$Type updates: Found $($updates.Count) updates. Declining..." -Level INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Write-Log "Declined $Type update: $($update.Title)" -Level INFO
                            $log += [PSCustomObject]@{
                                KB          = $update.KnowledgeBaseArticles -join ","
                                Title       = $update.Title
                                Type        = $Type
                                Date        = $update.CreationDate
                                DeclinedOn  = Get-Date
                                Server      = $ServerName
                            }
                        } catch {
                            Write-Log "Failed to decline $Type update: $($update.Title) - $_" -Level ERROR
                        }
                    }
                    return $log
                } catch {
                    Write-Log "Error in Decline-Updates ($Type): $_" -Level ERROR
                    throw
                }
            }

            # Define Decline-ByClassification
            function Decline-ByClassification {
                param (
                    [Parameter(Mandatory=$true)]
                    [string]$ServerName,
                    [int]$Port = 8530,
                    [bool]$UseSSL = $false
                )
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)

                    $classifications = @("Itanium", "Windows XP")
                    $updates = $wsus.SearchUpdates($scope) | Where-Object {
                        $_.IsDeclined -eq $false -and ($_.Title -match ($classifications -join "|") -or $_.Description -match ($classifications -join "|"))
                    }

                    if ($updates.Count -eq 0) {
                        Write-Log "Classification-based updates: None found matching criteria." -Level INFO
                        return @()
                    }

                    Write-Log "Classification-based updates: Found $($updates.Count) updates. Declining..." -Level INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Write-Log "Declined classification-based update: $($update.Title)" -Level INFO
                            $log += [PSCustomObject]@{
                                KB          = $update.KnowledgeBaseArticles -join ","
                                Title       = $update.Title
                                Type        = "Classification"
                                Date        = $update.CreationDate
                                DeclinedOn  = Get-Date
                                Server      = $ServerName
                            }
                        } catch {
                            Write-Log "Failed to decline classification-based update: $($update.Title) - $_" -Level ERROR
                        }
                    }
                    return $log
                } catch {
                    Write-Log "Error in Decline-ByClassification: $_" -Level ERROR
                    throw
                }
            }

            # Define Run-WSUSCleanup
            function Run-WSUSCleanup {
                param (
                    [Parameter(Mandatory=$true)]
                    [bool]$IncludeCompress,
                    [Parameter(Mandatory=$true)]
                    [string]$ServerName,
                    [int]$Port = 8530,
                    [bool]$UseSSL = $false
                )
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $cleanup = $wsus.GetCleanupManager()
                    $steps = @(
                        [Microsoft.UpdateServices.Administration.CleanupScope]::SupersededUpdates,
                        [Microsoft.UpdateServices.Administration.CleanupScope]::ExpiredUpdates,
                        [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteUpdates,
                        [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteComputers
                    )
                    if ($IncludeCompress) { $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::CompressUpdates }

                    foreach ($step in $steps) {
                        try {
                            Write-Log "Running cleanup step: $step" -Level INFO
                            $cleanup.PerformCleanup($step)
                            Write-Log "Cleanup step '$step' completed." -Level INFO
                        } catch {
                            Write-Log "Cleanup step '$step' failed: $_" -Level ERROR
                        }
                    }
                } catch {
                    Write-Log "Error in Run-WSUSCleanup: $_" -Level ERROR
                    throw
                }
            }

            # Define Purge-UnassignedFiles
            function Purge-UnassignedFiles {
                param (
                    [string]$WsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
                )
                try {
                    if (-not (Test-Path $WsusUtilPath)) {
                        Write-Log "wsusutil.exe not found at $WsusUtilPath" -Level ERROR
                        throw "wsusutil.exe not found"
                    }
                    Write-Log "Running wsusutil.exe reset to purge unassigned files..." -Level INFO
                    $output = & $WsusUtilPath reset 2>&1
                    Write-Log "wsusutil.exe reset output: $output" -Level INFO
                } catch {
                    Write-Log "Error in Purge-UnassignedFiles: $_" -Level ERROR
                    throw
                }
            }

            # Define Run-WIDMaintenance
            function Run-WIDMaintenance {
                param (
                    [bool]$DoCheckDB,
                    [bool]$DoCheckFragmentation,
                    [bool]$DoReindex,
                    [bool]$DoShrink,
                    [bool]$DoBackup
                )
                try {
                    $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"

                    if ($DoBackup) {
                        $backupFile = Join-Path $BackupDir "SUSDB-Backup-$((Get-Date).ToString('yyyyMMdd_HHmmss')).bak"
                        Write-Log "Backing up SUSDB to $backupFile..." -Level INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
                        $output = & $SqlcmdPath $args 2>&1
                        Write-Log "Backup output: $output" -Level INFO
                    }

                    if ($DoCheckDB) {
                        Write-Log "Running DBCC CHECKDB..." -Level INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
                        $output = & $SqlcmdPath $args 2>&1
                        Write-Log "DBCC CHECKDB output: $output" -Level INFO
                    }

                    if ($DoCheckFragmentation) {
                        $fragmentationScript = Join-Path $SqlScriptDir "wsus-verify-fragmentation.sql"
                        if (Test-Path $fragmentationScript) {
                            Write-Log "Checking index fragmentation with $fragmentationScript..." -Level INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Write-Log "Fragmentation check output: $output" -Level INFO
                        } else {
                            Write-Log "Fragmentation script not found at $fragmentationScript" -Level ERROR
                        }
                    }

                    if ($DoReindex) {
                        $reindexScript = Join-Path $SqlScriptDir "wsus-reindex.sql"
                        if (Test-Path $reindexScript) {
                            Write-Log "Reindexing with $reindexScript..." -Level INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Write-Log "Reindex output: $output" -Level INFO
                        } else {
                            Write-Log "Reindex script not found at $reindexScript" -Level ERROR
                        }
                    }

                    if ($DoShrink) {
                        Write-Log "Shrinking SUSDB..." -Level INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
                        $output = & $SqlcmdPath $args 2>&1
                        Write-Log "Shrink database output: $output" -Level INFO
                    }
                } catch {
                    Write-Log "Error in Run-WIDMaintenance: $_" -Level ERROR
                    throw
                }
            }

            # Runspace execution logic
            $ErrorActionPreference = 'Stop'
            $declined = @()
            Write-Log "Runspace started for tasks: $($Tasks -join ', ')" -Level INFO

            foreach ($task in $Tasks) {
                if ($task -eq "DeclineUnapproved") {
                    $declined += Decline-Updates -Type "Unapproved" -Filter { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) } -ServerName $SelectedServer
                }
                if ($task -eq "DeclineExpired") {
                    $declined += Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined } -ServerName $SelectedServer
                }
                if ($task -eq "DeclineSuperseded") {
                    $declined += Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined } -ServerName $SelectedServer
                }
                if ($task -eq "RemoveClassifications") {
                    $declined += Decline-ByClassification -ServerName $SelectedServer
                }
                if ($task -eq "WSUSCleanup") {
                    Run-WSUSCleanup -IncludeCompress $ChkCompress -ServerName $SelectedServer
                }
                if ($task -eq "PurgeUnassigned") {
                    Purge-UnassignedFiles
                }
                if ($task -in @("BackupDB", "CheckDB", "CheckFragmentation", "Reindex", "ShrinkDB")) {
                    Run-WIDMaintenance -DoBackup ($task -eq "BackupDB" -and $ChkBackup) -DoCheckDB ($task -eq "CheckDB" -and $ChkCheckDB) -DoCheckFragmentation ($task -eq "CheckFragmentation" -and $ChkCheckFragmentation) -DoReindex ($task -eq "Reindex" -and $ChkReindex) -DoShrink ($task -eq "ShrinkDB" -and $ChkShrink)
                }
            }

            if ($declined.Count -gt 0) {
                $declined | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
            }
            Write-Log "Runspace execution completed." -Level INFO
            return $declined
        }).AddArgument($tasks).AddArgument($selectedServer).AddArgument($chkCompress.Checked).AddArgument($chkPurge.Checked).AddArgument($chkRemoveClassifications.Checked).AddArgument($chkBackup.Checked).AddArgument($chkCheckDB.Checked).AddArgument($chkCheckFragmentation.Checked).AddArgument($chkReindex.Checked).AddArgument($chkShrink.Checked).AddArgument($csvFile).AddArgument($logFile).AddArgument($backupDir).AddArgument($sqlScriptDir).AddArgument($sqlcmdPath).AddArgument($wsusAssemblyPath)
        $runspace.RunspacePool = $runspacePool
        $handle = $runspace.BeginInvoke()

        while (-not $handle.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $currentStep += $progressStep / 10
            $progress.Value = [Math]::Min([int]($currentStep * 100), $progress.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }

        $result = $runspace.EndInvoke($handle)
        $runspace.Dispose()

        if ($result) {
            Write-Log "Declined updates exported to $csvFile" -Level INFO
        }

        $progress.Value = $progress.Maximum
        $statusLabel.Text = "Maintenance complete. Log saved to $logFile"
        Write-Log "Maintenance complete." -Level INFO
        [System.Windows.Forms.MessageBox]::Show("Maintenance completed successfully.`nLog: $logFile`nCSV: $csvFile", "Complete", 'OK', 'Information')
    } catch {
        Write-Log "Execution failed: $_" -Level ERROR
        $statusLabel.Text = "Maintenance failed. Check log for details."
        [System.Windows.Forms.MessageBox]::Show("Maintenance failed: $_`nLog: $logFile", "Error", 'OK', 'Error')
    } finally {
        $btnRun.Enabled = $true
        $btnSchedule.Enabled = $true
    }
})

# Load settings and show GUI
try {
    Load-Settings
    Write-Log "Starting WSUS Maintenance GUI" -Level INFO
    [void]$form.ShowDialog()
    Write-Log "WSUS Maintenance GUI closed" -Level INFO
} finally {
    Save-Settings
    $runspacePool.Close()
    $runspacePool.Dispose()
}

# End of script
