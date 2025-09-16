<#
.SYNOPSIS
    WSUS Maintenance GUI — decline, cleanup and WID (SUSDB) tasks.

.DESCRIPTION
    Robust GUI for WSUS maintenance:
      - Decline Unapproved/Expired/Superseded (30+ days alignment)
      - WSUS cleanup (obsolete updates, unneeded files, obsolete computers)
      - Optional "Compress Revisions" with retry/backoff and temporary IIS tuning
      - SUSDB (WID) tasks via sqlcmd: backup, CHECKDB, fragmentation check, reindex, shrink
    Improvements:
      - Administrator/elevation check
      - IIS/WSUS readiness (W3SVC, WSUSService, WsusPool) to avoid HTTP 503
      - HTTP probe on test
      - Cancel support (cooperative)
      - Broad search scope (no 365-day cut-off)
      - Consistent superseded 30+ days rule
      - sqlcmd exit code checks
      - Fixed Load-Settings server resolution
      - Progress bar reflects real work (weighted, bounded 0–100)
      - Safe string interpolation using ${Server}/${Port}

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: Sep 16, 2025  -03
    Version: 2.20 (US-English, progress + interpolation)
#>

#region --- Global Setup / Admin Check / Logging

# Require elevation
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).
IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Run this tool as Administrator.", "WSUS Maintenance", "OK", "Error") | Out-Null
    exit 1
}

# Logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP\WSUS-GUI\Logs'
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath = Join-Path $logDir "$scriptName-$timestamp.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Log-Message {
    param([string]$Message, [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")] [string]$MessageType = "INFO")
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $Message"
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    Write-Host $entry
}

# Hide console (comment while debugging)
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
    FqdnHostname = $(try {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($cs.Domain -and $cs.Domain -ne $cs.DNSHostName) { "$($cs.DNSHostName).$($cs.Domain)" } else { $cs.DNSHostName }
        } catch { try { [System.Net.Dns]::GetHostEntry('').HostName } catch { $env:COMPUTERNAME } })
}

foreach ($dir in @($Config.LogDir, $Config.BackupDir, $Config.CsvDir, $Config.SqlScriptDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

Log-Message "Detected FQDN: $($Config.FqdnHostname)" -MessageType INFO

# sqlcmd required for WID tasks
$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
if (-not $sqlcmdPath) {
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Install SQLCMD (SQL Server tools) or add it to PATH.", "Error", 'OK', 'Error') | Out-Null
    Log-Message "sqlcmd.exe not found. Install SQLCMD or add to PATH." -MessageType ERROR
    exit 1
}
Log-Message "Using sqlcmd.exe: $sqlcmdPath" -MessageType INFO

#endregion

#region --- Helpers (services/IIS/WSUS)

$global:CancelRequested = $false

function Set-WsusDbTimeoutIfAvailable([object]$Wsus) {
    try {
        $cfg = $Wsus.GetConfiguration()
        if ($cfg -and ($cfg | Get-Member -Name DatabaseCommandTimeout -ErrorAction SilentlyContinue)) {
            if (-not $cfg.DatabaseCommandTimeout -or $cfg.DatabaseCommandTimeout -lt 10800) {
                $cfg.DatabaseCommandTimeout = 10800
                $cfg.Save()
                Log-Message "Set WSUS DatabaseCommandTimeout to $($cfg.DatabaseCommandTimeout)s." -MessageType DEBUG
            }
        }
    } catch { Log-Message "Skip DB timeout tune: $($_.Exception.Message)" -MessageType DEBUG }
}

function Start-And-WaitService([string]$Name, [int]$TimeoutSec = 240) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Log-Message "Service $Name not found." -MessageType WARNING; return }
    if ($svc.Status -ne 'Running') { try { Start-Service $Name -ErrorAction SilentlyContinue }catch {} }
    try { $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSec)) | Out-Null
        Log-Message "Service $Name Running." -MessageType INFO
    } catch { Log-Message "Timeout waiting $Name." -MessageType WARNING }
}

