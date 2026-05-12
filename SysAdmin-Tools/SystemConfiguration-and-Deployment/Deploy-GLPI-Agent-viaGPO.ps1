<#
.SYNOPSIS
  Enterprise-grade idempotent GLPI Agent deployment through Machine GPO, with mandatory local artifact staging, deferred execution, and controlled inventory convergence.

.DESCRIPTION
  Stable enterprise deployment architecture based on the Bootstrap Online + Deferred Offline execution model.

  This script performs a lightweight bootstrap during Machine GPO processing, creates and validates the local staging structure, synchronizes the MSI installer and the current PowerShell script locally, recreates the deferred CMD launcher, and transfers installation or remediation workflows to a deferred local execution running under the SYSTEM context.

  This release preserves the validated production behavior from the stable Portuguese-BR version while fully generalizing paths, names, comments, configuration labels, and operational messages for broader enterprise deployment scenarios.

  The workflow includes:
  - Mandatory StageRoot creation and validation;
  - Mandatory synchronization of the MSI installer into the local staging directory;
  - Mandatory self-synchronization of the current PowerShell script into the local staging directory;
  - Automatic recreation of the deferred CMD launcher;
  - Robust GLPI Agent detection through:
      - Fixed baseline registry key;
      - Uninstall registry entries;
      - Known executable and wrapper paths;
  - Baseline version validation as the authoritative operational decision source;
  - Executable version tracking used strictly as diagnostic telemetry;
  - In-place reconfiguration when the expected baseline is already compliant and operational;
  - Corrective installation or repair only when real structural non-compliance is detected;
  - Enterprise managed configuration generation through a dedicated managed CFG file;
  - Inventory TAG resolution based on the machine DNS domain independently from the logged-on user context;
  - MSI execution from a local cache to reduce UNC dependency during installation and repair operations;
  - JSON state persistence for continuity between bootstrap and deferred execution stages;
  - Deferred execution lock control to prevent concurrent local convergence runs;
  - Structured UTF-8 logging for:
      - Main operational workflow;
      - MSI execution lifecycle;
      - Artifact synchronization;
      - Inventory convergence;
  - Scheduled Task creation, execution, and cleanup using schtasks.exe for maximum Windows PowerShell 5.1 compatibility;
  - Immediate inventory synchronization using glpi-agent.bat when available, with automatic fallback to known executable paths;
  - Stable and validated inventory trigger arguments:
      --force --logger=stderr
  - Automatic cleanup of deferred scheduled tasks after successful convergence;
  - Enterprise-safe idempotent behavior for repeated GPO Startup executions.

  Default paths and configuration values are intentionally generic and should be customized according to each organization's operational standards before production deployment.

.AUTHOR
    Luiz Hamilton Silva (@brazilianscriptguy)

.VERSION
  2026-05-12-v5.1.6-ENTERPRISE-STABLE-ARTIFACT-STAGING-CONVERGENCE-USA-EN
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallerFileName = 'glpi-agent-install.msi',

    [Parameter()]
    [string]$SourceInstallerPath = '\\headq.scriptguy\netlogon\glpi-agent-install\glpi-agent116-install.msi',

    [Parameter()]
    [string]$LogDirectory = 'C:\Logs-TEMP',

    [Parameter()]
    [string]$ExpectedVersion = '1.17',

    [Parameter()]
    [string]$ServerUrl = 'http://cmdb.headq.scriptguy/front/inventory.php',

    [Parameter()]
    [string]$HttpdTrust = '127.0.0.1,10.0.0.0/8',

    [Parameter()]
    [int]$DelayTime = 3600,

    [Parameter()]
    [ValidateSet(0, 1)]
    [int]$ExecMode = 1,

    [Parameter()]
    [bool]$FullInventory = $true,

    [Parameter()]
    [AllowNull()]
    [string]$TagOverride = $null,

    [Parameter()]
    [switch]$RunDeferred,

    [Parameter()]
    [string]$StageRoot = 'C:\ProgramData\SCRIPTGUY\GLPI-Agent-Deploy',

    [Parameter()]
    [string]$ScheduledTaskName = 'Enterprise-Deploy-GLPI-Agent',

    [Parameter()]
    [int]$DeferredDelayMinutes = 2,

    [Parameter()]
    [int]$InstallerCopyMaxRetries = 5,

    [Parameter()]
    [int]$InstallerCopyInitialDelaySeconds = 4
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($true)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($true)
}
catch {
    # Do not interrupt execution when the host does not allow console encoding changes.
}

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($scriptName)) {
    $scriptName = 'Deploy-GLPI-Agent-viaGPO'
}

