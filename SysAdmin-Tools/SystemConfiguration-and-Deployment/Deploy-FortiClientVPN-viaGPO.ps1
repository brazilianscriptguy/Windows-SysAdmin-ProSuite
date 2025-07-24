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
    Last Updated: February 10, 2024
#>

param (
    [string]$FortiClientMSIPath = "\\headq.scriptguy\netlogon\forticlient-vpn-install\forticlient-vpn-install.msi",
    [string]$MsiVersion = "7.4.1.1736"  # Target version of FortiClient VPN to install.
)
 
$ErrorActionPreference = "Stop"

# Log configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Function to log messages
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$Severity] [$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to log the message to $logPath. Error: $_"
    }
}

# Function to retrieve installed programs (searching for FortiClient VPN)
function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and $_.DisplayName -match "FortiClient VPN" } |
            Select-Object DisplayName, DisplayVersion,
            @{Name = "UninstallString"; Expression = { $_.UninstallString } }
        }
        return $installedPrograms
    }

    # Function to compare versions
    function Compare-Version {
        param (
            [string]$installed,
            [string]$target
        )
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
        param (
            [string]$UninstallString
        )
        try {
            Log-Message "Uninstalling FortiClient using: $UninstallString"
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/qn /x `"$UninstallString`" REBOOT=ReallySuppress" -Wait -ErrorAction Stop
            Log-Message "FortiClient successfully uninstalled."
        }
        catch {
            Log-Message "Error uninstalling FortiClient: $_" -Severity "ERROR"
            throw
        }
    }

    try {
        # Ensure the log directory exists
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Log-Message "Log directory $logDir created."
        }

        # Check if the MSI file exists
        if (-not (Test-Path $FortiClientMSIPath)) {
            Log-Message "ERROR: MSI file not found at $FortiClientMSIPath. Please check the path and try again." -Severity "ERROR"
            exit 1
        }

        Log-Message "MSI version to be installed: $MsiVersion"

        # Retrieve installed programs
        $installedPrograms = Get-InstalledPrograms
        $needInstall = $false

        if ($installedPrograms.Count -eq 0) {
            Log-Message "No FortiClient VPN version found. Proceeding with installation."
            $needInstall = $true
        }
        else {
            foreach ($program in $installedPrograms) {
                Log-Message "Found: $($program.DisplayName) - Version: $($program.DisplayVersion)"
                if (Compare-Version -installed $program.DisplayVersion -target $MsiVersion) {
                    Log-Message "Installed version ($($program.DisplayVersion)) is lower than the required ($MsiVersion). Update needed."
                    Uninstall-Application -UninstallString $program.UninstallString
                    $needInstall = $true
                }
                else {
                    Log-Message "Installed version ($($program.DisplayVersion)) is up-to-date. No need to reinstall FortiClient VPN."
                }
            }
        }

        # Proceed with installation if necessary
        if ($needInstall) {
            Log-Message "Starting FortiClient VPN installation."
            $installArgs = "/qn /i `"$FortiClientMSIPath`" REBOOT=ReallySuppress /log `"$logPath`""
            Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -ErrorAction Stop
            Log-Message "FortiClient VPN installed successfully."
        }

        # ============================================================
        # Removal and recreation of the tunnels registry key
        # ============================================================
        # Always remove the tunnels key (even if reinstallation is not needed)
        $BaseTunnelRegistryPath = "HKLM:\SOFTWARE\Fortinet\FortiClient\Sslvpn\Tunnels"
        if (Test-Path $BaseTunnelRegistryPath) {
            Remove-Item -Path $BaseTunnelRegistryPath -Recurse -Force -ErrorAction SilentlyContinue
            Log-Message "Tunnels registry key removed: $BaseTunnelRegistryPath"
        }
        else {
            Log-Message "Tunnels registry key not found. Proceeding with creation."
        }

        # Recreate the base tunnels registry key
        New-Item -Path $BaseTunnelRegistryPath -Force | Out-Null
        Log-Message "Base tunnels registry key recreated: $BaseTunnelRegistryPath"

        # Definition of tunnels to be configured
        $Tunnels = @{
            "VPN-SCRIPTGUY-CHANNEL01" = @{
                "Description" = "Remote Access via VPN to SCRIPTGUY"
                "Server" = "vpn.headq.scriptguy.com:443"
                "promptusername" = 0
                "promptcertificate" = 0
                "ServerCert" = "1"
                "dual_stack" = 0
                "sso_enabled" = 0
                "use_external_browser" = 0
                "azure_auto_login" = 0
            }
            "VPN-SCRIPTGUY-CHANNEL02" = @{
                "Description" = "Remote Access via VPN to SCRIPTGUY"
                "Server" = "vpn.headq.scriptguy-ddns.com:443"
                "promptusername" = 0
                "promptcertificate" = 0
                "ServerCert" = "1"
                "dual_stack" = 0
                "sso_enabled" = 0
                "use_external_browser" = 0
                "azure_auto_login" = 0
            }
        }

        # Create and configure the tunnels
        foreach ($tunnelName in $Tunnels.Keys) {
            $tunnelRegistryPath = Join-Path $BaseTunnelRegistryPath $tunnelName
            New-Item -Path $tunnelRegistryPath -Force | Out-Null
            Log-Message "Registry path created for tunnel: $tunnelRegistryPath"
            foreach ($property in $Tunnels[$tunnelName].Keys) {
                Set-ItemProperty -Path $tunnelRegistryPath -Name $property -Value $Tunnels[$tunnelName][$property] -ErrorAction SilentlyContinue
                Log-Message "Property '$property' configured for tunnel '$tunnelName' with value '$($Tunnels[$tunnelName][$property])'"
            }
        }

        Log-Message "VPN tunnels management completed successfully."
    }
    catch {
        Log-Message "An error occurred: $_" -Severity "ERROR"
        exit 1
    }

    Log-Message "Script completed successfully."
    exit 0

    # End of script
