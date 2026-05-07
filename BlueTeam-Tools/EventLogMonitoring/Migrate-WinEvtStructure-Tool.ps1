<#
.SYNOPSIS
    Safely migrates Windows Event Log storage to a dedicated target root with compliance reporting and cleanup-safe residual handling.

.DESCRIPTION
    This tool:
      0) Applies the ACL baseline on the target root.
      1) Stops Event Log and tracked dependent services.
      2) Copies .evtx files from the default WINEVT folder into the new structure.
      3) Validates copied files with a resilient enterprise model.
      4) Updates Classic registry paths.
      5) Updates Modern WINEVT channel logFileName paths directly from copied mappings.
      6) Restarts services.
      7) Retains source files during normal migration; cleanup is restricted to explicit post-reboot cleanup mode.
      8) Provides explicit execution modes: migration, audit-only, full dry-run, and post-reboot cleanup-only.
      9) Produces compliance reports:
           - Migration summary CSV
           - Residual source files CSV
           - Post-run verification TXT
           - Enterprise telemetry JSON for SIEM/ITSM ingestion

.NOTES
    - PowerShell 5.1 compatible
    - Intended for Windows Server 2019+
    - Target root must be a dedicated drive root such as L:\
    - .etl files are explicitly out of scope for migration

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    8.8.1 - ENTERPRISE HARDENED-STATE - Strict-Mode Safe State Model - 2026-05-04
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$PostRebootCleanupOnly,
    [switch]$ForceSourceCleanup,
    [switch]$WhatIfFull,
    [switch]$NoJsonTelemetry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Hide Console
# ------------------------------------------------------------
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
        if (handle != IntPtr.Zero) ShowWindow(handle, 0);
    }
}
"@
if (-not $ShowConsole) { [Window]::Hide() }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------------------------
# WinForms Global Exception Mode - MUST be set before any control is created
# ------------------------------------------------------------
$script:WinFormsExceptionModeApplied = $false
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode(
        [System.Windows.Forms.UnhandledExceptionMode]::CatchException
    )
    $script:WinFormsExceptionModeApplied = $true
} catch {
    # This can happen if a control was already created by the host/session.
    # The script must continue and rely on explicit event-handler containment.
    $script:WinFormsExceptionModeApplied = $false
}

# ------------------------------------------------------------
# Admin Check
# ------------------------------------------------------------
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        'This script must be run as an Administrator.',
        'Insufficient Privileges',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit
}

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir ("{0}.log" -f $scriptName)
$timestampTag = Get-Date -Format 'yyyyMMdd_HHmmss'
$summaryCsvPath = Join-Path $logDir ("{0}_MigrationSummary_{1}.csv" -f $scriptName, $timestampTag)
$residualCsvPath = Join-Path $logDir ("{0}_ResidualSourceFiles_{1}.csv" -f $scriptName, $timestampTag)
$verificationTxtPath = Join-Path $logDir ("{0}_Verification_{1}.txt" -f $scriptName, $timestampTag)
$telemetryJsonPath = Join-Path $logDir ("{0}_EnterpriseTelemetry_{1}.json" -f $scriptName, $timestampTag)

if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    try {
        Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { }
}

function Format-ExceptionDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $ex = $ErrorRecord.Exception
    $type = if ($ex) { $ex.GetType().FullName } else { 'UnknownExceptionType' }
    $msg  = if ($ex) { $ex.Message } else { [string]$ErrorRecord }

    $pos = ''
    try { $pos = $ErrorRecord.InvocationInfo.PositionMessage } catch { }

    $stack = ''
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][object]$Exception
    )

    $detail = ''
    if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $detail = Format-ExceptionDetail -ErrorRecord $Exception
    } elseif ($Exception -is [System.Exception]) {
        $detail = "ExceptionType: $($Exception.GetType().FullName)`nMessage: $($Exception.Message)`nStackTrace:`n$($Exception.StackTrace)"
    } elseif ($Exception) {
        $detail = [string]$Exception
    }

    $full = if ($detail) { "$Message`n`n$detail" } else { $Message }
    Write-Log -Message $full -Level 'ERROR'

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        'Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}


function Write-FailsafeExceptionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Context,
        [Parameter()][object]$ExceptionObject
    )

    try {
        $text = if ($ExceptionObject -is [System.Management.Automation.ErrorRecord]) {
            Format-ExceptionDetail -ErrorRecord $ExceptionObject
        } elseif ($ExceptionObject -is [System.Exception]) {
            "ExceptionType: $($ExceptionObject.GetType().FullName)`r`nMessage: $($ExceptionObject.Message)`r`nStackTrace:`r`n$($ExceptionObject.StackTrace)"
        } elseif ($ExceptionObject) {
            [string]$ExceptionObject
        } else {
            'No exception object provided.'
        }

        Write-Log -Message ("{0}`r`n{1}" -f $Context, $text) -Level 'ERROR'
    } catch {
        try {
            $fallback = Join-Path $env:TEMP 'Migrate-WinEvtStructure-Tool_FailsafeException.log'
            Add-Content -Path $fallback -Value ("[{0}] {1}`r`n{2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Context, [string]$ExceptionObject) -Encoding UTF8
        } catch { }
    }
}

function Show-SafeMessageBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][string]$Title = 'Information',
        [Parameter()][System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    try {
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $Icon
        ) | Out-Null
    } catch {
        Write-FailsafeExceptionLog -Context 'MessageBox display failed.' -ExceptionObject $_
    }
}

function Invoke-EventHandlerSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$Context
    )

    try {
        & $ScriptBlock
    } catch {
        $script:LastUnhandledException = $_
        Write-FailsafeExceptionLog -Context ("Unhandled GUI event exception captured: {0}" -f $Context) -ExceptionObject $_
        Show-SafeMessageBox -Message ("A GUI operation failed but was contained.`r`n`r`nContext: {0}`r`n`r`nReview the log file:`r`n{1}" -f $Context, $logPath) -Title 'Contained GUI Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# SetUnhandledExceptionMode is executed immediately after loading System.Windows.Forms. Do not call it here; controls may already exist.
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    try {
        $script:LastUnhandledException = $eventArgs.Exception
        Write-FailsafeExceptionLog -Context 'Global WinForms ThreadException captured.' -ExceptionObject $eventArgs.Exception
        Show-SafeMessageBox -Message ("A WinForms exception was contained.`r`n`r`nMessage:`r`n{0}`r`n`r`nReview the log file:`r`n{1}" -f $eventArgs.Exception.Message, $logPath) -Title 'Contained WinForms Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { }
})
[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    try {
        $script:LastUnhandledException = $eventArgs.ExceptionObject
        Write-FailsafeExceptionLog -Context 'Global AppDomain UnhandledException captured.' -ExceptionObject $eventArgs.ExceptionObject
    } catch { }
})

# ------------------------------------------------------------
# Runtime State - StrictMode Safe, Script-Scoped
# ------------------------------------------------------------
$DefaultLogsFolder = Join-Path $env:SystemRoot 'System32\winevt\Logs'
$script:ServiceState = @{}
$script:SourceDeletionPolicyEnabled = $false
$script:LastUnhandledException = $null
$script:EnterpriseWhatIfFull = [bool]$WhatIfFull
$script:JsonTelemetryEnabled = -not [bool]$NoJsonTelemetry

# Protected WINEVT channels that may return Access Denied even under elevated execution.
# They must not invalidate the entire migration when all other channels are aligned.
$script:NonFatalWinevtChannels = @(
    'State',
    'Active Directory Web Services',
    'Kaspersky Security'
)

