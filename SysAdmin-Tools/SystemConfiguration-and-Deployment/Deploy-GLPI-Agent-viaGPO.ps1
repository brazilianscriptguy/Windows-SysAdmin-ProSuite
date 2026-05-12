<#
.SYNOPSIS
  Idempotent GLPI Agent deployment through Machine GPO, with local staging, deferred execution, and controlled convergence.

.DESCRIPTION
  Stable enterprise version based on the Bootstrap Online + Deferred Offline architecture. The script performs a lightweight bootstrap during Machine GPO processing, stages the MSI installer and the current PowerShell script locally, and transfers the installation or repair workflow to a deferred local execution running under the SYSTEM context.

  This release preserves the validated stable behavior from the Portuguese-BR production build while generalizing paths, names, comments, log messages, and configuration labels for broader enterprise use.

  The workflow includes:
  - Robust GLPI Agent detection through the fixed baseline registry key, uninstall registry entries, and known executable paths;
  - Baseline version validation as the authoritative operational decision source;
  - Executable version tracking as diagnostic telemetry only;
  - In-place reconfiguration when the expected baseline is already compliant and operational;
  - Corrective installation or repair only when real structural non-compliance is detected;
  - Managed configuration generation through an enterprise configuration file;
  - Inventory TAG resolution based on the machine DNS domain, independent from the logged-on user context;
  - MSI execution from a local cache to reduce UNC dependency during installation;
  - JSON state persistence for continuity between bootstrap and deferred execution;
  - Execution lock control to prevent concurrent deferred runs;
  - Detailed UTF-8 logging for the main workflow and MSI execution;
  - Scheduled task creation, execution and removal using schtasks.exe for Windows PowerShell 5.1 compatibility;
  - Immediate inventory synchronization using glpi-agent.bat when available, with fallback to known executable paths;
  - Stable inventory trigger arguments: --force --logger=stderr;
  - Automatic cleanup of the deferred scheduled task after convergence.

  Default paths and values are intentionally generic and should be adjusted for each organization before production deployment.

.AUTHOR
    Luiz Hamilton Silva (@brazilianscriptguy)

.VERSION
  2026-05-12-v5.1.5-ENTERPRISE-STABLE-WRAPPER-FORCEFRESH-CONVERGENCE
#>


[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallerFileName = "glpi-agent117-install.msi",

    [Parameter()]
    [string]$SourceInstallerPath = "\\headq.scriptguy\netlogon\glpi-agent-install\glpi-agent116-install.msi",

    [Parameter()]
    [string]$LogDirectory = "C:\Logs-TEMP",

    [Parameter()]
    [string]$ExpectedVersion = "1.17",

    [Parameter()]
    [string]$ServerUrl = "http://cmdb.headq.scriptguy/front/inventory.php",

    [Parameter()]
    [string]$HttpdTrust = "127.0.0.1,10.0.0.0/8",

    [Parameter()]
    [int]$DelayTime = 3600,

    [Parameter()]
    [ValidateSet(0,1)]
    [int]$ExecMode = 1,

    [Parameter()]
    [bool]$FullInventory = $true,

    [Parameter()]
    [AllowNull()]
    [string]$TagOverride = $null,

    [Parameter()]
    [switch]$RunDeferred,

    [Parameter()]
    [string]$StageRoot = "C:\ProgramData\Enterprise\GLPI-Agent-Deploy",

    [Parameter()]
    [string]$ScheduledTaskName = "Enterprise-Deploy-GLPI-Agent",

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
    # Do not interrupt execution if the host does not allow console encoding changes
}

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($scriptName)) {
    $scriptName = 'glpi-agent-install'
}

$logFileName = "$scriptName.log"
$logPath = Join-Path -Path $LogDirectory -ChildPath $logFileName
$msiLogPath = Join-Path -Path $LogDirectory -ChildPath 'glpi-msi-install.log'

$StageInstallerPath = Join-Path -Path $StageRoot -ChildPath $InstallerFileName
$LocalScriptPath = Join-Path -Path $StageRoot -ChildPath ($scriptName + '.ps1')
$LauncherCmdPath = Join-Path -Path $StageRoot -ChildPath 'run-glpi-agent-deferred.cmd'
$DeferredRunLockPath = Join-Path -Path $StageRoot -ChildPath 'glpi-agent-deferred.lock'
$StateFilePath = Join-Path -Path $StageRoot -ChildPath 'glpi-agent-state.json'

# Fixed registry key for the expected GLPI Agent baseline
$fixedRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{5332E0B7-6BF4-1014-9007-D34CA10DA491}'
$managedConfigFileName = '90-enterprise-managed.cfg'
$expectedDisplayName = 'GLPI Agent 1.17'
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

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"

    try {
        Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        try {
            $line | Out-File -FilePath $logPath -Append -Encoding utf8 -ErrorAction Stop
        }
        catch {
            # Do not interrupt execution due to residual logging failure
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
            throw "Failed to create the log directory '$LogDirectory'. Error: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path -LiteralPath $logPath)) {
        try {
            [System.IO.File]::WriteAllText($logPath, [string]::Empty, [System.Text.UTF8Encoding]::new($true))
        }
        catch {
            throw "Failed to initialize the log file '$logPath'. Error: $($_.Exception.Message)"
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
            throw "Failed to create the log directory '$LogDirectory' for the MSI log. Error: $($_.Exception.Message)"
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
            Write-Log "Failed to evaluate or recycle the MSI log '$msiLogPath'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    if (-not (Test-Path -LiteralPath $msiLogPath)) {
        try {
            [System.IO.File]::WriteAllText($msiLogPath, [string]::Empty, [System.Text.UTF8Encoding]::new($true))
        }
        catch {
            throw "Failed to initialize the MSI log file '$msiLogPath'. Error: $($_.Exception.Message)"
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
        '============================================================'
    )

    try {
        foreach ($line in $lines) {
            Add-Content -Path $msiLogPath -Value $line -Encoding UTF8 -ErrorAction Stop
        }
    }
    catch {
        Write-Log "Failed to write the MSI log marker to '$msiLogPath'. Error: $($_.Exception.Message)" 'WARNING'
    }
}

function Get-GpoStartupContext {
    [CmdletBinding()]
    param()

    try {
        $isSystem = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq 'S-1-5-18')
        $session0 = ([Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0)
        $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$pid" -ErrorAction Stop
        $parent = $null

        if ($processInfo -and $processInfo.ParentProcessId) {
            $parent = Get-Process -Id $processInfo.ParentProcessId -ErrorAction SilentlyContinue
        }

        $parentName = if ($parent) { ($parent.Name -replace '\.exe$', '').ToLowerInvariant() } else { '' }
        $gpoParents = @('gpscript', 'gpupdate', 'winlogon', 'services')

        return ($isSystem -and $session0 -and ($gpoParents -contains $parentName))
    }
    catch {
        return $false
    }
}

function ConvertTo-VersionObject {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) {
        return $null
    }

    $normalized = (($VersionText -replace ',', '.') -replace '[^0-9\.]', '').Trim('.')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $null
    }

    $parts = @($normalized.Split('.') | Where-Object { $_ -match '^\d+$' })
    if ($parts.Count -eq 0) {
        return $null
    }

    while ($parts.Count -lt 4) {
        $parts += '0'
    }

    if ($parts.Count -gt 4) {
        $parts = $parts[0..3]
    }

    $candidate = ($parts -join '.')
    try {
        return [version]$candidate
    }
    catch {
        return $null
    }
}

