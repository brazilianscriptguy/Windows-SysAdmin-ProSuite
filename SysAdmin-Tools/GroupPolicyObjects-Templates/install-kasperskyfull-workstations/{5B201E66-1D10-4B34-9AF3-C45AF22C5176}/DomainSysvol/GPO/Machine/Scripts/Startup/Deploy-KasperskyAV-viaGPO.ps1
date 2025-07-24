<#
.SYNOPSIS
    PowerShell Script for Deploying Kaspersky Endpoint Security and Network Agent via GPO.

.DESCRIPTION
    This script automates the deployment of Kaspersky Endpoint Security (KES) and the Kaspersky Network Agent through Group Policy (GPO). 
    It validates the presence of the MSI files, checks the installed versions, uninstalls outdated versions, and installs the latest specified versions.
    Additionally, it configures the Network Agent with the specified server address.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 26, 2024
#>

param (
    [string]$KESInstallerPath = "\\forest-domain\netlogon\kes-antivirus-install\pkg_2\exec\kes_win.msi", # Path to KES installer
    [string]$NetworkAgentInstallerPath = "\\forest-domain\netlogon\kes-antivirus-install\pkg_1\exec\Kaspersky Network Agent.msi", # Path to Network Agent installer
    [string]$TargetKESVersion = "12.6.0.438", # Target version of Kaspersky Endpoint Security
    [string]$TargetAgentVersion = "14.0.0.10902", # Target version of Kaspersky Network Agent
    [string]$KLMoverServerAddress = "kes01-svr.contoso.com", # KES server address
    [string]$NetworkAgentDirectory = "C:\Program Files (x86)\Kaspersky Lab\NetworkAgent\" # Network Agent directory
)

$ErrorActionPreference = "Stop"

# Log Configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

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
        # If failing to write to log, log to Event Log
        Write-EventLog -LogName Application -Source "KES-Install Script" -EntryType Error -EventId 1001 -Message "Failed to write to log at $logPath. Error: $_"
    }
}

