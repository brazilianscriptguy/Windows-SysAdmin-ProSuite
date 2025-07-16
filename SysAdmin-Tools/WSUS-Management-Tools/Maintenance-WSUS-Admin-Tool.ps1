<#
.SYNOPSIS
    WSUS Update Source and Proxy Configuration Script

.DESCRIPTION
    A PowerShell script designed to configure the WSUS (Windows Server Update Services) server to utilize Microsoft Update as the upstream update source.
    Optionally enables and configures proxy server settings for efficient update downloads. Requires the WSUS Administration Console components to be installed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 16, 2025 09:10 AM -03
    Version: 2.6
#>

#region --- Global Setup and Logging

# Setup Logging with single consolidated file
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP\WSUS-GUI\Logs'
$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"  # Set once at script start: 20250716-0910
$logPath    = Join-Path $logDir "$scriptName-$timestamp.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$MessageType = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $Message"
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    Write-Host $entry
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

#endregion

#region --- Configuration

$global:Config = @{
    WsusAssemblyPath = "C:\Windows\Microsoft.Net\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration\v4.0_4.0.0.0__31bf3856ad364e35\Microsoft.UpdateServices.Administration.dll"
    SqlScriptDir     = "C:\Logs-TEMP\WSUS-GUI\Scripts"
    WsusUtilPath     = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    LogDir           = 'C:\Logs-TEMP\WSUS-GUI\Logs'
    BackupDir        = 'C:\Logs-TEMP\WSUS-GUI\Backups'
    CsvDir           = 'C:\Logs-TEMP\WSUS-GUI\CSV'
    SettingsFile     = 'C:\Logs-TEMP\WSUS-GUI\settings.json'
}

# Load or prompt for configuration
if (Test-Path $Config.SettingsFile) {
    $loadedConfig = Get-Content $Config.SettingsFile -Raw | ConvertFrom-Json
    foreach ($key in $loadedConfig.PSObject.Properties.Name) {
        if ($Config.ContainsKey($key)) {
            $Config[$key] = $loadedConfig.$key
        }
    }
} else {
    $formConfig = New-Object System.Windows.Forms.Form
    $formConfig.Text = "Configure Paths"
    $formConfig.Size = New-Object System.Drawing.Size(400, 200)
    $formConfig.StartPosition = 'CenterScreen'

    $lblWsusAssembly = New-Object System.Windows.Forms.Label; $lblWsusAssembly.Text = "WSUS Assembly Path:"; $lblWsusAssembly.Location = New-Object System.Drawing.Point(10, 20); $formConfig.Controls.Add($lblWsusAssembly)
    $txtWsusAssembly = New-Object System.Windows.Forms.TextBox; $txtWsusAssembly.Text = $Config.WsusAssemblyPath; $txtWsusAssembly.Location = New-Object System.Drawing.Point(150, 20); $txtWsusAssembly.Size = New-Object System.Drawing.Size(230, 20); $formConfig.Controls.Add($txtWsusAssembly)

    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = "Save"; $btnSave.Location = New-Object System.Drawing.Point(150, 150); $btnSave.Add_Click({
        $Config.WsusAssemblyPath = $txtWsusAssembly.Text
        $Config | ConvertTo-Json | Set-Content -Path $Config.SettingsFile -Force
        $formConfig.Close()
    }); $formConfig.Controls.Add($btnSave)

    [void]$formConfig.ShowDialog()
}

$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
if (-not $sqlcmdPath) {
    Log-Message "sqlcmd.exe not found. Please install SQL Server tools or specify the path." -MessageType ERROR
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Please install SQL Server tools or specify the path.", "Error", 'OK', 'Error')
    exit 1
}
Log-Message "Using sqlcmd.exe path: $sqlcmdPath" -MessageType INFO