$logFileName = "$scriptName.log"
$logPath = Join-Path -Path $LogDirectory -ChildPath $logFileName
$msiLogPath = Join-Path -Path $LogDirectory -ChildPath 'glpi-msi-install.log'

$StageInstallerPath = Join-Path -Path $StageRoot -ChildPath $InstallerFileName
$LocalScriptPath = Join-Path -Path $StageRoot -ChildPath ($scriptName + '.ps1')
$LauncherCmdPath = Join-Path -Path $StageRoot -ChildPath 'run-glpi-agent-deferred.cmd'
$DeferredRunLockPath = Join-Path -Path $StageRoot -ChildPath 'glpi-agent-deferred.lock'
$StateFilePath = Join-Path -Path $StageRoot -ChildPath 'glpi-agent-state.json'

$FixedRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{5332E0B7-6BF4-1014-9007-D34CA10DA491}'
$ManagedConfigFileName = '90-enterprise-managed.cfg'
$ExpectedDisplayName = "GLPI Agent $ExpectedVersion"
$script:DeferredLockOwned = $false

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        try {
            $line | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop
        }
        catch {
            # Logging must never break the deployment flow.
        }
    }
}

function Initialize-Log {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        try {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to create log directory '$LogDirectory'. Error: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -LiteralPath $logPath)) {
        try {
            [System.IO.File]::WriteAllText($logPath, [string]::Empty, [System.Text.UTF8Encoding]::new($true))
        }
        catch {
            throw "Failed to initialize log file '$logPath'. Error: $($_.Exception.Message)"
        }
    }
}

function Initialize-MsiLog {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        try {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to create log directory '$LogDirectory' for the MSI log. Error: $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $msiLogPath) {
        try {
            $sizeMB = [Math]::Round(((Get-Item -LiteralPath $msiLogPath -ErrorAction Stop).Length / 1MB), 2)
            if ($sizeMB -gt 20) {
                Remove-Item -LiteralPath $msiLogPath -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to evaluate or rotate MSI log '$msiLogPath'. Error: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -LiteralPath $msiLogPath)) {
        try {
            [System.IO.File]::WriteAllText($msiLogPath, [string]::Empty, [System.Text.UTF8Encoding]::new($true))
        }
        catch {
            throw "Failed to initialize MSI log file '$msiLogPath'. Error: $($_.Exception.Message)"
        }
    }
}

function Write-MsiLogMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $lines = @(
        '============================================================',
        ('MSI execution started: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('Computer: {0}' -f $ComputerName),
        ('Expected baseline version: {0}' -f $ExpectedVersion),
        ('Source MSI: {0}' -f $SourceInstallerPath),
        ('Local staged MSI: {0}' -f $StageInstallerPath),
        '============================================================'
    )

    try {
        Add-Content -Path $msiLogPath -Value $lines -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to write MSI log marker. Error: $($_.Exception.Message)"
    }
}

function Test-IsRunningAsSystem {
    [CmdletBinding()]
    param()

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ($identity.User.Value -eq 'S-1-5-18')
    }
    catch {
        return $false
    }
}

function Ensure-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
}

function Copy-FileWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter()]
        [int]$MaxRetries = 5,

        [Parameter()]
        [int]$InitialDelaySeconds = 4,

        [Parameter()]
        [string]$Description = 'file'
    )

    $attempt = 0
    $delay = [Math]::Max(1, $InitialDelaySeconds)

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            if (-not (Test-Path -LiteralPath $Source)) {
                throw "$Description source not found: '$Source'"
            }

            $destinationFolder = Split-Path -Parent $Destination
            Ensure-Directory -Path $destinationFolder

            Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop

            if (-not (Test-Path -LiteralPath $Destination)) {
                throw "$Description destination was not created: '$Destination'"
            }

            $item = Get-Item -LiteralPath $Destination -ErrorAction Stop
            Write-Log -Message "$Description confirmed at '$Destination' with size $($item.Length) byte(s)."

            return $true
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to copy $Description. Attempt $attempt of $MaxRetries. Error: $($_.Exception.Message)"

            if ($attempt -ge $MaxRetries) {
                throw "Unable to copy $Description after $MaxRetries attempt(s). Source='$Source' | Destination='$Destination'. Last error: $($_.Exception.Message)"
            }

            Start-Sleep -Seconds $delay
            $delay = [Math]::Min(($delay * 2), 60)
        }
    }

    return $false
}

