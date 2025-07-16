<#
.SYNOPSIS
    [SCRIPT_TITLE] - PowerShell Logging and Error Handling Framework

.DESCRIPTION
    A standardized PowerShell script template with built-in logging, error handling, GUI readiness, 
    and dynamic initialization. Ideal for automation, deployments, or interactive tasks.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2025-07-16 09:06 AM -03
    Version: 3.0
#>

#region --- Global Setup ---

# Optional: Hide Console Window for GUI-based execution or silent automation
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

# Load GUI-related assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

#endregion

#region --- Logging & Error Handling Framework ---

function Initialize-ScriptPaths {
    param (
        [string]$DefaultLogDir = 'C:\Logs-TEMP'
    )

    $scriptName = if ($PSCommandPath) {
        [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    } else {
        "Script"
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        ScriptName = $scriptName
    }
}

function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        if (-not (Test-Path $global:logDir)) {
            New-Item -Path $global:logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $global:logPath -Value $logEntry -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log file: $_"
        Write-Output $logEntry
    }

    Write-Host $logEntry
}

function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    Log-Message -Message "$ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage,
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

#endregion

#region --- Example Usage Block ---

function Example-Logging {
    # Initialize global paths
    $paths = Initialize-ScriptPaths
    $global:logDir = $paths.LogDir
    $global:logPath = $paths.LogPath

    Log-Message -Message "Script [$($paths.ScriptName)] started." -MessageType "INFO"

    try {
        Log-Message -Message "Executing main logic..." -MessageType "DEBUG"

        # Simulate error
        throw "An example error occurred during execution."

    } catch {
        Handle-Error -ErrorMessage $_.Exception.Message
    } finally {
        Log-Message -Message "Script execution complete." -MessageType "INFO"
    }
}

# Entry Point
Example-Logging

#endregion