# Explicit publisher services that are not always returned as EventLog dependents but may lock or protect channels.
$script:ExplicitPublisherServices = @(
    'ADWS'
)

# Known residual / recreated channels (seed list; can be expanded safely)
$script:ExpectedResidualPatterns = @(
    '^State$',
    '^Microsoft-Windows-StateRepository%4',
    '^Microsoft-Windows-AppXDeployment%4',
    '^Microsoft-Windows-AppXDeploymentServer%4',
    '^Microsoft-Windows-Shell-Core%4',
    '^Microsoft-Windows-DeviceSetupManager%4',
    '^Microsoft-Windows-PushNotification-Platform%4',
    '^Microsoft-Windows-PrintService%4Operational$',
    '^Microsoft-Windows-Windows Firewall With Advanced Security%4',
    '^Microsoft-Windows-WinINet-Config%4ProxyConfigChanged$',
    '^Microsoft-Windows-TerminalServices-Licensing%4'
)

Write-Log -Message 'Script started.' -Level 'INFO'
Write-Log -Message ("Enterprise mode flags: PostRebootCleanupOnly={0}; ForceSourceCleanup={1}; WhatIfFull={2}; JsonTelemetryEnabled={3}" -f ([bool]$PostRebootCleanupOnly), ([bool]$ForceSourceCleanup), ([bool]$WhatIfFull), ($script:JsonTelemetryEnabled)) -Level 'INFO'
if ($script:WinFormsExceptionModeApplied) {
    Write-Log -Message 'WinForms exception containment mode: CatchException applied before control creation.' -Level 'INFO'
} else {
    Write-Log -Message 'WinForms exception containment mode: host had already initialized WinForms; explicit safe event-handler containment remains active.' -Level 'WARN'
}

# ------------------------------------------------------------
# Generic Helpers
# ------------------------------------------------------------
function Expand-EnvPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try { return [Environment]::ExpandEnvironmentVariables($Path) }
    catch { return $Path }
}

function Normalize-TargetRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $normalized = $Path.Trim()
    if ($normalized -match '^[A-Za-z]:$') {
        $normalized += '\'
    }
    return $normalized
}

function Test-IsDriveRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return ($Path -match '^[A-Za-z]:\\$')
}

function Get-SafeFolderOrActiveName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name
    $n = $n -replace '%4', '-'
    $n = $n -replace '/', '-'
    $n = $n -replace '\s+', '-'
    $n = $n -replace '[^A-Za-z0-9\-]', ''
    $n = $n -replace '-{2,}', '-'
    $n = $n.Trim('-').Trim('.')

    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'Log' }
    return $n
}

function Get-SafeArchiveFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $n = $Name
    $n = $n -replace '%4', '-'
    $n = $n -replace '/', '-'
    $n = $n -replace '\s+', '-'
    $n = $n -replace '[^A-Za-z0-9\.\-]', ''
    $n = $n -replace '-{2,}', '-'
    $n = $n.Trim('-').Trim('.')

    if ([string]::IsNullOrWhiteSpace($n)) { $n = 'Archive-Log.evtx' }
    return $n
}

function Convert-EvtxBaseNameToChannelName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$BaseName)

    # Windows stores many modern channel files using %4 as the path separator.
    # Example: Microsoft-Windows-TaskScheduler%4Operational.evtx
    # Channel: Microsoft-Windows-TaskScheduler/Operational
    return ($BaseName -replace '%4', '/')
}

function New-UniqueArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$PreferredFileName
    )

    $candidate = Join-Path $Directory $PreferredFileName
    if (-not (Test-Path -LiteralPath $candidate)) {
        return $candidate
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($PreferredFileName)
    $ext  = [System.IO.Path]::GetExtension($PreferredFileName)

    $suffixCharCode = [int][char]'A'
    while ($true) {
        $suffix = [char]$suffixCharCode
        $newName = "{0}-{1}{2}" -f $base, $suffix, $ext
        $candidate = Join-Path $Directory $newName
        if (-not (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
        $suffixCharCode++
        if ($suffixCharCode -gt [int][char]'Z') {
            throw "Unable to generate a unique archive file name in: $Directory"
        }
    }
}

function Invoke-Retry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter()][int]$MaxAttempts = 8,
        [Parameter()][int]$DelayMs = 350
    )

    for ($i = 1; $i -le $MaxAttempts; $i++) {
        try {
            return & $Action
        } catch {
            if ($i -eq $MaxAttempts) { throw }
            Start-Sleep -Milliseconds ($DelayMs * $i)
        }
    }
}

function Test-ReadableFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try { return ($fs.Length -ge 0) }
        finally { $fs.Dispose() }
    } catch {
        return $false
    }
}

function Test-FileLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try { return $false }
        finally { $fs.Dispose() }
    } catch {
        return $true
    }
}

function Get-FileHashSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    try {
        if (-not (Test-ReadableFile -Path $Path)) {
            return $null
        }
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    } catch {
        return $null
    }
}

function Test-DestinationFileSane {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return ($item.Length -gt 0)
    } catch {
        return $false
    }
}

function Get-TargetRouting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$LogFile,
        [Parameter(Mandatory)][string]$TargetRoot
    )

    $base = $LogFile.BaseName
    $archiveRx = '^Archive-(?<log>.+)-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-\d{3}$'

    if ($base -match $archiveRx) {
        $logical = [string]$matches['log']
        $folderName = Get-SafeFolderOrActiveName -Name $logical
        $targetFolder = Join-Path -Path $TargetRoot -ChildPath $folderName
        $archiveFileName = Get-SafeArchiveFileName -Name $LogFile.Name

        return [pscustomobject]@{
            TargetFolder = $targetFolder
            DestFile     = (Join-Path -Path $targetFolder -ChildPath $archiveFileName)
            IsArchive    = $true
            LogicalName  = $logical
            ChannelName  = (Convert-EvtxBaseNameToChannelName -BaseName $logical)
            SafeName     = $folderName
            SourceName   = $LogFile.Name
        }
    }

    $safeName = Get-SafeFolderOrActiveName -Name $base
    $targetFolder = Join-Path -Path $TargetRoot -ChildPath $safeName
    $destFile = Join-Path -Path $targetFolder -ChildPath ("{0}.evtx" -f $safeName)

    return [pscustomobject]@{
        TargetFolder = $targetFolder
        DestFile     = $destFile
        IsArchive    = $false
        LogicalName  = $base
        ChannelName  = (Convert-EvtxBaseNameToChannelName -BaseName $base)
        SafeName     = $safeName
        SourceName   = $LogFile.Name
    }
}

function Get-ResidualClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][bool]$Locked = $false
    )

    if ($Name -like '*.etl') {
        return 'OutOfScope-ETL'
    }

    # Protected/recreated files may remain under the default WINEVT folder even after a valid migration.
    # These must not be reported as generic unexpected residuals.
    if ($Name -match '^(Active Directory Web Services|State|Kaspersky Security)\.evtx$') {
        if ($Locked) {
            return 'LockedProtectedResidual'
        }
        return 'ProtectedResidual'
    }

    if (-not $script:SourceDeletionPolicyEnabled -and $Name -like '*.evtx') {
        return 'RetainedByPolicy'
    }

    foreach ($pattern in $script:ExpectedResidualPatterns) {
        if ($Name -match $pattern) {
            return 'ExpectedResidual'
        }
    }

    return 'UnexpectedResidual'
}

