#requires -Version 5.1
<#
.SYNOPSIS
Weekly Windows workstation maintenance.

.DESCRIPTION
PowerShell refactor of the original VBS workstation maintenance workflow, preserving the main operational logic:
- System integrity verification (SFC / DISM).
- Controlled local GPO cache reset.
- Controlled Windows Update component cleanup.
- AD / DC / time / Kerberos / certificate validation.
- Profile handling, default user avatar, spooler restart, and basic inventory.
- Controlled C:\Scripts-LOGS cleanup with minimum 7-day retention.
- Smart restart policy based on active user sessions and idle time.
- Persistent local restart state in C:\ProgramData\SCRIPTGUY\Maintenance-Workstations.
- Final user communication through msg.exe and shutdown.exe.

.AUTHOR
Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
2026.04.28-WKS-v1.3.3-ENTERPRISE-GITHUB-ENGLISH-PS51
#>


[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==================== Configuration ====================
$LogRetentionDays            = 7
$LogRetentionPath         = 'C:\Scripts-LOGS'
$LogDir                      = 'C:\Scripts-LOGS'
$ScriptName                  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$ScriptVersion               = '2026.04.28-WKS-v1.3.3-ENTERPRISE-GITHUB-ENGLISH-PS51'
$script:ExpectedExecutionSource = '\\headq.scriptguy\netlogon\system-maintenance-wks\system-maintenance-wks.ps1'
$script:ExecutionSource      = if ($MyInvocation.MyCommand.Path) { $MyInvocation.MyCommand.Path } else { $MyInvocation.MyCommand.Name }
$script:StateRoot            = 'C:\ProgramData\SCRIPTGUY\Maintenance-Workstations'
$script:StateFilePath        = Join-Path $script:StateRoot 'restart-state.json'
$script:IdleThresholdMinutes = 90
$script:MaxDeferredRunsBeforeForcedReboot = 3
$LogFile                     = Join-Path $LogDir "$ScriptName.log"
$PathSoftDist                = 'C:\Windows\SoftwareDistribution'
$PathCatroot2                = 'C:\Windows\System32\catroot2'
$DefaultUserImagePath        = 'C:\ProgramData\Microsoft\User Account Pictures\user.png'
$GpUpdateWaitSeconds         = 30
$CleanWuTimeoutSec           = 600
$RebootFinalDelaySec         = 0
$ShutdownNoticeSeconds       = 900

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
        Write-Log -Level INFO -Message "Expected GPO UNC source: $script:ExpectedExecutionSource"
    } catch {
        throw "Pre-validation failed for state directory '$script:StateRoot': $($_.Exception.Message)"
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

# ==================== Command Execution ====================
function Normalize-ExternalText {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $normalized = $Text -replace "`0", ''
    $normalized = $normalized -replace [char]0xFFFD, '?'
    $normalized = $normalized -replace "[\x00-\x08\x0B\x0C\x0E-\x1F]", ''
    return $normalized
}

function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][string]$CommandLine,
        [Parameter(Mandatory)][string]$Title,
        [int]$TimeoutSec = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:ComSpec"
    $psi.Arguments = "/c chcp 65001 >nul && $CommandLine"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

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
        Write-Log -Level WARN -Message "Command '$Title' returned rc=$($result.ExitCode)."
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
        Write-Log -Level INFO -Message "Pasta renomeada: $src -> $(Join-Path $parent $newName)"
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
    # - Computer DN and Domain FQDN are different values.
    # - Never return the full DN as the domain because nltest /dsgetdc:<DN> generates ERROR_INVALID_DOMAINNAME.

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
            Write-Log -Level WARN -Message "Failed to start $Name. current state: $state"
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
    Write-Log -Level WARN -Message "Could not stop $Name. Continuing."
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
        Write-Log -Level WARN -Message "SFC returned code $rc (duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    }

    Write-Log -Level INFO -Message 'Running DISM /RestoreHealth...'
    $t0 = Get-Date
    $rc = (Start-Process -FilePath "$env:windir\system32\dism.exe" -ArgumentList '/online','/cleanup-image','/restorehealth' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc -eq 0) {
        Write-Log -Level INFO -Message "DISM /restorehealth completed (rc=0, duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    } else {
        Write-Log -Level WARN -Message "DISM returned $rc (duration=$([int]((Get-Date)-$t0).TotalSeconds)s)."
    }
}

