<#
.SYNOPSIS
    PowerShell script for updating workstation software via winget using Computer GPO, without interactive console windows for ordinary users.

.DESCRIPTION
    This enterprise-grade script automates software updates across Windows 10/11 workstations using winget.exe, with deployment managed through Group Policy (GPO).

    Main features:
    - Preferentially runs in 64-bit Windows PowerShell;
    - Uses ProcessStartInfo with CreateNoWindow=True and WindowStyle=Hidden for no-console execution;
    - Resolves the real winget.exe path, including Desktop App Installer locations;
    - Applies jitter to reduce simultaneous execution peaks across many workstations;
    - Uses a global mutex to prevent local concurrent executions;
    - Uses an HKLM execution stamp to avoid repeated GPO-triggered runs within the configured interval;
    - Updates winget sources and silently upgrades compatible packages;
    - Captures stdout/stderr asynchronously without Start-Process and without -NoNewWindow;
    - Sanitizes progress bars, spinners, redraw-only lines, ANSI sequences, and control characters before writing logs;
    - Uses a single log file under C:\Logs-TEMP, following the older script convention;
    - Avoids breaking GPO execution because of individual winget failures;
    - Records LastRun, LastExitCode, and LastRunResult in HKLM.

.NOTES
    winget has known limitations when running as SYSTEM, especially on machines where Desktop App Installer is not available for the system context.
    This script attempts to resolve the winget binary directly from WindowsApps, but operational availability still depends on the local App Installer/winget installation state.

    Recommended Computer GPO execution command:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Path\winget-update-wks-apps.ps1"

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: May 13, 2026
    2026-05-13-v2.0.5-PRODUCTION-USAEN-WINDOWSAPPS-RESOLUTION-HOTFIX
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 720)]
    [int]$RunIntervalHours = 24,

    [ValidateRange(0, 3600)]
    [int]$JitterMaxSeconds = 180,

    [ValidateRange(10, 2000)]
    [int]$TailOutLines = 150,

    [ValidateRange(10, 1000)]
    [int]$TailErrLines = 100,

    [ValidateNotNullOrEmpty()]
    [string]$LogDir = 'C:\Logs-TEMP',

    [switch]$ForceRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

try {
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $script:Utf8NoBom
    [Console]::InputEncoding  = $script:Utf8NoBom
} catch {
    $script:Utf8NoBom = [System.Text.Encoding]::UTF8
}

$script:ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($script:ScriptName)) {
    $script:ScriptName = 'winget-update-wks-apps'
}

$script:LogFile = Join-Path -Path $LogDir -ChildPath ("{0}.log" -f $script:ScriptName)
$script:Mutex = $null
$script:ExitCode = 0
$script:StampKey = 'HKLM:\SOFTWARE\SCRIPTGUY\WingetUpdate'

function Initialize-LogDirectory {
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        try {
            $fallbackDir = Join-Path -Path $env:ProgramData -ChildPath 'SCRIPTGUY\Scripts-LOGS'
            if (-not (Test-Path -LiteralPath $fallbackDir)) {
                New-Item -Path $fallbackDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            $script:LogFile = Join-Path -Path $fallbackDir -ChildPath ("{0}.log" -f $script:ScriptName)
        } catch {
            # Logging must never block script completion in the GPO context.
        }
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}{3}' -f $timestamp, $Level, $Message, [Environment]::NewLine

    try {
        [System.IO.File]::AppendAllText($script:LogFile, $line, $script:Utf8NoBom)
    } catch {
        # Avoids any console dependency during hidden GPO execution.
    }
}

function ConvertTo-SafeLogText {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ''
    }

    $safe = $Text

    # Removes ANSI/VT sequences and OSC terminal-control sequences.
    $safe = $safe -replace "`e\][^`a]*(?:`a|`e\\)", ''
    $safe = $safe -replace "`e\[[0-9;?]*[ -/]*[@-~]", ''

    # Normalizes CR-only redraw operations emitted by command-line progress renderers.
    $safe = $safe -replace "`r(?!`n)", "`n"

    # Removes non-printable controls while preserving TAB/LF/CR.
    $safe = $safe -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''

    # Removes Unicode block characters commonly used by winget progress bars.
    $safe = $safe -replace '[\u2580-\u259F]+', ''

    return $safe.TrimEnd()
}