function Ensure-WsusPool() {
    try {
        Import-Module WebAdministration -ErrorAction Stop
        if (Test-Path IIS:\AppPools\WsusPool) {
            $state = (Get-Item IIS:\AppPools\WsusPool).state
            if ($state -ne 'Started') { Start-WebAppPool WsusPool } else { Restart-WebAppPool WsusPool }
            Log-Message "WsusPool started/recycled." -MessageType INFO
        } else { Log-Message "AppPool 'WsusPool' not found." -MessageType WARNING }
    } catch { Log-Message "IIS/WebAdministration unavailable: $($_.Exception.Message)" -MessageType WARNING }
}

function HTTP-Probe([string]$Server, [int]$Port) {
    try {
        $u = "http://${Server}:${Port}/ServerSyncWebService/ServerSyncWebService.asmx?wsdl"
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { Log-Message "HTTP probe OK (${Server}:${Port})" -MessageType DEBUG; return $true }
    } catch { Log-Message "HTTP probe failed (${Server}:${Port}): $($_.Exception.Message)" -MessageType WARNING }
    return $false
}

function Get-WSUSServerSafe([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false) {
    if ([string]::IsNullOrWhiteSpace($ServerName) -or $ServerName -match '^(localhost|127\.0\.0\.1)$') {
        $ServerName = $Config.FqdnHostname
    }
    if (Get-Module -ListAvailable -Name UpdateServices) {
        try {
            Import-Module UpdateServices -ErrorAction Stop
            $cmd = Get-Command Get-WsusServer -ErrorAction Stop
            if ($cmd.Parameters.ContainsKey('UseSecureConnection')) {
                return Get-WsusServer -Name $ServerName -PortNumber $Port -UseSecureConnection:$UseSSL
            } else {
                return Get-WsusServer -Name $ServerName -PortNumber $Port
            }
        } catch { Log-Message ("Get-WsusServer failed: {0}" -f $_.Exception.Message) -MessageType WARNING }
    }
    try {
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if (-not $asm) { throw "WSUS Admin assembly missing." }
        return [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
    } catch { Log-Message ("AdminProxy fallback failed: {0}" -f $_.Exception.Message) -MessageType ERROR; throw }
}

function Test-WSUSConnection([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false) {
    Start-And-WaitService 'W3SVC' 180
    Start-And-WaitService 'WSUSService' 240
    Ensure-WsusPool | Out-Null
    $null = HTTP-Probe -Server $ServerName -Port $Port
    $wsus = Get-WSUSServerSafe -ServerName $ServerName -Port $Port -UseSSL $UseSSL
    if (-not $wsus) { throw "WSUS connection failed." }
    Log-Message "Connected to WSUS: $($wsus.Name):${Port} SSL=$UseSSL" -MessageType INFO
    Set-WsusDbTimeoutIfAvailable -Wsus $wsus
    return $wsus
}

# IIS tuning for CompressUpdates (auto-restore)
function Set-WsusIisTuning([switch]$Apply, [hashtable]$OriginalOut) {
    $appcmd = "$env:WinDir\System32\inetsrv\appcmd.exe"
    if (-not (Test-Path $appcmd)) { return $OriginalOut }
    $pool = "WsusPool"; $changed = @{}
    try {
        $poolCfg = & $appcmd list apppool "$pool" /text:* 2>$null
        if (-not $poolCfg) { return $OriginalOut }
        if ($Apply) {
            $orig_idle = ($poolCfg -split "`n" | Where-Object { $_ -match '^processModel\.idleTimeout:' }) -replace '.*:', ''
            $orig_queue = ($poolCfg -split "`n" | Where-Object { $_ -match '^queueLength:' }) -replace '.*:', ''
            $orig_recycle = ($poolCfg -split "`n" | Where-Object { $_ -match '^recycling\.periodicRestart\.time:' }) -replace '.*:', ''
            $changed.IdleTimeout = $orig_idle; $changed.QueueLength = $orig_queue; $changed.PeriodicRestartTime = $orig_recycle
            & $appcmd set apppool "$pool" /processModel.idleTimeout:"00:00:00" | Out-Null
            & $appcmd set apppool "$pool" /queueLength:20000                   | Out-Null
            & $appcmd set apppool "$pool" /recycling\.periodicRestart\.time:"00:00:00" | Out-Null
            Log-Message "Applied IIS tuning on $pool." -MessageType DEBUG
        } elseif ($OriginalOut) {
            if ($OriginalOut.IdleTimeout) { & $appcmd set apppool "$pool" /processModel.idleTimeout:$($OriginalOut.IdleTimeout) | Out-Null }
            if ($OriginalOut.QueueLength) { & $appcmd set apppool "$pool" /queueLength:$($OriginalOut.QueueLength)             | Out-Null }
            if ($OriginalOut.PeriodicRestartTime) { & $appcmd set apppool "$pool" /recycling\.periodicRestart\.time:$($OriginalOut.PeriodicRestartTime) | Out-Null }
            Log-Message "Restored IIS tuning on $pool." -MessageType DEBUG
        }
    } catch { Log-Message "IIS tuning skipped: $($_.Exception.Message)" -MessageType DEBUG }
    return $changed
}

# Retry wrapper for CompressUpdates (optional)
function Invoke-CompressUpdatesWithRetry([int]$MaxRetries = 3, [int]$InitialDelaySec = 45) {
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
        $attempt++
        try {
            Log-Message "Invoke-WsusServerCleanup -CompressUpdates (attempt $attempt/$MaxRetries) ..." -MessageType INFO
            Invoke-WsusServerCleanup -CompressUpdates -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
            Log-Message "CompressUpdates completed on attempt $attempt." -MessageType INFO
            return
        } catch {
            Log-Message "CompressUpdates failed (attempt $attempt): $($_.Exception.Message)" -MessageType WARNING
            if ($attempt -lt $MaxRetries) {
                $delay = [int]([Math]::Min($InitialDelaySec * [math]::Pow(2, $attempt - 1), 600))
                Log-Message "Retrying in ${delay}s..." -MessageType INFO
                Start-Sleep -Seconds $delay
            } else { throw }
        }
    }
}

#endregion

#region --- Progress tracker (bounded 0–100)

$script:ProgressTracker = [pscustomobject]@{ Used = 0; PhaseWeight = 0; PerItem = 0 }

function PT-Reset {
    $script:ProgressTracker.Used = 0
    if ($null -ne $progress) { $progress.Value = 0 }
    [System.Windows.Forms.Application]::DoEvents()
}
function PT-StartPhase([int]$weight, [int]$items = 1) {
    $script:ProgressTracker.PhaseWeight = [math]::Max(1, $weight)
    $script:ProgressTracker.PerItem = if ($items -gt 0) { [double]$weight / $items } else { [double]$weight }
}
function PT-Step([int]$itemsDone = 1) {
    $inc = [int][math]::Round($script:ProgressTracker.PerItem * $itemsDone)
    $script:ProgressTracker.Used = [math]::Min(100, $script:ProgressTracker.Used + $inc)
    if ($null -ne $progress) { $progress.Value = $script:ProgressTracker.Used }
    [System.Windows.Forms.Application]::DoEvents()
}
function PT-Add([int]$weight) {
    $script:ProgressTracker.Used = [math]::Min(100, $script:ProgressTracker.Used + [int]$weight)
    if ($null -ne $progress) { $progress.Value = $script:ProgressTracker.Used }
    [System.Windows.Forms.Application]::DoEvents()
}

#endregion

#region --- Decline / Cleanup / WID

function Decline-Updates {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter(Mandatory = $true)][scriptblock]$Filter,
        [Parameter(Mandatory = $true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false,
        [int]$Weight = 10   # progress weight for this decline phase
    )
    if ($global:CancelRequested) { throw "Operation canceled by user." }
    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL

    try {
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
    } catch {
        Log-Message "SearchUpdates failed; using empty set." -MessageType WARNING
        $updates = @()
    }

    $count = [math]::Max(1, ($updates | Measure-Object).Count)
    PT-StartPhase -weight $Weight -items $count

    if ($count -eq 1 -and $updates.Count -eq 0) {
        Log-Message "$Type updates: none found." -MessageType INFO
        PT-Step 1
        return @()
    }

    Log-Message "$Type updates: Found $($updates.Count). Declining..." -MessageType INFO
    $log = @()
    foreach ($u in $updates) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
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
        PT-Step 1
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
        [bool]$AttemptCompress,      # UI toggle
        [string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    if ($global:CancelRequested) { throw "Operation canceled by user." }
    $null = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL

    # Progress weights (tune as needed; sums stay <= 100 across whole run)
    $wDeclinePreExpired = 6
    $wDeclinePreSuperseded = 8
    $wObsoleteUpdates = 18
    $wUnneededFiles = 12
    $wObsoleteComputers = 10
    $wCompress = 20

    # Pre-decline to reduce load
    if ($IncludeExpiredUpdates) {
        Log-Message "Pre-clean: Decline expired (unapproved)..." -MessageType INFO
        Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined -and -not $_.IsApproved } `
            -ServerName $ServerName -Port $Port -UseSSL:$UseSSL -Weight $wDeclinePreExpired | Out-Null
    }

    if ($IncludeSupersededUpdates) {
        Log-Message "Pre-clean: Decline superseded (30+ days, unapproved)..." -MessageType INFO
        Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) } `
            -ServerName $ServerName -Port $Port -UseSSL:$UseSSL -Weight $wDeclinePreSuperseded | Out-Null
    }

    Import-Module UpdateServices -ErrorAction SilentlyContinue | Out-Null

    if ($IncludeUnusedUpdates) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
        try {
            Log-Message "CleanupObsoleteUpdates..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupObsoleteUpdates -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
        } catch { Log-Message ("CleanupObsoleteUpdates failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
        PT-Add $wObsoleteUpdates
    }

    if ($IncludeUnneededFiles) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
        try {
            Log-Message "CleanupUnneededContentFiles..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupUnneededContentFiles -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
        } catch { Log-Message ("CleanupUnneededContentFiles failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
        PT-Add $wUnneededFiles
    }

    if ($IncludeObsoleteComputers) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
        try {
            Log-Message "CleanupObsoleteComputers..." -MessageType INFO
            Invoke-WsusServerCleanup -CleanupObsoleteComputers -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ }
        } catch { Log-Message ("CleanupObsoleteComputers failed: {0}" -f $_.Exception.Message) -MessageType ERROR }
        PT-Add $wObsoleteComputers
    }

    if ($AttemptCompress) {
        if ($global:CancelRequested) { throw "Operation canceled by user." }
        $__iisOriginal = Set-WsusIisTuning -Apply -OriginalOut @{}
        try { Invoke-CompressUpdatesWithRetry -MaxRetries 3 -InitialDelaySec 45 }
        catch { Log-Message ("CompressUpdates failed after retries: {0}" -f $_.Exception.Message) -MessageType WARNING }
        finally { Set-WsusIisTuning -OriginalOut $__iisOriginal | Out-Null }
        PT-Add $wCompress
    } else {
        Log-Message "CompressUpdates skipped by user." -MessageType INFO
    }
}

function Run-WIDMaintenance {
    param(
        [bool]$DoCheckDB, [bool]$DoCheckFragmentation, [bool]$DoReindex, [bool]$DoShrink, [bool]$DoBackup
    )
    $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    # modest weights for DB tasks
    $wBackup = 8; $wCheckDB = 8; $wFrag = 6; $wReindex = 10; $wShrink = 6

    if ($DoBackup) {
        $backupFile = Join-Path $Config.BackupDir "SUSDB-Backup-$timestamp.bak"
        Log-Message "BACKUP DATABASE SUSDB -> $backupFile" -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
        if ($LASTEXITCODE -ne 0) { Log-Message "sqlcmd exit: $LASTEXITCODE" -MessageType ERROR }
        PT-Add $wBackup
        if ($global:CancelRequested) { throw "Operation canceled by user." }
    }
    if ($DoCheckDB) {
        Log-Message "DBCC CHECKDB" -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "DBCC CHECKDB")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
        if ($LASTEXITCODE -ne 0) { Log-Message "sqlcmd exit: $LASTEXITCODE" -MessageType ERROR }
        PT-Add $wCheckDB
        if ($global:CancelRequested) { throw "Operation canceled by user." }
    }
    if ($DoCheckFragmentation) {
        $fragmentationScript = Join-Path $Config.SqlScriptDir "wsus-verify-fragmentation.sql"
        if (Test-Path $fragmentationScript) {
            Log-Message "Check fragmentation ($fragmentationScript)" -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-i", "`"$fragmentationScript`"")
            (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
            if ($LASTEXITCODE -ne 0) { Log-Message "sqlcmd exit: $LASTEXITCODE" -MessageType ERROR }
        } else { Log-Message "Fragmentation script not found: $fragmentationScript" -MessageType WARNING }
        PT-Add $wFrag
        if ($global:CancelRequested) { throw "Operation canceled by user." }
    }
    if ($DoReindex) {
        $reindexScript = Join-Path $Config.SqlScriptDir "wsus-reindex-smart.sql"
        if (Test-Path $reindexScript) {
            Log-Message "Reindex ($reindexScript)" -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-i", "`"$reindexScript`"")
            (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
            if ($LASTEXITCODE -ne 0) { Log-Message "sqlcmd exit: $LASTEXITCODE" -MessageType ERROR }
        } else { Log-Message "Reindex script not found: $reindexScript" -MessageType WARNING }
        PT-Add $wReindex
        if ($global:CancelRequested) { throw "Operation canceled by user." }
    }
    if ($DoShrink) {
        Log-Message "DBCC SHRINKDATABASE (SUSDB, 10)" -MessageType INFO
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-l", "0", "-W", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
        (& $sqlcmdPath $args 2>&1) | ForEach-Object { Log-Message $_ }
        if ($LASTEXITCODE -ne 0) { Log-Message "sqlcmd exit: $LASTEXITCODE" -MessageType ERROR }
        PT-Add $wShrink
        if ($global:CancelRequested) { throw "Operation canceled by user." }
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
        AttemptCompress = $chkCompress.Checked
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

        # Normalize ServerName (avoid localhost)
        $serverName =
        if ($s.ServerName -and $s.ServerName -notmatch '^(localhost|127\.0\.0\.1)$') {
            $s.ServerName
        } else {
            $Config.FqdnHostname
        }
        $txtServer.Text = $serverName

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
        $chkCompress.Checked = if ($s.AttemptCompress -ne $null) { [bool]$s.AttemptCompress } else { $false }
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
$form.Size = New-Object System.Drawing.Size(700, 740)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

# Top panel
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Size = New-Object System.Drawing.Size(660, 60)
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
$txtServer.Size = New-Object System.Drawing.Size(200, 22)
$txtServer.Font = $font
$panelTop.Controls.Add($txtServer)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Port:"
$lblPort.Location = New-Object System.Drawing.Point(320, 20)
$lblPort.Size = New-Object System.Drawing.Size(35, 20)
$lblPort.Font = $font
$panelTop.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = "8530"
$txtPort.Location = New-Object System.Drawing.Point(360, 18)
$txtPort.Size = New-Object System.Drawing.Size(60, 22)
$txtPort.Font = $font
$panelTop.Controls.Add($txtPort)

$btnTestConnection = New-Object System.Windows.Forms.Button
$btnTestConnection.Text = "Test Connectivity"
$btnTestConnection.Location = New-Object System.Drawing.Point(430, 15)
$btnTestConnection.Size = New-Object System.Drawing.Size(135, 27)
$btnTestConnection.Font = $font
$btnTestConnection.Add_Click({
        try {
            Start-And-WaitService 'W3SVC' 180
            Start-And-WaitService 'WSUSService' 240
            Ensure-WsusPool
            $null = Test-WSUSConnection -ServerName $txtServer.Text -Port ([int]$txtPort.Text)
            $lblStatus.Text = "Connected to ${($txtServer.Text)}:${($txtPort.Text)}"
            $lblStatus.ForeColor = [System.Drawing.Color]::Green
            HTTP-Probe -Server $txtServer.Text -Port ([int]$txtPort.Text) | Out-Null
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
$lblStatus.Location = New-Object System.Drawing.Point(575, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::Black
$panelTop.Controls.Add($lblStatus)

# Tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(660, 520)
$tabControl.Location = New-Object System.Drawing.Point(15, 80)
$tabControl.Font = $font
$form.Controls.Add($tabControl)

# Tab: Updates
$tabUpdates = New-Object System.Windows.Forms.TabPage
$tabUpdates.Text = "Updates"
$tabControl.Controls.Add($tabUpdates)

$groupUpdates = New-Object System.Windows.Forms.GroupBox
$groupUpdates.Text = "Update Maintenance"
$groupUpdates.Size = New-Object System.Drawing.Size(610, 160)
$groupUpdates.Location = New-Object System.Drawing.Point(10, 10)
$groupUpdates.Font = $font
$tabUpdates.Controls.Add($groupUpdates)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline Unapproved (older than 30 days)"
$chkDeclineUnapproved.Location = New-Object System.Drawing.Point(15, 25)
$chkDeclineUnapproved.Size = New-Object System.Drawing.Size(580, 20)
$chkDeclineUnapproved.Font = $font
$groupUpdates.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline Expired"
$chkDeclineExpired.Location = New-Object System.Drawing.Point(15, 50)
$chkDeclineExpired.Size = New-Object System.Drawing.Size(580, 20)
$chkDeclineExpired.Font = $font
$groupUpdates.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline Superseded (older than 30 days, unapproved)"
$chkDeclineSuperseded.Location = New-Object System.Drawing.Point(15, 75)
$chkDeclineSuperseded.Size = New-Object System.Drawing.Size(580, 20)
$chkDeclineSuperseded.Font = $font
$groupUpdates.Controls.Add($chkDeclineSuperseded)

$chkRemoveClassifications = New-Object System.Windows.Forms.CheckBox
$chkRemoveClassifications.Text = "Decline legacy platforms (Itanium / Windows XP)"
$chkRemoveClassifications.Location = New-Object System.Drawing.Point(15, 100)
$chkRemoveClassifications.Size = New-Object System.Drawing.Size(580, 20)
$chkRemoveClassifications.Font = $font
$groupUpdates.Controls.Add($chkRemoveClassifications)

# Tab: Maintenance
$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Maintenance"
$tabControl.Controls.Add($tabMaintenance)

$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Cleanup Options"
$groupWSUS.Size = New-Object System.Drawing.Size(610, 185)
$groupWSUS.Location = New-Object System.Drawing.Point(10, 10)
$groupWSUS.Font = $font
$tabMaintenance.Controls.Add($groupWSUS)

$chkUnusedUpdates = New-Object System.Windows.Forms.CheckBox
$chkUnusedUpdates.Text = "Unused Updates and Revisions"
$chkUnusedUpdates.Location = New-Object System.Drawing.Point(15, 25)
$chkUnusedUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkUnusedUpdates.Font = $font
$groupWSUS.Controls.Add($chkUnusedUpdates)

$chkObsoleteComputers = New-Object System.Windows.Forms.CheckBox
$chkObsoleteComputers.Text = "Obsolete Computers (not contacted in 30+ days)"
$chkObsoleteComputers.Location = New-Object System.Drawing.Point(15, 50)
$chkObsoleteComputers.Size = New-Object System.Drawing.Size(580, 20)
$chkObsoleteComputers.Checked = $true
$chkObsoleteComputers.Font = $font
$groupWSUS.Controls.Add($chkObsoleteComputers)

$chkUnneededFiles = New-Object System.Windows.Forms.CheckBox
$chkUnneededFiles.Text = "Unneeded Update Files"
$chkUnneededFiles.Location = New-Object System.Drawing.Point(15, 75)
$chkUnneededFiles.Size = New-Object System.Drawing.Size(580, 20)
$chkUnneededFiles.Font = $font
$groupWSUS.Controls.Add($chkUnneededFiles)

$chkExpiredUpdates = New-Object System.Windows.Forms.CheckBox
$chkExpiredUpdates.Text = "Expired Updates (decline unapproved)"
$chkExpiredUpdates.Location = New-Object System.Drawing.Point(15, 100)
$chkExpiredUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkExpiredUpdates.Checked = $true
$chkExpiredUpdates.Font = $font
$groupWSUS.Controls.Add($chkExpiredUpdates)

$chkSupersededUpdates = New-Object System.Windows.Forms.CheckBox
$chkSupersededUpdates.Text = "Superseded Updates (decline > 30 days, unapproved)"
$chkSupersededUpdates.Location = New-Object System.Drawing.Point(15, 125)
$chkSupersededUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkSupersededUpdates.Checked = $true
$chkSupersededUpdates.Font = $font
$groupWSUS.Controls.Add($chkSupersededUpdates)

# Optional Compress toggle
$chkCompress = New-Object System.Windows.Forms.CheckBox
$chkCompress.Text = "Attempt Compress Revisions (can be slow/timeout)"
$chkCompress.Location = New-Object System.Drawing.Point(15, 150)
$chkCompress.Size = New-Object System.Drawing.Size(580, 20)
$chkCompress.Checked = $false
$chkCompress.Font = $font
$groupWSUS.Controls.Add($chkCompress)

# SQL group
$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB Maintenance Tasks"
$groupSQL.Size = New-Object System.Drawing.Size(610, 160)
$groupSQL.Location = New-Object System.Drawing.Point(10, 205)
$groupSQL.Font = $font
$tabMaintenance.Controls.Add($groupSQL)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = New-Object System.Drawing.Point(15, 25)
$chkCheckDB.Size = New-Object System.Drawing.Size(580, 20)
$chkCheckDB.Font = $font
$groupSQL.Controls.Add($chkCheckDB)

$chkCheckFragmentation = New-Object System.Windows.Forms.CheckBox
$chkCheckFragmentation.Text = "Check Index Fragmentation"
$chkCheckFragmentation.Location = New-Object System.Drawing.Point(15, 50)
$chkCheckFragmentation.Size = New-Object System.Drawing.Size(580, 20)
$chkCheckFragmentation.Font = $font
$groupSQL.Controls.Add($chkCheckFragmentation)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild Indexes"
$chkReindex.Location = New-Object System.Drawing.Point(15, 75)
$chkReindex.Size = New-Object System.Drawing.Size(580, 20)
$chkReindex.Font = $font
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink Database (use sparingly)"
$chkShrink.Location = New-Object System.Drawing.Point(15, 100)
$chkShrink.Size = New-Object System.Drawing.Size(580, 20)
$chkShrink.Font = $font
$groupSQL.Controls.Add($chkShrink)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = "Backup SUSDB"
$chkBackup.Location = New-Object System.Drawing.Point(15, 125)
$chkBackup.Size = New-Object System.Drawing.Size(580, 20)
$chkBackup.Font = $font
$groupSQL.Controls.Add($chkBackup)

# Bottom panel
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Size = New-Object System.Drawing.Size(660, 70)
$panelBottom.Location = New-Object System.Drawing.Point(15, 610)
$panelBottom.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelBottom)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 40)
$progress.Size = New-Object System.Drawing.Size(410, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$panelBottom.Controls.Add($progress)

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Ready"
$statusBar.Location = New-Object System.Drawing.Point(430, 40)
$statusBar.Size = New-Object System.Drawing.Size(210, 20)
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
$btnClose.Location = New-Object System.Drawing.Point(570, 10)
$btnClose.Font = $font
$panelBottom.Controls.Add($btnClose)

#endregion

#region --- Button handlers

$btnCancel.Add_Click({
        $global:CancelRequested = $true
        $statusBar.Text = "Cancel requested…"
        Log-Message "Operation cancel requested by user." -MessageType WARNING
    })

$btnHelp.Add_Click({
        [System.Windows.Forms.MessageBox]::Show(@"
WSUS Maintenance Tool
- Decline Unapproved/Expired/Superseded (30+ days alignment)
- Cleanup (ObsoleteUpdates, UnneededFiles, ObsoleteComputers)
- Optional Compress Revisions with retry/backoff (can be slow)
- IIS app-pool temporary tuning during Compress (auto-restore)
- SUSDB tasks (CHECKDB, fragmentation, reindex, shrink, backup)
"@, "Help", "OK", "Information") | Out-Null
        Log-Message "Help opened." -MessageType INFO
    })

$btnClose.Add_Click({
        try { Save-Settings } catch {}
        $form.Close()
    })

$btnRun.Add_Click({
        try {
            $btnRun.Enabled = $false; $btnCancel.Enabled = $true; $btnHelp.Enabled = $false; $btnClose.Enabled = $false
            $global:CancelRequested = $false
            $statusBar.Text = "Starting..."
            Log-Message "Starting WSUS maintenance..." -MessageType INFO
            Save-Settings

            # server/port normalization
            $Server = if ([string]::IsNullOrWhiteSpace($txtServer.Text) -or $txtServer.Text -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $txtServer.Text }
            $Port = [int]$txtPort.Text

            # readiness + connection
            Start-And-WaitService 'W3SVC' 180
            Start-And-WaitService 'WSUSService' 240
            Ensure-WsusPool
            $null = HTTP-Probe -Server $Server -Port $Port
            $null = Test-WSUSConnection -ServerName $Server -Port $Port

            # Reset progress tracker (bounded 0–100)
            PT-Reset

            # Selected tasks
            $tasks = @()
            if ($chkDeclineUnapproved.Checked) { $tasks += "DeclineUnapproved" }
            if ($chkDeclineExpired.Checked) { $tasks += "DeclineExpired" }
            if ($chkDeclineSuperseded.Checked) { $tasks += "DeclineSuperseded" }
            if ($chkRemoveClassifications.Checked) { $tasks += "DeclineLegacy" }
            if ($chkUnusedUpdates.Checked -or $chkObsoleteComputers.Checked -or $chkUnneededFiles.Checked -or $chkExpiredUpdates.Checked -or $chkSupersededUpdates.Checked -or $chkCompress.Checked) { $tasks += "WSUSCleanup" }
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

            $declined = @()
            foreach ($t in $tasks) {
                if ($global:CancelRequested) { throw "Operation canceled by user." }
                Log-Message "Executing: $t" -MessageType INFO
                $statusBar.Text = "Running: $t"

                switch ($t) {
                    "DeclineUnapproved" {
                        $declined += Decline-Updates -Type "Unapproved" -Filter { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) } `
                            -ServerName $Server -Port $Port -Weight 10
                    }
                    "DeclineExpired" {
                        $declined += Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined } `
                            -ServerName $Server -Port $Port -Weight 10
                    }
                    "DeclineSuperseded" {
                        $declined += Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) } `
                            -ServerName $Server -Port $Port -Weight 10
                    }
                    "DeclineLegacy" {
                        $declined += Decline-Updates -Type "Legacy" -Filter { -not $_.IsDeclined -and ($_.Title -match 'Itanium|Windows XP' -or $_.Description -match 'Itanium|Windows XP') } `
                            -ServerName $Server -Port $Port -Weight 5
                    }
                    "WSUSCleanup" {
                        Run-WSUSCleanup `
                            -IncludeUnusedUpdates   $chkUnusedUpdates.Checked `
                            -IncludeObsoleteComputers $chkObsoleteComputers.Checked `
                            -IncludeUnneededFiles   $chkUnneededFiles.Checked `
                            -IncludeExpiredUpdates  $chkExpiredUpdates.Checked `
                            -IncludeSupersededUpdates $chkSupersededUpdates.Checked `
                            -AttemptCompress        $chkCompress.Checked `
                            -ServerName $Server -Port $Port
                    }
                    { $_ -in @("CheckDB", "CheckFragmentation", "Reindex", "ShrinkDB", "BackupDB") } {
                        Run-WIDMaintenance `
                            -DoCheckDB ($t -eq "CheckDB") `
                            -DoCheckFragmentation ($t -eq "CheckFragmentation") `
                            -DoReindex ($t -eq "Reindex") `
                            -DoShrink ($t -eq "ShrinkDB") `
                            -DoBackup ($t -eq "BackupDB")
                    }
                }
            }

            if ($declined.Count -gt 0) {
                $csvFile = Join-Path $Config.CsvDir ("{0}-Declined-{1}.csv" -f $scriptName, (Get-Date -Format "yyyyMMdd-HHmmss"))
                $declined | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
                Log-Message "Declined list exported: $csvFile" -MessageType INFO
            }

            $progress.Value = 100
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
            $global:CancelRequested = $false
        }
    })

#endregion

#region --- Boot

try {
    Load-Settings
    Log-Message "Starting WSUS Maintenance GUI" -MessageType INFO
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    Log-Message "GUI closed" -MessageType INFO
}
finally {
    try { Save-Settings } catch { Log-Message ("Save-Settings failed: {0}" -f $_.Exception.Message) -MessageType WARNING }
    try { [System.Windows.Forms.Application]::ExitThread() } catch {}
}

#endregion

# End of script
