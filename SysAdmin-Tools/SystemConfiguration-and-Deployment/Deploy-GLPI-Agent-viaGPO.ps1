<#
.SYNOPSIS
  Deploy/upgrade GLPI Agent via GPO without blocking startup.

.DESCRIPTION
  - Detects installed GLPI Agent version from registry (and falls back to the EXE file version).
  - If the same major/minor version is already installed, it skips installation (idempotent).
  - If different/not found, runs MSI with silent parameters and logs to C:\Scripts-LOGS.
  - Avoids uninstalling older versions; relies on MSI’s built-in upgrade/replace logic.
  - Detects GPO Startup context and does NOT wait on msiexec in that path (prevents boot hang).

.AUTHOR
  Luiz Hamilton Silva (@brazilianscriptguy) – adapted for GPO-safe, idempotent flow.

.VERSION
  Last Updated: 2025-09-10
#>

param(
    # Path to the GLPI Agent MSI installer (desired version)
    [string]$GLPIAgentMSI = "\\headq.scriptguy\netlogon\glpi-agent115-install.msi",
    # Directory where logs will be recorded
    [string]$GLPILogDir = "C:\Logs-TEMP",
    # Target version string to compare (prefix match, e.g. '1.15')
    [string]$ExpectedVersion = "1.15",
    # GLPI server URL and TAG to write during MSI install
    [string]$ServerUrl = "http://cmdb.headq.scriptguy/front/inventory.php",
    [string]$TagOverride = $null
)

$ErrorActionPreference = 'Stop'

# ------------------------ Logging ------------------------
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "$scriptName.log"
$logPath = Join-Path $GLPILogDir $logFileName

function Log-Message {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $line -ErrorAction Stop } catch { Write-Host $line }
}

# Ensure log directory
if (-not (Test-Path -Path $GLPILogDir)) {
    try { New-Item -Path $GLPILogDir -ItemType Directory -Force | Out-Null } catch {}
}

# -------------------- Context detection --------------------
function Get-IsGpoStartup {
    try {
        $isSystem = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
        $session0 = ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0)
        $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$pid"
        $parent = if ($pp.ParentProcessId) { Get-Process -Id $pp.ParentProcessId -ErrorAction SilentlyContinue }
        $pname = ($parent.Name -replace '\.exe$', '').ToLower()
        $gpParents = @('gpscript', 'gpupdate', 'winlogon', 'services')
        return ($isSystem -and $session0 -and $gpParents -contains $pname)
    } catch { return $false }
}

$IsGpoStartup = Get-IsGpoStartup
Log-Message "GPO Startup context: $IsGpoStartup"

# -------------------- Utilities --------------------
function Get-GLPIAgentPath {
    $candidates = @(
        "C:\Program Files\GLPI-Agent\glpi-agent.exe",
        "C:\Program Files (x86)\GLPI-Agent\glpi-agent.exe",
        "C:\Program Files\GLPI-Agent\perl\bin\glpi-agent.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-InstalledGLPIInfo {
    $roots = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($r in $roots) {
        Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
            $it = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($it -and $it.DisplayName -and ($it.DisplayName -like "*GLPI Agent*")) {
                [PSCustomObject]@{
                    DisplayName = $it.DisplayName
                    DisplayVersion = $it.DisplayVersion
                    UninstallString = $it.UninstallString
                    InstallLocation = $it.InstallLocation
                    RegistryKey = $_.PSChildName
                }
            }
        }
    }
}

# Resolve domain/TAG
$domainTag = if ($TagOverride) { $TagOverride } elseif ($env:USERDOMAIN) { $env:USERDOMAIN } else {
    try { (Get-CimInstance Win32_ComputerSystem).Domain } catch { 'UNKNOWN' }
}

# -------------------- Pre-checks --------------------
if (-not (Test-Path $GLPIAgentMSI)) { Log-Message "MSI not found: $GLPIAgentMSI" 'ERROR'; exit 1 }

# Installed version?
$installed = Get-InstalledGLPIInfo | Select-Object -First 1
if ($installed) {
    Log-Message "Detected installed GLPI Agent: '$($installed.DisplayName)' version '$($installed.DisplayVersion)'."
} else {
    # Try fallback by file version
    $exe = Get-GLPIAgentPath
    if ($exe) {
        try {
            $fv = (Get-Item $exe).VersionInfo.ProductVersion
            if ($fv) {
                $installed = [PSCustomObject]@{ DisplayName = 'GLPI Agent (file)'; DisplayVersion = $fv; UninstallString = $null; InstallLocation = (Split-Path $exe -Parent); RegistryKey = '(file)' }
                Log-Message "Detected GLPI Agent by executable: '$exe' (file version: $fv)."
            }
        } catch {}
    }
}

# -------------------- Idempotent decision --------------------
$needInstall = $true
if ($installed -and $installed.DisplayVersion) {
    if ($installed.DisplayVersion -like "$ExpectedVersion*") {
        $needInstall = $false
        Log-Message "Same version '$ExpectedVersion' already installed; skipping installation (idempotent)."
    } else {
        Log-Message "Installed version '$($installed.DisplayVersion)' differs from target '$ExpectedVersion'; will run MSI."
    }
} else {
    Log-Message "GLPI Agent not found; will run MSI."
}

# -------------------- Install (no uninstall) --------------------
if ($needInstall) {
    # Build MSI arguments. We log MSI to a separate file for troubleshooting.
    $msiLog = Join-Path $GLPILogDir 'glpi-install.log'
    $installArgs = @(
        '/i', "`"$GLPIAgentMSI`"",
        '/qn', '/norestart', 'REBOOT=ReallySuppress',
        '/l*v', "`"$msiLog`"",
        "RUNNOW=1",
        "SERVER=`"$ServerUrl`"",
        "TAG=`"$domainTag`""
    ) -join ' '

    Log-Message "Executing: msiexec.exe $installArgs"

    try {
        # IMPORTANT: Do not block in GPO Startup. We omit -NoNewWindow to avoid conflicts with -WindowStyle.
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs `
            -WindowStyle Hidden -PassThru -Wait:(!$IsGpoStartup) -ErrorAction Stop

        # If we did not wait (GPO Startup), $proc may be $null; log accordingly.
        if ($proc) {
            Log-Message "msiexec exited with code: $($proc.ExitCode)"
            if ($proc.ExitCode -ne 0) { Log-Message "MSI returned non-zero exit code. See $msiLog" 'WARNING' }
        } else {
            Log-Message "Started msiexec in background (GPO Startup); see $msiLog for progress."
        }
    }
    catch {
        Log-Message "Failed to launch msiexec. Error: $_" 'ERROR'
        exit 1
    }
} else {
    # Optionally ensure service is running, but do not block.
    try {
        $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like '*glpi*agent*' -or $_.DisplayName -like '*GLPI*Agent*'
        } | Select-Object -First 1
        if ($svc -and $svc.Status -ne 'Running') {
            Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
            Log-Message "Started service '$($svc.Name)'."
        }
    } catch {}
}

# -------------------- End --------------------
Log-Message "End of script."
exit 0

# End of script
