<#
.SYNOPSIS
    PowerShell Script to Remove Administrative Drive Shares via Group Policy.

.DESCRIPTION
    This script removes all shares (except ADMIN$ and IPC$) on Windows workstations, and only removes
    administrative drive shares (e.g., C$, D$) on all Windows servers, while preserving all
    custom shares (e.g., WSUS, File Server) and critical shares (IPC$, ADMIN$, NETLOGON, SYSVOL).

    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 28, 2025
#>

#Requires -RunAsAdministrator

# Log path configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "$env:SystemDrive\Scripts-LOGS"
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Log function
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogLevel = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computerName = $env:COMPUTERNAME
    $logEntry = "[$timestamp] [$computerName] [$LogLevel] $Message"

    if (-not (Test-Path $logDir)) {
        $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
    }

    try {
        Add-Content -Path $logPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-EventLog -LogName "Application" -Source "GPO_Script" -EventId 1000 -EntryType $LogLevel -Message "Failed to write to log at ${logPath}: $Message - Error: $_" -ErrorAction SilentlyContinue
    }
}

# Register script in Event Log
try {
    New-EventLog -LogName "Application" -Source "GPO_Script" -ErrorAction SilentlyContinue
} catch {
    # Ignore if the source already exists
}

# Verify and configure LanmanServer service
function Ensure-LanmanServerService {
    Write-Log "Validating the LanmanServer service."

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer'
    try {
        $startValue = (Get-ItemProperty -Path $regPath -Name 'Start' -ErrorAction Stop).Start
        if ($startValue -ne 2) {
            Set-ItemProperty -Path $regPath -Name 'Start' -Value 2 -ErrorAction Stop
            Write-Log "LanmanServer service set to automatic startup."
        }

        $service = Get-Service -Name 'LanmanServer' -ErrorAction Stop
        if ($service.Status -ne 'Running') {
            Start-Service -Name 'LanmanServer' -ErrorAction Stop
            Write-Log "LanmanServer service started successfully."
        } else {
            Write-Log "LanmanServer service is already running."
        }
    } catch {
        Write-Log "Error configuring or starting the LanmanServer service: $_" -LogLevel "ERROR"
        exit 1
    }
}

# Disable automatic creation of administrative drive shares
function Disable-DriveLetterAdminShares {
    Write-Log "Disabling the automatic creation of administrative drive shares (e.g., C$, D$)."

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

    try {
        if ($osInfo) {
            if ($osInfo.ProductType -eq 1) {
                # Workstation
                Set-ItemProperty -Path $regPath -Name 'AutoShareWks' -Value 0 -ErrorAction Stop
                Write-Log "AutoShareWks set to 0 (Workstation)."
            } else {
                # All Servers
                Set-ItemProperty -Path $regPath -Name 'AutoShareServer' -Value 0 -ErrorAction Stop
                Write-Log "AutoShareServer set to 0 (Server)."
            }
        } else {
            Write-Log "Could not determine the operating system type. No registry changes applied." -LogLevel "WARNING"
        }
    } catch {
        Write-Log "Failed to disable automatic shares in the registry: $_" -LogLevel "ERROR"
    }
}

# Remove unauthorized shares
function Remove-UnauthorizedShares {
    Write-Log "Removing unauthorized shares."

    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue

    try {
        # Define protected shares by system type
        $protectedShares = if ($osInfo -and $osInfo.ProductType -eq 1) {
            @('IPC$', 'ADMIN$', 'UpdateServicesPackages', 'WsusContent', 'WSUSTemp')  # Workstations: only IPC$, ADMIN$ and WSUS shares
        } else {
            @('IPC$', 'ADMIN$', 'NETLOGON', 'SYSVOL', 'UpdateServicesPackages', 'WsusContent', 'WSUSTemp')  # Servers: includes WSUS and File Server shares
        }

        # Remove only administrative drive shares on servers
        $sharesToRemove = if ($osInfo -and $osInfo.ProductType -eq 1) {
            # Workstations: remove everything except the protected shares
            Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -notin $protectedShares }
        } else {
            # Servers: remove only administrative drive shares (e.g., C$, D$)
            Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -match '^[A-Za-z]\$$' -and $_.Name -notin $protectedShares }
        }

        if (-not $sharesToRemove) {
            Write-Log "No unauthorized shares found for removal."
            return
        }

        foreach ($share in $sharesToRemove) {
            & net share $share.Name /delete /y
            Write-Log "Share $($share.Name) removed successfully."
        }
    } catch {
        Write-Log "Error removing unauthorized shares: $_" -LogLevel "ERROR"
    }
}

# Validate results after execution
function Validate-SharesRemoval {
    Write-Log "Validating the removal of unauthorized shares."

    try {
        $remainingShares = Get-SmbShare -ErrorAction Stop
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $protectedShares = if ($osInfo -and $osInfo.ProductType -eq 1) {
            @('IPC$', 'ADMIN$', 'UpdateServicesPackages', 'WsusContent', 'WSUSTemp')
        } else {
            @('IPC$', 'ADMIN$', 'NETLOGON', 'SYSVOL', 'UpdateServicesPackages', 'WsusContent', 'WSUSTemp')
        }

        $unauthorizedShares = if ($osInfo -and $osInfo.ProductType -eq 1) {
            $remainingShares | Where-Object { $_.Name -notin $protectedShares }
        } else {
            $remainingShares | Where-Object { $_.Name -match '^[A-Za-z]\$$' -and $_.Name -notin $protectedShares }
        }

        if ($unauthorizedShares) {
            Write-Log "The following legitimate shares were preserved and not removed: $($unauthorizedShares.Name -join ', ')" -LogLevel "WARNING"
        } else {
            Write-Log "All unauthorized shares were successfully removed."
        }
    } catch {
        Write-Log "Error validating remaining shares: $_" -LogLevel "ERROR"
    }
}

# Main Execution
Write-Log "Starting the script for share management via GPO."

Ensure-LanmanServerService
Disable-DriveLetterAdminShares
Remove-UnauthorizedShares
Validate-SharesRemoval

Write-Log "Script completed successfully."

# End of script
exit 0
