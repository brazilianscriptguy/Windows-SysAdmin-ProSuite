<#
.SYNOPSIS
    WSUS Update Source and Proxy Configuration Script (Maintenance GUI)

.DESCRIPTION
    GUI for WSUS maintenance: decline, cleanup, and SUSDB (WID) database tasks.
    Emphasis on robustness: uses the UpdateServices module when available; falls back to AdminProxy if needed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: Sep 15, 2025  -03
    Version: 2.18
#>

#region --- Global Setup and Logging

# Setup Logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP\WSUS-GUI\Logs'
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logDir "$scriptName-$timestamp.log"

if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

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

# Hide the console window (comment the last line to keep visible while debugging)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() { var handle = GetConsoleWindow(); ShowWindow(handle, 0); }
}
"@
[Window]::Hide()

# WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

#endregion

#region --- Configuration
$global:Config = @{
    SqlScriptDir = "C:\Logs-TEMP\WSUS-GUI\Scripts"
    WsusUtilPath = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    LogDir = 'C:\Logs-TEMP\WSUS-GUI\Logs'
    BackupDir = 'C:\Logs-TEMP\WSUS-GUI\Backups'
    CsvDir = 'C:\Logs-TEMP\WSUS-GUI\CSV'
    SettingsFile = 'C:\Logs-TEMP\WSUS-GUI\settings.json'

    # Resolve local FQDN (domain-joined and workgroup-safe)
    FqdnHostname = $(
        try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($cs.Domain -and $cs.Domain -ne $cs.DNSHostName) {
                "$($cs.DNSHostName).$($cs.Domain)"
            } else {
                $cs.DNSHostName
            }
        } catch {
            try { [System.Net.Dns]::GetHostEntry('').HostName } catch { $env:COMPUTERNAME }
        }
    )
}

Log-Message "Detected FQDN: $($Config.FqdnHostname)" -MessageType INFO

# Locate sqlcmd
$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
if (-not $sqlcmdPath) {
    Log-Message "sqlcmd.exe not found. Install SQLCMD (SQL Server tools) or add it to PATH." -MessageType ERROR
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Install SQLCMD (SQL Server tools) or add it to PATH.", "Error", 'OK', 'Error') | Out-Null
    exit 1
}
Log-Message "Using sqlcmd.exe path: $sqlcmdPath" -MessageType INFO