function Compare-VersionText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,

        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $leftVersion = ConvertTo-VersionObject -VersionText $Left
    $rightVersion = ConvertTo-VersionObject -VersionText $Right

    if (-not $leftVersion -and -not $rightVersion) { return 0 }
    if (-not $leftVersion) { return -1 }
    if (-not $rightVersion) { return 1 }

    if ($leftVersion -lt $rightVersion) { return -1 }
    if ($leftVersion -gt $rightVersion) { return 1 }
    return 0
}

function Get-GLPIExecutablePath {
    [CmdletBinding()]
    param()

    $candidates = @(
        'C:\Program Files\GLPI-Agent\glpi-agent.bat',
        'C:\Program Files (x86)\GLPI-Agent\glpi-agent.bat',
        'C:\Program Files\GLPI-Agent\glpi-agent.exe',
        'C:\Program Files (x86)\GLPI-Agent\glpi-agent.exe',
        'C:\Program Files\GLPI-Agent\perl\bin\glpi-agent.exe',
        'C:\Program Files (x86)\GLPI-Agent\perl\bin\glpi-agent.exe'
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return $path
        }
    }

    return $null
}

function Get-GLPIServices {
    [CmdletBinding()]
    param()

    try {
        return @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like '*glpi*agent*' -or $_.DisplayName -like '*GLPI*Agent*'
        })
    }
    catch {
        return @()
    }
}

function Get-MsiExitCodeDescription {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    switch ($ExitCode) {
        0    { return 'Success' }
        3010 { return 'Success, restart required' }
        1641 { return 'Success, restart initiated' }
        1618 { return 'Another MSI installation is already in progress' }
        default { return 'The MSI returned an explicitly unmapped exit code' }
    }
}

function Test-MsiExitCodeSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode
    )

    return ($ExitCode -in @(0, 3010, 1641))
}

function Get-RegistryCandidateInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $true)]
        [string]$Architecture
    )

    try {
        $item = Get-ItemProperty -LiteralPath $RegistryPath -ErrorAction Stop
        if ($item -and $item.DisplayName -match 'GLPI\s*Agent') {
            return [PSCustomObject]@{
                DisplayName     = $item.DisplayName
                DisplayVersion  = $item.DisplayVersion
                InstallLocation = $item.InstallLocation
                RegistryPath    = $RegistryPath
                RegistryKey     = Split-Path -Path $RegistryPath -Leaf
                Architecture    = $Architecture
                DetectionMethod = 'Registro-Uninstall'
                VersionObject   = ConvertTo-VersionObject -VersionText $item.DisplayVersion
            }
        }
    }
    catch {
        # Ignorar e prosseguir
    }

    return $null
}

function Select-BestGLPICandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Candidates
    )

    $valid = @($Candidates | Where-Object { $_ -ne $null })
    if ($valid.Count -eq 0) {
        return $null
    }

    $sorted = $valid | Sort-Object -Property @(
        @{ Expression = { if ($_.VersionObject) { 1 } else { 0 } }; Descending = $true },
        @{ Expression = { $_.VersionObject }; Descending = $true },
        @{ Expression = { if ($_.RegistryPath -eq $fixedRegistryPath) { 1 } else { 0 } }; Descending = $true }
    )

    return @($sorted)[0]
}


function Test-GLPI117BaselineCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryKey,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedDisplayName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedDisplayVersion
    )

    $result = [PSCustomObject]@{
        IsCompliant            = $false
        KeyPresent             = $false
        DisplayNameMatches     = $false
        DisplayVersionMatches  = $false
        ActualDisplayName      = $null
        ActualDisplayVersion   = $null
        RegistryKey            = $RegistryKey
    }

    if (-not (Test-Path -LiteralPath $RegistryKey)) {
        return $result
    }

    $result.KeyPresent = $true

    try {
        $item = Get-ItemProperty -LiteralPath $RegistryKey -ErrorAction Stop
        $result.ActualDisplayName = $item.DisplayName
        $result.ActualDisplayVersion = $item.DisplayVersion
        $result.DisplayNameMatches = ($item.DisplayName -eq $ExpectedDisplayName)
        $result.DisplayVersionMatches = ($item.DisplayVersion -eq $ExpectedDisplayVersion)
        $result.IsCompliant = ($result.DisplayNameMatches -and $result.DisplayVersionMatches)
        return $result
    }
    catch {
        return $result
    }
}


function Get-GLPIExecutableInfo {
    [CmdletBinding()]
    param()

    $exe = Get-GLPIExecutablePath
    if (-not $exe) {
        return $null
    }

    try {
        $file = Get-Item -LiteralPath $exe -ErrorAction Stop
        $fileVersion = $file.VersionInfo.ProductVersion
        if ([string]::IsNullOrWhiteSpace($fileVersion)) {
            $fileVersion = $file.VersionInfo.FileVersion
        }

        $architecture = if ($exe -like '*Program Files (x86)*') { '32-bit' } else { '64-bit' }
        return [PSCustomObject]@{
            DisplayName     = 'GLPI Agent (File Detection)'
            DisplayVersion  = $fileVersion
            ExecutablePath  = $exe
            InstallLocation = Split-Path -Path $exe -Parent
            RegistryPath    = '(file)'
            RegistryKey     = '(file)'
            Architecture    = $architecture
            DetectionMethod = 'File'
            VersionObject   = ConvertTo-VersionObject -VersionText $fileVersion
        }
    }
    catch {
        Write-Log "Failed to retrieve the executable version for '$exe'. Error: $($_.Exception.Message)" 'WARNING'
        return $null
    }
}

