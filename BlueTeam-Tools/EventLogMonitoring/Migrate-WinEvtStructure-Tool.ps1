<#
.SYNOPSIS
    Migrates Windows Event Log storage to a new target root and updates BOTH:  
      - Classic EventLog registry paths (HKLM:\SYSTEM\CCS\Services\EventLog)
      - Modern WINEVT channel logFileName paths (via wevtutil)

.DESCRIPTION
    This tool:
      0) ENFORCES an ACL baseline on the target log repository (root + inheritance) EXACTLY as required:
         - Authenticated Users
         - SYSTEM
         - Administrators
         - EventLog (NT SERVICE\EventLog)
      1) Stops Event Log service (and dependents) and optionally DHCP Server (if present), taking a state snapshot.
      2) Copies all .evtx files from:
           %SystemRoot%\System32\winevt\Logs
         into a target root using a stable folder convention:
           <TargetRoot>\<SafeName>\<SafeName>.evtx   (active logs)
         Archive files "Archive-<LogName>-<timestamp>.evtx" are placed under:
           <TargetRoot>\<SafeLogName>\Archive-<LogName>-<timestamp>.evtx
      3) Updates Classic registry keys: HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\<Log>\File
      4) Updates Modern channels using wevtutil (with timeouts so it cannot hang):
           wevtutil sl "<ChannelName>" /lfn:"<NewPath>"
         Only channels whose current logFileName points to the default folder are modified.
      5) Enforces Classic log size to 153600 KB (150 MB) for:
           Application, Security, Setup, System
      6) Restarts services to their prior states.
      7) Supports StagingCopyOnly mode:
         - Copies first, updates registry/channels, restarts services
         - DOES NOT delete source .evtx files from the default folder

.NOTES
    - Requires administrative privileges.
    - PowerShell 5.1+.
    - Maintenance window strongly recommended.
    - A reboot may be required.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    7.4.0 - January 16, 2026
#>

# --- Hide the PowerShell Console Window ---
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
        if (handle != IntPtr.Zero) ShowWindow(handle, 0); // SW_HIDE
    }
}
"@
[Window]::Hide()

# --- Load UI Libraries ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Elevation Check ---
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Administrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        "This script must be run as an Administrator.",
        "Insufficient Privileges",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit
}

# --- Logging ---
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'WARN', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop } catch { }
}

function Format-ExceptionDetail {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $ex = $ErrorRecord.Exception
    $type = if ($ex) { $ex.GetType().FullName } else { "UnknownExceptionType" }
    $msg = if ($ex) { $ex.Message } else { [string]$ErrorRecord }
    $pos = ""
    try { $pos = $ErrorRecord.InvocationInfo.PositionMessage } catch { }
    $stack = ""
    try { $stack = $ex.StackTrace } catch { }
    @"
ExceptionType: $type
Message: $msg

Position:
$pos

StackTrace:
$stack
"@
}

function Handle-Error {
    param ([string]$Message, $Exception = $null)

    $detail = ""
    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $detail = Format-ExceptionDetail -ErrorRecord $Exception
    } elseif ($Exception -is [System.Exception]) {
        $detail = "ExceptionType: $($Exception.GetType().FullName)`nMessage: $($Exception.Message)`nStackTrace:`n$($Exception.StackTrace)"
    } elseif ($Exception) {
        $detail = [string]$Exception
    }

    $fullMessage = if ($detail) { "$Message`n`n$detail" } else { $Message }
    Write-Log -Message $fullMessage -Level "ERROR"

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

Write-Log -Message "Script started." -Level "INFO"

# --- Globals & Helpers ---
$DefaultLogsFolder = Join-Path $env:SystemRoot 'System32\winevt\Logs'

function Get-SafeName {
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name -replace '%4', '-'
    $n = $n -replace '/', '-'
    $invalid = ([IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()) | Sort-Object -Unique
    foreach ($c in $invalid) { $n = $n -replace [Regex]::Escape([string]$c), '-' }
    $n = ($n -replace '[\s\-]+', '-').Trim().Trim('.').Trim('-')
    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'Log' }
    return $n
}

function Expand-EnvPath { param([Parameter(Mandatory)][string]$Path) try { [Environment]::ExpandEnvironmentVariables($Path) } catch { $Path } }

