#Requires -RunAsAdministrator
<#!
.SYNOPSIS
    Idempotent, machine-GPO-safe WinGet bootstrap for Windows Server 2019 Standard.

.DESCRIPTION
    Installs or repairs Microsoft.DesktopAppInstaller (WinGet) on Windows Server 2019 using a
    package-aware, non-interactive workflow suitable for Computer Startup GPO execution.

    Design goals:
    - Idempotent across clean and previously-modified machines
    - Safe for Session 0 / LocalSystem / machine startup GPO usage
    - Removes remnants from older custom WinGet bridge/portable deployments before install
    - Avoids interactive wrappers by default
    - Validates WinGet inside desktop package context

    Default behavior intentionally does NOT expose a global 'winget' command in plain CMD/PATH.
    It validates WinGet in package context only, which is the reliable model for Server 2019 GPO use.

.NOTES
    Recommended usage: Computer Startup GPO under LocalSystem.
    Re-run is safe.

.AUTHOR
    Luiz Hamilton Silva (@brazilianscriptguy) — v11 consolidated

.VERSION
    2026-03-06
#>

[CmdletBinding()]
param(
    [string]$LogDir = 'C:\Logs-TEMP',
    [string]$SetupRoot = 'C:\ProgramData\WinGet-Setup',
    [switch]$InstallBridge,
    [switch]$SkipTier1,
    [switch]$KeepBootstrapPolicies
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
function Initialize-Log {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    $scriptName = try {
        if ($PSCommandPath) {
            [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
        }
        elseif ($MyInvocation.MyCommand.Path) {
            [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Path)
        }
        elseif ($MyInvocation.MyCommand.Name) {
            [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
        }
        else {
            'new-winget-install-servers'
        }
    }
    catch {
        'new-winget-install-servers'
    }

    $script:LogFile = Join-Path -Path $LogDir -ChildPath ("{0}.log" -f $scriptName)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[INFO] [$ts] Log initialized: $script:LogFile"
    Set-Content -Path $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor Gray
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$Level] [$ts] $Message"
    try {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
    catch {}

    switch ($Level) {
        'INFO'    { Write-Host $line -ForegroundColor Gray }
        'WARNING' { Write-Host $line -ForegroundColor Yellow }
        'ERROR'   { Write-Host $line -ForegroundColor Red }
    }
}

function Write-Stage {
    param([Parameter(Mandatory)][string]$Name)
    Write-Log "---- $Name ----"
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-IsSystem {
    try {
        return ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq 'NT AUTHORITY\SYSTEM')
    }
    catch {
        return $false
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Remove-PathItemSafe {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        try {
            Write-Log "Removing path: $Path"
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to remove '$Path' -> $($_.Exception.Message)" 'WARNING'
        }
    }
    else {
        Write-Log "Path not present: $Path"
    }
}

function Remove-WildcardItemsSafe {
    param([Parameter(Mandatory)][string]$Pattern)

    $items = @(Get-Item -Path $Pattern -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) {
        Write-Log "No matches for pattern: $Pattern"
        return
    }

    foreach ($item in $items) {
        try {
            Write-Log "Removing wildcard match: $($item.FullName)"
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to remove '$($item.FullName)' -> $($_.Exception.Message)" 'WARNING'
        }
    }
}

function Remove-MachinePathEntries {
    param([Parameter(Mandatory)][string[]]$Patterns)

    Write-Log 'Cleaning machine PATH...'
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not $machinePath) {
        Write-Log 'Machine PATH is empty or unavailable.' 'WARNING'
        return
    }

    $entries = @(
        $machinePath -split ';' |
        Where-Object { $_ -and $_.Trim() } |
        ForEach-Object { $_.Trim() }
    )

    $cleaned = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $entries) {
        $remove = $false
        foreach ($pattern in $Patterns) {
            if ($entry -like "*$pattern*") {
                Write-Log "Removing PATH entry -> $entry"
                $remove = $true
                break
            }
        }
        if (-not $remove) {
            if (-not $cleaned.Contains($entry)) {
                [void]$cleaned.Add($entry)
            }
        }
    }

    [Environment]::SetEnvironmentVariable('Path', ($cleaned -join ';'), 'Machine')
    Write-Log 'Machine PATH cleanup completed.'
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )

    Write-Log "Downloading: $Url -> $Destination"
    Ensure-Directory -Path ([IO.Path]::GetDirectoryName($Destination))

    $wc = New-Object System.Net.WebClient
    try {
        $wc.Headers['User-Agent'] = 'WindowsPowerShell/5.1 WinGetBootstrap/v11'
        $wc.DownloadFile($Url, $Destination)
    }
    finally {
        $wc.Dispose()
    }

    $size = (Get-Item -LiteralPath $Destination -ErrorAction Stop).Length
    Write-Log "Download OK. Size: $size bytes."
}

function Ensure-AppxPolicies {
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
    if (-not (Test-Path -LiteralPath $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    New-ItemProperty -Path $policyPath -Name 'AllowAllTrustedApps' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $policyPath -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Log 'Ensured AppX policy: AllowAllTrustedApps=1, AllowDevelopmentWithoutDevLicense=1'
}

function Remove-AppxPoliciesIfRequested {
    if ($KeepBootstrapPolicies) {
        Write-Log 'KeepBootstrapPolicies requested; leaving AppX policy values in place.'
        return
    }

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
    if (-not (Test-Path -LiteralPath $policyPath)) {
        Write-Log "Policy path not present: $policyPath"
        return
    }

    foreach ($name in @('AllowAllTrustedApps','AllowDevelopmentWithoutDevLicense')) {
        try {
            $prop = Get-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue
            if ($null -ne $prop) {
                Remove-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue
                Write-Log "Removed bootstrap policy value -> $name"
            }
            else {
                Write-Log "Bootstrap policy value not present -> $name"
            }
        }
        catch {
            Write-Log "Failed removing bootstrap policy value '$name' -> $($_.Exception.Message)" 'WARNING'
        }
    }
}

function Get-DesktopAppInstallerPackage {
    $pkgs = @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending)
    if ($pkgs.Count -gt 0) { return $pkgs[0] }
    return $null
}

function Resolve-PackagedCliPath {
    param([Parameter(Mandatory)]$Package)

    $candidates = @(
        (Join-Path $Package.InstallLocation 'winget.exe'),
        (Join-Path $Package.InstallLocation 'AppInstallerCLI.exe'),
        (Join-Path $Package.InstallLocation 'AppInstallerCli.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Test-WinGetInDesktopPackageContext {
    param(
        [Parameter(Mandatory)][string]$PackageFamilyName,
        [Parameter(Mandatory)][string]$CliPath
    )

    $quotedCli = $CliPath.Replace("'", "''")
    $cmd = "& '$quotedCli' --version"

    try {
        $output = Invoke-CommandInDesktopPackage -AppxPackageFamilyName $PackageFamilyName -Command $cmd 2>&1 | Out-String
        $text = ($output | Out-String).Trim()
        if ($text -match 'v?\d+\.\d+\.\d+') {
            Write-Log "winget functional via desktop package context :: $($Matches[0])"
            return $true
        }

        Write-Log "Desktop package invocation completed but did not return a version string. Output='$text'" 'WARNING'
        return $false
    }
    catch {
        Write-Log "Desktop package invocation failed -> $($_.Exception.Message)" 'WARNING'
        return $false
    }
}

function Ensure-DependencyPackage {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string[]]$NamesToCheck
    )

    foreach ($n in $NamesToCheck) {
        $pkg = @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1)
        if ($pkg.Count -gt 0) {
            Write-Log "$DisplayName detected. Version: $($pkg[0].Version)"
            return $true
        }
    }

    Write-Log "$DisplayName not detected." 'WARNING'
    return $false
}

function Remove-LegacyArtifacts {
    Write-Stage 'Legacy artifact cleanup'

    foreach ($folder in @(
        'C:\Program Files\winget',
        'C:\Program Files\WinGetShim',
        'C:\Program Files\WinGet-Bridge',
        'C:\winget',
        'C:\Program Files (x86)\winget'
    )) {
        Remove-PathItemSafe -Path $folder
    }

    Remove-WildcardItemsSafe -Pattern 'C:\Program Files\*\winget.cmd'

    foreach ($pattern in @(
        "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_*",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget*",
        'C:\Program Files\WindowsPowerShell\Modules\Microsoft.WinGet.Client*',
        'C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Client*',
        "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\Microsoft.WinGet.Client*",
        "$env:USERPROFILE\Documents\PowerShell\Modules\Microsoft.WinGet.Client*",
        'C:\Program Files\WindowsPowerShell\Modules\Microsoft.WinGet.Source*',
        'C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Source*',
        "$env:USERPROFILE\Documents\PowerShell\Modules\Microsoft.WinGet.Source*"
    )) {
        Remove-WildcardItemsSafe -Pattern $pattern
    }

    foreach ($path in @(
        $SetupRoot,
        'C:\WinGet'
    )) {
        Remove-PathItemSafe -Path $path
    }

    foreach ($pattern in @(
        "$env:TEMP\WinGet*",
        "$env:TEMP\DesktopAppInstaller*"
    )) {
        Remove-WildcardItemsSafe -Pattern $pattern
    }

    Remove-MachinePathEntries -Patterns @('\winget','WinGetShim','WinGet-Bridge','DesktopAppInstaller')
}

function Try-Tier1ModuleWorkflow {
    Write-Log 'Tier 1: Attempting Microsoft.WinGet.Client workflow...'

    try {
        $module = Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if (-not $module) {
            Write-Log 'Microsoft.WinGet.Client module not present. Skipping Tier 1 module workflow.' 'WARNING'
            return $false
        }

        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Write-Log "Microsoft.WinGet.Client module loaded. Version=$($module.Version)"

        $pkg = Get-DesktopAppInstallerPackage
        if ($pkg) {
            $cli = Resolve-PackagedCliPath -Package $pkg
            if ($cli) {
                return (Test-WinGetInDesktopPackageContext -PackageFamilyName $pkg.PackageFamilyName -CliPath $cli)
            }
        }

        return $false
    }
    catch {
        Write-Log "Tier 1 failed: $($_.Exception.Message)" 'WARNING'
        return $false
    }
}

function Install-DesktopAppInstallerBundle {
    param([Parameter(Mandatory)][string]$BundlePath)

    Write-Log "Tier 2: Attempting DesktopAppInstaller install from: $BundlePath"

    $before = Get-DesktopAppInstallerPackage
    if ($before) {
        Write-Log "DesktopAppInstaller already present before Tier 2. Version=$($before.Version)"
    }
    else {
        Write-Log 'DesktopAppInstaller package not currently detected.' 'WARNING'
    }

    try {
        Add-AppxPackage -Path $BundlePath -ErrorAction Stop
        Write-Log 'DesktopAppInstaller installed via Add-AppxPackage.'
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match '0x80073D06' -or $msg -match 'versão superior' -or $msg -match 'higher version') {
            Write-Log "DesktopAppInstaller install skipped because a higher version is already installed: $msg" 'WARNING'
        }
        else {
            throw
        }
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
        Write-Log 'DesktopAppInstaller re-registered by family name.'
    }
    catch {
        Write-Log "DesktopAppInstaller family-name registration failed: $($_.Exception.Message)" 'WARNING'
    }

    Start-Sleep -Seconds 3

    $pkg = Get-DesktopAppInstallerPackage
    if (-not $pkg) {
        Write-Log 'DesktopAppInstaller still not detected after Tier 2.' 'WARNING'
        return $false
    }

    Write-Log "DesktopAppInstaller detected. Version=$($pkg.Version) InstallLocation=$($pkg.InstallLocation)"
    $cli = Resolve-PackagedCliPath -Package $pkg
    if (-not $cli) {
        Write-Log 'Could not resolve packaged WinGet CLI path after Tier 2.' 'WARNING'
        return $false
    }

    Write-Log "Resolved packaged WinGet CLI path: $cli"
    return (Test-WinGetInDesktopPackageContext -PackageFamilyName $pkg.PackageFamilyName -CliPath $cli)
}

