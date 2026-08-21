#requires -Version 5.1
<#
.SYNOPSIS
Runs governed weekly maintenance on domain-joined or standalone Windows workstations.

.DESCRIPTION
Provides an enterprise workstation-maintenance framework with local runtime staging,
idempotent Scheduled Task registration, deterministic UTF-8 logging, system integrity
checks, optional domain/GPO operations, controlled Windows Update cache maintenance,
session-aware notifications, and a mandatory reboot fail-safe.

The default organization identifier is SCRIPTGUY. Environment-specific values are
centralized in the configuration section and no forest, domain controller, WSUS
server, OU, GPO name, or institutional UNC path is assumed.

.PARAMETER MasterScriptPath
Optional authoritative UNC or local source path used to refresh the staged runtime.
When omitted or unavailable, the currently executing script is staged locally.

.PARAMETER RunDeferred
Runs the scheduled maintenance workload. Without this switch, the script performs
bootstrap and Scheduled Task registration only.

.PARAMETER StageRuntime
Identifies an invocation launched from the local staging workflow.

.PARAMETER ShowConsole
Keeps the PowerShell console visible for interactive troubleshooting.

.NOTES
Author: Luiz Hamilton Silva - github.com/brazilianscriptguy
Organization template: SCRIPTGUY
Version: 3.0.0-GENERALIZED-ENTERPRISE-REBOOT-GUARANTEED
Requires: Windows PowerShell 5.1; administrative or SYSTEM context
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$RunDeferred,
    [switch]$StageRuntime,
    [string]$MasterScriptPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==================== Configuration ====================
$OrganizationName             = 'SCRIPTGUY'
$LogRetentionDays            = 7
$LogRetentionPath         = 'C:\Scripts-LOGS'
$LogDir                      = 'C:\Scripts-LOGS'
$ScriptName                  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$ScriptVersion               = '3.0.0-GENERALIZED-ENTERPRISE-REBOOT-GUARANTEED'
$script:ExpectedExecutionSource = $MasterScriptPath
$script:StageRoot            = Join-Path $env:ProgramData "$OrganizationName\Maintenance-Workstations"
$script:LocalScriptPath      = Join-Path $script:StageRoot 'Invoke-EnterpriseWorkstationMaintenance.ps1'
$script:DeferredTaskName     = "$OrganizationName-Maintenance-Workstations-Deferred"
$script:RebootEnforcerTaskName = "$OrganizationName-Maintenance-Workstations-Reboot-Enforcer"
$script:MaintenanceWindow     = [ordered]@{
    Day               = 'Thursday'
    InstallTime       = '18:00'
    RestartTime       = '20:00'
    NotificationStart = '18:00'
}
$script:ExecutionSource      = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $MyInvocation.MyCommand.Name }
$script:StateRoot            = $script:StageRoot
$script:StateFilePath        = Join-Path $script:StateRoot 'restart-state.json'
$script:IdleThresholdMinutes = 90 # Telemetry only; never blocks the restart.
$script:MaxDeferredRunsBeforeForcedReboot = 0 # State compatibility; deferral is disabled.
$LogFile                     = Join-Path $LogDir "$ScriptName.log"
$PathSoftDist                = 'C:\Windows\SoftwareDistribution'
$PathCatroot2                = 'C:\Windows\System32\catroot2'
$DefaultUserImagePath        = 'C:\ProgramData\Microsoft\User Account Pictures\user.png'
$GroupPolicyUpdateWaitSeconds         = 30
$CleanWuTimeoutSec           = 600
$RebootFinalDelaySec         = 0
$ShutdownNoticeSeconds       = 900
$script:ExecutionLockMinutes  = 600
$script:RebootAwaitMinutes    = 240
$script:GovernanceStateFile   = Join-Path $script:StateRoot 'runtime-governance-state.json'
$script:MaintenanceStateFile  = Join-Path $script:StateRoot 'maintenance-state.json'
$script:BootstrapStateFile    = Join-Path $script:StateRoot 'bootstrap-state.json'

$RunSfcDism                  = $true
$ResetLocalGpo               = $true
$CleanWuCache                = $true
$ReEnableWuTasksAtEnd        = $true
$RunAdNetworkChecks          = $true
$RunGpupdateComputerOnly     = $true
$RunCertutilPulse            = $true
$CertSyncEnable              = $false
$SetDefaultUserPicture       = $true
$HandleUserProfiles          = $true
$CleanUserTemp               = $true
$RestartSpooler              = $true
$SendUserNotices             = $true
$ForceReboot                 = $true

# ==================== Console ====================
function Set-ConsoleVisibility {
    param([bool]$Visible)
    try {
        $signature = @'
using System;
using System.Runtime.InteropServices;
public static class Win32Console {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue | Out-Null
        $hWnd = [Win32Console]::GetConsoleWindow()
        if ($hWnd -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($hWnd, $(if ($Visible) { 5 } else { 0 }))
        }
    } catch {
    }
}
if (-not $ShowConsole) { Set-ConsoleVisibility -Visible $false }

# ==================== Logging ====================
function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-TimeStamp {
    (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Test-AdministratorContext {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-PreValidation {
    Ensure-Directory -Path $script:StateRoot
    Ensure-Directory -Path $LogDir

    if (-not (Test-AdministratorContext)) {
        throw 'Insufficient context: the script must run with administrative privileges or as SYSTEM.'
    }

    try {
        if (-not (Test-Path -LiteralPath $script:StateRoot)) {
            New-Item -Path $script:StateRoot -ItemType Directory -Force | Out-Null
        }
        $probeFile = Join-Path $script:StateRoot '.__write_test.tmp'
        Set-Content -LiteralPath $probeFile -Value 'ok' -Encoding UTF8 -Force
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
        Write-Log -Level INFO -Message "Pre-validation completed. Script source: $script:ExecutionSource | Local state: $script:StateFilePath"
        if ([string]::IsNullOrWhiteSpace($script:ExpectedExecutionSource)) {
            Write-Log -Level INFO -Message 'Authoritative source: not configured; the current script will be used for local staging.'
        } else {
            Write-Log -Level INFO -Message "Configured authoritative source: $script:ExpectedExecutionSource"
        }
    } catch {
        throw "State-directory pre-validation failed for '$script:StateRoot': $($_.Exception.Message)"
    }
}

function Initialize-Log {
    Ensure-Directory -Path $LogDir
    if (-not (Test-Path -LiteralPath $LogFile)) {
        [System.IO.File]::WriteAllText($LogFile, "[$(Get-TimeStamp)] [INFO] (init) Created UTF-8 log file.`r`n", [System.Text.UTF8Encoding]::new($true))
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    try {
        Initialize-Log
        $line = "[$(Get-TimeStamp)] [$Level] $Message`r`n"
        [System.IO.File]::AppendAllText($LogFile, $line, [System.Text.UTF8Encoding]::new($false))
    } catch {
    }
}

function Write-LogSection {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][string]$Body = ''
    )
    $chunk = "`r`n==== $Title ====`r`n"
    if ($Body) {
        $chunk += $Body
        if (-not $Body.EndsWith("`n")) { $chunk += "`r`n" }
    }
    [System.IO.File]::AppendAllText($LogFile, $chunk, [System.Text.UTF8Encoding]::new($false))
}

# ==================== Command execution ====================
function Normalize-ExternalText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $normalized = $Text -replace "`0", ''
    $normalized = $normalized -replace [char]0xFFFD, '?'
    $normalized = $normalized -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ''
    return $normalized
}

function Get-NativeOutputEncoding {
    try {
        $codePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
        return [System.Text.Encoding]::GetEncoding($codePage)
    } catch {
        return [System.Text.Encoding]::Default
    }
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$Title,
        [int]$TimeoutSec = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:ComSpec"
    # Most Windows inbox tools emit text in the active OEM code page, even when
    # their output is redirected. Forcing UTF-8 causes mojibake on pt-BR hosts.
    $psi.Arguments = "/d /c $CommandLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $nativeEncoding = Get-NativeOutputEncoding
    $psi.StandardOutputEncoding = $nativeEncoding
    $psi.StandardErrorEncoding  = $nativeEncoding

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    if ($TimeoutSec -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            try { $proc.Kill() } catch {}
            $stdout = Normalize-ExternalText -Text ($proc.StandardOutput.ReadToEnd())
            $stderr = Normalize-ExternalText -Text ($proc.StandardError.ReadToEnd())
            Write-LogSection -Title $Title -Body (($stdout + "`r`n" + $stderr).Trim())
            return [pscustomobject]@{ ExitCode = -1; StdOut = $stdout; StdErr = $stderr; TimedOut = $true }
        }
    } else {
        $proc.WaitForExit()
    }

    $stdout = Normalize-ExternalText -Text ($proc.StandardOutput.ReadToEnd())
    $stderr = Normalize-ExternalText -Text ($proc.StandardError.ReadToEnd())
    $body = ($stdout + $(if ($stderr) { "`r`n$stderr" } else { '' })).TrimEnd()
    Write-LogSection -Title $Title -Body $body

    [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
        TimedOut = $false
    }
}

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$Title,
        [int]$TimeoutSec = 0
    )
    $result = Invoke-CapturedCommand -CommandLine $CommandLine -Title $Title -TimeoutSec $TimeoutSec
    if ($result.ExitCode -ne 0) {
        Write-Log -Level WARN -Message "Command '$Title' returned exit code $($result.ExitCode)."
    }
    $result
}

# ==================== Helpers ====================
function Test-TaskExists {
    param([Parameter(Mandatory)][string]$TaskName)
    $p = Start-Process -FilePath schtasks.exe -ArgumentList @('/query','/tn', $TaskName) -Wait -PassThru -WindowStyle Hidden -ErrorAction SilentlyContinue
    return ($p -and $p.ExitCode -eq 0)
}

function Remove-FolderIfExists {
    param([Parameter(Mandatory)][string]$PathLiteral)
    $path = [Environment]::ExpandEnvironmentVariables($PathLiteral)
    if (Test-Path -LiteralPath $path) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Log -Level INFO -Message "Directory deleted: $path"
        } catch {
            Write-Log -Level WARN -Message "Failed to delete $path - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level INFO -Message "Directory not found: $path"
    }
}

function Rename-IfExists {
    param([Parameter(Mandatory)][string]$PathLiteral)
    $src = [Environment]::ExpandEnvironmentVariables($PathLiteral)
    if (-not (Test-Path -LiteralPath $src)) { return }
    $parent = Split-Path -Path $src -Parent
    $name = Split-Path -Path $src -Leaf
    $newName = '{0}._purge_{1}' -f $name, (Get-Date).ToString('yyyyMMdd_HHmmss')
    try {
        Rename-Item -LiteralPath $src -NewName $newName -ErrorAction Stop
        Write-Log -Level INFO -Message "Folder renamed: $src -> $(Join-Path $parent $newName)"
    } catch {
        Write-Log -Level WARN -Message "Failed to rename $src - $($_.Exception.Message)"
    }
}

function Get-NormalizedValue {
    param($Value, [string]$Fallback = '')
    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

# ==================== Domain / AD ====================
function Get-ComputerDN {
    try {
        $adsi = New-Object -ComObject ADSystemInfo
        $val = Get-NormalizedValue -Value $adsi.ComputerName -Fallback ''
        if ($val) { return $val }
    } catch {}

    try {
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.Filter = "(&(objectCategory=computer)(sAMAccountName=$env:COMPUTERNAME`$))"
        $searcher.SearchScope = 'Subtree'
        $searcher.PropertiesToLoad.Add('distinguishedName') | Out-Null
        $result = $searcher.FindOne()
        if ($result -and $result.Properties['distinguishedname'] -and $result.Properties['distinguishedname'].Count -gt 0) {
            return (Get-NormalizedValue -Value $result.Properties['distinguishedname'][0] -Fallback 'NOT AVAILABLE')
        }
    } catch {}

    try {
        return (Get-NormalizedValue -Value ([ADSI]'LDAP://RootDSE').defaultNamingContext -Fallback 'NOT AVAILABLE')
    } catch {
        return 'NOT AVAILABLE'
    }
}

function Convert-DistinguishedNameToDnsDomain {
    param([string]$DistinguishedName)

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) { return '' }

    $dcParts = @([regex]::Matches($DistinguishedName, '(?i)(?:^|,)DC=([^,]+)') | ForEach-Object { $_.Groups[1].Value })
    if ($dcParts.Count -gt 0) {
        return ($dcParts -join '.').ToUpperInvariant()
    }

    return ''
}