function New-UniqueArchiveName {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Base)
    do {
        $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        $candidate = Join-Path $Dir ("{0}_{1}.evtx" -f $Base, $stamp)
        if (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $Dir ("{0}_{1}_{2}.evtx" -f $Base, $stamp, (Get-Random -Maximum 10000))
        }
    } until (-not (Test-Path -LiteralPath $candidate))
    return $candidate
}

function Invoke-Retry {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [int]$MaxAttempts = 8,
        [int]$DelayMs = 350
    )
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try { return & $Action }
        catch {
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Milliseconds ($DelayMs * $i)
        }
    }
}

function Get-TargetRouting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$LogFile,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    $base = $LogFile.BaseName

    # Archive-<LogOrChannel>-YYYY-MM-DD-HH-MM-SS-mmm.evtx
    $rx = '^Archive-(?<log>.+)-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-\d{3}$'
    if ($base -match $rx) {
        $logical = $matches['log']
        $folderName = Get-SafeName -Name $logical
        $targetFolder = Join-Path -Path $TargetRoot -ChildPath $folderName
        $destFile = Join-Path -Path $targetFolder -ChildPath $LogFile.Name
        return [pscustomobject]@{ TargetFolder = $targetFolder; DestFile = $destFile; IsArchive = $true }
    }

    $folderName = Get-SafeName -Name $base
    $targetFolder = Join-Path -Path $TargetRoot -ChildPath $folderName
    $destFile = Join-Path -Path $targetFolder -ChildPath ("{0}.evtx" -f $folderName)
    return [pscustomobject]@{ TargetFolder = $targetFolder; DestFile = $destFile; IsArchive = $false }
}

# --- NEW: ACL Baseline (REQUIRED) ---
function Set-LogRepositoryAclBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        try {
            New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created target root folder: $RootPath" -Level "INFO"
        } catch {
            Handle-Error -Message "Failed to create target root folder: $RootPath" -Exception $_
            throw
        }
    }

    try {
        Write-Log -Message "Applying REQUIRED ACL baseline (SID-based) to: $RootPath" -Level "INFO"

        $acl = Get-Acl -LiteralPath $RootPath

        # Disable inheritance from volume root; do NOT preserve inherited rules
        $acl.SetAccessRuleProtection($true, $false)

        # Remove existing explicit rules
        foreach ($rule in @($acl.Access)) {
            $null = $acl.RemoveAccessRule($rule)
        }

        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow

        # --- Well-known SIDs (language independent) ---
        $sidSystem = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'   # LocalSystem
        $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544' # Builtin Administrators
        $sidAuthUsers = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-11'   # Authenticated Users

        # --- Service SID: NT SERVICE\EventLog ---
        # Resolve dynamically to avoid translation issues
        $ntEventLog = New-Object System.Security.Principal.NTAccount 'NT SERVICE', 'EventLog'
        $sidEventLog = $ntEventLog.Translate([System.Security.Principal.SecurityIdentifier])

        # Rights baseline (matches practical EventLog repo usage)
        $ruleAuth = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sidAuthUsers,
            [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
            $inherit,
            $prop,
            $allow
        )

        $ruleSys = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sidSystem,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,
            $prop,
            $allow
        )

        $ruleAdm = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sidAdmins,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inherit,
            $prop,
            $allow
        )

        $ruleEvt = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sidEventLog,
            [System.Security.AccessControl.FileSystemRights]::Modify,
            $inherit,
            $prop,
            $allow
        )

        # Apply rules
        $acl.AddAccessRule($ruleAuth) | Out-Null
        $acl.AddAccessRule($ruleSys)  | Out-Null
        $acl.AddAccessRule($ruleAdm)  | Out-Null
        $acl.AddAccessRule($ruleEvt)  | Out-Null

        Set-Acl -LiteralPath $RootPath -AclObject $acl

        Write-Log -Message "ACL baseline applied successfully: $RootPath" -Level "INFO"
        Write-Log -Message "Baseline SIDs: AuthUsers=S-1-5-11, SYSTEM=S-1-5-18, Admins=S-1-5-32-544, EventLog=$($sidEventLog.Value)" -Level "INFO"
    }
    catch {
        Handle-Error -Message "Failed to apply ACL baseline to: $RootPath" -Exception $_
        throw
    }
}

