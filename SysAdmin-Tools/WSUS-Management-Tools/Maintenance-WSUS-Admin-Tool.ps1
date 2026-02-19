<#
.SYNOPSIS
    WSUS Maintenance GUI  decline, cleanup, and WID (SUSDB) tasks (Hardened Edition).

.DESCRIPTION
    Hardened GUI for WSUS maintenance:
      - Decline Unapproved/Expired/Superseded (30+ days alignment)
      - WSUS cleanup (obsolete updates, unneeded files, obsolete computers)
      - Optional "Compress Revisions" with retry/backoff and temporary IIS tuning (LOCAL WSUS ONLY)
      - SUSDB (WID) tasks via sqlcmd: backup, CHECKDB, fragmentation check, reindex, shrink

    v2.32 Hardening:
      - Cleanup operations explicitly bound to the selected WSUS server (no silent no-op)
      - Remote WSUS cleanup only allowed if Invoke-WsusServerCleanup supports server binding
      - Compress Revisions enforced as local-only (practical WSUS reality)
      - Strict module validation + fail-fast errors surfaced to UI/log
      - Robust sqlcmd runner (stdout/stderr/exit code captured deterministically)
      - Single log per run with session markers
      - UseSSL toggle persisted
      - Improved hostname normalization & local-host detection

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-12
    Version: 3.01 (Hardened Edition)
#>

param(
    [switch]$ShowConsole
)

#Requires -RunAsAdministrator

#region --- Global Setup / Strict Mode / WinForms / Admin Check

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script-scoped overrides (set when SQL scripts are generated during this session)
$script:SqlScriptDirOverride = $null
$script:GeneratedSqlPaths = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Require elevation (defensive, in addition to #Requires)
$IsAdmin = $false
try {
    $currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $IsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch {
    $IsAdmin = $false
}

if (-not $IsAdmin) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "Run this tool as Administrator.",
            "WSUS Maintenance",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch { }

    exit 1
}

# Cache WSUS connections (avoid reconnect per task) - StrictMode safe
if (-not (Get-Variable -Name 'WsusConnCache' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WsusConnCache = @{}
}

# Track whether services/pool precheck already ran in this session - StrictMode safe
if (-not (Get-Variable -Name 'WsusServicesChecked' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WsusServicesChecked = $false
}

#endregion

#region --- Console Visibility (optional)

function Set-ConsoleVisibility {
    param(
        [Parameter(Mandatory=$true)]
        [bool]$Visible
    )

    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinConsole {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop

        $h = [WinConsole]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) {
            # 0 = SW_HIDE, 5 = SW_SHOW
            $cmd = if ($Visible) { 5 } else { 0 }
            [void][WinConsole]::ShowWindow($h, $cmd)
        }
    } catch {
        # best-effort only
    }
}

if (-not $ShowConsole) {
    Set-ConsoleVisibility -Visible:$false
}

#endregion

#region --- Configuration / Directories / Logging

$script:CancelRequested = $false

$script:Config = @{
    # Provide C:\Scripts  make it the first-class default.
    SqlScriptDir  = "C:\Scripts\SUSDB"

    # Fallback (if you prefer staging scripts under Logs-TEMP)
    SqlScriptDirFallback = "C:\Logs-TEMP\WSUS-GUI\Scripts\SUSDB"

    WsusUtilPath  = "C:\Program Files\Update Services\Tools\wsusutil.exe"

    RootDir       = "C:\Logs-TEMP\WSUS-GUI"
    LogDir        = "C:\Logs-TEMP\WSUS-GUI\Logs"
    BackupDir     = "C:\Logs-TEMP\WSUS-GUI\Backups"
    CsvDir        = "C:\Logs-TEMP\WSUS-GUI\CSV"
    SettingsFile  = "C:\Logs-TEMP\WSUS-GUI\settings.json"

    FqdnHostname  = $null
    LogPath       = $null
}

function Get-HostFqdnSafe {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.Domain -and $cs.Domain -ne $cs.DNSHostName) {
            return "$($cs.DNSHostName).$($cs.Domain)"
        }
        if ($cs.DNSHostName) { return $cs.DNSHostName }
    } catch { }

    try { return [System.Net.Dns]::GetHostEntry('').HostName } catch { }
    return $env:COMPUTERNAME
}

$script:Config.FqdnHostname = Get-HostFqdnSafe

foreach ($dir in @($Config.RootDir, $Config.LogDir, $Config.BackupDir, $Config.CsvDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

# Single log per run (hardened standard)
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:Config.LogPath = Join-Path $Config.LogDir ("{0}.log" -f $scriptName)

function Log-Message {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")][string]$MessageType="INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $Message"
    try {
        Add-Content -Path $Config.LogPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {
        # If logging fails, do not crash the tool
    }
}

function Log-SessionStart {
    Log-Message ("=" * 92) "INFO"
    Log-Message ("WSUS MAINTENANCE SESSION START: {0}" -f (Get-Date)) "INFO"
    Log-Message ("Host: {0}" -f $Config.FqdnHostname) "INFO"
    Log-Message ("Log:  {0}" -f $Config.LogPath) "INFO"
    Log-Message ("=" * 92) "INFO"
}

function Log-SessionEnd {
    Log-Message ("=" * 92) "INFO"
    Log-Message ("WSUS MAINTENANCE SESSION END: {0}" -f (Get-Date)) "INFO"
    Log-Message ("=" * 92) "INFO"
}

function Show-UiMessage {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title="WSUS Maintenance",
        [ValidateSet("Info","Warning","Error")][string]$Kind="Info"
    )

    $icon =
        switch ($Kind) {
            "Info"    { [System.Windows.Forms.MessageBoxIcon]::Information }
            "Warning" { [System.Windows.Forms.MessageBoxIcon]::Warning }
            "Error"   { [System.Windows.Forms.MessageBoxIcon]::Error }
        }

    [System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}

Log-SessionStart
Log-Message ("Detected FQDN: {0}" -f $Config.FqdnHostname) "INFO"

#endregion

#region --- External Dependencies (sqlcmd)

function Get-SqlCmdPath {
    try {
        $cmd = Get-Command sqlcmd.exe -ErrorAction Stop
        return $cmd.Source
    } catch { return $null }
}

$script:sqlcmdPath = Get-SqlCmdPath
if (-not $sqlcmdPath) {
    Show-UiMessage -Kind Error -Text "sqlcmd.exe not found. Install SQLCMD tools or add it to PATH."
    Log-Message "sqlcmd.exe not found. Install SQLCMD tools or add it to PATH." "ERROR"
    Log-SessionEnd
    exit 1
}
Log-Message ("Using sqlcmd.exe: {0}" -f $sqlcmdPath) "INFO"

#endregion

function Set-ProgressSafe {
    [CmdletBinding()]
    param(
        # Accept both -Percent and -Value (some code uses -Value)
        [Parameter(Mandatory = $false)]
        [Alias('Value')]
        [int]$Percent = -1,

        [Parameter(Mandatory = $false)]
        [string]$Status = "",

        [Parameter(Mandatory = $false)]
        [System.Windows.Forms.ProgressBar]$ProgressBar,

        [Parameter(Mandatory = $false)]
        [System.Windows.Forms.Label]$StatusLabel,

        [Parameter(Mandatory = $false)]
        [switch]$Marquee
    )

    try {
        # Clamp the percentage
        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }

        # ──────────────────────────────
        # ProgressBar
        # ──────────────────────────────
        if ($ProgressBar) {
            if ($Marquee) {
                # Switch to Marquee only if needed
                if ($ProgressBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Marquee) {
                    $ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
                }
            }
            else {
                # Switch to Continuous only if needed
                if ($ProgressBar.Style -ne [System.Windows.Forms.ProgressBarStyle]::Continuous) {
                    $ProgressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                }

                # Update value only if different
                if ($ProgressBar.Value -ne $Percent) {
                    $ProgressBar.Value = $Percent
                }
            }
        }

        # ──────────────────────────────
        # Status Label
        # ──────────────────────────────
        if ($StatusLabel -and -not [string]::IsNullOrWhiteSpace($Status)) {
            # Update only if text is really different
            if ($StatusLabel.Text -ne $Status) {
                $StatusLabel.Text = $Status
            }
        }
    }
    catch {
        # Best effort logging — never break the script because of UI update
        if (Get-Command Log-Message -ErrorAction SilentlyContinue) {
            try {
                Log-Message "Set-ProgressSafe non-critical error: $($_.Exception.Message)" "DEBUG"
            }
            catch { }
        }
    }
}

#region --- Helpers: Local Host Detection / Services / IIS / WSUS

function Test-IsLocalHostName {
    param([Parameter(Mandatory)][string]$ServerName)

    $s = $ServerName.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($s)) { return $true }
    if ($s -match '^(localhost|127\.0\.0\.1)$') { return $true }

    $localNames = @()
    try { $localNames += $env:COMPUTERNAME.ToLowerInvariant() } catch { }
    try { $localNames += $Config.FqdnHostname.ToLowerInvariant() } catch { }
    try { $localNames += ([System.Net.Dns]::GetHostName()).ToLowerInvariant() } catch { }

    return ($localNames | Where-Object { $_ -and $_ -eq $s } | Measure-Object).Count -gt 0
}

function Start-And-WaitService {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$TimeoutSec=240
    )

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Log-Message "Service $Name not found." "WARNING"; return }

    if ($svc.Status -ne 'Running') {
        try { Start-Service $Name -ErrorAction SilentlyContinue } catch { }
    }

    try {
        $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSec)) | Out-Null
        Log-Message "Service $Name Running." "INFO"
    } catch {
        Log-Message "Timeout waiting for service $Name." "WARNING"
    }
}

function Ensure-WsusPool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Recycle
    )

    try {
        Import-Module WebAdministration -ErrorAction Stop

        if (-not (Test-Path IIS:\AppPools\WsusPool)) {
            Log-Message "AppPool 'WsusPool' not found." "WARNING"
            return
        }

        $item  = Get-Item IIS:\AppPools\WsusPool -ErrorAction Stop
        $state = [string]$item.state

        if ($state -ne 'Started') {
            Start-WebAppPool -Name 'WsusPool' -ErrorAction Stop
            Log-Message "WsusPool started." "INFO"
            return
        }

        if ($Recycle) {
            # Recycle only when explicitly requested (avoids destabilizing WSUS during long cleanup)
            Restart-WebAppPool -Name 'WsusPool' -ErrorAction Stop
            Log-Message "WsusPool recycled." "INFO"
        } else {
            Log-Message "WsusPool already started (no recycle requested)." "DEBUG"
        }
    }
    catch {
        Log-Message ("Ensure-WsusPool: IIS/WebAdministration unavailable or operation failed: {0}" -f $_.Exception.Message) "WARNING"
    }
}

function HTTP-Probe {
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][int]$Port,
        [switch]$UseSSL
    )

    try {
        $scheme = if ($UseSSL) { "https" } else { "http" }
        $u = "{0}://{1}:{2}/SelfUpdate/wuident.cab" -f $scheme, $Server, $Port
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 8
        if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) {
            Log-Message ("HTTP probe OK ({0}:{1}, SSL={2})" -f $Server, $Port, $UseSSL) "DEBUG"
            return $true
        }
    } catch {
        Log-Message ("HTTP probe failed ({0}:{1}, SSL={2}): {3}" -f $Server, $Port, $UseSSL, $_.Exception.Message) "WARNING"
    }
    return $false
}

function Set-WsusDbTimeoutIfAvailable {
    param([Parameter(Mandatory)][object]$Wsus)

    try {
        $cfg = $Wsus.GetConfiguration()
        if ($cfg -and ($cfg | Get-Member -Name DatabaseCommandTimeout -ErrorAction SilentlyContinue)) {
            if (-not $cfg.DatabaseCommandTimeout -or $cfg.DatabaseCommandTimeout -lt 10800) {
                $cfg.DatabaseCommandTimeout = 10800
                $cfg.Save()
                Log-Message ("Set WSUS DatabaseCommandTimeout to {0}s." -f $cfg.DatabaseCommandTimeout) "DEBUG"
            }
        }
    } catch {
        Log-Message ("Skip DB timeout tune: {0}" -f $_.Exception.Message) "DEBUG"
    }
}

function Get-WSUSServerSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [int]$Port = 8530,

        [Parameter(Mandatory = $false)]
        [switch]$UseSsl,

        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh
    )

    if ([string]::IsNullOrWhiteSpace($ServerName)) {
        $ServerName = $script:WsusServerName
    }
    if (-not $Port) { $Port = 8530 }

    $sslBool = [bool]$UseSsl
    $key = ("{0}|{1}|{2}" -f $ServerName.ToLowerInvariant(), $Port, $sslBool)

    if (-not $ForceRefresh -and $script:WsusConnCache.ContainsKey($key) -and $script:WsusConnCache[$key]) {
        Log-Message ("Reusing cached WSUS connection: {0}:{1} SSL={2}" -f $ServerName, $Port, $sslBool) "DEBUG"
        return $script:WsusConnCache[$key]
    }

    Log-Message ("Connecting to WSUS: {0}:{1} SSL={2}" -f $ServerName, $Port, $sslBool) "DEBUG"

    try {
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer(
            $ServerName,
            $sslBool,
            $Port
        )

        $script:WsusConnCache[$key] = $wsus
        return $wsus
    }
    catch {
        Log-Message ("GetUpdateServer failed for {0}:{1} SSL={2} -> {3}" -f $ServerName, $Port, $sslBool, $_.Exception.Message) "ERROR"
        return $null
    }
}