# ==================== GPO ====================
function Reset-LocalGpoCache {
    Remove-FolderIfExists -PathLiteral '%windir%\System32\GroupPolicy'
    Remove-FolderIfExists -PathLiteral '%windir%\System32\GroupPolicyUsers'
    Remove-FolderIfExists -PathLiteral '%windir%\SysWOW64\GroupPolicy'
    Remove-FolderIfExists -PathLiteral '%windir%\SysWOW64\GroupPolicyUsers'
    Write-Log -Level INFO -Message 'Local GPO cache removed (folders). No security.inf will be applied.'

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy'
    if (Test-Path -LiteralPath $key) {
        try {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
            Write-Log -Level INFO -Message 'Local GPO registry key removed.'
        } catch {
            Write-Log -Level WARN -Message "Failed to remove GPO registry key - $($_.Exception.Message)"
        }
    } else {
        Write-Log -Level INFO -Message 'Local GPO registry key not found (nothing to remove).'
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
                & schtasks.exe /change /tn $task $action *>> $LogFile
            } catch {}
        }
    }
    Write-Log -Level INFO -Message "WU tasks $label."
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
                    Write-Log -Level WARN -Message 'Failed to remove SoftwareDistribution. Trying rename...'
                    Rename-IfExists -PathLiteral '%SystemRoot%\SoftwareDistribution'
                }
            } else {
                Write-Log -Level INFO -Message 'Pasta SoftwareDistribution not found.'
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
                    Write-Log -Level WARN -Message 'Failed to remove catroot2. Trying rename...'
                    Rename-IfExists -PathLiteral $PathCatroot2
                }
            } else {
                Write-Log -Level INFO -Message 'catroot2 not found (pular).'
            }
        }
    } else {
        Write-Log -Level ERROR -Message '[WU] Block timeout. Aborting cleanup and re-enabling services/tasks.'
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
        Write-Log -Level INFO -Message 'Trusted root certificate synchronization DISABLED by institutional policy.'
        return
    }
    Write-Log -Level INFO -Message 'Sincronizando certificados raiz via Windows Update...'
    $rc1 = (Start-Process -FilePath certutil.exe -ArgumentList '-setreg','chain\ChainCacheResyncFiletime','@now' -Wait -PassThru -WindowStyle Hidden).ExitCode
    $rc2 = (Start-Process -FilePath certutil.exe -ArgumentList '-f','-verifyCTL','AuthRoot' -Wait -PassThru -WindowStyle Hidden).ExitCode
    $rc3 = (Start-Process -FilePath certutil.exe -ArgumentList '-syncWithWU' -Wait -PassThru -WindowStyle Hidden).ExitCode
    if ($rc1 -eq 0 -and $rc2 -eq 0 -and $rc3 -eq 0) {
        Write-Log -Level INFO -Message 'Certificate synchronization completed.'
    } else {
        Write-Log -Level WARN -Message "Certificate synchronization completed with warnings (rc setreg=$rc1, verifyCTL=$rc2, syncWithWU=$rc3)."
    }
}