# --- Service State Snapshot / Restore ---
$Global:ServiceState = @{}

function Snapshot-ServiceState {
    param([string[]]$ServiceNames)
    foreach ($name in $ServiceNames) {
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            $Global:ServiceState[$name] = $svc.Status
            Write-Log -Message "Service state snapshot: $name = $($svc.Status)"
        } catch {
            Write-Log -Message "Service not found (snapshot skip): $name" -Level "WARN"
        }
    }
}

function Restore-ServiceState {
    foreach ($kvp in $Global:ServiceState.GetEnumerator()) {
        $name = $kvp.Key
        $state = $kvp.Value
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($state -eq 'Running' -and $svc.Status -ne 'Running') {
                Start-Service -Name $name -ErrorAction Stop
                Write-Log -Message "Restored service to Running: $name"
            } elseif ($state -eq 'Stopped' -and $svc.Status -ne 'Stopped') {
                Stop-Service -Name $name -Force -ErrorAction Stop
                Write-Log -Message "Restored service to Stopped: $name"
            }
        } catch {
            Write-Log -Message "Failed to restore service state: $name ($($_.Exception.Message))" -Level "ERROR"
        }
    }
}

function Stop-For-Migration {
    $deps = @(Get-Service -Name "EventLog" -DependentServices 2>$null)
    $depNames = @()
    if ($deps) { $depNames = $deps.Name }

    $track = ($depNames + @('DhcpServer') + @('EventLog')) | Select-Object -Unique
    Snapshot-ServiceState -ServiceNames $track

    foreach ($svcName in $depNames) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction Stop
            Write-Log -Message "Stopped dependent service: $svcName"
        } catch {
            Write-Log -Message "Failed stopping dependent service: $svcName ($($_.Exception.Message))" -Level "WARN"
        }
    }

    try {
        $dhcp = Get-Service -Name 'DhcpServer' -ErrorAction Stop
        if ($dhcp.Status -ne 'Stopped') {
            Stop-Service -Name 'DhcpServer' -Force -ErrorAction Stop
            Write-Log -Message "Stopped DHCP Server service for migration."
        }
    } catch {
        Write-Log -Message "DHCP Server service not found or not stoppable." -Level "WARN"
    }

    try {
        Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        Write-Log -Message "Stop requested: EventLog"

        $sw = [Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 250
        } while ((Get-Service -Name "EventLog").Status -ne 'Stopped' -and $sw.Elapsed.TotalSeconds -lt 30)

        if ((Get-Service -Name "EventLog").Status -ne 'Stopped') {
            throw "EventLog could not be stopped reliably. Abort to avoid file locks."
        }

        Write-Log -Message "EventLog is Stopped."
    } catch {
        Handle-Error -Message "Failed to stop Event Log service." -Exception $_
        throw
    }
}

function Start-After-Migration {
    try {
        Start-Service -Name "EventLog" -ErrorAction Stop
        Write-Log -Message "Started Event Log service."
    } catch {
        Handle-Error -Message "Failed to start Event Log service." -Exception $_
    }
    Restore-ServiceState
}

# --- Timed wevtutil (prevents hangs) ---
function Invoke-WevtutilTimed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter()][int]$TimeoutSeconds = 20
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wevtutil.exe"
    $psi.Arguments = ($Arguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
        try { $p.Kill() } catch { }
        return [pscustomobject]@{ TimedOut = $true; ExitCode = $null; StdOut = ""; StdErr = "Timed out after $TimeoutSeconds seconds." }
    }

    return [pscustomobject]@{
        TimedOut = $false
        ExitCode = $p.ExitCode
        StdOut = $p.StandardOutput.ReadToEnd()
        StdErr = $p.StandardError.ReadToEnd()
    }
}

function Get-ChannelLogFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $r = Invoke-WevtutilTimed -Arguments @("gl", "`"$ChannelName`"") -TimeoutSeconds 20
    if ($r.TimedOut -or $r.ExitCode -ne 0 -or -not $r.StdOut) { return $null }

    $lines = $r.StdOut -split "`r?`n"
    $line = $lines | Where-Object { $_ -match '^\s*logFileName\s*:\s*' } | Select-Object -First 1
    if (-not $line) { return $null }
    (($line -replace '^\s*logFileName\s*:\s*', '').Trim())
}

function Set-ChannelLogFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$NewLogFileName
    )

    $r = Invoke-WevtutilTimed -Arguments @("sl", "`"$ChannelName`"", "/lfn:`"$NewLogFileName`"") -TimeoutSeconds 20
    if ($r.TimedOut) {
        Write-Log -Message "wevtutil sl timed out: $ChannelName" -Level "WARN"
        return $false
    }
    return ($r.ExitCode -eq 0)
}

