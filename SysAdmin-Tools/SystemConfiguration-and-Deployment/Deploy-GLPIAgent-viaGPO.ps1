<#
.SYNOPSIS
    PowerShell Script for Deploying GLPI Agent via GPO.

.DESCRIPTION
    This script installs and configures the GLPI Agent on workstations using Group Policy (GPO).
    It ensures seamless inventory management and reporting within an enterprise environment.
    The script also retrieves the %USERDOMAIN% environment variable and sends it as a TAG to the GLPI server.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 8, 2024
#>

param (
    [string]$GLPIAgentMSI = "\\sede.tjap\NETLOGON\glpi-agent-cmdb\glpi-agent-install.msi",
    [string]$GLPILogDir = "C:\Scripts-LOGS",
    [string]$ExpectedVersion = "1.11",
    [bool]$ReinstallIfSameVersion = $true
)

$ErrorActionPreference = "Stop"

# Log file configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $GLPILogDir $logFileName

# Retrieve user domain
$userDomain = $env:USERDOMAIN
if (-not $userDomain) {
    Log-Message "WARNING: USERDOMAIN variable not defined. Check environment settings." -Warning
    $userDomain = "UNKNOWN_DOMAIN"
}

# Function for logging messages
function Log-Message {
    param (
        [string]$Message,
        [switch]$Warning
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log file at $logPath. Error: $_"
    }
}

# Ensure the log directory exists
if (-not (Test-Path $GLPILogDir)) {
    New-Item -Path $GLPILogDir -ItemType Directory -ErrorAction Stop | Out-Null
    Log-Message "Log directory $GLPILogDir created."
}

# Function to check the installed GLPI Agent version
function Get-InstalledVersion {
    param (
        [string]$RegistryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GLPI-Agent"
    )
    try {
        $key = Get-ItemProperty -Path $RegistryKey -ErrorAction SilentlyContinue
        if ($key) { return $key.DisplayVersion }
    } catch {
        Log-Message "Error accessing registry: $_"
    }
    return $null
}

# Check installed version
$installedVersion = Get-InstalledVersion
if ($installedVersion -eq $ExpectedVersion -and -not $ReinstallIfSameVersion) {
    Log-Message "GLPI Agent version $ExpectedVersion is already installed, and reinstallation is not allowed. No action required."
    exit 0
} elseif ($installedVersion -eq $ExpectedVersion -and $ReinstallIfSameVersion) {
    Log-Message "GLPI Agent version $ExpectedVersion is already installed, but reinstallation is allowed. Proceeding with reinstallation."
} else {
    Log-Message "Installing the new GLPI Agent version: $ExpectedVersion."
}

# Function to install the GLPI Agent with TAG based on the user domain
function Install-GLPIAgent {
    param (
        [string]$InstallerPath
    )
    Log-Message "Executing GLPI Agent installer: $InstallerPath"

    # Pass user domain as TAG
    $installArgs = "/quiet RUNNOW=1 SERVER='http://cas.sede.tjap/glpi/front/inventory.php' TAG='$userDomain'"

    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$InstallerPath`" $installArgs" -Wait -NoNewWindow -ErrorAction Stop
        Log-Message "GLPI Agent installation completed successfully."
    } catch {
        Log-Message "An error occurred during installation: $_" -Warning
        exit 1
    }
}

# Execute GLPI Agent installation
Install-GLPIAgent -InstallerPath $GLPIAgentMSI

Log-Message "Script execution completed."

# End of script