function Ensure-WsusServicesAndPool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Server
    )
    try {
        Start-And-WaitService -Name 'W3SVC'       -TimeoutSec 120
        Start-And-WaitService -Name 'WSUSService' -TimeoutSec 300

        # Start the pool if needed, but do NOT recycle by default (prevents transient SCM errors during long cleanup)
        Ensure-WsusPool | Out-Null

        # IMPORTANT: mark as done so Test-WSUSConnection does NOT repeat this work
        $script:WsusServicesChecked = $true
        Log-Message "Service/pool precheck completed (session flag set)." "DEBUG"
    }
    catch {
        Log-Message ("Ensure-WsusServicesAndPool failed: {0}" -f $_.Exception.Message) "ERROR"
        throw
    }
}

function Resolve-WsusEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServerName,

        [Parameter(Mandatory = $false)]
        [int]$Port = 8530,

        [Parameter(Mandatory = $false)]
        [bool]$UseSSL = $false
    )

    # Normalize server name (prefer configured FQDN when user supplies localhost/blank)
    $sv = ("" + $ServerName).Trim()
    if ([string]::IsNullOrWhiteSpace($sv) -or $sv -match '^(localhost|127\.0\.0\.1)$') {
        if ($Config -and $Config.FqdnHostname) {
            $sv = [string]$Config.FqdnHostname
        }
    }

    # Normalize port
    if (-not $Port -or $Port -lt 1 -or $Port -gt 65535) {
        $Port = 8530
    }

    # Return a small object used everywhere
    [pscustomobject]@{
        Server = $sv
        Port   = [int]$Port
        UseSSL = [bool]$UseSSL
        Key    = ("{0}|{1}|{2}" -f $sv.ToLowerInvariant(), [int]$Port, [bool]$UseSSL)
    }
}

function Wait-WsusServicesStable {
    [CmdletBinding()]
    param(
        [int]$TimeoutSec = 90
    )

    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            $w3  = Get-Service -Name 'W3SVC' -ErrorAction SilentlyContinue
            $ws  = Get-Service -Name 'WSUSService' -ErrorAction SilentlyContinue

            $ok = $true
            foreach ($s in @($w3, $ws)) {
                if ($null -eq $s) { continue }
                if ($s.Status -ne 'Running') { $ok = $false; break }
            }

            if ($ok) { return $true }
        } catch { }

        Start-Sleep -Seconds 3
    }
    return $false
}

function Test-WSUSConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false,
        [switch]$ForceRefresh
    )

    # Normalize and compute cache key
    $ep = Resolve-WsusEndpoint -ServerName $ServerName -Port $Port -UseSSL:$UseSSL

    # StrictMode-safe cache ensure (defensive)
if (-not (Get-Variable -Name 'WsusConnCache' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WsusConnCache = @{}
}
if (-not (Get-Variable -Name 'WsusServicesChecked' -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WsusServicesChecked = $false
}


    # Return cached WSUS object if present (eliminates repeated probe/connect)
    if (-not $ForceRefresh -and $script:WsusConnCache -and $script:WsusConnCache.ContainsKey($ep.Key) -and $script:WsusConnCache[$ep.Key]) {
        Log-Message ("Reusing cached WSUS connection: {0}:{1} SSL={2}" -f $ep.Server, $ep.Port, $ep.UseSSL) "DEBUG"
        return $script:WsusConnCache[$ep.Key]
    }

    # Service/pool precheck only once per session
    if (-not $script:WsusServicesChecked) {
        Start-And-WaitService 'W3SVC' 180
        Start-And-WaitService 'WSUSService' 240
        Ensure-WsusPool | Out-Null
        $script:WsusServicesChecked = $true
    }
    else {
        Log-Message "Skipping service/pool precheck (already done this session)." "DEBUG"
    }

    # Probe once (still useful for fast failure)
    $null = HTTP-Probe -Server $ep.Server -Port $ep.Port -UseSSL:$ep.UseSSL

    # Connect (only pass -UseSsl if enabled)
    $wsus = if ($ep.UseSSL) {
        Get-WSUSServerSafe -ServerName $ep.Server -Port $ep.Port -UseSsl
    } else {
        Get-WSUSServerSafe -ServerName $ep.Server -Port $ep.Port
    }

    if (-not $wsus) { throw "WSUS connection failed." }

    Log-Message ("Connected to WSUS: {0}:{1} SSL={2}" -f $wsus.Name, $ep.Port, $ep.UseSSL) "INFO"
    Set-WsusDbTimeoutIfAvailable -Wsus $wsus

    # Cache for the rest of the run/session
    if ($script:WsusConnCache) {
        $script:WsusConnCache[$ep.Key] = $wsus
    }

    return $wsus
}

# Cache WSUS connections (avoid reconnect per task)
$script:WsusConnCache = @{}

function Get-WsusCacheKey {
    param([string]$Server,[int]$Port,[bool]$UseSSL)
    return ("{0}:{1}:ssl={2}" -f $Server.Trim().ToLowerInvariant(), $Port, $UseSSL)
}

function Get-WSUSConnectionCached {
    param(
        [Parameter(Mandatory)][string]$Server,
        [int]$Port=8530,
        [bool]$UseSSL=$false
    )

    $key = Get-WsusCacheKey -Server $Server -Port $Port -UseSSL $UseSSL
    if ($script:WsusConnCache.ContainsKey($key) -and $script:WsusConnCache[$key]) {
        return $script:WsusConnCache[$key]
    }

    $wsus = Test-WSUSConnection -ServerName $Server -Port $Port -UseSSL:$UseSSL
    $script:WsusConnCache[$key] = $wsus
    return $wsus
}

function Import-UpdateServicesStrict {
    if (-not (Get-Module -ListAvailable -Name UpdateServices)) {
        throw "UpdateServices module not found. Install WSUS management tools / RSAT WSUS."
    }
    Import-Module UpdateServices -ErrorAction Stop | Out-Null

    if (-not (Get-Command Invoke-WsusServerCleanup -ErrorAction SilentlyContinue)) {
        throw "Invoke-WsusServerCleanup cmdlet not available after importing UpdateServices."
    }
}

function Get-WsusCleanupBindingSplat {
    param([Parameter(Mandatory)][object]$Wsus)

    $cmd = Get-Command Invoke-WsusServerCleanup -ErrorAction Stop
    $splat = @{ Confirm = $false }

    if ($cmd.Parameters.ContainsKey('UpdateServer')) { $splat.UpdateServer = $Wsus; return $splat }
    if ($cmd.Parameters.ContainsKey('WsusServer'))   { $splat.WsusServer   = $Wsus; return $splat }
    if ($cmd.Parameters.ContainsKey('Server'))       { $splat.Server       = $Wsus; return $splat }

    # No binding param available: remote cleanup is not safe -> fail
    throw "Invoke-WsusServerCleanup has no supported server binding parameter (UpdateServer/WsusServer/Server)."
}

# IIS tuning for CompressUpdates (auto-restore)
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
            $orig_idle    = (($poolCfg -split "`n") | Where-Object { $_ -match '^processModel\.idleTimeout:' }) -replace '.*:',''
            $orig_queue   = (($poolCfg -split "`n") | Where-Object { $_ -match '^queueLength:' }) -replace '.*:',''
            $orig_recycle = (($poolCfg -split "`n") | Where-Object { $_ -match '^recycling\.periodicRestart\.time:' }) -replace '.*:',''

            $changed.IdleTimeout        = $orig_idle
            $changed.QueueLength        = $orig_queue
            $changed.PeriodicRestartTime= $orig_recycle

            & $appcmd set apppool "$pool" /processModel.idleTimeout:"00:00:00" | Out-Null
            & $appcmd set apppool "$pool" /queueLength:20000 | Out-Null
            & $appcmd set apppool "$pool" /recycling\.periodicRestart\.time:"00:00:00" | Out-Null

            Log-Message "Applied IIS tuning on WsusPool." "DEBUG"
        }
        elseif ($OriginalOut) {
            if ($OriginalOut.IdleTimeout) {
                & $appcmd set apppool "$pool" /processModel.idleTimeout:$($OriginalOut.IdleTimeout) | Out-Null
            }
            if ($OriginalOut.QueueLength) {
                & $appcmd set apppool "$pool" /queueLength:$($OriginalOut.QueueLength) | Out-Null
            }
            if ($OriginalOut.PeriodicRestartTime) {
                & $appcmd set apppool "$pool" /recycling\.periodicRestart\.time:$($OriginalOut.PeriodicRestartTime) | Out-Null
            }
            Log-Message "Restored IIS tuning on WsusPool." "DEBUG"
        }
    } catch {
        Log-Message ("IIS tuning skipped: {0}" -f $_.Exception.Message) "DEBUG"
    }

    return $changed
}

