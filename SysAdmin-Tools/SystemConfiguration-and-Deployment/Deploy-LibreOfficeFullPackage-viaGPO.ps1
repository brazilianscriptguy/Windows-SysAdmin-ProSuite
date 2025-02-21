<#
.SYNOPSIS
    PowerShell Script for Deploying LibreOffice Suite and Help Pack.

.DESCRIPTION
    This script automates the deployment of LibreOffice Suite and Help Pack.
    It validates the presence of the MSI files, checks the installed LibreOffice version,
    uninstalls outdated versions, and installs the latest specified version for all users.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 21, 2025
#>

param (
    [string]$LibreSuiteMSIPath = "\\headq.scriptguy\NETLOGON\libreoffice-fullpackage-install\libreoffice-25.2-suite.msi",  # Path to the Suite MSI on the network
    [string]$LibreHelpMSIPath = "\\headq.scriptguy\NETLOGON\libreoffice-fullpackage-install\libreoffice-25.2-helppack.msi",  # Path to the Help Pack MSI on the network
    [string]$LibreVersion = "25.2"  # Target version of LibreOffice to be installed
)

$ErrorActionPreference = "Stop"

# Log configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Scripts-LOGS'
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

# Function to search for installed LibreOffice programs
function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ |
        Where-Object { $_.DisplayName -and $_.DisplayName -match "LibreOffice" } |
        Select-Object DisplayName, DisplayVersion,
                      @{Name="UninstallString"; Expression={ $_.UninstallString }},
                      @{Name="Architecture"; Expression={ if ($_.PSPath -match 'WOW6432Node') {'32-bit'} else {'64-bit'} }}
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

    # Check for the existence of the MSI files
    if (-not (Test-Path $LibreSuiteMSIPath)) {
        Log-Message "ERROR: Suite MSI file not found at $LibreSuiteMSIPath. Please verify the path and try again."
        throw "Suite MSI file not found."
    }
    if (-not (Test-Path $LibreHelpMSIPath)) {
        Log-Message "ERROR: Help Pack MSI file not found at $LibreHelpMSIPath. Please verify the path and try again."
        throw "Help Pack MSI file not found."
    }

    # Log the target LibreOffice version
    Log-Message "Target LibreOffice version to be installed: $LibreVersion"

    # Check installed programs
    $installedPrograms = Get-InstalledPrograms
    if ($installedPrograms.Count -eq 0) {
        Log-Message "No version of LibreOffice was found. Proceeding with installation."
    } else {
        foreach ($program in $installedPrograms) {
            Log-Message "Found: $($program.DisplayName) - Version: $($program.DisplayVersion) - Architecture: $($program.Architecture)"
            if (Compare-Version -installed $program.DisplayVersion -target $LibreVersion) {
                Log-Message "Installed version ($($program.DisplayVersion)) is older than the target version ($LibreVersion). Update required."
                Uninstall-Application -UninstallString $program.UninstallString
            } else {
                Log-Message "The installed version ($($program.DisplayVersion)) is up-to-date. No action required."
                return
            }
        }
    }

    # Proceed with machine-wide installation of the LibreOffice Suite
    Log-Message "No updated version found. Starting machine-wide installation of LibreOffice Suite."
    $installArgsSuite = "/qn /i `"$LibreSuiteMSIPath`" ALLUSERS=1 REBOOT=ReallySuppress /log `"$logPath`""
    Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgsSuite -Wait -ErrorAction Stop
    Log-Message "LibreOffice Suite installed successfully (Machine-wide)."

    # Proceed with machine-wide installation of the LibreOffice Help Pack
    Log-Message "Starting machine-wide installation of LibreOffice Help Pack."
    $installArgsHelp = "/qn /i `"$LibreHelpMSIPath`" ALLUSERS=1 REBOOT=ReallySuppress /log `"$logPath`""
    Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgsHelp -Wait -ErrorAction Stop
    Log-Message "LibreOffice Help Pack installed successfully (Machine-wide)."

} catch {
    Log-Message "An error occurred: $_"
}

# End of script