function Get-LastUsefulLines {
    param(
        [AllowNull()]
        [string]$Text,

        [ValidateRange(1, 5000)]
        [int]$Count = 150
    )

    $safeText = ConvertTo-SafeLogText -Text $Text
    if ([string]::IsNullOrWhiteSpace($safeText)) {
        return ''
    }

    $lines = New-Object System.Collections.Generic.List[string]

    foreach ($rawLine in @($safeText -split "\r?\n")) {
        $line = ConvertTo-SafeLogText -Text ([string]$rawLine)
        $line = $line.TrimEnd()

        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        # Removes isolated winget spinner frames: -, \, |, /.
        if ($line -match '^\s*[-\\\|/]\s*$') {
            continue
        }

        # Removes numeric redraw lines containing only progress percentage.
        if ($line -match '^\s*\d{1,3}\s*%\s*$') {
            continue
        }

        # Removes size/progress redraw lines with no useful package or context text.
        if ($line -match '^\s*[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB)\s*/\s*[0-9]+(?:\.[0-9]+)?\s*(?:B|KB|MB|GB)\s*$') {
            continue
        }

        # Removes residual lines made only of progress/spinner punctuation and spaces.
        if ($line -match '^\s*[\.·•=:_#\-\\\|/]+\s*$') {
            continue
        }

        [void]$lines.Add($line)
    }

    if ($lines.Count -eq 0) {
        return ''
    }

    return (($lines | Select-Object -Last $Count) -join [Environment]::NewLine)
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to verify administrative privileges: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Get-ScriptPathForRelaunch {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return $PSCommandPath
    }

    if ($MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return $MyInvocation.MyCommand.Path
    }

    return $null
}

function ConvertTo-NativeArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Argument
    )

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    return '"{0}"' -f ($Argument -replace '"', '\"')
}

function Invoke-HiddenProcess {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Arguments,

        [ValidateRange(30, 14400)]
        [int]$TimeoutSeconds = 7200,

        [string]$WorkingDirectory = $env:SystemRoot
    )

    $argumentString = (@($Arguments) | ForEach-Object { ConvertTo-NativeArgument -Argument ([string]$_) }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $argumentString
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    try {
        $psi.StandardOutputEncoding = $script:Utf8NoBom
        $psi.StandardErrorEncoding = $script:Utf8NoBom
    } catch {
        # Older .NET/PowerShell hosts may not expose these properties. Continue with the default pipe encoding.
    }

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory) -and (Test-Path -LiteralPath $WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }

    try {
        if ($psi.EnvironmentVariables.ContainsKey('WT_SESSION')) {
            $psi.EnvironmentVariables.Remove('WT_SESSION')
        }
        $psi.EnvironmentVariables['TERM'] = 'dumb'
        $psi.EnvironmentVariables['NO_COLOR'] = '1'
        $psi.EnvironmentVariables['CI'] = 'true'
        $psi.EnvironmentVariables['DOTNET_CLI_CONTEXT_ANSI_PASS_THRU'] = 'false'
        $psi.EnvironmentVariables['WINGET_DISABLE_INTERACTIVE'] = '1'
        $psi.EnvironmentVariables['WINGET_DISABLE_ANIMATION'] = '1'
    } catch {}

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try { $process.Kill() } catch {}
            try { $process.WaitForExit(5000) | Out-Null } catch {}
            return [pscustomobject]@{
                ExitCode = 124
                TimedOut  = $true
                StdOut    = ''
                StdErr    = 'Process timeout exceeded; the process was terminated.'
            }
        }

        try { $process.WaitForExit() } catch {}

        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            TimedOut  = $false
            StdOut    = [string]$stdoutTask.Result
            StdErr    = [string]$stderrTask.Result
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 1
            TimedOut  = $false
            StdOut    = ''
            StdErr    = $_.Exception.Message
        }
    } finally {
        try { $process.Dispose() } catch {}
    }
}