function Test-IsDistinguishedName {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -match '(?i)(^|,)(CN|OU|DC)=')
}

function Get-DomainFQDN {
    # Critical rule v1.3.2:
    # - Computer DN e Domain FQDN are different values.
    # - Never return the full DN as the domain because nltest /dsgetdc:<DN> returns ERROR_INVALID_DOMAINNAME.

    try {
        $adsi = New-Object -ComObject ADSystemInfo
        $val = Get-NormalizedValue -Value $adsi.DomainDNSName -Fallback ''
        if ($val) {
            if (Test-IsDistinguishedName -Value $val) {
                $fromDn = Convert-DistinguishedNameToDnsDomain -DistinguishedName $val
                if ($fromDn) { return $fromDn }
            } else {
                return $val.ToUpperInvariant()
            }
        }
    } catch {}

    if ($env:USERDNSDOMAIN -and -not (Test-IsDistinguishedName -Value $env:USERDNSDOMAIN)) {
        return $env:USERDNSDOMAIN.ToUpperInvariant()
    }

    try {
        $rootDse = [ADSI]'LDAP://RootDSE'
        $defaultNamingContext = Get-NormalizedValue -Value $rootDse.defaultNamingContext -Fallback ''
        $fromRootDse = Convert-DistinguishedNameToDnsDomain -DistinguishedName $defaultNamingContext
        if ($fromRootDse) { return $fromRootDse }
    } catch {}

    try {
        $computerDn = Get-ComputerDN
        $fromComputerDn = Convert-DistinguishedNameToDnsDomain -DistinguishedName $computerDn
        if ($fromComputerDn) { return $fromComputerDn }
    } catch {}

    try {
        $fqdn = (& whoami /fqdn 2>$null | Out-String).Trim()
        if ($fqdn -match '@') {
            $candidate = ($fqdn -split '@')[-1]
            if (-not (Test-IsDistinguishedName -Value $candidate)) { return $candidate.ToUpperInvariant() }
        }
    } catch {}

    return 'WORKGROUP'
}

function Get-DomainNetBIOS {
    try {
        $adsi = New-Object -ComObject ADSystemInfo
        $val = Get-NormalizedValue -Value $adsi.DomainShortName -Fallback ''
        if ($val) { return $val }
    } catch {}

    if ($env:USERDOMAIN) { return $env:USERDOMAIN }
    return 'WORKGROUP'
}

# ==================== Services ====================
function Get-ServiceStateSafe {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
        return [string]$svc.State
    } catch {
        return 'DESCONHECIDO'
    }
}

function Start-ServiceSilentSafe {
    param([Parameter(Mandatory)][string]$Name)
    $state = Get-ServiceStateSafe -Name $Name
    if ($state -eq 'Running') {
        Write-Log -Level INFO -Message "Service $Name was already running."
        return
    }
    try {
        Start-Service -Name $Name -ErrorAction Stop
        Start-Sleep -Milliseconds 750
        $state = Get-ServiceStateSafe -Name $Name
        if ($state -eq 'Running') {
            Write-Log -Level INFO -Message "Service $Name started successfully."
        } else {
            Write-Log -Level WARN -Message "Failed to start $Name. Current state: $state"
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to start $Name - $($_.Exception.Message)"
    }
}

function Stop-ServiceWithRetry {
    param([Parameter(Mandatory)][string]$Name)

    $state = Get-ServiceStateSafe -Name $Name
    if ($state -eq 'Stopped') {
        Write-Log -Level INFO -Message "Service $Name was already stopped."
        return $true
    }

    if ($Name -in @('WaaSMedicSvc','TrustedInstaller')) {
        try {
            & sc.exe stop $Name *> $null
            Start-Sleep -Milliseconds 750
            $state = Get-ServiceStateSafe -Name $Name
            if ($state -eq 'Stopped') {
                Write-Log -Level INFO -Message "Service $Name stopped successfully."
                return $true
            }
            Write-Log -Level WARN -Message "Protected service detected: $Name could not be stopped. Continuing."
            return $false
        } catch {
            Write-Log -Level WARN -Message "Protected service detected: $Name could not be stopped. Continuing."
            return $false
        }
    }

    foreach ($attempt in 1..3) {
        try {
            & net.exe stop $Name /y *> $null
        } catch {}
        try {
            & sc.exe stop $Name *> $null
        } catch {}
        Start-Sleep -Milliseconds 1500
        $state = Get-ServiceStateSafe -Name $Name
        if ($state -eq 'Stopped') {
            Write-Log -Level INFO -Message "Service $Name stopped successfully."
            return $true
        }
        try {
            & taskkill.exe /f /im UsoClient.exe /im MoUsoCoreWorker.exe /im usocoreworker.exe /im wuauclt.exe /im tiworker.exe *> $null
        } catch {}
        Write-Log -Level WARN -Message "Failed to stop $Name (attempt $attempt/3)."
        Start-Sleep -Seconds 5
    }

    $state = Get-ServiceStateSafe -Name $Name
    if ($state -eq 'Stopped') { return $true }
    Write-Log -Level WARN -Message "Unable to stop $Name. Prosseguindo."
    return $false
}

# ==================== SFC / DISM ====================
function Invoke-SfcDism {
    Write-Log -Level INFO -Message 'Running SFC /scannow...'
    $t0 = Get-Date
    $rc = (Start-Process -FilePath "$env:windir\system32\sfc.exe" -ArgumentList '/scannow' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) {
        Write-Log -Level INFO -Message "SFC completed successfully (rc=0, duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    } else {
        Write-Log -Level WARN -Message "SFC returned exit code $rc (duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    }

    Write-Log -Level INFO -Message 'Running DISM /RestoreHealth...'
    $t0 = Get-Date
    $rc = (Start-Process -FilePath "$env:windir\system32\dism.exe" -ArgumentList '/online','/cleanup-image','/restorehealth' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) {
        Write-Log -Level INFO -Message "DISM /restorehealth completed (rc=0, duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    } else {
        $unsignedRc = [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes([int32]$rc), 0)
        $hexRc = ('0x{0:X8}' -f $unsignedRc)
        $diagnosis = switch ($hexRc) {
            '0x800F081F' { 'Source files were not found. Validate the repair source, connectivity, and repair-content policy.' }
            '0x800F0906' { 'Repair content could not be downloaded. Validate the proxy, WSUS/Microsoft Update, and connectivity.' }
            '0x800F0954' { 'WSUS policy may be preventing optional or repair content downloads. Validate the alternate component source.' }
            '0x800F0922' { 'Servicing failure. Validate system-partition free space, CBS.log, and DISM.log.' }
            '0x800F0915' { 'CBS/servicing engine failure. Review C:\Windows\Logs\DISM\dism.log e C:\Windows\Logs\CBS\CBS.log; validate a repair source that matches the installed build.' }
            default      { 'Code is not mapped locally. Review DISM.log and CBS.log before retrying repair.' }
        }
        Write-Log -Level WARN -Message "DISM /RestoreHealth failed. ExitCodeDecimal=$rc; ExitCodeHex=$hexRc; Duration=$([int]((Get-Date)-$t0).TotalSeconds)s; Diagnosis='$diagnosis'"
    }
}

# ==================== GPO ====================
function Reset-LocalGpoCache {
    Remove-FolderIfExists -PathLiteral '%windir%\System32\GroupPolicy'
    Remove-FolderIfExists -PathLiteral '%windir%\System32\GroupPolicyUsers'
    Remove-FolderIfExists -PathLiteral '%windir%\SysWOW64\GroupPolicy'
    Remove-FolderIfExists -PathLiteral '%windir%\SysWOW64\GroupPolicyUsers'
    Write-Log -Level INFO -Message 'Local Group Policy cache removed (folders). No security.inf file will be applied.'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy'
    if (Test-Path -LiteralPath $key) {
        try {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            Write-Log -Level INFO -Message 'Local Group Policy registry key removed (reg).'
        } catch {
            Write-Log -Level WARN -Message "Failed to remove the local Group Policy registry key - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level INFO -Message 'Local Group Policy registry key not found (nothing to remove).'
    }
}

# ==================== WU ====================
function Set-WuRecurringTasksState {
    param([Parameter(Mandatory)][bool]$Enable)

    $tasks = @(
        '\Microsoft\Windows\UpdateOrchestrator\Schedule Scan',
        '\Microsoft\Windows\UpdateOrchestrator\USO_UxBroker',
        '\Microsoft\Windows\UpdateOrchestrator\Schedule Retry Scan',
        '\Microsoft\Windows\UpdateOrchestrator\UpdateModelTask',
        '\Microsoft\Windows\WindowsUpdate\Scheduled Start',
        '\Microsoft\Windows\WindowsUpdate\AUScheduledInstall',
        '\Microsoft\Windows\WindowsUpdate\Automatic App Update'
    )

    $action = if ($Enable) { '/enable' } else { '/disable' }
    $label  = if ($Enable) { 'reabilitadas (best-effort)' } else { 'desabilitadas temporariamente' }

    foreach ($task in $tasks) {
        if (Test-TaskExists -TaskName $task) {
            try {
                $taskCommand = 'schtasks.exe /change /tn "{0}" {1}' -f $task, $action
                $taskResult = Invoke-CapturedCommand -CommandLine $taskCommand -Title "SCHTASKS WU $action - $task"
                if ($taskResult.ExitCode -ne 0) {
                    Write-Log -Level WARN -Message "Failed to update Windows Update task '$task'. ExitCode=$($taskResult.ExitCode)."
                }
            } catch {}
        }
    }
    Write-Log -Level INFO -Message "Tarefas WU $label."
}

function Invoke-WuCacheCleanup {
    if (-not $CleanWuCache) { return }
    $t0 = Get-Date
    Write-Log -Level INFO -Message "[WU] Block started (timeout ${CleanWuTimeoutSec}s)."

    Set-WuRecurringTasksState -Enable:$false

    $okDo    = Stop-ServiceWithRetry -Name 'dosvc'
    $okMedic = Stop-ServiceWithRetry -Name 'WaaSMedicSvc'
    $okTI    = Stop-ServiceWithRetry -Name 'TrustedInstaller'
    $okBits  = Stop-ServiceWithRetry -Name 'bits'
    $okWua   = Stop-ServiceWithRetry -Name 'wuauserv'
    $okCrypt = Stop-ServiceWithRetry -Name 'cryptsvc'

    if (-not $okCrypt) {
        Write-Log -Level WARN -Message 'CryptSvc did not stop (possible AV/EDR). catroot2 will be preserved.'
    }

    if (((Get-Date) - $t0).TotalSeconds -le $CleanWuTimeoutSec) {
        if ($okBits -and $okWua) {
            if (Test-Path -LiteralPath $PathSoftDist) {
                try {
                    Remove-Item -LiteralPath $PathSoftDist -Recurse -Force -ErrorAction Stop
                    Write-Log -Level INFO -Message 'SoftwareDistribution removed successfully.'
                } catch {
                    Write-Log -Level WARN -Message 'Failed to remove SoftwareDistribution. Attempting rename...'
                    Rename-IfExists -PathLiteral '%SystemRoot%\SoftwareDistribution'
                }
            } else {
                Write-Log -Level INFO -Message 'SoftwareDistribution folder not found.'
            }
        } else {
            Write-Log -Level ERROR -Message 'BITS/WUAUSERV did not stop; skipping SoftwareDistribution cleanup.'
        }

        if ($okCrypt) {
            if (Test-Path -LiteralPath $PathCatroot2) {
                try {
                    Remove-Item -LiteralPath $PathCatroot2 -Recurse -Force -ErrorAction Stop
                    Write-Log -Level INFO -Message 'catroot2 removed successfully.'
                } catch {
                    Write-Log -Level WARN -Message 'Failed to remove catroot2. Attempting rename...'
                    Rename-IfExists -PathLiteral $PathCatroot2
                }
            } else {
                Write-Log -Level INFO -Message 'catroot2 not found (skipping).'
            }
        }
    } else {
        Write-Log -Level ERROR -Message '[WU] Block timed out. Aborting cleanup and restoring services/tasks.'
    }

    if ($ReEnableWuTasksAtEnd) { Set-WuRecurringTasksState -Enable:$true }

    foreach ($svc in 'cryptsvc','bits','wuauserv') {
        Start-ServiceSilentSafe -Name $svc
    }

    try { & bitsadmin.exe /reset /allusers *> $null } catch {}
    try { Start-Process -FilePath wuauclt.exe -ArgumentList '/resetauthorization','/detectnow' -WindowStyle Hidden } catch {}
    if (Test-Path -LiteralPath "$env:SystemRoot\System32\UsoClient.exe") {
        foreach ($arg in 'StartScan','StartDownload','StartInstall') {
            try { Start-Process -FilePath "$env:SystemRoot\System32\UsoClient.exe" -ArgumentList $arg -WindowStyle Hidden } catch {}
        }
    }

    Write-Log -Level INFO -Message "[WU] Completed in $([int]((Get-Date)-$t0).TotalSeconds)s."
}

# ==================== Certificados ====================
function Invoke-CertSyncIfEnabled {
    if (-not $CertSyncEnable) {
        Write-Log -Level INFO -Message 'Trusted root certificate synchronization is disabled by configuration.'
        return
    }
    Write-Log -Level INFO -Message 'Synchronizing root certificates through Windows Update...'
    $rc1 = (Start-Process -FilePath certutil.exe -ArgumentList '-setreg','chain\ChainCacheResyncFiletime','@now' -Wait -PassThru -WindowStyle Hidden).ExitCode
    $rc2 = (Start-Process -FilePath certutil.exe -ArgumentList '-f','-verifyCTL','AuthRoot' -Wait -PassThru -WindowStyle Hidden).ExitCode
    $rc3 = (Start-Process -FilePath certutil.exe -ArgumentList '-syncWithWU' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc1 -eq 0 -and $rc2 -eq 0 -and $rc3 -eq 0) {
        Write-Log -Level INFO -Message 'Certificate synchronization completed.'
    } else {
        Write-Log -Level WARN -Message "Certificate synchronization completed with warnings (rc setreg=$rc1, verifyCTL=$rc2, syncWithWU=$rc3)."
    }
}

# ==================== Network / AD ====================
function Invoke-KerberosPurgeAllSessions {
    [void](Invoke-CapturedCommand -CommandLine "$env:windir\System32\klist.exe -li 0x3e7 purge" -Title 'KLIST PURGE (SYSTEM 0x3e7)')
    [void](Invoke-CapturedCommand -CommandLine "$env:windir\System32\klist.exe purge" -Title 'KLIST PURGE (Current Session)')

    $count = 0
    try {
        $sessions = & "$env:windir\System32\klist.exe" sessions 2>$null
        foreach ($line in $sessions) {
            if ($line -match '^\s*Session ID\s*:\s*(.+)$') {
                $sess = $Matches[1].Trim()
                if ($sess) {
                    [void](Invoke-CapturedCommand -CommandLine "$env:windir\System32\klist.exe -li $sess purge" -Title "KLIST PURGE (Session $sess)")
                    $count++
                }
            }
        }
    } catch {}
    Write-Log -Level INFO -Message "Additional sessions processed for purge: $count"
}

function Invoke-RedeAd {
    param([Parameter(Mandatory)][string]$DomainForNltest)
    if (-not $RunAdNetworkChecks) { return }

    Write-Log -Level INFO -Message "Validating domain controller '$DomainForNltest'..."
    [void](Invoke-LoggedCommand -CommandLine "nltest /dsgetdc:$DomainForNltest" -Title 'NLTEST /DSGETDC')

    Write-Log -Level INFO -Message 'Resynchronizing time with the domain controller...'
    [void](Invoke-LoggedCommand -CommandLine 'w32tm /resync' -Title 'W32TM /RESYNC')

    Write-Log -Level INFO -Message 'Purging Kerberos tickets from all sessions...'
    Invoke-KerberosPurgeAllSessions
}

# ==================== Policies ====================
function Invoke-GpupdateComputerOnly {
    $result = Invoke-CapturedCommand -CommandLine "gpupdate /target:computer /force /wait:$GroupPolicyUpdateWaitSeconds" -Title "GPUPDATE COMPUTER (/wait:$GroupPolicyUpdateWaitSeconds)" -TimeoutSec ($GroupPolicyUpdateWaitSeconds + 10)
    if ($result.ExitCode -ne 0) {
        Write-Log -Level WARN -Message "GPUPDATE (computer) did not complete within the expected time (rc=$($result.ExitCode)). Enabling synchronous processing at the next startup."
        [void](Invoke-CapturedCommand -CommandLine 'reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v SyncForegroundPolicy /t REG_DWORD /d 1 /f' -Title 'Enable SyncForegroundPolicy')
    }
}

function Invoke-Policies {
    if ($RunCertutilPulse) {
        Write-Log -Level INFO -Message 'Refreshing the internal CA chain (certutil -pulse)...'
        [void](Invoke-LoggedCommand -CommandLine 'certutil -pulse' -Title 'CERTUTIL -PULSE')
    }
    if ($RunGpupdateComputerOnly) {
        Write-Log -Level INFO -Message 'Running gpupdate for computer policy with a short wait...'
        Invoke-GpupdateComputerOnly
    } else {
        Write-Log -Level INFO -Message 'Computer gpupdate is DISABLED by configuration.'
    }
}

# ==================== Perfis ====================
function Remove-DatAvatarFiles {
    $path = 'C:\ProgramData\Microsoft\User Account Pictures'
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log -Level INFO -Message "Default avatar folder not found: $path"
        return
    }
    Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue | Where-Object Extension -eq '.dat' | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
            Write-Log -Level INFO -Message ".dat file removed: $($_.Name)"
        } catch {}
    }
}