function Test-GLPIHybridDivergence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $BaselineCompliance,

        [Parameter()]
        [AllowNull()]
        $ExecutableInfo,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedDisplayVersion
    )

    $result = [PSCustomObject]@{
        IsDivergent          = $false
        Reason               = $null
        ExecutableVersion    = $null
        ExecutablePath       = $null
        BaselineVersion      = $BaselineCompliance.ActualDisplayVersion
        ExecutableComparison = $null
    }

    if ($null -eq $ExecutableInfo) {
        return $result
    }

    $result.ExecutableVersion = $ExecutableInfo.DisplayVersion
    $result.ExecutablePath = $ExecutableInfo.ExecutablePath

    try {
        $result.ExecutableComparison = Compare-VersionText -Left $ExecutableInfo.DisplayVersion -Right $ExpectedDisplayVersion
    }
    catch {
        $result.ExecutableComparison = $null
    }

    return $result
}

function Get-GLPIInstalledInfo {
    [CmdletBinding()]
    param()

    $candidates = New-Object System.Collections.Generic.List[object]

    if (Test-Path -LiteralPath $fixedRegistryPath) {
        try {
            $item = Get-ItemProperty -LiteralPath $fixedRegistryPath -ErrorAction Stop
            $candidates.Add([PSCustomObject]@{
                DisplayName     = $item.DisplayName
                DisplayVersion  = $item.DisplayVersion
                InstallLocation = $item.InstallLocation
                RegistryPath    = $fixedRegistryPath
                RegistryKey     = '{5332E0B7-6BF4-1014-9007-D34CA10DA491}'
                Architecture    = '64-bit'
                DetectionMethod = 'FixedRegistryKey'
                VersionObject   = ConvertTo-VersionObject -VersionText $item.DisplayVersion
            }) | Out-Null
        }
        catch {
            Write-Log "Failed to read the fixed registry key '$fixedRegistryPath'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    $uninstallRoots = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Architecture = '64-bit' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Architecture = '32-bit' }
    )

    foreach ($root in $uninstallRoots) {
        try {
            if (Test-Path -LiteralPath $root.Path) {
                $subKeys = Get-ChildItem -LiteralPath $root.Path -ErrorAction Stop
                foreach ($subKey in $subKeys) {
                    $candidate = Get-RegistryCandidateInfo -RegistryPath $subKey.PSPath -Architecture $root.Architecture
                    if ($candidate) {
                        $candidates.Add($candidate) | Out-Null
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to enumerate the uninstall registry repository '$($root.Path)'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    $selectedRegistryCandidate = Select-BestGLPICandidate -Candidates $candidates
    if ($null -ne $selectedRegistryCandidate) {
        return $selectedRegistryCandidate
    }

    return (Get-GLPIExecutableInfo)
}

function Get-MachineDomainTag {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($TagOverride)) {
        return $TagOverride.Trim().ToUpperInvariant()
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs -and $cs.PartOfDomain -and -not [string]::IsNullOrWhiteSpace($cs.Domain)) {
            $candidates.Add([string]$cs.Domain)
        }
    }
    catch {
        Write-Log "Failed to query Win32_ComputerSystem for machine TAG resolution. Error: $($_.Exception.Message)" 'WARNING'
    }

    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
            Where-Object { $_.IPEnabled -eq $true -and -not [string]::IsNullOrWhiteSpace($_.DNSDomain) }

        foreach ($adapter in $adapters) {
            $candidates.Add([string]$adapter.DNSDomain)
        }
    }
    catch {
        Write-Log "Failed to query DNSDomain from active interfaces for TAG resolution. Error: $($_.Exception.Message)" 'WARNING'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) {
        $candidates.Add([string]$env:USERDNSDOMAIN)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        $candidates.Add([string]$env:USERDOMAIN)
    }

    $tag = $candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($tag)) {
        return 'WORKGROUP'
    }

    return $tag.Trim().ToUpperInvariant()
}

function Test-GLPIOperationalFootprint {
    [CmdletBinding()]
    param()

    $result = [PSCustomObject]@{
        ExecutableFound = $false
        ExecutablePath  = $null
        ServicesFound   = $false
        Services        = @()
        ServiceCount    = 0
        FinalState      = 'UNKNOWN'
    }

    $exe = Get-GLPIExecutablePath
    if ($exe) {
        $result.ExecutableFound = $true
        $result.ExecutablePath  = $exe
    }

    $services = @(Get-GLPIServices)
    if ($services.Count -gt 0) {
        $result.ServicesFound = $true
        $result.Services      = $services
        $result.ServiceCount  = $services.Count
    }

    if ($result.ExecutableFound -and $result.ServicesFound) {
        $result.FinalState = 'HEALTHY'
    }
    elseif ($result.ExecutableFound -and -not $result.ServicesFound) {
        $result.FinalState = 'PARTIAL'
    }
    elseif (-not $result.ExecutableFound -and $result.ServicesFound) {
        $result.FinalState = 'PARTIAL'
    }
    else {
        $result.FinalState = 'NOT_DETECTED'
    }

    return $result
}

function Get-GLPIConfigDirectory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string]$ExecutablePath,

        [Parameter()]
        [AllowNull()]
        [string]$InstallLocation
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($InstallLocation)) {
        $candidates.Add((Join-Path -Path $InstallLocation -ChildPath 'etc\conf.d'))
        $candidates.Add((Join-Path -Path $InstallLocation -ChildPath 'conf.d'))
        $candidates.Add((Join-Path -Path $InstallLocation -ChildPath 'etc'))
    }

    if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
        $exeDir = Split-Path -Path $ExecutablePath -Parent
        $candidates.Add((Join-Path -Path $exeDir -ChildPath 'etc\conf.d'))
        $candidates.Add((Join-Path -Path $exeDir -ChildPath 'conf.d'))
        $parent1 = Split-Path -Path $exeDir -Parent
        if (-not [string]::IsNullOrWhiteSpace($parent1)) {
            $candidates.Add((Join-Path -Path $parent1 -ChildPath 'etc\conf.d'))
            $candidates.Add((Join-Path -Path $parent1 -ChildPath 'conf.d'))
            $parent2 = Split-Path -Path $parent1 -Parent
            if (-not [string]::IsNullOrWhiteSpace($parent2)) {
                $candidates.Add((Join-Path -Path $parent2 -ChildPath 'etc\conf.d'))
                $candidates.Add((Join-Path -Path $parent2 -ChildPath 'conf.d'))
            }
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }

    return $null
}