# Function to retrieve installed programs
function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and ($_.DisplayName -like "*Kaspersky Endpoint Security*" -or $_.DisplayName -like "*Kaspersky Network Agent*") } |
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
        try {
            # Sanitize versions to ensure consistent format
            $installedVersion = [Version]$installed.Trim() -replace '\s+', '.'
            $targetVersion = [Version]$target.Trim() -replace '\s+', '.'

            if ($installedVersion -lt $targetVersion) { return $true }
            else { return $false }
        } catch {
            Log-Message "Error comparing versions: $_" -Severity "ERROR"
            throw
        }
    }

    # Function to uninstall an application
    function Uninstall-Application {
        param (
            [string]$UninstallString
        )
        try {
            Log-Message "Received UninstallString: $UninstallString"

            if ([string]::IsNullOrWhiteSpace($UninstallString)) {
                throw "UninstallString is empty or not defined for the application."
            }

            # Determine if UninstallString is an MSI command or an executable
            if ($UninstallString -match 'MsiExec\.exe.*?\/[IX]\s*\{([\w\-]+)\}') {
                $productCode = $Matches[1]
                $arguments = @(
                    "/qn"
                    "/X{$productCode}"
                    "REBOOT=ReallySuppress"
                    "/norestart"
                )
                $exePath = "msiexec.exe"
            } elseif ($UninstallString -match '\{([\w\-]+)\}') {
                $productCode = $Matches[1]
                $arguments = @(
                    "/qn"
                    "/X{$productCode}"
                    "REBOOT=ReallySuppress"
                    "/norestart"
                )
                $exePath = "msiexec.exe"
            } elseif (Test-Path $UninstallString) {
                # UninstallString is a file path
                $exePath = $UninstallString
                $arguments = @(
                    "/S"  # Adjust based on the silent uninstallation parameters of the uninstaller
                )
            } else {
                throw "Invalid format of UninstallString: $UninstallString"
            }

            # Start the uninstallation process
            $process = Start-Process -FilePath $exePath -ArgumentList $arguments -Wait -PassThru -ErrorAction Stop
            if ($process.ExitCode -eq 0) {
                Log-Message "Application successfully uninstalled using: $exePath $($arguments -join ' ')"
            } else {
                throw "Uninstallation process returned exit code $($process.ExitCode)"
            }
        } catch {
            Log-Message "Error uninstalling the application: $_" -Severity "ERROR"
            throw
        }
    }

    # Function to remove residual registry entries
    function Remove-KasperskyRegistryEntries {
        param (
            [string[]]$ProductNames,
            [string]$TargetVersion
        )
        try {
            $registryPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
            )

            foreach ($regPath in $registryPaths) {
                Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $key = $_
                    $properties = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                    $displayName = $properties.DisplayName
                    $displayVersionString = $properties.DisplayVersion

                    if ($displayName) {
                        foreach ($productName in $ProductNames) {
                            if ($displayName -eq $productName) {
                                # Check if $displayVersionString is empty or null
                                if ([string]::IsNullOrWhiteSpace($displayVersionString)) {
                                    Log-Message "DisplayVersion is empty for ${displayName}. Removing registry entry."
                                    Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                    continue
                                }

                                $displayVersionString = $displayVersionString.Trim() -replace '\s+', '.'

                                try {
                                    $displayVersion = [Version]$displayVersionString
                                } catch {
                                    Log-Message "Invalid version format for ${displayName}: $displayVersionString. Removing registry entry."
                                    Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                    continue
                                }

                                # Compare versions
                                if ($displayVersion -ne [Version]$TargetVersion) {
                                    Log-Message "Removing residual registry entry: $displayName version $displayVersion"
                                    Remove-Item -Path $key.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                                } else {
                                    Log-Message "Keeping registry entry for $displayName version $displayVersion (target version)."
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            Log-Message "Error removing residual registry entries: $_" -Severity "ERROR"
            throw
        }
    }

    try {
        # Ensure the log directory exists
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            Log-Message "Log directory $logDir created."
        }

        # Verify if installers are accessible
        if (-not (Test-Path $KESInstallerPath)) {
            throw "KES installer not found at $KESInstallerPath"
        }
        if (-not (Test-Path $NetworkAgentInstallerPath)) {
            throw "Network Agent installer not found at $NetworkAgentInstallerPath"
        }

        Log-Message "KES MSI version to be installed: $TargetKESVersion"
        Log-Message "Network Agent MSI version to be installed: $TargetAgentVersion"

        # Retrieve installed Kaspersky programs
        $installedPrograms = Get-InstalledPrograms

        # Control variables for installation
        $installKES = $false
        $installAgent = $false

        # Flags to indicate if we should configure KLMover
        $configureKLMover = $false

        # Check and manage Kaspersky Endpoint Security
        $kesPrograms = $installedPrograms | Where-Object { $_.DisplayName -match "Kaspersky Endpoint Security" }
        if ($kesPrograms) {
            foreach ($kesProgram in $kesPrograms) {
                $displayName = $kesProgram.DisplayName
                $displayVersionString = $kesProgram.DisplayVersion

                # Check if $displayVersionString is empty or null
                if ([string]::IsNullOrWhiteSpace($displayVersionString)) {
                    Log-Message "DisplayVersion is empty for ${displayName}. Cannot compare versions." -Severity "ERROR"
                    continue
                }

                $uninstallString = $kesProgram.UninstallString

                try {
                    $displayVersion = [Version]$displayVersionString.Trim() -replace '\s+', '.'
                } catch {
                    Log-Message "Invalid version format for ${displayName}: $displayVersionString" -Severity "ERROR"
                    continue
                }

                Log-Message "Found $displayName version $displayVersion."

                if ([string]::IsNullOrWhiteSpace($uninstallString)) {
                    Log-Message "UninstallString is empty. Cannot uninstall $displayName." -Severity "ERROR"
                    continue
                }

                $needsUpdate = Compare-Version -installed $displayVersion.ToString() -target $TargetKESVersion

                if ($needsUpdate) {
                    Log-Message "Installed version ($displayVersion) is older than target version ($TargetKESVersion). Uninstalling."
                    Uninstall-Application -UninstallString $uninstallString
                    $installKES = $true
                } else {
                    Log-Message "Kaspersky Endpoint Security is up-to-date ($TargetKESVersion). No installation action needed."
                    # May need to configure KLMover
                    $configureKLMover = $true
                }
            }
        } else {
            Log-Message "No installation of Kaspersky Endpoint Security found. Proceeding with installation."
            $installKES = $true
        }

        # Check and manage Kaspersky Network Agent
        $agentPrograms = $installedPrograms | Where-Object { $_.DisplayName -match "Kaspersky Network Agent" }
        if ($agentPrograms) {
            foreach ($agentProgram in $agentPrograms) {
                $displayName = $agentProgram.DisplayName
                $displayVersionString = $agentProgram.DisplayVersion

                # Check if $displayVersionString is empty or null
                if ([string]::IsNullOrWhiteSpace($displayVersionString)) {
                    Log-Message "DisplayVersion is empty for ${displayName}. Cannot compare versions." -Severity "ERROR"
                    continue
                }

                $uninstallString = $agentProgram.UninstallString

                try {
                    $displayVersion = [Version]$displayVersionString.Trim() -replace '\s+', '.'
                } catch {
                    Log-Message "Invalid version format for ${displayName}: $displayVersionString" -Severity "ERROR"
                    continue
                }

                Log-Message "Found $displayName version $displayVersion."

                if ([string]::IsNullOrWhiteSpace($uninstallString)) {
                    Log-Message "UninstallString is empty. Cannot uninstall $displayName." -Severity "ERROR"
                    continue
                }

                $needsUpdate = Compare-Version -installed $displayVersion.ToString() -target $TargetAgentVersion

                if ($needsUpdate) {
                    Log-Message "Installed version ($displayVersion) is older than target version ($TargetAgentVersion). Uninstalling."
                    Uninstall-Application -UninstallString $uninstallString
                    $installAgent = $true
                } else {
                    Log-Message "Kaspersky Network Agent is up-to-date ($TargetAgentVersion). No installation action needed."
                    # May need to configure KLMover
                    $configureKLMover = $true
                }
            }
        } else {
            Log-Message "No installation of Kaspersky Network Agent found. Proceeding with installation."
            $installAgent = $true
        }

        # After uninstallation and before installation
        $productNamesToRemoveKES = @("Kaspersky Endpoint Security")
        $productNamesToRemoveAgent = @("Kaspersky Network Agent")

        # Remove residual registry entries for KES
        if ($installKES) {
            Log-Message "Removing residual registry entries for Kaspersky Endpoint Security."
            Remove-KasperskyRegistryEntries -ProductNames $productNamesToRemoveKES -TargetVersion $TargetKESVersion
        }

        # Remove residual registry entries for Agent
        if ($installAgent) {
            Log-Message "Removing residual registry entries for Kaspersky Network Agent."
            Remove-KasperskyRegistryEntries -ProductNames $productNamesToRemoveAgent -TargetVersion $TargetAgentVersion
        }

        # Install Kaspersky Endpoint Security if necessary
        if ($installKES) {
            Log-Message "Installing Kaspersky Endpoint Security version $TargetKESVersion."

            $installArgs = "/quiet /i `"$KESInstallerPath`" EULA=1 PRIVACYPOLICY=1 /log `"$logPath`""
            try {
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -ErrorAction Stop
                if ($process.ExitCode -eq 0) {
                    Log-Message "Kaspersky Endpoint Security installed successfully."
                } else {
                    throw "KES installation process returned exit code $($process.ExitCode)"
                }
                # As we just installed, need to configure KLMover
                $configureKLMover = $true
            } catch {
                Log-Message "Error installing Kaspersky Endpoint Security: $_" -Severity "ERROR"
                throw
            }
        }

        # Install Kaspersky Network Agent if necessary
        if ($installAgent) {
            Log-Message "Installing Kaspersky Network Agent version $TargetAgentVersion."

            $installArgs = "/quiet /i `"$NetworkAgentInstallerPath`" EULA=1 PRIVACYPOLICY=1 /log `"$logPath`""
            try {
                $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -ErrorAction Stop
                if ($process.ExitCode -eq 0) {
                    Log-Message "Kaspersky Network Agent installed successfully."
                } else {
                    throw "Network Agent installation process returned exit code $($process.ExitCode)"
                }
                # As we just installed, need to configure KLMover
                $configureKLMover = $true
            } catch {
                Log-Message "Error installing Kaspersky Network Agent: $_" -Severity "ERROR"
                throw
            }
        }

        # Configure Kaspersky Network Agent if necessary
        if ($configureKLMover) {
            $klmoverPath = Join-Path $NetworkAgentDirectory "klmover.exe"
            if (Test-Path $klmoverPath) {
                Log-Message "Configuring Kaspersky Network Agent with server address $KLMoverServerAddress."
                try {
                    $process = Start-Process -FilePath $klmoverPath -ArgumentList "-address $KLMoverServerAddress" -Wait -PassThru -ErrorAction Stop
                    if ($process.ExitCode -eq 0) {
                        Log-Message "Kaspersky Network Agent configured successfully."
                    } else {
                        throw "klmover.exe returned exit code $($process.ExitCode)"
                    }
                } catch {
                    Log-Message "Error configuring Kaspersky Network Agent: $_" -Severity "ERROR"
                    throw
                }
            } else {
                Log-Message "ERROR: klmover.exe not found in $NetworkAgentDirectory." -Severity "ERROR"
            }
        } else {
            Log-Message "Configuration of Kaspersky Network Agent is not necessary."
        }
    } catch {
        Log-Message "An error occurred: $_" -Severity "ERROR"
        # Log to Event Log
        Write-EventLog -LogName Application -Source "KES-Install Script" -EntryType Error -EventId 1002 -Message "An error occurred during script execution: $_"
        exit 1
    }

    Log-Message "Script execution completed successfully."
    exit 0

    # End of script
