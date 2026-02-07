<#
.SYNOPSIS
    PowerShell Script for Installing PowerShell via GPO.

.DESCRIPTION
    This script simplifies the deployment of PowerShell to workstations and servers via Group Policy (GPO).
    It validates the MSI version, checks for existing installations, and updates or installs PowerShell as needed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 12, 2024
#>

param (
    [string]$PowerShellMSIPath = ""\\headq.scriptguy\netlogon\powershell-msi-folder\AutoDeployment-PowerShell.msi",
    [string]$MsiVersion = "7.4.6.0" # Target version of PowerShell to install
)

$ErrorActionPreference = "Stop"

# Configure log file path and name
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
    } catch {
        Write-Error "Failed to write to log at $logPath. Error: $_"
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
        Where-Object { $_.DisplayName -and $_.DisplayName -match "PowerShell" } |
        Select-Object DisplayName, DisplayVersion,
                      @{Name="UninstallString"; Expression={ $_.UninstallString }},
                      @{Name="Architecture"; Expression={ if ($_.PSPath -match 'WOW6432Node') {'32-bit'} else {'64-bit'} }}
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
    param ([string]$UninstallString)
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/quiet /x `"$UninstallString`" REBOOT=ReallySuppress" -Wait -ErrorAction Stop
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

    # Verify the MSI file exists
    if (-not (Test-Path $PowerShellMSIPath)) {
        Log-Message "ERROR: PowerShell MSI file not found at '$PowerShellMSIPath'. Please verify the path." -Severity "ERROR"
        exit 1
    }

    Log-Message "Target PowerShell MSI version: $MsiVersion"

    # Retrieve installed PowerShell programs
    $installedPrograms = Get-InstalledPrograms
    if ($installedPrograms.Count -eq 0) {
        Log-Message "No version of PowerShell found. Proceeding with installation."
    } else {
        foreach ($program in $installedPrograms) {
            Log-Message "Found: $($program.DisplayName) - Version: $($program.DisplayVersion) - Architecture: $($program.Architecture)"
            if (Compare-Version -installed $program.DisplayVersion -target $MsiVersion) {
                Log-Message "Installed version ($($program.DisplayVersion)) is earlier than target version ($MsiVersion). Update required."
                Uninstall-Application -UninstallString $program.UninstallString
            } else {
                Log-Message "Installed version ($($program.DisplayVersion)) is up-to-date. No action needed."
                return
            }
        }
    }

    # Proceed with PowerShell installation
    Log-Message "Starting PowerShell installation."
    $installArgs = "/quiet /i `"$PowerShellMSIPath`" ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1 /log `"$logPath`""
    Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -ErrorAction Stop
    Log-Message "PowerShell successfully installed."

} catch {
    Log-Message "An error occurred: $_" -Severity "ERROR"
    exit 1
}

Log-Message "Script completed successfully."
exit 0

# End of script