function Set-GLPIManagedConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Tag,

        [Parameter(Mandatory = $true)]
        [string]$HttpdTrustValue,

        [Parameter(Mandatory = $true)]
        [int]$Delay,

        [Parameter(Mandatory = $true)]
        [int]$Mode,

        [Parameter(Mandatory = $true)]
        [bool]$EnableFullInventory,

        [Parameter()]
        [AllowNull()]
        [string]$ExecutablePath,

        [Parameter()]
        [AllowNull()]
        [string]$InstallLocation
    )

    $configDir = Get-GLPIConfigDirectory -ExecutablePath $ExecutablePath -InstallLocation $InstallLocation
    if ([string]::IsNullOrWhiteSpace($configDir)) {
        throw 'Unable to determine the GLPI Agent configuration directory.'
    }

    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $configFile = Join-Path -Path $configDir -ChildPath $managedConfigFileName

    $lines = @(
        '# Automatically managed file - DO NOT EDIT MANUALLY',
        ('server = {0}' -f $Server),
        ('tag = {0}' -f $Tag),
        ('httpd-trust = {0}' -f $HttpdTrustValue),
        ('delaytime = {0}' -f $Delay),
        ('execmode = {0}' -f $Mode)
    )

    if ($EnableFullInventory) {
        $lines += 'full = 1'
    }

    $content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    Set-Content -Path $configFile -Value $content -Encoding ASCII -Force -ErrorAction Stop

    return $configFile
}

function Invoke-GLPIAgentOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExecutablePath
    )

    $launcherPath = $ExecutablePath

    $wrapperCandidates = @(
        'C:\Program Files\GLPI-Agent\glpi-agent.bat',
        'C:\Program Files (x86)\GLPI-Agent\glpi-agent.bat',
        'C:\Program Files\GLPI-Agent\glpi-agent.exe',
        'C:\Program Files (x86)\GLPI-Agent\glpi-agent.exe',
        'C:\Program Files\GLPI-Agent\perl\bin\glpi-agent.exe',
        'C:\Program Files (x86)\GLPI-Agent\perl\bin\glpi-agent.exe'
    )

    foreach ($candidate in $wrapperCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            $launcherPath = $candidate
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath)) {
        throw 'No valid GLPI Agent wrapper/executable was found for immediate inventory synchronization.'
    }

    $agentArguments = @('--force', '--logger=stderr')

    $psi = New-Object System.Diagnostics.ProcessStartInfo

    if ($launcherPath.ToLowerInvariant().EndsWith('.bat') -or $launcherPath.ToLowerInvariant().EndsWith('.cmd')) {
        $psi.FileName = $env:ComSpec
        if ([string]::IsNullOrWhiteSpace($psi.FileName)) {
            $psi.FileName = 'C:\Windows\System32\cmd.exe'
        }
        $escapedLauncher = '"' + $launcherPath + '"'
        $psi.Arguments = '/d /c ' + $escapedLauncher + ' ' + ($agentArguments -join ' ')
        $psi.WorkingDirectory = Split-Path -Parent $launcherPath
    }
    else {
        $psi.FileName = $launcherPath
        $psi.Arguments = ($agentArguments -join ' ')
        $psi.WorkingDirectory = Split-Path -Parent $launcherPath
    }

    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi

        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        $exitCode = [int]$process.ExitCode

        return [pscustomobject]@{
            ExitCode     = $exitCode
            Succeeded    = ($exitCode -eq 0)
            LauncherPath = $launcherPath
            Arguments    = ($agentArguments -join ' ')
            StdOut       = $stdout
            StdErr       = $stderr
        }
    }
    catch {
        throw "Failed to execute GLPI Agent for immediate inventory synchronization. Launcher='$launcherPath'. Error: $($_.Exception.Message)"
    }
}

function Test-Admin {
    [CmdletBinding()]
    param()

    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Get-CurrentScriptPath {
    [CmdletBinding()]
    param()

    if ($PSCommandPath) { return $PSCommandPath }
    if ($MyInvocation.MyCommand.Path) { return $MyInvocation.MyCommand.Path }
    throw 'Nao foi possivel determinar o caminho do script em execucao.'
}

function Copy-ScriptToStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Ensure-Directory -Path $StageRoot
    $currentScriptPath = Get-CurrentScriptPath
    Copy-Item -LiteralPath $currentScriptPath -Destination $DestinationPath -Force -ErrorAction Stop
}

function Copy-InstallerToStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Ensure-Directory -Path $StageRoot

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "The source installer was not found at '$SourcePath'."
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            return
        }
        catch {
            if ($attempt -ge $InstallerCopyMaxRetries) {
                throw "Failed to copy the installer to local staging after $attempt attempt(s). Error: $($_.Exception.Message)"
            }

            $delay = [Math]::Max(1, ($InstallerCopyInitialDelaySeconds * $attempt))
            Write-Log "Failed to copy the installer to local staging on attempt $attempt. Retrying in $delay second(s). Error: $($_.Exception.Message)" 'WARNING'
            Start-Sleep -Seconds $delay
        }
    }
}

function Confirm-StagedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label ausente em '$Path'."
    }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        throw "$Label invalido: '$Path' e um diretorio."
    }

    if ($item.Length -le 0) {
        throw "$Label invalido: '$Path' esta vazio."
    }

    Write-Log "$Label confirmado em '$Path' com tamanho de $($item.Length) byte(s)."
}

function Test-InstallerCacheIsUsable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        return (-not $item.PSIsContainer -and $item.Length -gt 0)
    }
    catch {
        return $false
    }
}

function Save-GLPIBootstrapState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State
    )

    Ensure-Directory -Path $StageRoot
    $json = $State | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($StateFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Log "Estado do bootstrap persistido em '$StateFilePath'."
}

function Get-GLPIDeferredState {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $StateFilePath)) {
        throw "O estado persistido do bootstrap nao foi encontrado em '$StateFilePath'."
    }

    try {
        $raw = Get-Content -LiteralPath $StateFilePath -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{
            SavedAt          = [string]$obj.SavedAt
            DomainTag        = [string]$obj.DomainTag
            DesiredAction    = [string]$obj.DesiredAction
            SourceInstaller  = [string]$obj.SourceInstaller
            StageInstaller   = [string]$obj.StageInstaller
            ExpectedVersion  = [string]$obj.ExpectedVersion
            BootstrapHost    = [string]$obj.BootstrapHost
        }
    }
    catch {
        throw "Failed to load the persisted bootstrap state. Error: $($_.Exception.Message)"
    }
}

function Get-DeferredRunLockDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockPath
    )

    $result = [pscustomobject]@{
        RawText    = $null
        Pid        = $null
        ParsedTime = $null
        IsStale    = $false
        Reason     = $null
    }

    try {
        $raw = Get-Content -LiteralPath $LockPath -Raw -ErrorAction Stop
        $result.RawText = $raw

        if ($raw -match 'PID=(\d+)') {
            $result.Pid = [int]$matches[1]
        }
        if ($raw -match 'TIME=([^;]+)') {
            try { $result.ParsedTime = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch {}
        }

        if ($null -ne $result.Pid) {
            $proc = Get-Process -Id $result.Pid -ErrorAction SilentlyContinue
            if ($null -eq $proc) {
                $result.IsStale = $true
                $result.Reason = 'PID ausente'
            }
        }

        if (-not $result.IsStale -and $null -ne $result.ParsedTime) {
            if (((Get-Date) - $result.ParsedTime).TotalMinutes -ge 180) {
                $result.IsStale = $true
                $result.Reason = 'idade excedida'
            }
        }
    }
    catch {
        $result.IsStale = $true
        $result.Reason = 'conteudo invalido ou inacessivel'
    }

    return $result
}