# Ensure directories exist
foreach ($dir in @($Config.LogDir, $Config.BackupDir, $Config.CsvDir, $Config.SqlScriptDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

#endregion

#region --- Assembly Validation

function Validate-WSUSAssembly {
    $wsusAssemblyPath = $Config.WsusAssemblyPath
    try {
        $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if ($assembly) {
            Log-Message "WSUS Administration assembly loaded successfully from GAC." -MessageType INFO
            [System.Windows.Forms.MessageBox]::Show("WSUS Administration assembly loaded successfully from the Global Assembly Cache (GAC).", "Success", 'OK', 'Information')
            return
        } else {
            throw "Assembly not loaded from GAC."
        }
    } catch {
        Log-Message "Failed to load WSUS assembly from GAC: $_" -MessageType WARNING
    }

    if (Test-Path $wsusAssemblyPath) {
        try {
            Add-Type -Path $wsusAssemblyPath -ErrorAction Stop
            Log-Message "WSUS Administration assembly loaded successfully from $wsusAssemblyPath." -MessageType INFO
            [System.Windows.Forms.MessageBox]::Show("WSUS Administration assembly loaded successfully from path:`n$wsusAssemblyPath", "Success", 'OK', 'Information')
        } catch {
            $msg = "Error: Failed to load WSUS assembly from:`n$wsusAssemblyPath`n`nDetails: $_"
            Log-Message $msg -MessageType ERROR
            [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
            exit 1
        }
    } else {
        $msg = "WSUS assembly not found at:`n$wsusAssemblyPath`n`nEnsure the WSUS Administration Console is installed using one of the following methods:`n"
        $msg += "`n1. Server Manager:`n   - Add Roles and Features > Features > Windows Server Update Services > WSUS Tools"
        $msg += "`n2. PowerShell:`n   - Install-WindowsFeature -Name UpdateServices-UI"
        Log-Message "Error: WSUS assembly not found at $wsusAssemblyPath." -MessageType ERROR
        [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
        exit 1
    }
}

#endregion

#region --- Script Functions

function Save-Settings {
    $settings = @{
        DeclineUnapproved    = $chkDeclineUnapproved.Checked
        DeclineExpired      = $chkDeclineExpired.Checked
        DeclineSuperseded   = $chkDeclineSuperseded.Checked
        CompressUpdates     = $chkCompress.Checked
        PurgeUnassigned     = $chkPurge.Checked
        RemoveClassifications = $chkRemoveClassifications.Checked
        CheckDB             = $chkCheckDB.Checked
        CheckFragmentation  = $chkCheckFragmentation.Checked
        Reindex             = $chkReindex.Checked
        ShrinkDB            = $chkShrink.Checked
        BackupDB            = $chkBackup.Checked
        SelectedServer      = $comboServer.SelectedItem
        WsusAssemblyPath    = $Config.WsusAssemblyPath
        SqlScriptDir        = $Config.SqlScriptDir
        WsusUtilPath        = $Config.WsusUtilPath
    }
    $settings | ConvertTo-Json | Set-Content -Path $Config.SettingsFile -Force
}

function Load-Settings {
    if (Test-Path $Config.SettingsFile) {
        $settings = Get-Content $Config.SettingsFile -Raw | ConvertFrom-Json
        $chkDeclineUnapproved.Checked = if ($settings.DeclineUnapproved) { $settings.DeclineUnapproved } else { $false }
        $chkDeclineExpired.Checked = if ($settings.DeclineExpired) { $settings.DeclineExpired } else { $false }
        $chkDeclineSuperseded.Checked = if ($settings.DeclineSuperseded) { $settings.DeclineSuperseded } else { $false }
        $chkCompress.Checked = if ($settings.CompressUpdates) { $settings.CompressUpdates } else { $false }
        $chkPurge.Checked = if ($settings.PurgeUnassigned) { $settings.PurgeUnassigned } else { $false }
        $chkRemoveClassifications.Checked = if ($settings.RemoveClassifications) { $settings.RemoveClassifications } else { $false }
        $chkCheckDB.Checked = if ($settings.CheckDB) { $settings.CheckDB } else { $false }
        $chkCheckFragmentation.Checked = if ($settings.CheckFragmentation) { $settings.CheckFragmentation } else { $false }
        $chkReindex.Checked = if ($settings.Reindex) { $settings.Reindex } else { $false }
        $chkShrink.Checked = if ($settings.ShrinkDB) { $settings.ShrinkDB } else { $false }
        $chkBackup.Checked = if ($settings.BackupDB) { $settings.BackupDB } else { $false }
        if ($comboServer.Items.Contains($settings.SelectedServer)) {
            $comboServer.SelectedItem = $settings.SelectedServer
        }
        if ($settings.WsusAssemblyPath) { $Config.WsusAssemblyPath = $settings.WsusAssemblyPath }
        if ($settings.SqlScriptDir) { $Config.SqlScriptDir = $settings.SqlScriptDir }
        if ($settings.WsusUtilPath) { $Config.WsusUtilPath = $settings.WsusUtilPath }
    }
}

function Get-WSUSServers {
    $servers = @("localhost")
    try {
        if (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue) {
            Import-Module ActiveDirectory -ErrorAction Stop
            $wsusServers = Get-ADObject -Filter {objectClass -eq "microsoftWSUS"} -Properties dNSHostName | Select-Object -ExpandProperty dNSHostName -ErrorAction Stop
            if ($wsusServers) {
                $servers += $wsusServers
            }
            Log-Message "Discovered WSUS servers via AD: $($servers -join ', ')" -MessageType INFO
        } else {
            Log-Message "Active Directory module not available, using local server only." -MessageType WARNING
        }
    } catch {
        Log-Message "Failed to discover WSUS servers via AD: $_" -MessageType WARNING
    }
    return $servers | Sort-Object -Unique
}

function Test-WSUSConnection {
    param (
        [string]$ServerName = "localhost",
        [int]$Port = 8530,
        [bool]$UseSSL = $false,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2
    )
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
            if ($wsus -and ($wsus | Get-Member -Name "SearchUpdates" -MemberType Method)) {
                Log-Message "Successfully connected to WSUS server: $ServerName (Port: $Port, SSL: $UseSSL)" -MessageType INFO
                return $wsus
            }
            throw "WSUS connection validation failed."
        } catch {
            $retryCount++
            Log-Message "Failed to connect to WSUS server ($ServerName, Attempt $retryCount/$MaxRetries): $_" -MessageType WARNING
            if ($retryCount -ge $MaxRetries) {
                Log-Message "Max retries reached for WSUS connection to $ServerName" -MessageType ERROR
                throw
            }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    throw "Unexpected exit from Test-WSUSConnection"
}

function Decline-Updates {
    param (
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][scriptblock]$Filter,
        [Parameter(Mandatory=$true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)
        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
        if ($updates.Count -eq 0) {
            Log-Message "$Type updates: None found matching criteria." -MessageType INFO
            return @()
        }
        Log-Message "$Type updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Log-Message "Declined $Type update: $($update.Title)" -MessageType INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = $Type
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Log-Message "Failed to decline $Type update: $($update.Title) - $_" -MessageType ERROR
            }
        }
        return $log
    } catch {
        Log-Message "Error in Decline-Updates ($Type): $_" -MessageType ERROR
        throw
    }
}

function Decline-ByClassification {
    param (
        [Parameter(Mandatory=$true)][string]$ServerName,
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
            Log-Message "Classification-based updates: None found matching criteria." -MessageType INFO
            return @()
        }
        Log-Message "Classification-based updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Log-Message "Declined classification-based update: $($update.Title)" -MessageType INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = "Classification"
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Log-Message "Failed to decline classification-based update: $($update.Title) - $_" -MessageType ERROR
            }
        }
        return $log
    } catch {
        Log-Message "Error in Decline-ByClassification: $_" -MessageType ERROR
        throw
    }
}