# ------------------------------------------------------------
# ACL Baseline
# ------------------------------------------------------------
function Set-LogRepositoryAclBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        try {
            New-Item -Path $RootPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created target root folder: $RootPath"
        } catch {
            Handle-Error -Message "Failed to create target root folder: $RootPath" -Exception $_
            throw
        }
    }

    try {
        Write-Log -Message "Applying ACL baseline to target root: $RootPath"

        $acl = Get-Acl -LiteralPath $RootPath
        $acl.SetAccessRuleProtection($true, $false)

        foreach ($rule in @($acl.Access)) {
            [void]$acl.RemoveAccessRule($rule)
        }

        $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $prop = [System.Security.AccessControl.PropagationFlags]::None
        $allow = [System.Security.AccessControl.AccessControlType]::Allow

        $sidSystem    = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
        $sidAdmins    = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
        $sidEventReaders = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-573'

        $ntEventLog = New-Object System.Security.Principal.NTAccount 'NT SERVICE', 'EventLog'
        $sidEventLog = $ntEventLog.Translate([System.Security.Principal.SecurityIdentifier])

        $ruleReaders = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sidEventReaders,
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

        [void]$acl.AddAccessRule($ruleReaders)
        [void]$acl.AddAccessRule($ruleSys)
        [void]$acl.AddAccessRule($ruleAdm)
        [void]$acl.AddAccessRule($ruleEvt)

        Set-Acl -LiteralPath $RootPath -AclObject $acl

        Write-Log -Message "ACL baseline applied successfully."
        Write-Log -Message "Baseline SIDs: EventLogReaders=S-1-5-32-573, SYSTEM=S-1-5-18, Admins=S-1-5-32-544, EventLog=$($sidEventLog.Value)"
    } catch {
        Handle-Error -Message "Failed to apply ACL baseline to: $RootPath" -Exception $_
        throw
    }
}

# ------------------------------------------------------------
# Services
# ------------------------------------------------------------
function Snapshot-ServiceState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$ServiceNames)

    foreach ($name in $ServiceNames) {
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            $script:ServiceState[$name] = $svc.Status
            Write-Log -Message "Service state snapshot: $name = $($svc.Status)"
        } catch {
            Write-Log -Message "Service not found (snapshot skip): $name" -Level 'WARN'
        }
    }
}

function Restore-ServiceState {
    [CmdletBinding()]
    param()

    foreach ($kvp in $script:ServiceState.GetEnumerator()) {
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
            Write-Log -Message "Failed to restore service state: $name ($($_.Exception.Message))" -Level 'WARN'
        }
    }
}

function Stop-For-Migration {
    [CmdletBinding()]
    param()

    $deps = @(Get-Service -Name 'EventLog' -DependentServices 2>$null)
    $depNames = @()
    if ($deps) { $depNames = @($deps.Name) }

    $track = @($depNames + $script:ExplicitPublisherServices + @('DhcpServer') + @('EventLog')) | Select-Object -Unique
    Snapshot-ServiceState -ServiceNames $track

    foreach ($svcName in $depNames) {
        try {
            Stop-Service -Name $svcName -Force -ErrorAction Stop
            Write-Log -Message "Stopped dependent service: $svcName"
        } catch {
            Write-Log -Message "Failed stopping dependent service: $svcName ($($_.Exception.Message))" -Level 'WARN'
        }
    }

    foreach ($svcName in $script:ExplicitPublisherServices) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne 'Stopped') {
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                Write-Log -Message "Stopped explicit publisher service: $svcName"
            }
        } catch {
            Write-Log -Message "Explicit publisher service not found or not stoppable: $svcName ($($_.Exception.Message))" -Level 'WARN'
        }
    }

    try {
        $dhcp = Get-Service -Name 'DhcpServer' -ErrorAction Stop
        if ($dhcp.Status -ne 'Stopped') {
            Stop-Service -Name 'DhcpServer' -Force -ErrorAction Stop
            Write-Log -Message 'Stopped DHCP Server service for migration.'
        }
    } catch {
        Write-Log -Message 'DHCP Server service not found or not stoppable.' -Level 'WARN'
    }

    try {
        Stop-Service -Name 'EventLog' -Force -ErrorAction Stop
        Write-Log -Message 'Stop requested: EventLog'

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            Start-Sleep -Milliseconds 250
        } while ((Get-Service -Name 'EventLog').Status -ne 'Stopped' -and $sw.Elapsed.TotalSeconds -lt 30)

        if ((Get-Service -Name 'EventLog').Status -ne 'Stopped') {
            throw 'EventLog could not be stopped reliably. Abort to avoid file locks.'
        }

        Write-Log -Message 'EventLog is Stopped.'
    } catch {
        Handle-Error -Message 'Failed to stop Event Log service.' -Exception $_
        throw
    }
}

function Start-After-Migration {
    [CmdletBinding()]
    param()

    try {
        $svc = Get-Service -Name 'EventLog' -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Start-Service -Name 'EventLog' -ErrorAction Stop
            Write-Log -Message 'Started Event Log service.'
        } else {
            Write-Log -Message 'Event Log service already Running.'
        }
    } catch {
        Handle-Error -Message 'Failed to start Event Log service.' -Exception $_
        throw
    }

    Restore-ServiceState
}

# ------------------------------------------------------------
# wevtutil Helpers
# ------------------------------------------------------------
function Invoke-WevtutilTimed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter()][int]$TimeoutSeconds = 20
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wevtutil.exe'
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
        return [pscustomobject]@{
            TimedOut = $true
            ExitCode = $null
            StdOut   = ''
            StdErr   = "Timed out after $TimeoutSeconds seconds."
        }
    }

    return [pscustomobject]@{
        TimedOut = $false
        ExitCode = $p.ExitCode
        StdOut   = $p.StandardOutput.ReadToEnd()
        StdErr   = $p.StandardError.ReadToEnd()
    }
}

function Get-ChannelLogFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $result = Invoke-WevtutilTimed -Arguments @('gl', "`"$ChannelName`"") -TimeoutSeconds 20
    if ($result.TimedOut -or $result.ExitCode -ne 0 -or -not $result.StdOut) {
        return $null
    }

    $lines = $result.StdOut -split "`r?`n"
    $line = $lines | Where-Object { $_ -match '^\s*logFileName\s*:\s*' } | Select-Object -First 1
    if (-not $line) { return $null }

    return (($line -replace '^\s*logFileName\s*:\s*', '').Trim())
}

function Set-ChannelLogFileNameDetailed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$NewLogFileName
    )

    $result = Invoke-WevtutilTimed -Arguments @('sl', "`"$ChannelName`"", "/lfn:`"$NewLogFileName`"") -TimeoutSeconds 20

    $accessDenied = $false
    if (-not $result.TimedOut -and $result.ExitCode -eq 5) {
        $accessDenied = $true
    }
    if (-not $accessDenied -and $result.StdErr -and ($result.StdErr -match 'access is denied|acesso negado')) {
        $accessDenied = $true
    }

    [pscustomobject]@{
        Success      = (-not $result.TimedOut -and $result.ExitCode -eq 0)
        TimedOut     = $result.TimedOut
        ExitCode     = $result.ExitCode
        StdErr       = $result.StdErr
        StdOut       = $result.StdOut
        AccessDenied = $accessDenied
    }
}