function Get-CurrentScriptPath {
    [CmdletBinding()]
    param()

    try {
        if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
            return $PSCommandPath
        }

        if ($MyInvocation.MyCommand.Path) {
            return $MyInvocation.MyCommand.Path
        }
    }
    catch {
    }

    return $null
}

function New-DeferredLauncher {
    [CmdletBinding()]
    param()

    $launcherContent = @"
@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$LocalScriptPath" -RunDeferred
exit /b %ERRORLEVEL%
"@

    try {
        [System.IO.File]::WriteAllText($LauncherCmdPath, $launcherContent, [System.Text.ASCIIEncoding]::new())
        $item = Get-Item -LiteralPath $LauncherCmdPath -ErrorAction Stop
        Write-Log -Message "Local deferred CMD launcher confirmed at '$LauncherCmdPath' with size $($item.Length) byte(s)."
    }
    catch {
        throw "Failed to create deferred CMD launcher '$LauncherCmdPath'. Error: $($_.Exception.Message)"
    }
}

function Sync-DeploymentArtifacts {
    [CmdletBinding()]
    param()

    Write-Log -Message "Starting mandatory local artifact synchronization in StageRoot '$StageRoot'."

    try {
        Ensure-Directory -Path $StageRoot
        Write-Log -Message "StageRoot confirmed or created at '$StageRoot'."

        $currentScript = Get-CurrentScriptPath
        if ([string]::IsNullOrWhiteSpace($currentScript) -or -not (Test-Path -LiteralPath $currentScript)) {
            Write-Log -Level 'WARNING' -Message 'Current PowerShell script path could not be resolved. Local PS1 self-synchronization was skipped.'
        }
        else {
            Copy-FileWithRetry -Source $currentScript -Destination $LocalScriptPath -MaxRetries 3 -InitialDelaySeconds 1 -Description 'PowerShell script'
            Write-Log -Message "Current PowerShell script synchronized to '$LocalScriptPath'."
        }

        Copy-FileWithRetry -Source $SourceInstallerPath -Destination $StageInstallerPath -MaxRetries $InstallerCopyMaxRetries -InitialDelaySeconds $InstallerCopyInitialDelaySeconds -Description 'GLPI Agent MSI installer'
        Write-Log -Message "MSI installer synchronized to '$StageInstallerPath'."

        New-DeferredLauncher
        Write-Log -Message "Deferred CMD launcher recreated at '$LauncherCmdPath'."

        Write-Log -Message 'Mandatory local artifact synchronization completed successfully.'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Mandatory artifact synchronization failed. Error: $($_.Exception.Message)"
        throw
    }
}

function Save-State {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    try {
        Ensure-Directory -Path $StageRoot
        $json = $State | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($StateFilePath, $json, [System.Text.UTF8Encoding]::new($true))
        Write-Log -Message "Operational state file written to '$StateFilePath'."
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to write operational state file '$StateFilePath'. Error: $($_.Exception.Message)"
    }
}

function Read-State {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $StateFilePath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $StateFilePath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to read state file '$StateFilePath'. Error: $($_.Exception.Message)"
        return $null
    }
}

function Get-ResolvedTag {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($TagOverride)) {
        Write-Log -Message "Inventory TAG resolved from TagOverride: '$TagOverride'."
        return $TagOverride
    }

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($computerSystem.Domain)) {
            $domain = [string]$computerSystem.Domain
            if ($domain -and $domain -ne 'WORKGROUP') {
                $resolved = $domain.ToUpperInvariant()
                Write-Log -Message "Inventory TAG resolved from machine DNS domain: '$resolved'."
                return $resolved
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to resolve inventory TAG from Win32_ComputerSystem.Domain. Error: $($_.Exception.Message)"
    }

    Write-Log -Level 'WARNING' -Message "Unable to resolve domain-based inventory TAG. Falling back to 'WORKGROUP'."
    return 'WORKGROUP'
}