function Run-WSUSCleanup {
    param (
        [Parameter(Mandatory=$true)][bool]$IncludeCompress,
        [Parameter(Mandatory=$true)][string]$ServerName,
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
        $success = $false
        foreach ($step in $steps) {
            try {
                Log-Message "Running cleanup step: $step" -MessageType INFO
                $cleanup.PerformCleanup($step)
                Log-Message "Cleanup step '$step' completed." -MessageType INFO
                $success = $true
            } catch {
                Log-Message "Cleanup step '$step' failed with assembly method: $_" -MessageType WARNING
            }
        }
        if (-not $success -and (Test-Path $Config.WsusUtilPath)) {
            Log-Message "Falling back to wsusutil.exe for cleanup..." -MessageType INFO
            $output = & $Config.WsusUtilPath deleteunneededrevisions 2>&1
            Log-Message "wsusutil.exe deleteunneededrevisions output: $output" -MessageType INFO
            if ($IncludeCompress) {
                $output = & $Config.WsusUtilPath compress 2>&1
                Log-Message "wsusutil.exe compress output: $output" -MessageType INFO
            }
            Log-Message "WSUS cleanup completed using wsusutil.exe." -MessageType INFO
        } elseif (-not $success) {
            Log-Message "Error: No cleanup method succeeded and wsusutil.exe not found at $($Config.WsusUtilPath)" -MessageType ERROR
            throw "Cleanup failed"
        }
    } catch {
        Log-Message "Error in Run-WSUSCleanup: $_" -MessageType ERROR
        throw
    }
}