function Update-WinevtChannels {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetRoot)

    $defaultExpanded = (Resolve-Path -LiteralPath $DefaultLogsFolder).Path

    $rEl = Invoke-WevtutilTimed -Arguments @("el") -TimeoutSeconds 20
    if ($rEl.TimedOut -or $rEl.ExitCode -ne 0 -or -not $rEl.StdOut) {
        Write-Log -Message "wevtutil el failed or timed out. Skipping WINEVT channel update." -Level "WARN"
        return $false
    }

    $channels = $rEl.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $changed = 0; $skipped = 0; $failed = 0

    foreach ($ch in $channels) {
        $currentLfn = Get-ChannelLogFileName -ChannelName $ch
        if ([string]::IsNullOrWhiteSpace($currentLfn)) { $skipped++; continue }

        $expanded = Expand-EnvPath -Path $currentLfn

        $inDefault = $false
        try {
            $expandedDir = Split-Path -Path $expanded -Parent
            $resolved = Resolve-Path -LiteralPath $expandedDir -ErrorAction SilentlyContinue
            if ($resolved -and ($resolved.Path.TrimEnd('\') -ieq $defaultExpanded.TrimEnd('\'))) { $inDefault = $true }
        } catch { }

        if (-not $inDefault) { $skipped++; continue }

        $safe = Get-SafeName -Name ($ch -replace '/', '-')
        $folder = Join-Path -Path $TargetRoot -ChildPath $safe
        $file = Join-Path -Path $folder -ChildPath ("{0}.evtx" -f $safe)

        if (-not (Test-Path -LiteralPath $folder)) {
            try { New-Item -Path $folder -ItemType Directory -Force | Out-Null } catch { }
        }

        if (Set-ChannelLogFileName -ChannelName $ch -NewLogFileName $file) {
            $changed++
            Write-Log -Message "WINEVT channel updated: $ch -> $file"
        } else {
            $failed++
            Write-Log -Message "WINEVT channel update FAILED: $ch -> $file" -Level "WARN"
        }
    }

    Write-Log -Message "WINEVT channel update summary: changed=$changed, skipped=$skipped, failed=$failed"
    return ($failed -eq 0)
}

# --- Update Classic Registry Paths ---
function Update-ClassicRegistryPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TargetRoot)

    $registryBasePath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"

    try {
        foreach ($subKey in (Get-ChildItem -Path $registryBasePath -ErrorAction Stop)) {
            $fileProp = Get-ItemProperty -Path $subKey.PSPath -Name "File" -ErrorAction SilentlyContinue
            if ($fileProp -eq $null) { continue }

            $logName = $subKey.PSChildName
            $safeLog = Get-SafeName -Name $logName

            $newFolder = Join-Path -Path $TargetRoot -ChildPath $safeLog
            $newFile = Join-Path -Path $newFolder -ChildPath ("{0}.evtx" -f $safeLog)

            if (-not (Test-Path -LiteralPath $newFolder)) {
                New-Item -Path $newFolder -ItemType Directory -Force | Out-Null
            }

            New-ItemProperty -Path $subKey.PSPath -Name "AutoBackupLogFiles" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $subKey.PSPath -Name "Flags"             -Value 1 -PropertyType DWord -Force | Out-Null

            $current = [string](Get-ItemProperty -Path $subKey.PSPath -Name "File" -ErrorAction SilentlyContinue).File
            if ($current -ne $newFile) {
                Set-ItemProperty -Path $subKey.PSPath -Name "File" -Value $newFile -ErrorAction Stop
            }

            Write-Log -Message "Classic registry updated: $logName -> $newFile"
        }
        return $true
    } catch {
        Handle-Error -Message "Failed to update classic registry paths." -Exception $_
        return $false
    }
}