function Set-DefaultUserImage {
    if (-not $SetDefaultUserPicture) { return }
    if (-not (Test-Path -LiteralPath $DefaultUserImagePath)) {
        Write-Log -Level WARN -Message "Default image NOT found: $DefaultUserImagePath"
        return
    }
    try {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'UseDefaultTile' -PropertyType DWord -Value 1 -Force | Out-Null
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\DefaultUser' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\DefaultUser' -Name 'Image' -PropertyType String -Value $DefaultUserImagePath -Force | Out-Null
        Write-Log -Level INFO -Message "Default image configured: $DefaultUserImagePath"
    } catch {
        Write-Log -Level WARN -Message "Failed to configure the default image - $($_.Exception.Message)"
    }
}

function Reset-ExistingAvatars {
    try {
        Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $u = $_.Name.ToLowerInvariant()
            if ($u -notin @('default','default user','public','all users') -and $u -notmatch 'defaultapp|administrator|administrador') {
                $accPics = Join-Path $_.FullName 'AppData\Roaming\Microsoft\Windows\AccountPictures'
                if (Test-Path -LiteralPath $accPics) {
                    try {
                        Remove-Item -LiteralPath $accPics -Recurse -Force -ErrorAction Stop
                        Write-Log -Level INFO -Message "Avatar cache removed: $accPics"
                    } catch {}
                }
            }
            if ($_.Name.EndsWith('.bak')) {
                Write-Log -Level WARN -Message "A .bak profile entry was detected: $($_.Name)"
            }
        }
    } catch {}

    try {
        Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | ForEach-Object {
            $sid = Split-Path $_.Name -Leaf
            if ($sid -like 'S-1-5-21-*' -and $sid -notlike '*_Classes') {
                $path = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\AccountPicture\Users"
                if (Test-Path -LiteralPath $path) {
                    try {
                        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
                        Write-Log -Level INFO -Message "Avatar registry key removed for SID: $sid"
                    } catch {}
                }
            }
        }
    } catch {}

    Remove-DatAvatarFiles
}

function Invoke-ProfileMaintenance {
    if (-not $HandleUserProfiles) { return }
    Reset-ExistingAvatars
    Set-DefaultUserImage
}

# ==================== Log retention ====================
function Invoke-LogsRetention {
    $root = $LogRetentionPath
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Log -Level INFO -Message "Log-retention folder not found: $root"
        return
    }

    $cutoff = (Get-Date).AddDays(-$LogRetentionDays)
    $removedFiles = 0
    $ignoredFiles = 0
    $failedFiles = 0
    $removedDirs = 0
    $failedDirs = 0

    Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.FullName -ieq $LogFile) { $ignoredFiles++; return }
        if ($_.LastWriteTime -lt $cutoff) {
            try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                $removedFiles++
            } catch {
                $failedFiles++
            }
        } else {
            $ignoredFiles++
        }
    }

    Get-ChildItem -LiteralPath $root -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            try {
                if ($_.FullName -and -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop
                    $removedDirs++
                }
            } catch {
                $failedDirs++
            }
        }

    Write-Log -Level INFO -Message "Retention cleanup with $LogRetentionDays day(s) completed in '$root'. Files removed: $removedFiles | Files skipped: $ignoredFiles | File failures: $failedFiles | Folders removed: $removedDirs | Folder failures: $failedDirs"
}

# ==================== Infra ====================
function Invoke-Infrastructure {
    if ($RestartSpooler) {
        Write-Log -Level INFO -Message 'Restarting the Print Spooler...'
        try {
            Stop-Service -Name spooler -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Start-Service -Name spooler -ErrorAction SilentlyContinue
        } catch {}
    }

    if ($CleanUserTemp) {
        Write-Log -Level INFO -Message 'Cleaning %TEMP% for the current process context (best effort)...'
        try {
            Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    Invoke-LogsRetention

    Write-Log -Level INFO -Message 'Basic inventory:'
    [void](Invoke-LoggedCommand -CommandLine 'hostname' -Title 'HOSTNAME')
    [void](Invoke-LoggedCommand -CommandLine 'whoami' -Title 'WHOAMI')
    [void](Invoke-LoggedCommand -CommandLine 'ipconfig | findstr /i IPv4' -Title 'IPCONFIG (IPv4)')
}

function Invoke-NetworkSummary {
    param(
        [Parameter(Mandatory)][string]$Fqdn,
        [Parameter(Mandatory)][string]$NetBIOS
    )
    Write-Log -Level INFO -Message '===== NETWORK SUMMARY ====='
    Write-Log -Level INFO -Message "Detected domain FQDN: $Fqdn"
    Write-Log -Level INFO -Message "Domain NetBIOS name: $NetBIOS"

    $r = Invoke-CapturedCommand -CommandLine "nltest /dsgetdc:$NetBIOS" -Title 'NLTEST /DSGETDC (NetBIOS)'
    if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "NLTEST (NetBIOS) failed with exit code $($r.ExitCode)." }

    if ($Fqdn -ne 'WORKGROUP' -and $Fqdn.Contains('.')) {
        $r = Invoke-CapturedCommand -CommandLine "nltest /dsgetdc:$Fqdn" -Title 'NLTEST /DSGETDC (FQDN)'
        if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "NLTEST (FQDN) failed with exit code $($r.ExitCode)." }
    }

    $r = Invoke-CapturedCommand -CommandLine 'w32tm /query /status' -Title 'W32TM STATUS'
    if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "W32TM STATUS failed with exit code $($r.ExitCode)." }
    Write-Log -Level INFO -Message '===== END NETWORK SUMMARY ====='
}

# ==================== Sessions / notifications ====================
function Convert-IdleStringToMinutes {
    param([string]$IdleString)

    if ([string]::IsNullOrWhiteSpace($IdleString)) { return 0 }

    $value = $IdleString.Trim()
    if ($value -match '^(none|nenhum|nunca|\.)$') { return 0 }
    if ($value -match '^\d+$') { return [int]$value }
    if ($value -match '^(?<Days>\d+)\+(?<Hours>\d{1,2}):(?<Minutes>\d{2})$') {
        return ([int]$Matches.Days * 1440) + ([int]$Matches.Hours * 60) + [int]$Matches.Minutes
    }
    if ($value -match '^(?<Hours>\d{1,2}):(?<Minutes>\d{2})$') {
        return ([int]$Matches.Hours * 60) + [int]$Matches.Minutes
    }
    return 0
}