function Acquire-DeferredRunLock {
    [CmdletBinding()]
    param()

    $script:DeferredLockOwned = $false

    if (Test-Path -LiteralPath $DeferredRunLockPath) {
        $lockDetails = Get-DeferredRunLockDetails -LockPath $DeferredRunLockPath
        if ($lockDetails.IsStale) {
            Remove-Item -LiteralPath $DeferredRunLockPath -Force -ErrorAction SilentlyContinue
            Write-Log "Lock stale removido de '$DeferredRunLockPath'. Motivo='$($lockDetails.Reason)'." 'WARNING'
        }
        else {
            Write-Log "Outra execucao diferida ja esta em andamento. Lock='$DeferredRunLockPath'." 'WARNING'
            return $false
        }
    }

    $lockData = "PID=$PID;HOST=$env:COMPUTERNAME;TIME=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    [System.IO.File]::WriteAllText($DeferredRunLockPath, $lockData, [System.Text.UTF8Encoding]::new($false))
    $script:DeferredLockOwned = $true
    Write-Log "Lock de execucao diferida criado em '$DeferredRunLockPath'."
    return $true
}

function Release-DeferredRunLock {
    [CmdletBinding()]
    param()

    try {
        if ($script:DeferredLockOwned -and (Test-Path -LiteralPath $DeferredRunLockPath)) {
            Remove-Item -LiteralPath $DeferredRunLockPath -Force -ErrorAction SilentlyContinue
            Write-Log "Deferred execution lock removed."
        }
    }
    catch {
        Write-Log "Failed to remove the deferred execution lock. Error: $($_.Exception.Message)" 'WARNING'
    }
    finally {
        $script:DeferredLockOwned = $false
    }
}

function New-DeferredLauncherContent {
    [CmdletBinding()]
    param()

    $escapedScript = $LocalScriptPath.Replace('"','""')
    return @(
        '@echo off',
        'setlocal',
        'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $escapedScript + '" -RunDeferred',
        'exit /b %errorlevel%'
    ) -join [Environment]::NewLine
}


function Invoke-Schtasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter()]
        [switch]$IgnoreExitCode
    )

    $escapedArguments = foreach ($arg in $Arguments) {
        if ($null -eq $arg) { '""'; continue }
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '"','\"') + '"'
        }
        else {
            $arg
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'schtasks.exe'
    $psi.Arguments = ($escapedArguments -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    $result = [pscustomobject]@{
        ExitCode = [int]$proc.ExitCode
        StdOut   = $stdout.Trim()
        StdErr   = $stderr.Trim()
    }

    if ((-not $IgnoreExitCode) -and ($result.ExitCode -ne 0)) {
        $msgParts = @("schtasks.exe retornou ExitCode=$($result.ExitCode).")
        if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) { $msgParts += "StdOut='$($result.StdOut)'." }
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) { $msgParts += "StdErr='$($result.StdErr)'." }
        throw ($msgParts -join ' ')
    }

    return $result
}

function Register-DeferredScheduledTask {
    [CmdletBinding()]
    param()

    Ensure-Directory -Path $StageRoot

    Copy-ScriptToStage -DestinationPath $LocalScriptPath
    Confirm-StagedFile -Path $LocalScriptPath -Label 'Local PowerShell script'

    if (-not (Test-InstallerCacheIsUsable -Path $StageInstallerPath)) {
        Copy-InstallerToStage -SourcePath $SourceInstallerPath -DestinationPath $StageInstallerPath
    }
    Confirm-StagedFile -Path $StageInstallerPath -Label 'GLPI Agent installer'

    $launcherContent = New-DeferredLauncherContent
    [System.IO.File]::WriteAllText($LauncherCmdPath, $launcherContent, [System.Text.UTF8Encoding]::new($false))
    Confirm-StagedFile -Path $LauncherCmdPath -Label 'Launcher CMD local'

    $taskDelete = Invoke-Schtasks -Arguments @('/Delete','/TN',$ScheduledTaskName,'/F') -IgnoreExitCode
    if ($taskDelete.ExitCode -eq 0) {
        Write-Log "Scheduled task '$ScheduledTaskName' previously removed for recreation."
    }

    $startTime = (Get-Date).AddMinutes(1).ToString('HH:mm')
    $createArgs = @(
        '/Create',
        '/TN', $ScheduledTaskName,
        '/TR', ('"{0}"' -f $LauncherCmdPath),
        '/SC', 'ONCE',
        '/ST', $startTime,
        '/RU', 'SYSTEM',
        '/RL', 'HIGHEST',
        '/F'
    )
    $createResult = Invoke-Schtasks -Arguments $createArgs
    if (-not [string]::IsNullOrWhiteSpace($createResult.StdOut)) {
        Write-Log "schtasks /Create: $($createResult.StdOut)"
    }

    $runResult = Invoke-Schtasks -Arguments @('/Run','/TN',$ScheduledTaskName) -IgnoreExitCode
    if ($runResult.ExitCode -eq 0) {
        Write-Log "Scheduled task '$ScheduledTaskName' started immediately."
    }
    else {
        $warnParts = @("Scheduled task '$ScheduledTaskName' was created, but immediate start returned ExitCode=$($runResult.ExitCode).")
        if (-not [string]::IsNullOrWhiteSpace($runResult.StdOut)) { $warnParts += "StdOut='$($runResult.StdOut)'." }
        if (-not [string]::IsNullOrWhiteSpace($runResult.StdErr)) { $warnParts += "StdErr='$($runResult.StdErr)'." }
        Write-Log ($warnParts -join ' ') 'WARNING'
    }

    Write-Log "Scheduled task '$ScheduledTaskName' created/updated for deferred execution through schtasks.exe. StageRoot='$StageRoot'."
}