function Invoke-SelfAsPowerShell64 {
    if ([Environment]::Is64BitProcess) {
        return $false
    }

    $ps64 = Join-Path -Path $env:SystemRoot -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Get-ScriptPathForRelaunch

    if (-not (Test-Path -LiteralPath $ps64) -or [string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath)) {
        Write-Log -Level 'WARN' -Message '64-bit PowerShell is not available or the script path could not be resolved. Continuing in the current process.'
        return $false
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $scriptPath,
        '-RunIntervalHours', $RunIntervalHours,
        '-JitterMaxSeconds', $JitterMaxSeconds,
        '-TailOutLines', $TailOutLines,
        '-TailErrLines', $TailErrLines,
        '-LogDir', $LogDir
    )

    if ($ForceRun.IsPresent) {
        $arguments += '-ForceRun'
    }

    Write-Log -Message 'Relaunching the script in 64-bit PowerShell via SysNative, without a console window.'
    $result = Invoke-HiddenProcess -FilePath $ps64 -Arguments $arguments -TimeoutSeconds 14400 -WorkingDirectory $env:SystemRoot
    $script:ExitCode = [int]$result.ExitCode

    $out = Get-LastUsefulLines -Text $result.StdOut -Count 20
    $err = Get-LastUsefulLines -Text $result.StdErr -Count 20
    if (-not [string]::IsNullOrWhiteSpace($out)) { Write-Log -Message ("64-bit relaunch STDOUT:{0}{1}" -f [Environment]::NewLine, $out) }
    if (-not [string]::IsNullOrWhiteSpace($err)) { Write-Log -Level 'WARN' -Message ("64-bit relaunch STDERR:{0}{1}" -f [Environment]::NewLine, $err) }

    return $true
}

function Initialize-Mutex {
    $mutexName = 'Global\SCRIPTGUY_WingetUpdate_WKS_Mutex'
    $created = $false

    try {
        $script:Mutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$created)
        if (-not $created) {
            Write-Log -Level 'WARN' -Message 'Another local instance is already running. Exiting to prevent concurrency.'
            return $false
        }
        return $true
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to create the global mutex. Continuing without guaranteed local exclusion. Error: {0}" -f $_.Exception.Message)
        return $true
    }
}

function Release-MutexSafe {
    if ($null -eq $script:Mutex) {
        return
    }

    try {
        $script:Mutex.ReleaseMutex() | Out-Null
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to release mutex: {0}" -f $_.Exception.Message)
    } finally {
        try { $script:Mutex.Dispose() } catch {}
        $script:Mutex = $null
    }
}