function Invoke-CompressUpdatesWithRetry {
    param(
        [int]$MaxRetries=3,
        [int]$InitialDelaySec=45
    )

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        if ($script:CancelRequested) { throw "Operation canceled by user." }
        $attempt++

        try {
            Log-Message ("Invoke-WsusServerCleanup -CompressUpdates (attempt {0}/{1}) ..." -f $attempt, $MaxRetries) "INFO"
            Invoke-WsusServerCleanup -CompressUpdates -Confirm:$false -Verbose 2>&1 | ForEach-Object { Log-Message $_ "INFO" }
            Log-Message ("CompressUpdates completed on attempt {0}." -f $attempt) "INFO"
            return
        } catch {
            Log-Message ("CompressUpdates failed (attempt {0}): {1}" -f $attempt, $_.Exception.Message) "WARNING"

            if ($attempt -lt $MaxRetries) {
                $delay = [int]([Math]::Min($InitialDelaySec * [Math]::Pow(2, $attempt-1), 600))
                Log-Message ("Retrying in {0}s..." -f $delay) "INFO"
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

#endregion

#region --- Progress tracker (bounded 0100)

$script:ProgressTracker = [pscustomobject]@{
    Used        = 0
    PhaseWeight = 0
    PerItem     = 0
}

function PT-Reset {
    $script:ProgressTracker.Used = 0
    if ($null -ne $progress) { $progress.Value = 0 }
    [System.Windows.Forms.Application]::DoEvents()
}

function PT-StartPhase {
    param([int]$weight,[int]$items=1)

    $script:ProgressTracker.PhaseWeight = [Math]::Max(1, $weight)
    if ($items -gt 0) {
        $script:ProgressTracker.PerItem = [double]$weight / [double]$items
    } else {
        $script:ProgressTracker.PerItem = [double]$weight
    }
}

function PT-Step {
    param([int]$itemsDone=1)

    $inc = [int][Math]::Round($script:ProgressTracker.PerItem * $itemsDone)
    $script:ProgressTracker.Used = [Math]::Min(100, $script:ProgressTracker.Used + $inc)
    if ($null -ne $progress) { $progress.Value = $script:ProgressTracker.Used }
    [System.Windows.Forms.Application]::DoEvents()
}

function PT-Add {
    param([int]$weight)

    $script:ProgressTracker.Used = [Math]::Min(100, $script:ProgressTracker.Used + [int]$weight)
    if ($null -ne $progress) { $progress.Value = $script:ProgressTracker.Used }
    [System.Windows.Forms.Application]::DoEvents()
}

#endregion

#region --- WSUS Decline / Cleanup / WID Maintenance (Hardened)

function Decline-Updates {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][scriptblock]$Filter,
        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port=8530,
        [bool]$UseSSL=$false,
        [int]$Weight=10
    )

    if ($script:CancelRequested) { throw "Operation canceled by user." }

    $wsus = Get-WSUSConnectionCached -Server $ServerName -Port $Port -UseSSL:$UseSSL

    try {
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
    } catch {
        Log-Message ("SearchUpdates failed for {0}: {1}" -f $Type, $_.Exception.Message) "WARNING"
        $updates = @()
    }

    $count = [Math]::Max(1, ($updates | Measure-Object).Count)
    PT-StartPhase -weight $Weight -items $count

    if (($updates | Measure-Object).Count -eq 0) {
        Log-Message ("{0} updates: none found." -f $Type) "INFO"
        PT-Step 1
        return @()
    }

    Log-Message ("{0} updates: Found {1}. Declining..." -f $Type, $updates.Count) "INFO"

    $log = @()
    foreach ($u in $updates) {
        if ($script:CancelRequested) { throw "Operation canceled by user." }

        try {
            $u.Decline()
            Log-Message ("Declined ({0}): {1}" -f $Type, $u.Title) "INFO"

            $log += [pscustomobject]@{
                KB         = ($u.KnowledgeBaseArticles -join ',')
                Title      = $u.Title
                Type       = $Type
                Date       = $u.CreationDate
                DeclinedOn = (Get-Date)
                Server     = $ServerName
            }
        } catch {
            Log-Message ("Decline failed ({0}): {1} :: {2}" -f $Type, $u.Title, $_.Exception.Message) "ERROR"
        }

        PT-Step 1
    }

    return $log
}

# Wrapper used by the UI task dispatcher (Run Current Tab / Run All Tabs)
# Declines updates that have **no approvals** and are older than the provided threshold.
function Decline-WSUSUnapproved {
    <#
      Wrapper used by the UI task dispatcher.
      Declines updates that have NO approvals and are older than the provided threshold.
      Notes:
        - Uses Decline-Updates() in this script (Type/Filter/ServerName/Port/UseSSL).
        - Accepts multiple parameter names for backward/dispatcher compatibility.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(1,3650)]
        [Alias('Days')]
        [int]$OlderThanDays = 30,

                [Parameter(Mandatory=$false)]
        [Alias('Server')]
        [string]$ServerName,

        [Parameter(Mandatory=$false)]
        [int]$Port = 8530,

        [Parameter(Mandatory=$false)]
        [bool]$UseSSL = $false
    )

    $cutoff = (Get-Date).AddDays(-1 * [double]$OlderThanDays)
    Log-Message ("DeclineUnapproved: scanning for updates with 0 approvals older than {0} day(s) (cutoff={1})" -f $OlderThanDays, $cutoff.ToString('yyyy-MM-dd HH:mm:ss')) "INFO"

    $filter = {
        try {
            if ($_.IsDeclined) { return $false }

            $approvals = $null
            try { $approvals = $_.GetUpdateApprovals() } catch { $approvals = $null }

            $isApproved = ($approvals -ne $null -and @($approvals).Count -gt 0)
            if ($isApproved) { return $false }

            $dt = $null
            if ($_.PSObject.Properties.Name -contains 'CreationDate') { $dt = $_.CreationDate }
            elseif ($_.PSObject.Properties.Name -contains 'ArrivalDate') { $dt = $_.ArrivalDate }

            if ($dt -eq $null) { return $true } # conservative for cleanup: unknown date -> eligible
            return ($dt -lt $cutoff)
        } catch {
            return $false
        }
    }

    Decline-Updates -Type "Unapproved" -Filter $filter -ServerName $ServerName -Port $Port -UseSSL:$UseSSL -Weight 10
}
function Invoke-WsusCleanupAction {
    param(
        [Parameter(Mandatory)][object]$Wsus,
        [Parameter(Mandatory)][hashtable]$Switches,
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][bool]$IsRemoteTarget
    )

    if ($script:CancelRequested) { throw "Operation canceled by user." }

    Import-UpdateServicesStrict

    # If remote target, require that Invoke-WsusServerCleanup supports binding
    $binding = $null
    try {
        $binding = Get-WsusCleanupBindingSplat -Wsus $Wsus
    } catch {
        if ($IsRemoteTarget) {
            throw ("Remote WSUS cleanup is not supported in this environment: {0}" -f $_.Exception.Message)
        }
        # local WSUS: allow fallback to default binding if no param exists (rare), but still warn
        Log-Message ("Cleanup binding parameter missing; proceeding local-only. Details: {0}" -f $_.Exception.Message) "WARNING"
        $binding = @{ Confirm = $false }
    }

    $splat = @{}
    foreach ($k in $binding.Keys) { $splat[$k] = $binding[$k] }
    foreach ($k in $Switches.Keys) { $splat[$k] = $Switches[$k] }

    Log-Message ("WSUS cleanup action: {0}" -f $ActionName) "INFO"
    Log-Message ("Cleanup target WSUS: {0}" -f $Wsus.Name) "DEBUG"

    Invoke-WsusServerCleanup @splat -Verbose 2>&1 | ForEach-Object { Log-Message $_ "INFO" }
}

function Resolve-SqlScriptDir {
    param(
        [string]$OverrideDir
    )

    # User override (GUI selection) has top priority
    if (-not [string]::IsNullOrWhiteSpace($OverrideDir)) {
        try {
            if (-not (Test-Path -LiteralPath $OverrideDir)) {
                New-Item -ItemType Directory -Path $OverrideDir -Force | Out-Null
            }
            return $OverrideDir
        } catch {
            Write-Log -Level "WARNING" -Message ("Could not use override SQL script directory: {0} ({1})" -f $OverrideDir, $_.Exception.Message)
        }
    }

    $primary  = $Config.SqlScriptDir          # C:\Scripts\SUSDB
    $fallback = $Config.SqlScriptDirFallback  # C:\Logs-TEMP\WSUS-GUI\Scripts\SUSDB

    foreach ($p in @($primary, $fallback)) {
        try {
            if (-not (Test-Path -LiteralPath $p)) {
                New-Item -ItemType Directory -Path $p -Force | Out-Null
            }
            if (Test-Path -LiteralPath $p) { return $p }
        } catch {
            Write-Log -Level "WARNING" -Message ("Could not ensure SQL script directory: {0} ({1})" -f $p, $_.Exception.Message)
        }
    }

    function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('DEBUG','INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    # Map to canonical logger
    Log-Message $Message $Level
}

    # Last resort: temp under %ProgramData%
    $last = Join-Path -Path $env:ProgramData -ChildPath "WSUS-GUI\Scripts\SUSDB"
    try {
        if (-not (Test-Path -LiteralPath $last)) {
            New-Item -ItemType Directory -Path $last -Force | Out-Null
        }
        return $last
    } catch {
        throw ("Unable to create any SQL script directory. Tried: {0} ; {1} ; {2}" -f $primary, $fallback, $last)
    }
}

function Run-WSUSCleanup {
    param(
        [bool]$IncludeUnusedUpdates,
        [bool]$IncludeObsoleteComputers,
        [bool]$IncludeUnneededFiles,
        [bool]$IncludeExpiredUpdates,
        [bool]$IncludeSupersededUpdates,
        [bool]$AttemptCompress,
        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port=8530,
        [bool]$UseSSL=$false
    )

    if ($script:CancelRequested) { throw "Operation canceled by user." }

    $ServerNormalized =
        if ([string]::IsNullOrWhiteSpace($ServerName) -or $ServerName -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $ServerName }

    $isRemote = -not (Test-IsLocalHostName -ServerName $ServerNormalized)

    # Connect once, reuse
    $wsus = Get-WSUSConnectionCached -Server $ServerNormalized -Port $Port -UseSSL:$UseSSL

    # Weights
    $wDeclinePreExpired      = 6
    $wDeclinePreSuperseded   = 8
    $wObsoleteUpdates        = 18
    $wUnneededFiles          = 12
    $wObsoleteComputers      = 10
    $wCompress               = 20

    # Pre-decline: reduces cleanup load
    if ($IncludeExpiredUpdates) {
        Log-Message "Pre-clean: Decline expired (unapproved)..." "INFO"
        Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined -and -not $_.IsApproved } `
            -Server $ServerNormalized -Port $Port -UseSSL:$UseSSL -Weight $wDeclinePreExpired | Out-Null
    }

    if ($IncludeSupersededUpdates) {
        Log-Message "Pre-clean: Decline superseded (30+ days, unapproved)..." "INFO"
        Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) } `
            -Server $ServerNormalized -Port $Port -UseSSL:$UseSSL -Weight $wDeclinePreSuperseded | Out-Null
    }

    # Cleanup actions (explicitly bound)
    if ($IncludeUnusedUpdates) {
        try {
            Invoke-WsusCleanupAction -Wsus $wsus -IsRemoteTarget:$isRemote -ActionName "CleanupObsoleteUpdates" -Switches @{
                CleanupObsoleteUpdates = $true
                Confirm = $false
            }
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '(?i)tempo limite|timeout|time[- ]?out') {
                $hint = "CleanupObsoleteUpdates timed out. On large SUSDB/WID environments this is common. Recommended: run CheckDB + Reindex first, then retry CleanupObsoleteUpdates in a later maintenance window."
                Log-Message ($msg + " :: " + $hint) "WARNING"
                Show-UiMessage -Kind Warning -Text ($msg + "`r`n`r`n" + $hint)
            } else {
                Log-Message $msg "ERROR"
                Show-UiMessage -Kind Error -Text $msg
            }
        }
        PT-Add $wObsoleteUpdates
    }

    if ($IncludeUnneededFiles) {
        try {
            Invoke-WsusCleanupAction -Wsus $wsus -IsRemoteTarget:$isRemote -ActionName "CleanupUnneededContentFiles" -Switches @{
                CleanupUnneededContentFiles = $true
                Confirm = $false
            }
        } catch {
            Log-Message $_.Exception.Message "ERROR"
            Show-UiMessage -Kind Error -Text $_.Exception.Message
        }
        PT-Add $wUnneededFiles
    }

    if ($IncludeObsoleteComputers) {
        try {
            Invoke-WsusCleanupAction -Wsus $wsus -IsRemoteTarget:$isRemote -ActionName "CleanupObsoleteComputers" -Switches @{
                CleanupObsoleteComputers = $true
                Confirm = $false
            }
        } catch {
            Log-Message $_.Exception.Message "ERROR"
            Show-UiMessage -Kind Error -Text $_.Exception.Message
        }
        PT-Add $wObsoleteComputers
    }

    # Compress: enforce local-only
    if ($AttemptCompress) {
        if ($isRemote) {
            $msg = "Compress Revisions is enforced as LOCAL-ONLY. Run this tool on the WSUS server itself (selected: $ServerNormalized)."
            Log-Message $msg "WARNING"
            Show-UiMessage -Kind Warning -Text $msg
        } else {
            Import-UpdateServicesStrict

            $__iisOriginal = Set-WsusIisTuning -Apply -OriginalOut @{}
            try {
                Invoke-CompressUpdatesWithRetry -MaxRetries 3 -InitialDelaySec 45
            } catch {
                Log-Message ("CompressUpdates failed after retries: {0}" -f $_.Exception.Message) "WARNING"
                Show-UiMessage -Kind Warning -Text ("CompressUpdates failed: {0}" -f $_.Exception.Message)
            } finally {
                Set-WsusIisTuning -OriginalOut $__iisOriginal | Out-Null
            }

            PT-Add $wCompress
        }
    } else {
        Log-Message "CompressUpdates skipped by user." "INFO"
    }
}

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory)][string]$Arg)

    # If already quoted, keep as-is
    if ($Arg.Length -ge 2 -and $Arg.StartsWith('"') -and $Arg.EndsWith('"')) {
        return $Arg
    }

    # Escape embedded quotes
    $escaped = $Arg -replace '"', '\"'

    # Quote if whitespace or special chars that commonly break parsing
    if ($escaped -match '\s|[&\(\)\^\%\!\|<>]') {
        return '"' + $escaped + '"'
    }

    return $escaped
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath

    # Join arguments with robust quoting so tools like sqlcmd receive -Q / -i strings correctly.
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument $_ }) -join ' ')

    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    try {
        # Keep sqlcmd/native tool output legible in logs (avoid mojibake)
        $oemCp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        $enc = [System.Text.Encoding]::GetEncoding($oemCp)
        $psi.StandardOutputEncoding = $enc
        $psi.StandardErrorEncoding  = $enc
    } catch { }
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    [void]$p.Start()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    $p.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $p.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Invoke-SqlCmdWID {
    param(
        [Parameter(Mandatory)][string[]]$SqlCmdArgs
    )

    $res = Invoke-ExternalProcess -FilePath $sqlcmdPath -Arguments $SqlCmdArgs

    if ($res.StdOut) {
        $res.StdOut -split "(`r`n|`n)" | Where-Object { $_ -ne '' } | ForEach-Object { Log-Message $_ "INFO" }
    }
    if ($res.StdErr) {
        $res.StdErr -split "(`r`n|`n)" | Where-Object { $_ -ne '' } | ForEach-Object { Log-Message $_ "ERROR" }
    }

    if ($res.ExitCode -ne 0) {
        throw ("sqlcmd.exe exit code: {0}" -f $res.ExitCode)
    }
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
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"

    $wBackup=8; $wCheckDB=8; $wFrag=6; $wReindex=10; $wShrink=6

    $sqlDir = Resolve-SqlScriptDir

    if ($DoBackup) {
        $backupFile = Join-Path $Config.BackupDir ("SUSDB-Backup-{0}.bak" -f $ts)
        Log-Message ("BACKUP DATABASE SUSDB -> {0}" -f $backupFile) "INFO"

        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-W", "-f","65001", "-t", "0", "-Q",
                  ("BACKUP DATABASE SUSDB TO DISK = '{0}' WITH INIT" -f $backupFile))

        try { Invoke-SqlCmdWID -SqlCmdArgs $args } catch { Log-Message $_.Exception.Message "ERROR"; throw }
        PT-Add $wBackup
        if ($script:CancelRequested) { throw "Operation canceled by user." }
    }

    if ($DoCheckDB) {
        Log-Message "DBCC CHECKDB" "INFO"
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-W", "-f","65001", "-t", "0", "-Q", "DBCC CHECKDB (SUSDB) WITH NO_INFOMSGS")
        try { Invoke-SqlCmdWID -SqlCmdArgs $args } catch { Log-Message $_.Exception.Message "ERROR"; throw }
        PT-Add $wCheckDB
        if ($script:CancelRequested) { throw "Operation canceled by user." }
    }

    if ($DoCheckFragmentation) {
        $fragmentationScript = Join-Path $sqlDir "wsus-verify-fragmentation.sql"
        if (-not (Test-Path $fragmentationScript)) {
            Log-Message ("Fragmentation script missing. Attempting to generate into: {0}" -f $sqlDir) "WARNING"
            try {
                $gen = Generate-WsusReindexScripts -OutDir $sqlDir -IncludeClassic:$false
                if ($gen -and (Test-Path $gen.Verify)) {
                    $fragmentationScript = $gen.Verify
                    Log-Message ("Fragmentation script generated: {0}" -f $fragmentationScript) "INFO"
                }
            } catch {
                Log-Message ("Failed to auto-generate fragmentation script: {0}" -f $_.Exception.Message) "WARNING"
            }
        }

        if (-not (Test-Path $fragmentationScript)) {
            $msg = "Fragmentation script not found: $fragmentationScript"
            Log-Message $msg "WARNING"
            Show-UiMessage -Kind Warning -Text $msg
        } else {
            Log-Message ("Check fragmentation ({0})" -f $fragmentationScript) "INFO"
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-W", "-f","65001", "-t", "0", "-i", "`"$fragmentationScript`"")
            try { Invoke-SqlCmdWID -SqlCmdArgs $args } catch { Log-Message $_.Exception.Message "ERROR"; throw }
        }
        PT-Add $wFrag
        if ($script:CancelRequested) { throw "Operation canceled by user." }
    }

    if ($DoReindex) {
        $reindexScript = Join-Path $sqlDir "wsus-reindex-smart.sql"
        if (-not (Test-Path $reindexScript)) {
            Log-Message ("Reindex script missing. Attempting to generate into: {0}" -f $sqlDir) "WARNING"
            try {
                $gen = Generate-WsusReindexScripts -OutDir $sqlDir -IncludeClassic:$false
                if ($gen -and (Test-Path $gen.Smart)) {
                    $reindexScript = $gen.Smart
                    Log-Message ("Reindex script generated: {0}" -f $reindexScript) "INFO"
                }
            } catch {
                Log-Message ("Failed to auto-generate reindex script: {0}" -f $_.Exception.Message) "WARNING"
            }
        }

        if (-not (Test-Path $reindexScript)) {
            $msg = "Reindex script not found: $reindexScript"
            Log-Message $msg "WARNING"
            Show-UiMessage -Kind Warning -Text $msg
        } else {
            Log-Message ("Reindex ({0})" -f $reindexScript) "INFO"
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-W", "-f","65001", "-t", "0", "-i", "`"$reindexScript`"")
            try { Invoke-SqlCmdWID -SqlCmdArgs $args } catch { Log-Message $_.Exception.Message "ERROR"; throw }
        }
        PT-Add $wReindex
        if ($script:CancelRequested) { throw "Operation canceled by user." }
    }

    if ($DoShrink) {
        Log-Message "DBCC SHRINKDATABASE (SUSDB, 10)" "WARNING"
        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-b", "-W", "-f","65001", "-t", "0", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
        try { Invoke-SqlCmdWID -SqlCmdArgs $args } catch { Log-Message $_.Exception.Message "ERROR"; throw }
        PT-Add $wShrink
        if ($script:CancelRequested) { throw "Operation canceled by user." }
    }
}