# ==================== Rede / AD ====================
function Invoke-KerberosPurgeAllSessions {
    [void](Invoke-CapturedCommand -CommandLine "$env:windir\System32\klist.exe -li 0x3e7 purge" -Title 'KLIST PURGE (SYSTEM 0x3e7)')
    [void](Invoke-CapturedCommand -CommandLine "$env:windir\System32\klist.exe purge" -Title 'KLIST PURGE (Session Atual)')

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

    Write-Log -Level INFO -Message "Validating DC '$DomainForNltest'..."
    [void](Invoke-LoggedCommand -CommandLine "nltest /dsgetdc:$DomainForNltest" -Title 'NLTEST /DSGETDC')

    Write-Log -Level INFO -Message 'Resynchronizing time with the DC...'
    [void](Invoke-LoggedCommand -CommandLine 'w32tm /resync' -Title 'W32TM /RESYNC')

    Write-Log -Level INFO -Message 'Purging Kerberos tickets (all sessions)...'
    Invoke-KerberosPurgeAllSessions
}

# ==================== Policys ====================
function Invoke-GpupdateComputerOnly {
    $result = Invoke-CapturedCommand -CommandLine "gpupdate /target:computer /force /wait:$GpUpdateWaitSeconds" -Title "GPUPDATE COMPUTER (/wait:$GpUpdateWaitSeconds)" -TimeoutSec ($GpUpdateWaitSeconds + 10)
    if ($result.ExitCode -ne 0) {
        Write-Log -Level WARN -Message "Computer GPUPDATE did not complete within the expected time (rc=$($result.ExitCode)). Forcing synchronous processing at the next boot."
        [void](Invoke-CapturedCommand -CommandLine 'reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v SyncForegroundPolicy /t REG_DWORD /d 1 /f' -Title 'Enable SyncForegroundPolicy')
    }
}

function Invoke-Policies {
    if ($RunCertutilPulse) {
        Write-Log -Level INFO -Message 'Updating internal CA chain (certutil -pulse)...'
        [void](Invoke-LoggedCommand -CommandLine 'certutil -pulse' -Title 'CERTUTIL -PULSE')
    }
    if ($RunGpupdateComputerOnly) {
        Write-Log -Level INFO -Message 'Running computer gpupdate with short wait...'
        Invoke-GpupdateComputerOnly
    } else {
        Write-Log -Level INFO -Message 'Computer gpupdate DISABLED by configuration.'
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
            Write-Log -Level INFO -Message "Arquivo .dat removido: $($_.Name)"
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
        Write-Log -Level WARN -Message "Failed to configure default image - $($_.Exception.Message)"
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

# ==================== Log Retention ====================
function Invoke-LogsRetention {
    $root = $LogRetentionPath
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Log -Level INFO -Message "Folder not found for log retention: $root"
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

    Write-Log -Level INFO -Message "Cleanup with retention of $LogRetentionDays day(s) completed in '$root'. Files removed: $removedFiles | Files skipped: $ignoredFiles | File failures: $failedFiles | Folders removed: $removedDirs | Folder failures: $failedDirs"
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
        Write-Log -Level INFO -Message 'Cleaning %TEMP% for the current context (SYSTEM/current process) (best-effort)...'
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
    Write-Log -Level INFO -Message "Domain FQDN (detected): $Fqdn"
    Write-Log -Level INFO -Message "NetBIOS domain: $NetBIOS"

    $r = Invoke-CapturedCommand -CommandLine "nltest /dsgetdc:$NetBIOS" -Title 'NLTEST /DSGETDC (NetBIOS)'
    if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "NLTEST failed (NetBIOS) rc=$($r.ExitCode)." }

    if ($Fqdn -ne 'WORKGROUP' -and $Fqdn.Contains('.')) {
        $r = Invoke-CapturedCommand -CommandLine "nltest /dsgetdc:$Fqdn" -Title 'NLTEST /DSGETDC (FQDN)'
        if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "NLTEST failed (FQDN) rc=$($r.ExitCode)." }
    }

    $r = Invoke-CapturedCommand -CommandLine 'w32tm /query /status' -Title 'W32TM STATUS'
    if ($r.ExitCode -ne 0) { Write-Log -Level WARN -Message "W32TM STATUS failed rc=$($r.ExitCode)." }
    Write-Log -Level INFO -Message '===== END NETWORK SUMMARY ====='
}