function Purge-UnassignedFiles {
    param ([string]$WsusUtilPath = $Config.WsusUtilPath)
    try {
        if (-not (Test-Path $WsusUtilPath)) {
            Log-Message "wsusutil.exe not found at $WsusUtilPath" -MessageType ERROR
            throw "wsusutil.exe not found"
        }
        Log-Message "Running wsusutil.exe reset to purge unassigned files..." -MessageType INFO
        $output = & $WsusUtilPath reset 2>&1
        Log-Message "wsusutil.exe reset output: $output" -MessageType INFO
    } catch {
        Log-Message "Error in Purge-UnassignedFiles: $_" -MessageType ERROR
        throw
    }
}

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
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

        if ($DoBackup) {
            $backupFile = Join-Path $Config.BackupDir "SUSDB-Backup-$timestamp.bak"
            Log-Message "Backing up SUSDB to $backupFile..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "Backup output: $output" -MessageType INFO
        }

        if ($DoCheckDB) {
            Log-Message "Running DBCC CHECKDB..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "DBCC CHECKDB output: $output" -MessageType INFO
        }

        if ($DoCheckFragmentation) {
            $fragmentationScript = Join-Path $Config.SqlScriptDir "wsus-verify-fragmentation.sql"
            if (Test-Path $fragmentationScript) {
                Log-Message "Checking index fragmentation with $fragmentationScript..." -MessageType INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Log-Message "Fragmentation check output: $output" -MessageType INFO
            } else {
                Log-Message "Fragmentation script not found at $fragmentationScript" -MessageType WARNING
            }
        }

        if ($DoReindex) {
            $reindexScript = Join-Path $Config.SqlScriptDir "wsus-reindex.sql"
            if (Test-Path $reindexScript) {
                Log-Message "Reindexing with $reindexScript..." -MessageType INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Log-Message "Reindex output: $output" -MessageType INFO
            } else {
                Log-Message "Reindex script not found at $reindexScript" -MessageType WARNING
            }
        }

        if ($DoShrink) {
            Log-Message "Shrinking SUSDB..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "Shrink database output: $output" -MessageType INFO
        }
    } catch {
        Log-Message "Error in Run-WIDMaintenance: $_" -MessageType ERROR
        throw
    }
}