# ------------------------------------------------------------
# Classic Registry Update
# ------------------------------------------------------------
function Update-ClassicRegistryPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter(Mandatory)][bool]$AuditOnly
    )

    $registryBasePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog'

    try {
        foreach ($subKey in (Get-ChildItem -Path $registryBasePath -ErrorAction Stop)) {
            $fileProp = Get-ItemProperty -Path $subKey.PSPath -Name 'File' -ErrorAction SilentlyContinue
            if ($null -eq $fileProp) { continue }

            $logName = $subKey.PSChildName
            $safeLog = Get-SafeFolderOrActiveName -Name $logName
            $newFolder = Join-Path -Path $TargetRoot -ChildPath $safeLog
            $newFile = Join-Path -Path $newFolder -ChildPath ("{0}.evtx" -f $safeLog)

            if (-not (Test-Path -LiteralPath $newFolder)) {
                if (-not $AuditOnly) {
                    New-Item -Path $newFolder -ItemType Directory -Force | Out-Null
                }
            }

            if (-not $AuditOnly) {
                New-ItemProperty -Path $subKey.PSPath -Name 'AutoBackupLogFiles' -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $subKey.PSPath -Name 'Flags' -Value 1 -PropertyType DWord -Force | Out-Null

                $current = [string](Get-ItemProperty -Path $subKey.PSPath -Name 'File' -ErrorAction SilentlyContinue).File
                if ($current -ne $newFile) {
                    Set-ItemProperty -Path $subKey.PSPath -Name 'File' -Value $newFile -ErrorAction Stop
                }
            }

            Write-Log -Message ("Classic registry {0}: {1} -> {2}" -f ($(if ($AuditOnly) { 'audit' } else { 'updated' }), $logName, $newFile))
        }

        return $true
    } catch {
        Handle-Error -Message 'Failed to process classic registry paths.' -Exception $_
        return $false
    }
}

# ------------------------------------------------------------
# Direct WINEVT Update From Mappings
# ------------------------------------------------------------
function Update-WinevtChannels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Mappings,
        [Parameter(Mandatory)][bool]$AuditOnly
    )

    $activeMappings = @($Mappings | Where-Object { -not $_.IsArchive })
    if (@($activeMappings).Count -eq 0) {
        Write-Log -Message 'No active mappings available for direct WINEVT update.' -Level 'WARN'
        return $false
    }

    $changed = 0
    $skipped = 0
    $failed  = 0
    $nonFatalDenied = 0

    foreach ($map in $activeMappings) {
        $channelName = if ($map.PSObject.Properties.Name -contains 'ChannelName' -and -not [string]::IsNullOrWhiteSpace([string]$map.ChannelName)) { [string]$map.ChannelName } else { [string]$map.LogicalName }
        $targetFile  = [string]$map.DestinationFullPath

        try {
            if ([string]::IsNullOrWhiteSpace($channelName)) {
                $skipped++
                continue
            }

            $currentLfn = Get-ChannelLogFileName -ChannelName $channelName

            if ([string]::IsNullOrWhiteSpace($currentLfn)) {
                Write-Log -Message "Channel not readable via wevtutil gl, skip: $channelName" -Level 'WARN'
                $skipped++
                continue
            }

            $currentExpanded = Expand-EnvPath -Path $currentLfn

            if ($currentExpanded.TrimEnd('\') -ieq $targetFile.TrimEnd('\')) {
                Write-Log -Message "WINEVT channel already aligned: $channelName -> $targetFile"
                $changed++
                continue
            }

            if ($AuditOnly) {
                Write-Log -Message "WINEVT audit pending alignment: $channelName -> $targetFile"
                $changed++
                continue
            }

            $setResult = Set-ChannelLogFileNameDetailed -ChannelName $channelName -NewLogFileName $targetFile

            if (-not $setResult.Success) {
                $isNonFatal = $false

                if ($setResult.AccessDenied -and ($script:NonFatalWinevtChannels -contains $channelName)) {
                    $isNonFatal = $true
                }

                if ($isNonFatal) {
                    $nonFatalDenied++
                    Write-Log -Message "WINEVT channel protected/access-denied; migration will continue with warning: $channelName -> $targetFile | ExitCode=$($setResult.ExitCode) | StdErr=$($setResult.StdErr)" -Level 'WARN'
                    continue
                }

                $failed++
                Write-Log -Message "WINEVT channel update FAILED: $channelName -> $targetFile | ExitCode=$($setResult.ExitCode) | StdErr=$($setResult.StdErr)" -Level 'WARN'
                continue
            }

            $post = Get-ChannelLogFileName -ChannelName $channelName
            if ($post -and ((Expand-EnvPath -Path $post).TrimEnd('\') -ieq $targetFile.TrimEnd('\'))) {
                $changed++
                Write-Log -Message "WINEVT channel updated: $channelName -> $targetFile"
            } else {
                $failed++
                Write-Log -Message "WINEVT post-check mismatch: $channelName expected $targetFile got $post" -Level 'WARN'
            }
        } catch {
            $failed++
            Write-Log -Message "WINEVT channel exception: $channelName ($($_.Exception.Message))" -Level 'WARN'
        }
    }

    Write-Log -Message "WINEVT channel direct update summary: changed=$changed, skipped=$skipped, nonfatalDenied=$nonFatalDenied, failed=$failed"
    return ($failed -eq 0)
}

# ------------------------------------------------------------
# Classic Log Size
# ------------------------------------------------------------
function Set-ClassicLogSizes153600KB {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$AuditOnly)

    $classic = @('Application', 'Security', 'Setup', 'System')
    $maxKb = 153600
    $maxBytes = $maxKb * 1024

    foreach ($name in $classic) {
        try {
            if ($AuditOnly) {
                Write-Log -Message "Classic log size audit: $name would be set to ${maxKb}KB"
                continue
            }

            $result = Invoke-WevtutilTimed -Arguments @('sl', $name, "/ms:$maxBytes") -TimeoutSeconds 15
            if ($result.TimedOut -or $result.ExitCode -ne 0) {
                Write-Log -Message "Failed to enforce size for ${name}: ExitCode=$($result.ExitCode) StdErr=$($result.StdErr)" -Level 'WARN'
            } else {
                Write-Log -Message "Classic log size enforced: $name = ${maxKb}KB"
            }
        } catch {
            Write-Log -Message "Failed to enforce size for ${name}: $($_.Exception.Message)" -Level 'WARN'
        }
    }
}

# ------------------------------------------------------------
# Copy / Validate / Cleanup
# ------------------------------------------------------------
function Copy-EventLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TargetRoot,
        [Parameter()][object]$ProgressBar,
        [Parameter(Mandatory)][bool]$AuditOnly
    )

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        if (-not $AuditOnly) {
            New-Item -Path $TargetRoot -ItemType Directory -Force | Out-Null
        }
    }

    $logFiles = Get-ChildItem -LiteralPath $DefaultLogsFolder -File -ErrorAction Stop

    $evtxFiles = @($logFiles | Where-Object { $_.Extension -ieq '.evtx' })
    $etlFiles  = @($logFiles | Where-Object { $_.Extension -ieq '.etl' })

    foreach ($etl in $etlFiles) {
        Write-Log -Message "ETL file out of scope and skipped: $($etl.Name)" -Level 'WARN'
    }

    if ($ProgressBar -is [System.Windows.Forms.ProgressBar]) {
        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = @($evtxFiles).Count
        $ProgressBar.Value = 0
    }

    $mappings = New-Object System.Collections.Generic.List[pscustomobject]
    $i = 0

    foreach ($logFile in $evtxFiles) {
        try {
            $route = Get-TargetRouting -LogFile $logFile -TargetRoot $TargetRoot
            $targetFolder = $route.TargetFolder

            if (-not (Test-Path -LiteralPath $targetFolder)) {
                if (-not $AuditOnly) {
                    New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
                }
            }

            $dest = $route.DestFile
            $validationMode = 'AuditOnly'

            if (-not $AuditOnly) {
                if ($route.IsArchive -and (Test-Path -LiteralPath $dest)) {
                    $preferred = [System.IO.Path]::GetFileName($dest)
                    $dest = New-UniqueArchivePath -Directory $targetFolder -PreferredFileName $preferred
                }

                if (-not $route.IsArchive -and (Test-Path -LiteralPath $dest)) {
                    if (Test-DestinationFileSane -Path $dest) {
                        Write-Log -Message "Existing destination reused for active log: $dest" -Level 'WARN'

                        $sourceHash = Get-FileHashSafe -Path $logFile.FullName
                        $destHash   = Get-FileHashSafe -Path $dest

                        if ($sourceHash -and $destHash) {
                            if ($sourceHash -eq $destHash) {
                                $validationMode = 'SHA256-Reused'
                            } else {
                                Write-Log -Message "Existing destination differs from source but will be preserved: $dest" -Level 'WARN'
                                $validationMode = 'Existing-Reused'
                            }
                        } else {
                            $validationMode = 'Existing-Reused'
                        }
                    } else {
                        if (Test-FileLocked -Path $dest) {
                            Write-Log -Message "Locked active destination accepted by existence/path semantics: $dest" -Level 'WARN'
                            $validationMode = 'Locked-Existing-Reused'
                        } else {
                            Invoke-Retry -MaxAttempts 6 -DelayMs 300 -Action {
                                Copy-Item -LiteralPath $logFile.FullName -Destination $dest -Force -ErrorAction Stop
                            } | Out-Null
                            $validationMode = 'Basic'
                        }
                    }
                } elseif (-not (Test-Path -LiteralPath $dest)) {
                    Invoke-Retry -MaxAttempts 6 -DelayMs 300 -Action {
                        Copy-Item -LiteralPath $logFile.FullName -Destination $dest -Force -ErrorAction Stop
                    } | Out-Null
                    $validationMode = 'Basic'
                }

                if (-not (Test-Path -LiteralPath $dest)) {
                    throw "Destination missing after copy/reuse: '$dest'"
                }

                if (-not $route.IsArchive) {
                    if (-not (Test-DestinationFileSane -Path $dest) -and -not (Test-FileLocked -Path $dest)) {
                        throw "Destination validation failed for active log '$dest'"
                    }
                } else {
                    if (-not (Test-DestinationFileSane -Path $dest)) {
                        throw "Destination validation failed for archive '$dest'"
                    }
                }

                $sourceHash = Get-FileHashSafe -Path $logFile.FullName
                $destHash   = Get-FileHashSafe -Path $dest

                if ($sourceHash -and $destHash) {
                    if ($sourceHash -ne $destHash) {
                        Write-Log -Message "Hash mismatch tolerated for live/reused destination: $dest" -Level 'WARN'
                        if ($validationMode -eq 'Basic') {
                            $validationMode = 'Basic-HashMismatchTolerated'
                        }
                    } elseif ($validationMode -eq 'Basic') {
                        $validationMode = 'SHA256'
                    }
                } elseif (-not $destHash) {
                    if (-not $route.IsArchive -and (Test-FileLocked -Path $dest)) {
                        Write-Log -Message "Destination hash skipped due to active lock on canonical destination: $dest" -Level 'WARN'
                        if ($validationMode -eq 'Basic') {
                            $validationMode = 'Locked-Active-Destination'
                        }
                    } else {
                        throw "Destination hash/read validation failed for '$dest'"
                    }
                } else {
                    Write-Log -Message "Source hash skipped due to live lock/read restriction: $($logFile.FullName)" -Level 'WARN'
                }
            } else {
                Write-Log -Message "Audit-only mapping: $($logFile.Name) -> $dest"
            }

            $mappings.Add([pscustomobject]@{
                SourceFullPath      = $logFile.FullName
                SourceName          = $route.SourceName
                DestinationFullPath = $dest
                IsArchive           = $route.IsArchive
                SafeName            = $route.SafeName
                LogicalName         = $route.LogicalName
                ChannelName         = $route.ChannelName
                ValidationMode      = $validationMode
            }) | Out-Null

            Write-Log -Message "Mapped and validated ($validationMode): $($logFile.Name) -> $dest"
        } catch {
            Write-Log -Message "Copy/validation error: $($logFile.FullName) ($($_.Exception.Message))" -Level 'WARN'
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                Write-Log -Message (Format-ExceptionDetail -ErrorRecord $_) -Level 'WARN'
            }
        } finally {
            $i++
            if ($ProgressBar -is [System.Windows.Forms.ProgressBar]) {
                $ProgressBar.Value = [Math]::Min($i, $ProgressBar.Maximum)
            }
        }
    }

    return @($mappings)
}