#endregion

#region --- Settings (persist)

function Save-Settings {
    try {
        function Get-TextSafe {
            param([string]$VarName, [string]$Default = "")
            $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
            if ($v -and $v.Value -and $v.Value.PSObject.Properties.Match('Text').Count -gt 0) {
                try { return [string]$v.Value.Text } catch { return $Default }
            }
            return $Default
        }
        function Get-CheckedSafe {
            param([string]$VarName, [bool]$Default = $false)
            $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
            if ($v -and $v.Value -is [System.Windows.Forms.CheckBox]) {
                try { return [bool]$v.Value.Checked } catch { return $Default }
            }
            return $Default
        }
        function Get-NumericSafe {
            param([string]$VarName, [int]$Default = 0)
            $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
            if ($v -and $v.Value -is [System.Windows.Forms.NumericUpDown]) {
                try { return [int]$v.Value.Value } catch { return $Default }
            }
            return $Default
        }

        $s = [ordered]@{
            ServerName  = (Get-TextSafe -VarName 'txtServer' -Default $Config.FqdnHostname)
            Port        = (Get-TextSafe -VarName 'txtPort'   -Default "8530")
            UseSSL      = (Get-CheckedSafe -VarName 'chkUseSSL' -Default $false)

            DeclineUnapproved     = (Get-CheckedSafe -VarName 'chkDeclineUnapproved' -Default $false)
            DeclineExpired        = (Get-CheckedSafe -VarName 'chkDeclineExpired' -Default $true)
            DeclineSuperseded     = (Get-CheckedSafe -VarName 'chkDeclineSuperseded' -Default $true)

            CleanupUnusedUpdates     = (Get-CheckedSafe -VarName 'chkCleanupUnusedUpdates' -Default $false)
            CleanupObsoleteComputers = (Get-CheckedSafe -VarName 'chkCleanupObsoleteComputers' -Default $false)
            CleanupUnneededFiles     = (Get-CheckedSafe -VarName 'chkCleanupUnneededFiles' -Default $false)
            CleanupExpiredUpdates    = (Get-CheckedSafe -VarName 'chkCleanupExpiredUpdates' -Default $false)
            CleanupSupersededUpdates = (Get-CheckedSafe -VarName 'chkCleanupSupersededUpdates' -Default $false)

            CompressRevisions = (Get-CheckedSafe -VarName 'chkCompress' -Default $false)

            CheckDB            = (Get-CheckedSafe -VarName 'chkCheckDB' -Default $false)
            CheckFragmentation = (Get-CheckedSafe -VarName 'chkCheckFragmentation' -Default $false)
            Reindex            = (Get-CheckedSafe -VarName 'chkReindex' -Default $false)
            ShrinkDB           = (Get-CheckedSafe -VarName 'chkShrink' -Default $false)
            BackupDB           = (Get-CheckedSafe -VarName 'chkBackup' -Default $false)

            DeclineUnapprovedDays = (Get-NumericSafe -VarName 'nudDeclineUnapprovedDays' -Default 30)
            DeclineSupersededDays = (Get-NumericSafe -VarName 'nudDeclineSupersededDays' -Default 30)
        }

        $dir = Split-Path -Parent $Config.SettingsFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        ($s | ConvertTo-Json -Depth 6) | Set-Content -Path $Config.SettingsFile -Encoding UTF8 -Force
    } catch {
        Log-Message ("Save-Settings failed: {0}" -f $_.Exception.Message) "WARNING"
    }
}

function Load-Settings {
    if (-not (Test-Path $Config.SettingsFile)) { return }

    try {
        $s = Get-Content $Config.SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Log-Message ("Load-Settings failed: {0}" -f $_.Exception.Message) "WARNING"
        return
    }

    function Set-TextSafe {
        param([string]$VarName, [string]$Value)
        $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
        if ($v -and $v.Value -and $v.Value.PSObject.Properties.Match('Text').Count -gt 0) {
            try { $v.Value.Text = $Value } catch { }
        }
    }
    function Set-CheckedSafe {
        param([string]$VarName, [bool]$Value)
        $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
        if ($v -and $v.Value -is [System.Windows.Forms.CheckBox]) {
            try { $v.Value.Checked = $Value } catch { }
        }
    }
    function Set-NumericSafe {
        param([string]$VarName, [int]$Value)
        $v = Get-Variable -Name $VarName -Scope Script -ErrorAction SilentlyContinue
        if ($v -and $v.Value -is [System.Windows.Forms.NumericUpDown]) {
            try { $v.Value.Value = [decimal]$Value } catch { }
        }
    }

    $serverName =
        if ($s.ServerName -and $s.ServerName -notmatch '^(localhost|127\.0\.0\.1)$') { [string]$s.ServerName } else { [string]$Config.FqdnHostname }

    Set-TextSafe -VarName 'txtServer' -Value $serverName
    Set-TextSafe -VarName 'txtPort'   -Value ($(if ($s.Port) { [string]$s.Port } else { "8530" }))

    Set-CheckedSafe -VarName 'chkUseSSL' -Value ($(if ($s.UseSSL -ne $null) { [bool]$s.UseSSL } else { $false }))

    # Updates tab (align with wizard + existing options)
    Set-CheckedSafe -VarName 'chkDeclineUnapproved' -Value ([bool]$s.DeclineUnapproved)
    Set-CheckedSafe -VarName 'chkDeclineExpired'    -Value ($(if ($s.DeclineExpired -ne $null) { [bool]$s.DeclineExpired } else { $true }))
    Set-CheckedSafe -VarName 'chkDeclineSuperseded' -Value ($(if ($s.DeclineSuperseded -ne $null) { [bool]$s.DeclineSuperseded } else { $true }))

    Set-CheckedSafe -VarName 'chkCleanupUnusedUpdates'    -Value ([bool]$s.CleanupUnusedUpdates)
    Set-CheckedSafe -VarName 'chkCleanupObsoleteComputers' -Value ([bool]$s.CleanupObsoleteComputers)
    Set-CheckedSafe -VarName 'chkCleanupUnneededFiles'    -Value ([bool]$s.CleanupUnneededFiles)
    Set-CheckedSafe -VarName 'chkCleanupExpiredUpdates'   -Value ([bool]$s.CleanupExpiredUpdates)
    Set-CheckedSafe -VarName 'chkCleanupSupersededUpdates' -Value ([bool]$s.CleanupSupersededUpdates)

    Set-CheckedSafe -VarName 'chkCompress' -Value ([bool]$s.CompressRevisions)

    # Maintenance tab
    Set-CheckedSafe -VarName 'chkCheckDB'            -Value ([bool]$s.CheckDB)
    Set-CheckedSafe -VarName 'chkCheckFragmentation' -Value ([bool]$s.CheckFragmentation)
    Set-CheckedSafe -VarName 'chkReindex'            -Value ([bool]$s.Reindex)
    Set-CheckedSafe -VarName 'chkShrink'             -Value ([bool]$s.ShrinkDB)
    Set-CheckedSafe -VarName 'chkBackup'             -Value ([bool]$s.BackupDB)

    Set-NumericSafe -VarName 'nudDeclineUnapprovedDays'  -Value ($(if ($s.DeclineUnapprovedDays) { [int]$s.DeclineUnapprovedDays } else { 30 }))
    Set-NumericSafe -VarName 'nudDeclineSupersededDays'  -Value ($(if ($s.DeclineSupersededDays) { [int]$s.DeclineSupersededDays } else { 30 }))
} 

#endregion


#region --- Preflight (Admin API + Inventory + SQL Generator)

