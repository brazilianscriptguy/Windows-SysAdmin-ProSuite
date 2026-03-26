<#
.SYNOPSIS
  Installs or upgrades GLPI Agent via machine GPO, avoiding boot blocking when executed in Startup context.

.DESCRIPTION
  - Detects installed GLPI Agent using:
      1) known fixed registry key,
      2) standard Uninstall registry locations (64-bit and WOW6432Node),
      3) known executable paths.
  - If the expected major/minor version is already installed, installation is skipped (idempotent behavior).
  - If absent or different, runs the MSI silently and writes logs to the configured log directory.
  - Does not forcibly uninstall previous versions; relies on native MSI upgrade behavior.
  - Detects GPO Startup context and does NOT wait for msiexec in that path, reducing boot impact.
  - Performs richer post-install validation in synchronous execution mode.

.AUTHOR
  Luiz Hamilton Silva (@brazilianscriptguy)

.VERSION
  Last Updated: 2026-03-26
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$GLPIAgentMSI = "\\headq.scriptguy\netlogon\glpi-agent-install\glpi-agent116-install.msi",

    [Parameter()]
    [string]$GLPILogDir = "C:\Logs-TEMP",

    [Parameter()]
    [string]$ExpectedVersion = "1.16",

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
    [string]$TagOverride = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($scriptName)) {
    $scriptName = 'glpi-agent-install'
}

$logFileName = "$scriptName.log"
$logPath = Join-Path -Path $GLPILogDir -ChildPath $logFileName
$msiLogPath = Join-Path -Path $GLPILogDir -ChildPath 'glpi-msi-install.log'

# Known historical ProductCode path retained as first-class detection candidate.
$fixedRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{960934CD-6BF4-1014-B0BF-CA310C0FF926}'

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
            # Do not break execution due to residual logging failure.
        }
    }
}

function Initialize-Log {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $GLPILogDir)) {
        try {
            New-Item -Path $GLPILogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to create log directory '$GLPILogDir'. Error: $($_.Exception.Message)"
        }
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

function Get-GLPIExecutablePath {
    [CmdletBinding()]
    param()

    $candidates = @(
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
        3010 { return 'Success, reboot required' }
        1641 { return 'Success, reboot initiated' }
        1618 { return 'Another installation is already in progress' }
        default { return 'MSI execution returned a non-mapped exit code' }
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
                DetectionMethod = 'Registry-Uninstall'
            }
        }
    }
    catch {
        # Ignore and continue.
    }

    return $null
}

