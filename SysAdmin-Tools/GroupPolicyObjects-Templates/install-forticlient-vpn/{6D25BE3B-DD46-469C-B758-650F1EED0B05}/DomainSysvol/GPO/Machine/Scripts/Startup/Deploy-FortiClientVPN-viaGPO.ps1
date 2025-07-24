<#
.SYNOPSIS
    PowerShell Script for Deploying FortiClient VPN via GPO.

.DESCRIPTION
    This script automates the deployment of FortiClient VPN through Group Policy (GPO).
    It validates the presence of the MSI file, checks the installed FortiClient version,
    uninstalls outdated versions, installs the latest specified version, and manages VPN tunnel configurations.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 12, 2024
#>

param (
    [string]$FortiClientMSIPath = "\\forest-domain\netlogon\forticlient-vpn-install\forticlient-vpn-install.msi",
    [string]$MsiVersion = "7.4.0.1658" # Target version of FortiClient VPN to install.
)

$ErrorActionPreference = "Stop"

# Log Configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Keyword to search in the registry
$RegistryKeyword = "FortiClient VPN"

# Function to log messages
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

# Function to retrieve installed programs
function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ |
            Where-Object { $_.DisplayName -and $_.DisplayName -match $RegistryKeyword } |
            Select-Object DisplayName, DisplayVersion,
            @{Name = "UninstallString"; Expression = { $_.UninstallString } },
            @{Name = "Architecture"; Expression = { if ($_.PSPath -match 'WOW6432Node') { '32-bit' } else { '64-bit' } } }
        }
        return $installedPrograms
    }

    # Function to compare versions (returns True if 'installed' is earlier than 'target')
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
            Log-Message "Application uninstalled successfully using: $UninstallString"
        } catch {
            Log-Message "Error uninstalling the application: $_" -Severity "ERROR"
            throw
        }
    }

    try {
        # Ensure log directory exists
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Log-Message "Log directory $logDir created."
        }

        # Verify MSI path exists
        if (-not (Test-Path $FortiClientMSIPath)) {
            Log-Message "ERROR: The MSI file was not found at $FortiClientMSIPath. Please verify the path and try again." -Severity "ERROR"
            exit 1
        }

        Log-Message "MSI version to be installed: $MsiVersion"

        # Retrieve installed programs
        $installedPrograms = Get-InstalledPrograms
        if ($installedPrograms.Count -eq 0) {
            Log-Message "No version of FortiClient VPN was found. Proceeding with installation."
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

        # Proceed with installation
        Log-Message "No updated version found. Starting installation."
        $installArgs = "/qn /i `"$FortiClientMSIPath`" REBOOT=ReallySuppress /log `"$logPath`""
        Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -ErrorAction Stop
        Log-Message "FortiClient VPN installed successfully."

        # VPN Tunnels Management
        Log-Message "Starting VPN tunnel management."

        # Registry Path for Tunnels
        $TunnelRegistryPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"

        # Remove existing tunnels
        $ExistingTunnels = Get-ChildItem -Path $TunnelRegistryPath -ErrorAction SilentlyContinue
        foreach ($tunnel in $ExistingTunnels) {
            $tunnelPath = Join-Path $TunnelRegistryPath $tunnel.PSChildName
            Remove-Item -Path $tunnelPath -Recurse -Force -ErrorAction SilentlyContinue
            Log-Message "Removed existing tunnel: $tunnel.PSChildName"
        }

        # Define new tunnels
        $Tunnels = @{
            "VPN-Channel01" = @{
                "Description" = "Corporate Network VPN - Channel 01"
                "Server" = "vpn.corporate01.com:443"
                "promptusername" = 0
                "promptcertificate" = 0
                "ServerCert" = "1"
                "dual_stack" = 0
                "sso_enabled" = 0
                "use_external_browser" = 0
                "azure_auto_login" = 0
            }
            "VPN-Channel02" = @{
                "Description" = "Corporate Network VPN - Channel 02"
                "Server" = "vpn.corporate02.com:443"
                "promptusername" = 0
                "promptcertificate" = 0
                "ServerCert" = "1"
                "dual_stack" = 0
                "sso_enabled" = 0
                "use_external_browser" = 0
                "azure_auto_login" = 0
            }
        }

        # Add new tunnels
        foreach ($tunnelName in $Tunnels.Keys) {
            $tunnelRegistryPath = Join-Path $TunnelRegistryPath $tunnelName
            if (-not (Test-Path $tunnelRegistryPath)) {
                New-Item -Path $tunnelRegistryPath -Force | Out-Null
                Log-Message "Created registry path for tunnel: $tunnelRegistryPath"
            }
            foreach ($property in $Tunnels[$tunnelName].Keys) {
                Set-ItemProperty -Path $tunnelRegistryPath -Name $property -Value $Tunnels[$tunnelName][$property]
                Log-Message "Set property '$property' for tunnel '$tunnelName' to value '${Tunnels[$tunnelName][$property]}'"
            }
        }

        Log-Message "VPN tunnel management completed successfully."

    } catch {
        Log-Message "An error occurred: $_" -Severity "ERROR"
        exit 1
    }

    Log-Message "Script completed successfully."
    exit 0

    # End of script
