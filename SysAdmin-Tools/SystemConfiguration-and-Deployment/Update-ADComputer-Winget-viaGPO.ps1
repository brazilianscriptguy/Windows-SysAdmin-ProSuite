<#
.SYNOPSIS
    PowerShell Script for Updating Software via Winget Using GPO.

.DESCRIPTION
    This script automates software updates across workstations using the winget tool, with 
    deployment managed through Group Policy (GPO), ensuring consistent software management across the domain.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Log file path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
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
        Write-Error "Failed to write to log: $_"
    }
}

# Function to find the winget executable path
function Find-WingetPath {
    param (
        [string]$SearchBase = "C:\Program Files\WindowsApps",
        [string]$SearchPattern = 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe'
    )

    try {
        Log-Message "Searching for winget executable..."
        $wingetPath = Get-ChildItem -Path $SearchBase -Filter 'winget.exe' -Recurse -ErrorAction Ignore |
            Where-Object { $_.FullName -like "*$SearchPattern" } |
            Select-Object -ExpandProperty FullName -First 1
        if ($wingetPath -and (Test-Path -Path $wingetPath -Type Leaf)) {
            Log-Message "winget found at: $wingetPath"
            return $wingetPath
        } else {
            throw "winget not found."
        }
    } catch {
        $errorMsg = "An error occurred while searching for winget: $($_.Exception.Message)"
        Log-Message $errorMsg
        return $null
    }
}

# Function to update software using winget
function Update-Software {
    param (
        [string]$WingetPath
    )

    try {
        Log-Message "Starting software updates with winget..."
        $wingetCommandQuery = "& `"$WingetPath`" upgrade --query"
        $wingetUpdateAvailable = Invoke-Expression $wingetCommandQuery | Out-String

        if ($wingetUpdateAvailable -match "No applicable updates found") {
            Log-Message "No updates available for any packages."
        } else {
            $wingetCommandUpgrade = "& `"$WingetPath`" upgrade --all --include-unknown --silent --accept-package-agreements --accept-source-agreements"
            $updateResults = Invoke-Expression $wingetCommandUpgrade
            Log-Message "All package updates completed successfully. Details: `n$updateResults"
        }
    } catch {
        $errorMsg = "An error occurred during the update: $($_.Exception.Message)"
        Log-Message $errorMsg
    }
}

# Main script logic
$wingetPath = Find-WingetPath

if ($wingetPath) {
    Update-Software -WingetPath $wingetPath
} else {
    Log-Message "winget not found. Please verify the installation and path."
}

# End of script