function Create-ScheduledTask {
    param ([string]$ScriptPath = $PSCommandPath, [string]$TaskName = "WSUSMaintenanceTask", [string]$Time = "02:00")
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $Time
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Weekly WSUS Maintenance" -Force
        Log-Message "Scheduled task '$TaskName' created successfully at $Time." -MessageType INFO
        [System.Windows.Forms.MessageBox]::Show("Scheduled task '$TaskName' created successfully at $Time.", "Success", 'OK', 'Information')
    } catch {
        Log-Message "Failed to create scheduled task: $_" -MessageType ERROR
        [System.Windows.Forms.MessageBox]::Show("Failed to create scheduled task: $_", "Error", 'OK', 'Error')
    }
}

#endregion

#region --- GUI Bootstrapping

$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS and WID Maintenance Tool"
$form.Size = New-Object System.Drawing.Size(620, 700)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)

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

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 420)
$progress.Size = New-Object System.Drawing.Size(570, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$form.Controls.Add($progress)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 450)
$statusLabel.Size = New-Object System.Drawing.Size(570, 20)
$statusLabel.Text = "Ready to execute..."
$form.Controls.Add($statusLabel)

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Location = New-Object System.Drawing.Point(20, 470)
$script:txtLog.Size = New-Object System.Drawing.Size(570, 100)
$script:txtLog.Multiline = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.ReadOnly = $true
$form.Controls.Add($script:txtLog)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run Maintenance"
$btnRun.Size = New-Object System.Drawing.Size(180, 35)
$btnRun.Location = New-Object System.Drawing.Point(20, 580)
$form.Controls.Add($btnRun)

$btnSchedule = New-Object System.Windows.Forms.Button
$btnSchedule.Text = "Schedule Task"
$btnSchedule.Size = New-Object System.Drawing.Size(180, 35)
$btnSchedule.Location = New-Object System.Drawing.Point(220, 580)
$btnSchedule.Add_Click({
    $timeForm = New-Object System.Windows.Forms.Form
    $timeForm.Text = "Schedule Time"
    $timeForm.Size = New-Object System.Drawing.Size(300, 150)
    $timeForm.StartPosition = 'CenterScreen'
    $lblTime = New-Object System.Windows.Forms.Label; $lblTime.Text = "Time (HH:MM):"; $lblTime.Location = New-Object System.Drawing.Point(10, 20); $timeForm.Controls.Add($lblTime)
    $txtTime = New-Object System.Windows.Forms.TextBox; $txtTime.Text = "02:00"; $txtTime.Location = New-Object System.Drawing.Point(100, 20); $timeForm.Controls.Add($txtTime)
    $btnSet = New-Object System.Windows.Forms.Button; $btnSet.Text = "Set"; $btnSet.Location = New-Object System.Drawing.Point(100, 70); $btnSet.Add_Click({ Create-ScheduledTask -Time $txtTime.Text; $timeForm.Close() }); $timeForm.Controls.Add($btnSet)
    [void]$timeForm.ShowDialog()
})
$form.Controls.Add($btnSchedule)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Size = New-Object System.Drawing.Size(180, 35)
$btnClose.Location = New-Object System.Drawing.Point(410, 580)
$btnClose.Add_Click({ Save-Settings; $form.Close() })
$form.Controls.Add($btnClose)

$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 4)
$runspacePool.Open()

