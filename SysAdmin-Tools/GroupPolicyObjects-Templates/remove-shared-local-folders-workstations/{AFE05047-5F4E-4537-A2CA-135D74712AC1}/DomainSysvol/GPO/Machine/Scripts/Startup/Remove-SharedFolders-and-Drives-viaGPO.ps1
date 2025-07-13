<#
.SYNOPSIS
    PowerShell script to remove automatic administrative drive shares (C$, D$, etc.).

.DESCRIPTION
    Removes Windows default administrative drive shares while preserving critical system and service shares 
    such as Active Directory, DFS, WSUS, Certificate Services, File Server, Print Server, and others.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: June 17, 2025
#>

#Requires -RunAsAdministrator

# --- Log configuration ---
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "$env:SystemDrive\Logs-TEMP"
$logPath = Join-Path $logDir "$scriptName.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")] [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$env:COMPUTERNAME] [$Level] $Message"
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
}

Write-Log "========== Script execution started =========="

# --- Protected shares to always preserve ---
$fixedShares = @(
    'ADMIN$', 'IPC$', 'NETLOGON', 'SYSVOL',
    'print$', 'CertEnroll',
    'WsusContent', 'WSUSTemp', 'UpdateServicesPackages',
    'DFSRoots', 'REMINST'
)

# --- Service share prefixes to preserve ---
$allowedPrefixes = @(
    'IMP-', 'PRINT-', 'STORAGE', 'DFS', 'FS', 'SRV', 'FILE', 'DATA'
)

# --- Retrieve current shares ---
try {
    $currentShares = Get-SmbShare -ErrorAction Stop
} catch {
    Write-Log "Failed to retrieve current shares: $_" -Level "ERROR"
    exit 1
}

$sharesToRemove = @()

foreach ($share in $currentShares) {
    $name = $share.Name
    $path = $share.Path

    if ($fixedShares -contains $name) {
        Write-Log "Preserving essential share: $name"
        continue
    }

    if ($allowedPrefixes | Where-Object { $name.ToUpper().StartsWith($_) }) {
        Write-Log "Preserving based on known service prefix: $name"
        continue
    }

    if ($name -notmatch '^[A-Z]\$$') {
        Write-Log "Preserving custom share: $name"
        continue
    }

    # If it matches an admin drive letter share (e.g., C$, D$), mark for removal
    $sharesToRemove += $name
}

# --- Remove unwanted administrative shares ---
if ($sharesToRemove.Count -eq 0) {
    Write-Log "No administrative drive letter shares identified for removal."
} else {
    foreach ($name in $sharesToRemove) {
        try {
            net share $name /delete /y | Out-Null
            Write-Log "Share $name removed successfully."
        } catch {
            Write-Log "Failed to remove ${name}: $_" -Level "ERROR"
        }
    }
}

# --- Ensure critical system shares are present ---
function Ensure-Share {
    param (
        [string]$Name,
        [string]$Path,
        [string]$Description
    )

    if (-not (Get-SmbShare -Name $Name -ErrorAction SilentlyContinue)) {
        try {
            New-SmbShare -Name $Name -Path $Path -Description $Description -FullAccess "Administrators" -ErrorAction Stop
            Write-Log "Share $Name recreated successfully."
        } catch {
            Write-Log "Failed to recreate ${name}: $_" -Level "ERROR"
        }
    }
}

Ensure-Share -Name "ADMIN$" -Path "$env:SystemRoot" -Description "Remote administration"
Ensure-Share -Name "IPC$"   -Path "$env:SystemRoot" -Description "Remote IPC channel"

Write-Log "========== Script execution completed =========="

# --- End of script ---
