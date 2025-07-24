<#
.SYNOPSIS
    PowerShell Script for Removing Non-Compliant Software via Group Policy.

.DESCRIPTION
    This script enforces software compliance by removing non-compliant or unauthorized 
    software via Group Policy (GPO). It helps to reduce vulnerabilities by automatically 
    uninstalling unauthorized applications across multiple machines within the domain.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

param (
    [string[]]$SoftwareNames = @(
        "Amazon Music", "avast", "avg", "Battle.net", "broffice", "Bubble Witch", "Candy Crush", "CCleaner", "Checkers Deluxe",
        "Circle Empires", "Crunchyroll", "Damas Pro", "Deezer", "Dic Michaelis", "Disney", "Dota", "Crosswords", "Gardenscapes",
        "GGPoker", "Glary Utilities", "Groove Music", "Hotspot", "Infatica", "LibreOffice 5.", "LibreOffice 6.", "McAfee", "netflix",
        "Northgard", "OpenVPN", "Riot Vanguard", "ShockwaveFlash", "Solitaire", "Souldiers", "Spotify", "StarCraft", "SupremaPoker",
        "Wandering", "TikTok", "WebDiscover Browser", "WireGuard", "xbox", "ZeroTier"
    ),
    [string]$LogDir = 'C:\Logs-TEMP'
)

$ErrorActionPreference = "Continue"

# Configure the log file name based on the script name
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $LogDir $logFileName

# Function to log messages with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log at $logPath. Error: $_"
    }
}

# Verify if the script is running
Log-Message "Script execution started."

try {
    # Ensure the log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -ErrorAction Stop | Out-Null
        Log-Message "Log directory $LogDir created."
    }

    # Search for installed software in the registry
    $installedSoftwarePaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($path in $installedSoftwarePaths) {
        Get-ChildItem $path | ForEach-Object {
            $software = Get-ItemProperty $_.PsPath
            foreach ($name in $SoftwareNames) {
                # Partial name matching
                if ($software.DisplayName -like "*$name*") {
                    Log-Message "Software found for removal: $($software.DisplayName)"
                    $uninstallCommand = $software.UninstallString
                    if ($uninstallCommand) {
                        if ($uninstallCommand -like "*msiexec*") {
                            $uninstallCommand = $uninstallCommand -replace "msiexec.exe", "msiexec.exe /quiet /norestart"
                            $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -PassThru -NoNewWindow
                        } else {
                            # Assume uninstallation can be run silently
                            $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand /S" -Wait -PassThru -NoNewWindow
                        }
                        if ($processInfo -and $processInfo.ExitCode -ne 0) {
                            Log-Message "Error uninstalling $($software.DisplayName) with exit code: $($processInfo.ExitCode)"
                        } elseif ($processInfo) {
                            Log-Message "$($software.DisplayName) was successfully uninstalled silently via executable command."
                        } else {
                            Log-Message "No uninstallation method found for $($software.DisplayName)."
                        }
                    } else {
                        Log-Message "No uninstall string found for $($software.DisplayName)."
                    }
                }
            }
        }
    }
} catch {
    Log-Message "An error occurred: $_"
}

Log-Message "Script execution finished."

# End of script