function Initialize-StampKey {
    try {
        if (-not (Test-Path -LiteralPath $script:StampKey)) {
            New-Item -Path $script:StampKey -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to create/access the HKLM control key: {0}" -f $_.Exception.Message)
    }
}

function Test-RunIntervalAllowed {
    if ($ForceRun.IsPresent) {
        Write-Log -Message 'ForceRun was specified. Skipping interval control.'
        return $true
    }

    try {
        $props = Get-ItemProperty -Path $script:StampKey -ErrorAction SilentlyContinue
        if ($null -eq $props -or -not ($props.PSObject.Properties.Name -contains 'LastRun')) {
            return $true
        }

        $lastRunText = [string]$props.LastRun
        if ([string]::IsNullOrWhiteSpace($lastRunText)) {
            return $true
        }

        $lastRun = [datetime]::Parse($lastRunText, [Globalization.CultureInfo]::InvariantCulture)
        $nextAllowed = $lastRun.AddHours($RunIntervalHours)

        if ((Get-Date) -lt $nextAllowed) {
            Write-Log -Message ("Last run recorded at {0}. Next allowed run after {1}. Exiting." -f $lastRun.ToString('yyyy-MM-dd HH:mm:ss'), $nextAllowed.ToString('yyyy-MM-dd HH:mm:ss'))
            return $false
        }

        return $true
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to validate the execution interval. Proceeding for operational safety. Error: {0}" -f $_.Exception.Message)
        return $true
    }
}

function Set-RunStamp {
    param(
        [Parameter(Mandatory = $true)]
        [int]$NativeExitCode,

        [Parameter(Mandatory = $true)]
        [string]$Result
    )

    try {
        $now = (Get-Date).ToString('s', [Globalization.CultureInfo]::InvariantCulture)
        New-ItemProperty -Path $script:StampKey -Name 'LastRun' -Value $now -PropertyType String -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $script:StampKey -Name 'LastExitCode' -Value $NativeExitCode -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $script:StampKey -Name 'LastRunResult' -Value $Result -PropertyType String -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to write execution stamp: {0}" -f $_.Exception.Message)
    }
}

function Start-JitterDelay {
    if ($JitterMaxSeconds -le 0) {
        Write-Log -Message 'Jitter disabled.'
        return
    }

    try {
        $delay = Get-Random -Minimum 1 -Maximum ($JitterMaxSeconds + 1)
        Write-Log -Message ("Applying jitter of {0}s to reduce simultaneous execution." -f $delay)
        Start-Sleep -Seconds $delay
    } catch {
        Write-Log -Level 'WARN' -Message ("Failed to apply jitter: {0}" -f $_.Exception.Message)
    }
}

function Resolve-WingetPath {
    $candidateList = New-Object System.Collections.Generic.List[string]

    try {
        $cmd = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
        if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
            [void]$candidateList.Add($cmd.Source)
        }
    } catch {}

    # Fast Desktop App Installer resolution.
    # Avoids broad recursive enumeration under C:\Program Files\WindowsApps, which can be slow and permission-sensitive.
    $windowsApps = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsApps'
    if (Test-Path -LiteralPath $windowsApps) {
        try {
            $desktopAppInstallerFolders = @(Get-ChildItem -Path $windowsApps -Directory -Filter 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe' -ErrorAction SilentlyContinue |
                Sort-Object -Property LastWriteTime -Descending)

            foreach ($folder in $desktopAppInstallerFolders) {
                $candidatePath = Join-Path -Path $folder.FullName -ChildPath 'winget.exe'
                if (Test-Path -LiteralPath $candidatePath) {
                    [void]$candidateList.Add($candidatePath)
                }
            }
        } catch {
            Write-Log -Level 'WARN' -Message ("Error while resolving Desktop App Installer folders under WindowsApps: {0}" -f $_.Exception.Message)
        }
    }

    # Per-user WindowsApps fallback. Useful when the script is executed in an interactive administrative user context.
    try {
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $userWinget = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
            [void]$candidateList.Add($userWinget)
        }
    } catch {}

    foreach ($candidatePath in @($candidateList | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($candidatePath) -and (Test-Path -LiteralPath $candidatePath)) {
            return $candidatePath
        }
    }

    return $null
}

