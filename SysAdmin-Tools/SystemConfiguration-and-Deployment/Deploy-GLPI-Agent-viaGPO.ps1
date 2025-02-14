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
    Last Updated: February 14, 2025
#>

param (
    # Path to the GLPI Agent MSI installer (desired version)
    [string]$GLPIAgentMSI = "\\headq.scriptguy\netlogon\glpi-agent112-install.msi",
    # Directory where logs will be recorded
    [string]$GLPILogDir = "C:\Logs-TEMP",
    # Expected version after installation
    [string]$ExpectedVersion = "1.12"
)

# Immediately stop execution in case of an error
$ErrorActionPreference = "Stop"

# Define log file name and path
$scriptName  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath     = Join-Path $GLPILogDir $logFileName

# Get the user’s domain from the environment variable; if not set, use a default value.
$userDomain = $env:USERDOMAIN
if (-not $userDomain) {
    $userDomain = "UNKNOWN_DOMAIN"
}

###############################################################################
# FUNCTION: Log-Message
# Logs messages to the log file. In case of an error, also logs to the EventLog.
###############################################################################
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$Severity] [$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    }
    catch {
        Write-EventLog -LogName Application -Source "GLPI-Agent-Install" -EntryType Error -EventId 1 -Message "Failed to write to log at $logPath. Error: $_"
    }
}

# Ensure the log directory exists
if (-not (Test-Path $GLPILogDir)) {
    New-Item -Path $GLPILogDir -ItemType Directory -Force | Out-Null
    Log-Message "Log directory $GLPILogDir created."
}

###############################################################################
# FUNCTION: Uninstall-GLPIAgent
# Uninstalls the current installation of GLPI Agent using the Registry value.
###############################################################################
function Uninstall-GLPIAgent {
    param (
        [string]$RegistryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\GLPI-Agent"
    )
    Log-Message "Checking for GLPI Agent in the registry..."
    try {
        $key = Get-ItemProperty -Path $RegistryKey -ErrorAction SilentlyContinue
        if ($key) {
            $uninstallString = $key.UninstallString
            if ($uninstallString) {
                Log-Message "Removing installed version of GLPI Agent..."
                # Execute the uninstallation command silently
                Start-Process -FilePath "cmdbexe" -ArgumentList "/c $uninstallString /quiet /norestart" -Wait -NoNewWindow
                Log-Message "GLPI Agent successfully removed."
            } else {
                Log-Message "Key found, but UninstallString is empty." -Severity "WARNING"
            }
        } else {
            Log-Message "GLPI Agent not found in the registry."
        }
    }
    catch {
        Log-Message "Error while uninstalling GLPI Agent: $_" -Severity "WARNING"
    }
}

###############################################################################
# FUNCTION: Install-GLPIAgent
# Installs the GLPI Agent via MSI.
###############################################################################
function Install-GLPIAgent {
    param (
        [string]$InstallerPath
    )
    Log-Message "Starting installation of GLPI Agent version $ExpectedVersion..."
    # Define installation parameters: /quiet, RUNNOW=1, SERVER, and TAG
    $installArgs = "/quiet RUNNOW=1 SERVER='http://cmdb.headq.scriptguy/front/inventory.php' TAG='$userDomain'"
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$InstallerPath`" $installArgs" -Wait -NoNewWindow -ErrorAction Stop
        Log-Message "GLPI Agent version $ExpectedVersion installed successfully."
    }
    catch {
        Log-Message "Error while installing GLPI Agent: $_" -Severity "WARNING"
        exit 1
    }
}

###############################################################################
# FUNCTION: Get-GLPIAgentPath
# Returns the path of the GLPI Agent executable, checking known locations.
###############################################################################
function Get-GLPIAgentPath {
    $possiblePaths = @(
        "C:\Program Files\GLPI-Agent\glpi-agent.exe",
        "C:\Program Files (x86)\GLPI-Agent\glpi-agent.exe",
        "C:\Program Files\GLPI-Agent\perl\bin\glpi-agent.exe"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    return $null
}

###############################################################################
# FUNCTION: Configure-GLPIAgent
# Applies configuration to the GLPI Agent by calling the executable with parameters.
###############################################################################
function Configure-GLPIAgent {
    param (
        [string]$AgentPath
    )
    Log-Message "Configuring GLPI Agent for domain: $userDomain..."
    $configArgs = "--server=http://cmdb.headq.scriptguy/front/inventory.php --tag='$userDomain' --debug"
    try {
        Start-Process -FilePath $AgentPath -ArgumentList $configArgs -Wait -NoNewWindow -ErrorAction Stop
        Log-Message "GLPI Agent configuration successfully applied."
    }
    catch {
        Log-Message "Error while configuring GLPI Agent: $_" -Severity "WARNING"
        exit 1
    }
}

###############################################################################
# MAIN SCRIPT FLOW
###############################################################################

# Always perform a clean installation: uninstall any existing version
Uninstall-GLPIAgent

# Install the GLPI Agent (even if no previous version exists)
Install-GLPIAgent -InstallerPath $GLPIAgentMSI

# Try to locate the installed executable
$glpiAgentPath = Get-GLPIAgentPath
if (-not $glpiAgentPath) {
    Log-Message "Error: Could not locate the GLPI Agent executable after installation." -Severity "WARNING"
    exit 1
} else {
    Log-Message "GLPI Agent found at: $glpiAgentPath"
    # Apply the agent configuration
    Configure-GLPIAgent -AgentPath $glpiAgentPath
}

Log-Message "End of script."
exit 0

# End of script
