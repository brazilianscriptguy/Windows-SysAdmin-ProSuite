<#
.SYNOPSIS
    PowerShell Script for Deploying Zoom Workplace via GPO.

.DESCRIPTION
    This script automates the deployment of Zoom software through Group Policy (GPO). 
    It validates the presence of the MSI file, checks the installed Zoom version,
    uninstalls outdated versions, and installs the latest specified version for all users.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 21, 2025
#>

param (
    [string]$ZoomMSIPath = "\\headq.scriptguy\netlogon\zoom-workplace-install\zoom-workplace-install.msi",  # Path to the MSI on the network
    [string]$MsiVersion = "6.3.59437"  # The new MSI version to be installed
)

$ErrorActionPreference = "Stop"

# Log configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Function to log messages
function Log-Message {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log at $logPath. Error: $_"
    }
}

# Check if the script is running with administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    Log-Message "This script must be run with administrator privileges for machine-wide installation."
    throw "Insufficient privileges. Run the script as Administrator."
}

# Function to search for installed programs
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

    # Function to compare versions (returns True if the installed version is older than the target version)
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

    # Function to uninstall an application
    function Uninstall-Application {
        param ([string]$UninstallString)
        try {
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/qn /x `"$UninstallString`" REBOOT=ReallySuppress" -Wait -ErrorAction Stop
            Log-Message "Application successfully uninstalled using: $UninstallString"
        } catch {
            Log-Message "Error uninstalling the application: $_"
            throw
        }
    }

    try {
        # Ensure the log directory exists
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Log-Message "Log directory $logDir created."
        }

        # Check for the existence of the MSI file
        if (-not (Test-Path $ZoomMSIPath)) {
            Log-Message "ERROR: MSI file not found at $ZoomMSIPath. Please verify the path and try again."
            throw "MSI file not found."
        }

        # Log the MSI version to be installed
        Log-Message "MSI version to be installed: $MsiVersion"

        # Check installed programs
        $installedPrograms = Get-InstalledPrograms
        if ($installedPrograms.Count -eq 0) {
            Log-Message "No version of Zoom was found. Proceeding with installation."
        } else {
            foreach ($program in $installedPrograms) {
                Log-Message "Found: $($program.DisplayName) - Version: $($program.DisplayVersion) - Architecture: $($program.Architecture)"
                if (Compare-Version -installed $program.DisplayVersion -target $MsiVersion) {
                    Log-Message "Installed version ($($program.DisplayVersion)) is older than the MSI version ($MsiVersion). Update required."
                    Uninstall-Application -UninstallString $program.UninstallString
                } else {
                    Log-Message "The installed version ($($program.DisplayVersion)) is already up-to-date. No action required."
                    return
                }
            }
        }

        # Proceed with machine-wide installation (ALLUSERS=1)
        Log-Message "No updated version found. Starting machine-wide installation."
        $installArgs = "/qn /i `"$ZoomMSIPath`" ALLUSERS=1 REBOOT=ReallySuppress /log `"$logPath`""
        Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -ErrorAction Stop
        Log-Message "Zoom Workplace successfully installed (Machine-wide)."

    } catch {
        Log-Message "An error occurred: $_"
    }

    # End of script