function Get-GLPIAgentLauncher {
    [CmdletBinding()]
    param()

    $candidates = @(
        'C:\Program Files\GLPI-Agent\glpi-agent.bat',
        'C:\Program Files\GLPI-Agent\glpi-agent.exe',
        'C:\Program Files\GLPI-Agent\perl\bin\glpi-agent.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-FileVersionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            return ''
        }

        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return [string]$item.VersionInfo.FileVersion
    }
    catch {
        return ''
    }
}

function Get-GLPIOperationalFootprint {
    [CmdletBinding()]
    param()

    $launcher = Get-GLPIAgentLauncher
    $services = @()

    try {
        $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match 'glpi|fusioninventory' -or $_.DisplayName -match 'GLPI|FusionInventory'
        })
    }
    catch {
        $services = @()
    }

    $state = 'UNHEALTHY'

    if ($launcher -and $services.Count -gt 0) {
        $running = @($services | Where-Object { $_.Status -eq 'Running' })
        if ($running.Count -gt 0) {
            $state = 'HEALTHY'
        }
        else {
            $state = 'SERVICE_FOUND_NOT_RUNNING'
        }
    }
    elseif ($launcher) {
        $state = 'EXECUTABLE_ONLY'
    }
    elseif ($services.Count -gt 0) {
        $state = 'SERVICE_ONLY'
    }

    return [PSCustomObject]@{
        ExecutableFound = [bool]$launcher
        ExecutablePath  = $launcher
        ServicesFound   = ($services.Count -gt 0)
        ServiceCount    = $services.Count
        FinalState      = $state
    }
}

function Get-InstalledGLPIAgent {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $FixedRegistryPath) {
        try {
            $fixed = Get-ItemProperty -LiteralPath $FixedRegistryPath -ErrorAction Stop
            if ($fixed.DisplayName -match 'GLPI Agent') {
                return [PSCustomObject]@{
                    Name       = [string]$fixed.DisplayName
                    Version    = [string]$fixed.DisplayVersion
                    Reference  = $FixedRegistryPath
                    DetectedBy = 'FixedRegistryKey'
                    Architecture = '64-bit'
                }
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to read fixed GLPI Agent registry key '$FixedRegistryPath'. Error: $($_.Exception.Message)"
        }
    }

    $registryRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $registryRoots) {
        try {
            if (-not (Test-Path -LiteralPath $root)) {
                continue
            }

            $children = @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)

            foreach ($child in $children) {
                try {
                    $item = Get-ItemProperty -LiteralPath $child.PSPath -ErrorAction Stop
                    if ($item.DisplayName -match 'GLPI Agent') {
                        $arch = if ($root -match 'WOW6432Node') { '32-bit' } else { '64-bit' }

                        return [PSCustomObject]@{
                            Name       = [string]$item.DisplayName
                            Version    = [string]$item.DisplayVersion
                            Reference  = [string]$child.PSPath
                            DetectedBy = 'UninstallRegistry'
                            Architecture = $arch
                        }
                    }
                }
                catch {
                }
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to inspect uninstall registry root '$root'. Error: $($_.Exception.Message)"
        }
    }

    return $null
}

function Test-BaselineCompliance {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InstalledAgent
    )

    $keyPresent = Test-Path -LiteralPath $FixedRegistryPath
    $currentName = ''
    $currentVersion = ''

    if ($InstalledAgent) {
        $currentName = [string]$InstalledAgent.Name
        $currentVersion = [string]$InstalledAgent.Version
    }

    $compliant = $false

    if ($keyPresent -and $InstalledAgent -and $currentName -eq $ExpectedDisplayName -and $currentVersion -eq $ExpectedVersion) {
        $compliant = $true
    }
    elseif ($InstalledAgent -and $currentVersion -eq $ExpectedVersion -and $currentName -match 'GLPI Agent') {
        $compliant = $true
    }

    Write-Log -Message "Strict baseline compliance check: FixedKeyPresent=$keyPresent | ExpectedName='$ExpectedDisplayName' | CurrentName='$currentName' | ExpectedVersion='$ExpectedVersion' | CurrentVersion='$currentVersion' | Compliant=$compliant."

    return $compliant
}