function Install-OptionalBridge {
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$CliPath
    )

    Write-Stage 'Optional bridge installation'

    $bridgeDir = 'C:\Program Files\WinGet-Bridge'
    Ensure-Directory -Path $bridgeDir

    $wrapperPs1 = Join-Path $bridgeDir 'Invoke-WinGet.ps1'
    $wrapperCmd = Join-Path $bridgeDir 'winget.cmd'
    $pf = $Package.PackageFamilyName.Replace("'","''")
    $cp = $CliPath.Replace("'","''")

    $psContent = @"
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$ArgsFromCaller)
`$cmd = "& '$cp' " + ((`$ArgsFromCaller | ForEach-Object { if (`$_ -match '[\s"]') { '"' + (`$_ -replace '"','\"') + '"' } else { `$_ } }) -join ' ')
`$raw = Invoke-CommandInDesktopPackage -AppxPackageFamilyName '$pf' -Command `$cmd 2>&1 | Out-String
if (`$raw) { Write-Output `$raw.TrimEnd() }
exit 0
"@

    $cmdContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wrapperPs1`" %*`r`n"

    Set-Content -Path $wrapperPs1 -Value $psContent -Encoding UTF8
    Set-Content -Path $wrapperCmd -Value $cmdContent -Encoding ASCII

    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    if ($machinePath -notlike "*$bridgeDir*") {
        [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $bridgeDir), 'Machine')
        Write-Log "Added to PATH (Machine): $bridgeDir"
    }
    else {
        Write-Log "Already in PATH (Machine): $bridgeDir"
    }

    Write-Log "Installed WinGet bridge wrapper: $wrapperCmd"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
