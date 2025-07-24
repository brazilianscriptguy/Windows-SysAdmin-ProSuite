<#
.SYNOPSIS
    PowerShell Script for Deploying Zoom Workplace via GPO.

.DESCRIPTION
    This script automates the deployment of Zoom software through Group Policy (GPO). 
    It validates the presence of the MSI file, checks the installed Zoom version,
    uninstalls outdated versions, and installs the latest specified version.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 12, 2024
#>

param (
    [string]$ZoomMSIPath = "\\forest-domain\netlogon\zoom-workplace-install\zoom-workplace-install.msi",
    [string]$MsiVersion = "6.2.49583" # Target version of Zoom Workplace to install.
)

$ErrorActionPreference = "Stop"

# Log Configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

function Log-Message {
    param (
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$Severity] [$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to log the message at $logPath. Error: $_"
    }
}

function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ |
            Where-Object { $_.DisplayName -and $_.DisplayName -match "Zoom" } |
            Select-Object DisplayName, DisplayVersion,
            @{Name = "UninstallString"; Expression = { $_.UninstallString } },
            @{Name = "Architecture"; Expression = { if ($_.PSPath -match 'WOW6432Node') { '32-bit' } else { '64-bit' } } }
        }
        return $installedPrograms
    }

    function Compare-Version {
        param ([string]$installed, [string]$target)
        $installedParts = $installed -split '[.-]' | ForEach-Object { [int]$_ }
        $targetParts = $target -split '[.-]' | ForEach-Object { [int]$_ }
        for ($i = 0; $i -lt $targetParts.Length; $i++) {
            if ($installedParts[$i] -lt $targetParts[$i]) { return $true }
            if ($installedParts[$i] -gt $targetParts[$i]) { return $false }
        }
        return $false
    }

    function Uninstall-Application {
        param ([string]$UninstallString)
        try {
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/qn /x `"$UninstallString`" REBOOT=ReallySuppress" -Wait -ErrorAction Stop
            Log-Message "Application uninstalled successfully using: $UninstallString"
        } catch {
            Log-Message "Error uninstalling the application: $_" -Severity "ERROR"
            throw
        }
    }

    try {
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Log-Message "Log directory $logDir created."
        }

        if (-not (Test-Path $ZoomMSIPath)) {
            Log-Message "ERROR: The MSI file was not found at $ZoomMSIPath. Please verify the path and try again." -Severity "ERROR"
            exit 1
        }

        Log-Message "MSI version to be installed: $MsiVersion"

        $installedPrograms = Get-InstalledPrograms
        if ($installedPrograms.Count -eq 0) {
            Log-Message "No version of Zoom was found. Proceeding with installation."
        } else {
            foreach ($program in $installedPrograms) {
                Log-Message "Found: $($program.DisplayName) - Version: $($program.DisplayVersion) - Architecture: $($program.Architecture)"
                if (Compare-Version -installed $program.DisplayVersion -target $MsiVersion) {
                    Log-Message "Installed version ($($program.DisplayVersion)) is earlier than the MSI version ($MsiVersion). Update required."
                    Uninstall-Application -UninstallString $program.UninstallString
                } else {
                    Log-Message "The installed version ($($program.DisplayVersion)) is up-to-date. No action needed."
                    return
                }
            }
        }

        Log-Message "No updated version found. Starting installation."
        $installArgs = "/qn /i `"$ZoomMSIPath`" REBOOT=ReallySuppress /log `"$logPath`""
        Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -ErrorAction Stop
        Log-Message "Zoom Workplace installed successfully."

    } catch {
        Log-Message "An error occurred: $_" -Severity "ERROR"
        exit 1
    }

    Log-Message "Script completed successfully."
    exit 0

    # End of script