function Set-ManagedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    $configRoot = 'C:\Program Files\GLPI-Agent\etc\conf.d'

    try {
        Ensure-Directory -Path $configRoot

        $configPath = Join-Path -Path $configRoot -ChildPath $ManagedConfigFileName

        $content = @(
            "# Enterprise managed GLPI Agent configuration",
            "# Generated by Deploy-GLPI-Agent-viaGPO",
            "# LastWrite: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "server = $ServerUrl",
            "tag = $Tag",
            "delaytime = $DelayTime",
            "httpd-trust = $HttpdTrust",
            "backend-collect-timeout = 180"
        )

        $content | Out-File -FilePath $configPath -Encoding ascii -Force -ErrorAction Stop

        Write-Log -Message "Managed configuration file successfully written to '$configPath'."
    }
    catch {
        throw "Failed to write managed GLPI Agent configuration. Error: $($_.Exception.Message)"
    }
}

function Invoke-GLPIAgentOnce {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Context = 'manual execution'
    )

    $launcher = Get-GLPIAgentLauncher

    if ([string]::IsNullOrWhiteSpace($launcher)) {
        Write-Log -Level 'WARNING' -Message "GLPI Agent launcher not found during $Context."
        return $false
    }

    $arguments = @('--force', '--logger=stderr')

    Write-Log -Message "Starting immediate GLPI Agent inventory during $Context. Launcher='$launcher' | Arguments='$($arguments -join ' ')'."

    $process = $null

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $launcher
        $psi.Arguments = ($arguments -join ' ')
        $psi.WorkingDirectory = Split-Path -Parent $launcher
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi

        [void]$process.Start()

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()

        $process.WaitForExit()

        Write-Log -Message "Immediate GLPI Agent execution result during $Context: ExitCode=$($process.ExitCode) | Success=$(($process.ExitCode -eq 0))."

        if (-not [string]::IsNullOrWhiteSpace($stdout)) {
            Write-Log -Message "GLPI Agent STDOUT: $stdout"
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr)) {
            Write-Log -Level 'WARNING' -Message "GLPI Agent STDERR: $stderr"
        }

        return ($process.ExitCode -eq 0)
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Failed to execute GLPI Agent during $Context. Error: $($_.Exception.Message)"
        return $false
    }
    finally {
        if ($process) {
            $process.Dispose()
        }
    }
}

function Invoke-MsiInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    if (-not (Test-Path -LiteralPath $StageInstallerPath)) {
        throw "Local staged GLPI Agent MSI was not found at '$StageInstallerPath'."
    }

    Write-MsiLogMarker -ComputerName $env:COMPUTERNAME

    $fullValue = if ($FullInventory) { '1' } else { '0' }

    $argumentList = @(
        '/i',
        ('"{0}"' -f $StageInstallerPath),
        '/qn',
        '/norestart',
        ('/L*v "{0}"' -f $msiLogPath),
        ('SERVER="{0}"' -f $ServerUrl),
        ('TAG="{0}"' -f $Tag),
        ('HTTPD_TRUST="{0}"' -f $HttpdTrust),
        ('DELAYTIME="{0}"' -f $DelayTime),
        ('EXECMODE="{0}"' -f $ExecMode),
        ('FULL="{0}"' -f $fullValue),
        'RUNNOW=1',
        'ADD_FIREWALL_EXCEPTION=1'
    )

    Write-Log -Message "Starting GLPI Agent MSI installation or repair from local staged installer. MSI='$StageInstallerPath'."

    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden

    Write-Log -Message "MSI installation or repair completed. ExitCode=$($process.ExitCode)."

    if ($process.ExitCode -notin @(0, 3010, 1641)) {
        throw "GLPI Agent MSI installation failed. ExitCode=$($process.ExitCode). Review '$msiLogPath'."
    }

    if ($process.ExitCode -in @(3010, 1641)) {
        Write-Log -Level 'WARNING' -Message "MSI completed with reboot-related ExitCode=$($process.ExitCode)."
    }
}