Initialize-Log
Write-Log 'Starting WinGet configuration on Windows Server 2019...'
Write-Log ("Execution context: User={0}; IsSystem={1}; PowerShell={2}" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name, (Test-IsSystem), $PSVersionTable.PSVersion)

try {
    if (-not (Test-IsAdmin)) {
        throw 'This script must run elevated.'
    }

    Remove-LegacyArtifacts

    $existing = Get-DesktopAppInstallerPackage
    if ($existing) {
        Write-Log "DesktopAppInstaller detected. Version=$($existing.Version) InstallLocation=$($existing.InstallLocation)"
        $existingCli = Resolve-PackagedCliPath -Package $existing
        if ($existingCli) {
            Write-Log "Resolved packaged WinGet CLI path: $existingCli"
            if (Test-WinGetInDesktopPackageContext -PackageFamilyName $existing.PackageFamilyName -CliPath $existingCli) {
                if ($InstallBridge) {
                    Install-OptionalBridge -Package $existing -CliPath $existingCli
                }
                else {
                    Write-Log 'Bridge installation not requested; skipping optional interactive wrapper.'
                }
                Write-Log 'WinGet is already functional. No package reinstall required.'
                exit 0
            }
        }
        else {
            Write-Log 'DesktopAppInstaller exists, but packaged CLI path could not be resolved. Continuing with repair.' 'WARNING'
        }
    }
    else {
        Write-Log 'DesktopAppInstaller package not currently detected.' 'WARNING'
    }

    if (-not $SkipTier1) {
        [void](Try-Tier1ModuleWorkflow)
        # even if false, proceed with Tier 2 because Tier 1 is opportunistic only
    }
    else {
        Write-Log 'SkipTier1 requested; skipping Microsoft.WinGet.Client workflow.'
    }

    Ensure-AppxPolicies

    [void](Ensure-DependencyPackage -DisplayName 'VCLibs' -NamesToCheck @('Microsoft.VCLibs.140.00.UWPDesktop','Microsoft.VCLibs.140.00'))
    [void](Ensure-DependencyPackage -DisplayName 'UI.Xaml' -NamesToCheck @('Microsoft.UI.Xaml.2.8','Microsoft.UI.Xaml.2.7','Microsoft.UI.Xaml.2.6'))
    [void](Ensure-DependencyPackage -DisplayName 'WindowsAppRuntime 1.8' -NamesToCheck @('Microsoft.WindowsAppRuntime.1.8'))

    $downloadDir = Join-Path $SetupRoot 'Downloads'
    Ensure-Directory -Path $downloadDir

    $candidates = @(
        [pscustomobject]@{
            Name = 'v1.11.180-preview'
            Url  = 'https://github.com/microsoft/winget-cli/releases/download/v1.11.180-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            File = (Join-Path $downloadDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe_v1.11.180-preview.msixbundle')
        },
        [pscustomobject]@{
            Name = 'v1.11.230-preview'
            Url  = 'https://github.com/microsoft/winget-cli/releases/download/v1.11.230-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            File = (Join-Path $downloadDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe_v1.11.230-preview.msixbundle')
        },
        [pscustomobject]@{
            Name = 'latest'
            Url  = 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
            File = (Join-Path $downloadDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe_latest.msixbundle')
        }
    )

    $success = $false
    foreach ($candidate in $candidates) {
        try {
            if (Test-Path -LiteralPath $candidate.File) {
                Write-Log "Found existing download: $($candidate.File) ($( (Get-Item -LiteralPath $candidate.File).Length ) bytes)"
            }
            else {
                Invoke-DownloadFile -Url $candidate.Url -Destination $candidate.File
            }

            if (Install-DesktopAppInstallerBundle -BundlePath $candidate.File) {
                $pkg = Get-DesktopAppInstallerPackage
                $cli = if ($pkg) { Resolve-PackagedCliPath -Package $pkg } else { $null }
                if ($InstallBridge -and $pkg -and $cli) {
                    Install-OptionalBridge -Package $pkg -CliPath $cli
                }
                else {
                    Write-Log 'Bridge installation not requested; skipping optional interactive wrapper.'
                }

                Write-Log "WinGet functional after Tier 2 offline App Installer from $($candidate.Name)."
                $success = $true
                break
            }
            else {
                Write-Log "Release $($candidate.Name) failed package-aware validation." 'WARNING'
            }
        }
        catch {
            Write-Log "Release $($candidate.Name) failed: $($_.Exception.Message)" 'WARNING'
        }
    }

    if (-not $success) {
        throw "All candidate releases failed package-aware validation. See log for details: $script:LogFile"
    }
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
    exit 1
}
finally {
    Remove-AppxPoliciesIfRequested
    Write-Log 'Script finished.'
}

# End of script