function Get-GLPIInstalledInfo {
    [CmdletBinding()]
    param()

    # 1) Fixed known key first
    if (Test-Path -LiteralPath $fixedRegistryPath) {
        try {
            $item = Get-ItemProperty -LiteralPath $fixedRegistryPath -ErrorAction Stop
            return [PSCustomObject]@{
                DisplayName     = $item.DisplayName
                DisplayVersion  = $item.DisplayVersion
                InstallLocation = $item.InstallLocation
                RegistryPath    = $fixedRegistryPath
                RegistryKey     = '{960934CD-6BF4-1014-B0BF-CA310C0FF926}'
                Architecture    = '64-bit'
                DetectionMethod = 'Registry-FixedKey'
            }
        }
        catch {
            Write-Log "Failed to read fixed registry path '$fixedRegistryPath'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    # 2) Standard uninstall locations
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
                        return $candidate
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to enumerate uninstall root '$($root.Path)'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    # 3) Executable fallback
    $exe = Get-GLPIExecutablePath
    if ($exe) {
        try {
            $file = Get-Item -LiteralPath $exe -ErrorAction Stop
            $fileVersion = $file.VersionInfo.ProductVersion
            if ([string]::IsNullOrWhiteSpace($fileVersion)) {
                $fileVersion = $file.VersionInfo.FileVersion
            }

            if (-not [string]::IsNullOrWhiteSpace($fileVersion)) {
                $architecture = if ($exe -like '*Program Files (x86)*') { '32-bit' } else { '64-bit' }
                return [PSCustomObject]@{
                    DisplayName     = 'GLPI Agent (File Detection)'
                    DisplayVersion  = $fileVersion
                    InstallLocation = Split-Path -Path $exe -Parent
                    RegistryPath    = '(file)'
                    RegistryKey     = '(file)'
                    Architecture    = $architecture
                    DetectionMethod = 'File'
                }
            }
        }
        catch {
            Write-Log "Failed to retrieve executable version from '$exe'. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    return $null
}

function Test-ExpectedVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$InstalledVersion,

        [Parameter(Mandatory = $true)]
        [string]$TargetVersion
    )

    if ([string]::IsNullOrWhiteSpace($InstalledVersion)) {
        return $false
    }

    # Conservative behavior preserved:
    # Target "1.16" accepts "1.16", "1.16.0", "1.16.x.y", etc.
    $pattern = '^{0}(\.|$)' -f [regex]::Escape($TargetVersion)
    return ($InstalledVersion -match $pattern)
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
        Write-Log "Failed to query Win32_ComputerSystem for machine domain tag resolution. Error: $($_.Exception.Message)" 'WARNING'
    }

    try {
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction Stop |
            Where-Object { $_.IPEnabled -eq $true -and -not [string]::IsNullOrWhiteSpace($_.DNSDomain) }

        foreach ($adapter in $adapters) {
            $candidates.Add([string]$adapter.DNSDomain)
        }
    }
    catch {
        Write-Log "Failed to query DNSDomain from active interfaces for machine tag resolution. Error: $($_.Exception.Message)" 'WARNING'
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
    }

    $exe = Get-GLPIExecutablePath
    if ($exe) {
        $result.ExecutableFound = $true
        $result.ExecutablePath  = $exe
    }

    $services = Get-GLPIServices
    if ($services.Count -gt 0) {
        $result.ServicesFound = $true
        $result.Services      = $services
    }

    return $result
}

try {
    Initialize-Log

    $computerName = $env:COMPUTERNAME
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log 'Starting glpi-agent-install.'
    Write-Log "ComputerName: '$computerName'."
    Write-Log "Execution identity: '$currentIdentity'."
    Write-Log "MSI installer path: '$GLPIAgentMSI'."
    Write-Log "Expected version target: '$ExpectedVersion'."
    Write-Log "Fixed monitored registry path: '$fixedRegistryPath'."
    Write-Log "Log directory: '$GLPILogDir'."
    Write-Log "MSI log file: '$msiLogPath'."
    Write-Log "Configured install parameters: HTTPD_TRUST='$HttpdTrust' | DELAYTIME='$DelayTime' | EXECMODE='$ExecMode' | FULL='$([int]$FullInventory)'."

    $isGpoStartup = Get-GpoStartupContext
    Write-Log "GPO Startup context detected: $isGpoStartup."

    $domainTag = Get-MachineDomainTag
    Write-Log "Resolved TAG with priority to machine DNS domain: '$domainTag'."

    if (-not (Test-Path -LiteralPath $GLPIAgentMSI)) {
        throw "MSI installer was not found at '$GLPIAgentMSI'."
    }

    Write-Log "MSI installer located successfully at '$GLPIAgentMSI'."

    $installed = Get-GLPIInstalledInfo
    $needInstall = $true

    if ($installed) {
        Write-Log "GLPI Agent detected by '$($installed.DetectionMethod)'. Name='$($installed.DisplayName)' | Version='$($installed.DisplayVersion)' | Architecture='$($installed.Architecture)' | Reference='$($installed.RegistryPath)'."

        if (Test-ExpectedVersion -InstalledVersion $installed.DisplayVersion -TargetVersion $ExpectedVersion) {
            $needInstall = $false
            Write-Log "Installed version '$($installed.DisplayVersion)' already satisfies target '$ExpectedVersion'. Installation will be skipped idempotently."
        }
        else {
            Write-Log "Installed version '$($installed.DisplayVersion)' differs from target '$ExpectedVersion'. MSI will run for upgrade/correction." 'WARNING'
        }
    }
    else {
        Write-Log "GLPI Agent was not detected by fixed registry key, uninstall registry locations, or known executable path. MSI will run." 'WARNING'
    }

    if (-not $needInstall) {
        $footprint = Test-GLPIOperationalFootprint

        if ($footprint.ExecutableFound) {
            Write-Log "Executable confirmed at '$($footprint.ExecutablePath)'."
        }
        else {
            Write-Log 'GLPI executable was not found during final idempotent validation.' 'WARNING'
        }

        if ($footprint.ServicesFound) {
            $serviceNames = ($footprint.Services | ForEach-Object { "'$($_.Name)'" }) -join ', '
            Write-Log "Related GLPI service(s) identified: $serviceNames."
        }
        else {
            Write-Log 'No GLPI-related service was identified during final idempotent validation.' 'WARNING'
        }

        Write-Log 'Flow completed without installation requirement.'
        exit 0
    }

    $installArgs = @(
        '/i',
        ('"{0}"' -f $GLPIAgentMSI),
        '/quiet',
        '/norestart',
        '/l*v',
        ('"{0}"' -f $msiLogPath),
        ('SERVER="{0}"' -f $ServerUrl),
        ('TAG="{0}"' -f $domainTag),
        ('HTTPD_TRUST="{0}"' -f $HttpdTrust),
        ('DELAYTIME={0}' -f $DelayTime),
        ('EXECMODE={0}' -f $ExecMode),
        'ADD_FIREWALL_EXCEPTION=1',
        'RUNNOW=1'
    )

    if ($FullInventory) {
        $installArgs += 'FULL=1'
    }

    $installArgsForLog = $installArgs -join ' '
    Write-Log "Prepared MSI command line: msiexec.exe $installArgsForLog"
    Write-Log "Additional parameters: HTTPD_TRUST='$HttpdTrust' | DELAYTIME='$DelayTime' | EXECMODE='$ExecMode' | ADD_FIREWALL_EXCEPTION='1' | RUNNOW='1' | FULL='$([int]$FullInventory)'."

    if ($isGpoStartup) {
        Write-Log 'Startup GPO context detected. msiexec will be launched asynchronously to reduce boot impact.'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -WindowStyle Hidden -PassThru -ErrorAction Stop
        Write-Log "msiexec launched successfully in asynchronous mode. PID=$($process.Id). Final result has NOT been validated in this execution path. Review MSI log at '$msiLogPath'."
        Write-Log 'Flow completed after asynchronous installer trigger in Startup GPO context.'
        exit 0
    }
    else {
        Write-Log 'Non-Startup-GPO context detected. msiexec will run synchronously and wait for completion.'
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $installArgs -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
        $exitCode = [int]$process.ExitCode
        $exitDesc = Get-MsiExitCodeDescription -ExitCode $exitCode

        Write-Log "msiexec finished. ExitCode=$exitCode | Meaning='$exitDesc'."

        if ($exitCode -eq 1618) {
            throw "GLPI Agent installation could not proceed because another MSI installation is already in progress (ExitCode 1618). Review '$msiLogPath'."
        }

        if (-not (Test-MsiExitCodeSuccess -ExitCode $exitCode)) {
            throw "GLPI Agent installation failed. ExitCode=$exitCode | Meaning='$exitDesc'. Review '$msiLogPath'."
        }

        Start-Sleep -Seconds 3
        $installedAfter = Get-GLPIInstalledInfo
        $footprintAfter = Test-GLPIOperationalFootprint

        if ($installedAfter) {
            Write-Log "Post-install detection result: Method='$($installedAfter.DetectionMethod)' | Name='$($installedAfter.DisplayName)' | Version='$($installedAfter.DisplayVersion)' | Reference='$($installedAfter.RegistryPath)'."
        }
        else {
            Write-Log 'Post-install detection did not find GLPI Agent in registry or executable fallback.' 'WARNING'
        }

        if ($footprintAfter.ExecutableFound) {
            Write-Log "Post-install executable confirmed at '$($footprintAfter.ExecutablePath)'."
        }
        else {
            Write-Log 'Post-install executable was not found.' 'WARNING'
        }

        if ($footprintAfter.ServicesFound) {
            $serviceNamesAfter = ($footprintAfter.Services | ForEach-Object { "'$($_.Name)'" }) -join ', '
            Write-Log "Post-install related service(s) identified: $serviceNamesAfter."
        }
        else {
            Write-Log 'No GLPI-related service was identified after installation.' 'WARNING'
        }

        if ($installedAfter -and (Test-ExpectedVersion -InstalledVersion $installedAfter.DisplayVersion -TargetVersion $ExpectedVersion)) {
            if ($exitCode -eq 3010) {
                Write-Log "Post-install validation succeeded. GLPI Agent version '$($installedAfter.DisplayVersion)' matches target '$ExpectedVersion'. A reboot is required." 'WARNING'
            }
            elseif ($exitCode -eq 1641) {
                Write-Log "Post-install validation succeeded. GLPI Agent version '$($installedAfter.DisplayVersion)' matches target '$ExpectedVersion'. MSI initiated reboot." 'WARNING'
            }
            else {
                Write-Log "Post-install validation succeeded. GLPI Agent version '$($installedAfter.DisplayVersion)' matches target '$ExpectedVersion'."
            }

            exit 0
        }
        else {
            Write-Log "msiexec completed with a success-class exit code, but post-install validation did not confirm target version '$ExpectedVersion'. Review '$msiLogPath'." 'WARNING'
            exit 0
        }
    }
}
catch {
    $errorMessage = $_.Exception.Message
    try {
        Write-Log "Critical failure: $errorMessage" 'ERROR'
    }
    catch {
        # Ignore residual logging failure.
    }
    exit 1
}

# End of script
