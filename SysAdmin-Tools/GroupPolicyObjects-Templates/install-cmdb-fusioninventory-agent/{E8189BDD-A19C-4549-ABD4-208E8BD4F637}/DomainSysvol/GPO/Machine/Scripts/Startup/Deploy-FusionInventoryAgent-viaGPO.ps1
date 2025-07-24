<#
.SYNOPSIS
    PowerShell Script for Deploying FusionInventory Agent via GPO.

.DESCRIPTION
    This script deploys the FusionInventory Agent on workstations via Group Policy (GPO), 
    ensuring seamless inventory management and reporting in enterprise environments.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 12, 2024
#>

param (
    [string]$FusionInventoryURL = "http://glpi.contoso.com/plugins/fusioninventory/clients/2.6.1/fusioninventory-agent_windows-x64_2.6.1.exe",
    [string]$FusionInventoryLogDir = "C:\Logs-TEMP",
    [string]$ExpectedVersion = "2.6", # Target version of FusionInventory Agent to install
    [bool]$ReinstallIfSameVersion = $true
)

$ErrorActionPreference = "Stop"

# Log configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $FusionInventoryLogDir $logFileName

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
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
try {
    if (-not (Test-Path $FusionInventoryLogDir)) {
        New-Item -Path $FusionInventoryLogDir -ItemType Directory -Force | Out-Null
        Log-Message "Log directory $FusionInventoryLogDir created."
    }
} catch {
    Log-Message "WARNING: Failed to create log directory at $FusionInventoryLogDir." -Warning
}

# Retrieve the installed version of FusionInventory
function Get-InstalledVersion {
    param (
        [string]$RegistryKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\FusionInventory-Agent"
    )
    try {
        $key = Get-ItemProperty -Path $RegistryKey -ErrorAction SilentlyContinue
        if ($key) { return $key.DisplayVersion }
    } catch {
        Log-Message "Error accessing registry: $_" -Warning
    }
    return $null
}

# Check the installed version
$installedVersion = Get-InstalledVersion
if ($installedVersion -eq $ExpectedVersion -and -not $ReinstallIfSameVersion) {
    Log-Message "Version $ExpectedVersion of FusionInventory is already installed, and reinstallation is not allowed. No action required."
    exit 0
} elseif ($installedVersion -eq $ExpectedVersion -and $ReinstallIfSameVersion) {
    Log-Message "Version $ExpectedVersion is already installed, but reinstallation is allowed. Proceeding with reinstallation."
} else {
    Log-Message "Installing the new version of FusionInventory: $ExpectedVersion."
}

# Temporary path for download
$tempDir = [System.IO.Path]::GetTempPath()
$fusionInventorySetup = Join-Path $tempDir "fusioninventory-agent.exe"

# Download the installer
function Download-File {
    param (
        [string]$url,
        [string]$destinationPath
    )
    try {
        Log-Message "Downloading: $url"
        Invoke-WebRequest -Uri $url -OutFile $destinationPath -ErrorAction Stop
        Log-Message "Download completed: $url"
    } catch {
        Log-Message "Error downloading '$url'. Details: $_" -Warning
        throw
    }
}

Download-File -url $FusionInventoryURL -destinationPath $fusionInventorySetup

# Execute the installer
Log-Message "Executing the installer: $fusionInventorySetup"
$userDomain = $env:USERDOMAIN
if (-not $userDomain) {
    Log-Message "WARNING: USERDOMAIN variable not defined. Check environment settings." -Warning
    $userDomain = "UNKNOWN_DOMAIN"
}
$installArgs = "/S /acceptlicense /no-start-menu /runnow /server='http://glpi.contoso.com/plugins/fusioninventory/' /add-firewall-exception /installtasks=Full /execmode=Service /httpd-trust='127.0.0.1,10.10.0.0/8' /tag='$userDomain' /delaytime=3600"
try {
    Start-Process -FilePath $fusionInventorySetup -ArgumentList $installArgs -Wait -NoNewWindow -ErrorAction Stop
    Log-Message "FusionInventory installation completed successfully."
} catch {
    Log-Message "An error occurred during installation: $_" -Warning
    exit 1
}

# Remove the temporary installer
try {
    Log-Message "Removing the temporary installer: $fusionInventorySetup"
    Remove-Item -Path $fusionInventorySetup -Force -ErrorAction Stop
} catch {
    Log-Message "Error removing temporary installer: $_" -Warning
}

# Log script completion
Log-Message "Script execution completed successfully."
exit 0

# End of script