# --- Enforce Classic Log Sizes (Application, Security, Setup, System) ---
function Set-ClassicLogSizes153600KB {
    [CmdletBinding()]
    param()

    $classic = @('Application', 'Security', 'Setup', 'System')
    $maxKb = 153600

    foreach ($name in $classic) {
        try {
            & wevtutil sl $name /ms:($maxKb * 1024) /rt:false 2>$null | Out-Null
            Write-Log -Message "Classic log size enforced: $name = ${maxKb}KB (rt=false)"
        } catch {
            Write-Log -Message "Failed to enforce size for ${name}: $($_.Exception.Message)" -Level "WARN"
        }
    }
}

# --- Copy Logs (safe; avoids Rename-Item on active destination files; UI-safe ProgressBar) ---
function Copy-Or-Move-EventLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][bool]$StagingCopyOnly,
        [Parameter(Mandatory = $false)][object]$ProgressBar
    )

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        New-Item -Path $TargetRoot -ItemType Directory -Force | Out-Null
    }

    $logFiles = Get-ChildItem -LiteralPath $DefaultLogsFolder -Filter "*.evtx" -File -ErrorAction Stop

    if ($ProgressBar -and $ProgressBar -is [System.Windows.Forms.ProgressBar]) {
        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $logFiles.Count
        $ProgressBar.Value = 0
    }

    $mappings = New-Object System.Collections.Generic.List[pscustomobject]
    $i = 0

    foreach ($logFile in $logFiles) {
        try {
            $route = Get-TargetRouting -LogFile $logFile -TargetRoot $TargetRoot
            $targetFolder = $route.TargetFolder

            if (-not (Test-Path -LiteralPath $targetFolder)) {
                New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
            }

            # IMPORTANT: Do NOT rename existing destination active files (can be locked).
            # If destination exists, generate a unique file name and copy.
            $dest = $route.DestFile
            if (Test-Path -LiteralPath $dest) {
                $dir = Split-Path -Path $dest -Parent
                $base = [IO.Path]::GetFileNameWithoutExtension($dest)
                $dest = New-UniqueArchiveName -Dir $dir -Base $base
            }

            Invoke-Retry -MaxAttempts 6 -DelayMs 300 -Action {
                Copy-Item -LiteralPath $logFile.FullName -Destination $dest -Force -ErrorAction Stop
            } | Out-Null

            Write-Log -Message ("Copied{0}: {1} -> {2}" -f ($(if ($StagingCopyOnly) { " (staging)" }else { "" })), $logFile.Name, $dest)

            $mappings.Add([pscustomobject]@{
                    SourceFullPath = $logFile.FullName
                    DestinationFullPath = $dest
                }) | Out-Null

        } catch {
            Write-Log -Message ("Copy error: {0} ({1})" -f $logFile.FullName, $_.Exception.Message) -Level "WARN"
            Write-Log -Message (Format-ExceptionDetail -ErrorRecord $_) -Level "WARN"
        } finally {
            $i++
            if ($ProgressBar -and $ProgressBar -is [System.Windows.Forms.ProgressBar]) {
                $ProgressBar.Value = [Math]::Min($i, $ProgressBar.Maximum)
            }
        }
    }

    return @($mappings)
}

function Cleanup-SourceEvtx {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][object]$Mappings)

    if ($null -eq $Mappings) { Write-Log -Message "Cleanup skipped: mappings null." -Level "WARN"; return }
    $items = @($Mappings)
    if ($items.Count -eq 0) { Write-Log -Message "Cleanup skipped: mappings empty." -Level "WARN"; return }

    foreach ($m in $items) {
        try {
            if (-not (Test-Path -LiteralPath $m.DestinationFullPath)) { continue }
            if (Test-Path -LiteralPath $m.SourceFullPath) {
                Remove-Item -LiteralPath $m.SourceFullPath -Force -ErrorAction Stop
                Write-Log -Message "Deleted source: $($m.SourceFullPath)"
            }
        } catch {
            Write-Log -Message "Kept source (delete failed): $($m.SourceFullPath) $($_.Exception.Message)" -Level "WARN"
        }
    }
}

