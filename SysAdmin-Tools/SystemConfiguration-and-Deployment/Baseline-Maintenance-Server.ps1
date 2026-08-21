#requires -Version 5.1
<#
.SYNOPSIS
Runs governed maintenance on Windows Server systems.

.DESCRIPTION
Provides a generalized enterprise server-maintenance workflow with local runtime
staging, deterministic logging, inventory, optional SFC and DISM repair, controlled
Group Policy and Windows Update cache maintenance, domain health operations, folder
retention cleanup, session auditing, and a forced-restart fallback task.

No forest, domain controller, WSUS server, GPO, OU, or institutional UNC path is
assumed. Critical server roles are blocked by default and require explicit operator
authorization through AllowCriticalServerRoles.

.PARAMETER MasterScriptPath
Optional authoritative UNC or local script used to refresh the staged runtime.

.PARAMETER AllowCriticalServerRoles
Explicitly authorizes maintenance and restart on domain controllers, failover-cluster
nodes, and Hyper-V hosts. Review workload redundancy before using this switch.

.PARAMETER ShowConsole
Keeps the console visible for interactive troubleshooting.

.NOTES
Author: Luiz Hamilton Silva - github.com/brazilianscriptguy
Organization template: SCRIPTGUY
Version: 2.0.0-GENERALIZED-ENTERPRISE-SERVER
Requires: Windows PowerShell 5.1; administrative or SYSTEM context
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [string]$MasterScriptPath = '',
    [switch]$AllowCriticalServerRoles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==================== Configuration ====================
$OrganizationName            = 'SCRIPTGUY'
$LogRetentionDays            = 6
$LogRetentionPath            = 'C:\Scripts-LOGS'
$LogDir                      = 'C:\Scripts-LOGS'
$ScriptName                  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$ScriptVersion               = '2.0.0-GENERALIZED-ENTERPRISE-SERVER'
$script:ExecutionSource      = $MyInvocation.MyCommand.Path
$script:ExpectedUncSource    = $MasterScriptPath
$script:LocalScriptRoot      = Join-Path $env:ProgramData "$OrganizationName\Maintenance-Servers"
$script:LocalScriptPath      = Join-Path $script:LocalScriptRoot 'Invoke-EnterpriseServerMaintenance.ps1'
$script:StateRoot            = $script:LocalScriptRoot
$script:StateFilePath        = Join-Path $script:StateRoot 'restart-state.json'
$script:IdleThresholdMinutes = 120
$script:MaxDeferredRunsBeforeForcedReboot = 0
$LogFile                     = Join-Path $LogDir "$ScriptName.log"
$PathSoftDist                = 'C:\Windows\SoftwareDistribution'
$PathCatroot2                = 'C:\Windows\System32\catroot2'
$DefaultUserImagePath        = 'C:\ProgramData\Microsoft\User Account Pictures\user.png'
$GroupPolicyUpdateWaitSeconds         = 30
$CleanWuTimeoutSec           = 600
$RebootFinalDelaySec         = 0
$ServerCleanupPaths          = @('C:\Temp','C:\Logs-TEMP','C:\Scripts-LOGS')
$ShutdownNoticeSeconds       = 900
$script:RebootFallbackTaskName = "$OrganizationName-Maintenance-Servers-Reboot-Fallback"

$RunSfcDism                  = $true
$ResetLocalGpo               = $true
$CleanWuCache                = $true
$ReEnableWuTasksAtEnd        = $true
$RunAdNetworkChecks          = $true
$RunGpupdateComputerOnly     = $true
$RunCertutilPulse            = $true
$CertSyncEnable              = $false
$SetDefaultUserPicture       = $false
$HandleUserProfiles          = $false
$CleanUserTemp               = $false
$RestartSpooler              = $false
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

function Get-ServerRoleSafetyAssessment {
    $roles = New-Object System.Collections.Generic.List[string]
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    if ([int]$os.ProductType -eq 1) {
        throw "Unsupported operating system: '$($os.Caption)'. This script is intended for Windows Server."
    }

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    if ([int]$computerSystem.DomainRole -ge 4) { $roles.Add('Active Directory Domain Controller') }
    if (Get-Service -Name 'ClusSvc' -ErrorAction SilentlyContinue) { $roles.Add('Failover Cluster Node') }
    if (Get-Service -Name 'vmms' -ErrorAction SilentlyContinue) { $roles.Add('Hyper-V Host') }

    [pscustomobject]@{
        OperatingSystem = [string]$os.Caption
        CriticalRoles   = @($roles)
        IsCritical      = ($roles.Count -gt 0)
    }
}