function Remove-DeferredScheduledTask {
    param (
        [string]$TaskName = $ScheduledTaskName
    )

    try {
        if ([string]::IsNullOrWhiteSpace($TaskName)) {
            Write-Log "Scheduled task does not exist; no removal required." "INFO"
            return
        }

        $queryOutput = & schtasks.exe /Query /TN $TaskName 2>&1
        $queryExitCode = $LASTEXITCODE

        if ($queryExitCode -ne 0) {
            $queryText = ($queryOutput | Out-String).Trim()
            $queryText = $queryText -replace "not", "not"
            $queryText = $queryText -replace "invalid", "invalid"

            if ($queryText -match "cannot find|does not exist") {
                Write-Log "Scheduled task '$TaskName' does not exist; no removal required." "INFO"
                return
            }

            Write-Log "Unable to confirm the existence of the scheduled task '$TaskName'. StdErr='$queryText'." "WARNING"
            return
        }

        $deleteOutput = & schtasks.exe /Delete /TN $TaskName /F 2>&1
        $deleteExitCode = $LASTEXITCODE
        $deleteText = ($deleteOutput | Out-String).Trim()
        $deleteText = $deleteText -replace "not", "not"
        $deleteText = $deleteText -replace "invalid", "invalid"

        if ($deleteExitCode -eq 0) {
            Write-Log "Scheduled task '$TaskName' successfully removed." "INFO"
        }
        elseif ($deleteText -match "cannot find|does not exist") {
            Write-Log "Scheduled task '$TaskName' does not exist; no removal required." "INFO"
        }
        else {
            Write-Log "Failed to remove the scheduled task '$TaskName'. ExitCode=$deleteExitCode. StdErr='$deleteText'." "WARNING"
        }
    }
    catch {
        Write-Log "Unexpected error while removing the scheduled task '$TaskName'. Details: $($_.Exception.Message)" "ERROR"
    }
}

function Invoke-GLPIInstallFromStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [Parameter(Mandatory = $true)]
        [string]$DomainTag
    )

    $installArgs = @(
        '/i',
        ('"{0}"' -f $InstallerPath),
        '/quiet',
        '/norestart',
        '/l*v',
        ('"{0}"' -f $msiLogPath),
        ('SERVER="{0}"' -f $ServerUrl),
        ('TAG="{0}"' -f $DomainTag),
        ('HTTPD_TRUST="{0}"' -f $HttpdTrust),
        ('DELAYTIME={0}' -f $DelayTime),
        ('EXECMODE={0}' -f $ExecMode),
        'ADD_FIREWALL_EXCEPTION=1',
        'RUNNOW=1'
    )

    if ($FullInventory) {
        $installArgs += 'FULL=1'
    }

    Write-Log ("Prepared command line for staged MSI: msiexec.exe {0}" -f ($installArgs -join ' '))
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
    $exitCode = [int]$process.ExitCode
    $exitDesc = Get-MsiExitCodeDescription -ExitCode $exitCode

    Write-Log "msiexec completed in deferred mode. ExitCode=$exitCode | Interpretation='$exitDesc'."

    if ($exitCode -eq 1618) {
        throw "The GLPI Agent installation cannot continue because another MSI installation is already in progress (ExitCode 1618)."
    }

    if (-not (Test-MsiExitCodeSuccess -ExitCode $exitCode)) {
        throw "The GLPI Agent installation failed in deferred mode. ExitCode=$exitCode | Interpretation='$exitDesc'."
    }
}

function Invoke-GLPIReconfigureOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DomainTag,

        [Parameter()]
        [AllowNull()]
        $InstalledInfo
    )

    $footprintBefore = Test-GLPIOperationalFootprint
    Write-Log "Operational footprint before reconfiguration: ExecutableFound=$($footprintBefore.ExecutableFound) | ExecutablePath='$($footprintBefore.ExecutablePath)' | ServicesFound=$($footprintBefore.ServicesFound) | ServiceCount=$($footprintBefore.ServiceCount) | FinalState='$($footprintBefore.FinalState)'."

    $installLocation = $null
    if ($null -ne $InstalledInfo) { $installLocation = $InstalledInfo.InstallLocation }

    $configFile = Set-GLPIManagedConfiguration -Server $ServerUrl -Tag $DomainTag -HttpdTrustValue $HttpdTrust -Delay $DelayTime -Mode $ExecMode -EnableFullInventory $FullInventory -ExecutablePath $footprintBefore.ExecutablePath -InstallLocation $installLocation
    Write-Log "Managed configuration file successfully written to '$configFile'."

    if ($footprintBefore.ExecutableFound) {
        try {
            Write-Log "Starting immediate GLPI Agent inventory after reconfiguration. Argumentos='--force --logger=stderr'."
            $runResult = Invoke-GLPIAgentOnce -ExecutablePath $footprintBefore.ExecutablePath
            Write-Log "Immediate GLPI Agent inventory result after reconfiguration: ExitCode=$($runResult.ExitCode) | Success=$($runResult.Succeeded)."
            if (-not $runResult.Succeeded) {
                Write-Log "The GLPI Agent was executed, but returned ExitCode=$($runResult.ExitCode). The configuration remains applied; review the agent log if the inventory does not reach GLPI." 'WARNING'
            }
        }
        catch {
            Write-Log "Failed to start immediate inventory after reconfiguration. The configuration remains applied. Error: $($_.Exception.Message)" 'WARNING'
        }
    }
    else {
        Write-Log 'The GLPI Agent executable was not found during reconfiguration. The configuration was written, but binary validation was not performed.' 'WARNING'
    }

    Start-Sleep -Seconds 2
    $footprintAfterConfig = Test-GLPIOperationalFootprint
    Write-Log "Operational footprint after reconfiguration: ExecutableFound=$($footprintAfterConfig.ExecutableFound) | ExecutablePath='$($footprintAfterConfig.ExecutablePath)' | ServicesFound=$($footprintAfterConfig.ServicesFound) | ServiceCount=$($footprintAfterConfig.ServiceCount) | FinalState='$($footprintAfterConfig.FinalState)'."
}