function Invoke-WingetCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WingetPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StepName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Arguments,

        [ValidateRange(30, 14400)]
        [int]$TimeoutSeconds = 7200
    )

    $cleanArgs = @($Arguments | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
    if ($cleanArgs.Count -eq 0) {
        Write-Log -Level 'ERROR' -Message ("No valid argument was provided for step '{0}'." -f $StepName)
        return 1
    }

    $argumentString = ($cleanArgs | ForEach-Object { ConvertTo-NativeArgument -Argument $_ }) -join ' '
    Write-Log -Message ("Executing step '{0}' without a console window: `"{1}`" {2}" -f $StepName, $WingetPath, $argumentString)

    $result = Invoke-HiddenProcess -FilePath $WingetPath -Arguments $cleanArgs -TimeoutSeconds $TimeoutSeconds -WorkingDirectory $env:SystemRoot

    if ($result.TimedOut) {
        Write-Log -Level 'ERROR' -Message ("Step '{0}' exceeded timeout of {1}s and was terminated." -f $StepName, $TimeoutSeconds)
    }

    $exit = [int]$result.ExitCode
    if ($exit -eq 0) {
        Write-Log -Message ("Step '{0}' completed with ExitCode=0." -f $StepName)
    } else {
        Write-Log -Level 'WARN' -Message ("Step '{0}' completed with ExitCode={1}." -f $StepName, $exit)
    }

    $stdoutTail = Get-LastUsefulLines -Text $result.StdOut -Count $TailOutLines
    if (-not [string]::IsNullOrWhiteSpace($stdoutTail)) {
        Write-Log -Message ("Sanitized STDOUT from step '{0}' - last {1} lines:{2}{3}" -f $StepName, $TailOutLines, [Environment]::NewLine, $stdoutTail)
    }

    $stderrTail = Get-LastUsefulLines -Text $result.StdErr -Count $TailErrLines
    if (-not [string]::IsNullOrWhiteSpace($stderrTail)) {
        Write-Log -Level 'WARN' -Message ("Sanitized STDERR from step '{0}' - last {1} lines:{2}{3}" -f $StepName, $TailErrLines, [Environment]::NewLine, $stderrTail)
    }

    return $exit
}

Initialize-LogDirectory
Write-Log -Message ('========== START: {0} ==========' -f $script:ScriptName)
Write-Log -Message 'Version: 2026-05-13-v2.0.5-PRODUCTION-USAEN-WINDOWSAPPS-RESOLUTION-HOTFIX'
Write-Log -Message ("LogFile: {0}" -f $script:LogFile)
Write-Log -Message ("User/context: {0}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Log -Message ("PowerShell: {0}; 64-bit process: {1}" -f $PSVersionTable.PSVersion.ToString(), [Environment]::Is64BitProcess)

try {
    if (Invoke-SelfAsPowerShell64) {
        Write-Log -Message ('64-bit process completed with ExitCode={0}.' -f $script:ExitCode)
        exit $script:ExitCode
    }

    if (-not (Test-IsAdministrator)) {
        Write-Log -Level 'WARN' -Message 'Non-administrative context detected. For Computer GPO, execution as NT AUTHORITY\SYSTEM is recommended.'
    }

    if ($MyInvocation.MyCommand.Path -like '\\*') {
        Write-Log -Level 'WARN' -Message 'Script executed from a UNC path. A local copy is recommended to reduce execution-policy failures and network unavailability.'
    }

    if (-not (Initialize-Mutex)) {
        exit 0
    }

    Initialize-StampKey

    if (-not (Test-RunIntervalAllowed)) {
        exit 0
    }

    Start-JitterDelay

    $wingetPath = Resolve-WingetPath
    if ([string]::IsNullOrWhiteSpace($wingetPath)) {
        Write-Log -Level 'ERROR' -Message 'winget.exe was not found. Verify Microsoft Desktop App Installer/App Installer and availability for the execution context.'
        Set-RunStamp -NativeExitCode 9009 -Result 'WINGET_NOT_FOUND'
        exit 0
    }

    Write-Log -Message ("winget.exe resolved at: {0}" -f $wingetPath)

    [void](Invoke-WingetCommand -WingetPath $wingetPath -StepName 'winget-version' -Arguments @('--version') -TimeoutSeconds 120)

    [void](Invoke-WingetCommand -WingetPath $wingetPath -StepName 'source-list' -Arguments @('source', 'list', '--disable-interactivity') -TimeoutSeconds 300)

    $codeSourceUpdate = Invoke-WingetCommand -WingetPath $wingetPath -StepName 'source-update' -Arguments @('source', 'update', '--disable-interactivity') -TimeoutSeconds 900

    $codeUpgradeList = Invoke-WingetCommand -WingetPath $wingetPath -StepName 'upgrade-list' -Arguments @(
        'upgrade',
        '--include-unknown',
        '--accept-source-agreements',
        '--disable-interactivity'
    ) -TimeoutSeconds 900

    $codeUpgrade = Invoke-WingetCommand -WingetPath $wingetPath -StepName 'upgrade-all' -Arguments @(
        'upgrade',
        '--all',
        '--include-unknown',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    ) -TimeoutSeconds 7200

    $highestExitCode = @($codeSourceUpdate, $codeUpgradeList, $codeUpgrade) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    if ($codeUpgrade -eq 0) {
        Write-Log -Message 'winget upgrade --all completed without an error reported by winget.'
        Set-RunStamp -NativeExitCode 0 -Result 'SUCCESS'
    } else {
        Write-Log -Level 'WARN' -Message ("winget upgrade --all completed with ExitCode={0}. Review the consolidated log." -f $codeUpgrade)
        Set-RunStamp -NativeExitCode ([int]$highestExitCode) -Result 'COMPLETED_WITH_WARNINGS'
    }

    $script:ExitCode = 0
} catch {
    $script:ExitCode = 0
    Write-Log -Level 'ERROR' -Message ("Unhandled failure: {0}" -f $_.Exception.Message)
    try { Set-RunStamp -NativeExitCode 1 -Result 'SCRIPT_ERROR' } catch {}
} finally {
    Release-MutexSafe
    Write-Log -Message ('========== END: {0}; ExitCode={1} ==========' -f $script:ScriptName, $script:ExitCode)
}

exit $script:ExitCode

# End of script