function Register-DeferredTask {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $LauncherCmdPath)) {
        throw "Deferred launcher was not found at '$LauncherCmdPath'."
    }

    $runTime = (Get-Date).AddMinutes($DeferredDelayMinutes).ToString('HH:mm')
    $quotedCmd = ('"{0}"' -f $LauncherCmdPath)

    Write-Log -Message "Creating deferred Scheduled Task '$ScheduledTaskName' to run at $runTime as SYSTEM."

    try {
        & schtasks.exe /Create /TN $ScheduledTaskName /TR $quotedCmd /SC ONCE /ST $runTime /RU SYSTEM /RL HIGHEST /F | Out-Null
        $createCode = $LASTEXITCODE

        if ($createCode -ne 0) {
            throw "schtasks.exe /Create returned ExitCode=$createCode."
        }

        & schtasks.exe /Run /TN $ScheduledTaskName | Out-Null
        $runCode = $LASTEXITCODE

        if ($runCode -ne 0) {
            throw "schtasks.exe /Run returned ExitCode=$runCode."
        }

        Write-Log -Message "Deferred Scheduled Task '$ScheduledTaskName' created and triggered successfully."
    }
    catch {
        throw "Failed to create or trigger deferred Scheduled Task '$ScheduledTaskName'. Error: $($_.Exception.Message)"
    }
}

function Remove-DeferredTask {
    [CmdletBinding()]
    param()

    try {
        & schtasks.exe /Query /TN $ScheduledTaskName | Out-Null
        $queryCode = $LASTEXITCODE

        if ($queryCode -ne 0) {
            Write-Log -Message 'Scheduled Task does not exist. No removal required.'
            return
        }

        & schtasks.exe /Delete /TN $ScheduledTaskName /F | Out-Null
        $deleteCode = $LASTEXITCODE

        if ($deleteCode -eq 0) {
            Write-Log -Message "Deferred Scheduled Task '$ScheduledTaskName' removed successfully."
        }
        else {
            Write-Log -Level 'WARNING' -Message "Failed to remove Scheduled Task '$ScheduledTaskName'. schtasks ExitCode=$deleteCode."
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed while removing Scheduled Task '$ScheduledTaskName'. Error: $($_.Exception.Message)"
    }
}

function Enter-DeferredLock {
    [CmdletBinding()]
    param()

    try {
        Ensure-Directory -Path $StageRoot

        if (Test-Path -LiteralPath $DeferredRunLockPath) {
            $ageMinutes = 0
            try {
                $lockItem = Get-Item -LiteralPath $DeferredRunLockPath -ErrorAction Stop
                $ageMinutes = [Math]::Round(((Get-Date) - $lockItem.LastWriteTime).TotalMinutes, 2)
            }
            catch {
            }

            if ($ageMinutes -lt 60) {
                Write-Log -Level 'WARNING' -Message "Deferred lock already exists and is recent. Lock='$DeferredRunLockPath' | AgeMinutes=$ageMinutes. Deferred execution will stop."
                return $false
            }

            Write-Log -Level 'WARNING' -Message "Stale deferred lock detected. Removing lock '$DeferredRunLockPath'."
            Remove-Item -LiteralPath $DeferredRunLockPath -Force -ErrorAction SilentlyContinue
        }

        [System.IO.File]::WriteAllText($DeferredRunLockPath, (Get-Date).ToString('o'), [System.Text.UTF8Encoding]::new($true))
        $script:DeferredLockOwned = $true
        Write-Log -Message "Deferred execution lock acquired at '$DeferredRunLockPath'."
        return $true
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to acquire deferred execution lock. Error: $($_.Exception.Message)"
        return $false
    }
}

function Exit-DeferredLock {
    [CmdletBinding()]
    param()

    if (-not $script:DeferredLockOwned) {
        return
    }

    try {
        if (Test-Path -LiteralPath $DeferredRunLockPath) {
            Remove-Item -LiteralPath $DeferredRunLockPath -Force -ErrorAction Stop
        }

        Write-Log -Message "Deferred execution lock released from '$DeferredRunLockPath'."
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Failed to release deferred execution lock '$DeferredRunLockPath'. Error: $($_.Exception.Message)"
    }
    finally {
        $script:DeferredLockOwned = $false
    }
}

function Invoke-PostInstallConvergence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter()]
        [string]$Context = 'post-installation convergence'
    )

    $installedAfter = Get-InstalledGLPIAgent

    if ($installedAfter) {
        Write-Log -Message "GLPI Agent detected after installation. Name='$($installedAfter.Name)' | Version='$($installedAfter.Version)' | DetectedBy='$($installedAfter.DetectedBy)' | Reference='$($installedAfter.Reference)'."
    }
    else {
        Write-Log -Level 'WARNING' -Message 'GLPI Agent was not detected after MSI execution.'
    }

    Set-ManagedConfiguration -Tag $Tag

    $inventorySuccess = Invoke-GLPIAgentOnce -Context $Context

    if (-not $inventorySuccess) {
        Write-Log -Level 'WARNING' -Message 'GLPI Agent executed but did not return success. Configuration remains applied; review agent logs if the inventory does not reach GLPI.'
    }

    $footprint = Get-GLPIOperationalFootprint
    Write-Log -Message "Operational footprint after convergence: ExecutableFound=$($footprint.ExecutableFound) | ExecutablePath='$($footprint.ExecutablePath)' | ServicesFound=$($footprint.ServicesFound) | ServiceCount=$($footprint.ServiceCount) | FinalState='$($footprint.FinalState)'."
}

