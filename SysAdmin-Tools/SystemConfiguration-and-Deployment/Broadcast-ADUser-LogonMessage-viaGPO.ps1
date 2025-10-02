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
    Last Updated: 2025-10-02
#>

param (
    [string]$messagePath = "\\forest-logonserver\NETLOGON\broadcast-logonmessage\Broadcast-UserLogonMessageViaGPO.hta"
)

# Fail quietly by default (caller environment controlled)
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
try {
    $consolePtr = [Win32]::GetConsoleWindow()
    # 0 = SW_HIDE
    [Win32]::ShowWindow($consolePtr, 0) | Out-Null
} catch {
    # If hiding fails, continue but log the condition below (if logging is available)
}
# ---------------------------------

# Prepare logging
$scriptName  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir      = "C:\Scripts-LOGS"
$logFileName = "${scriptName}.log"
$logPath     = Join-Path $logDir $logFileName

function Log-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Severity = "INFO"
    )
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "[$timestamp] [$Severity] $Message"
        Add-Content -Path $logPath -Value $entry -ErrorAction Stop
    } catch {
        # If logging fails, we cannot do much in a hidden logon script; swallow to avoid blocking logon
    }
}

# Start
Log-Message "Script started. Target HTA: $messagePath"

# Validate the HTA path and run it via mshta.exe
if (Test-Path $messagePath -PathType Leaf) {
    Log-Message "HTA file found at: $messagePath"
    try {
        $mshta = Join-Path $env:windir "System32\mshta.exe"
        if (-not (Test-Path $mshta)) {
            Log-Message "mshta.exe not found at expected location: $mshta" "ERROR"
        } else {
            # Use Start-Process to launch mshta.exe with the HTA file; run hidden
            $args = "`"$messagePath`""
            Start-Process -FilePath $mshta -ArgumentList $args -WindowStyle Hidden -NoNewWindow
            Log-Message "mshta.exe launched (hidden) for: $messagePath"
        }
    } catch {
        Log-Message "Error launching mshta.exe for HTA: $_" "ERROR"
    }
} else {
    Log-Message "HTA file not found at: $messagePath" "ERROR"
}

Log-Message "Script finished."
exit 0

# End of script
