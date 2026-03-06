<#
.SYNOPSIS
  WinGet bootstrap and repair for Windows Server 2019.

.DESCRIPTION
  Installs or repairs WinGet using App Installer (Microsoft.DesktopAppInstaller)
  with package-aware validation and a machine-wide bridge wrapper.

  Key fixes in this revision:
    1. Avoid relying on the winget alias inside cmd.exe package context.
    2. Resolve the packaged CLI executable directly from InstallLocation.
    3. Invoke the packaged CLI through Invoke-CommandInDesktopPackage.
    4. Install a stable machine-wide wrapper for server sessions.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-03-06 (v8)
#>

[CmdletBinding()]
param(
    [string]$LogDir = 'C:\Logs-TEMP',
    [string]$SetupRoot = 'C:\ProgramData\WinGet-Setup',
    [string]$BridgeRoot = 'C:\Program Files\WinGet-Bridge',
    [switch]$StrictPrereqs,
    [switch]$SkipBridge,
    [string[]]$CandidateReleases = @(
        'v1.11.180-preview',
        'v1.11.230-preview',
        'latest'
    )
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

function Get-ScriptBaseName {
    try { if ($PSCommandPath) { return [IO.Path]::GetFileNameWithoutExtension($PSCommandPath) } } catch {}
    try { if ($MyInvocation.MyCommand.Path) { return [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path) } } catch {}
    try { if ($MyInvocation.MyCommand.Name) { return [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name) } } catch {}
    return 'new-winget-install-servers'
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

$scriptBase = Get-ScriptBaseName
Ensure-Directory -Path $LogDir
$script:LogPath = Join-Path $LogDir ($scriptBase + '.log')

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1}] {2}' -f $Level, $ts, $Message
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
}

Write-Log -Message ('Log initialized: {0}' -f $script:LogPath)

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enable-Tls12 {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
}

function Join-NativeArgumentString {
    param([string[]]$Arguments = @())

    if (-not $Arguments -or @($Arguments).Count -eq 0) { return '' }

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $Arguments) {
        if ($null -eq $arg) { continue }
        $s = [string]$arg
        if ($s -match '[\s"]') {
            $escaped = $s -replace '"', '\\"'
            $parts.Add(('"{0}"' -f $escaped))
        } else {
            $parts.Add($s)
        }
    }

    return ($parts -join ' ')
}

function Invoke-Native {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSec = 60
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Join-NativeArgumentString -Arguments $Arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        return [PSCustomObject]@{
            ExitCode = 1460
            StdOut   = ''
            StdErr   = 'Timed out'
        }
    }

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        StdOut   = ($p.StandardOutput.ReadToEnd()).Trim()
        StdErr   = ($p.StandardError.ReadToEnd()).Trim()
    }
}