function Invoke-ReconfigurationOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tag
    )

    $footprintBefore = Get-GLPIOperationalFootprint
    Write-Log -Message "Operational footprint before reconfiguration: ExecutableFound=$($footprintBefore.ExecutableFound) | ExecutablePath='$($footprintBefore.ExecutablePath)' | ServicesFound=$($footprintBefore.ServicesFound) | ServiceCount=$($footprintBefore.ServiceCount) | FinalState='$($footprintBefore.FinalState)'."

    Set-ManagedConfiguration -Tag $Tag

    $inventorySuccess = Invoke-GLPIAgentOnce -Context 'post-reconfiguration convergence'

    if (-not $inventorySuccess) {
        Write-Log -Level 'WARNING' -Message 'GLPI Agent executed but returned a non-success result. Configuration remains applied; review agent logs if the inventory does not reach GLPI.'
    }

    Start-Sleep -Seconds 2

    $footprintAfter = Get-GLPIOperationalFootprint
    Write-Log -Message "Operational footprint after reconfiguration: ExecutableFound=$($footprintAfter.ExecutableFound) | ExecutablePath='$($footprintAfter.ExecutablePath)' | ServicesFound=$($footprintAfter.ServicesFound) | ServiceCount=$($footprintAfter.ServiceCount) | FinalState='$($footprintAfter.FinalState)'."
}

function Invoke-DeferredMode {
    [CmdletBinding()]
    param()

    Write-Log -Message 'Deferred local execution mode started.'

    if (-not (Enter-DeferredLock)) {
        return
    }

    try {
        $state = Read-State
        $tag = Get-ResolvedTag

        if ($state -and $state.Tag) {
            $tag = [string]$state.Tag
            Write-Log -Message "Inventory TAG loaded from state file: '$tag'."
        }

        if (-not (Test-Path -LiteralPath $StageInstallerPath)) {
            throw "Local staged MSI does not exist in deferred mode: '$StageInstallerPath'."
        }

        $installed = Get-InstalledGLPIAgent
        $compliant = Test-BaselineCompliance -InstalledAgent $installed

        if ($compliant) {
            Write-Log -Message "Installed GLPI Agent already matches baseline '$ExpectedVersion'. Deferred mode will only reconfigure and converge inventory."
            Invoke-ReconfigurationOnly -Tag $tag
        }
        else {
            Write-Log -Message "Installed GLPI Agent is missing or non-compliant. Deferred mode will install or repair baseline '$ExpectedVersion'."
            Invoke-MsiInstall -Tag $tag
            Invoke-PostInstallConvergence -Tag $tag -Context 'deferred post-installation convergence'
        }

        Remove-DeferredTask
        Write-Log -Message 'Deferred local execution mode completed successfully.'
    }
    finally {
        Exit-DeferredLock
    }
}