function Run-WsusCleanupWizard {
    [CmdletBinding()]
    param(
        [bool]$IncludeUnusedUpdates,
        [bool]$IncludeObsoleteComputers,
        [bool]$IncludeUnneededFiles,
        [bool]$IncludeExpiredUpdates,
        [bool]$IncludeSupersededUpdates,
        [bool]$AttemptCompress,

        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )

    if ($script:CancelRequested) { throw "Operation canceled by user." }

    $ServerNormalized =
        if ([string]::IsNullOrWhiteSpace($ServerName) -or $ServerName -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $ServerName }

    $isRemote = -not (Test-IsLocalHostName -ServerName $ServerNormalized)

    # Connect once (cache handles reuse)
    $wsus = Get-WSUSConnectionCached -Server $ServerNormalized -Port $Port -UseSSL:$UseSSL

    function Invoke-CleanupStep {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][hashtable]$Switches
        )

        if ($script:CancelRequested) { throw "Operation canceled by user." }

        try {
            Invoke-WsusCleanupAction -Wsus $wsus -IsRemoteTarget:$isRemote -ActionName $Name -Switches $Switches | Out-Null
            return $true
        }
        catch {
            $msg = $_.Exception.Message

            # Timeout handling (very common on large WSUS/SUSDB)
            if ($msg -match '(?i)tempo limite|timeout|time[- ]?out|Execution Timeout') {
                Log-Message ("{0} timed out. This is common on large WSUS/SUSDB. Continuing with next step. Details: {1}" -f $Name, $msg) "WARNING"
                return $false
            }

            # SCM transient: "service cannot accept control messages at this time"
            if ($msg -match '(?i)não pode aceitar mensagens de controle|cannot accept control messages') {
                Log-Message ("{0} hit transient service-control state. Will stabilize services and retry once. Details: {1}" -f $Name, $msg) "WARNING"
                try {
                    Start-And-WaitService -Name 'W3SVC'       -TimeoutSec 120
                    Start-And-WaitService -Name 'WSUSService' -TimeoutSec 300
                    Ensure-WsusPool | Out-Null
                    [void](Wait-WsusServicesStable -TimeoutSec 90)
                } catch { }

                Start-Sleep -Seconds 10

                try {
                    Invoke-WsusCleanupAction -Wsus $wsus -IsRemoteTarget:$isRemote -ActionName $Name -Switches $Switches | Out-Null
                    return $true
                } catch {
                    Log-Message ("{0} retry failed. Continuing with next step. Details: {1}" -f $Name, $_.Exception.Message) "WARNING"
                    return $false
                }
            }

            # Non-timeout errors should stop the run (safer)
            throw
        }
    }

    # Mirror the WSUS Cleanup Wizard semantics (native flags)
    if ($IncludeUnusedUpdates) {
        [void](Invoke-CleanupStep -Name "CleanupObsoleteUpdates" -Switches @{ CleanupObsoleteUpdates = $true })
    }
    if ($IncludeObsoleteComputers) {
        [void](Invoke-CleanupStep -Name "CleanupObsoleteComputers" -Switches @{ CleanupObsoleteComputers = $true })
    }
    if ($IncludeUnneededFiles) {
        [void](Invoke-CleanupStep -Name "CleanupUnneededContentFiles" -Switches @{ CleanupUnneededContentFiles = $true })
    }
    if ($IncludeExpiredUpdates) {
        [void](Invoke-CleanupStep -Name "DeclineExpiredUpdates" -Switches @{ DeclineExpiredUpdates = $true })
    }
    if ($IncludeSupersededUpdates) {
        [void](Invoke-CleanupStep -Name "DeclineSupersededUpdates" -Switches @{ DeclineSupersededUpdates = $true })
    }

    if ($AttemptCompress -and -not $script:CancelRequested) {
        Invoke-WsusCompressRevisionsHardened -ServerName $ServerNormalized -Port $Port -UseSSL:$UseSSL
    }
}

function Invoke-WsusCompressRevisionsHardened {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )

    if ($script:CancelRequested) { throw "Operation canceled by user." }

    $ServerNormalized =
        if ([string]::IsNullOrWhiteSpace($ServerName) -or $ServerName -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $ServerName }

    if (-not (Test-IsLocalHostName -ServerName $ServerNormalized)) {
        Log-Message "Compress Revisions is blocked on remote targets (Hardened rule)." "WARNING"
        return
    }

    Log-Message "Compress Revisions: starting (local-only)..." "INFO"
    Invoke-CompressUpdatesWithRetry -ServerName $ServerNormalized -Port $Port -UseSSL:$UseSSL | Out-Null
    Log-Message "Compress Revisions: completed." "INFO"
}

function Invoke-DeclineLegacyPlatforms {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )

    Log-Message "Decline legacy platforms: option is currently not implemented in this build." "WARNING"
    Log-Message "Reason: classification/product matching is environment-specific and risky without an explicit allowlist." "WARNING"
}

function Import-WsusAdminApi {
    [CmdletBinding()]
    param()

    # 1) Known path
    $dll = Join-Path $env:ProgramFiles 'Update Services\Api\Microsoft.UpdateServices.Administration.dll'
    if (Test-Path -LiteralPath $dll) {
        try {
            Add-Type -LiteralPath $dll -ErrorAction Stop | Out-Null
            Log-Message ("Loaded WSUS Admin API from: {0}" -f $dll) "INFO"
            return $true
        } catch {
            Log-Message ("Failed loading WSUS Admin API from {0}: {1}" -f $dll, $_.Exception.Message) "WARNING"
        }
    }

    # 2) GAC / partial
    try {
        [void][reflection.assembly]::LoadWithPartialName('Microsoft.UpdateServices.Administration')
        Log-Message "Loaded WSUS Admin API via GAC/LoadWithPartialName." "INFO"
        return $true
    } catch {
        Log-Message ("Failed loading WSUS Admin API via GAC: {0}" -f $_.Exception.Message) "WARNING"
    }

    # 3) Module fallback
    try {
        if (Get-Module -ListAvailable -Name UpdateServices) {
            Import-Module UpdateServices -ErrorAction Stop
            Log-Message "Imported UpdateServices module (fallback)." "INFO"
            return $true
        }
    } catch {
        Log-Message ("Failed importing UpdateServices module: {0}" -f $_.Exception.Message) "WARNING"
    }

    return $false
}

function Test-WsusAdminApi {
    [CmdletBinding()]
    param(
        [string]$ServerName,
        [int]$Port = 8530,
        [switch]$UseSSL,
        [switch]$TestConnection
    )

    if (-not (Import-WsusAdminApi)) {
        throw "WSUS Admin API not available. Install WSUS Admin Console / API on this machine."
    }

    if (-not $TestConnection) {
        return [pscustomobject]@{
            Success = $true
            Stage   = "Load"
            Server  = $null
            Port    = $null
            UseSSL  = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($ServerName)) { throw "ServerName is required for connection test." }

    # Prefer explicit binding: AdminProxy.GetUpdateServer(host, useSsl, port)
    try {
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, [bool]$UseSSL, [int]$Port)
        $v = $wsus.Version
        $cfg = $wsus.GetConfiguration()
        return [pscustomobject]@{
            Success      = $true
            Stage        = "Connect"
            Server       = $ServerName
            Port         = $Port
            UseSSL       = [bool]$UseSSL
            WsusVersion  = [string]$v
            ContentDir   = [string]$cfg.LocalContentCachePath
            IsReplica    = [bool]$cfg.IsReplicaServer
        }
    } catch {
        throw ("WSUS Admin API connection failed: {0}" -f $_.Exception.Message)
    }
}

function Get-WsusSetupRegistry {
    [CmdletBinding()]
    param()

    $base = 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
    if (-not (Test-Path $base)) { return $null }

    $p = Get-ItemProperty -Path $base -ErrorAction Stop

    # Important values: SqlServerName, SqlDatabaseName, UsingSSL, PortNumber, ContentDir
    [pscustomobject]@{
        SetupKey        = $base
        WsusVersion     = [string]$p.Version
        ContentDir      = [string]$p.ContentDir
        SqlServerName   = [string]$p.SqlServerName
        SqlDatabaseName = [string]$p.SqlDatabaseName
        UsingSSL        = [bool]$p.UsingSSL
        PortNumber      = [int]$p.PortNumber
        TargetingMode   = [string]$p.TargetingMode
    }
}

function Get-WsusDbConnectionInfo {
    [CmdletBinding()]
    param()

    $s = Get-WsusSetupRegistry
    if (-not $s) { return $null }

    $isWid = $false
    if ($s.SqlServerName -match 'MICROSOFT##WID' -or $s.SqlServerName -match '\\\\.\\pipe\\MICROSOFT##WID') { $isWid = $true }
    if ($s.SqlServerName -match 'np:\\\\.\\pipe\\MICROSOFT##WID\\tsql\\query') { $isWid = $true }

    $widPipe = 'np:\\.\pipe\MICROSOFT##WID\tsql\query'

    [pscustomobject]@{
        Engine        = if ($isWid) { "WID" } else { "SQL" }
        Database      = if ($s.SqlDatabaseName) { $s.SqlDatabaseName } else { "SUSDB" }
        SqlServerName = $s.SqlServerName
        WidPipe       = $widPipe
    }
}