function Get-LoggedOnSessions {
    $result = [ordered]@{
        QueryOk     = $false
        ParseOk     = $false
        HasActive   = $false
        ActiveCount = 0
        ActiveUsers = @()
        Sessions    = @()
        RawOut      = ''
        RawErr      = ''
        ExitCode    = 1
        Reason      = ''
    }

    try {
        $cmd = Invoke-CapturedCommand -CommandLine 'quser' -Title 'QUERY USER (RAW)'
        $result.RawOut   = $cmd.StdOut
        $result.RawErr   = $cmd.StdErr
        $result.ExitCode = $cmd.ExitCode

        $allLines = @()
        if (-not [string]::IsNullOrWhiteSpace($cmd.StdOut)) {
            $result.QueryOk = $true
            $allLines += ($cmd.StdOut -split "`r?`n")
        }
        if (-not [string]::IsNullOrWhiteSpace($cmd.StdErr)) {
            $allLines += ($cmd.StdErr -split "`r?`n")
        }
        $allLines = @($allLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $combinedSessionOutput = (($cmd.StdOut + "`r`n" + $cmd.StdErr) -replace "`0", '')
        if ($combinedSessionOutput -match '(?i)(n\u00E3o existe nenhum usu\u00E1rio|nao existe nenhum usuario|no user exists|no users exist)') {
            # Valid condition on a workstation with no signed-in user.
            $result.QueryOk = $true
            $result.ParseOk = $true
            $result.Reason  = 'No user session is present.'
            if ($cmd.StdErr) {
                Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd()
            }
            Write-Log -Level INFO -Message 'QUSER reported no signed-in users. Interpreted as no active session.'
            return [pscustomobject]$result
        }

        if (-not $result.QueryOk) {
            $result.Reason = 'QUSER did not return usable standard output.'
            if ($cmd.StdErr) {
                Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd()
            }
            return [pscustomobject]$result
        }

        foreach ($line in $allLines) {
            if ($line -match 'USERNAME\s+SESSIONNAME\s+ID\s+STATE') { continue }

            $normalized = $line.TrimStart('>',' ').TrimEnd()
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

            $match = [regex]::Match(
                $normalized,
                '^(?<User>\S+)\s+(?<SessionName>\S+|)\s+(?<Id>\d+)\s+(?<State>Active|Ativo|Disc|Disconnected|Descon|Conn)\s+(?<Idle>\S+)\s+(?<Logon>.+)$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )

            if (-not $match.Success) { continue }

            $stateText = $match.Groups['State'].Value
            $isActive  = $stateText -match '^(Active|Ativo)$'
            $idleText  = $match.Groups['Idle'].Value
            $idleMins  = Convert-IdleStringToMinutes -IdleString $idleText

            $obj = [pscustomobject]@{
                UserName    = $match.Groups['User'].Value
                SessionName = $match.Groups['SessionName'].Value.Trim()
                SessionId   = [int]$match.Groups['Id'].Value
                State       = $stateText
                IsActive    = $isActive
                IdleText    = $idleText
                IdleMinutes = $idleMins
                LogonTime   = $match.Groups['Logon'].Value.Trim()
                RawLine     = $line
            }

            $result.Sessions += $obj
            if ($isActive) {
                $result.ActiveUsers += $obj.UserName
            }
        }

        if ($result.Sessions.Count -gt 0) {
            $result.ParseOk = $true
        } else {
            $result.Reason = 'Unable to interpret QUSER output.'
        }

        if ($result.ActiveUsers.Count -gt 0) {
            $result.HasActive = $true
            $result.ActiveCount = @($result.ActiveUsers | Sort-Object -Unique).Count
            Write-LogSection -Title 'QUERY USER (ACTIVE MATCH)' -Body $cmd.StdOut.TrimEnd()
        } elseif ($cmd.StdOut) {
            Write-LogSection -Title 'QUERY USER (STDOUT)' -Body $cmd.StdOut.TrimEnd()
        }

        if ($cmd.ExitCode -ne 0 -and -not $result.ParseOk) {
            Write-Log -Level WARN -Message "'query user' returned exit code $($cmd.ExitCode) without reliable output interpretation."
            if ($cmd.StdErr) { Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd() }
        } elseif ($cmd.ExitCode -ne 0) {
            Write-Log -Level WARN -Message "'query user' returned exit code $($cmd.ExitCode), but usable output was returned; continuing with result interpretation."
            if ($cmd.StdErr) { Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd() }
        }
    } catch {
        $result.Reason = $_.Exception.Message
        Write-Log -Level WARN -Message "Failed to run 'query user': $($_.Exception.Message)"
    }

    [pscustomobject]$result
}

function Get-RebootDecision {
    param([int]$IdleThresholdMinutes = 90)

    $sessionInfo = Get-LoggedOnSessions

    if (-not $sessionInfo.QueryOk -or -not $sessionInfo.ParseOk) {
        $reason = if ($sessionInfo.Reason) { $sessionInfo.Reason } else { 'Session detection failed.' }
        Write-Log -Level WARN -Message "Restart policy: user-session query or interpretation failed. The failure is audited only; the mandatory restart remains authorized. Reason: $reason"
        return [pscustomobject]@{
            AllowReboot = $true
            Reason      = $reason
            ActiveUsers = @()
            Sessions    = @()
        }
    }

    $activeSessions = @($sessionInfo.Sessions | Where-Object { $_.IsActive })

    if ($activeSessions.Count -eq 0) {
        Write-Log -Level INFO -Message 'Restart policy: no active session detected. Restart authorized.'
        return [pscustomobject]@{
            AllowReboot = $true
            Reason      = 'No active session'
            ActiveUsers = @()
            Sessions    = @()
        }
    }

    foreach ($session in $activeSessions) {
        Write-Log -Level INFO -Message ("Active session detected: User='{0}', Session='{1}', ID={2}, State='{3}', Idle='{4}', IdleMinutes={5}" -f `
            $session.UserName, $session.SessionName, $session.SessionId, $session.State, $session.IdleText, $session.IdleMinutes)
    }

    $blockingSessions = @($activeSessions | Where-Object { $_.IdleMinutes -lt $IdleThresholdMinutes })
    if ($blockingSessions.Count -gt 0) {
        $users = ($blockingSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
        Write-Log -Level WARN -Message ("Restart policy: active sessions exist below the idle threshold ({0} min). The condition is recorded but does not block the mandatory restart. User(s): {1}" -f $IdleThresholdMinutes, $users)
        return [pscustomobject]@{
            AllowReboot = $true
            Reason      = "Mandatory restart despite an active session below ${IdleThresholdMinutes} min"
            ActiveUsers = @($blockingSessions)
            Sessions    = @($activeSessions)
        }
    }

    $users2 = ($activeSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
    Write-Log -Level INFO -Message ("Restart policy: all active sessions have been idle for at least {0} minute(s). Restart authorized. User(s): {1}" -f $IdleThresholdMinutes, $users2)
    return [pscustomobject]@{
        AllowReboot = $true
        Reason      = "All active sessions are idle >= ${IdleThresholdMinutes} min"
        ActiveUsers = @($activeSessions)
        Sessions    = @($activeSessions)
    }
}

function Send-MessageToSession {
    param(
        [Parameter(Mandatory)][int]$SessionId,
        [Parameter(Mandatory)][string]$Message
    )
    try {
        $p = Start-Process -FilePath msg.exe -ArgumentList $SessionId, $Message -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return $p.ExitCode
    } catch {
        return -1
    }
}

function Send-MessageToAllSessions {
    param([Parameter(Mandatory)][string]$Message)
    try {
        $p = Start-Process -FilePath msg.exe -ArgumentList '*', $Message -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        return $p.ExitCode
    } catch {
        return -1
    }
}

function Build-DeferredRestartMessage {
    param(
        [string[]]$Users,
        [int]$IdleThresholdMinutes = 90
    )
    $usersText = if ($Users -and $Users.Count -gt 0) { ($Users | Sort-Object -Unique) -join ', ' } else { 'signed-in user' }
    return @"
Maintenance has completed on this workstation.
An active session is in use by: $usersText.
The weekly restart is mandatory and will not be deferred because of session state or idle time.
Save your work immediately. The workstation will restart automatically during the configured maintenance window.
"@
}

function Ensure-StateStore {
    try {
        if (-not (Test-Path -LiteralPath $script:StateRoot)) {
            New-Item -Path $script:StateRoot -ItemType Directory -Force | Out-Null
        }
        return $true
    } catch {
        Write-Log -Level WARN -Message "Failed to prepare the state directory '$script:StateRoot': $($_.Exception.Message)"
        return $false
    }
}

function Get-RestartState {
    $default = [ordered]@{
        DeferredCount     = 0
        LastDecision      = ''
        LastReason        = ''
        LastRunTime       = ''
        LastActiveUsers   = @()
    }
    try {
        if (-not (Test-Path -LiteralPath $script:StateFilePath)) {
            return [pscustomobject]$default
        }
        $raw = Get-Content -LiteralPath $script:StateFilePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$default
        }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            DeferredCount   = [int]($obj.DeferredCount)
            LastDecision    = [string]$obj.LastDecision
            LastReason      = [string]$obj.LastReason
            LastRunTime     = [string]$obj.LastRunTime
            LastActiveUsers = @($obj.LastActiveUsers)
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to read persistent restart state: $($_.Exception.Message)"
        return [pscustomobject]$default
    }
}

function Save-RestartState {
    param(
        [int]$DeferredCount,
        [string]$LastDecision,
        [string]$LastReason,
        [string[]]$LastActiveUsers = @()
    )
    try {
        if (Ensure-StateStore) {
            $payload = [ordered]@{
                DeferredCount   = $DeferredCount
                LastDecision    = $LastDecision
                LastReason      = $LastReason
                LastRunTime     = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                LastActiveUsers = @($LastActiveUsers | Sort-Object -Unique)
            } | ConvertTo-Json -Depth 4
            Set-Content -LiteralPath $script:StateFilePath -Value $payload -Encoding UTF8 -Force
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to write persistent restart state: $($_.Exception.Message)"
    }
}

function Reset-RestartState {
    Save-RestartState -DeferredCount 0 -LastDecision 'Authorized' -LastReason 'Restart authorized' -LastActiveUsers @()
}


function Get-SystemBootTimeSafe {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return ([Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime))
    } catch {
        try {
            # PowerShell 5.1 may run on .NET Framework versions where TickCount64 is not available.
            # TickCount is used only as a best-effort fallback and must never break runtime governance.
            return (Get-Date).AddMilliseconds(-[Environment]::TickCount)
        } catch {
            return $null
        }
    }
}

function ConvertTo-StateDateTime {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) { return $null }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $formats = @(
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-ddTHH:mm:ss',
        'yyyy-MM-ddTHH:mm:ss.fffffffK',
        'yyyy-MM-ddTHH:mm:ssK'
    )

    foreach ($format in $formats) {
        try {
            return [datetime]::ParseExact(
                $text,
                $format,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeLocal
            )
        } catch {
        }
    }

    try {
        return [datetime]::Parse(
            $text,
            [System.Globalization.CultureInfo]::CurrentCulture,
            [System.Globalization.DateTimeStyles]::AssumeLocal
        )
    } catch {
        try {
            return [datetime]::Parse(
                $text,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeLocal
            )
        } catch {
            Write-Log -Level WARN -Message "Runtime governance could not convert the state date/time value. Value='$text'."
            return $null
        }
    }
}

function Get-GovernanceState {
    $default = [ordered]@{
        RuntimeState                 = 'UNKNOWN'
        ExecutionLock                = $false
        ExecutionLockOwnerPid         = $null
        ExecutionLockStartedAt        = $null
        ExecutionLockExpiresAt        = $null
        RebootScheduled              = $false
        AwaitingRestart              = $false
        ShutdownIssuedAt             = $null
        ShutdownTimeoutSeconds       = 0
        ShutdownExitCode             = $null
        ShutdownIssuedBootTime       = $null
        LastDomainHealth             = 'UNKNOWN'
        LastDomainGateReason         = ''
        LastUpdated                  = $null
    }
    try {
        if (-not (Test-Path -LiteralPath $script:GovernanceStateFile)) {
            return [pscustomobject]$default
        }
        $raw = Get-Content -LiteralPath $script:GovernanceStateFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$default
        }
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($key in @($default.Keys)) {
            if ($null -eq $obj.PSObject.Properties[$key]) {
                Add-Member -InputObject $obj -NotePropertyName $key -NotePropertyValue $default[$key] -Force
            }
        }
        return $obj
    } catch {
        Write-Log -Level WARN -Message "Failed to read runtime governance state: $($_.Exception.Message)"
        return [pscustomobject]$default
    }
}

function Save-GovernanceState {
    param([hashtable]$Patch)
    try {
        Ensure-StateStore | Out-Null
        $state = Get-GovernanceState
        $ordered = [ordered]@{}
        foreach ($p in $state.PSObject.Properties) { $ordered[$p.Name] = $p.Value }
        foreach ($key in $Patch.Keys) { $ordered[$key] = $Patch[$key] }
        $ordered['LastUpdated'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $json = $ordered | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $script:GovernanceStateFile -Value $json -Encoding UTF8 -Force
    } catch {
        Write-Log -Level WARN -Message "Failed to write runtime governance state: $($_.Exception.Message)"
    }
}

function Clear-GovernanceRuntimeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuntimeState,
        [Parameter(Mandatory)][string]$Reason
    )

    Write-Log -Level INFO -Message "Runtime governance: clearing pending state. RuntimeState='$RuntimeState'; Reason='$Reason'."
    Save-GovernanceState -Patch @{
        RuntimeState           = $RuntimeState
        RebootScheduled        = $false
        AwaitingRestart        = $false
        ExecutionLock          = $false
        ExecutionLockOwnerPid  = $null
        ExecutionLockStartedAt = $null
        ExecutionLockExpiresAt = $null
    }
}

function Repair-StaleGovernanceState {
    [CmdletBinding()]
    param()

    $state = Get-GovernanceState
    $now = Get-Date
    $currentBoot = Get-SystemBootTimeSafe
    $storedBoot = ConvertTo-StateDateTime -Value $state.ShutdownIssuedBootTime
    $issuedAt = ConvertTo-StateDateTime -Value $state.ShutdownIssuedAt
    $lockExpiresAt = ConvertTo-StateDateTime -Value $state.ExecutionLockExpiresAt

    if ([bool]$state.AwaitingRestart) {
        if ($currentBoot -and $storedBoot -and ($currentBoot -gt $storedBoot.AddSeconds(30))) {
            Clear-GovernanceRuntimeState -RuntimeState 'POST_REBOOT_CONFIRMED_BY_BOOT_TIME' -Reason "Current boot time is later than the boot time saved when shutdown was issued. CurrentBoot='$currentBoot'; ShutdownIssuedBootTime='$storedBoot'."
            Save-MaintenanceState -Patch @{
                PendingReboot        = $false
                PendingRebootReasons = @()
                RestartScheduled     = $false
                RestartCompleted     = $true
                Compliance           = 'COMPLIANT'
                LastOutcome          = 'POST_REBOOT_CONFIRMED_BY_BOOT_TIME'
            }
            return [pscustomobject]@{ Cleared = $true; StillWaiting = $false; Reason = 'Restart confirmed by ShutdownIssuedBootTime.' }
        }

        if ($currentBoot -and $issuedAt -and ($currentBoot -gt $issuedAt.AddSeconds(30))) {
            Clear-GovernanceRuntimeState -RuntimeState 'POST_REBOOT_CONFIRMED_BY_ISSUED_AT' -Reason "Current boot time is later than the time shutdown was issued. CurrentBoot='$currentBoot'; ShutdownIssuedAt='$issuedAt'."
            Save-MaintenanceState -Patch @{
                PendingReboot        = $false
                PendingRebootReasons = @()
                RestartScheduled     = $false
                RestartCompleted     = $true
                Compliance           = 'COMPLIANT'
                LastOutcome          = 'POST_REBOOT_CONFIRMED_BY_ISSUED_AT'
            }
            return [pscustomobject]@{ Cleared = $true; StillWaiting = $false; Reason = 'Restart confirmed by ShutdownIssuedAt.' }
        }

        if ($issuedAt -and ($now -gt $issuedAt.AddMinutes($script:RebootAwaitMinutes))) {
            Clear-GovernanceRuntimeState -RuntimeState 'REBOOT_WAIT_EXPIRED_CLEARED' -Reason "AwaitingRestart expired without reliable evidence of a restart. IssuedAt='$issuedAt'; LimitMinutes=$script:RebootAwaitMinutes."
            return [pscustomobject]@{ Cleared = $true; StillWaiting = $false; Reason = 'Restart wait window expired.' }
        }

        if ($lockExpiresAt -and ($now -gt $lockExpiresAt)) {
            Clear-GovernanceRuntimeState -RuntimeState 'EXPIRED_REBOOT_LOCK_CLEARED' -Reason "ExecutionLock associated with AwaitingRestart expired. ExpiresAt='$lockExpiresAt'."
            return [pscustomobject]@{ Cleared = $true; StillWaiting = $false; Reason = 'Restart lock expired.' }
        }

        Write-Log -Level WARN -Message "Restart governance: a restart is already pending or scheduled by this runtime. The new run will exit to prevent stacked shutdown.exe requests. ShutdownIssuedAt='$($state.ShutdownIssuedAt)' Timeout='$($state.ShutdownTimeoutSeconds)s'."
        return [pscustomobject]@{ Cleared = $false; StillWaiting = $true; Reason = 'AwaitingRestart ainda vigente.' }
    }

    if ([bool]$state.ExecutionLock -and $lockExpiresAt -and ($now -gt $lockExpiresAt)) {
        Clear-GovernanceRuntimeState -RuntimeState 'STALE_EXECUTION_LOCK_CLEARED' -Reason "ExecutionLock expired without an active AwaitingRestart state. ExpiresAt='$lockExpiresAt'."
        return [pscustomobject]@{ Cleared = $true; StillWaiting = $false; Reason = 'Expired execution lock cleared.' }
    }

    return [pscustomobject]@{ Cleared = $false; StillWaiting = $false; Reason = 'No stale state detected.' }
}

function Test-AwaitingRestartLock {
    $repair = Repair-StaleGovernanceState
    return [bool]$repair.StillWaiting
}

function Acquire-ExecutionLock {
    $state = Get-GovernanceState
    if ([bool]$state.ExecutionLock) {
        $expiresAt = ConvertTo-StateDateTime -Value $state.ExecutionLockExpiresAt
        if ($expiresAt -and (Get-Date) -lt $expiresAt) {
            Write-Log -Level WARN -Message "Execution governance: active lock detected. OwnerPid='$($state.ExecutionLockOwnerPid)' StartedAt='$($state.ExecutionLockStartedAt)' ExpiresAt='$($state.ExecutionLockExpiresAt)'. Exiting to prevent reentrancy."
            return $false
        }
        Write-Log -Level WARN -Message "Execution governance: previous lock is expired or stale and will be replaced."
    }

    $started = Get-Date
    Save-GovernanceState -Patch @{
        RuntimeState = 'CONVERGING'
        ExecutionLock = $true
        ExecutionLockOwnerPid = $PID
        ExecutionLockStartedAt = $started.ToString('yyyy-MM-dd HH:mm:ss')
        ExecutionLockExpiresAt = $started.AddMinutes($script:ExecutionLockMinutes).ToString('yyyy-MM-dd HH:mm:ss')
    }
    Write-Log -Level INFO -Message "Execution governance: lock acquired. PID=$PID; ExpiresInMinutes=$script:ExecutionLockMinutes."
    return $true
}

function Release-ExecutionLock {
    param([string]$RuntimeState = 'COMPLETED')
    $state = Get-GovernanceState
    if ([bool]$state.AwaitingRestart) {
        Write-Log -Level INFO -Message 'Execution governance: lock will not be cleared because AwaitingRestart=True.'
        return
    }
    Save-GovernanceState -Patch @{
        RuntimeState = $RuntimeState
        ExecutionLock = $false
        ExecutionLockOwnerPid = $null
        ExecutionLockStartedAt = $null
        ExecutionLockExpiresAt = $null
    }
    Write-Log -Level INFO -Message "Execution governance: lock released. RuntimeState='$RuntimeState'."
}

function Set-RebootScheduledLock {
    param(
        [int]$ShutdownTimeoutSeconds,
        [int]$ShutdownExitCode
    )
    $boot = Get-SystemBootTimeSafe
    Save-GovernanceState -Patch @{
        RuntimeState = 'WAITING_REBOOT'
        RebootScheduled = $true
        AwaitingRestart = $true
        ShutdownIssuedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ShutdownTimeoutSeconds = $ShutdownTimeoutSeconds
        ShutdownExitCode = $ShutdownExitCode
        ShutdownIssuedBootTime = if ($boot) { $boot.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        ExecutionLock = $true
        ExecutionLockOwnerPid = $PID
        ExecutionLockStartedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        ExecutionLockExpiresAt = (Get-Date).AddMinutes($script:RebootAwaitMinutes).ToString('yyyy-MM-dd HH:mm:ss')
    }
}


function Get-MaintenanceState {
    $default = [ordered]@{
        FrameworkVersion        = $ScriptVersion
        MaintenanceWindow       = ("{0} {1}" -f $script:MaintenanceWindow.Day, $script:MaintenanceWindow.InstallTime)
        RestartWindow           = ("{0} {1}" -f $script:MaintenanceWindow.Day, $script:MaintenanceWindow.RestartTime)
        LastRunStartedAt        = $null
        LastRunCompletedAt      = $null
        UpdatesInstalled        = $null
        UpdateManagementState   = 'UNKNOWN'
        WindowsUpdatePolicy     = $null
        PendingReboot           = $false
        PendingRebootReasons    = @()
        RestartScheduled        = $false
        RestartCompleted        = $false
        DomainHealth            = 'UNKNOWN'
        DomainHealthReason      = ''
        Compliance              = 'UNKNOWN'
        LastOutcome             = ''
        LastUpdated             = $null
    }

    try {
        if (-not (Test-Path -LiteralPath $script:MaintenanceStateFile)) {
            return [pscustomobject]$default
        }

        $raw = Get-Content -LiteralPath $script:MaintenanceStateFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return [pscustomobject]$default
        }

        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($key in @($default.Keys)) {
            if ($null -eq $obj.PSObject.Properties[$key]) {
                Add-Member -InputObject $obj -NotePropertyName $key -NotePropertyValue $default[$key] -Force
            }
        }
        return $obj
    } catch {
        Write-Log -Level WARN -Message "Failed to read maintenance-state.json: $($_.Exception.Message)"
        return [pscustomobject]$default
    }
}

function Save-MaintenanceState {
    param([hashtable]$Patch)

    try {
        Ensure-StateStore | Out-Null
        $state = Get-MaintenanceState
        $ordered = [ordered]@{}
        # Remove obsolete metadata that coupled the framework to a named WSUS baseline or GPO.
        $legacyFields = @('WsusBaseline', 'WsusPolicyHealth', 'WsusPolicySnapshot')
        foreach ($p in $state.PSObject.Properties) {
            if ($legacyFields -notcontains $p.Name) {
                $ordered[$p.Name] = $p.Value
            }
        }

        $ordered['FrameworkVersion']  = $ScriptVersion
        $ordered['MaintenanceWindow'] = ("{0} {1}" -f $script:MaintenanceWindow.Day, $script:MaintenanceWindow.InstallTime)
        $ordered['RestartWindow']     = ("{0} {1}" -f $script:MaintenanceWindow.Day, $script:MaintenanceWindow.RestartTime)

        foreach ($key in $Patch.Keys) { $ordered[$key] = $Patch[$key] }
        $ordered['LastUpdated'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

        $json = $ordered | ConvertTo-Json -Depth 8
        $tempPath = "$($script:MaintenanceStateFile).tmp"
        Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8 -Force
        Move-Item -LiteralPath $tempPath -Destination $script:MaintenanceStateFile -Force
    } catch {
        Write-Log -Level WARN -Message "Failed to write maintenance-state.json: $($_.Exception.Message)"
    }
}


function Get-WindowsUpdatePolicyState {
    [CmdletBinding()]
    param()

    $wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auPath = Join-Path $wuPath 'AU'

    $state = [ordered]@{
        PolicyPath                = $wuPath
        PolicyDetected            = $false
        Managed                   = $false
        SourceType                = 'NONE'
        UpdateManagementState     = 'WINDOWS_UPDATE_POLICY_NOT_DETECTED'

        WUServer                  = $null
        WUStatusServer            = $null
        TargetGroup               = $null
        TargetGroupEnabled        = $null
        UseWUServer               = $null

        NoAutoUpdate              = $null
        AUOptions                 = $null
        SetDisableUXWUAccess      = $null
        DoNotConnectToWindowsUpdateInternetLocations = $null
        DisableWindowsUpdateAccess = $null
        TargetReleaseVersion      = $null
        TargetReleaseVersionInfo  = $null
        ProductVersion            = $null
        DeferFeatureUpdates       = $null
        DeferFeatureUpdatesPeriodInDays = $null
        DeferQualityUpdates       = $null
        DeferQualityUpdatesPeriodInDays = $null

        Observation               = ''
    }

    try {
        $wuExists = Test-Path -LiteralPath $wuPath
        $auExists = Test-Path -LiteralPath $auPath

        if ($wuExists) {
            $state.PolicyDetected = $true
            $wu = Get-ItemProperty -LiteralPath $wuPath -ErrorAction Stop

            foreach ($name in @(
                'WUServer',
                'WUStatusServer',
                'TargetGroup',
                'TargetGroupEnabled',
                'SetDisableUXWUAccess',
                'DoNotConnectToWindowsUpdateInternetLocations',
                'DisableWindowsUpdateAccess',
                'TargetReleaseVersion',
                'TargetReleaseVersionInfo',
                'ProductVersion',
                'DeferFeatureUpdates',
                'DeferFeatureUpdatesPeriodInDays',
                'DeferQualityUpdates',
                'DeferQualityUpdatesPeriodInDays'
            )) {
                if ($null -ne $wu.PSObject.Properties[$name]) {
                    $state[$name] = $wu.$name
                }
            }
        }

        if ($auExists) {
            $state.PolicyDetected = $true
            $au = Get-ItemProperty -LiteralPath $auPath -ErrorAction Stop

            foreach ($name in @('UseWUServer', 'NoAutoUpdate', 'AUOptions')) {
                if ($null -ne $au.PSObject.Properties[$name]) {
                    $state[$name] = $au.$name
                }
            }
        }

        $isWsus = (
            $null -ne $state.UseWUServer -and
            [int]$state.UseWUServer -eq 1 -and
            -not [string]::IsNullOrWhiteSpace([string]$state.WUServer)
        )

        if ($isWsus) {
            $state.Managed = $true
            $state.SourceType = 'WSUS'
            $state.UpdateManagementState = 'MANAGED_BY_WSUS'
            $state.Observation = 'Effective policy points to WSUS. No specific GPO or baseline is assumed by the script.'
        }
        elseif ($state.PolicyDetected) {
            $state.Managed = $true
            $state.SourceType = 'WINDOWS_UPDATE_POLICY'
            $state.UpdateManagementState = 'MANAGED_BY_WINDOWS_UPDATE_POLICY'
            $state.Observation = 'Effective Windows Update policy detected without assuming a named GPO, TargetGroup, or specific baseline.'
        }
        else {
            $state.Managed = $false
            $state.SourceType = 'NONE'
            $state.UpdateManagementState = 'WINDOWS_UPDATE_POLICY_NOT_DETECTED'
            $state.Observation = 'No administrative Windows Update policy was detected in the evaluated paths.'
        }
    }
    catch {
        $state.Managed = $false
        $state.SourceType = 'UNKNOWN'
        $state.UpdateManagementState = 'WINDOWS_UPDATE_POLICY_QUERY_FAILED'
        $state.Observation = "Failed to query effective Windows Update policy: $($_.Exception.Message)"
    }

    [pscustomobject]$state
}

function Get-UpdatesInstalledSince {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Since
    )

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()

        if ($total -le 0) {
            return [pscustomobject]@{ Count = 0; Titles = @(); QueryOk = $true }
        }

        $history = @($searcher.QueryHistory(0, $total) | Where-Object {
            $_.Date -ge $Since -and
            $_.Operation -eq 1 -and
            ($_.ResultCode -eq 2 -or $_.ResultCode -eq 3)
        })

        return [pscustomobject]@{
            Count   = $history.Count
            Titles  = @($history | Select-Object -ExpandProperty Title)
            QueryOk = $true
        }
    } catch {
        Write-Log -Level WARN -Message "Unable to query Windows Update history: $($_.Exception.Message)"
        return [pscustomobject]@{ Count = 0; Titles = @(); QueryOk = $false }
    }
}

function Test-PendingReboot {
    [CmdletBinding()]
    param()

    $reasons = New-Object System.Collections.Generic.List[string]

    try {
        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
            $reasons.Add('CBS:RebootPending')
        }
    } catch {}

    try {
        if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
            $reasons.Add('WindowsUpdate:RebootRequired')
        }
    } catch {}

    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($sessionManager -and $sessionManager.PendingFileRenameOperations) {
            $reasons.Add('SessionManager:PendingFileRenameOperations')
        }
    } catch {}

    try {
        $volatile = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Updates' -Name UpdateExeVolatile -ErrorAction SilentlyContinue
        if ($volatile -and ([int]$volatile.UpdateExeVolatile -ne 0)) {
            $reasons.Add("MicrosoftUpdates:UpdateExeVolatile=$($volatile.UpdateExeVolatile)")
        }
    } catch {}

    # SCCM/ConfigMgr, when present. Absence is normal and does not affect the result.
    try {
        $ccm = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
        if ($ccm -and ($ccm.RebootPending -or $ccm.IsHardRebootPending)) {
            $reasons.Add('ConfigMgr:RebootPending')
        }
    } catch {}

    $uniqueReasons = @($reasons | Sort-Object -Unique)
    [pscustomobject]@{
        Required = ($uniqueReasons.Count -gt 0)
        Reasons  = $uniqueReasons
    }
}

function Get-RestartDelaySeconds {
    [CmdletBinding()]
    param(
        [int]$MinimumNoticeSeconds = $ShutdownNoticeSeconds
    )

    $now = Get-Date
    $restartTime = [datetime]::MinValue

    if (-not [datetime]::TryParseExact(
        $script:MaintenanceWindow.RestartTime,
        'HH:mm',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$restartTime
    )) {
        return $MinimumNoticeSeconds
    }

    $target = Get-Date -Hour $restartTime.Hour -Minute $restartTime.Minute -Second 0
    if ($target -le $now) {
        return $MinimumNoticeSeconds
    }

    $seconds = [int][math]::Ceiling(($target - $now).TotalSeconds)
    return [math]::Max($MinimumNoticeSeconds, $seconds)
}

function Test-DomainHealthGate {
    param(
        [string]$DomainFqdn,
        [string]$DomainNetBIOS,
        [string]$ComputerDn
    )

    $reasons = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($DomainFqdn) -or $DomainFqdn -eq 'WORKGROUP') {
        $reasons.Add('DomainFQDN=WORKGROUP/empty')
    }

    if ([string]::IsNullOrWhiteSpace($ComputerDn) -or $ComputerDn -eq 'NOT AVAILABLE') {
        $reasons.Add('ComputerDN unavailable')
    }

    if ($DomainFqdn -and $DomainFqdn -ne 'WORKGROUP') {
        # DNS SRV discovery of domain controllers.
        try {
            $srvName = "_ldap._tcp.dc._msdcs.$DomainFqdn"
            $dnsOk = $false
            if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                $srv = @(Resolve-DnsName -Name $srvName -Type SRV -DnsOnly -ErrorAction Stop)
                $dnsOk = ($srv.Count -gt 0)
            } else {
                $ns = Invoke-CapturedCommand -CommandLine "nslookup -type=SRV $srvName" -Title 'DOMAIN GATE - DNS SRV' -TimeoutSec 30
                $dnsOk = ($ns.ExitCode -eq 0 -and $ns.StdOut -match '(?i)service|svr hostname|priority')
            }
            if (-not $dnsOk) { $reasons.Add("DNS SRV discovery failed for '$srvName'") }
        } catch {
            $reasons.Add("DNS SRV discovery failed: $($_.Exception.Message)")
        }

        # DC discovery.
        try {
            $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\nltest.exe') -ArgumentList @('/dsgetdc:' + $DomainFqdn) -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
            if ($p.ExitCode -ne 0) { $reasons.Add("NLTEST /dsgetdc failed rc=$($p.ExitCode)") }
        } catch {
            $reasons.Add("NLTEST /dsgetdc exception: $($_.Exception.Message)")
        }

        # Secure channel / trust.
        try {
            # Test-ComputerSecureChannel already returns Boolean and does not have -Quiet in Windows PowerShell 5.1.
            $secure = Test-ComputerSecureChannel -ErrorAction Stop
            if (-not $secure) { $reasons.Add('Test-ComputerSecureChannel=False') }
        } catch {
            $reasons.Add("SecureChannel exception: $($_.Exception.Message)")
        }

        # Domain time health. A failed query is critical because Kerberos is time-sensitive.
        try {
            $timeResult = Invoke-CapturedCommand -CommandLine 'w32tm /query /status' -Title 'DOMAIN GATE - W32TIME STATUS' -TimeoutSec 30
            if ($timeResult.ExitCode -ne 0) { $reasons.Add("W32TIME status failed rc=$($timeResult.ExitCode)") }
        } catch {
            $reasons.Add("W32TIME exception: $($_.Exception.Message)")
        }

        # Kerberos validation in the current machine/SYSTEM security context.
        try {
            $klistPath = Join-Path $env:SystemRoot 'System32\klist.exe'
            if (Test-Path -LiteralPath $klistPath) {
                $kerb = Invoke-CapturedCommand -CommandLine ('"{0}" get krbtgt/{1}' -f $klistPath, $DomainFqdn) -Title 'DOMAIN GATE - KERBEROS' -TimeoutSec 30
                $kerberosSuccessText = (($kerb.StdOut + "`r`n" + $kerb.StdErr) -match '(?i)(ticket|t.quete).*(success|success|exito|recuperado)')
                if ($kerb.ExitCode -ne 0 -and -not $kerberosSuccessText) {
                    $reasons.Add("Kerberos TGT acquisition failed rc=$($kerb.ExitCode)")
                } elseif ($kerb.ExitCode -ne 0) {
                    Write-Log -Level WARN -Message "Kerberos returned exit code $($kerb.ExitCode), but output confirms TGT acquisition; the result is accepted as healthy."
                }
            } else {
                $reasons.Add('klist.exe unavailable')
            }
        } catch {
            $reasons.Add("Kerberos exception: $($_.Exception.Message)")
        }
    }

    if ($reasons.Count -gt 0) {
        $reason = ($reasons -join '; ')
        Write-Log -Level WARN -Message "DomainHealthGate: domain environment is unhealthy. Only domain-dependent operations will be blocked; the mandatory restart remains armed. Reason='$reason'."
        Save-GovernanceState -Patch @{ LastDomainHealth = 'UNHEALTHY'; LastDomainGateReason = $reason; RuntimeState = 'DOMAIN_BLOCKED' }
        Save-MaintenanceState -Patch @{ DomainHealth = 'UNHEALTHY'; DomainHealthReason = $reason; Compliance = 'DEFERRED'; LastOutcome = 'DOMAIN_HEALTH_FAILED' }
        return [pscustomobject]@{ Healthy = $false; Reason = $reason }
    }

    Write-Log -Level INFO -Message "DomainHealthGate: DNS/DC/SecureChannel/W32Time/Kerberos validados. DomainFQDN='$DomainFqdn'; ComputerDN='$ComputerDn'."
    Save-GovernanceState -Patch @{ LastDomainHealth = 'HEALTHY'; LastDomainGateReason = ''; RuntimeState = 'DOMAIN_HEALTHY' }
    Save-MaintenanceState -Patch @{ DomainHealth = 'HEALTHY'; DomainHealthReason = '' }
    return [pscustomobject]@{ Healthy = $true; Reason = 'Healthy' }
}

function Write-RestartPolicySummary {
    param(
        [string]$Decision,
        [string]$Reason,
        [int]$DeferredCount,
        [int]$ActiveCount,
        [int]$DisconnectedCount
    )
    Write-Log -Level INFO -Message "FINAL SUMMARY - Restart policy: Decision='$Decision' | Reason='$Reason' | ActiveSessions=$ActiveCount | DisconnectedSessions=$DisconnectedCount | Deferrals=$DeferredCount/$script:MaxDeferredRunsBeforeForcedReboot | State='$script:StateFilePath'"
}

function Invoke-RestartNotificationPolicy {
    param(
        [Parameter(Mandatory)]$PendingReboot,
        [int]$IdleThresholdMinutes = $script:IdleThresholdMinutes,
        [int]$MaxDeferredRunsBeforeForcedReboot = $script:MaxDeferredRunsBeforeForcedReboot
    )

    $sessionInfo = Get-LoggedOnSessions
    $allSessions = @()
    $activeSessions = @()
    $disconnectedSessions = @()

    if ($sessionInfo.QueryOk -and $sessionInfo.ParseOk) {
        $allSessions = @($sessionInfo.Sessions)
        $activeSessions = @($allSessions | Where-Object { $_.IsActive })
        $disconnectedSessions = @($allSessions | Where-Object { $_.State -match '^(Disc|Disconnected|Descon|Disco)$' })
    } else {
        $sessionReason = if ($sessionInfo.Reason) { $sessionInfo.Reason } else { 'Session detection failed.' }
        Write-Log -Level WARN -Message "Restart policy: failed to query sessions. The failure will be audited and will not block the required restart. Reason: $sessionReason"
    }

    foreach ($session in $activeSessions) {
        Write-Log -Level WARN -Message ("Active session before the required restart: User='{0}', Session='{1}', ID={2}, State='{3}', Idle='{4}', IdleMinutes={5}" -f `
            $session.UserName, $session.SessionName, $session.SessionId, $session.State, $session.IdleText, $session.IdleMinutes)
    }

    foreach ($session in $disconnectedSessions) {
        Write-Log -Level INFO -Message ("Disconnected session before the required restart: User='{0}', Session='{1}', ID={2}, State='{3}', Idle='{4}', IdleMinutes={5}" -f `
            $session.UserName, $session.SessionName, $session.SessionId, $session.State, $session.IdleText, $session.IdleMinutes)
    }

    $activeUsers = @($activeSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique)
    $rebootReasons = @($PendingReboot.Reasons)
    if ($rebootReasons.Count -eq 0) { $rebootReasons = @('Configured mandatory weekly restart policy') }
    $finalReason = "Mandatory restart: $($rebootReasons -join ', ')"

    Save-RestartState -DeferredCount 0 -LastDecision 'Authorized' -LastReason $finalReason -LastActiveUsers $activeUsers
    Save-MaintenanceState -Patch @{
        PendingReboot         = [bool]$PendingReboot.Required
        PendingRebootReasons  = $rebootReasons
        RestartScheduled      = $false
        RestartCompleted      = $false
        Compliance            = 'PENDING_REBOOT'
        LastOutcome           = 'REBOOT_REQUIRED'
        LastRunCompletedAt    = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }

    $restartDelaySeconds = Get-RestartDelaySeconds -MinimumNoticeSeconds $ShutdownNoticeSeconds
    Write-Log -Level INFO -Message "Restart policy: weekly restart is mandatory and unconditionally authorized. Reason='$finalReason'. Delay=${restartDelaySeconds}s; configured window='$($script:MaintenanceWindow.RestartTime)'."

    if ($SendUserNotices) {
        $minutes = [math]::Max(1, [int][math]::Ceiling($restartDelaySeconds / 60))
        $msg = "Maintenance completed. This workstation requires a restart and will restart automatically in approximately $minutes minute(s). Save your work immediately."
        $rc = Send-MessageToAllSessions -Message $msg
        if ($rc -eq 0) {
            Write-Log -Level INFO -Message 'Required-restart notification sent through msg.exe.'
        } else {
            Write-Log -Level INFO -Message "msg.exe notification was not delivered (rc=$rc). The native shutdown.exe notice remains active."
        }
    }

    if (-not $ForceReboot) {
        throw 'Safety invariant violated: ForceReboot=False under a mandatory restart policy.'
    }

    $shutdownExe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    $comment = 'Enterprise maintenance completed. A restart is required to finish Windows updates, repairs, or pending operations.'
    $safeComment = $comment.Replace('"', '\"')
    $shutdownArgs = '/r /f /t {0} /c "{1}"' -f [int]$restartDelaySeconds, $safeComment

    Write-Log -Level INFO -Message ("Preparing restart: {0} {1}" -f $shutdownExe, $shutdownArgs)

    try {
        $p = Start-Process -FilePath $shutdownExe -ArgumentList $shutdownArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop

        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1190) {
            Set-RebootScheduledLock -ShutdownTimeoutSeconds ([int]$restartDelaySeconds) -ShutdownExitCode ([int]$p.ExitCode)
            Save-MaintenanceState -Patch @{
                RestartScheduled = $true
                Compliance       = 'PENDING_REBOOT'
                LastOutcome      = 'REBOOT_SCHEDULED'
            }
            Write-Log -Level INFO -Message "Restart registered. ExitCode=$($p.ExitCode); Delay=${restartDelaySeconds}s."
            return [pscustomobject]@{ RebootScheduled = $true; Reason = $finalReason }
        }

        Write-Log -Level ERROR -Message "shutdown.exe returned ExitCode=$($p.ExitCode). Attempting immediate fallback through Restart-Computer -Force."
        Save-MaintenanceState -Patch @{ RestartScheduled = $false; Compliance = 'NON_COMPLIANT'; LastOutcome = "SHUTDOWN_FAILED_$($p.ExitCode)" }
        Restart-Computer -Force -ErrorAction Stop
        return [pscustomobject]@{ RebootScheduled = $true; Reason = 'Fallback Restart-Computer -Force invocado' }
    } catch {
        Write-Log -Level ERROR -Message "Primary restart mechanism failed: $($_.Exception.Message). Attempting fallback via Win32Shutdown."
        Save-MaintenanceState -Patch @{ RestartScheduled = $false; Compliance = 'NON_COMPLIANT'; LastOutcome = 'SHUTDOWN_EXCEPTION' }
        try {
            $os = Get-WmiObject -Class Win32_OperatingSystem -EnableAllPrivileges -ErrorAction Stop
            $result = $os.Win32Shutdown(6)
            if ($result.ReturnValue -ne 0) { throw "Win32Shutdown returned $($result.ReturnValue)" }
            return [pscustomobject]@{ RebootScheduled = $true; Reason = 'Fallback Win32Shutdown(6) invocado' }
        } catch {
            Write-Log -Level ERROR -Message "All restart mechanisms failed: $($_.Exception.Message)"
            Save-MaintenanceState -Patch @{ RestartScheduled = $false; Compliance = 'NON_COMPLIANT'; LastOutcome = 'ALL_REBOOT_MECHANISMS_FAILED' }
            return [pscustomobject]@{ RebootScheduled = $false; Reason = $_.Exception.Message }
        }
    }
}


# ==================== Bootstrap / Deferred Task Governance ====================
function Get-CurrentScriptPathSafe {
    try {
        if ($PSCommandPath) { return $PSCommandPath }
        if ($MyInvocation.MyCommand.Path) { return $MyInvocation.MyCommand.Path }
        return $script:ExecutionSource
    } catch {
        return $script:ExecutionSource
    }
}

function Test-CurrentScriptIsStaged {
    try {
        $current = [System.IO.Path]::GetFullPath((Get-CurrentScriptPathSafe))
        $local   = [System.IO.Path]::GetFullPath($script:LocalScriptPath)
        return ($current.TrimEnd('\') -ieq $local.TrimEnd('\'))
    } catch {
        return $false
    }
}

function Sync-LocalMaintenanceScript {
    Ensure-Directory -Path $script:StageRoot

    $currentPath = Get-CurrentScriptPathSafe
    $isStaged = Test-CurrentScriptIsStaged

    if ($isStaged) {
        Write-Log -Level INFO -Message "The script is already running from local staging at '$script:LocalScriptPath'. No script copy is required."
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($script:ExpectedExecutionSource) -and
        (Test-Path -LiteralPath $script:ExpectedExecutionSource)) {
        Copy-Item -LiteralPath $script:ExpectedExecutionSource -Destination $script:LocalScriptPath -Force -ErrorAction Stop
        $size = (Get-Item -LiteralPath $script:LocalScriptPath -ErrorAction Stop).Length
        Write-Log -Level INFO -Message "PowerShell script synchronized to local staging. Source='$script:ExpectedExecutionSource'; Destination='$script:LocalScriptPath'; Size=$size byte(s)."
        return
    }

    if (Test-Path -LiteralPath $currentPath) {
        Copy-Item -LiteralPath $currentPath -Destination $script:LocalScriptPath -Force -ErrorAction Stop
        $size = (Get-Item -LiteralPath $script:LocalScriptPath -ErrorAction Stop).Length
        Write-Log -Level WARN -Message "The configured authoritative source is unavailable or not set. The current script was copied to local staging. Source='$currentPath'; Destination='$script:LocalScriptPath'; Size=$size byte(s)."
        return
    }

    throw "Unable to synchronize the local script. Source='$script:ExpectedExecutionSource'; Current='$currentPath'."
}



function Invoke-StagedRuntimeHandoff {
    if ($RunDeferred) { return $false }

    $isStaged = Test-CurrentScriptIsStaged
    if ($isStaged) {
        Write-Log -Level INFO -Message "Local staged runtime confirmed. The current run already uses '$script:LocalScriptPath'."
        return $false
    }

    if (-not (Test-Path -LiteralPath $script:LocalScriptPath)) {
        throw "Local staged runtime was not found after synchronization: '$script:LocalScriptPath'."
    }

    $currentPath = Get-CurrentScriptPathSafe
    Write-Log -Level INFO -Message "The current runtime is outside StageRoot. CurrentScript='$currentPath'. A new local staged instance will start and the current instance will exit."

    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $script:LocalScriptPath,
        '-StageRuntime'
    )

    if ($ShowConsole) { $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script:LocalScriptPath,'-StageRuntime','-ShowConsole') }

    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -PassThru -WindowStyle Hidden -ErrorAction Stop
    Write-Log -Level INFO -Message "New local staged instance started. PID=$($p.Id); Script='$script:LocalScriptPath'."
    Write-Log -Level INFO -Message 'Original instance exited after the local staged handoff. Deferred-task governance will continue from the ProgramData runtime.'
    return $true
}

function Ensure-WeeklyMaintenanceDeferredTask {
    [CmdletBinding()]
    param()

    Ensure-Directory -Path $script:StageRoot

    if (-not (Test-Path -LiteralPath $script:LocalScriptPath)) {
        throw "Local maintenance script not found: '$script:LocalScriptPath'."
    }

    $actionArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -RunDeferred -StageRuntime' -f $script:LocalScriptPath
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArgs -WorkingDirectory $script:StageRoot
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $script:MaintenanceWindow.Day -At $script:MaintenanceWindow.InstallTime
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 8) `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Hidden

    $taskDescription = 'Runs governed weekly workstation maintenance during the configured window as SYSTEM from the local staged runtime. The action invokes powershell.exe directly without an intermediate CMD launcher.'
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $taskDescription

    Register-ScheduledTask -TaskName $script:DeferredTaskName -InputObject $task -Force | Out-Null
    Write-Log -Level INFO -Message "Weekly deferred task '$script:DeferredTaskName' created or updated as a managed singleton. Schedule='$($script:MaintenanceWindow.Day) $($script:MaintenanceWindow.InstallTime)'; Action='powershell.exe $actionArgs'; WorkingDirectory='$script:StageRoot'; Context='SYSTEM'."

    # Independent watchdog: guarantees the configured restart even if maintenance
    # hangs, exits, or fails before it can invoke shutdown.exe.
    $shutdownExe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    $enforcerArgs = '/r /f /t 0 /c "SCRIPTGUY mandatory weekly workstation restart."'
    $enforcerAction = New-ScheduledTaskAction -Execute $shutdownExe -Argument $enforcerArgs
    $enforcerTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $script:MaintenanceWindow.Day -At $script:MaintenanceWindow.RestartTime
    $enforcerSettings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
        -StartWhenAvailable `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Hidden
    $enforcerDescription = 'Independent fail-safe that forces the configured weekly workstation restart as SYSTEM even when the maintenance workload fails or hangs.'
    $enforcerTask = New-ScheduledTask -Action $enforcerAction -Trigger $enforcerTrigger -Principal $principal -Settings $enforcerSettings -Description $enforcerDescription
    Register-ScheduledTask -TaskName $script:RebootEnforcerTaskName -InputObject $enforcerTask -Force | Out-Null
    Write-Log -Level INFO -Message "Restart watchdog task '$script:RebootEnforcerTaskName' created or updated. Schedule='$($script:MaintenanceWindow.Day) $($script:MaintenanceWindow.RestartTime)'; Action='$shutdownExe $enforcerArgs'; Context='SYSTEM'."

    try {
        $info = Get-ScheduledTask -TaskName $script:DeferredTaskName -ErrorAction Stop
        $triggerInfo = @($info.Triggers | ForEach-Object { $_.ToString() }) -join ' | '
        $actionInfo  = @($info.Actions  | ForEach-Object { "Execute='$($_.Execute)' Arguments='$($_.Arguments)' WorkingDirectory='$($_.WorkingDirectory)'" }) -join ' | '
        Write-Log -Level INFO -Message "Deferred-task validation completed. TaskName='$script:DeferredTaskName'; State='$($info.State)'; Triggers='$triggerInfo'; Actions='$actionInfo'."

        $invalidCmd = @($info.Actions | Where-Object { $_.Execute -match '(?i)cmd\.exe' })
        if (@($invalidCmd).Count -gt 0) {
            Write-Log -Level WARN -Message "Validation detected a cmd.exe action in task '$script:DeferredTaskName'. The next bootstrap run must recreate it with direct PowerShell execution."
        }

        $enforcerInfo = Get-ScheduledTask -TaskName $script:RebootEnforcerTaskName -ErrorAction Stop
        $enforcerActionInfo = @($enforcerInfo.Actions | ForEach-Object { "Execute='$($_.Execute)' Arguments='$($_.Arguments)'" }) -join ' | '
        Write-Log -Level INFO -Message "Restart-watchdog validation completed. TaskName='$script:RebootEnforcerTaskName'; State='$($enforcerInfo.State)'; Actions='$enforcerActionInfo'."
    } catch {
        Write-Log -Level WARN -Message "Unable to validate the deferred task after registration: $($_.Exception.Message)"
    }
}

function Get-CurrentBootTimeUtc {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    return ([datetime]$os.LastBootUpTime).ToUniversalTime()
}

function Test-BootstrapAlreadyCompletedThisBoot {
    if (-not (Test-Path -LiteralPath $script:BootstrapStateFile)) { return $false }

    try {
        $state = Get-Content -LiteralPath $script:BootstrapStateFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $currentBoot = Get-CurrentBootTimeUtc
        $savedBoot = [datetime]::Parse(
            [string]$state.BootTimeUtc,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()

        if ($savedBoot -ne $currentBoot) { return $false }
        if ([string]$state.ScriptVersion -ne $ScriptVersion) { return $false }

        $deferred = Get-ScheduledTask -TaskName $script:DeferredTaskName -ErrorAction SilentlyContinue
        $enforcer = Get-ScheduledTask -TaskName $script:RebootEnforcerTaskName -ErrorAction SilentlyContinue
        return ($null -ne $deferred -and $null -ne $enforcer)
    } catch {
        Write-Log -Level WARN -Message "Unable to validate the bootstrap marker: $($_.Exception.Message). Bootstrap will run again."
        return $false
    }
}

function Set-BootstrapCompletedThisBoot {
    try {
        $state = [ordered]@{
            SchemaVersion  = 1
            ScriptVersion  = $ScriptVersion
            BootTimeUtc    = (Get-CurrentBootTimeUtc).ToString('o')
            CompletedAtUtc = ([datetime]::UtcNow).ToString('o')
            ComputerName   = $env:COMPUTERNAME
        }
        $json = $state | ConvertTo-Json -Depth 3
        Set-Content -LiteralPath $script:BootstrapStateFile -Value $json -Encoding UTF8 -Force
    } catch {
        Write-Log -Level WARN -Message "Bootstrap completed, but the duplicate-run marker could not be written: $($_.Exception.Message)"
    }
}

function Invoke-MaintenanceBootstrap {
    Write-Log -Level INFO -Message "Bootstrap mode detected. Preparing the local staged runtime in '$script:StageRoot' and ensuring the weekly deferred task."
    Sync-LocalMaintenanceScript
    if (Invoke-StagedRuntimeHandoff) {
        return
    }

    if (Test-BootstrapAlreadyCompletedThisBoot) {
        Write-Log -Level INFO -Message "Bootstrap already completed during this boot for version '$ScriptVersion'; authoritative tasks are present. Duplicate run skipped."
        return
    }

    Ensure-WeeklyMaintenanceDeferredTask
    Set-BootstrapCompletedThisBoot
    Write-Log -Level INFO -Message "Bootstrap completed. Maintenance='$script:DeferredTaskName' at $($script:MaintenanceWindow.InstallTime); restart watchdog='$script:RebootEnforcerTaskName' at $($script:MaintenanceWindow.RestartTime)."
}

# ==================== Main ====================
try {
    Initialize-Log
    Invoke-PreValidation
    [void](Repair-StaleGovernanceState)

    if (-not $RunDeferred) {
        Invoke-MaintenanceBootstrap
        Write-Log -Level INFO -Message "===== END $ScriptName - BOOTSTRAP ====="
        exit 0
    }

    Write-Log -Level INFO -Message 'Deferred mode detected. Starting the weekly maintenance workload.'

    if (Test-AwaitingRestartLock) {
        Write-Log -Level INFO -Message 'Run ended by governance: restart is already scheduled or pending. No intensive maintenance will run.'
        Write-Log -Level INFO -Message "===== END $ScriptName - WAITING_REBOOT ====="
        exit 0
    }

    if (-not (Acquire-ExecutionLock)) {
        Write-Log -Level INFO -Message 'Run ended by governance: another run is active or still within the lock window.'
        Write-Log -Level INFO -Message "===== END $ScriptName - EXECUTION_LOCKED ====="
        exit 0
    }

    $finalRuntimeState = 'COMPLETED'
    $runStartedDate = Get-Date
    $runStartedAt = $runStartedDate.ToString('yyyy-MM-dd HH:mm:ss')
    $windowsUpdatePolicy = Get-WindowsUpdatePolicyState
    Write-Log -Level INFO -Message "Windows Update effective policy: State='$($windowsUpdatePolicy.UpdateManagementState)' | SourceType='$($windowsUpdatePolicy.SourceType)' | Managed=$($windowsUpdatePolicy.Managed) | WUServer='$($windowsUpdatePolicy.WUServer)' | TargetGroup='$($windowsUpdatePolicy.TargetGroup)'."

    Save-MaintenanceState -Patch @{
        LastRunStartedAt      = $runStartedAt
        LastRunCompletedAt    = $null
        UpdateManagementState = $windowsUpdatePolicy.UpdateManagementState
        WindowsUpdatePolicy   = $windowsUpdatePolicy
        PendingReboot        = $false
        PendingRebootReasons = @()
        RestartScheduled     = $false
        RestartCompleted     = $false
        Compliance           = 'RUNNING'
        LastOutcome          = 'MAINTENANCE_STARTED'
    }

    $preReboot = Test-PendingReboot
    Write-Log -Level INFO -Message "Restart pre-check: Required=$($preReboot.Required) | Reasons='$($preReboot.Reasons -join ', ')'."

    # Central invariant: arm the restart before maintenance or any health gate.
    # A timeout, exception, unavailable domain, or later failure cannot suppress it.
    $initialRestartResult = Invoke-RestartNotificationPolicy `
        -PendingReboot $preReboot `
        -IdleThresholdMinutes $script:IdleThresholdMinutes `
        -MaxDeferredRunsBeforeForcedReboot $script:MaxDeferredRunsBeforeForcedReboot
    if (-not $initialRestartResult.RebootScheduled) {
        throw "Unable to arm the mandatory restart: $($initialRestartResult.Reason)"
    }
    $finalRuntimeState = 'WAITING_REBOOT'
    Write-Log -Level INFO -Message 'Invariant confirmed: mandatory restart armed before maintenance.'

    $domainFqdn    = Get-DomainFQDN
    $domainNetBIOS = Get-DomainNetBIOS
    $computerDn    = Get-ComputerDN
    $domainGate    = Test-DomainHealthGate -DomainFqdn $domainFqdn -DomainNetBIOS $domainNetBIOS -ComputerDn $computerDn

    Write-Log -Level INFO -Message "===== START $ScriptName v$ScriptVersion ====="
    Write-Log -Level INFO -Message "Computer DN: $computerDn"
    Write-Log -Level INFO -Message "Detected domain FQDN: $domainFqdn"
    Write-Log -Level INFO -Message "Detected domain NetBIOS name: $domainNetBIOS"

    # SFC, DISM, and local operations do not depend on domain health.
    if ($RunSfcDism)              { Invoke-SfcDism }

    if ($domainGate.Healthy) {
        if ($ResetLocalGpo)       { Reset-LocalGpoCache }
        if ($RunAdNetworkChecks -and $domainFqdn -ne 'WORKGROUP') { Invoke-RedeAd -DomainForNltest $domainFqdn }
        if ($RunCertutilPulse -or $RunGpupdateComputerOnly) { Invoke-Policies }
        if ($CertSyncEnable)      { Invoke-CertSyncIfEnabled }
    } else {
        Write-Log -Level WARN -Message "DomainHealthGate blocked sensitive domain/GPO operations. Reason='$($domainGate.Reason)'."
    }

    if ($CleanWuCache)            { Invoke-WuCacheCleanup }

    Invoke-ProfileMaintenance
    Invoke-Infrastructure
    Invoke-NetworkSummary -Fqdn $domainFqdn -NetBIOS $domainNetBIOS

    if ($domainGate.Healthy) {
        $updateHistory = Get-UpdatesInstalledSince -Since $runStartedDate
        $updatesInstalledValue = if ($updateHistory.QueryOk) { ($updateHistory.Count -gt 0) } else { $null }
        Write-Log -Level INFO -Message "Windows Update history since the start of the maintenance window: QueryOk=$($updateHistory.QueryOk) | InstalledCount=$($updateHistory.Count)."
        if ($updateHistory.Count -gt 0) {
            foreach ($title in $updateHistory.Titles) {
                Write-Log -Level INFO -Message "Update installed during the maintenance window: $title"
            }
        }
        Save-MaintenanceState -Patch @{ UpdatesInstalled = $updatesInstalledValue }

        $postReboot = Test-PendingReboot
        Write-Log -Level INFO -Message "Restart post-check: Required=$($postReboot.Required) | Reasons='$($postReboot.Reasons -join ', ')'."

        Write-Log -Level INFO -Message 'The restart was already armed at the start of execution; the post-check was recorded without rescheduling.'
        $finalRuntimeState = 'WAITING_REBOOT'
    } else {
        Write-Log -Level WARN -Message 'Domain/GPO-dependent operations were blocked pelo DomainHealthGate. The mandatory restart remains armed.'
        Save-GovernanceState -Patch @{ RuntimeState = 'WAITING_REBOOT_DOMAIN_DEGRADED' }
        Save-MaintenanceState -Patch @{
            DomainHealth         = 'UNHEALTHY'
            DomainHealthReason   = $domainGate.Reason
            Compliance           = 'PENDING_REBOOT'
            LastOutcome          = 'DOMAIN_HEALTH_FAILED_REBOOT_ARMED'
            LastRunCompletedAt   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $finalRuntimeState = 'WAITING_REBOOT_DOMAIN_DEGRADED'
    }

    Release-ExecutionLock -RuntimeState $finalRuntimeState
    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 0
} catch {
    Write-Log -Level ERROR -Message "Unhandled critical failure: $($_.Exception.Message)"
    Save-MaintenanceState -Patch @{
        Compliance         = 'NON_COMPLIANT'
        LastOutcome        = 'FAILED'
        LastRunCompletedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    # Deferred-mode final fail-safe: an exception must never convert a maintenance
    # failure into a missing restart. Bootstrap mode does not restart the workstation.
    $governanceAfterFailure = Get-GovernanceState
    if ($RunDeferred -and -not [bool]$governanceAfterFailure.AwaitingRestart) {
        Write-Log -Level WARN -Message 'Fail-safe: no restart was registered after a critical failure. Arming a forced restart with minimum notice.'
        $ShutdownNoticeSeconds = 60
        $fallbackPending = [pscustomobject]@{ Required = $true; Reasons = @('Fail-safe after a critical maintenance failure') }
        $fallbackRestart = Invoke-RestartNotificationPolicy -PendingReboot $fallbackPending
        if (-not $fallbackRestart.RebootScheduled) {
            Write-Log -Level ERROR -Message "Fail-safe could not arm the restart: $($fallbackRestart.Reason)"
        }
    }
    Release-ExecutionLock -RuntimeState 'FAILED_REBOOT_FAILSAFE_PROCESSED'
    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 1
}

# End of script