# ==================== Sessions / Notifications ====================
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
        if ($combinedSessionOutput -match '(?i)(no user|nao existe nenhum usuario|no user exists|no users exist)') {
            # Valid condition on a workstation with no logged-on user.
            # In v1.3.1 this was treated as a failure; in v1.3.2 it authorizes the normal reboot policy.
            $result.QueryOk = $true
            $result.ParseOk = $true
            $result.Reason  = 'No user session present.'
            if ($cmd.StdErr) {
                Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd()
            }
            Write-Log -Level INFO -Message 'QUSER reported no logged-on users. Condition interpreted as no active session.'
            return [pscustomobject]$result
        }

        if (-not $result.QueryOk) {
            $result.Reason = 'quser did not return usable stdout.'
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
            $result.Reason = 'Unable to parse quser output.'
        }

        if ($result.ActiveUsers.Count -gt 0) {
            $result.HasActive = $true
            $result.ActiveCount = @($result.ActiveUsers | Sort-Object -Unique).Count
            Write-LogSection -Title 'QUERY USER (ACTIVE MATCH)' -Body $cmd.StdOut.TrimEnd()
        } elseif ($cmd.StdOut) {
            Write-LogSection -Title 'QUERY USER (STDOUT)' -Body $cmd.StdOut.TrimEnd()
        }

        if ($cmd.ExitCode -ne 0 -and -not $result.ParseOk) {
            Write-Log -Level WARN -Message "'query user' returned rc=$($cmd.ExitCode) without reliable output parsing."
            if ($cmd.StdErr) { Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd() }
        } elseif ($cmd.ExitCode -ne 0) {
            Write-Log -Level WARN -Message "'query user' returned rc=$($cmd.ExitCode), but usable output was returned; continuing with result parsing."
            if ($cmd.StdErr) { Write-LogSection -Title 'QUERY USER (STDERR)' -Body $cmd.StdErr.TrimEnd() }
        }
    } catch {
        $result.Reason = $_.Exception.Message
        Write-Log -Level WARN -Message "Failed to run 'query user' - $($_.Exception.Message)"
    }

    [pscustomobject]$result
}