function Download-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$OutFile
    )

    Ensure-Directory -Path (Split-Path $OutFile -Parent)

    if (Test-Path -LiteralPath $OutFile) {
        try {
            $len = (Get-Item -LiteralPath $OutFile -ErrorAction Stop).Length
            if ($len -gt 1024) {
                Write-Log -Message ('Found existing download: {0} ({1} bytes)' -f $OutFile, $len)
                return $true
            }
        } catch {}
        try { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue } catch {}
    }

    Write-Log -Message ('Downloading: {0} -> {1}' -f $Url, $OutFile)
    Enable-Tls12

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        $len2 = (Get-Item -LiteralPath $OutFile -ErrorAction Stop).Length
        Write-Log -Message ('Download OK. Size: {0} bytes.' -f $len2)
        return $true
    } catch {
        Write-Log -Message ('Download failed: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Get-WinGetFromPath {
    foreach ($name in @('winget.exe','winget.cmd','winget')) {
        try {
            $cmd = Get-Command $name -ErrorAction Stop | Select-Object -First 1
            if ($cmd -and $cmd.Source) { return $cmd.Source }
        } catch {}
    }
    return $null
}

function Get-DesktopAppInstallerPackage {
    $packages = @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
    if ($packages.Count -gt 0) { return $packages[0] }
    return $null
}

function Get-PackagedWinGetExecutable {
    $pkg = Get-DesktopAppInstallerPackage
    if (-not $pkg) { return $null }

    $candidates = @(
        (Join-Path $pkg.InstallLocation 'winget.exe'),
        (Join-Path $pkg.InstallLocation 'AppInstallerCLI.exe'),
        (Join-Path $pkg.InstallLocation 'AppInstallerCli.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-OutputLooksLikeWinGetVersion {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -match '(?im)Windows\s+Package\s+Manager\s+v?\d+\.\d+') { return $true }
    if ($Text -match '(?im)^v?\d+\.\d+(?:\.\d+){0,2}$') { return $true }
    return $false
}

function Add-MachinePathEntry {
    param([Parameter(Mandatory=$true)][string]$PathEntry)

    try {
        $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
        $parts = @()
        if ($machinePath) {
            $parts = @($machinePath -split ';' | Where-Object { $_ -and $_.Trim() })
        }

        $exists = $false
        foreach ($part in $parts) {
            if ($part.TrimEnd('\\') -ieq $PathEntry.TrimEnd('\\')) {
                $exists = $true
                break
            }
        }

        if (-not $exists) {
            $newMachinePath = if ([string]::IsNullOrWhiteSpace($machinePath)) { $PathEntry } else { $machinePath.TrimEnd(';') + ';' + $PathEntry }
            [Environment]::SetEnvironmentVariable('Path', $newMachinePath, 'Machine')
            $userPath = [Environment]::GetEnvironmentVariable('Path','User')
            $env:Path = if ([string]::IsNullOrWhiteSpace($userPath)) { $newMachinePath } else { $newMachinePath + ';' + $userPath }
            Write-Log -Message ('Added to PATH (Machine): {0}' -f $PathEntry)
        } else {
            Write-Log -Message ('Already in PATH (Machine): {0}' -f $PathEntry)
        }

        return $true
    } catch {
        Write-Log -Message ('Failed to update PATH: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Test-WinGetFunctional {
    param([Parameter(Mandatory=$true)][string]$WingetPath)

    if (-not (Test-Path -LiteralPath $WingetPath)) { return $false }

    if ($WingetPath -match '\.cmd$') {
        $r = Invoke-Native -FilePath 'C:\Windows\System32\cmd.exe' -Arguments @('/c','winget','--version') -TimeoutSec 30
    } else {
        $r = Invoke-Native -FilePath $WingetPath -Arguments @('--version') -TimeoutSec 30
    }

    if ($r.ExitCode -eq 0 -and (Test-OutputLooksLikeWinGetVersion -Text $r.StdOut)) {
        Write-Log -Message ('winget functional: {0} :: {1}' -f $WingetPath, $r.StdOut)
        return $true
    }

    Write-Log -Message ('winget test failed. ExitCode={0} StdOut=''{1}'' StdErr=''{2}''' -f $r.ExitCode, $r.StdOut, $r.StdErr) -Level 'WARNING'
    return $false
}

function Test-WinGetByAlias {
    $pathCandidate = Get-WinGetFromPath
    if (-not $pathCandidate) { return $false }

    if ($pathCandidate -match 'WindowsApps') {
        Write-Log -Message ('Skipping direct alias execution from WindowsApps path during validation: {0}' -f $pathCandidate)
        return $false
    }

    return (Test-WinGetFunctional -WingetPath $pathCandidate)
}

function Set-AppxPolicies {
    try {
        $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name 'AllowAllTrustedApps' -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $k -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Log -Message 'Ensured AppX policy: AllowAllTrustedApps=1, AllowDevelopmentWithoutDevLicense=1'
        return $true
    } catch {
        Write-Log -Message ('Failed setting AppX policy: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Try-AddAppx {
    param([Parameter(Mandatory=$true)][string]$PackagePath)

    try {
        Add-AppxPackage -Path $PackagePath -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Log -Message ('Add-AppxPackage failed for {0}: {1}' -f $PackagePath, $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Ensure-VCLibs {
    $have = Get-AppxPackage -AllUsers -Name 'Microsoft.VCLibs.140.00*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ('VCLibs detected. Version: {0}' -f $have.Version)
        return $true
    }

    Write-Log -Message 'Ensuring Microsoft.VCLibs.x64.14.00.Desktop (best effort)...'
    $depDir = Join-Path $SetupRoot 'Dependencies'
    Ensure-Directory -Path $depDir
    $vcl = Join-Path $depDir 'Microsoft.VCLibs.x64.14.00.Desktop.appx'
    if (-not (Download-File -Url 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' -OutFile $vcl)) { return $false }

    [void](Try-AddAppx -PackagePath $vcl)
    Start-Sleep -Seconds 2

    $have2 = Get-AppxPackage -AllUsers -Name 'Microsoft.VCLibs.140.00*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ('VCLibs installed/updated. Version: {0}' -f $have2.Version)
        return $true
    }

    Write-Log -Message 'VCLibs still not detected after attempt.' -Level 'WARNING'
    return $false
}

function Ensure-UIXaml28 {
    $have = Get-AppxPackage -AllUsers -Name 'Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ('UI.Xaml detected. Version: {0}' -f $have.Version)
        return $true
    }

    Write-Log -Message 'UI.Xaml not detected. Attempting best-effort install...'
    $depDir = Join-Path $SetupRoot 'Dependencies'
    Ensure-Directory -Path $depDir
    $uix = Join-Path $depDir 'Microsoft.UI.Xaml.2.8.x64.appx'
    if (-not (Download-File -Url 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx' -OutFile $uix)) { return $false }

    [void](Try-AddAppx -PackagePath $uix)
    Start-Sleep -Seconds 2

    $have2 = Get-AppxPackage -AllUsers -Name 'Microsoft.UI.Xaml*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ('UI.Xaml installed. Version: {0}' -f $have2.Version)
        return $true
    }

    Write-Log -Message 'UI.Xaml still not detected after attempt.' -Level 'WARNING'
    return $false
}

function Ensure-WindowsAppRuntime18 {
    $have = Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsAppRuntime.1.8*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have) {
        Write-Log -Message ('WindowsAppRuntime 1.8 detected. Version: {0}' -f $have.Version)
        return $true
    }

    Write-Log -Message 'WindowsAppRuntime 1.8 not detected. Attempting install...'
    $depDir = Join-Path $SetupRoot 'Dependencies'
    Ensure-Directory -Path $depDir
    $exe = Join-Path $depDir ('WindowsAppRuntimeInstall-x64_{0}.exe' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (-not (Download-File -Url 'https://aka.ms/windowsappsdk/1.8/1.8.260209005/windowsappruntimeinstall-x64.exe' -OutFile $exe)) { return $false }

    $r = Invoke-Native -FilePath $exe -Arguments @('/install','/quiet','/norestart') -TimeoutSec 300
    Write-Log -Message ('WindowsAppRuntime installer exit code: {0}' -f $r.ExitCode)

    Start-Sleep -Seconds 2
    $have2 = Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsAppRuntime.1.8*' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($have2) {
        Write-Log -Message ('WindowsAppRuntime 1.8 installed. Version: {0}' -f $have2.Version)
        return $true
    }

    Write-Log -Message 'WindowsAppRuntime 1.8 still not detected after attempt.' -Level 'WARNING'
    return $false
}

function Register-DesktopAppInstallerByFamilyName {
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop | Out-Null
        Write-Log -Message 'DesktopAppInstaller re-registered by family name.'
        return $true
    } catch {
        Write-Log -Message ('RegisterByFamilyName failed: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Test-WinGetViaDesktopPackage {
    $pkg = Get-DesktopAppInstallerPackage
    if (-not $pkg) {
        Write-Log -Message 'DesktopAppInstaller package not currently detected.' -Level 'WARNING'
        return $false
    }

    Write-Log -Message ('DesktopAppInstaller detected. Version={0} InstallLocation={1}' -f $pkg.Version, $pkg.InstallLocation)

    $packagedExe = Get-PackagedWinGetExecutable
    if (-not $packagedExe) {
        Write-Log -Message ('No packaged WinGet CLI executable was found under: {0}' -f $pkg.InstallLocation) -Level 'WARNING'
        return $false
    }

    Write-Log -Message ('Resolved packaged WinGet CLI path: {0}' -f $packagedExe)

    $tempDir = Join-Path $SetupRoot 'Validation'
    Ensure-Directory -Path $tempDir
    $tempOut = Join-Path $tempDir ('winget-version-' + [guid]::NewGuid().ToString('N') + '.txt')

    $escapedExe = $packagedExe.Replace('"','""')
    $escapedOut = $tempOut.Replace('"','""')
    $cmdArgs = '/d /c ""' + $escapedExe + '" --version > "' + $escapedOut + '" 2>&1"'

    try {
        $null = Invoke-CommandInDesktopPackage -PackageFamilyName $pkg.PackageFamilyName -AppId 'winget' -Command 'C:\Windows\System32\cmd.exe' -Args $cmdArgs -PreventBreakaway -ErrorAction Stop
        Start-Sleep -Seconds 2

        $content = ''
        if (Test-Path -LiteralPath $tempOut) {
            $content = (Get-Content -LiteralPath $tempOut -Raw -ErrorAction SilentlyContinue).Trim()
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }

        if (Test-OutputLooksLikeWinGetVersion -Text $content) {
            Write-Log -Message ('winget functional via desktop package context :: {0}' -f $content)
            return $true
        }

        Write-Log -Message ('Desktop package invocation completed but did not return a valid version string. Output=''{0}''' -f $content) -Level 'WARNING'
        return $false
    } catch {
        Write-Log -Message ('Desktop package invocation failed: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Install-WinGetBridge {
    param(
        [Parameter(Mandatory=$true)][string]$TargetRoot,
        [Parameter(Mandatory=$true)][string]$PackageFamilyName,
        [Parameter(Mandatory=$true)][string]$CliPath
    )

    try {
        Ensure-Directory -Path $TargetRoot

        $ps1Path = Join-Path $TargetRoot 'Invoke-WinGet.ps1'
        $cmdPath = Join-Path $TargetRoot 'winget.cmd'
        $embeddedPackageFamily = $PackageFamilyName.Replace("'","''")
        $embeddedCliPath = $CliPath.Replace("'","''")

        $bridgePs1 = @"
param(
    [Parameter(ValueFromRemainingArguments=`$true)]
    [string[]]`$Arguments
)

`$ErrorActionPreference = 'Stop'
`$PackageFamilyName = '$embeddedPackageFamily'
`$CliPath = '$embeddedCliPath'

function Join-BridgeArgumentString {
    param([string[]]`$Items = @())

    if (-not `$Items -or @(`$Items).Count -eq 0) { return '' }

    `$parts = New-Object System.Collections.Generic.List[string]
    foreach (`$item in `$Items) {
        if (`$null -eq `$item) { continue }
        `$s = [string]`$item
        if (`$s -match '[\s"]') {
            `$escaped = `$s.Replace('"','""')
            `$parts.Add(('"{0}"' -f `$escaped))
        } else {
            `$parts.Add(`$s)
        }
    }

    return (`$parts -join ' ')
}

if ([string]::IsNullOrWhiteSpace(`$PackageFamilyName)) {
    Write-Error 'Bridge metadata is missing PackageFamilyName.'
    exit 1
}

if ([string]::IsNullOrWhiteSpace(`$CliPath)) {
    Write-Error 'Bridge metadata is missing CliPath.'
    exit 1
}

`$argText = Join-BridgeArgumentString -Items `$Arguments
`$escapedCli = `$CliPath.Replace('"','""')
`$cmdArgs = if ([string]::IsNullOrWhiteSpace(`$argText)) {
    '/d /c ""' + `$escapedCli + '""'
} else {
    '/d /c ""' + `$escapedCli + '" ' + `$argText + '"'
}

Invoke-CommandInDesktopPackage -PackageFamilyName `$PackageFamilyName -AppId 'winget' -Command 'C:\Windows\System32\cmd.exe' -Args `$cmdArgs -PreventBreakaway
exit `$LASTEXITCODE
"@

        $bridgeCmd = '@echo off' + [Environment]::NewLine +
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $ps1Path + '" %*'

        Set-Content -LiteralPath $ps1Path -Value $bridgePs1 -Encoding UTF8 -Force
        Set-Content -LiteralPath $cmdPath -Value $bridgeCmd -Encoding ASCII -Force

        [void](Add-MachinePathEntry -PathEntry $TargetRoot)
        Write-Log -Message ('Installed WinGet bridge wrapper: {0}' -f $cmdPath)
        return $cmdPath
    } catch {
        Write-Log -Message ('Failed to install WinGet bridge: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $null
    }
}

function Test-WinGetAny {
    if (Test-WinGetByAlias) { return $true }
    if (Test-WinGetViaDesktopPackage) { return $true }
    return $false
}

function Ensure-WinGetBridge {
    if ($SkipBridge) {
        Write-Log -Message 'Bridge installation skipped by parameter.'
        return $true
    }

    $pkg = Get-DesktopAppInstallerPackage
    if (-not $pkg) {
        Write-Log -Message 'Cannot install WinGet bridge because DesktopAppInstaller package was not found.' -Level 'WARNING'
        return $false
    }

    $cliPath = Get-PackagedWinGetExecutable
    if (-not $cliPath) {
        Write-Log -Message 'Cannot install WinGet bridge because no packaged WinGet CLI executable was found.' -Level 'WARNING'
        return $false
    }

    $cmdPath = Install-WinGetBridge -TargetRoot $BridgeRoot -PackageFamilyName $pkg.PackageFamilyName -CliPath $cliPath
    if (-not $cmdPath) { return $false }

    return (Test-WinGetFunctional -WingetPath $cmdPath)
}

function Try-RepairWinGetPackageManager {
    Write-Log -Message 'Tier 1: Attempting Microsoft.WinGet.Client workflow...'
    try {
        try { Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null } catch {}

        if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
            Install-Module -Name Microsoft.WinGet.Client -Scope AllUsers -AllowClobber -ErrorAction Stop | Out-Null
        }

        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
        Start-Sleep -Seconds 5

        [void](Register-DesktopAppInstallerByFamilyName)
        Start-Sleep -Seconds 3

        if (Test-WinGetViaDesktopPackage) {
            [void](Ensure-WinGetBridge)
            return $true
        }

        return $false
    } catch {
        Write-Log -Message ('Tier 1 failed: {0}' -f $_.Exception.Message) -Level 'WARNING'
        return $false
    }
}

function Try-OfflineDesktopAppInstaller {
    param([Parameter(Mandatory=$true)][string]$BundlePath)

    Write-Log -Message ('Tier 2: Attempting DesktopAppInstaller install from: {0}' -f $BundlePath)

    $packageBefore = Get-DesktopAppInstallerPackage
    if ($packageBefore) {
        Write-Log -Message ('DesktopAppInstaller already present before Tier 2. Version={0}' -f $packageBefore.Version)
    }

    try {
        Add-AppxPackage -Path $BundlePath -ErrorAction Stop | Out-Null
        Write-Log -Message 'DesktopAppInstaller installed via Add-AppxPackage.'
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match '0x80073D06' -or $msg -match 'vers[aã]o superior' -or $msg -match 'higher version') {
            Write-Log -Message ('DesktopAppInstaller install skipped because a higher version is already installed: {0}' -f $msg) -Level 'WARNING'
        } else {
            Write-Log -Message ('DesktopAppInstaller Add-AppxPackage failed: {0}' -f $msg) -Level 'WARNING'
        }
    }

    Start-Sleep -Seconds 5
    [void](Register-DesktopAppInstallerByFamilyName)
    Start-Sleep -Seconds 3

    if (Test-WinGetViaDesktopPackage) {
        [void](Ensure-WinGetBridge)
        return $true
    }

    return $false
}

try {
    if (-not (Test-IsAdmin)) { throw 'This script must run elevated (Administrator).' }

    Write-Log -Message 'Starting WinGet configuration on Windows Server 2019...'
    Ensure-Directory -Path $SetupRoot
    Ensure-Directory -Path (Join-Path $SetupRoot 'Downloads')

    if (Test-WinGetAny) {
        [void](Ensure-WinGetBridge)
        Write-Log -Message 'WinGet is already functional. No package reinstall required.'
        exit 0
    }

    if (Try-RepairWinGetPackageManager) {
        Write-Log -Message 'WinGet installed or repaired via Tier 1 (Microsoft.WinGet.Client).'
        exit 0
    }

    [void](Set-AppxPolicies)
    $vOk = Ensure-VCLibs
    $uOk = Ensure-UIXaml28
    $rOk = Ensure-WindowsAppRuntime18

    if ($StrictPrereqs) {
        if (-not $vOk) { throw 'Strict prereq failure: VCLibs' }
        if (-not $uOk) { throw 'Strict prereq failure: UI.Xaml' }
        if (-not $rOk) { throw 'Strict prereq failure: WindowsAppRuntime 1.8' }
    }

    if (-not $rOk) {
        Write-Log -Message 'WindowsAppRuntime 1.8 is missing. Tier 2 may fail until the runtime is present.' -Level 'WARNING'
    }

    $downloads = Join-Path $SetupRoot 'Downloads'

    foreach ($tag in $CandidateReleases) {
        try {
            $bundleName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe_{0}.msixbundle' -f $tag.Replace('/','_')
            $bundlePath = Join-Path $downloads $bundleName

            if ($tag -eq 'latest') {
                $url = 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            } else {
                $url = 'https://github.com/microsoft/winget-cli/releases/download/{0}/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -f $tag
            }

            if (-not (Download-File -Url $url -OutFile $bundlePath)) {
                Write-Log -Message ('Skipping release {0}; download failed.' -f $tag) -Level 'WARNING'
                continue
            }

            if (Try-OfflineDesktopAppInstaller -BundlePath $bundlePath) {
                Write-Log -Message ('WinGet functional after Tier 2 offline App Installer from {0}.' -f $tag)
                exit 0
            }
        } catch {
            Write-Log -Message ('Release {0} failed: {1}' -f $tag, $_.Exception.Message) -Level 'WARNING'
        }
    }

    throw ('All candidate releases failed package-aware validation. See log for details: {0}' -f $script:LogPath)
}
catch {
    Write-Log -Message ('Fatal error: {0}' -f $_.Exception.Message) -Level 'ERROR'
    exit 1
}

# End of script
