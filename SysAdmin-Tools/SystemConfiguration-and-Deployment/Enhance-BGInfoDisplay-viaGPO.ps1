<#
.SYNOPSIS
    PowerShell Script for Integrating BGInfo Display with GPO.

.DESCRIPTION
    This script integrates BGInfo with Group Policy (GPO) to enrich server desktop displays 
    with critical system information, aiding IT administrators in monitoring system health.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Determine the script name and set up logging path
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
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display error messages
function Log-ErrorMessage {
    param ([string]$message)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display warning messages
function Log-WarningMessage {
    param ([string]$message)
    Log-Message "Warning: $message" -MessageType "WARNING"
}

# Function to display information messages
function Log-InfoMessage {
    param ([string]$message)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Create a shortcut to BGInfo in the Common Startup directory
function Create-BGInfoShortcut {
    param (
        [string]$CommonStartUpDir,
        [string]$BGInfoPath,
        [string]$BGInfoConfig
    )

    $shortcutPath = Join-Path -Path $CommonStartUpDir -ChildPath "bginfo.lnk"
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $shortcut = $WScriptShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $BGInfoPath
        $shortcut.Arguments = "/timer:0 /silent /nolicprompt $BGInfoConfig"
        $shortcut.Save()
        Log-Message "Shortcut created successfully: $shortcutPath"
    } catch {
        Log-ErrorMessage "Failed to create BGInfo shortcut: $($_.Exception.Message)"
    }
}

# Main execution
try {
    Log-Message "Starting BGInfo script execution."

    $CommonStartUpDir = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    $BGInfoPath = "%systemroot%\Resources\ITSM-Templates-Servers\Themes\BGInfo\bginfo64.exe"
    $BGInfoConfig = "%systemroot%\Resources\ITSM-Templates-Servers\Themes\BGInfo\Enhance-BGInfoDisplay-viaGPO.bgi"

    if ((Test-Path $BGInfoPath) -and (Test-Path $BGInfoConfig)) {
        Create-BGInfoShortcut -CommonStartUpDir $CommonStartUpDir -BGInfoPath $BGInfoPath -BGInfoConfig $BGInfoConfig
        Log-InfoMessage "BGInfo shortcut creation completed."
    } else {
        Log-ErrorMessage "BGInfo executable or configuration file not found."
    }

    Log-Message "BGInfo script execution completed successfully."
} catch {
    Log-ErrorMessage "An unexpected error occurred: $($_.Exception.Message)"
}

# End of script