function Test-MigrationMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Mappings,
        [Parameter(Mandatory)][bool]$AuditOnly
    )

    if ($AuditOnly) {
        return $true
    }

    foreach ($map in $Mappings) {
        if (-not (Test-Path -LiteralPath $map.DestinationFullPath)) {
            Write-Log -Message "Validation failed: destination missing: $($map.DestinationFullPath)" -Level 'WARN'
            return $false
        }

        if ($map.IsArchive) {
            if (-not (Test-DestinationFileSane -Path $map.DestinationFullPath)) {
                Write-Log -Message "Validation failed: archive destination invalid/empty: $($map.DestinationFullPath)" -Level 'WARN'
                return $false
            }
        } else {
            if (-not (Test-DestinationFileSane -Path $map.DestinationFullPath) -and -not (Test-FileLocked -Path $map.DestinationFullPath)) {
                Write-Log -Message "Validation failed: active destination invalid/non-locked: $($map.DestinationFullPath)" -Level 'WARN'
                return $false
            }
        }
    }

    return $true
}

function Cleanup-SourceEvtx {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Mappings,
        [Parameter(Mandatory)][bool]$AuditOnly,
        [Parameter(Mandatory)][bool]$DeleteSourceAfterValidation,
        [Parameter()][bool]$PostRebootCleanupMode = $false
    )

    if ($AuditOnly) {
        Write-Log -Message 'Cleanup skipped due to audit-only mode.' -Level 'WARN'
        return
    }

    if (-not $PostRebootCleanupMode) {
        Write-Log -Message 'Source EVTX deletion skipped: normal migration never deletes source files in v8.8.0 enterprise cleanup-safe mode.' -Level 'WARN'
        return
    }

    if (-not $DeleteSourceAfterValidation) {
        Write-Log -Message 'Post-reboot cleanup mode enabled, but source deletion was not explicitly forced. Residual files will be reported only.' -Level 'WARN'
        return
    }

    if (@($Mappings).Count -eq 0) {
        Write-Log -Message 'Cleanup skipped: mappings empty.' -Level 'WARN'
        return
    }

    foreach ($map in $Mappings) {
        try {
            if (-not (Test-Path -LiteralPath $map.DestinationFullPath)) {
                Write-Log -Message "Cleanup skipped; destination missing: $($map.DestinationFullPath)" -Level 'WARN'
                continue
            }

            if (Test-Path -LiteralPath $map.SourceFullPath) {
                $classification = Get-ResidualClassification -Name ([System.IO.Path]::GetFileName($map.SourceFullPath)) -Locked (Test-FileLocked -Path $map.SourceFullPath)
                if ($classification -in @('LockedProtectedResidual','ProtectedResidual','OutOfScope-ETL')) {
                    Write-Log -Message "Cleanup skipped for protected residual: $($map.SourceFullPath) [$classification]" -Level 'WARN'
                    continue
                }
                Remove-Item -LiteralPath $map.SourceFullPath -Force -ErrorAction Stop
                Write-Log -Message "Deleted source: $($map.SourceFullPath)"
            }
        } catch {
            Write-Log -Message "Delete source failed: $($map.SourceFullPath) ($($_.Exception.Message))" -Level 'WARN'
        }
    }
}