# Ensure directories
foreach ($dir in @($Config.LogDir, $Config.BackupDir, $Config.CsvDir, $Config.SqlScriptDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

#endregion

#region --- Helpers (general)

function Set-WsusDbTimeoutIfAvailable {
    param([object]$Wsus)
    try {
        $cfg = $Wsus.GetConfiguration()
        if ($cfg -and ($cfg | Get-Member -Name DatabaseCommandTimeout -ErrorAction SilentlyContinue)) {
            if (-not $cfg.DatabaseCommandTimeout -or $cfg.DatabaseCommandTimeout -lt 10800) {
                $cfg.DatabaseCommandTimeout = 10800  # 3 hours
                $cfg.Save()
                Log-Message "Set WSUS DatabaseCommandTimeout to $($cfg.DatabaseCommandTimeout)s." -MessageType DEBUG
            }
        } else {
            Log-Message "DatabaseCommandTimeout not available in this WSUS version; skipping." -MessageType DEBUG
        }
    } catch {
        Log-Message "Failed to set WSUS DB timeout: $($_.Exception.Message)" -MessageType DEBUG
    }
}

# Retry wrapper only for CompressUpdates
function Invoke-CompressUpdatesWithRetry {
    param(
        [int]$MaxRetries = 3,
        [int]$InitialDelaySec = 45,
        [switch]$VerboseCleanup
    )
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            Log-Message "Invoke-WsusServerCleanup -CompressUpdates (attempt $attempt/$MaxRetries) ..." -MessageType INFO
            if ($VerboseCleanup) {
                Invoke-WsusServerCleanup -CompressUpdates -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
            } else {
                Invoke-WsusServerCleanup -CompressUpdates -Confirm:$false 2>&1        | ForEach-Object { Log-Message $_ }
            }
            Log-Message "CompressUpdates completed on attempt $attempt." -MessageType INFO
            return
        } catch {
            $msg = $_.Exception.Message
            Log-Message "CompressUpdates failed on attempt ${attempt}: $msg" -MessageType WARNING
            if ($attempt -lt $MaxRetries) {
                $delay = [int]([Math]::Min($InitialDelaySec * [math]::Pow(2, $attempt - 1), 600))
                Log-Message "Retrying in ${delay}s..." -MessageType INFO
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

# Temporarily relax IIS WSUS app pool settings (auto-restore)
function Set-WsusIisTuning {
    param(
        [switch]$Apply,
        [hashtable]$OriginalOut
    )
    $appcmd = "$env:WinDir\System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) { return $OriginalOut }

    $pool = "WsusPool"
    $changed = @{}

    try {
        $poolCfg = & $appcmd list apppool "$pool" /text:* 2>$null
        if (-not $poolCfg) { return $OriginalOut }

        if ($Apply) {
            $orig_idle = ($poolCfg -split "`n" | Where-Object { $_ -match '^processModel\.idleTimeout:' }) -replace '.*:', ''
            $orig_queue = ($poolCfg -split "`n" | Where-Object { $_ -match '^queueLength:' }) -replace '.*:', ''
            $orig_recycle = ($poolCfg -split "`n" | Where-Object { $_ -match '^recycling\.periodicRestart\.time:' }) -replace '.*:', ''

            $changed.IdleTimeout = $orig_idle
            $changed.QueueLength = $orig_queue
            $changed.PeriodicRestartTime = $orig_recycle

            & $appcmd set apppool "$pool" /processModel.idleTimeout:"00:00:00"      | Out-Null
            & $appcmd set apppool "$pool" /queueLength:20000                         | Out-Null
            & $appcmd set apppool "$pool" /recycling.periodicRestart.time:"00:00:00" | Out-Null
            Log-Message "Applied IIS tuning on $pool (idle=0, queue=20000, no periodic restart)." -MessageType DEBUG
        } elseif ($OriginalOut) {
            if ($OriginalOut.IdleTimeout) { & $appcmd set apppool "$pool" /processModel.idleTimeout:$($OriginalOut.IdleTimeout) | Out-Null }
            if ($OriginalOut.QueueLength) { & $appcmd set apppool "$pool" /queueLength:$($OriginalOut.QueueLength)             | Out-Null }
            if ($OriginalOut.PeriodicRestartTime) { & $appcmd set apppool "$pool" /recycling.periodicRestart.time:$($OriginalOut.PeriodicRestartTime) | Out-Null }
            Log-Message "Restored IIS tuning on $pool." -MessageType DEBUG
        }
    } catch {
        Log-Message "IIS tuning skipped/failed: $($_.Exception.Message)" -MessageType DEBUG
    }
    return $changed
}

#endregion

#region --- Helpers (WSUS access)

# Try UpdateServices module first; if missing, fall back to AdminProxy
function Get-WSUSServerSafe {
    param(
        [string]$ServerName,
        [int]   $Port = 8530,
        [bool]  $UseSSL = $false
    )

    # Force FQDN when GUI/JSON didn't provide (null/empty/localhost)
    if ([string]::IsNullOrWhiteSpace($ServerName) -or $ServerName -match '^(localhost|127\.0\.0\.1)$') {
        $ServerName = $Config.FqdnHostname
    }

    # UpdateServices module
    if (Get-Module -ListAvailable -Name UpdateServices) {
        try {
            Import-Module UpdateServices -ErrorAction Stop

            $cmd = Get-Command Get-WsusServer -ErrorAction Stop
            if ($cmd.Parameters.ContainsKey('UseSecureConnection')) {
                $wsus = Get-WsusServer -Name $ServerName -PortNumber $Port -UseSecureConnection:$UseSSL
            } else {
                $wsus = Get-WsusServer -Name $ServerName -PortNumber $Port
            }

            if ($wsus) { return $wsus }
        } catch {
            Log-Message ("Get-WsusServer failed: {0}" -f $_.Exception.Message) -MessageType WARNING
        }
    }

    # Fallback: AdminProxy from GAC
    try {
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if (-not $asm) { throw "WSUS Administration assembly not available." }
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
        return $wsus
    } catch {
        Log-Message ("AdminProxy fallback failed: {0}" -f $_.Exception.Message) -MessageType ERROR
        throw
    }
}

function Test-WSUSConnection {
    param(
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    $wsus = Get-WSUSServerSafe -ServerName $ServerName -Port $Port -UseSSL $UseSSL
    if (-not $wsus) { throw "WSUS connection failed." }
    Log-Message "Connected to WSUS: $($wsus.Name):$Port SSL=$UseSSL" -MessageType INFO
    Set-WsusDbTimeoutIfAvailable -Wsus $wsus
    return $wsus
}

#endregion

#region --- Decline / Cleanup / WID

function Decline-Updates {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][scriptblock]$Filter,
        [Parameter(Mandatory = $true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL

    # Try to use SearchUpdates via WSUS Admin API
    try {
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)
        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
    } catch {
        Log-Message "SearchUpdates failed (Admin API unavailable?). Using empty set..." -MessageType WARNING
        $updates = @()
    }

    if (($updates | Measure-Object).Count -eq 0) {
        Log-Message "$Type updates: none found." -MessageType INFO
        return @()
    }

    Log-Message "$Type updates: Found $($updates.Count). Declining..." -MessageType INFO
    $log = @()
    foreach ($u in $updates) {
        try {
            $u.Decline()
            Log-Message "Declined ($Type): $($u.Title)" -MessageType INFO
            $log += [pscustomobject]@{
                KB = ($u.KnowledgeBaseArticles -join ',')
                Title = $u.Title
                Type = $Type
                Date = $u.CreationDate
                DeclinedOn = Get-Date
                Server = $ServerName
            }
        } catch {
            Log-Message "Decline failed ($Type): $($u.Title) :: $($_.Exception.Message)" -MessageType ERROR
        }
    }
    return $log
}

function Run-WSUSCleanup {
    param(
        [bool]$IncludeUnusedUpdates,
        [bool]$IncludeObsoleteComputers,
        [bool]$IncludeUnneededFiles,
        [bool]$IncludeExpiredUpdates,
        [bool]$IncludeSupersededUpdates,
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )

    $null = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL

    # 1) Pre-decline (reduces cleanup load)
    if ($IncludeExpiredUpdates) {
        Log-Message "Pre-clean: Decline expired (unapproved)..." -MessageType INFO
        Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined -and -not $_.IsApproved } -ServerName $ServerName -Port $Port -UseSSL:$UseSSL | Out-Null
    }
    if ($IncludeSupersededUpdates) {
        Log-Message "Pre-clean: Decline superseded (30+ days, unapproved)..." -MessageType INFO
        Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) } -ServerName $ServerName -Port $Port -UseSSL:$UseSSL | Out-Null
    }

    # 2) wsusutil removeinactiveapprovals (if available)
    if (Test-Path $Config.WsusUtilPath) {
        try {
            Log-Message "wsusutil.exe removeinactiveapprovals ..." -MessageType INFO
            & $Config.WsusUtilPath removeinactiveapprovals | Out-Null
        } catch {
            Log-Message ("wsusutil removeinactiveapprovals failed: {0}" -f $_.Exception.Message) -MessageType WARNING
        }
    } else {
        Log-Message "wsusutil.exe not found at $($Config.WsusUtilPath). Continuing without it." -MessageType WARNING
    }

    # 3) Step-wise cleanup via cmdlet (more compatible than CleanupScope)
    Import-Module UpdateServices -ErrorAction SilentlyContinue | Out-Null
    $ok = $false

    if ($IncludeUnusedUpdates) {
        try {
            Log-Message "Invoke-WsusServerCleanup -CleanupObsoleteUpdates ..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupObsoleteUpdates -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
            $ok = $true
        } catch { Log-Message ("CleanupObsoleteUpdates failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
    }
    if ($IncludeUnneededFiles) {
        try {
            Log-Message "Invoke-WsusServerCleanup -CleanupUnneededContentFiles ..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupUnneededContentFiles -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
            $ok = $true
        } catch { Log-Message ("CleanupUnneededContentFiles failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
    }
    if ($IncludeObsoleteComputers) {
        try {
            Log-Message "Invoke-WsusServerCleanup -CleanupObsoleteComputers ..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupObsoleteComputers -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
            $ok = $true
        } catch { Log-Message ("CleanupObsoleteComputers failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
    }

    # 4) CompressUpdates with retry and temporary IIS tuning
    $__iisOriginal = Set-WsusIisTuning -Apply -OriginalOut @{}
    try {
        Invoke-CompressUpdatesWithRetry -MaxRetries 3 -InitialDelaySec 45
        $ok = $true
    } catch {
        Log-Message ("CompressUpdates failed after retries: {0}" -f $_.Exception.Message) -MessageType WARNING
    } finally {
        Set-WsusIisTuning -OriginalOut $__iisOriginal | Out-Null
    }

    if (-not $ok) { throw "No cleanup step could run." }
}

function Run-WIDMaintenance {
    param(
        [bool]$DoCheckDB,
        [bool]$DoCheckFragmentation,
        [bool]$DoReindex,
        [bool]$DoShrink,
        [bool]$DoBackup
    )
    $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    if ($DoBackup) {
        $backupFile = Join-Path $Config.BackupDir "SUSDB-Backup-$timestamp.bak"
        Log-Message "Backing up SUSDB to $backupFile..." -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
    }
    if ($DoCheckDB) {
        Log-Message "DBCC CHECKDB..." -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "DBCC CHECKDB")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
    }
    if ($DoCheckFragmentation) {
        $fragmentationScript = Join-Path $Config.SqlScriptDir "wsus-verify-fragmentation.sql"
        if (Test-Path $fragmentationScript) {
            Log-Message "Check fragmentation ($fragmentationScript)..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-i", "`"$fragmentationScript`"")
            (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
        } else {
            Log-Message "Fragmentation script not found: $fragmentationScript" -MessageType WARNING
        }
    }
    if ($DoReindex) {
        $reindexScript = Join-Path $Config.SqlScriptDir "wsus-reindex-smart.sql"
        if (Test-Path $reindexScript) {
            Log-Message "Reindex ($reindexScript)..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-i", "`"$reindexScript`"")
            (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
        } else {
            Log-Message "Reindex script not found: $reindexScript" -MessageType WARNING
        }
    }
    if ($DoShrink) {
        Log-Message "DBCC SHRINKDATABASE (SUSDB, 10)..." -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
    }
}

#endregion

#region --- Settings (persist)

function Save-Settings {
    $settings = @{
        ServerName = $txtServer.Text
        Port = $txtPort.Text
        DeclineUnapproved = $chkDeclineUnapproved.Checked
        DeclineExpired = $chkDeclineExpired.Checked
        DeclineSuperseded = $chkDeclineSuperseded.Checked
        RemoveClassifications = $chkRemoveClassifications.Checked
        UnusedUpdates = $chkUnusedUpdates.Checked
        ObsoleteComputers = $chkObsoleteComputers.Checked
        UnneededFiles = $chkUnneededFiles.Checked
        ExpiredUpdates = $chkExpiredUpdates.Checked
        SupersededUpdates = $chkSupersededUpdates.Checked
        CheckDB = $chkCheckDB.Checked
        CheckFragmentation = $chkCheckFragmentation.Checked
        Reindex = $chkReindex.Checked
        ShrinkDB = $chkShrink.Checked
        BackupDB = $chkBackup.Checked
    }
    $settings | ConvertTo-Json | Set-Content -Path $Config.SettingsFile -Force
}

function Load-Settings {
    if (Test-Path $Config.SettingsFile) {
        $s = Get-Content $Config.SettingsFile -Raw | ConvertFrom-Json
        # Default to FQDN when missing/localhost
        $defaultServer = if ($s.ServerName -and $s.ServerName -notmatch '^(localhost|127\.0\.0\.1)$') { $s.ServerName } else { $Config.FqdnHostname }
        $txtServer.Text = $defaultServer
        $txtPort.Text = if ($s.Port) { $s.Port } else { "8530" }
        $chkDeclineUnapproved.Checked = [bool]$s.DeclineUnapproved
        $chkDeclineExpired.Checked = if ($s.DeclineExpired -ne $null) { [bool]$s.DeclineExpired } else { $true }
        $chkDeclineSuperseded.Checked = if ($s.DeclineSuperseded -ne $null) { [bool]$s.DeclineSuperseded } else { $true }
        $chkRemoveClassifications.Checked = [bool]$s.RemoveClassifications
        $chkUnusedUpdates.Checked = [bool]$s.UnusedUpdates
        $chkObsoleteComputers.Checked = if ($s.ObsoleteComputers -ne $null) { [bool]$s.ObsoleteComputers } else { $true }
        $chkUnneededFiles.Checked = [bool]$s.UnneededFiles
        $chkExpiredUpdates.Checked = if ($s.ExpiredUpdates -ne $null) { [bool]$s.ExpiredUpdates } else { $true }
        $chkSupersededUpdates.Checked = if ($s.SupersededUpdates -ne $null) { [bool]$s.SupersededUpdates } else { $true }
        $chkCheckDB.Checked = [bool]$s.CheckDB
        $chkCheckFragmentation.Checked = [bool]$s.CheckFragmentation
        $chkReindex.Checked = [bool]$s.Reindex
        $chkShrink.Checked = [bool]$s.ShrinkDB
        $chkBackup.Checked = [bool]$s.BackupDB
    } else {
        # First run defaults
        $txtServer.Text = $Config.FqdnHostname
        $txtPort.Text = "8530"
    }
}

#endregion

#region --- GUI

$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS Maintenance Tool"
$form.Size = New-Object System.Drawing.Size(680, 730)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

# Top panel
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Size = New-Object System.Drawing.Size(640, 60)
$panelTop.Location = New-Object System.Drawing.Point(15, 10)
$panelTop.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelTop)

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = "WSUS Server:"
$lblServer.Location = New-Object System.Drawing.Point(10, 20)
$lblServer.Size = New-Object System.Drawing.Size(100, 20)
$lblServer.Font = $font
$panelTop.Controls.Add($lblServer)

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Text = $Config.FqdnHostname
$txtServer.Location = New-Object System.Drawing.Point(110, 18)
$txtServer.Size = New-Object System.Drawing.Size(180, 22)
$txtServer.Font = $font
$panelTop.Controls.Add($txtServer)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Port:"
$lblPort.Location = New-Object System.Drawing.Point(300, 20)
$lblPort.Size = New-Object System.Drawing.Size(35, 20)
$lblPort.Font = $font
$panelTop.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = "8530"
$txtPort.Location = New-Object System.Drawing.Point(340, 18)
$txtPort.Size = New-Object System.Drawing.Size(60, 22)
$txtPort.Font = $font
$panelTop.Controls.Add($txtPort)

$btnTestConnection = New-Object System.Windows.Forms.Button
$btnTestConnection.Text = "Test Connectivity"
$btnTestConnection.Location = New-Object System.Drawing.Point(410, 15)
$btnTestConnection.Size = New-Object System.Drawing.Size(135, 27)
$btnTestConnection.Font = $font
$btnTestConnection.Add_Click({
        try {
            $null = Test-WSUSConnection -ServerName $txtServer.Text -Port ([int]$txtPort.Text)
            $lblStatus.Text = "Connected to ${($txtServer.Text)}:${($txtPort.Text)}"
            $lblStatus.ForeColor = [System.Drawing.Color]::Green
            Log-Message "Connection test successful." -MessageType INFO
        } catch {
            $lblStatus.Text = "Failed"
            $lblStatus.ForeColor = [System.Drawing.Color]::Red
            Log-Message ("Connection test failed: {0}" -f $_.Exception.Message) -MessageType ERROR
        }
    })
$panelTop.Controls.Add($btnTestConnection)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Font = $font
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(560, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::Black
$panelTop.Controls.Add($lblStatus)

# Tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(640, 520)
$tabControl.Location = New-Object System.Drawing.Point(15, 80)
$tabControl.Font = $font
$form.Controls.Add($tabControl)

# Tab: Updates
$tabUpdates = New-Object System.Windows.Forms.TabPage
$tabUpdates.Text = "Updates"
$tabControl.Controls.Add($tabUpdates)

$groupUpdates = New-Object System.Windows.Forms.GroupBox
$groupUpdates.Text = "Update Maintenance"
$groupUpdates.Size = New-Object System.Drawing.Size(590, 160)
$groupUpdates.Location = New-Object System.Drawing.Point(10, 10)
$groupUpdates.Font = $font
$tabUpdates.Controls.Add($groupUpdates)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline Unapproved (older than 30 days)"
$chkDeclineUnapproved.Location = New-Object System.Drawing.Point(15, 25)
$chkDeclineUnapproved.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineUnapproved.Font = $font
$groupUpdates.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline Expired"
$chkDeclineExpired.Location = New-Object System.Drawing.Point(15, 50)
$chkDeclineExpired.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineExpired.Font = $font
$groupUpdates.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline Superseded"
$chkDeclineSuperseded.Location = New-Object System.Drawing.Point(15, 75)
$chkDeclineSuperseded.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineSuperseded.Font = $font
$groupUpdates.Controls.Add($chkDeclineSuperseded)

$chkRemoveClassifications = New-Object System.Windows.Forms.CheckBox
$chkRemoveClassifications.Text = "Decline Itanium / Windows XP"
$chkRemoveClassifications.Location = New-Object System.Drawing.Point(15, 100)
$chkRemoveClassifications.Size = New-Object System.Drawing.Size(560, 20)
$chkRemoveClassifications.Font = $font
$groupUpdates.Controls.Add($chkRemoveClassifications)

# Tab: Maintenance
$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Maintenance"
$tabControl.Controls.Add($tabMaintenance)

$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Cleanup Options"
$groupWSUS.Size = New-Object System.Drawing.Size(590, 160)
$groupWSUS.Location = New-Object System.Drawing.Point(10, 10)
$groupWSUS.Font = $font
$tabMaintenance.Controls.Add($groupWSUS)

$chkUnusedUpdates = New-Object System.Windows.Forms.CheckBox
$chkUnusedUpdates.Text = "Unused Updates and Revisions (older than 30 days)"
$chkUnusedUpdates.Location = New-Object System.Drawing.Point(15, 25)
$chkUnusedUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkUnusedUpdates.Font = $font
$groupWSUS.Controls.Add($chkUnusedUpdates)

$chkObsoleteComputers = New-Object System.Windows.Forms.CheckBox
$chkObsoleteComputers.Text = "Obsolete Computers (not contacted in 30+ days)"
$chkObsoleteComputers.Location = New-Object System.Drawing.Point(15, 50)
$chkObsoleteComputers.Size = New-Object System.Drawing.Size(560, 20)
$chkObsoleteComputers.Checked = $true
$chkObsoleteComputers.Font = $font
$groupWSUS.Controls.Add($chkObsoleteComputers)

$chkUnneededFiles = New-Object System.Windows.Forms.CheckBox
$chkUnneededFiles.Text = "Unneeded Update Files"
$chkUnneededFiles.Location = New-Object System.Drawing.Point(15, 75)
$chkUnneededFiles.Size = New-Object System.Drawing.Size(560, 20)
$chkUnneededFiles.Font = $font
$groupWSUS.Controls.Add($chkUnneededFiles)

$chkExpiredUpdates = New-Object System.Windows.Forms.CheckBox
$chkExpiredUpdates.Text = "Expired Updates (declines unapproved)"
$chkExpiredUpdates.Location = New-Object System.Drawing.Point(15, 100)
$chkExpiredUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkExpiredUpdates.Checked = $true
$chkExpiredUpdates.Font = $font
$groupWSUS.Controls.Add($chkExpiredUpdates)

$chkSupersededUpdates = New-Object System.Windows.Forms.CheckBox
$chkSupersededUpdates.Text = "Superseded Updates (declines > 30 days)"
$chkSupersededUpdates.Location = New-Object System.Drawing.Point(15, 125)
$chkSupersededUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkSupersededUpdates.Checked = $true
$chkSupersededUpdates.Font = $font
$groupWSUS.Controls.Add($chkSupersededUpdates)

# SQL group
$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB Maintenance Tasks"
$groupSQL.Size = New-Object System.Drawing.Size(590, 160)
$groupSQL.Location = New-Object System.Drawing.Point(10, 180)
$groupSQL.Font = $font
$tabMaintenance.Controls.Add($groupSQL)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = New-Object System.Drawing.Point(15, 25)
$chkCheckDB.Size = New-Object System.Drawing.Size(560, 20)
$chkCheckDB.Font = $font
$groupSQL.Controls.Add($chkCheckDB)

$chkCheckFragmentation = New-Object System.Windows.Forms.CheckBox
$chkCheckFragmentation.Text = "Check Index Fragmentation"
$chkCheckFragmentation.Location = New-Object System.Drawing.Point(15, 50)
$chkCheckFragmentation.Size = New-Object System.Drawing.Size(560, 20)
$chkCheckFragmentation.Font = $font
$groupSQL.Controls.Add($chkCheckFragmentation)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild Indexes"
$chkReindex.Location = New-Object System.Drawing.Point(15, 75)
$chkReindex.Size = New-Object System.Drawing.Size(560, 20)
$chkReindex.Font = $font
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink Database"
$chkShrink.Location = New-Object System.Drawing.Point(15, 100)
$chkShrink.Size = New-Object System.Drawing.Size(560, 20)
$chkShrink.Font = $font
$groupSQL.Controls.Add($chkShrink)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = "Backup SUSDB"
$chkBackup.Location = New-Object System.Drawing.Point(15, 125)
$chkBackup.Size = New-Object System.Drawing.Size(560, 20)
$chkBackup.Font = $font
$groupSQL.Controls.Add($chkBackup)

# Bottom Panel (progress + controls)
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Size = New-Object System.Drawing.Size(640, 70)
$panelBottom.Location = New-Object System.Drawing.Point(15, 610)
$panelBottom.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelBottom)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 40)
$progress.Size = New-Object System.Drawing.Size(400, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$panelBottom.Controls.Add($progress)

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Ready"
$statusBar.Location = New-Object System.Drawing.Point(420, 40)
$statusBar.Size = New-Object System.Drawing.Size(190, 20)
$statusBar.Font = $font
$panelBottom.Controls.Add($statusBar)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "&Run"
$btnRun.Size = New-Object System.Drawing.Size(80, 25)
$btnRun.Location = New-Object System.Drawing.Point(10, 10)
$btnRun.Font = $font
$panelBottom.Controls.Add($btnRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "&Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(80, 25)
$btnCancel.Location = New-Object System.Drawing.Point(100, 10)
$btnCancel.Font = $font
$panelBottom.Controls.Add($btnCancel)

$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "&Help"
$btnHelp.Size = New-Object System.Drawing.Size(80, 25)
$btnHelp.Location = New-Object System.Drawing.Point(190, 10)
$btnHelp.Font = $font
$panelBottom.Controls.Add($btnHelp)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "&Close"
$btnClose.Size = New-Object System.Drawing.Size(80, 25)
$btnClose.Location = New-Object System.Drawing.Point(540, 10)
$btnClose.Font = $font
$panelBottom.Controls.Add($btnClose)

# Runspace infra (kept for compatibility with finally)
$runspace = $null
$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 2)
$runspacePool.Open()

# Button handlers
$btnRun.Add_Click({
        try {
            $btnRun.Enabled = $false; $btnCancel.Enabled = $false; $btnHelp.Enabled = $false; $btnClose.Enabled = $false
            $progress.Value = 0
            $statusBar.Text = "Starting..."
            Log-Message "Starting WSUS maintenance..." -MessageType INFO
            Save-Settings

            # Force FQDN when empty/localhost
            $server = if ([string]::IsNullOrWhiteSpace($txtServer.Text) -or $txtServer.Text -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $txtServer.Text }
            $port = [int]$txtPort.Text

            # Connection
            $null = Test-WSUSConnection -ServerName $server -Port $port

            # Task selection
            $tasks = @()
            if ($chkDeclineUnapproved.Checked) { $tasks += "DeclineUnapproved" }
            if ($chkDeclineExpired.Checked) { $tasks += "DeclineExpired" }
            if ($chkDeclineSuperseded.Checked) { $tasks += "DeclineSuperseded" }
            if ($chkRemoveClassifications.Checked) { $tasks += "RemoveClassifications" }
            if ($chkUnusedUpdates.Checked -or $chkObsoleteComputers.Checked -or $chkUnneededFiles.Checked -or $chkExpiredUpdates.Checked -or $chkSupersededUpdates.Checked) { $tasks += "WSUSCleanup" }
            if ($chkCheckDB.Checked) { $tasks += "CheckDB" }
            if ($chkCheckFragmentation.Checked) { $tasks += "CheckFragmentation" }
            if ($chkReindex.Checked) { $tasks += "Reindex" }
            if ($chkShrink.Checked) { $tasks += "ShrinkDB" }
            if ($chkBackup.Checked) { $tasks += "BackupDB" }

            if ($tasks.Count -eq 0) {
                Log-Message "No tasks selected." -MessageType WARNING
                [System.Windows.Forms.MessageBox]::Show("Please select at least one task.", "WSUS Maintenance", "OK", "Warning") | Out-Null
                return
            }

            # Synchronous execution with simple feedback
            $progress.Maximum = $tasks.Count * 100
            $advance = { param($pct) $progress.Value = [Math]::Min($progress.Value + $pct, $progress.Maximum); [System.Windows.Forms.Application]::DoEvents() }

            $declined = @()
            foreach ($t in $tasks) {
                Log-Message "Executing: $t" -MessageType INFO
                $statusBar.Text = "Running: $t"
                switch ($t) {
                    "DeclineUnapproved" { $declined += Decline-Updates -Type "Unapproved"   -Filter { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) } -ServerName $server -Port $port }
                    "DeclineExpired" { $declined += Decline-Updates -Type "Expired"      -Filter { $_.IsExpired -and -not $_.IsDeclined } -ServerName $server -Port $port }
                    "DeclineSuperseded" { $declined += Decline-Updates -Type "Superseded"   -Filter { $_.IsSuperseded -and -not $_.IsDeclined } -ServerName $server -Port $port }
                    "RemoveClassifications" { $declined += Decline-Updates -Type "Classification" -Filter { -not $_.IsDeclined -and ($_.Title -match 'Itanium|Windows XP' -or $_.Description -match 'Itanium|Windows XP') } -ServerName $server -Port $port }
                    "WSUSCleanup" { Run-WSUSCleanup -IncludeUnusedUpdates $chkUnusedUpdates.Checked -IncludeObsoleteComputers $chkObsoleteComputers.Checked -IncludeUnneededFiles $chkUnneededFiles.Checked -IncludeExpiredUpdates $chkExpiredUpdates.Checked -IncludeSupersededUpdates $chkSupersededUpdates.Checked -ServerName $server -Port $port }
                    { $_ -in @("CheckDB", "CheckFragmentation", "Reindex", "ShrinkDB", "BackupDB") } {
                        Run-WIDMaintenance -DoCheckDB ($t -eq "CheckDB") -DoCheckFragmentation ($t -eq "CheckFragmentation") -DoReindex ($t -eq "Reindex") -DoShrink ($t -eq "ShrinkDB") -DoBackup ($t -eq "BackupDB")
                    }
                }
                & $advance 100
            }

            # Export CSV of declined items (if any)
            if ($declined.Count -gt 0) {
                $csvFile = Join-Path $Config.CsvDir ("{0}-Declined-{1}.csv" -f $scriptName, (Get-Date -Format "yyyyMMdd-HHmmss"))
                $declined | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
                Log-Message "Declined list exported: $csvFile" -MessageType INFO
            }

            $statusBar.Text = "Done. Log: $logPath"
            Log-Message "Maintenance complete." -MessageType INFO
            [System.Windows.Forms.MessageBox]::Show("Maintenance completed.`nLog: $logPath", "WSUS Maintenance", "OK", "Information") | Out-Null
        }
        catch {
            $statusBar.Text = "Failed — see log"
            Log-Message ("Execution failed: {0}" -f $_.Exception.Message) -MessageType ERROR
            [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)`nLog: $logPath", "WSUS Maintenance", "OK", "Error") | Out-Null
        }
        finally {
            $btnRun.Enabled = $true; $btnCancel.Enabled = $true; $btnHelp.Enabled = $true; $btnClose.Enabled = $true
        }
    })

$btnCancel.Add_Click({
        $statusBar.Text = "Operation canceled."
        Log-Message "Operation canceled by user." -MessageType WARNING
    })

$btnHelp.Add_Click({
        [System.Windows.Forms.MessageBox]::Show(@"
WSUS Maintenance Tool
- Decline Unapproved/Expired/Superseded
- Cleanup (ObsoleteUpdates, UnneededFiles, ObsoleteComputers, Compress with retry/backoff)
- Optional IIS app-pool tuning during CompressUpdates (auto-restore)
- SUSDB tasks (CHECKDB, fragmentation, reindex, shrink, backup)
"@, "Help", "OK", "Information") | Out-Null
        Log-Message "Help opened." -MessageType INFO
    })

$btnClose.Add_Click({
        try { Save-Settings } catch {}
        $form.Close()
    })

# Boot
try {
    Load-Settings
    Log-Message "Starting WSUS Maintenance GUI" -MessageType INFO
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    Log-Message "GUI closed" -MessageType INFO
}
finally {
    try { Save-Settings } catch { Log-Message ("Save-Settings failed: {0}" -f $_.Exception.Message) -MessageType WARNING }
    if ($runspace) {
        try { $runspace.Stop() } catch {}
        try { $runspace.Dispose() } catch {}
        $runspace = $null
    }
    if ($runspacePool) {
        try { if ($runspacePool.RunspacePoolStateInfo.State -ne 'Closed') { $runspacePool.Close() } } catch {}
        try { $runspacePool.Dispose() } catch {}
        $runspacePool = $null
    }
    try { [System.Windows.Forms.Application]::ExitThread() } catch {}
}

#endregion

# End of script