function Invoke-GLPIFinalValidation {
    [CmdletBinding()]
    param()

    Start-Sleep -Seconds 3
    $installedAfter = Get-GLPIInstalledInfo
    $footprintAfter = Test-GLPIOperationalFootprint

    Write-Log "Final operational footprint: ExecutableFound=$($footprintAfter.ExecutableFound) | ExecutablePath='$($footprintAfter.ExecutablePath)' | ServicesFound=$($footprintAfter.ServicesFound) | ServiceCount=$($footprintAfter.ServiceCount) | FinalState='$($footprintAfter.FinalState)'."

    if ($installedAfter) {
        Write-Log "Final detection result: Method='$($installedAfter.DetectionMethod)' | Name='$($installedAfter.DisplayName)' | Version='$($installedAfter.DisplayVersion)' | Reference='$($installedAfter.RegistryPath)'."
        $configFileAfter = Set-GLPIManagedConfiguration -Server $ServerUrl -Tag (Get-MachineDomainTag) -HttpdTrustValue $HttpdTrust -Delay $DelayTime -Mode $ExecMode -EnableFullInventory $FullInventory -ExecutablePath $footprintAfter.ExecutablePath -InstallLocation $installedAfter.InstallLocation
        Write-Log "Managed configuration file successfully written/updated at '$configFileAfter'."
    }
    else {
        Write-Log 'Final detection did not locate GLPI Agent through registry or known executable paths.' 'WARNING'
    }

    if ($footprintAfter.ExecutableFound) {
        try {
            Write-Log "Starting immediate GLPI Agent inventory after final convergence. Argumentos='--force --logger=stderr'."
            $runResult = Invoke-GLPIAgentOnce -ExecutablePath $footprintAfter.ExecutablePath
            Write-Log "Immediate GLPI Agent inventory result after final convergence: ExitCode=$($runResult.ExitCode) | Success=$($runResult.Succeeded)."
            if (-not $runResult.Succeeded) {
                Write-Log "The GLPI Agent was executed after convergence, but returned ExitCode=$($runResult.ExitCode). Review connectivity with '$ServerUrl' and the agent log." 'WARNING'
            }
        }
        catch {
            Write-Log "Failed to start immediate inventory after final convergence. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    return [pscustomobject]@{
        InstalledInfo = $installedAfter
        Footprint     = $footprintAfter
    }
}

try {
    Initialize-Log
    Initialize-MsiLog
    Ensure-Directory -Path $StageRoot

    $computerName = $env:COMPUTERNAME
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log '============================================================'
    Write-Log 'Starting GLPI Agent deployment script execution.'
    Write-Log "Name do computador: '$computerName'."
    Write-Log "Execution identity: '$currentIdentity'."
    Write-Log "SourceInstallerPath: '$SourceInstallerPath'."
    Write-Log "StageRoot: '$StageRoot'."
    Write-Log "StageInstallerPath: '$StageInstallerPath'."
    Write-Log "LocalScriptPath: '$LocalScriptPath'."
    Write-Log "LauncherCmdPath: '$LauncherCmdPath'."
    Write-Log "StateFilePath: '$StateFilePath'."
    Write-Log "RunDeferred: $RunDeferred."
    Write-Log "Expected target version: '$ExpectedVersion'."
    Write-Log "Monitored fixed registry key: '$fixedRegistryPath'."
    Write-Log "Log directory: '$LogDirectory'."
    Write-Log "MSI log file: '$msiLogPath'."
    Write-Log "Configured parameters: HTTPD_TRUST='$HttpdTrust' | DELAYTIME='$DelayTime' | EXECMODE='$ExecMode' | FULL='$([int]$FullInventory)'."
    Write-MsiLogMarker -ComputerName $computerName

    if (-not (Test-Admin)) {
        throw 'This script must be executed with administrative privileges.'
    }

    if (-not $RunDeferred) {
        Write-Log 'Online bootstrap mode started.'
        $domainTag = Get-MachineDomainTag
        Write-Log "TAG resolved with priority from the machine DNS domain: '$domainTag'."

        $installed = Get-GLPIInstalledInfo
        $executableInfo = Get-GLPIExecutableInfo
        $baselineCompliance = Test-GLPI117BaselineCompliance -RegistryKey $fixedRegistryPath -ExpectedDisplayName $expectedDisplayName -ExpectedDisplayVersion $ExpectedVersion
        $hybridDivergence = Test-GLPIHybridDivergence -BaselineCompliance $baselineCompliance -ExecutableInfo $executableInfo -ExpectedDisplayVersion $ExpectedVersion
        $action = 'INSTALL'

        Write-Log "Strict 1.17 baseline compliance: KeyPresent=$($baselineCompliance.KeyPresent) | NameEsperado='$expectedDisplayName' | ActualName='$($baselineCompliance.ActualDisplayName)' | ExpectedVersion='$ExpectedVersion' | ActualVersion='$($baselineCompliance.ActualDisplayVersion)' | Compliant=$($baselineCompliance.IsCompliant)."
        if ($null -ne $executableInfo) {
            Write-Log "GLPI executable detected separately: Version='$($executableInfo.DisplayVersion)' | Path='$($executableInfo.ExecutablePath)' | Architecture='$($executableInfo.Architecture)'."
        }

        if ($installed) {
            Write-Log "GLPI Agent detected by '$($installed.DetectionMethod)'. Name='$($installed.DisplayName)' | Version='$($installed.DisplayVersion)' | Architecture='$($installed.Architecture)' | Reference='$($installed.RegistryPath)'."
            $comparison = Compare-VersionText -Left $installed.DisplayVersion -Right $ExpectedVersion

            if ($hybridDivergence.ExecutablePath) {
                Write-Log "GLPI executable detected separately as diagnostic telemetry: Version='$($hybridDivergence.ExecutableVersion)' | Path='$($hybridDivergence.ExecutablePath)'. The operational decision will continue to be based on the registry-validated enterprise baseline."
            }

            if ($comparison -lt 0) {
                $action = 'INSTALL'
                Write-Log "The installed version '$($installed.DisplayVersion)' is lower than the target version '$ExpectedVersion'. Local staging will be prepared for upgrade and reconfiguration." 'WARNING'
            }
            elseif ($comparison -eq 0) {
                if ($baselineCompliance.IsCompliant) {
                    $action = 'RECONFIGURE_ONLY'
                    Write-Log "The installed version '$($installed.DisplayVersion)' matches the baseline exactly '$ExpectedVersion' and the fixed baseline key is compliant. Only reconfiguration will be executed."
                }
                else {
                    $action = 'INSTALL'
                    Write-Log "The detected version is '$($installed.DisplayVersion)', but the fixed 1.17 baseline key is not compliant. Local staging will be prepared for baseline repair/reinstallation." 'WARNING'
                }
            }
            else {
                $action = 'RECONFIGURE_ONLY'
                Write-Log "The installed version '$($installed.DisplayVersion)' is higher than the baseline '$ExpectedVersion'. No downgrade will be performed; reconfiguration only." 'WARNING'
            }
        }
        else {
            if ($hybridDivergence.ExecutablePath) {
                Write-Log "GLPI executable detected without a selected registry candidate: Version='$($hybridDivergence.ExecutableVersion)' | Path='$($hybridDivergence.ExecutablePath)'. Local staging will be prepared for installation or baseline correction." 'WARNING'
            }
            else {
                Write-Log 'GLPI Agent was not detected. Local staging will be prepared for installation.' 'WARNING'
            }
        }

        if ($action -eq 'RECONFIGURE_ONLY') {
            Invoke-GLPIReconfigureOnly -DomainTag $domainTag -InstalledInfo $installed
            Remove-DeferredScheduledTask
            Write-Log 'Bootstrap flow completed without requiring binary installation.'
            Write-Log 'Script execution finished.'
            Write-Log '============================================================'
            exit 0
        }

        if (-not (Test-Path -LiteralPath $SourceInstallerPath)) {
            throw "The source MSI installer was not found at '$SourceInstallerPath'."
        }

        $bootstrapState = [pscustomobject]@{
            SavedAt         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            DomainTag       = $domainTag
            DesiredAction   = $action
            SourceInstaller = $SourceInstallerPath
            StageInstaller  = $StageInstallerPath
            ExpectedVersion = $ExpectedVersion
            BootstrapHost   = $computerName
        }

        Save-GLPIBootstrapState -State $bootstrapState
        Register-DeferredScheduledTask
        Write-Log "Bootstrap completed with local staging and deferred execution. Task='$ScheduledTaskName'."
        Write-Log 'Script execution finished.'
        Write-Log '============================================================'
        exit 0
    }

    Write-Log 'Offline deferred mode started. Validating local staging.'
    Write-Log "LocalScriptPath: $LocalScriptPath | Exists=$([bool](Test-Path -LiteralPath $LocalScriptPath))."
    Write-Log "StageInstallerPath: $StageInstallerPath | Exists=$([bool](Test-Path -LiteralPath $StageInstallerPath))."

    Confirm-StagedFile -Path $LocalScriptPath -Label 'Local PowerShell script'
    Confirm-StagedFile -Path $StageInstallerPath -Label 'GLPI Agent installer'

    if (-not (Acquire-DeferredRunLock)) {
        exit 0
    }

    try {
        $deferredState = Get-GLPIDeferredState
        Write-Log "Deferred state loaded: SavedAt='$($deferredState.SavedAt)' | DomainTag='$($deferredState.DomainTag)' | DesiredAction='$($deferredState.DesiredAction)'."

        $installed = Get-GLPIInstalledInfo
        $executableInfo = Get-GLPIExecutableInfo
        $baselineCompliance = Test-GLPI117BaselineCompliance -RegistryKey $fixedRegistryPath -ExpectedDisplayName $expectedDisplayName -ExpectedDisplayVersion $ExpectedVersion
        $hybridDivergence = Test-GLPIHybridDivergence -BaselineCompliance $baselineCompliance -ExecutableInfo $executableInfo -ExpectedDisplayVersion $ExpectedVersion
        $effectiveAction = 'INSTALL'

        if ($null -ne $executableInfo) {
            Write-Log "GLPI executable detected in deferred mode: Version='$($executableInfo.DisplayVersion)' | Path='$($executableInfo.ExecutablePath)' | Architecture='$($executableInfo.Architecture)'."
        }

        if ($hybridDivergence.ExecutablePath) {
            Write-Log "Deferred mode recorded GLPI executable telemetry: Version='$($hybridDivergence.ExecutableVersion)' | Path='$($hybridDivergence.ExecutablePath)'. The decision will continue to be based on registry state and the enterprise baseline."
        }

        if ($installed) {
            $comparison = Compare-VersionText -Left $installed.DisplayVersion -Right $ExpectedVersion
            if ($comparison -gt 0) {
                $effectiveAction = 'RECONFIGURE_ONLY'
            }
            elseif ($comparison -eq 0 -and $baselineCompliance.IsCompliant) {
                $effectiveAction = 'RECONFIGURE_ONLY'
            }
            else {
                $effectiveAction = 'INSTALL'
            }
        }

        if ($effectiveAction -eq 'RECONFIGURE_ONLY') {
            Invoke-GLPIReconfigureOnly -DomainTag $deferredState.DomainTag -InstalledInfo $installed
            Remove-DeferredScheduledTask
            Write-Log 'Deferred mode completed reconfiguration only.'
            Write-Log 'Script execution finished.'
            Write-Log '============================================================'
            exit 0
        }

        Invoke-GLPIInstallFromStage -InstallerPath $StageInstallerPath -DomainTag $deferredState.DomainTag
        $validation = Invoke-GLPIFinalValidation

        if ($validation.InstalledInfo) {
            $finalComparison = Compare-VersionText -Left $validation.InstalledInfo.DisplayVersion -Right $ExpectedVersion
            $baselineComplianceAfter = Test-GLPI117BaselineCompliance -RegistryKey $fixedRegistryPath -ExpectedDisplayName $expectedDisplayName -ExpectedDisplayVersion $ExpectedVersion
            $executableInfoAfter = Get-GLPIExecutableInfo
            $hybridDivergenceAfter = Test-GLPIHybridDivergence -BaselineCompliance $baselineComplianceAfter -ExecutableInfo $executableInfoAfter -ExpectedDisplayVersion $ExpectedVersion
            Write-Log "Strict post-installation compliance: KeyPresent=$($baselineComplianceAfter.KeyPresent) | ActualName='$($baselineComplianceAfter.ActualDisplayName)' | ActualVersion='$($baselineComplianceAfter.ActualDisplayVersion)' | Compliant=$($baselineComplianceAfter.IsCompliant)."
            if ($null -ne $executableInfoAfter) {
                Write-Log "Post-installation GLPI executable: Version='$($executableInfoAfter.DisplayVersion)' | Path='$($executableInfoAfter.ExecutablePath)' | Architecture='$($executableInfoAfter.Architecture)'."
            }

            if ($finalComparison -lt 0) {
                Write-Log "Final validation did not confirm the baseline '$ExpectedVersion'. Review '$msiLogPath'." 'WARNING'
                exit 1
            }
            elseif (($finalComparison -eq 0) -and (-not $baselineComplianceAfter.IsCompliant)) {
                Write-Log "The final detected version is '$($validation.InstalledInfo.DisplayVersion)', but the fixed 1.17 baseline key was not confirmed as compliant after installation. Review '$msiLogPath'." 'WARNING'
                exit 1
            }
            elseif ($hybridDivergenceAfter.ExecutablePath) {
                Write-Log "Post-installation GLPI executable telemetry: Version='$($hybridDivergenceAfter.ExecutableVersion)' | Path='$($hybridDivergenceAfter.ExecutablePath)'. The enterprise baseline will remain authoritative for decision and compliance."
            }
        }
        else {
            Write-Log "Final validation did not confirm agent installation. Review '$msiLogPath'." 'WARNING'
            exit 1
        }

        Remove-DeferredScheduledTask
        Write-Log "Final agent state: '$($validation.Footprint.FinalState)'."
        Write-Log 'Deferred mode completed convergence successfully.'
        Write-Log 'Script execution finished.'
        Write-Log '============================================================'
        exit 0
    }
    finally {
        Release-DeferredRunLock
    }
}
catch {
    $errorMessage = $_.Exception.Message
    try {
        Write-Log "Critical failure: $errorMessage" 'ERROR'
        Write-Log 'Script execution finished.'
        Write-Log '============================================================'
    }
    catch {}
    exit 1
}

# End of script