function Invoke-PostRebootResidualCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$ForceCleanup
    )

    Write-Log -Message "Post-reboot cleanup-only mode started. ForceCleanup=$ForceCleanup" -Level 'WARN'

    $items = @(Get-ChildItem -LiteralPath $DefaultLogsFolder -File -ErrorAction Stop)
    foreach ($item in $items) {
        $locked = Test-FileLocked -Path $item.FullName
        $classification = Get-ResidualClassification -Name $item.Name -Locked $locked

        if ($classification -in @('OutOfScope-ETL','LockedProtectedResidual','ProtectedResidual','ExpectedResidual','RetainedByPolicy')) {
            Write-Log -Message "Post-reboot cleanup skipped: $($item.FullName) [$classification]"
            continue
        }

        if (-not $ForceCleanup) {
            Write-Log -Message "Post-reboot cleanup report-only: $($item.FullName) [$classification]" -Level 'WARN'
            continue
        }

        try {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            Write-Log -Message "Post-reboot cleanup deleted: $($item.FullName)"
        } catch {
            Write-Log -Message "Post-reboot cleanup delete failed: $($item.FullName) ($($_.Exception.Message))" -Level 'WARN'
        }
    }
}

# ------------------------------------------------------------
# Reporting / Verification
# ------------------------------------------------------------
function Export-MigrationSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Mappings)

    try {
        $rows = foreach ($m in $Mappings) {
            [pscustomobject]@{
                SourceName          = $m.SourceName
                LogicalName         = $m.LogicalName
                ChannelName         = $m.ChannelName
                IsArchive           = $m.IsArchive
                ValidationMode      = $m.ValidationMode
                SourceFullPath      = $m.SourceFullPath
                DestinationFullPath = $m.DestinationFullPath
            }
        }

        $rows | Export-Csv -Path $summaryCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log -Message "Migration summary CSV exported: $summaryCsvPath"
    } catch {
        Write-Log -Message "Failed to export migration summary CSV: $($_.Exception.Message)" -Level 'WARN'
    }
}

function Export-ResidualSourceFiles {
    [CmdletBinding()]
    param()

    try {
        $items = Get-ChildItem -LiteralPath $DefaultLogsFolder -File -ErrorAction Stop
        $rows = foreach ($item in $items) {
            $locked = Test-FileLocked -Path $item.FullName
            [pscustomobject]@{
                Name           = $item.Name
                Extension      = $item.Extension
                Length         = $item.Length
                LastWriteTime  = $item.LastWriteTime
                Classification = (Get-ResidualClassification -Name $item.Name -Locked $locked)
                Locked         = $locked
                FullPath       = $item.FullName
            }
        }

        $rows | Export-Csv -Path $residualCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log -Message "Residual source files CSV exported: $residualCsvPath"
    } catch {
        Write-Log -Message "Failed to export residual source files CSV: $($_.Exception.Message)" -Level 'WARN'
    }
}

