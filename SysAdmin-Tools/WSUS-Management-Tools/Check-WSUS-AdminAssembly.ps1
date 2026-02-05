<#
.SYNOPSIS
    WSUS Admin API / UpdateServices availability and connectivity preflight.  
    
.DESCRIPTION
    Validates that the WSUS Administration API can be loaded and (optionally) that a WSUS server
    can be reached via AdminProxy / Get-WsusServer. Designed to be used standalone or as a preflight
    dependency check by the WSUS Maintenance GUI.

    Hardened:
      - StrictMode safe (param at top)
      - Deterministic logging to C:\Logs-TEMP\WSUS-GUI\Logs
      - Robust assembly resolution chain:
          1) C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll
          2) LoadWithPartialName (GAC)
          3) UpdateServices module (if present)
      - Structured output object

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-05  -03
    Version: 1.20
#>

param(
    [string]$ServerName = "localhost",
    [int]$Port = 8530,
    [switch]$UseSSL,
    [switch]$TestConnection,
    [switch]$Quiet,
    [switch]$ShowConsole
)

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------- Logging (single log per run) -----------------
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$rootDir    = "C:\Logs-TEMP\WSUS-GUI"
$logDir     = Join-Path $rootDir "Logs"
$null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
$logPath    = Join-Path $logDir "$scriptName.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

function Show-Ui {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Title = "WSUS Admin API Check",
        [ValidateSet("Information","Warning","Error")][string]$Icon = "Information"
    )
    if ($Quiet) { return }
    $mbIcon = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', $mbIcon) | Out-Null
}

# ----------------- Console visibility (optional) -----------------
function Set-ConsoleVisibility {
    param([bool]$Visible)

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
            $cmd = if ($Visible) { 5 } else { 0 } # 5=SHOW, 0=HIDE
            [void][WinConsole]::ShowWindow($h, $cmd)
        }
    } catch {
        # best-effort
    }
}

if (-not $ShowConsole) { Set-ConsoleVisibility -Visible:$false }

# ----------------- Helpers -----------------
function Resolve-WsusAdminAssembly {
    $apiPath = "C:\Program Files\Update Services\Api\Microsoft.UpdateServices.Administration.dll"

    # Already loaded?
    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "Microsoft.UpdateServices.Administration" }
    if ($loaded) { return @{ Loaded=$true; Method="AlreadyLoaded"; Path=$null } }

    # Prefer explicit API path
    if (Test-Path $apiPath) {
        try {
            Add-Type -Path $apiPath -ErrorAction Stop
            return @{ Loaded=$true; Method="AddTypePath"; Path=$apiPath }
        } catch {
            return @{ Loaded=$false; Method="AddTypePath"; Path=$apiPath; Error=$_.Exception.Message }
        }
    }

    # GAC/PartialName fallback
    try {
        $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if ($asm) { return @{ Loaded=$true; Method="LoadWithPartialName"; Path=$asm.Location } }
    } catch {}

    # UpdateServices module presence (not the same as Admin assembly, but good signal)
    if (Get-Module -ListAvailable -Name UpdateServices) {
        return @{ Loaded=$false; Method="UpdateServicesModulePresent"; Path=$null; Error="Admin assembly not found at API path; module exists but assembly still required for AdminProxy." }
    }

    return @{ Loaded=$false; Method="NotFound"; Path=$null; Error="Microsoft.UpdateServices.Administration not found. Install WSUS Tools (UpdateServices-UI)." }
}

function Normalize-ServerName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return "localhost" }
    if ($Name -match '^(localhost|127\.0\.0\.1)$') { return "localhost" }
    return $Name.Trim()
}

function Test-WsusAdminConnection {
    param([string]$Name,[int]$Port,[bool]$UseSSL)

    # AdminProxy supports port overload depending on version. Use safest available.
    try {
        # Try 3-arg overload (server, ssl, port)
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Name, $UseSSL, $Port)
        return @{ Ok=$true; Name=$wsus.Name; Version=$wsus.Version.ToString(); Method="AdminProxy(ssl,port)" }
    } catch {
        try {
            # Try classic 2-arg overload (server, ssl) - port is implied by IIS config
            $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Name, $UseSSL)
            return @{ Ok=$true; Name=$wsus.Name; Version=$wsus.Version.ToString(); Method="AdminProxy(ssl)" }
        } catch {
            return @{ Ok=$false; Error=$_.Exception.Message }
        }
    }
}

# ----------------- Main -----------------
Write-Log "========== WSUS Admin API CHECK START ==========" "INFO"

$ServerName = Normalize-ServerName -Name $ServerName
Write-Log "Target: Server=$ServerName Port=$Port SSL=$($UseSSL.IsPresent)" "INFO"

$asmResult = Resolve-WsusAdminAssembly
if (-not $asmResult.Loaded) {
    Write-Log "Admin assembly load failed. Method=$($asmResult.Method) Error=$($asmResult.Error)" "ERROR"
    Show-Ui -Message ("WSUS Admin API not available.`n`nMethod: {0}`nError: {1}" -f $asmResult.Method,$asmResult.Error) -Icon Error
    [pscustomobject]@{
        Success        = $false
        Stage          = "LoadAssembly"
        Method         = $asmResult.Method
        AssemblyPath   = $asmResult.Path
        Error          = $asmResult.Error
        ServerName     = $ServerName
        Port           = $Port
        UseSSL         = [bool]$UseSSL
        LogPath        = $logPath
    }
    return
}

Write-Log "Admin assembly loaded. Method=$($asmResult.Method) Path=$($asmResult.Path)" "INFO"

$connection = $null
if ($TestConnection) {
    $connection = Test-WsusAdminConnection -Name $ServerName -Port $Port -UseSSL ([bool]$UseSSL)
    if (-not $connection.Ok) {
        Write-Log "Connection test failed: $($connection.Error)" "ERROR"
        Show-Ui -Message ("Loaded Admin API, but failed to connect to WSUS.`n`nServer: {0}`nPort: {1}`nSSL: {2}`nError: {3}" -f $ServerName,$Port,[bool]$UseSSL,$connection.Error) -Icon Error
        [pscustomobject]@{
            Success        = $false
            Stage          = "Connect"
            Method         = $asmResult.Method
            AssemblyPath   = $asmResult.Path
            Error          = $connection.Error
            ServerName     = $ServerName
            Port           = $Port
            UseSSL         = [bool]$UseSSL
            LogPath        = $logPath
        }
        return
    }
    Write-Log "Connected OK. WSUSName=$($connection.Name) Version=$($connection.Version) Method=$($connection.Method)" "INFO"
}

Write-Log "========== WSUS Admin API CHECK END ==========" "INFO"

if (-not $Quiet) {
    $msg = if ($TestConnection) {
        "OK.`nAdmin API loaded and WSUS connection succeeded.`n`nServer: $ServerName`nPort: $Port`nSSL: $([bool]$UseSSL)`nLog: $logPath"
    } else {
        "OK.`nAdmin API loaded successfully.`n`nLog: $logPath"
    }
    Show-Ui -Message $msg -Icon Information
}

[pscustomobject]@{
    Success        = $true
    Stage          = if ($TestConnection) { "Connect" } else { "LoadAssembly" }
    Method         = $asmResult.Method
    AssemblyPath   = $asmResult.Path
    ServerName     = $ServerName
    Port           = $Port
    UseSSL         = [bool]$UseSSL
    Connection     = $connection
    LogPath        = $logPath
}

# End of script
