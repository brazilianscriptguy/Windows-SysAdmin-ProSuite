<#
.SYNOPSIS
    Validates the presence of Microsoft.UpdateServices.Administration.dll in the Global Assembly Cache (GAC).

.DESCRIPTION
    This script checks whether the WSUS Administration Console assembly is loaded in the current PowerShell session.
    If not, it attempts to load it from the Global Assembly Cache (GAC). If that fails, it attempts to load it directly
    from a known file path. The script also displays GUI message boxes to assist the user with guidance and diagnostics.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 11, 2025
#>

# Hide Console Window
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

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# Logging function 
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"
    Write-Output $formatted
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title = "WSUS Administration Assembly Check",
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon) | Out-Null
}

# Define the expected path to the WSUS Administration assembly in the GAC
$wsusAssemblyPath = "C:\Windows\Microsoft.Net\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration\v4.0_4.0.0.0__31bf3856ad364e35\Microsoft.UpdateServices.Administration.dll"

# Attempt to load the assembly by partial name (GAC)
try {
    $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
    if ($assembly) {
        Write-Log "WSUS Administration assembly loaded successfully from GAC." -Level INFO
        Show-MessageBox -Message "WSUS Administration assembly loaded successfully from the Global Assembly Cache (GAC)."
        return
    } else {
        throw "Assembly not loaded from GAC."
    }
} catch {
    Write-Log "Failed to load WSUS assembly from GAC: $_" -Level WARNING
}

# Attempt to load the assembly directly from known GAC path
if (Test-Path $wsusAssemblyPath) {
    try {
        Add-Type -Path $wsusAssemblyPath -ErrorAction Stop
        Write-Log "WSUS Administration assembly loaded successfully from $wsusAssemblyPath." -Level INFO
        Show-MessageBox -Message "WSUS Administration assembly loaded successfully from path:`n$wsusAssemblyPath"
    } catch {
        $msg = "Error: Failed to load WSUS assembly from:`n$wsusAssemblyPath`n`nDetails: $_"
        Write-Log $msg -Level ERROR
        Show-MessageBox -Message $msg -Icon 'Error'
        exit 1
    }
} else {
    $msg = "WSUS assembly not found at:`n$wsusAssemblyPath`n`nEnsure the WSUS Administration Console is installed using one of the following methods:`n"
    $msg += "`n1. Server Manager:`n   - Add Roles and Features > Features > Windows Server Update Services > WSUS Tools"
    $msg += "`n2. PowerShell:`n   - Install-WindowsFeature -Name UpdateServices-UI"
    Write-Log "Error: WSUS assembly not found at $wsusAssemblyPath." -Level ERROR
    Show-MessageBox -Message $msg -Icon 'Error'
    exit 1
}

# End of script