function Write-VerificationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Mappings,
        [Parameter(Mandatory)][bool]$AuditOnly
    )

    try {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("Verification Report")
        $lines.Add(("Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
        $lines.Add(("AuditOnly: {0}" -f $AuditOnly))
        $lines.Add("")

        $activeMappings = @($Mappings | Where-Object { -not $_.IsArchive })
        $archiveMappings = @($Mappings | Where-Object { $_.IsArchive })

        $lines.Add(("Active mappings: {0}" -f @($activeMappings).Count))
        $lines.Add(("Archive mappings: {0}" -f @($archiveMappings).Count))
        $lines.Add("")

        $lines.Add("Selected Active Channel Verification:")
        foreach ($m in $activeMappings | Select-Object -First 30) {
            $channelName = if ($m.PSObject.Properties.Name -contains 'ChannelName' -and -not [string]::IsNullOrWhiteSpace([string]$m.ChannelName)) { [string]$m.ChannelName } else { [string]$m.LogicalName }
            $expected = [string]$m.DestinationFullPath
            $actual = Get-ChannelLogFileName -ChannelName $channelName
            if ($actual) {
                $actualExpanded = Expand-EnvPath -Path $actual
                if ($actualExpanded.TrimEnd('\') -ieq $expected.TrimEnd('\')) {
                    $status = 'Aligned'
                } elseif ($script:NonFatalWinevtChannels -contains $channelName) {
                    $status = 'ProtectedDifferent'
                } else {
                    $status = 'Different'
                }
                $lines.Add((" - {0} | Expected={1} | Actual={2} | Status={3}" -f $channelName, $expected, $actualExpanded, $status))
            } else {
                $status = if ($script:NonFatalWinevtChannels -contains $channelName) { 'UnreadableProtectedChannel' } else { 'Unknown' }
                $lines.Add((" - {0} | Expected={1} | Actual=<unreadable> | Status={2}" -f $channelName, $expected, $status))
            }
        }

        $lines.Add("")
        $lines.Add("Residual Source Classification Summary:")

        $residualItems = Get-ChildItem -LiteralPath $DefaultLogsFolder -File -ErrorAction Stop
        $groups = $residualItems | Group-Object {
            $locked = Test-FileLocked -Path $_.FullName
            Get-ResidualClassification -Name $_.Name -Locked $locked
        } | Sort-Object Name
        foreach ($g in $groups) {
            $lines.Add((" - {0}: {1}" -f $g.Name, $g.Count))
        }

        $lines | Set-Content -Path $verificationTxtPath -Encoding UTF8
        Write-Log -Message "Verification TXT exported: $verificationTxtPath"
    } catch {
        Write-Log -Message "Failed to export verification TXT: $($_.Exception.Message)" -Level 'WARN'
    }
}


function Export-EnterpriseTelemetry {
    [CmdletBinding()]
    param(
        [Parameter()][object[]]$Mappings = @(),
        [Parameter(Mandatory)][bool]$AuditOnly,
        [Parameter(Mandatory)][string]$ExecutionMode,
        [Parameter()][string]$TargetRoot = ''
    )

    if (-not $script:JsonTelemetryEnabled) {
        Write-Log -Message 'Enterprise telemetry JSON export skipped by -NoJsonTelemetry.' -Level 'WARN'
        return
    }

    try {
        $activeMappings = @($Mappings | Where-Object { -not $_.IsArchive })
        $archiveMappings = @($Mappings | Where-Object { $_.IsArchive })

        $residualItems = @(Get-ChildItem -LiteralPath $DefaultLogsFolder -File -ErrorAction Stop)
        $residualRows = foreach ($item in $residualItems) {
            $locked = Test-FileLocked -Path $item.FullName
            [pscustomobject]@{
                Name           = $item.Name
                Extension      = $item.Extension
                Length         = $item.Length
                LastWriteTime  = $item.LastWriteTime.ToString('o')
                Classification = (Get-ResidualClassification -Name $item.Name -Locked $locked)
                Locked         = $locked
                FullPath       = $item.FullName
            }
        }

        $residualSummary = @{}
        foreach ($group in ($residualRows | Group-Object Classification)) {
            $residualSummary[$group.Name] = $group.Count
        }

        $selectedVerification = foreach ($m in ($activeMappings | Select-Object -First 30)) {
            $channelName = if ($m.PSObject.Properties.Name -contains 'ChannelName' -and -not [string]::IsNullOrWhiteSpace([string]$m.ChannelName)) { [string]$m.ChannelName } else { [string]$m.LogicalName }
            $expected = [string]$m.DestinationFullPath
            $actual = Get-ChannelLogFileName -ChannelName $channelName
            if ($actual) {
                $actualExpanded = Expand-EnvPath -Path $actual
                $status = if ($actualExpanded.TrimEnd('\') -ieq $expected.TrimEnd('\')) {
                    'Aligned'
                } elseif ($script:NonFatalWinevtChannels -contains $channelName) {
                    'ProtectedDifferent'
                } else {
                    'Different'
                }
            } else {
                $actualExpanded = '<unreadable>'
                $status = if ($script:NonFatalWinevtChannels -contains $channelName) { 'UnreadableProtectedChannel' } else { 'Unknown' }
            }

            [pscustomobject]@{
                ChannelName = $channelName
                Expected    = $expected
                Actual      = $actualExpanded
                Status      = $status
            }
        }

        $payload = [ordered]@{
            ToolName              = $scriptName
            Version               = '8.8.1-HARDENED-STATE'
            GeneratedAt           = (Get-Date).ToString('o')
            ComputerName          = $env:COMPUTERNAME
            UserName              = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            ExecutionMode         = $ExecutionMode
            AuditOnly             = $AuditOnly
            WhatIfFull            = [bool]$script:EnterpriseWhatIfFull
            SourceDeletionEnabled = [bool]$script:SourceDeletionPolicyEnabled
            TargetRoot            = $TargetRoot
            DefaultLogsFolder     = $DefaultLogsFolder
            LogPath               = $logPath
            Reports               = [ordered]@{
                MigrationSummaryCsv = $summaryCsvPath
                ResidualCsv         = $residualCsvPath
                VerificationTxt     = $verificationTxtPath
                TelemetryJson       = $telemetryJsonPath
            }
            Counts                = [ordered]@{
                ActiveMappings  = @($activeMappings).Count
                ArchiveMappings = @($archiveMappings).Count
                ResidualFiles   = @($residualRows).Count
            }
            ResidualSummary       = $residualSummary
            SelectedVerification  = @($selectedVerification)
        }

        $payload | ConvertTo-Json -Depth 8 | Set-Content -Path $telemetryJsonPath -Encoding UTF8
        Write-Log -Message "Enterprise telemetry JSON exported: $telemetryJsonPath"
    } catch {
        Write-Log -Message "Failed to export enterprise telemetry JSON: $($_.Exception.Message)" -Level 'WARN'
    }
}

# ------------------------------------------------------------
# GUI
# ------------------------------------------------------------
function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Paths (Classic + WINEVT Channels) - v8.8.0 ENTERPRISE'
    $form.Size = New-Object System.Drawing.Size(700, 445)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $labelTargetRootFolder = New-Object System.Windows.Forms.Label
    $labelTargetRootFolder.Text = 'Target root folder (example: L:\)'
    $labelTargetRootFolder.Location = New-Object System.Drawing.Point(10, 15)
    $labelTargetRootFolder.Size = New-Object System.Drawing.Size(660, 18)
    $form.Controls.Add($labelTargetRootFolder)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 38)
    $textBox.Size = New-Object System.Drawing.Size(660, 22)
    $form.Controls.Add($textBox)

    $checkAuditOnly = New-Object System.Windows.Forms.CheckBox
    $checkAuditOnly.Text = 'Audit only (no changes, reporting only)'
    $checkAuditOnly.Location = New-Object System.Drawing.Point(10, 66)
    $checkAuditOnly.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($checkAuditOnly)

    $checkDeleteSource = New-Object System.Windows.Forms.CheckBox
    $checkDeleteSource.Text = 'Force source cleanup only in post-reboot cleanup mode'
    $checkDeleteSource.Location = New-Object System.Drawing.Point(330, 66)
    $checkDeleteSource.Size = New-Object System.Drawing.Size(340, 20)
    $checkDeleteSource.Checked = $false
    $form.Controls.Add($checkDeleteSource)

    $checkCleanupOnly = New-Object System.Windows.Forms.CheckBox
    $checkCleanupOnly.Text = 'Post-reboot cleanup/report-only mode (no migration changes)'
    $checkCleanupOnly.Location = New-Object System.Drawing.Point(10, 92)
    $checkCleanupOnly.Size = New-Object System.Drawing.Size(660, 20)
    $checkCleanupOnly.Checked = $false
    $form.Controls.Add($checkCleanupOnly)

    $checkWhatIfFull = New-Object System.Windows.Forms.CheckBox
    $checkWhatIfFull.Text = 'Enterprise full dry-run / diff mode (no ACL, service, registry, WINEVT, or file changes)'
    $checkWhatIfFull.Location = New-Object System.Drawing.Point(10, 118)
    $checkWhatIfFull.Size = New-Object System.Drawing.Size(660, 20)
    $checkWhatIfFull.Checked = [bool]$script:EnterpriseWhatIfFull
    $form.Controls.Add($checkWhatIfFull)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 148)
    $progressBar.Size = New-Object System.Drawing.Size(660, 20)
    $form.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 178)
    $statusLabel.Size = New-Object System.Drawing.Size(660, 90)
    $statusLabel.Text = 'Ready.'
    $form.Controls.Add($statusLabel)

    $labelLog = New-Object System.Windows.Forms.Label
    $labelLog.Location = New-Object System.Drawing.Point(10, 272)
    $labelLog.Size = New-Object System.Drawing.Size(660, 60)
    $labelLog.Text = "Log file:`r`n$logPath`r`nReports will be written to C:\Logs-TEMP"
    $form.Controls.Add($labelLog)

    $buttonRun = New-Object System.Windows.Forms.Button
    $buttonRun.Text = 'Run'
    $buttonRun.Location = New-Object System.Drawing.Point(420, 371)
    $buttonRun.Size = New-Object System.Drawing.Size(110, 28)
    $form.Controls.Add($buttonRun)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = 'Close'
    $buttonClose.Location = New-Object System.Drawing.Point(560, 371)
    $buttonClose.Size = New-Object System.Drawing.Size(110, 28)
    $buttonClose.Enabled = $true
    $buttonClose.Add_Click({ Invoke-EventHandlerSafely -Context 'Close button' -ScriptBlock { $form.Close() } })
    $form.Controls.Add($buttonClose)

    $buttonRun.Add_Click({
        Invoke-EventHandlerSafely -Context 'Run button execution' -ScriptBlock {
        $targetRoot = Normalize-TargetRoot -Path $textBox.Text
        $mappings = @()
        $servicesRecovered = $false
        $whatIfFullSelected = ($checkWhatIfFull.Checked -or [bool]$script:EnterpriseWhatIfFull)
        $auditOnly = ($checkAuditOnly.Checked -or $whatIfFullSelected)
        $deleteSourceAfterValidation = $checkDeleteSource.Checked
        $cleanupOnly = $checkCleanupOnly.Checked
        $script:EnterpriseWhatIfFull = [bool]$whatIfFullSelected
        $script:SourceDeletionPolicyEnabled = ($deleteSourceAfterValidation -and (-not $auditOnly) -and $cleanupOnly)
        $executionMode = if ($cleanupOnly) { 'PostRebootCleanupOnly' } elseif ($whatIfFullSelected) { 'WhatIfFull' } elseif ($auditOnly) { 'AuditOnly' } else { 'Migration' }
        Write-Log -Message ("Selected execution mode: {0}" -f $executionMode) -Level 'INFO'

        if ([string]::IsNullOrWhiteSpace($targetRoot) -and -not $cleanupOnly) {
            [System.Windows.Forms.MessageBox]::Show(
                'Please enter the target root folder.',
                'Input Error',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        try {
            if ($cleanupOnly) {
                $buttonRun.Enabled = $false
                $buttonClose.Enabled = $false
                $statusLabel.Text = 'Running post-reboot cleanup/report-only mode...'
                $script:SourceDeletionPolicyEnabled = ($deleteSourceAfterValidation -and (-not $auditOnly))
                Invoke-PostRebootResidualCleanup -ForceCleanup ($deleteSourceAfterValidation -and (-not $auditOnly))
                Export-ResidualSourceFiles
                Export-EnterpriseTelemetry -Mappings @() -AuditOnly $auditOnly -ExecutionMode $executionMode -TargetRoot ''
                Write-Log -Message 'Post-reboot cleanup/report-only mode completed.'
                [System.Windows.Forms.MessageBox]::Show(
                    ("Post-reboot cleanup/report-only mode completed.`n`nLog:`n{0}`n`nResidual report:`n{1}" -f $logPath, $residualCsvPath),
                    'Cleanup Done',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                return
            }

            if (-not (Test-IsDriveRoot -Path $targetRoot)) {
                throw "Target root must be a dedicated drive root like L:\"
            }

            $resolvedDefault = (Resolve-Path -LiteralPath $DefaultLogsFolder).Path
            if ($targetRoot.TrimEnd('\') -ieq $resolvedDefault.TrimEnd('\')) {
                throw 'Target root cannot be the default WINEVT folder.'
            }

            $buttonRun.Enabled = $false
            $buttonClose.Enabled = $false

            if ($whatIfFullSelected) {
                Write-Log -Message 'Enterprise full dry-run mode active: no ACL, service, registry, WINEVT, copy, cleanup, or size changes will be made.' -Level 'WARN'
            }

            $statusLabel.Text = 'Applying ACL baseline to target...'
            if (-not $auditOnly) {
                Set-LogRepositoryAclBaseline -RootPath $targetRoot
            } else {
                Write-Log -Message "Audit-only mode: ACL baseline would be applied to $targetRoot"
            }

            $statusLabel.Text = 'Stopping services...'
            if (-not $auditOnly) {
                Stop-For-Migration
            } else {
                Write-Log -Message 'Audit-only mode: service stop skipped.'
            }

            $statusLabel.Text = 'Mapping / copying / validating logs...'
            $mappings = @(Copy-EventLogs -TargetRoot $targetRoot -ProgressBar $progressBar -AuditOnly $auditOnly)

            if (@($mappings).Count -eq 0) {
                throw 'No .evtx files were successfully mapped.'
            }

            if (-not (Test-MigrationMappings -Mappings $mappings -AuditOnly $auditOnly)) {
                throw 'Destination validation failed after mapping phase.'
            }

            $statusLabel.Text = 'Processing classic registry paths...'
            $okClassic = Update-ClassicRegistryPaths -TargetRoot $targetRoot -AuditOnly $auditOnly

            $statusLabel.Text = 'Processing WINEVT channels directly from mappings...'
            $okWinevt = Update-WinevtChannels -Mappings $mappings -AuditOnly $auditOnly

            $statusLabel.Text = 'Restoring services...'
            if (-not $auditOnly) {
                Start-After-Migration
                $servicesRecovered = $true
            } else {
                Write-Log -Message 'Audit-only mode: service restore skipped.'
                $servicesRecovered = $true
            }

            $statusLabel.Text = 'Processing classic log size policy...'
            Write-Log -Message 'Classic log size policy will be enforced after EventLog service restoration to avoid RPC 1722 errors.'
            Set-ClassicLogSizes153600KB -AuditOnly $auditOnly

            if (-not $okClassic) {
                throw 'Classic registry processing failed.'
            }

            if (-not $okWinevt) {
                Write-Log -Message 'WINEVT channel processing completed with warnings. The migration will continue and verification report will identify channels requiring manual review.' -Level 'WARN'
            }

            $statusLabel.Text = 'Cleanup / reporting...'
            Cleanup-SourceEvtx -Mappings $mappings -AuditOnly $auditOnly -DeleteSourceAfterValidation $deleteSourceAfterValidation -PostRebootCleanupMode $false
            Export-MigrationSummary -Mappings $mappings
            Export-ResidualSourceFiles
            Write-VerificationReport -Mappings $mappings -AuditOnly $auditOnly
            Export-EnterpriseTelemetry -Mappings $mappings -AuditOnly $auditOnly -ExecutionMode $executionMode -TargetRoot $targetRoot

            $progressBar.Value = $progressBar.Maximum
            $finalStatus = if ($auditOnly) { 'Audit completed.' } else { 'Completed.' }
            $finalMessage = if ($auditOnly) { 'Audit completed successfully.' } else { 'Migration completed successfully.' }
            $statusLabel.Text = $finalStatus
            Write-Log -Message $finalMessage

            [System.Windows.Forms.MessageBox]::Show(
                ("{0}`n`nLog:`n{1}`n`nReports:`n{2}`n{3}`n{4}`n{5}" -f $finalMessage, $logPath, $summaryCsvPath, $residualCsvPath, $verificationTxtPath, $telemetryJsonPath),
                'Done',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } catch {
            Handle-Error -Message 'Processing failed. Review the log for details.' -Exception $_

            if (-not $servicesRecovered -and -not $auditOnly) {
                try { Start-After-Migration } catch { }
            }

            try {
                if (@($mappings).Count -gt 0) {
                    Export-MigrationSummary -Mappings $mappings
                }
                Export-ResidualSourceFiles
                if (@($mappings).Count -gt 0) {
                    Write-VerificationReport -Mappings $mappings -AuditOnly $auditOnly
                }
                Export-EnterpriseTelemetry -Mappings $mappings -AuditOnly $auditOnly -ExecutionMode $executionMode -TargetRoot $targetRoot
            } catch { }

            $statusLabel.Text = "Failed. Review log:`r`n$logPath"
            Write-Log -Message 'GUI failure path reached; Close button enabled for operator exit.' -Level 'WARN'
        } finally {
            try { if ($buttonClose -and -not $buttonClose.IsDisposed) { $buttonClose.Enabled = $true } } catch { }
            try { if ($buttonRun -and -not $buttonRun.IsDisposed) { $buttonRun.Enabled = $true } } catch { }
        }
        }
    })

    try {
        $null = $form.ShowDialog()
    } catch {
        Write-FailsafeExceptionLog -Context 'Form.ShowDialog failed.' -ExceptionObject $_
        Show-SafeMessageBox -Message ("The GUI failed before or during display. Review the log file:`r`n{0}" -f $logPath) -Title 'GUI Startup Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# ------------------------------------------------------------
# Launch
# ------------------------------------------------------------
if ($PostRebootCleanupOnly) {
    try {
        Write-Log -Message 'Command-line post-reboot cleanup-only mode selected. GUI and migration phases will not run.' -Level 'WARN'
        $script:SourceDeletionPolicyEnabled = [bool]$ForceSourceCleanup
        Invoke-PostRebootResidualCleanup -ForceCleanup ([bool]$ForceSourceCleanup)
        Export-ResidualSourceFiles
        Export-EnterpriseTelemetry -Mappings @() -AuditOnly $false -ExecutionMode 'PostRebootCleanupOnly' -TargetRoot ''
    } catch {
        Write-FailsafeExceptionLog -Context 'Post-reboot cleanup-only command-line mode failed.' -ExceptionObject $_
    }
    Write-Log -Message 'Script ended.' -Level 'INFO'
    return
}

Setup-GUI

Write-Log -Message 'Script ended.' -Level 'INFO'

# End of script
