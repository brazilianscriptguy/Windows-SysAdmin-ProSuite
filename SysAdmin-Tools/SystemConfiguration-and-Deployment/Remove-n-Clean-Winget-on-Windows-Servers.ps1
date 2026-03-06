<#
.SYNOPSIS
    Controlled cleanup of WinGet / DesktopAppInstaller artifacts on Windows Server 2019.

.DESCRIPTION
    Removes WinGet-related machine artifacts created by previous installer attempts, including:
    - Portable WinGet folders
    - WinGet bridge / shim folders and wrappers
    - DesktopAppInstaller AppX registrations
    - DesktopAppInstaller provisioned package remnants
    - Per-user DesktopAppInstaller remnants
    - WinGet PowerShell modules
    - WinGet staging / temp folders
    - PATH pollution related to WinGet bootstrap attempts
    - AppX sideloading policy overrides commonly set during bootstrap

    Designed to be idempotent, verbose in logging, and safer for repeated enterprise use.

.NOTES
    - Must be run as Administrator
    - Reboot is strongly recommended after cleanup before reinstall
    - Logging writes the full log path as the first line in the log file

.AUTHOR
    Luiz Hamilton Silva (@brazilianscriptguy) — merged and revised

.VERSION
    2026-03-06
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$LogDir      = "C:\Logs-TEMP",
    [string]$PortableDir = "C:\Program Files\winget",
    [string]$ShimDir     = "C:\Program Files\WinGetShim",
    [string]$BridgeDir   = "C:\Program Files\WinGet-Bridge",
    [string]$SetupRoot   = "C:\ProgramData\WinGet-Setup"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$WarningPreference     = 'Continue'

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------
function Initialize-Log {
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        throw "Failed to create log directory '$LogDir'. $($_.Exception.Message)"
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
            'winget-cleanup-server2019'
        }
    }
    catch {
        'winget-cleanup-server2019'
    }

    $script:LogFile = Join-Path -Path $LogDir -ChildPath ("{0}_{1}.log" -f $scriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))

    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[INFO] $timestamp Log initialized: $script:LogFile"
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
        Write-Host $line -ForegroundColor Gray
    }
    catch {
        Write-Host "Failed to initialize log file '$script:LogFile'. $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] {1} {2}" -f $Level, $timestamp, $Message

    try {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging must never crash the script
    }

    switch ($Level) {
        'INFO'  { Write-Host $line -ForegroundColor Gray }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
    }
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Write-Stage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title
    )

    Write-Log ("---- {0} ----" -f $Title)
}

function Remove-PathItemSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            Write-Log "Removing path: $Path"
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to remove '$Path' -> $($_.Exception.Message)" 'WARN'
        }
    }
    else {
        Write-Log "Path not present: $Path"
    }
}

function Remove-WildcardItemsSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pattern
    )

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
            Write-Log "Failed to remove '$($item.FullName)' -> $($_.Exception.Message)" 'WARN'
        }
    }
}

function Remove-MachinePathEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Patterns
    )

    Write-Log "Cleaning machine PATH..."

    try {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    }
    catch {
        Write-Log "Failed to read machine PATH -> $($_.Exception.Message)" 'WARN'
        return
    }

    if (-not $machinePath) {
        Write-Log "Machine PATH is empty or unavailable." 'WARN'
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

    try {
        [Environment]::SetEnvironmentVariable('Path', ($cleaned -join ';'), 'Machine')
        Write-Log "Machine PATH cleanup completed."
    }
    catch {
        Write-Log "Failed to update machine PATH -> $($_.Exception.Message)" 'WARN'
    }
}

