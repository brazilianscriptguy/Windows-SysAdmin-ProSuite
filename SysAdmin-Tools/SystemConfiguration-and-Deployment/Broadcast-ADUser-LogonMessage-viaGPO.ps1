<#
.SYNOPSIS
    Post-logon script to display a standard message via an HTA file.

.DESCRIPTION
    - Executes the .HTA using mshta.exe so it does not depend on the system's file handler.
    - Writes execution logs to C:\Scripts-LOGS (one log file per script).
    - Designed to run as a User Logon Script via Group Policy.
    - Runs mshta in a hidden window to avoid flashing a console for users.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy (adapted & generalized)

.VERSION
    Last Updated: 2025-01-23
#>

param (
    [string]$messagePath = "\\forest-logonserver\NETLOGON\broadcast-logonmessage\Broadcast-UserLogonMessageViaGPO.hta"
)

$ErrorActionPreference = "SilentlyContinue"

# --- Hide the console window ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$consolePtr = [Win32]::GetConsoleWindow()
[Win32]::ShowWindow($consolePtr, 0) | Out-Null
# --------------------------------

# Logging configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\Scripts-LOGS"
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

function Log-Message {
    param (
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] [$Severity] $Message"
}

# Ensure log directory exists
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

# Execute .hta with mshta.exe
if (Test-Path $messagePath) {
    Log-Message "File found: $messagePath"
    try {
        Start-Process -FilePath "$env:windir\System32\mshta.exe" -ArgumentList "`"$messagePath`"" -WindowStyle Hidden
        Log-Message "HTA execution triggered."
    } catch {
        Log-Message "Error executing HTA: $_" "ERROR"
    }
} else {
    Log-Message "File not found: $messagePath" "ERROR"
}

exit 0

# --- End of script ---