# --- GUI Setup ---
function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Paths (Classic + WINEVT Channels)'
    $form.Size = New-Object System.Drawing.Size(620, 330)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $labelTargetRootFolder = New-Object System.Windows.Forms.Label
    $labelTargetRootFolder.Text = 'Target root folder (e.g., "L:\")'
    $labelTargetRootFolder.Location = New-Object System.Drawing.Point(10, 15)
    $labelTargetRootFolder.Size = New-Object System.Drawing.Size(580, 18)
    $form.Controls.Add($labelTargetRootFolder)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 38)
    $textBox.Size = New-Object System.Drawing.Size(580, 22)
    $form.Controls.Add($textBox)

    $chkStaging = New-Object System.Windows.Forms.CheckBox
    $chkStaging.Text = "StagingCopyOnly (copy + update; do NOT delete source .evtx)"
    $chkStaging.Location = New-Object System.Drawing.Point(10, 68)
    $chkStaging.Size = New-Object System.Drawing.Size(580, 20)
    $chkStaging.Checked = $true
    $form.Controls.Add($chkStaging)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 98)
    $progressBar.Size = New-Object System.Drawing.Size(580, 20)
    $form.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 126)
    $statusLabel.Size = New-Object System.Drawing.Size(580, 60)
    $statusLabel.Text = "Ready."
    $form.Controls.Add($statusLabel)

    $labelLog = New-Object System.Windows.Forms.Label
    $labelLog.Location = New-Object System.Drawing.Point(10, 188)
    $labelLog.Size = New-Object System.Drawing.Size(580, 36)
    $labelLog.Text = "Log file:`r`n$logPath"
    $form.Controls.Add($labelLog)

    $buttonRun = New-Object System.Windows.Forms.Button
    $buttonRun.Text = "Run Migration"
    $buttonRun.Location = New-Object System.Drawing.Point(330, 240)
    $buttonRun.Size = New-Object System.Drawing.Size(120, 28)
    $form.Controls.Add($buttonRun)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = "Close"
    $buttonClose.Location = New-Object System.Drawing.Point(470, 240)
    $buttonClose.Size = New-Object System.Drawing.Size(120, 28)
    $buttonClose.Enabled = $false
    $buttonClose.Add_Click({ $form.Close() })
    $form.Controls.Add($buttonClose)

    $buttonRun.Add_Click({
            $targetRoot = $textBox.Text.Trim()
            $staging = [bool]$chkStaging.Checked
            $mappings = @()

            if ([string]::IsNullOrWhiteSpace($targetRoot)) {
                [System.Windows.Forms.MessageBox]::Show("Please enter the target root folder.", "Input Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                return
            }

            try {
                $statusLabel.Text = "Applying ACL baseline to target..."
                Set-LogRepositoryAclBaseline -RootPath $targetRoot

                $statusLabel.Text = "Stopping services..."
                Stop-For-Migration

                $statusLabel.Text = "Copying .evtx files..."
                $mappings = Copy-Or-Move-EventLogs -TargetRoot $targetRoot -StagingCopyOnly $staging -ProgressBar $progressBar
                if ($null -eq $mappings) { $mappings = @() }

                $statusLabel.Text = "Updating classic registry paths..."
                $okClassic = Update-ClassicRegistryPaths -TargetRoot $targetRoot

                $statusLabel.Text = "Updating WINEVT channels..."
                $okWinevt = Update-WinevtChannels -TargetRoot $targetRoot

                $statusLabel.Text = "Enforcing classic log size (153600 KB)..."
                Set-ClassicLogSizes153600KB

                $statusLabel.Text = "Restoring services..."
                Start-After-Migration

                if (-not $staging -and $okClassic -and $okWinevt -and @($mappings).Count -gt 0) {
                    $statusLabel.Text = "Deleting sources..."
                    Cleanup-SourceEvtx -Mappings $mappings
                } else {
                    Write-Log -Message "StagingCopyOnly enabled or update failures; sources NOT deleted." -Level "WARN"
                }

                $progressBar.Value = $progressBar.Maximum
                $buttonRun.Enabled = $false
                $buttonClose.Enabled = $true
                $statusLabel.Text = "Completed."

                [System.Windows.Forms.MessageBox]::Show(
                    "Completed.`n`nLog: $logPath",
                    "Done",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

            } catch {
                Handle-Error -Message "Migration failed. Review the log for details." -Exception $_
                try { Start-After-Migration } catch { }
            }
        })

    $form.ShowDialog() | Out-Null
}

# Launch GUI
Setup-GUI
Write-Log -Message "Script ended." -Level "INFO"