$btnRun.Add_Click({
    try {
        $btnRun.Enabled = $false
        $btnSchedule.Enabled = $false
        $progress.Value = 0
        $statusLabel.Text = "Starting WSUS maintenance..."
        $script:txtLog.Clear()
        Log-Message "Starting WSUS maintenance..." -MessageType INFO
        Save-Settings

        # Validate WSUS assembly before proceeding
        Validate-WSUSAssembly

        $selectedServer = $comboServer.SelectedItem
        Log-Message "Testing WSUS connection to $selectedServer..." -MessageType INFO
        $wsus = Test-WSUSConnection -ServerName $selectedServer
        Log-Message "WSUS connection test passed." -MessageType INFO

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
            Log-Message "No tasks selected." -MessageType WARNING
            $statusLabel.Text = "No tasks selected."
            [System.Windows.Forms.MessageBox]::Show("Please select at least one maintenance task.", "Warning", 'OK', 'Warning')
            return
        }

        $progress.Maximum = $totalTasks * 100
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvFile = Join-Path $Config.CsvDir "$scriptName-Declined-$timestamp.csv"
        $declined = @()

        $runspace = [PowerShell]::Create().AddScript({
            param($Tasks, $SelectedServer, $ChkCompress, $ChkPurge, $ChkRemoveClassifications, $ChkBackup, $ChkCheckDB, $ChkCheckFragmentation, $ChkReindex, $ChkShrink, $CsvFile, $LogPath, $BackupDir, $SqlScriptDir, $SqlcmdPath, $WsusUtilPath, $WsusAssemblyPath)

            $ErrorActionPreference = 'Stop'
            $script:txtLog = $null

            function Log-Message {
                param ([string]$Message, [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")][string]$MessageType = "INFO")
                $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $entry = "[$stamp] [$MessageType] $Message"
                Add-Content -Path $LogPath -Value $entry -Encoding UTF8
            }

            function Test-WSUSConnection {
                param ([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
                    Log-Message "Successfully connected to WSUS server: $ServerName" -MessageType INFO
                    return $wsus
                } catch {
                    Log-Message "Failed to connect to WSUS server ($ServerName): $_" -MessageType ERROR
                    throw
                }
            }

            function Decline-Updates {
                param ([string]$Type, [scriptblock]$Filter, [string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)
                    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
                    if ($updates.Count -eq 0) { return @() }
                    Log-Message "$Type updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Log-Message "Declined $Type update: $($update.Title)" -MessageType INFO
                            $log += [PSCustomObject]@{ KB = $update.KnowledgeBaseArticles -join ","; Title = $update.Title; Type = $Type; Date = $update.CreationDate; DeclinedOn = Get-Date; Server = $ServerName }
                        } catch {
                            Log-Message "Failed to decline $Type update: $($update.Title) - $_" -MessageType ERROR
                        }
                    }
                    return $log
                } catch {
                    Log-Message "Error in Decline-Updates ($Type): $_" -MessageType ERROR
                    throw
                }
            }

            function Decline-ByClassification {
                param ([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)
                    $classifications = @("Itanium", "Windows XP")
                    $updates = $wsus.SearchUpdates($scope) | Where-Object { $_.IsDeclined -eq $false -and ($_.Title -match ($classifications -join "|") -or $_.Description -match ($classifications -join "|")) }
                    if ($updates.Count -eq 0) { return @() }
                    Log-Message "Classification-based updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Log-Message "Declined classification-based update: $($update.Title)" -MessageType INFO
                            $log += [PSCustomObject]@{ KB = $update.KnowledgeBaseArticles -join ","; Title = $update.Title; Type = "Classification"; Date = $update.CreationDate; DeclinedOn = Get-Date; Server = $ServerName }
                        } catch {
                            Log-Message "Failed to decline classification-based update: $($update.Title) - $_" -MessageType ERROR
                        }
                    }
                    return $log
                } catch {
                    Log-Message "Error in Decline-ByClassification: $_" -MessageType ERROR
                    throw
                }
            }

            function Run-WSUSCleanup {
                param ([bool]$IncludeCompress, [string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $cleanup = $wsus.GetCleanupManager()
                    $steps = @([Microsoft.UpdateServices.Administration.CleanupScope]::SupersededUpdates, [Microsoft.UpdateServices.Administration.CleanupScope]::ExpiredUpdates, [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteUpdates, [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteComputers)
                    if ($IncludeCompress) { $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::CompressUpdates }
                    $success = $false
                    foreach ($step in $steps) {
                        try {
                            Log-Message "Running cleanup step: $step" -MessageType INFO
                            $cleanup.PerformCleanup($step)
                            Log-Message "Cleanup step '$step' completed." -MessageType INFO
                            $success = $true
                        } catch {
                            Log-Message "Cleanup step '$step' failed with assembly method: $_" -MessageType WARNING
                        }
                    }
                    if (-not $success -and (Test-Path $WsusUtilPath)) {
                        Log-Message "Falling back to wsusutil.exe for cleanup..." -MessageType INFO
                        $output = & $WsusUtilPath deleteunneededrevisions 2>&1
                        Log-Message "wsusutil.exe deleteunneededrevisions output: $output" -MessageType INFO
                        if ($IncludeCompress) {
                            $output = & $WsusUtilPath compress 2>&1
                            Log-Message "wsusutil.exe compress output: $output" -MessageType INFO
                        }
                        Log-Message "WSUS cleanup completed using wsusutil.exe." -MessageType INFO
                    } elseif (-not $success) {
                        Log-Message "Error: No cleanup method succeeded and wsusutil.exe not found at $WsusUtilPath" -MessageType ERROR
                        throw "Cleanup failed"
                    }
                } catch {
                    Log-Message "Error in Run-WSUSCleanup: $_" -MessageType ERROR
                    throw
                }
            }

            function Purge-UnassignedFiles {
                param ([string]$WsusUtilPath)
                try {
                    if (-not (Test-Path $WsusUtilPath)) {
                        Log-Message "wsusutil.exe not found at $WsusUtilPath" -MessageType ERROR
                        throw "wsusutil.exe not found"
                    }
                    Log-Message "Running wsusutil.exe reset to purge unassigned files..." -MessageType INFO
                    $output = & $WsusUtilPath reset 2>&1
                    Log-Message "wsusutil.exe reset output: $output" -MessageType INFO
                } catch {
                    Log-Message "Error in Purge-UnassignedFiles: $_" -MessageType ERROR
                    throw
                }
            }

            function Run-WIDMaintenance {
                param ([bool]$DoCheckDB, [bool]$DoCheckFragmentation, [bool]$DoReindex, [bool]$DoShrink, [bool]$DoBackup)
                try {
                    $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"
                    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    if ($DoBackup) {
                        $backupFile = Join-Path $BackupDir "SUSDB-Backup-$timestamp.bak"
                        Log-Message "Backing up SUSDB to $backupFile..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "Backup output: $output" -MessageType INFO
                    }
                    if ($DoCheckDB) {
                        Log-Message "Running DBCC CHECKDB..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "DBCC CHECKDB output: $output" -MessageType INFO
                    }
                    if ($DoCheckFragmentation) {
                        $fragmentationScript = Join-Path $SqlScriptDir "wsus-verify-fragmentation.sql"
                        if (Test-Path $fragmentationScript) {
                            Log-Message "Checking index fragmentation with $fragmentationScript..." -MessageType INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Log-Message "Fragmentation check output: $output" -MessageType INFO
                        } else {
                            Log-Message "Fragmentation script not found at $fragmentationScript" -MessageType WARNING
                        }
                    }
                    if ($DoReindex) {
                        $reindexScript = Join-Path $SqlScriptDir "wsus-reindex.sql"
                        if (Test-Path $reindexScript) {
                            Log-Message "Reindexing with $reindexScript..." -MessageType INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Log-Message "Reindex output: $output" -MessageType INFO
                        } else {
                            Log-Message "Reindex script not found at $reindexScript" -MessageType WARNING
                        }
                    }
                    if ($DoShrink) {
                        Log-Message "Shrinking SUSDB..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "Shrink database output: $output" -MessageType INFO
                    }
                } catch {
                    Log-Message "Error in Run-WIDMaintenance: $_" -MessageType ERROR
                    throw
                }
            }

            $declined = @()
            Log-Message "Runspace started for tasks: $($Tasks -join ', ')" -MessageType INFO
            foreach ($task in $Tasks) {
                Log-Message "Executing task: $task" -MessageType INFO
                switch ($task) {
                    "DeclineUnapproved" { $declined += Decline-Updates -Type "Unapproved" -Filter { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) } -ServerName $SelectedServer }
                    "DeclineExpired" { $declined += Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined } -ServerName $SelectedServer }
                    "DeclineSuperseded" { $declined += Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined } -ServerName $SelectedServer }
                    "RemoveClassifications" { $declined += Decline-ByClassification -ServerName $SelectedServer }
                    "WSUSCleanup" { Run-WSUSCleanup -IncludeCompress $ChkCompress -ServerName $SelectedServer }
                    "PurgeUnassigned" { Purge-UnassignedFiles -WsusUtilPath $WsusUtilPath }
                    { $_ -in @("BackupDB", "CheckDB", "CheckFragmentation", "Reindex", "ShrinkDB") } {
                        Run-WIDMaintenance -DoBackup ($task -eq "BackupDB" -and $ChkBackup) -DoCheckDB ($task -eq "CheckDB" -and $ChkCheckDB) -DoCheckFragmentation ($task -eq "CheckFragmentation" -and $ChkCheckFragmentation) -DoReindex ($task -eq "Reindex" -and $ChkReindex) -DoShrink ($task -eq "ShrinkDB" -and $ChkShrink)
                    }
                }
            }
            if ($declined.Count -gt 0) {
                $declined | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
                Log-Message "Declined updates exported to $CsvFile" -MessageType INFO
            }
            Log-Message "Runspace execution completed." -MessageType INFO
            return $declined
        }).AddArgument($tasks).AddArgument($selectedServer).AddArgument($chkCompress.Checked).AddArgument($chkPurge.Checked).AddArgument($chkRemoveClassifications.Checked).AddArgument($chkBackup.Checked).AddArgument($chkCheckDB.Checked).AddArgument($chkCheckFragmentation.Checked).AddArgument($chkReindex.Checked).AddArgument($chkShrink.Checked).AddArgument($csvFile).AddArgument($logPath).AddArgument($Config.BackupDir).AddArgument($Config.SqlScriptDir).AddArgument($sqlcmdPath).AddArgument($Config.WsusUtilPath).AddArgument($Config.WsusAssemblyPath)
        $runspace.RunspacePool = $runspacePool
        $handle = $runspace.BeginInvoke()

        $taskDurations = @{
            "DeclineUnapproved" = 10; "DeclineExpired" = 10; "DeclineSuperseded" = 10; "RemoveClassifications" = 10
            "WSUSCleanup" = 20; "PurgeUnassigned" = 15; "BackupDB" = 30; "CheckDB" = 20
            "CheckFragmentation" = 15; "Reindex" = 25; "ShrinkDB" = 20
        }
        $totalDuration = ($tasks | ForEach-Object { $taskDurations[$_] } | Measure-Object -Sum).Sum
        $progressStep = 100 / $totalDuration
        $currentTime = 0

        while (-not $handle.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $currentTime += 0.5
            $progress.Value = [Math]::Min([int]($currentTime * $progressStep), $progress.Maximum)
            [System.Windows.Forms.Application]::DoEvents()
        }

        $result = $runspace.EndInvoke($handle)
        $runspace.Dispose()

        $progress.Value = $progress.Maximum
        $statusLabel.Text = "Maintenance complete. Log saved to $logPath"
        Log-Message "Maintenance complete." -MessageType INFO
        [System.Windows.Forms.MessageBox]::Show("Maintenance completed successfully.`nLog: $logPath`nCSV: $csvFile", "Complete", 'OK', 'Information')
    } catch {
        Log-Message "Execution failed: $_" -MessageType ERROR
        $statusLabel.Text = "Maintenance failed. Check log for details."
        [System.Windows.Forms.MessageBox]::Show("Maintenance failed: $_`nLog: $logPath", "Error", 'OK', 'Error')
    } finally {
        $btnRun.Enabled = $true
        $btnSchedule.Enabled = $true
    }
})

try {
    Load-Settings
    Log-Message "Starting WSUS Maintenance GUI" -MessageType INFO
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    Log-Message "WSUS Maintenance GUI closed" -MessageType INFO
} finally {
    Save-Settings
    $runspacePool.Close()
    $runspacePool.Dispose()
}

#endregion

# End of script