function Get-RebootDecision {
    param([int]$IdleThresholdMinutes = 90)

    $sessionInfo = Get-LoggedOnSessions

    if (-not $sessionInfo.QueryOk -or -not $sessionInfo.ParseOk) {
        $reason = if ($sessionInfo.Reason) { $sessionInfo.Reason } else { 'Session detection failed.' }
        Write-Log -Level WARN -Message "Restart policy: failed to query/parse user sessions. Restart deferred for safety. Reason: $reason"
        return [pscustomobject]@{
            AllowReboot = $false
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
        Write-Log -Level INFO -Message ("Session active detectada: User='{0}', Session='{1}', ID={2}, State='{3}', Idle='{4}', IdleMin={5}" -f `
            $session.UserName, $session.SessionName, $session.SessionId, $session.State, $session.IdleText, $session.IdleMinutes)
    }

    $blockingSessions = @($activeSessions | Where-Object { $_.IdleMinutes -lt $IdleThresholdMinutes })
    if ($blockingSessions.Count -gt 0) {
        $users = ($blockingSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
        Write-Log -Level INFO -Message ("Restart policy: active sessions exist below the idle threshold ({0} min). Restart blocked. User(s): {1}" -f $IdleThresholdMinutes, $users)
        return [pscustomobject]@{
            AllowReboot = $false
            Reason      = "Active session below idle threshold (${IdleThresholdMinutes} min)"
            ActiveUsers = @($blockingSessions)
            Sessions    = @($activeSessions)
        }
    }

    $users2 = ($activeSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
    Write-Log -Level INFO -Message ("Policy of restart: all active sessions have been idle for at least {0} minute(s). Restart authorized. User(s): {1}" -f $IdleThresholdMinutes, $users2)
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
    $usersText = if ($Users -and $Users.Count -gt 0) { ($Users | Sort-Object -Unique) -join ', ' } else { 'user logado' }
    return @"
Maintenance completed on this workstation.
An active session is in use for: $usersText.
The automatic restart was deferred for safety.
The workstation will only restart automatically when there is no active session, or when idle time reaches at least $IdleThresholdMinutes minute(s).
Save your work and restart manually as soon as possible.
"@
}

function Ensure-StateStore {
    try {
        if (-not (Test-Path -LiteralPath $script:StateRoot)) {
            New-Item -Path $script:StateRoot -ItemType Directory -Force | Out-Null
        }
        return $true
    } catch {
        Write-Log -Level WARN -Message "Failed to prepare state directory '$script:StateRoot': $($_.Exception.Message)"
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
        [int]$IdleThresholdMinutes = $script:IdleThresholdMinutes,
        [int]$MaxDeferredRunsBeforeForcedReboot = $script:MaxDeferredRunsBeforeForcedReboot
    )

    $state = Get-RestartState
    $decision = Get-RebootDecision -IdleThresholdMinutes $IdleThresholdMinutes

    $allSessions         = @($decision.Sessions)
    $activeSessions      = @($allSessions | Where-Object { $_.IsActive })
    $disconnectedSessions = @($allSessions | Where-Object { $_.State -match '^(Disc|Disconnected|Descon)$' })

    Write-Log -Level INFO -Message "Total interpreted sessions: $($allSessions.Count) | Active sessions: $($activeSessions.Count) | Disconnected sessions: $($disconnectedSessions.Count)"

    if ($disconnectedSessions.Count -gt 0) {
        $discUsers = ($disconnectedSessions | ForEach-Object { $_.UserName } | Sort-Object -Unique) -join ', '
        Write-Log -Level INFO -Message "Disconnected sessions detected (do not block restart by themselves): $discUsers"
    }

    $forceByDeferredPolicy = $false
    if (-not $decision.AllowReboot) {
        $newDeferredCount = [int]$state.DeferredCount + 1
        Save-RestartState -DeferredCount $newDeferredCount -LastDecision 'Adiado' -LastReason $decision.Reason -LastActiveUsers ($activeSessions | ForEach-Object { $_.UserName })
        Write-Log -Level INFO -Message "Restart deferred. Reason: $($decision.Reason). Deferral counter: $newDeferredCount/$MaxDeferredRunsBeforeForcedReboot"

        if ($newDeferredCount -ge $MaxDeferredRunsBeforeForcedReboot -and $activeSessions.Count -eq 0) {
            $forceByDeferredPolicy = $true
            Write-Log -Level WARN -Message "Deferral limit reached and there is no active session. Restart will be authorized by accumulated pending policy."
        } elseif ($newDeferredCount -ge $MaxDeferredRunsBeforeForcedReboot -and $activeSessions.Count -gt 0) {
            Write-Log -Level WARN -Message 'Deferral limit reached, but an active session is still present. Restart will remain blocked for safety until there is no active session.'
        }

        if (-not $forceByDeferredPolicy) {
            if ($SendUserNotices -and $activeSessions.Count -gt 0) {
                $notice = Build-DeferredRestartMessage -Users ($activeSessions | ForEach-Object { $_.UserName }) -IdleThresholdMinutes $IdleThresholdMinutes
                foreach ($sess in $activeSessions) {
                    $rc = Send-MessageToSession -SessionId $sess.SessionId -Message $notice
                    if ($rc -eq 0) {
                        Write-Log -Level INFO -Message "Deferred restart notification sent to session $($sess.SessionId) ($($sess.UserName))."
                    } else {
                        Write-Log -Level INFO -Message "Deferred restart notification was not delivered to session $($sess.SessionId) ($($sess.UserName)) (rc=$rc). Expected behavior in some SYSTEM-context executions; continuing without functional impact."
                    }
                }
            }
            Write-RestartPolicySummary -Decision 'Adiado' -Reason $decision.Reason -DeferredCount $newDeferredCount -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count
            return
        }
    }

    Reset-RestartState

    $finalReason = if ($forceByDeferredPolicy) { 'Accumulated pending policy with no active session' } else { $decision.Reason }
    Write-Log -Level INFO -Message "Restart policy: restart authorized. Reason: $finalReason. Standard Windows warning in ${ShutdownNoticeSeconds}s."

    if ($SendUserNotices) {
        $msg = "Maintenance completed. The workstation will restart automatically in $([int]($ShutdownNoticeSeconds/60)) minute(s). Save your work immediately."
        $rc = Send-MessageToAllSessions -Message $msg
        if ($rc -eq 0) {
            Write-Log -Level INFO -Message 'General restart notification sent before shutdown.'
        } else {
            Write-Log -Level INFO -Message "General restart notification was not delivered through msg.exe (rc=$rc). The primary visual warning will remain the native shutdown.exe mechanism."
        }
    }

    if ($ForceReboot) {
        $comment = 'Updates applied. Restart required to complete workstation maintenance.'
        $args = @('/r','/f','/t', [string]$ShutdownNoticeSeconds, '/c', $comment, '/d','p:2:4')
        $p = Start-Process -FilePath shutdown.exe -ArgumentList $args -PassThru -WindowStyle Hidden
        Write-Log -Level INFO -Message "Restart command executed with countdown of ${ShutdownNoticeSeconds}s. PID=$($p.Id)."
        if ($RebootFinalDelaySec -eq 0) {
            Write-Log -Level INFO -Message 'The primary visual warning is now the native shutdown.exe mechanism, which is more reliable than sequential msg.exe messages in SYSTEM context.'
        }
        Write-RestartPolicySummary -Decision 'Authorized' -Reason $finalReason -DeferredCount 0 -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count
    } else {
        Write-Log -Level INFO -Message 'Restart NOT will be forced (FORCE_REBOOT=0).'
        Write-RestartPolicySummary -Decision 'AuthorizedNoExecution' -Reason $finalReason -DeferredCount 0 -ActiveCount $activeSessions.Count -DisconnectedCount $disconnectedSessions.Count
    }
}

# ==================== Main ====================
try {
    Initialize-Log
    Invoke-PreValidation

    $domainFqdn    = Get-DomainFQDN
    $domainNetBIOS = Get-DomainNetBIOS
    $computerDn    = Get-ComputerDN

    Write-Log -Level INFO -Message "===== START $ScriptName v$ScriptVersion ====="
    Write-Log -Level INFO -Message "Computer DN: $computerDn"
    Write-Log -Level INFO -Message "Detected domain FQDN: $domainFqdn"
    Write-Log -Level INFO -Message "Detected NetBIOS domain: $domainNetBIOS"

    if ($RunSfcDism)              { Invoke-SfcDism }
    if ($ResetLocalGpo)           { Reset-LocalGpoCache }
    if ($CleanWuCache)            { Invoke-WuCacheCleanup }
    if ($RunAdNetworkChecks -and $domainFqdn -ne 'WORKGROUP') { Invoke-RedeAd -DomainForNltest $domainFqdn }
    if ($RunCertutilPulse -or $RunGpupdateComputerOnly) { Invoke-Policies }
    if ($CertSyncEnable)          { Invoke-CertSyncIfEnabled }

    Invoke-ProfileMaintenance
    Invoke-Infrastructure
    Invoke-NetworkSummary -Fqdn $domainFqdn -NetBIOS $domainNetBIOS
    Invoke-RestartNotificationPolicy -IdleThresholdMinutes $script:IdleThresholdMinutes -MaxDeferredRunsBeforeForcedReboot $script:MaxDeferredRunsBeforeForcedReboot

    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 0
} catch {
    Write-Log -Level ERROR -Message "Fatal failure: $($_.Exception.Message)"
    Write-Log -Level INFO -Message "===== END $ScriptName ====="
    exit 1
}

# End of script