function Invoke-PreValidation {
    Ensure-Directory -Path $script:LocalScriptRoot
    Ensure-Directory -Path $LogDir

    if (-not (Test-AdministratorContext)) {
        throw 'Insufficient context: the script must run with administrative privileges or as SYSTEM.'
    }

    $roleAssessment = Get-ServerRoleSafetyAssessment
    Write-Log -Level INFO -Message "Server role preflight: OS='$($roleAssessment.OperatingSystem)'; CriticalRoles='$(@($roleAssessment.CriticalRoles) -join ', ')'; ExplicitAuthorization=$([bool]$AllowCriticalServerRoles)."
    if ($roleAssessment.IsCritical -and -not $AllowCriticalServerRoles) {
        throw "Critical server role protection blocked maintenance. Roles='$(@($roleAssessment.CriticalRoles) -join ', ')'. Re-run with -AllowCriticalServerRoles only after validating redundancy, failover, and the approved change window."
    }

    try {
        if (-not (Test-Path -LiteralPath $script:StateRoot)) {
            New-Item -Path $script:StateRoot -ItemType Directory -Force | Out-Null
        }
        $probeFile = Join-Path $script:StateRoot '.__write_test.tmp'
        Set-Content -LiteralPath $probeFile -Value 'ok' -Encoding UTF8 -Force
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
        Write-Log -Level INFO -Message "Pre-validation completed. Local root: $script:LocalScriptRoot | State: $script:StateFilePath | Local script: $script:LocalScriptPath"
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
function Test-LocalScriptSynchronization {
    [CmdletBinding()]
    param()

    try {
        Write-Log -Level INFO -Message "Local script synchronization check started. Local='$script:LocalScriptPath'; Authoritative='$script:ExpectedUncSource'."

        if ([string]::IsNullOrWhiteSpace($script:ExpectedUncSource)) {
            if (-not (Test-Path -LiteralPath $script:LocalScriptPath) -and (Test-Path -LiteralPath $script:ExecutionSource)) {
                Copy-Item -LiteralPath $script:ExecutionSource -Destination $script:LocalScriptPath -Force
                Write-Log -Level INFO -Message "No authoritative source was configured. The current script was copied to local staging at '$script:LocalScriptPath'."
            } else {
                Write-Log -Level INFO -Message 'No authoritative source was configured. The current local runtime remains authoritative for this run.'
            }
            return
        }

        if (-not (Test-Path -LiteralPath $script:ExpectedUncSource)) {
            Write-Log -Level WARN -Message "The authoritative script is currently unavailable: $script:ExpectedUncSource. Continuing with the local/current runtime."
            return
        }

        if (-not (Test-Path -LiteralPath $script:LocalScriptPath)) {
            try {
                Copy-Item -LiteralPath $script:ExpectedUncSource -Destination $script:LocalScriptPath -Force
                Write-Log -Level INFO -Message "The local runtime did not exist and was initialized from the authoritative source: $script:LocalScriptPath"
            } catch {
                Write-Log -Level WARN -Message "Failed to copy the authoritative script to '$script:LocalScriptPath': $($_.Exception.Message). Continuing with the current runtime."
            }
            return
        }

        $uncHash   = (Get-FileHash -LiteralPath $script:ExpectedUncSource -Algorithm SHA256).Hash
        $localHash = (Get-FileHash -LiteralPath $script:LocalScriptPath -Algorithm SHA256).Hash

        if ($uncHash -eq $localHash) {
            Write-Log -Level INFO -Message "Local runtime validated: SHA-256 matches the authoritative script. SHA256=$localHash"
            return
        }

        Write-Log -Level WARN -Message "The local runtime differs from the authoritative script. LocalSHA256=$localHash; AuthoritativeSHA256=$uncHash."

        $tempPath = Join-Path $script:LocalScriptRoot ("{0}.next" -f ([System.IO.Path]::GetFileName($script:LocalScriptPath)))
        Copy-Item -LiteralPath $script:ExpectedUncSource -Destination $tempPath -Force

        $tempHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash
        if ($tempHash -ne $uncHash) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            Write-Log -Level WARN -Message "The temporary copy hash does not match the authoritative script. Local update aborted. TempSHA256=$tempHash; AuthoritativeSHA256=$uncHash."
            return
        }

        Move-Item -LiteralPath $tempPath -Destination $script:LocalScriptPath -Force
        Write-Log -Level INFO -Message 'The local runtime was updated from the authoritative source and will be used on the next run.'
    } catch {
        Write-Log -Level WARN -Message "Local runtime synchronization failed: $($_.Exception.Message). Continuing with the current runtime."
    }
}

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
    $psi.Arguments = "/d /c $CommandLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    # A local working directory avoids CMD warnings when the script starts from UNC.
    $psi.WorkingDirectory = $env:WINDIR
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

function Invoke-TimedOperation {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )
    Write-Log -Level INFO -Message "[TIMER] Block started: $Name"
    $t0 = Get-Date
    try {
        & $ScriptBlock
    } finally {
        $elapsed = [int]((Get-Date) - $t0).TotalSeconds
        Write-Log -Level INFO -Message "[TIMER] Block ended: $Name ($elapsed s)"
    }
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

function Get-DomainFQDN {
    try {
        $adsi = New-Object -ComObject ADSystemInfo
        $val = Get-NormalizedValue -Value $adsi.DomainDNSName -Fallback ''
        if ($val) { return $val }
    } catch {}

    if ($env:USERDNSDOMAIN) { return $env:USERDNSDOMAIN }

    try {
        $fqdn = (& whoami /fqdn 2>$null | Out-String).Trim()
        if ($fqdn -match '@') { return ($fqdn -split '@')[-1] }
        if ($fqdn) { return $fqdn }
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
        return 'UNKNOWN'
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
            Write-Log -Level WARN -Message "Service protected service detected: $Name could not be stopped. Continuing."
            return $false
        } catch {
            Write-Log -Level WARN -Message "Service protected service detected: $Name could not be stopped. Continuing."
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
    Write-Log -Level WARN -Message "Unable to stop $Name. Continuing."
    return $false
}

# ==================== SFC / DISM ====================
function Invoke-SfcDism {
    Write-Log -Level INFO -Message 'Running SFC /scannow...'
    $t0 = Get-Date
    $rc = (Start-Process -FilePath "$env:windir\system32\sfc.exe" -ArgumentList '/scannow' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) {
        Write-Log -Level INFO -Message "SFC completed successfully (ExitCode=0; Duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    } else {
        Write-Log -Level WARN -Message "SFC returned ExitCode=$rc; Duration=$([int]((Get-Date)-$t0).TotalSeconds)s."
    }

    Write-Log -Level INFO -Message 'Running DISM /RestoreHealth...'
    $t0 = Get-Date
    $rc = (Start-Process -FilePath "$env:windir\system32\dism.exe" -ArgumentList '/online','/cleanup-image','/restorehealth' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) {
        Write-Log -Level INFO -Message "DISM /RestoreHealth completed successfully (ExitCode=0; Duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    } else {
        $unsignedRc = [System.BitConverter]::ToUInt32([System.BitConverter]::GetBytes([int32]$rc), 0)
        $hexRc = ('0x{0:X8}' -f $unsignedRc)
        $diagnosis = switch ($hexRc) {
            '0x800F081F' { 'Source files were not found. Validate the repair source and component-repair policy.' }
            '0x800F0906' { 'Repair content could not be downloaded. Validate proxy, WSUS/Microsoft Update, and connectivity.' }
            '0x800F0954' { 'WSUS policy may be blocking optional or repair content. Validate the alternate component source.' }
            '0x800F0922' { 'Servicing failure. Validate system-partition free space, CBS.log, and DISM.log.' }
            '0x800F0915' { 'CBS/servicing engine failure. Review DISM.log and CBS.log and validate a repair source matching the installed build.' }
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
    Write-Log -Level INFO -Message 'Local Group Policy cache removed. No security.inf file will be applied.'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy'
    if (Test-Path -LiteralPath $key) {
        try {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            Write-Log -Level INFO -Message 'Local Group Policy registry key removed.'
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
    $label  = if ($Enable) { 're-enabled (best effort)' } else { 'temporarily disabled' }

    foreach ($task in $tasks) {
        try {
            if (Test-TaskExists -TaskName $task) {
                $command = 'schtasks.exe /change /tn "{0}" {1}' -f $task, $action
                $result = Invoke-CapturedCommand -CommandLine $command -Title "SCHTASKS $($action.ToUpper()) $task" -TimeoutSec 30
                if ($result.ExitCode -ne 0) {
                    Write-Log -Level WARN -Message "Unable to update Windows Update task '$task' with action '$action'. rc=$($result.ExitCode). Continuing."
                }
            }
        } catch {
            Write-Log -Level WARN -Message "Failed to process Windows Update task '$task'. Nonfatal operation: $($_.Exception.Message)"
        }
    }
    Write-Log -Level INFO -Message "Windows Update tasks $label."
}

function Invoke-WuCacheCleanup {
    if (-not $CleanWuCache) { return }

    $t0 = Get-Date
    $wuHadPartialFailure = $false
    Write-Log -Level INFO -Message "[WU] Block started (timeout ${CleanWuTimeoutSec}s)."

    try {
        try {
            Set-WuRecurringTasksState -Enable:$false
        } catch {
            $wuHadPartialFailure = $true
            Write-Log -Level WARN -Message "Unable to disable all Windows Update tasks. Nonfatal operation: $($_.Exception.Message)"
        }

        $okDo    = Stop-ServiceWithRetry -Name 'dosvc'
        $okMedic = Stop-ServiceWithRetry -Name 'WaaSMedicSvc'
        $okTI    = Stop-ServiceWithRetry -Name 'TrustedInstaller'
        $okBits  = Stop-ServiceWithRetry -Name 'bits'
        $okWua   = Stop-ServiceWithRetry -Name 'wuauserv'
        $okCrypt = Stop-ServiceWithRetry -Name 'cryptsvc'

        if (-not $okCrypt) {
            $wuHadPartialFailure = $true
            Write-Log -Level WARN -Message 'CryptSvc did not stop (possible AV/EDR). catroot2 will be preserved.'
        }

        if (((Get-Date) - $t0).TotalSeconds -le $CleanWuTimeoutSec) {
            if ($okBits -and $okWua) {
                if (Test-Path -LiteralPath $PathSoftDist) {
                    try {
                        Remove-Item -LiteralPath $PathSoftDist -Recurse -Force -ErrorAction Stop
                        Write-Log -Level INFO -Message 'SoftwareDistribution removed successfully.'
                    } catch {
                        $wuHadPartialFailure = $true
                        Write-Log -Level WARN -Message "Failed to remove SoftwareDistribution. Attempting rename. Nonfatal operation: $($_.Exception.Message)"
                        Rename-IfExists -PathLiteral '%SystemRoot%\SoftwareDistribution'
                    }
                } else {
                    Write-Log -Level INFO -Message 'SoftwareDistribution folder not found.'
                }
            } else {
                $wuHadPartialFailure = $true
                Write-Log -Level WARN -Message 'BITS/WUAUSERV did not stop; SoftwareDistribution cleanup was skipped. Nonfatal operation.'
            }

            if ($okCrypt) {
                if (Test-Path -LiteralPath $PathCatroot2) {
                    try {
                        Remove-Item -LiteralPath $PathCatroot2 -Recurse -Force -ErrorAction Stop
                        Write-Log -Level INFO -Message 'catroot2 removed successfully.'
                    } catch {
                        $wuHadPartialFailure = $true
                        Write-Log -Level WARN -Message "Failed to remove catroot2. Attempting rename. Nonfatal operation: $($_.Exception.Message)"
                        Rename-IfExists -PathLiteral $PathCatroot2
                    }
                } else {
                    Write-Log -Level INFO -Message 'catroot2 not found (skipping).'
                }
            }
        } else {
            $wuHadPartialFailure = $true
            Write-Log -Level WARN -Message '[WU] Block timed out. Cleanup was partially completed; services and tasks will be restored on a best-effort basis.'
        }
    } catch {
        $wuHadPartialFailure = $true
        Write-Log -Level WARN -Message "Windows Update cleanup was partially completed. Nonfatal failure: $($_.Exception.Message)"
    } finally {
        try {
            if ($ReEnableWuTasksAtEnd) { Set-WuRecurringTasksState -Enable:$true }
        } catch {
            Write-Log -Level WARN -Message "Unable to re-enable all Windows Update tasks. Nonfatal operation: $($_.Exception.Message)"
        }

        foreach ($svc in 'cryptsvc','bits','wuauserv') {
            try { Start-ServiceSilentSafe -Name $svc } catch { Write-Log -Level WARN -Message "Failed to start service $svc after Windows Update reset. Nonfatal operation: $($_.Exception.Message)" }
        }

        try { & bitsadmin.exe /reset /allusers *> $null } catch { Write-Log -Level WARN -Message "Failed to run bitsadmin /reset. Nonfatal operation: $($_.Exception.Message)" }
        try { Start-Process -FilePath wuauclt.exe -ArgumentList '/resetauthorization','/detectnow' -WindowStyle Hidden -ErrorAction SilentlyContinue } catch { Write-Log -Level WARN -Message "Failed to invoke wuauclt. Nonfatal operation: $($_.Exception.Message)" }
        if (Test-Path -LiteralPath "$env:SystemRoot\System32\UsoClient.exe") {
            foreach ($arg in 'StartScan','StartDownload','StartInstall') {
                try { Start-Process -FilePath "$env:SystemRoot\System32\UsoClient.exe" -ArgumentList $arg -WindowStyle Hidden -ErrorAction SilentlyContinue } catch { Write-Log -Level WARN -Message "Failed to invoke UsoClient $arg. Nonfatal operation: $($_.Exception.Message)" }
            }
        }
    }

    if ($wuHadPartialFailure) {
        Write-Log -Level WARN -Message "[WU] Block completed with warnings in $([int]((Get-Date)-$t0).TotalSeconds)s. Execution will continue to the next steps."
    } else {
        Write-Log -Level INFO -Message "[WU] Completed in $([int]((Get-Date)-$t0).TotalSeconds)s."
    }
}

# ==================== Certificates ====================
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
        Write-Log -Level INFO -Message 'gpupdate de computer DISABLED by configuration.'
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
        Write-Log -Level WARN -Message "Default image was NOT found: $DefaultUserImagePath"
        return
    }
    try {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'UseDefaultTile' -PropertyType DWord -Value 1 -Force | Out-Null
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\DefaultUser' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\DefaultUser' -Name 'Image' -PropertyType String -Value $DefaultUserImagePath -Force | Out-Null
        Write-Log -Level INFO -Message "Default image configured: $DefaultUserImagePath"
    } catch {
        Write-Log -Level WARN -Message "Failed to configure the default image: $($_.Exception.Message)"
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
                Write-Log -Level WARN -Message "Perfil .bak detected: $($_.Name)"
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
        Write-Log -Level INFO -Message 'Reiniciando spooler...'
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
    Write-Log -Level INFO -Message '===== RESUMO DE REDE ====='
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
    Write-Log -Level INFO -Message '===== END RESUMO DE REDE ====='
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
                '^(?<User>\S+)\s+(?<SessionName>\S+|)\s+(?<Id>\d+)\s+(?<State>Active|Ativo|Disc|Disco|Disconnected|Descon|Conn)\s+(?<Idle>\S+)\s+(?<Logon>.+)$',
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
        Write-Log -Level WARN -Message "Failed to run 'query user' - $($_.Exception.Message)"
    }

    [pscustomobject]$result
}

function Get-RebootDecision {
    param([int]$IdleThresholdMinutes = 120)

    $sessionInfo = Get-LoggedOnSessions

    $noUserPattern = '(?i)(n\u00E3o existe nenhum usu\u00E1rio|nao existe nenhum usuario|no user exists|no users exist)'
    $rawCombined = "{0}`n{1}" -f [string]$sessionInfo.RawOut, [string]$sessionInfo.RawErr

    if (-not $sessionInfo.QueryOk -or -not $sessionInfo.ParseOk) {
        if ($rawCombined -match $noUserPattern) {
            Write-Log -Level INFO -Message 'Server restart policy: QUSER found no user session. Restart authorized.'
            return [pscustomobject]@{
                AllowReboot = $true
                Reason      = 'No user session detected'
                ActiveUsers = @()
                Sessions    = @()
            }
        }

        $reason = if ($sessionInfo.Reason) { $sessionInfo.Reason } else { 'Session detection failed.' }
        Write-Log -Level WARN -Message "Server restart policy: session query or interpretation failed. The failure is recorded only and does NOT block restart. Reason: $reason"
        return [pscustomobject]@{
            AllowReboot = $true
            Reason      = "Restart authorized without reliable session inventory: $reason"
            ActiveUsers = @()
            Sessions    = @()
        }
    }

    $allSessions = @($sessionInfo.Sessions)
    $activeSessions = @($allSessions | Where-Object { $_.IsActive })
    $disconnectedSessions = @($allSessions | Where-Object { $_.State -match '^(Disc|Disco|Disconnected|Descon)$' })

    if ($allSessions.Count -eq 0) {
        Write-Log -Level INFO -Message 'Server restart policy: no session was interpreted. Restart authorized.'
    }

    foreach ($session in $allSessions) {
        $classification = if ($session.IsActive) { 'ATIVA' } elseif ($session.State -match '^(Disc|Disco|Disconnected|Descon)$') { 'DESCONECTADA' } else { 'OUTRA' }
        Write-Log -Level INFO -Message ("Session recorded before restart: Classification='{0}', User='{1}', Session='{2}', ID={3}, State='{4}', Idle='{5}', IdleMinutes={6}, Logon='{7}'" -f `
            $classification, $session.UserName, $session.SessionName, $session.SessionId, $session.State, $session.IdleText, $session.IdleMinutes, $session.LogonTime)
    }

    $users = ($activeSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
    if ($activeSessions.Count -gt 0) {
        Write-Log -Level WARN -Message ("Server restart policy: active sessions exist, but they do NOT block restart under this server profile. User(s): {0}" -f $users)
    }
    if ($disconnectedSessions.Count -gt 0) {
        $discUsers = ($disconnectedSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
        Write-Log -Level INFO -Message "Disconnected sessions recorded before restart: $discUsers"
    }

    return [pscustomobject]@{
        AllowReboot = $true
        Reason      = 'Server restart authorized by configured policy regardless of open sessions'
        ActiveUsers = @($activeSessions)
        Sessions    = @($allSessions)
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
        [int]$IdleThresholdMinutes = 120
    )
    $usersText = if ($Users -and $Users.Count -gt 0) { ($Users | Sort-Object -Unique) -join ', ' } else { 'signed-in user' }
    return @"
Maintenance completed on this server.
An active session is registered for: $usersText.
Under the server policy, open sessions are recorded only and do not block the automatic restart.
Save any administrative work immediately.
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
        DeferredCount           = 0
        LastDecision            = ''
        LastReason              = ''
        LastRunTime             = ''
        RebootForced            = $true
        LastSessionsTotal       = 0
        LastActiveUsers         = @()
        LastDisconnectedUsers   = @()
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
            DeferredCount           = [int]($obj.DeferredCount)
            LastDecision            = [string]$obj.LastDecision
            LastReason              = [string]$obj.LastReason
            LastRunTime             = [string]$obj.LastRunTime
            RebootForced            = if ($null -ne $obj.RebootForced) { [bool]$obj.RebootForced } else { $true }
            LastSessionsTotal       = if ($null -ne $obj.LastSessionsTotal) { [int]$obj.LastSessionsTotal } else { 0 }
            LastActiveUsers         = @($obj.LastActiveUsers)
            LastDisconnectedUsers   = @($obj.LastDisconnectedUsers)
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to read persistent restart state: $($_.Exception.Message)"
        return [pscustomobject]$default
    }
}

function Test-RestartRegisteredThisBoot {
    try {
        $state = Get-RestartState
        if (-not [bool]$state.RebootForced) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$state.LastRunTime)) { return $false }
        if ([string]$state.LastDecision -notmatch '^Authorized') { return $false }

        $lastRun = [datetime]::ParseExact(
            [string]$state.LastRunTime,
            'yyyy-MM-dd HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        $bootTime = [datetime](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        return ($lastRun -gt $bootTime)
    } catch {
        Write-Log -Level WARN -Message "Unable to evaluate the same-boot restart guard: $($_.Exception.Message). Execution will continue."
        return $false
    }
}

function Save-RestartState {
    param(
        [int]$DeferredCount,
        [string]$LastDecision,
        [string]$LastReason,
        [bool]$RebootForced = $true,
        [object[]]$Sessions = @(),
        [string[]]$LastActiveUsers = @(),
        [string[]]$LastDisconnectedUsers = @()
    )

    try {
        if (Ensure-StateStore) {
            $normalizedSessions = @($Sessions)
            $activeUsers = @(
                $normalizedSessions |
                    Where-Object { $_.IsActive -eq $true } |
                    ForEach-Object { $_.UserName } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
            $disconnectedUsers = @(
                $normalizedSessions |
                    Where-Object { $_.State -match '^(Disc|Disco|Disconnected|Descon)$' } |
                    ForEach-Object { $_.UserName } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )

            if ($LastActiveUsers -and $LastActiveUsers.Count -gt 0) {
                $activeUsers = @($LastActiveUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            }
            if ($LastDisconnectedUsers -and $LastDisconnectedUsers.Count -gt 0) {
                $disconnectedUsers = @($LastDisconnectedUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            }

            $payload = [ordered]@{
                DeferredCount           = $DeferredCount
                LastDecision            = $LastDecision
                LastReason              = $LastReason
                LastRunTime             = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                RebootForced            = $RebootForced
                LastSessionsTotal       = $normalizedSessions.Count
                LastActiveUsers         = @($activeUsers)
                LastDisconnectedUsers   = @($disconnectedUsers)
            } | ConvertTo-Json -Depth 5
            Set-Content -LiteralPath $script:StateFilePath -Value $payload -Encoding UTF8 -Force
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to write persistent restart state: $($_.Exception.Message)"
    }
}

function Reset-RestartState {
    param([object[]]$Sessions = @())
    Save-RestartState -DeferredCount 0 -LastDecision 'Authorized' -LastReason 'Restart authorized' -RebootForced $true -Sessions $Sessions
}

function Write-RestartPolicySummary {
    param(
        [string]$Decision,
        [string]$Reason,
        [int]$ActiveCount,
        [int]$DisconnectedCount,
        [int]$TotalSessions
    )
    Write-Log -Level INFO -Message "FINAL SUMMARY - Server restart policy: Decision='$Decision' | Reason='$Reason' | TotalSessions=$TotalSessions | ActiveSessions=$ActiveCount | DisconnectedSessions=$DisconnectedCount | State='$script:StateFilePath' | ForcedRestart=$ForceReboot"
}

function Clear-RebootFallbackTask {
    $taskName = $script:RebootFallbackTaskName
    $taskPath = '\'
    try {
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
        if ($null -ne $existing) {
            Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
            Write-Log -Level INFO -Message "Previous restart fallback task removed: ${taskPath}${taskName}."
        }
    } catch {
        Write-Log -Level WARN -Message "Failed to remove the previous restart fallback task: $($_.Exception.Message)"
    }
}

function Register-RebootFallbackTask {
    param(
        [Parameter(Mandatory)][int]$DelaySeconds,
        [Parameter(Mandatory)][string]$Reason
    )

    $taskName = $script:RebootFallbackTaskName
    $taskPath = '\'
    $runAt = (Get-Date).AddSeconds($DelaySeconds)
    $fallbackComment = 'SCRIPTGUY fallback: forced server restart to complete automated maintenance.'

    try {
        Clear-RebootFallbackTask

        $shutdownExe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        $taskArgument = "/r /f /t 0 /c `"$fallbackComment`""
        $action = New-ScheduledTaskAction -Execute $shutdownExe -Argument $taskArgument
        $trigger = New-ScheduledTaskTrigger -Once -At $runAt
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal

        Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task -Force -ErrorAction Stop | Out-Null
        Write-Log -Level INFO -Message "Local restart fallback task registered for $($runAt.ToString('yyyy-MM-dd HH:mm:ss')): ${taskPath}${taskName}. Reason: $Reason"
        return $true
    } catch {
        Write-Log -Level ERROR -Message "Failed to register the local restart fallback task: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-ForcedServerReboot {
    param(
        [Parameter(Mandatory)][int]$DelaySeconds,
        [Parameter(Mandatory)][string]$Reason
    )

    $shutdownExe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
    $comment = 'Server maintenance completed. A forced restart is required to finish repairs, policies, and Windows components.'
    $argumentString = ('/r /f /t {0} /c "{1}"' -f $DelaySeconds, $comment)

    Write-Log -Level INFO -Message "Preparing forced restart: $shutdownExe $argumentString"

    $fallbackDelay = [Math]::Max(($DelaySeconds + 60), 120)
    [void](Register-RebootFallbackTask -DelaySeconds $fallbackDelay -Reason 'Guarantee restart if shutdown.exe does not persist or is canceled by external interference.')

    try {
        $p = Start-Process -FilePath $shutdownExe -ArgumentList $argumentString -PassThru -Wait -WindowStyle Hidden -ErrorAction Stop
        $exitCode = $p.ExitCode
        if ($exitCode -eq 0) {
            Write-Log -Level INFO -Message "Forced restart command issued successfully. ExitCode=$exitCode | PID=$($p.Id) | Countdown=${DelaySeconds}s."
            return $true
        }

        Write-Log -Level ERROR -Message "shutdown.exe returned a nonzero exit code. ExitCode=$exitCode | PID=$($p.Id). The scheduled fallback remains active."
        return $false
    } catch {
        Write-Log -Level ERROR -Message "Failed to issue the forced restart command through shutdown.exe: $($_.Exception.Message). The scheduled fallback remains active."
        return $false
    }
}

function Invoke-RestartNotificationPolicy {
    param(
        [int]$IdleThresholdMinutes = $script:IdleThresholdMinutes,
        [int]$MaxDeferredRunsBeforeForcedReboot = $script:MaxDeferredRunsBeforeForcedReboot
    )

    $decision = Get-RebootDecision -IdleThresholdMinutes $IdleThresholdMinutes

    $allSessions          = @($decision.Sessions)
    $activeSessions       = @($allSessions | Where-Object { $_.IsActive })
    $disconnectedSessions = @($allSessions | Where-Object { $_.State -match '^(Disc|Disco|Disconnected|Descon)$' })

    Write-Log -Level INFO -Message "Total interpreted sessions: $($allSessions.Count) | Active sessions: $($activeSessions.Count) | Disconnected sessions: $($disconnectedSessions.Count)"

    $finalReason = $decision.Reason
    Reset-RestartState -Sessions $allSessions
    Write-Log -Level INFO -Message "Server restart policy: restart authorized even with an open session. Reason: $finalReason. Standard Windows notice in ${ShutdownNoticeSeconds}s."

    if ($SendUserNotices) {
        $msg = "Maintenance completed. This server will restart automatically in $([int]($ShutdownNoticeSeconds/60)) minute(s). Save any administrative work immediately."
        $rc = Send-MessageToAllSessions -Message $msg
        if ($rc -eq 0) {
            Write-Log -Level INFO -Message 'General restart notification sent before shutdown.'
        } else {
            Write-Log -Level INFO -Message "General restart notification was not delivered through msg.exe (rc=$rc). The primary visual notice remains the native shutdown.exe mechanism."
        }
    }

    if ($ForceReboot) {
        $rebootIssued = Invoke-ForcedServerReboot -DelaySeconds $ShutdownNoticeSeconds -Reason $finalReason
        if ($rebootIssued) {
            Write-Log -Level INFO -Message 'Open sessions were recorded for audit only and did not block the restart under the configured server policy.'
            Write-RestartPolicySummary -Decision 'Authorized' -Reason $finalReason -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count -TotalSessions $allSessions.Count
        } else {
            Write-Log -Level WARN -Message 'The primary restart command did not confirm success; the local fallback task remains the guarantee mechanism.'
            Write-RestartPolicySummary -Decision 'AuthorizedComFallback' -Reason $finalReason -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count -TotalSessions $allSessions.Count
        }
    } else {
        Write-Log -Level INFO -Message 'Restart will NOT be forced (FORCE_REBOOT=0).'
        Clear-RebootFallbackTask
        Write-RestartPolicySummary -Decision 'AuthorizedSemExecucao' -Reason $finalReason -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count -TotalSessions $allSessions.Count
    }
}


# ==================== Server inventory and cleanup ====================
function Invoke-ServerInventory {
    Write-Log -Level INFO -Message 'Basic inventory:'
    Write-LogSection -Title 'BASIC INVENTORY' -Body @"
HOSTNAME: $env:COMPUTERNAME
USER DOMAIN: $env:USERDOMAIN
USER: $env:USERNAME
OPERATING SYSTEM: Windows Server (detected)
"@
    [void](Invoke-LoggedCommand -CommandLine 'whoami' -Title 'WHOAMI')
    [void](Invoke-LoggedCommand -CommandLine 'ipconfig | findstr /i IPv4' -Title 'IPCONFIG (IPv4)')
}

function Invoke-PathRetentionCleanup {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][int]$RetentionDays
    )

    if (-not (Test-Path -LiteralPath $RootPath)) {
        Write-Log -Level INFO -Message "Folder not found: $RootPath"
        return
    }

    $removedFiles = 0
    $ignoredFiles = 0
    $failedFiles = 0
    $removedDirs = 0
    $failedDirs = 0
    $cutoff = (Get-Date).AddDays(-$RetentionDays)

    Get-ChildItem -LiteralPath $RootPath -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
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

    Get-ChildItem -LiteralPath $RootPath -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        ForEach-Object {
            try {
                $hasChildren = Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                if (-not $hasChildren) {
                    Remove-Item -LiteralPath $_.FullName -Force -Recurse -ErrorAction Stop
                    $removedDirs++
                }
            } catch {
                $failedDirs++
            }
        }

    Write-Log -Level INFO -Message "Retention cleanup with $RetentionDays day(s) completed in '$RootPath'. Files removed: $removedFiles | Files skipped: $ignoredFiles | File failures: $failedFiles | Folders removed: $removedDirs | Folder failures: $failedDirs"
}

function Invoke-ServerFolderCleanup {
    foreach ($path in $ServerCleanupPaths) {
        Invoke-PathRetentionCleanup -RootPath $path -RetentionDays $LogRetentionDays
    }
}

# ==================== Main ====================
try {
    Initialize-Log
    Invoke-PreValidation
    Set-Location -LiteralPath $script:LocalScriptRoot
    Test-LocalScriptSynchronization

    if (Test-RestartRegisteredThisBoot) {
        Write-Log -Level WARN -Message 'A forced restart was already registered during the current boot. Duplicate intensive maintenance and restart scheduling were skipped.'
        Write-Log -Level INFO -Message "===== END $ScriptName - WAITING_RESTART ====="
        exit 0
    }

    $domainFqdn    = Get-DomainFQDN
    $domainNetBIOS = Get-DomainNetBIOS
    $computerDn    = Get-ComputerDN

    Write-Log -Level INFO -Message "===== START $ScriptName v$ScriptVersion ====="
    Write-Log -Level INFO -Message "Current script source: $script:ExecutionSource"
    Write-Log -Level INFO -Message "Authoritative script: $script:ExpectedUncSource"
    Write-Log -Level INFO -Message "Expected local script: $script:LocalScriptPath"
    Write-Log -Level INFO -Message "Operational and local-state directory: $script:StateRoot"
    Write-Log -Level INFO -Message "Working directory for external commands: $env:WINDIR"
    Write-Log -Level INFO -Message "Computer DN: $computerDn"
    Write-Log -Level INFO -Message "Detected domain FQDN: $domainFqdn"
    Write-Log -Level INFO -Message "Detected domain NetBIOS name: $domainNetBIOS"
    Write-Log -Level INFO -Message "Scope: controlled cleanup with a minimum retention of $LogRetentionDays day(s) in: $($ServerCleanupPaths -join '; ') on production Windows Server systems."
    Write-Log -Level INFO -Message 'Policy: no security.inf; Group Policy cache reset; Windows Update component reset; forced server restart policy with open-session audit logging.'

    Invoke-TimedOperation -Name 'Inventory' -ScriptBlock { Invoke-ServerInventory }
    if ($RunSfcDism)    { Invoke-TimedOperation -Name 'SFC-DISM' -ScriptBlock { Invoke-SfcDism } }
    if ($ResetLocalGpo) { Invoke-TimedOperation -Name 'Reset GPO' -ScriptBlock { Reset-LocalGpoCache } }
    if ($CleanWuCache)  { Invoke-TimedOperation -Name 'WU' -ScriptBlock { Invoke-WuCacheCleanup } }
    if ($RunAdNetworkChecks -and $domainFqdn -ne 'WORKGROUP') { Invoke-TimedOperation -Name 'AD-Network' -ScriptBlock { Invoke-RedeAd -DomainForNltest $domainFqdn } }
    if ($RunCertutilPulse -or $RunGpupdateComputerOnly) { Invoke-TimedOperation -Name 'Policies-Certificates' -ScriptBlock { Invoke-Policies } }
    if ($RunAdNetworkChecks) { Invoke-TimedOperation -Name 'Network Summary' -ScriptBlock { Invoke-NetworkSummary -Fqdn $domainFqdn -NetBIOS $domainNetBIOS } }
    Invoke-TimedOperation -Name 'Folder Cleanup' -ScriptBlock { Invoke-ServerFolderCleanup }
    Invoke-TimedOperation -Name 'Forced Restart' -ScriptBlock { Invoke-RestartNotificationPolicy -IdleThresholdMinutes $script:IdleThresholdMinutes -MaxDeferredRunsBeforeForcedReboot $script:MaxDeferredRunsBeforeForcedReboot }

    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 0
} catch {
    Write-Log -Level ERROR -Message "Unhandled critical failure: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 1
}

# End of script