function Invoke-BootstrapMode {
    [CmdletBinding()]
    param()

    Write-Log -Message 'Bootstrap online mode started.'

    $tag = Get-ResolvedTag

    Save-State -State @{
        ComputerName = $env:COMPUTERNAME
        Tag          = $tag
        ExpectedVersion = $ExpectedVersion
        ServerUrl    = $ServerUrl
        StageRoot    = $StageRoot
        Timestamp    = (Get-Date).ToString('o')
    }

    $installed = Get-InstalledGLPIAgent

    $launcher = Get-GLPIAgentLauncher
    if ($launcher) {
        $launcherVersion = Get-FileVersionSafe -Path $launcher
        Write-Log -Message "GLPI Agent launcher detected separately: Version='$launcherVersion' | Path='$launcher' | Architecture='64-bit'."
    }

    if ($installed) {
        Write-Log -Message "GLPI Agent detected by '$($installed.DetectedBy)'. Name='$($installed.Name)' | Version='$($installed.Version)' | Architecture='$($installed.Architecture)' | Reference='$($installed.Reference)'."
    }
    else {
        Write-Log -Message 'GLPI Agent was not detected in registry.'
    }

    if ($launcher) {
        $launcherVersion = Get-FileVersionSafe -Path $launcher
        Write-Log -Message "GLPI Agent launcher detected as diagnostic telemetry: Version='$launcherVersion' | Path='$launcher'. Operational decisions remain based on the registry-validated institutional baseline."
    }

    $compliant = Test-BaselineCompliance -InstalledAgent $installed

    if ($compliant) {
        Write-Log -Message "Installed version '$ExpectedVersion' matches the expected baseline and is compliant. Reconfiguration-only flow will run."
        Invoke-ReconfigurationOnly -Tag $tag
        Remove-DeferredTask
        Write-Log -Message 'Bootstrap flow completed without binary installation.'
        return
    }

    Write-Log -Message "Installed GLPI Agent is missing or non-compliant. A deferred local installation will be scheduled."

    Register-DeferredTask

    Write-Log -Message 'Bootstrap flow completed after scheduling deferred local convergence.'
}

try {
    Initialize-Log
    Initialize-MsiLog

    Write-Log -Message '============================================================'
    Write-Log -Message 'Starting Deploy-GLPI-Agent-viaGPO execution.'
    Write-Log -Message "Computer name: '$env:COMPUTERNAME'."
    Write-Log -Message "Execution identity: '$([Security.Principal.WindowsIdentity]::GetCurrent().Name)'."
    Write-Log -Message "SourceInstallerPath: '$SourceInstallerPath'."
    Write-Log -Message "StageRoot: '$StageRoot'."
    Write-Log -Message "StageInstallerPath: '$StageInstallerPath'."
    Write-Log -Message "LocalScriptPath: '$LocalScriptPath'."
    Write-Log -Message "LauncherCmdPath: '$LauncherCmdPath'."
    Write-Log -Message "StateFilePath: '$StateFilePath'."
    Write-Log -Message "RunDeferred: $([bool]$RunDeferred)."
    Write-Log -Message "Expected target version: '$ExpectedVersion'."
    Write-Log -Message "Fixed monitored registry key: '$FixedRegistryPath'."
    Write-Log -Message "Log directory: '$LogDirectory'."
    Write-Log -Message "MSI log file: '$msiLogPath'."
    Write-Log -Message "Configured parameters: HTTPD_TRUST='$HttpdTrust' | DELAYTIME='$DelayTime' | EXECMODE='$ExecMode' | FULL='$([int]$FullInventory)'."

    Sync-DeploymentArtifacts

    if ($RunDeferred) {
        Invoke-DeferredMode
    }
    else {
        Invoke-BootstrapMode
    }

    Write-Log -Message 'Finished script execution.'
    Write-Log -Message '============================================================'
}
catch {
    try {
        Write-Log -Level 'ERROR' -Message "Fatal script failure: $($_.Exception.Message)"
        Write-Log -Message '============================================================'
    }
    catch {
    }

    throw
}

# End of script