function Invoke-WsusEnvironmentInventory {
    [CmdletBinding()]
    param(
        [string]$ServerName,
        [int]$Port = 8530,
        [switch]$UseSSL,
        [string]$OutDir = (Join-Path $Config.LogDir 'Inventory')
    )

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $jsonPath = Join-Path $OutDir ("wsus-inventory-{0}.json" -f $ts)
    $csvPath  = Join-Path $OutDir ("wsus-inventory-summary-{0}.csv" -f $ts)

    $setup = $null
    try { $setup = Get-WsusSetupRegistry } catch { }

    $svc = @('WSUSService','W3SVC','BITS') | ForEach-Object {
        $o = [ordered]@{ Name = $_; Status = $null; StartType = $null }
        try {
            $s = Get-Service -Name $_ -ErrorAction Stop
            $o.Status = [string]$s.Status
            try { $o.StartType = (Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f $_)).StartMode } catch { }
        } catch { $o.Status = "NotFound" }
        [pscustomobject]$o
    }

    $iis = [ordered]@{
        SiteBinding  = $null
        WsusPool     = $null
        HasWebAdmin  = $false
    }

    if (Get-Module -ListAvailable -Name WebAdministration) {
        try {
            Import-Module WebAdministration -ErrorAction Stop
            $iis.HasWebAdmin = $true
            try {
                $bind = Get-WebBinding -Name 'WSUS Administration' -ErrorAction Stop | Select-Object -First 1
                if ($bind) { $iis.SiteBinding = ("{0}:{1}" -f $bind.protocol, $bind.bindingInformation) }
            } catch { }
            try {
                $p = Get-Item "IIS:\AppPools\WsusPool" -ErrorAction Stop
                if ($p) {
                    $iis.WsusPool = [ordered]@{
                        State                = (Get-WebAppPoolState -Name 'WsusPool').Value
                        ManagedRuntimeVersion = $p.managedRuntimeVersion
                        QueueLength          = $p.queueLength
                        PrivateMemoryMB      = [int]([math]::Round(($p.recycling.periodicRestart.privateMemory / 1024.0),0))
                    }
                }
            } catch { }
        } catch {
            Log-Message ("WebAdministration inventory failed: {0}" -f $_.Exception.Message) "WARNING"
        }
    }

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [pscustomobject]@{
            Drive = $_.DeviceID
            SizeGB = [math]::Round($_.Size/1GB,2)
            FreeGB = [math]::Round($_.FreeSpace/1GB,2)
            FreePct = if ($_.Size) { [math]::Round(($_.FreeSpace/$_.Size)*100,2) } else { $null }
        }
    }

    $db = $null
    try { $db = Get-WsusDbConnectionInfo } catch { }

    $api = $null
    try { $api = Test-WsusAdminApi -ServerName $ServerName -Port $Port -UseSSL:$UseSSL -TestConnection } catch { $api = [pscustomobject]@{ Success=$false; Error=$_.Exception.Message } }

    $report = [ordered]@{
        Timestamp = (Get-Date).ToString("o")
        Host      = $env:COMPUTERNAME
        User      = [string]([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        WSUS      = [ordered]@{
            TargetServer = $ServerName
            Port         = $Port
            UseSSL       = [bool]$UseSSL
            Setup        = $setup
            ApiCheck     = $api
        }
        Database  = $db
        Services  = $svc
        IIS       = $iis
        Disks     = $disks
    }

    ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    # Flatten summary
    $summary = [pscustomobject]@{
        Timestamp     = $report.Timestamp
        Host          = $report.Host
        TargetServer  = $ServerName
        Port          = $Port
        UseSSL        = [bool]$UseSSL
        SetupVersion  = if ($setup) { $setup.WsusVersion } else { $null }
        ContentDir    = if ($setup) { $setup.ContentDir } else { $null }
        DbEngine      = if ($db) { $db.Engine } else { $null }
        DbName        = if ($db) { $db.Database } else { $null }
        ApiSuccess    = [bool]($api.Success)
        WsusPoolState = if ($iis.WsusPool) { $iis.WsusPool.State } else { $null }
        DiskFreeWorstPct = ($disks | Sort-Object FreePct | Select-Object -First 1).FreePct
    }
    $summary | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

    Log-Message ("Inventory exported: {0} ; {1}" -f $jsonPath, $csvPath) "INFO"

    return [pscustomobject]@{
        JsonPath = $jsonPath
        CsvPath  = $csvPath
        Report   = $report
    }
}

function New-WsusReindexSqlScripts {
    [CmdletBinding()]
    param(
        [string]$OutDir = $Config.SqlScriptDir,
        [int]$MinPages = 1000,
        [int]$ReorgPct = 10,
        [int]$RebuildPct = 30,
        [switch]$IncludeClassic
    )

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $verify = @"
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

SET NOCOUNT ON;
SELECT
  DB_NAME() AS [DatabaseName],
  OBJECT_SCHEMA_NAME(ips.object_id) AS [SchemaName],
  OBJECT_NAME(ips.object_id) AS [TableName],
  i.name AS [IndexName],
  ips.index_id AS [IndexId],
  ips.page_count AS [PageCount],
  ips.avg_fragmentation_in_percent AS [FragPct],
  CASE
    WHEN ips.page_count < $MinPages THEN 'SKIP (small index)'
    WHEN ips.avg_fragmentation_in_percent >= $RebuildPct THEN 'REBUILD'
    WHEN ips.avg_fragmentation_in_percent >= $ReorgPct THEN 'REORGANIZE'
    ELSE 'OK'
  END AS [Recommendation]
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
  ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0
  AND i.is_disabled = 0
ORDER BY ips.avg_fragmentation_in_percent DESC, ips.page_count DESC;
"@

    $smart = @"
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

SET NOCOUNT ON;

DECLARE @MinPages INT = $MinPages;
DECLARE @ReorgPct FLOAT = $ReorgPct;
DECLARE @RebuildPct FLOAT = $RebuildPct;

DECLARE @schema SYSNAME, @table SYSNAME, @index SYSNAME, @sql NVARCHAR(MAX);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT
  OBJECT_SCHEMA_NAME(ips.object_id) AS SchemaName,
  OBJECT_NAME(ips.object_id) AS TableName,
  i.name AS IndexName,
  ips.page_count,
  ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
  ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0
  AND i.is_disabled = 0
  AND ips.page_count >= @MinPages
  AND ips.avg_fragmentation_in_percent >= @ReorgPct
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN c;

DECLARE @page_count BIGINT, @frag FLOAT;

FETCH NEXT FROM c INTO @schema, @table, @index, @page_count, @frag;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF (@frag >= @RebuildPct)
        SET @sql = N'ALTER INDEX [' + REPLACE(@index,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REBUILD WITH (ONLINE = OFF);';
    ELSE
        SET @sql = N'ALTER INDEX [' + REPLACE(@index,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REORGANIZE;';

    PRINT @sql;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM c INTO @schema, @table, @index, @page_count, @frag;
END

CLOSE c;
DEALLOCATE c;

EXEC sp_updatestats;
"@

    $classic = @"
SET NOCOUNT ON;

-- Classic WSUS SUSDB maintenance (high-churn tables)
DECLARE @ReorgPct FLOAT = $ReorgPct;
DECLARE @RebuildPct FLOAT = $RebuildPct;

-- Example hot tables (keep conservative, no fillfactor hacks by default)
DECLARE @T TABLE (SchemaName SYSNAME, TableName SYSNAME);
INSERT INTO @T VALUES
('dbo','tbRevisionSupersedesUpdate'),
('dbo','tbLocalizedPropertyForRevision'),
('dbo','tbRevision'),
('dbo','tbRevisionInCategory'),
('dbo','tbXml'),
('dbo','tbProperty');

DECLARE @schema SYSNAME, @table SYSNAME, @idx SYSNAME, @sql NVARCHAR(MAX), @frag FLOAT, @pages BIGINT;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT OBJECT_SCHEMA_NAME(ips.object_id), OBJECT_NAME(ips.object_id), i.name, ips.avg_fragmentation_in_percent, ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id=i.object_id AND ips.index_id=i.index_id
JOIN @T t ON t.SchemaName=OBJECT_SCHEMA_NAME(ips.object_id) AND t.TableName=OBJECT_NAME(ips.object_id)
WHERE ips.index_id>0 AND i.is_disabled=0 AND ips.page_count >= $MinPages AND ips.avg_fragmentation_in_percent >= @ReorgPct
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN c;
FETCH NEXT FROM c INTO @schema, @table, @idx, @frag, @pages;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF (@frag >= @RebuildPct)
        SET @sql = N'ALTER INDEX [' + REPLACE(@idx,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REBUILD WITH (ONLINE = OFF);';
    ELSE
        SET @sql = N'ALTER INDEX [' + REPLACE(@idx,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REORGANIZE;';

    PRINT @sql;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM c INTO @schema, @table, @idx, @frag, @pages;
END
CLOSE c;
DEALLOCATE c;

EXEC sp_updatestats;
"@

    $verifyPath = Join-Path $OutDir "wsus-verify-fragmentation.sql"
    $smartPath  = Join-Path $OutDir "wsus-reindex-smart.sql"
    Set-Content -LiteralPath $verifyPath -Value $verify -Encoding UTF8
    Set-Content -LiteralPath $smartPath  -Value $smart  -Encoding UTF8

    $classicPath = $null
    if ($IncludeClassic) {
        $classicPath = Join-Path $OutDir "wsusdbmaintenance-classic.sql"
        Set-Content -LiteralPath $classicPath -Value $classic -Encoding UTF8
    }

    Log-Message ("Generated SQL scripts: {0} ; {1}{2}" -f $verifyPath, $smartPath, $(if($classicPath){" ; $classicPath"}else{""})) "INFO"

# Backup copy (keep a second copy under the WSUS GUI log tree)
$backupDir = $Config.SqlScriptDirFallback
try {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -Path @($verifyPath, $smartPath) -Destination $backupDir -Force
    if ($classicPath) { Copy-Item -Path $classicPath -Destination $backupDir -Force }
    Log-Message ("Backed up SQL scripts to: {0}" -f $backupDir) "INFO"
}
catch {
    Log-Message ("Failed to backup SQL scripts to {0}: {1}" -f $backupDir, $_.Exception.Message) "WARNING"
}


    # Keep the generated paths for this session and align the maintenance runner with the same directory
    $script:GeneratedSqlPaths = [pscustomobject]@{
        Verify  = $verifyPath
        Smart   = $smartPath
        Classic = $classicPath
        OutDir  = $OutDir
    }
    $script:SqlScriptDirOverride = $OutDir

    return [pscustomobject]@{
        Verify  = $verifyPath
        Smart   = $smartPath
        Classic = $classicPath
        OutDir  = $OutDir
    }
}


function Generate-WsusReindexScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OutDir = $Config.SqlScriptDir,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeClassic
    )

    # Compatibility wrapper for older call sites (Run-WIDMaintenance)
    $out = New-WsusReindexSqlScripts -OutDir $OutDir -IncludeClassic:$IncludeClassic

    # Normalize returned shape expected by Run-WIDMaintenance
    [pscustomobject]@{
        OutDir   = $out.OutDir
        Verify   = $out.Verify
        Smart    = $out.Smart
        Classic  = $out.Classic
    }
}

#endregion
#region --- GUI

$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS Maintenance Tool (Hardened v2.32)"
$form.Size = New-Object System.Drawing.Size(700, 770)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

# Top panel
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Size = New-Object System.Drawing.Size(660, 78)
$panelTop.Location = New-Object System.Drawing.Point(15, 10)
$panelTop.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelTop)

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = "WSUS Server:"
$lblServer.Location = New-Object System.Drawing.Point(10, 14)
$lblServer.Size = New-Object System.Drawing.Size(100, 20)
$lblServer.Font = $font
$panelTop.Controls.Add($lblServer)

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Text = $Config.FqdnHostname
$txtServer.Location = New-Object System.Drawing.Point(110, 12)
$txtServer.Size = New-Object System.Drawing.Size(240, 22)
$txtServer.Font = $font
$panelTop.Controls.Add($txtServer)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Port:"
$lblPort.Location = New-Object System.Drawing.Point(360, 14)
$lblPort.Size = New-Object System.Drawing.Size(35, 20)
$lblPort.Font = $font
$panelTop.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = "8530"
$txtPort.Location = New-Object System.Drawing.Point(398, 12)
$txtPort.Size = New-Object System.Drawing.Size(60, 22)
$txtPort.Font = $font
$panelTop.Controls.Add($txtPort)

$chkUseSSL = New-Object System.Windows.Forms.CheckBox
$chkUseSSL.Text = "Use SSL"
$chkUseSSL.Location = New-Object System.Drawing.Point(470, 13)
$chkUseSSL.Size = New-Object System.Drawing.Size(80, 20)
$chkUseSSL.Font = $font
$panelTop.Controls.Add($chkUseSSL)

$btnTestConnection = New-Object System.Windows.Forms.Button
$btnTestConnection.Text = "Test Connectivity"
$btnTestConnection.Location = New-Object System.Drawing.Point(555, 10)
$btnTestConnection.Size = New-Object System.Drawing.Size(95, 27)
$btnTestConnection.Font = $font
$panelTop.Controls.Add($btnTestConnection)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Font = $font
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(10, 44)
$lblStatus.ForeColor = [System.Drawing.Color]::Black
$panelTop.Controls.Add($lblStatus)

# Tabs
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(660, 545)
$tabControl.Location = New-Object System.Drawing.Point(15, 96)
$tabControl.Font = $font
$form.Controls.Add($tabControl)

# Tab: Preflight
$tabPreflight = New-Object System.Windows.Forms.TabPage
$tabPreflight.Text = "Preflight"
$tabControl.Controls.Add($tabPreflight)

$groupPreflightApi = New-Object System.Windows.Forms.GroupBox
$groupPreflightApi.Text = "Admin API / Connectivity"
$groupPreflightApi.Size = New-Object System.Drawing.Size(610, 140)
$groupPreflightApi.Location = New-Object System.Drawing.Point(10, 10)
$groupPreflightApi.Font = $font
$tabPreflight.Controls.Add($groupPreflightApi)

$btnApiLoad = New-Object System.Windows.Forms.Button
$btnApiLoad.Text = "Load Admin API"
$btnApiLoad.Size = New-Object System.Drawing.Size(150, 27)
$btnApiLoad.Location = New-Object System.Drawing.Point(15, 28)
$btnApiLoad.Font = $font
$groupPreflightApi.Controls.Add($btnApiLoad)

$btnApiTest = New-Object System.Windows.Forms.Button
$btnApiTest.Text = "Test WSUS Connect"
$btnApiTest.Size = New-Object System.Drawing.Size(150, 27)
$btnApiTest.Location = New-Object System.Drawing.Point(175, 28)
$btnApiTest.Font = $font
$groupPreflightApi.Controls.Add($btnApiTest)

$lblApiInfo = New-Object System.Windows.Forms.Label
$lblApiInfo.Text = "Tip: Use the top panel to set Server/Port/SSL, then test connectivity here."
$lblApiInfo.AutoSize = $false
$lblApiInfo.Size = New-Object System.Drawing.Size(580, 60)
$lblApiInfo.Location = New-Object System.Drawing.Point(15, 65)
$lblApiInfo.ForeColor = [System.Drawing.Color]::DimGray
$lblApiInfo.Font = $font
$groupPreflightApi.Controls.Add($lblApiInfo)

$groupPreflightInv = New-Object System.Windows.Forms.GroupBox
$groupPreflightInv.Text = "Environment Inventory"
$groupPreflightInv.Size = New-Object System.Drawing.Size(610, 120)
$groupPreflightInv.Location = New-Object System.Drawing.Point(10, 160)
$groupPreflightInv.Font = $font
$tabPreflight.Controls.Add($groupPreflightInv)

$btnInventory = New-Object System.Windows.Forms.Button
$btnInventory.Text = "Export Inventory (JSON+CSV)"
$btnInventory.Size = New-Object System.Drawing.Size(220, 27)
$btnInventory.Location = New-Object System.Drawing.Point(15, 28)
$btnInventory.Font = $font
$groupPreflightInv.Controls.Add($btnInventory)

$lblInvInfo = New-Object System.Windows.Forms.Label
$lblInvInfo.Text = "Exports to: C:\Logs-TEMP\WSUS-GUI\Inventory"
$lblInvInfo.AutoSize = $false
$lblInvInfo.Size = New-Object System.Drawing.Size(560, 60)
$lblInvInfo.Location = New-Object System.Drawing.Point(15, 60)
$lblInvInfo.ForeColor = [System.Drawing.Color]::DimGray
$lblInvInfo.Font = $font
$groupPreflightInv.Controls.Add($lblInvInfo)

$groupPreflightSql = New-Object System.Windows.Forms.GroupBox
$groupPreflightSql.Text = "SUSDB SQL Script Generator"
$groupPreflightSql.Size = New-Object System.Drawing.Size(610, 150)
$groupPreflightSql.Location = New-Object System.Drawing.Point(10, 290)
$groupPreflightSql.Font = $font
$tabPreflight.Controls.Add($groupPreflightSql)

$btnGenSql = New-Object System.Windows.Forms.Button
$btnGenSql.Text = "Generate Reindex SQL"
$btnGenSql.Size = New-Object System.Drawing.Size(170, 27)
$btnGenSql.Location = New-Object System.Drawing.Point(15, 28)
$btnGenSql.Font = $font
$groupPreflightSql.Controls.Add($btnGenSql)

$chkGenClassic = New-Object System.Windows.Forms.CheckBox
$chkGenClassic.Text = "Include classic script"
$chkGenClassic.Size = New-Object System.Drawing.Size(200, 20)
$chkGenClassic.Location = New-Object System.Drawing.Point(200, 32)
$chkGenClassic.Font = $font
$groupPreflightSql.Controls.Add($chkGenClassic)

$lblSqlGenInfo = New-Object System.Windows.Forms.Label
$lblSqlGenInfo.Text = "Generates: wsus-verify-fragmentation.sql, wsus-reindex-smart.sql (+ optional classic) under C:\Scripts\SUSDB (fallback: C:\Logs-TEMP\WSUS-GUI\Scripts\SUSDB)"
$lblSqlGenInfo.AutoSize = $false
$lblSqlGenInfo.Size = New-Object System.Drawing.Size(580, 80)
$lblSqlGenInfo.Location = New-Object System.Drawing.Point(15, 60)
$lblSqlGenInfo.ForeColor = [System.Drawing.Color]::DimGray
$lblSqlGenInfo.Font = $font
$groupPreflightSql.Controls.Add($lblSqlGenInfo)

# Tab: Updates
$tabUpdates = New-Object System.Windows.Forms.TabPage
$tabUpdates.Text = "Updates"
$tabControl.Controls.Add($tabUpdates)

# WSUS Server Cleanup Wizard (native Admin API)
$groupCleanup = New-Object System.Windows.Forms.GroupBox
$groupCleanup.Text = "WSUS Server Cleanup Wizard (Admin API)"
$groupCleanup.Size = New-Object System.Drawing.Size(610, 215)
$groupCleanup.Location = New-Object System.Drawing.Point(10, 10)
$groupCleanup.Font = $font
$tabUpdates.Controls.Add($groupCleanup)

$chkUnusedUpdates = New-Object System.Windows.Forms.CheckBox
$chkUnusedUpdates.Text = "Unused updates and update revisions"
$chkUnusedUpdates.Location = New-Object System.Drawing.Point(15, 25)
$chkUnusedUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkUnusedUpdates.Font = $font
$groupCleanup.Controls.Add($chkUnusedUpdates)

$chkObsoleteComputers = New-Object System.Windows.Forms.CheckBox
$chkObsoleteComputers.Text = "Computers that have not contacted the server"
$chkObsoleteComputers.Location = New-Object System.Drawing.Point(15, 50)
$chkObsoleteComputers.Size = New-Object System.Drawing.Size(580, 20)
$chkObsoleteComputers.Checked = $true
$chkObsoleteComputers.Font = $font
$groupCleanup.Controls.Add($chkObsoleteComputers)

$chkUnneededFiles = New-Object System.Windows.Forms.CheckBox
$chkUnneededFiles.Text = "Unneeded update files"
$chkUnneededFiles.Location = New-Object System.Drawing.Point(15, 75)
$chkUnneededFiles.Size = New-Object System.Drawing.Size(580, 20)
$chkUnneededFiles.Font = $font
$groupCleanup.Controls.Add($chkUnneededFiles)

$chkExpiredUpdates = New-Object System.Windows.Forms.CheckBox
$chkExpiredUpdates.Text = "Expired updates"
$chkExpiredUpdates.Location = New-Object System.Drawing.Point(15, 100)
$chkExpiredUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkExpiredUpdates.Checked = $true
$chkExpiredUpdates.Font = $font
$groupCleanup.Controls.Add($chkExpiredUpdates)

$chkSupersededUpdates = New-Object System.Windows.Forms.CheckBox
$chkSupersededUpdates.Text = "Superseded updates"
$chkSupersededUpdates.Location = New-Object System.Drawing.Point(15, 125)
$chkSupersededUpdates.Size = New-Object System.Drawing.Size(580, 20)
$chkSupersededUpdates.Checked = $true
$chkSupersededUpdates.Font = $font
$groupCleanup.Controls.Add($chkSupersededUpdates)

$chkCompress = New-Object System.Windows.Forms.CheckBox
$chkCompress.Text = "Attempt Compress Revisions (LOCAL WSUS only; can be slow/timeout)"
$chkCompress.Location = New-Object System.Drawing.Point(15, 150)
$chkCompress.Size = New-Object System.Drawing.Size(580, 20)
$chkCompress.Checked = $false
$chkCompress.Font = $font
$groupCleanup.Controls.Add($chkCompress)

$lblCompressNote = New-Object System.Windows.Forms.Label
$lblCompressNote.Text = "Hardened rule: Compress Revisions is blocked on remote targets."
$lblCompressNote.Location = New-Object System.Drawing.Point(15, 172)
$lblCompressNote.Size = New-Object System.Drawing.Size(580, 20)
$lblCompressNote.Font = $font
$lblCompressNote.ForeColor = [System.Drawing.Color]::DimGray
$groupCleanup.Controls.Add($lblCompressNote)

# Advanced / Custom rules (optional)
$groupAdvanced = New-Object System.Windows.Forms.GroupBox
$groupAdvanced.Text = "Advanced Decline Rules (Optional)"
$groupAdvanced.Size = New-Object System.Drawing.Size(610, 120)
$groupAdvanced.Location = New-Object System.Drawing.Point(10, 235)
$groupAdvanced.Font = $font
$tabUpdates.Controls.Add($groupAdvanced)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline Unapproved (older than 30 days)"
$chkDeclineUnapproved.Location = New-Object System.Drawing.Point(15, 25)
$chkDeclineUnapproved.Size = New-Object System.Drawing.Size(580, 20)
$chkDeclineUnapproved.Font = $font
$groupAdvanced.Controls.Add($chkDeclineUnapproved)

$lblDeclineUnapprovedDays = New-Object System.Windows.Forms.Label
$lblDeclineUnapprovedDays.Text = "Unapproved older than (days):"
$lblDeclineUnapprovedDays.Location = New-Object System.Drawing.Point(330, 25)
$lblDeclineUnapprovedDays.Size = New-Object System.Drawing.Size(180, 18)
$lblDeclineUnapprovedDays.Font = $font

$nudDeclineUnapprovedDays = New-Object System.Windows.Forms.NumericUpDown
$nudDeclineUnapprovedDays.Minimum = 0
$nudDeclineUnapprovedDays.Maximum = 3650
$nudDeclineUnapprovedDays.Value   = 30
$nudDeclineUnapprovedDays.Location = New-Object System.Drawing.Point(520, 22)
$nudDeclineUnapprovedDays.Size = New-Object System.Drawing.Size(80, 22)
$nudDeclineUnapprovedDays.Font = $font

$groupAdvanced.Controls.Add($lblDeclineUnapprovedDays)
$groupAdvanced.Controls.Add($nudDeclineUnapprovedDays)

$chkRemoveClassifications = New-Object System.Windows.Forms.CheckBox
$chkRemoveClassifications.Text = "Decline legacy platforms (Itanium / Windows XP) [Not implemented]"
$chkRemoveClassifications.Location = New-Object System.Drawing.Point(15, 55)
$chkRemoveClassifications.Size = New-Object System.Drawing.Size(580, 20)
$chkRemoveClassifications.Font = $font
$groupAdvanced.Controls.Add($chkRemoveClassifications)

# Tab: Maintenance

$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Maintenance"
$tabControl.Controls.Add($tabMaintenance)

# SQL group

$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB Maintenance Tasks (WID via sqlcmd)"
$groupSQL.Size = New-Object System.Drawing.Size(610, 170)
$groupSQL.Location = New-Object System.Drawing.Point(10, 10)
$groupSQL.Font = $font
$tabMaintenance.Controls.Add($groupSQL)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = New-Object System.Drawing.Point(15, 25)
$chkCheckDB.Size = New-Object System.Drawing.Size(580, 20)
$chkCheckDB.Font = $font
$groupSQL.Controls.Add($chkCheckDB)

$chkCheckFragmentation = New-Object System.Windows.Forms.CheckBox
$chkCheckFragmentation.Text = "Check Index Fragmentation (wsus-verify-fragmentation.sql)"
$chkCheckFragmentation.Location = New-Object System.Drawing.Point(15, 50)
$chkCheckFragmentation.Size = New-Object System.Drawing.Size(580, 20)
$chkCheckFragmentation.Font = $font
$groupSQL.Controls.Add($chkCheckFragmentation)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild Indexes (wsus-reindex-smart.sql)"
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

$lblSqlNote = New-Object System.Windows.Forms.Label
$lblSqlNote.Text = "SQL scripts searched in: C:\Scripts\SUSDB (fallback: C:\Logs-TEMP\WSUS-GUI\Scripts\SUSDB)"
$lblSqlNote.Location = New-Object System.Drawing.Point(15, 145)
$lblSqlNote.Size = New-Object System.Drawing.Size(580, 20)
$lblSqlNote.ForeColor = [System.Drawing.Color]::DimGray
$lblSqlNote.Font = $font
$groupSQL.Controls.Add($lblSqlNote)

#region --- Bottom panel (Run/Cancel/Help/Close + Progress/Status)

# Bottom panel
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Size = New-Object System.Drawing.Size(660, 78)
$panelBottom.Location = New-Object System.Drawing.Point(15, 650)
$panelBottom.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelBottom)

# Progress bar
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 46)
$progress.Size = New-Object System.Drawing.Size(410, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$panelBottom.Controls.Add($progress)

# Status label
$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Ready"
$statusBar.Location = New-Object System.Drawing.Point(430, 46)
$statusBar.Size = New-Object System.Drawing.Size(215, 20)
$statusBar.Font = $font
$panelBottom.Controls.Add($statusBar)

# Run (All Tabs)
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "&Run (All Tabs)"
$btnRun.Size = New-Object System.Drawing.Size(110, 25)
$btnRun.Location = New-Object System.Drawing.Point(10, 12)
$btnRun.Enabled = $true

# Cancel
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "&Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(80, 25)
$btnCancel.Location = New-Object System.Drawing.Point(130, 12)
$btnCancel.Enabled = $false

# Help
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "&Help"
$btnHelp.Size = New-Object System.Drawing.Size(80, 25)
$btnHelp.Location = New-Object System.Drawing.Point(220, 12)
$btnHelp.Enabled = $true

# Close
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "&Close"
$btnClose.Size = New-Object System.Drawing.Size(80, 25)
$btnClose.Location = New-Object System.Drawing.Point(570, 12)

# Wire Cancel (cooperative cancellation)
$btnCancel.Add_Click({
    try {
        $script:CancelRequested = $true
        if ($statusBar) { $statusBar.Text = "Cancel requested..." }
        Log-Message "Cancel requested by user." "WARNING"
        $btnCancel.Enabled = $false
    } catch { }
})

# Wire Help
$btnHelp.Add_Click({
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "Run executes selected tasks across ALL tabs." +
            "`r`nCancel requests cooperative cancellation (tasks must check CancelRequested)." +
            "`r`nLogs: C:\Logs-TEMP\WSUS-GUI\Logs",
            "WSUS Maintenance Tool - Help",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch { }
})

# Add controls (ONCE)
$panelBottom.Controls.Add($btnRun)
$panelBottom.Controls.Add($btnCancel)
$panelBottom.Controls.Add($btnHelp)
$panelBottom.Controls.Add($btnClose)

#endregion


#region --- Button handlers (Hardened)

$btnTestConnection.Add_Click({
    try {
        $Server = if ([string]::IsNullOrWhiteSpace($txtServer.Text) -or $txtServer.Text -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $txtServer.Text }
        $Port   = [int]$txtPort.Text
        $UseSSL = [bool]$chkUseSSL.Checked

        Start-And-WaitService 'W3SVC' 180
        Start-And-WaitService 'WSUSService' 240
        Ensure-WsusPool

        $null = Test-WSUSConnection -ServerName $Server -Port $Port -UseSSL:$UseSSL

        $lblStatus.Text = ("Connected to {0}:{1} (SSL={2})" -f $Server, $Port, $UseSSL)
        $lblStatus.ForeColor = [System.Drawing.Color]::Green

        $null = HTTP-Probe -Server $Server -Port $Port -UseSSL:$UseSSL

        Log-Message "Connection test successful." "INFO"
    } catch {
        $lblStatus.Text = "Failed"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        Log-Message ("Connection test failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-UiMessage -Kind Error -Text ("Connection test failed: {0}" -f $_.Exception.Message)
    }
})


# Preflight: Admin API load
$btnApiLoad.Add_Click({
    try {
        $ok = Import-WsusAdminApi
        if ($ok) {
            Show-UiMessage -Kind Info -Text "WSUS Admin API loaded successfully."
            Log-Message "Preflight: Admin API loaded successfully." "INFO"
        } else {
            throw "WSUS Admin API not found. Install WSUS Admin Console / API."
        }
    } catch {
        Log-Message ("Preflight: Admin API load failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-UiMessage -Kind Error -Text ("Admin API load failed: {0}" -f $_.Exception.Message)
    }
})

# Preflight: WSUS connection test via Admin API
$btnApiTest.Add_Click({
    try {
        $Server = if ([string]::IsNullOrWhiteSpace($txtServer.Text) -or $txtServer.Text -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $txtServer.Text }
        $Port   = [int]$txtPort.Text
        $UseSSL = [bool]$chkUseSSL.Checked

        $r = Test-WsusAdminApi -ServerName $Server -Port $Port -UseSSL:$UseSSL -TestConnection

        $msg = @(
            "OK - WSUS connection succeeded.",
            "",
            ("Server: {0}:{1} (SSL={2})" -f $r.Server, $r.Port, $r.UseSSL),
            ("WSUS Version: {0}" -f $r.WsusVersion),
            ("Content: {0}" -f $r.ContentDir),
            ("Replica: {0}" -f $r.IsReplica)
        ) -join "`r`n"

        Show-UiMessage -Kind Info -Text $msg
        Log-Message ("Preflight: WSUS Admin API connection OK -> {0}:{1} SSL={2}" -f $Server,$Port,$UseSSL) "INFO"
    } catch {
        Log-Message ("Preflight: WSUS connection failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-UiMessage -Kind Error -Text ("WSUS connection failed: {0}" -f $_.Exception.Message)
    }
})

# Preflight: Inventory export
$btnInventory.Add_Click({
    try {
        $Server = if ([string]::IsNullOrWhiteSpace($txtServer.Text) -or $txtServer.Text -match '^(localhost|127\.0\.0\.1)$') { $Config.FqdnHostname } else { $txtServer.Text }
        $Port   = [int]$txtPort.Text
        $UseSSL = [bool]$chkUseSSL.Checked

        $result = Invoke-WsusEnvironmentInventory -ServerName $Server -Port $Port -UseSSL:$UseSSL

        Show-UiMessage -Kind Info -Text ("Inventory exported:`r`n`r`nJSON: {0}`r`nCSV:  {1}" -f $result.JsonPath, $result.CsvPath)
    } catch {
        Log-Message ("Preflight: Inventory failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-UiMessage -Kind Error -Text ("Inventory failed: {0}" -f $_.Exception.Message)
    }
})

# Preflight: Generate SQL scripts
$btnGenSql.Add_Click({
    try {
        $out = New-WsusReindexSqlScripts -IncludeClassic:([bool]$chkGenClassic.Checked)
        Show-UiMessage -Kind Info -Text ("SQL scripts generated in:`r`n{0}`r`n`r`nVerify: {1}`r`nSmart:  {2}{3}" -f $out.OutDir, $out.Verify, $out.Smart, $(if($out.Classic){"`r`nClassic: $($out.Classic)"}else{""}))
    } catch {
        Log-Message ("Preflight: SQL generation failed: {0}" -f $_.Exception.Message) "ERROR"
        Show-UiMessage -Kind Error -Text ("SQL generation failed: {0}" -f $_.Exception.Message)
    }
})
$btnCancel.Add_Click({
    $script:CancelRequested = $true
    $statusBar.Text = "Cancel requested"
    Log-Message "Operation cancel requested by user." "WARNING"
})

$btnHelp.Add_Click({
    $helpText = @"
WSUS Maintenance Tool (Hardened v2.32)

Updates:
- Decline Unapproved (older than 30 days)
- Decline Expired
- Decline Superseded (older than 30 days, unapproved)
- Decline legacy platforms (Itanium / Windows XP)

Maintenance:
- WSUS Cleanup actions are bound to the selected WSUS target (remote-safe when supported).
- Compress Revisions is enforced as LOCAL-ONLY (run on the WSUS server).

SUSDB (WID) via sqlcmd:
- Backup SUSDB
- DBCC CHECKDB
- Fragmentation check (wsus-verify-fragmentation.sql)
- Reindex (wsus-reindex-smart.sql)
- Shrink (sparingly)

Logs:
- Single log file per run:
  $($Config.LogPath)
"@

    [System.Windows.Forms.MessageBox]::Show(
        $helpText,
        "Help",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    Log-Message "Help opened." "INFO"
})

$btnClose.Add_Click({
    try { Save-Settings } catch { }
    $form.Close()
})

# Run (All Tabs)
$btnRun.Add_Click({
    try {
        Invoke-RunFromUi -Scope All
    } catch {
        # Invoke-RunFromUi already logs; keep UI safe
        try { Show-UiMessage -Kind Error -Text ("Run failed: {0}" -f $_.Exception.Message) } catch { }
    }
})


function Invoke-RunFromUi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('All','WsusOnly','SqlOnly')]
        [string]$Scope = 'All'
    )

    try {
        # --- Lock UI ---
        $btnRun.Enabled    = $false
        $btnHelp.Enabled   = $false
        $btnClose.Enabled  = $false
        $btnCancel.Enabled = $true

        $script:CancelRequested = $false

        # --- Local UI helpers (read controls safely by script-var name) ---
        function Get-ScriptVarValue {
            param([Parameter(Mandatory)][string]$Name)
            $gv = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
            if ($null -ne $gv) { return $gv.Value }
            return $null
        }

        function Get-CheckboxValue {
            param(
                [Parameter(Mandatory)][string]$Name,
                [bool]$Default = $false
            )
            $c = Get-ScriptVarValue -Name $Name
            if ($c -is [System.Windows.Forms.CheckBox]) { return [bool]$c.Checked }
            return $Default
        }

        function Get-NumericUpDownValue {
            param(
                [Parameter(Mandatory)][string]$Name,
                [int]$Default = 0
            )
            $n = Get-ScriptVarValue -Name $Name
            if ($n -is [System.Windows.Forms.NumericUpDown]) { return [int]$n.Value }
            return $Default
        }

        # --- Determine tasks from UI ---
        $tasks = @()


# --- Determine tasks from UI ---
        $tasks = @()

        # Use helpers to avoid StrictMode crashes when controls/vars differ between builds.
        $wizUnused      = (Get-CheckboxValue -Name 'chkUnusedUpdates' -Default $false) -or (Get-CheckboxValue -Name 'chkCleanupObsoleteUpdates' -Default $false)
        $wizObsoletePC  = (Get-CheckboxValue -Name 'chkObsoleteComputers' -Default $false) -or (Get-CheckboxValue -Name 'chkCleanupObsoleteComputers' -Default $false)
        $wizUnneeded    = (Get-CheckboxValue -Name 'chkUnneededFiles' -Default $false) -or (Get-CheckboxValue -Name 'chkCleanupUnneededContentFiles' -Default $false)
        $wizExpired     = (Get-CheckboxValue -Name 'chkExpiredUpdates' -Default $false) -or (Get-CheckboxValue -Name 'chkDeclineExpired' -Default $false)
        $wizSuperseded  = (Get-CheckboxValue -Name 'chkSupersededUpdates' -Default $false) -or (Get-CheckboxValue -Name 'chkDeclineSuperseded' -Default $false)
        $wizCompress    = (Get-CheckboxValue -Name 'chkCompress' -Default $false) -or (Get-CheckboxValue -Name 'chkCompressRevisions' -Default $false)

        $doDeclineUnapproved = (Get-CheckboxValue -Name 'chkDeclineUnapproved' -Default $false)
        if ($doDeclineUnapproved) { $tasks += "DeclineUnapproved" }

        # WSUS Server Cleanup Wizard (native Admin API flags)
        if ($wizUnused -or $wizObsoletePC -or $wizUnneeded -or $wizExpired -or $wizSuperseded -or $wizCompress) {
            $tasks += "WsusCleanupWizard"
        }

        # Legacy platforms: kept as a separate task (optional, environment-specific)
        $doLegacyPlatforms = (Get-CheckboxValue -Name 'chkRemoveClassifications' -Default $false) -or (Get-CheckboxValue -Name 'chkDeclineLegacyPlatforms' -Default $false)
        if ($doLegacyPlatforms) { $tasks += "DeclineLegacyPlatforms" }

        # --- Maintenance tab (SUSDB/WID via sqlcmd) ---
        # Accept multiple possible control names so the runner works across your iterations.
        $doCheckDB = (Get-CheckboxValue -Name 'chkCheckDB' -Default $false) -or (Get-CheckboxValue -Name 'chkDbccCheckDb' -Default $false)
        if ($doCheckDB) { $tasks += "CheckDB" }

        $doFrag = (Get-CheckboxValue -Name 'chkCheckFragmentation' -Default $false) -or (Get-CheckboxValue -Name 'chkCheckIndexFragmentation' -Default $false)
        if ($doFrag) { $tasks += "CheckFragmentation" }

        $doReindex = (Get-CheckboxValue -Name 'chkReindex' -Default $false) -or (Get-CheckboxValue -Name 'chkRebuildIndexes' -Default $false)
        if ($doReindex) { $tasks += "Reindex" }

        $doShrink = (Get-CheckboxValue -Name 'chkShrink' -Default $false) -or (Get-CheckboxValue -Name 'chkShrinkDatabase' -Default $false)
        if ($doShrink) { $tasks += "ShrinkDB" }

        $doBackup = (Get-CheckboxValue -Name 'chkBackup' -Default $false) -or (Get-CheckboxValue -Name 'chkBackupSusdb' -Default $false)
        if ($doBackup) { $tasks += "BackupDB" }



        # Apply scope filter
        if ($Scope -eq 'WsusOnly') {
            $tasks = $tasks | Where-Object { $_ -notin @("CheckDB","CheckFragmentation","Reindex","ShrinkDB","BackupDB") }
        }
        elseif ($Scope -eq 'SqlOnly') {
            $tasks = $tasks | Where-Object { $_ -in @("CheckDB","CheckFragmentation","Reindex","ShrinkDB","BackupDB") }
        }

        if (-not $tasks -or @($tasks).Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Select at least one task to run.",
                "WSUS Maintenance",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        Log-Message ("Run started. Tasks={0}" -f ($tasks -join ", ")) "INFO"

        # --- Normalize endpoint ONCE ---
        $Server = ""
        try { $Server = ("" + $txtServer.Text).Trim() } catch { $Server = "" }
        if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '^(localhost|127\.0\.0\.1)$') {
            if ($Config -and $Config.FqdnHostname) {
                $Server = [string]$Config.FqdnHostname
            }
        }

        $Port = 8530
        try { $Port = [int]$txtPort.Text } catch { $Port = 8530 }

        $UseSSL = $false
        try { $UseSSL = [bool]$chkUseSsl.Checked } catch { $UseSSL = $false }

        # --- Services/pool once per run ---
        Ensure-WsusServicesAndPool -Server $Server

        # --- Pre-warm WSUS connection cache once per run ---
        $null = Get-WSUSConnectionCached -Server $Server -Port $Port -UseSSL:$UseSSL

        # --- Split tasks ---
        $sqlTaskNames = @("CheckDB","CheckFragmentation","Reindex","ShrinkDB","BackupDB")
        $sqlTasks  = $tasks | Where-Object { $_ -in $sqlTaskNames }
        $wsusTasks = $tasks | Where-Object { $_ -notin $sqlTaskNames }

        # --- WSUS tasks ---
        foreach ($t in $wsusTasks) {
            if ($script:CancelRequested) { break }

            switch ($t) {
"DeclineUnapproved" {
    Decline-WSUSUnapproved -ServerName $Server -Port $Port -UseSSL:$UseSSL `
        -OlderThanDays (Get-NumericUpDownValue -Name 'nudDeclineUnapprovedDays' -Default 30)
}

"WsusCleanupWizard" {
    Run-WsusCleanupWizard `
        -IncludeUnusedUpdates:$wizUnused `
        -IncludeObsoleteComputers:$wizObsoletePC `
        -IncludeUnneededFiles:$wizUnneeded `
        -IncludeExpiredUpdates:$wizExpired `
        -IncludeSupersededUpdates:$wizSuperseded `
        -AttemptCompress:$wizCompress `
        -ServerName $Server -Port $Port -UseSSL:$UseSSL
}
"CompressRevisions" {
    # Separate task kept for backwards-compatibility; wizard can also trigger compress.
    Invoke-WsusCompressRevisionsHardened -ServerName $Server -Port $Port -UseSSL:$UseSSL
}
"DeclineLegacyPlatforms" {
    Invoke-DeclineLegacyPlatforms -ServerName $Server -Port $Port -UseSSL:$UseSSL
}


            }
        }

        # --- SQL tasks (WID/SUSDB) ---
        if (@($sqlTasks).Count -gt 0 -and -not $script:CancelRequested) {

            $doCheckDB = ($sqlTasks -contains "CheckDB")
            $doFrag    = ($sqlTasks -contains "CheckFragmentation")
            $doReindex = ($sqlTasks -contains "Reindex")
            $doShrink  = ($sqlTasks -contains "ShrinkDB")
            $doBackup  = ($sqlTasks -contains "BackupDB")

            Run-WIDMaintenance `
                -DoCheckDB:$doCheckDB `
                -DoCheckFragmentation:$doFrag `
                -DoReindex:$doReindex `
                -DoShrink:$doShrink `
                -DoBackup:$doBackup
        }

        Log-Message "Run finished." "INFO"
    }
    catch {
        Log-Message ("Run failed: {0}" -f $_.Exception.Message) "ERROR"
        throw
    }
    finally {
        # --- Unlock UI ---
        $btnRun.Enabled    = $true
        $btnHelp.Enabled   = $true
        $btnClose.Enabled  = $true
        $btnCancel.Enabled = $false
    }
}

#endregion

#region --- Boot (load settings + show GUI)

try {
    # Load persisted settings into GUI controls
    try { Load-Settings } catch { }

    Log-Message "Starting WSUS Maintenance GUI (Hardened v2.32)" "INFO"

    # Bring window to front on show
    $form.Add_Shown({
        try { $form.Activate() } catch { }
    })

    # SHOW GUI (this was missing)
    [void]$form.ShowDialog()

    Log-Message "GUI closed" "INFO"
}
catch {
    # If GUI fails to start, try to surface error at least once
    Log-Message ("Fatal startup error: {0}" -f $_.Exception.Message) "ERROR"
    try {
        [System.Windows.Forms.MessageBox]::Show(
            ("Fatal startup error:`r`n{0}" -f $_.Exception.Message),
            "WSUS Maintenance",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch { }
}
finally {
    try { Save-Settings } catch { }
    try { Log-SessionEnd } catch { }
}

#endregion

# End of script
