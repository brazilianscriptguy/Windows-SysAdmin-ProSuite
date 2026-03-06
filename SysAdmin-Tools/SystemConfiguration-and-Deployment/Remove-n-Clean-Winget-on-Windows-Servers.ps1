<#
.SYNOPSIS
    Aggressive but controlled cleanup of WinGet / DesktopAppInstaller artifacts on Windows Server 2019.

.DESCRIPTION
    Removes portable WinGet deployments, DesktopAppInstaller package registrations, provisioned package remnants,
    PATH pollution, setup staging folders, PowerShell WinGet modules, and common shim folders.
    Designed to be idempotent and safer for repeated enterprise use.

    Execution syntax: powershell -ExecutionPolicy Bypass -File Remove-n-Clean-Winget-on-Windows-Servers.ps1

.NOTES
    - Must be run as Administrator
    - Reboot is strongly recommended after cleanup before reinstall
    - Avoids direct destructive deletion inside protected WindowsApps package roots unless accessible

.AUTHOR
    Luiz Hamilton Silva (@brazilianscriptguy) — revised and hardened

.VERSION
    2026-03-06
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$LogDir      = "C:\Logs-TEMP",
    [string]$PortableDir = "C:\Program Files\winget",
    [string]$ShimDir     = "C:\Program Files\WinGetShim",
    [string]$SetupRoot   = "C:\ProgramData\WinGet-Setup"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
$WarningPreference     = 'Continue'

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
        else {
            'winget-cleanup'
        }
    } catch {
        'winget-cleanup'
    }

    $script:LogFile = Join-Path $LogDir ("{0}_{1}.log" -f $scriptName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $Level, $timestamp, $Message

    try {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch {}

    switch ($Level) {
        'INFO'  { Write-Host $line -ForegroundColor Gray }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
    }
}

Initialize-Log
Write-Log "Starting controlled WinGet / DesktopAppInstaller cleanup on Windows Server 2019"
Write-Log "Log file: $script:LogFile"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Remove-PathItemSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            Write-Log "Removing path: $Path"
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log "Failed to remove '$Path' -> $($_.Exception.Message)" 'WARN'
        }
    } else {
        Write-Log "Path not present: $Path"
    }
}

function Remove-WildcardItemsSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Pattern
    )

    Get-Item -Path $Pattern -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Write-Log "Removing wildcard match: $($_.FullName)"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Log "Failed to remove '$($_.FullName)' -> $($_.Exception.Message)" 'WARN'
        }
    }
}

function Remove-MachinePathEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Patterns
    )

    Write-Log "Cleaning machine PATH..."

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
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
                $null = $cleaned.Add($entry)
            }
        }
    }

    [Environment]::SetEnvironmentVariable('Path', ($cleaned -join ';'), 'Machine')
    Write-Log "Machine PATH cleanup completed."
}

# ------------------------------------------------------------
# 1. Remove portable deployments / shims / backups
# ------------------------------------------------------------
$fixedFolders = @(
    $PortableDir,
    $ShimDir,
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

# ------------------------------------------------------------
# 2. Remove DesktopAppInstaller AppX and provisioned packages
# ------------------------------------------------------------
Write-Log 'Removing Microsoft.DesktopAppInstaller package registrations...'

Get-AppxPackage -AllUsers 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Log "Attempting Remove-AppxPackage -> $($_.PackageFullName)"
    try {
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
        Write-Log "Removed AppX package -> $($_.PackageFullName)"
    } catch {
        Write-Log "Remove-AppxPackage failed -> $($_.Exception.Message)" 'WARN'
    }
}

Write-Log 'Removing provisioned DesktopAppInstaller packages...'
Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*DesktopAppInstaller*' } |
    ForEach-Object {
        try {
            Write-Log "Removing provisioned package -> $($_.DisplayName)"
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Write-Log "Remove-AppxProvisionedPackage failed -> $($_.Exception.Message)" 'WARN'
        }
    }

# ------------------------------------------------------------
# 3. Remove per-user package remnants (safe scope)
# ------------------------------------------------------------
Write-Log 'Removing current-user DesktopAppInstaller package remnants...'

$localPackagePatterns = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_*",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
)

foreach ($pattern in $localPackagePatterns) {
    Remove-WildcardItemsSafe -Pattern $pattern
}

# ------------------------------------------------------------
# 4. Remove WinGet PowerShell modules
# ------------------------------------------------------------
$modulePatterns = @(
    "C:\Program Files\WindowsPowerShell\Modules\Microsoft.WinGet.Client*",
    "C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Client*",
    "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\Microsoft.WinGet.Client*",
    "$env:ProgramFiles\WindowsPowerShell\Modules\Microsoft.WinGet.Source*"
)

foreach ($pattern in $modulePatterns) {
    Remove-WildcardItemsSafe -Pattern $pattern
}

# ------------------------------------------------------------
# 5. Remove staging / temp / dependency roots
# ------------------------------------------------------------
$stagingPatterns = @(
    $SetupRoot,
    'C:\WinGet',
    "$env:TEMP\WinGet*",
    "$env:TEMP\DesktopAppInstaller*"
)

foreach ($pattern in $stagingPatterns) {
    if ($pattern -like '*`**') {
        Remove-WildcardItemsSafe -Pattern $pattern
    } else {
        Remove-PathItemSafe -Path $pattern
    }
}

# ------------------------------------------------------------
# 6. Clean PATH pollution
# ------------------------------------------------------------
Remove-MachinePathEntries -Patterns @(
    '\winget',
    'WinGetShim',
    'DesktopAppInstaller'
)

# ------------------------------------------------------------
# 7. Optional: remove AppX policy keys commonly set during bootstrap
# ------------------------------------------------------------
Write-Log 'Removing AppX sideloading policy overrides (if present)...'

$policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx'
if (Test-Path $policyPath) {
    foreach ($name in @('AllowAllTrustedApps', 'AllowDevelopmentWithoutDevLicense')) {
        try {
            if ($null -ne (Get-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue)) {
                Remove-ItemProperty -Path $policyPath -Name $name -ErrorAction SilentlyContinue
                Write-Log "Removed policy value -> $name"
            }
        } catch {
            Write-Log "Failed to remove policy value '$name' -> $($_.Exception.Message)" 'WARN'
        }
    }
}

# ------------------------------------------------------------
# 8. Final status
# ------------------------------------------------------------
Write-Log 'Cleanup finished.'
Write-Host ''
Write-Host 'WinGet / DesktopAppInstaller environment cleaned.' -ForegroundColor Cyan
Write-Host ('Log saved to: {0}' -f $script:LogFile) -ForegroundColor Green
Write-Host ''
Write-Host 'Reboot the server before attempting a reinstall.' -ForegroundColor Yellow
Write-Host 'Some package registrations and file handles may remain until restart.' -ForegroundColor DarkYellow
Write-Host ''

Write-Log 'Script finished'

# End of script