function Remove-AppxDesktopAppInstallerPackages {
    [CmdletBinding()]
    param()

    Write-Log 'Removing DesktopAppInstaller AppX'

    $packages = @(Get-AppxPackage -AllUsers 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue)

    if ($packages.Count -eq 0) {
        Write-Log 'No Microsoft.DesktopAppInstaller AppX packages found.'
        return
    }

    foreach ($pkg in $packages) {
        try {
            Write-Log "Attempting Remove-AppxPackage -> $($pkg.PackageFullName)"
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "Removed AppX package -> $($pkg.PackageFullName)"
        }
        catch {
            Write-Log "Remove-AppxPackage failed -> $($pkg.PackageFullName) :: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Remove-ProvisionedDesktopAppInstallerPackages {
    [CmdletBinding()]
    param()

    Write-Log 'Removing provisioned DesktopAppInstaller packages...'

    $provisioned = @(
        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*DesktopAppInstaller*' }
    )

    if ($provisioned.Count -eq 0) {
        Write-Log 'No provisioned DesktopAppInstaller packages found.'
        return
    }

    foreach ($item in $provisioned) {
        try {
            Write-Log "Attempting Remove-AppxProvisionedPackage -> $($item.PackageName)"
            Remove-AppxProvisionedPackage -Online -PackageName $item.PackageName -ErrorAction SilentlyContinue | Out-Null
            Write-Log "Removed provisioned package -> $($item.PackageName)"
        }
        catch {
            Write-Log "Remove-AppxProvisionedPackage failed -> $($item.PackageName) :: $($_.Exception.Message)" 'WARN'
        }
    }
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
Initialize-Log
Write-Log "Starting WinGet environment cleanup"

try {
    # ------------------------------------------------------------
    # 1. Remove portable deployments / shims / bridge / backups
    # ------------------------------------------------------------
    Write-Stage "Portable installations cleanup"

    $fixedFolders = @(
        $PortableDir,
        $ShimDir,
        $BridgeDir,
        'C:\winget',
        'C:\Program Files (x86)\winget'
    )

    foreach ($folder in $fixedFolders) {
        Remove-PathItemSafe -Path $folder
    }

    Get-ChildItem 'C:\Program Files' -Filter 'winget.bak*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-PathItemSafe -Path $_.FullName
    }

    Get-ChildItem 'C:\Program Files' -Filter 'WinGetShim*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-PathItemSafe -Path $_.FullName
    }

    Get-ChildItem 'C:\Program Files' -Filter 'WinGet-Bridge*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-PathItemSafe -Path $_.FullName
    }

    # ------------------------------------------------------------
    # 2. Remove wrapper artifacts
    # ------------------------------------------------------------
    Write-Stage "Wrapper cleanup"

    Remove-WildcardItemsSafe -Pattern 'C:\Program Files\*\winget.cmd'

    # ------------------------------------------------------------
    # 3. Remove DesktopAppInstaller AppX and provisioned packages
    # ------------------------------------------------------------
    Write-Stage "DesktopAppInstaller package cleanup"

    Remove-AppxDesktopAppInstallerPackages
    Remove-ProvisionedDesktopAppInstallerPackages

    # ------------------------------------------------------------
    # 4. Remove per-user package remnants (current user scope)
    # ------------------------------------------------------------
    Write-Stage "Current-user remnants cleanup"

    $localPackagePatterns = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_*",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget*"
    )

    foreach ($pattern in $localPackagePatterns) {
        Remove-WildcardItemsSafe -Pattern $pattern
    }

    # ------------------------------------------------------------
    # 5. Remove WinGet PowerShell modules
    # ------------------------------------------------------------
    Write-Stage "PowerShell module cleanup"

    $modulePatterns = @(
        'C:\Program Files\WindowsPowerShell\Modules\Microsoft.WinGet.Client*',
        'C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Client*',
        "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\Microsoft.WinGet.Client*",
        "$env:ProgramFiles\WindowsPowerShell\Modules\Microsoft.WinGet.Source*",
        'C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Source*',
        "$env:USERPROFILE\Documents\PowerShell\Modules\Microsoft.WinGet.Client*",
        "$env:USERPROFILE\Documents\PowerShell\Modules\Microsoft.WinGet.Source*"
    )

    foreach ($pattern in $modulePatterns) {
        Remove-WildcardItemsSafe -Pattern $pattern
    }

    # ------------------------------------------------------------
    # 6. Remove staging / temp / dependency roots
    # ------------------------------------------------------------
    Write-Stage "Staging and temp cleanup"

    $stagingPatterns = @(
        $SetupRoot,
        'C:\WinGet',
        "$env:TEMP\WinGet*",
        "$env:TEMP\DesktopAppInstaller*"
    )

    foreach ($pattern in $stagingPatterns) {
        if ($pattern -like '*`**' -or $pattern.Contains('*')) {
            Remove-WildcardItemsSafe -Pattern $pattern
        }
        else {
            Remove-PathItemSafe -Path $pattern
        }
    }

    # ------------------------------------------------------------
    # 7. Clean PATH pollution
    # ------------------------------------------------------------
    Write-Stage "PATH cleanup"

    Remove-MachinePathEntries -Patterns @(
        '\winget',
        'WinGetShim',
        'WinGet-Bridge',
        'DesktopAppInstaller'
    )

    # ------------------------------------------------------------
    # 8. Remove AppX policy keys commonly set during bootstrap
    # ------------------------------------------------------------
    Write-Stage "AppX policy cleanup"

    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
    if (Test-Path -LiteralPath $policyPath) {
        foreach ($name in @('AllowAllTrustedApps', 'AllowDevelopmentWithoutDevLicense')) {
            try {
                $prop = Get-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue
                if ($null -ne $prop) {
                    Remove-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue
                    Write-Log "Removed policy value -> $name"
                }
                else {
                    Write-Log "Policy value not present -> $name"
                }
            }
            catch {
                Write-Log "Failed to remove policy value '$name' -> $($_.Exception.Message)" 'WARN'
            }
        }
    }
    else {
        Write-Log "Policy path not present: $policyPath"
    }

    Write-Log 'Cleanup finished.'
}
catch {
    Write-Log "Fatal error: $($_.Exception.Message)" 'ERROR'
}
finally {
    Write-Host ''
    Write-Host 'WinGet / DesktopAppInstaller environment cleanup completed.' -ForegroundColor Cyan
    Write-Host ('Log saved to: {0}' -f $script:LogFile) -ForegroundColor Green
    Write-Host ''
    Write-Host 'Reboot the server before attempting a reinstall.' -ForegroundColor Yellow
    Write-Host 'Some package registrations and file handles may remain until restart.' -ForegroundColor DarkYellow
    Write-Host ''

    Write-Log 'Script finished'
}

# End of script
