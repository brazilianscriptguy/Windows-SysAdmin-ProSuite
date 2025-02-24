<#
.SYNOPSIS
    PowerShell Script for Removing Unauthorized Shared Folders and Drives via Group Policy.

.DESCRIPTION
    This script automates the removal of unauthorized shared folders and drives using Group 
    Policy, ensuring compliance with organizational data-sharing policies and mitigating 
    the risk of data breaches or leaks.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Determine the script name and configure the log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Log Function
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogLevel = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$LogLevel] $Message"

    if (-not (Test-Path $logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    }

    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Ensure the LanmanServer service is enabled via registry
function Enable-LanmanServerService {
    Write-Log "Enabling the LanmanServer service via registry."

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer'
    try {
        Set-ItemProperty -Path $regPath -Name 'Start' -Value 2 -ErrorAction Stop  # 2 = Automatic
        Write-Log "LanmanServer service set to start automatically."
    } catch {
        Write-Log "Failed to set the LanmanServer service startup mode: $_" -LogLevel "ERROR"
    }
}

# Ensure the LanmanServer service is running
function Ensure-ServerService {
    Write-Log "Ensuring the LanmanServer service is running."

    $service = Get-Service -Name 'LanmanServer'
    if ($service.Status -ne 'Running') {
        try {
            Start-Service -Name 'LanmanServer' -ErrorAction Stop
            Write-Log "LanmanServer service started successfully."
        } catch {
            Write-Log "Failed to start the LanmanServer service: $_" -LogLevel "ERROR"
        }
    } else {
        Write-Log "LanmanServer service is already running."
    }
}

# Disable automatic creation of administrative shares via registry
function Disable-AutoAdministrativeShares {
    Write-Log "Disabling automatic creation of administrative shares (including C$, D$, etc.) via registry."

    try {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'AutoShareWks' -Value 0 -ErrorAction Stop
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'AutoShareServer' -Value 0 -ErrorAction Stop
        Write-Log "Automatic creation of administrative shares disabled in registry."
    } catch {
        Write-Log "Failed to disable automatic administrative shares in registry: $_" -LogLevel "ERROR"
    }
}

# Remove all shared folders on all drives (excluding IPC$ and ADMIN$)
function Remove-SharedFolders {
    Write-Log "Removing all shared folders on all drives (excluding IPC$ and ADMIN$)."

    try {
        $shares = Get-SmbShare | Where-Object { $_.Name -notin 'IPC$', 'ADMIN$' }
        foreach ($share in $shares) {
            & net share $share.Name /delete /y
            Write-Log "Shared folder $($share.Name) on $($share.Path) removed."
        }
    } catch {
        Write-Log "Failed to remove shared folders: $_" -LogLevel "ERROR"
    }
}

# Remove all administrative shares (e.g., C$, D$, etc.)
function Remove-AdministrativeShares {
    Write-Log "Removing all administrative shares (e.g., C$, D$, etc.)."

    try {
        $adminShares = Get-SmbShare | Where-Object { $_.Name -match '^\w\$' }
        foreach ($share in $adminShares) {
            & net share $share.Name /delete /y
            Write-Log "Administrative share $($share.Name) removed."
        }
    } catch {
        Write-Log "Failed to remove administrative shares: $_" -LogLevel "ERROR"
    }
}

# Main Script Execution
Write-Log "Starting share management script."

# Enable and start the LanmanServer service
Enable-LanmanServerService
Ensure-ServerService

# Disable automatic creation of administrative shares
Disable-AutoAdministrativeShares

# Remove all shared folders on all drives (excluding IPC$ and ADMIN$)
Remove-SharedFolders

# Remove all administrative shares (including C$, D$, etc.)
Remove-AdministrativeShares

Write-Log "Share management script completed."

# End of script
