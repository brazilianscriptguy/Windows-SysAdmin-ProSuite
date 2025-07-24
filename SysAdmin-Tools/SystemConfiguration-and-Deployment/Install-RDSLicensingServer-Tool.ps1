<#
.SYNOPSIS
    PowerShell Tool for Installing and Configuring Remote Desktop Licensing (RDS CALs) Server on Windows Server.

.DESCRIPTION
    This script installs the Remote Desktop Services (RDS) Licensing role on a Windows Server and configures it as the CAL (Client Access License) server.
    It includes an interactive GUI, checks for existing RDS Licensing roles, and provides detailed logging to ensure compliance and proper management.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 3, 2024
#>

# Hide the PowerShell console window
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
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@
[Window]::Hide()

# Add necessary assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Set up log path and global variables
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at ${logDir}. Logging will not be possible."
        return
    }
}

# Function to Log Messages
function Write-Log {
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
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
    
    if ($global:logBox -and $global:logBox.InvokeRequired -eq $false) {
        $global:logBox.Items.Add($logEntry)
        $global:logBox.TopIndex = $global:logBox.Items.Count - 1
    }
}

# Function to Handle Errors
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Write-Log -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Check if the Remote Desktop Licensing role is already installed
function Check-ExistingRDSLicensingRole {
    try {
        $rdsRoleInstalled = Get-WindowsFeature -Name "RDS-Licensing" | Where-Object { $_.InstallState -eq "Installed" }
        if ($rdsRoleInstalled) {
            Write-Log "An existing Remote Desktop Licensing role was found on this server. Aborting installation." -MessageType "WARNING"
            [System.Windows.Forms.MessageBox]::Show("The RDS Licensing role is already installed on this server. Installation is disabled.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $true
        } else {
            Write-Log "No existing RDS Licensing role found." -MessageType "INFO"
            [System.Windows.Forms.MessageBox]::Show("No RDS Licensing role found. You may proceed with the installation.", "Verification Result", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return $false
        }
    } catch {
        Handle-Error "Failed to check for existing RDS Licensing role."
        return $false
    }
}

# Main Execution Function for RDS Licensing Installation
function Install-RDSLicensing {
    try {
        Write-Log "Installing Remote Desktop Licensing role..." -MessageType "INFO"
        Install-WindowsFeature -Name RDS-Licensing -IncludeAllSubFeature -IncludeManagementTools | Out-Null

        Write-Log "Remote Desktop Licensing role installation completed successfully." -MessageType "INFO"
        [System.Windows.Forms.MessageBox]::Show("RDS Licensing Server installed successfully.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Handle-Error "An error occurred during RDS Licensing Server installation: $_"
    }
}

# GUI Creation Function
function Create-RDSLicensingGUI {
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "RDS Licensing Server Installation Tool"
    $form.Size = New-Object System.Drawing.Size(600, 400)
    $form.StartPosition = "CenterScreen"

    # Button to verify RDS Licensing Role
    $buttonVerify = New-Object System.Windows.Forms.Button
    $buttonVerify.Text = "Verify RDS Licensing Role"
    $buttonVerify.Size = New-Object System.Drawing.Size(180, 30)
    $buttonVerify.Location = New-Object System.Drawing.Point(10, 20)
    $form.Controls.Add($buttonVerify)

    # Button to start installation
    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Text = "Start Installation"
    $buttonStart.Size = New-Object System.Drawing.Size(180, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(200, 20)
    $buttonStart.Enabled = $false
    $form.Controls.Add($buttonStart)

    # ListBox for displaying log messages
    $global:logBox = New-Object System.Windows.Forms.ListBox
    $global:logBox.Size = New-Object System.Drawing.Size(560, 250)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 70)
    $form.Controls.Add($global:logBox)

    # Event handler for Verify RDS Licensing Role button
    $buttonVerify.Add_Click({
            if (Check-ExistingRDSLicensingRole) {
                $buttonStart.Enabled = $false
            } else {
                $buttonStart.Enabled = $true
            }
        })

    # Event handler for Start Installation button
    $buttonStart.Add_Click({
            $buttonStart.Enabled = $false
            Install-RDSLicensing
            $buttonStart.Enabled = $true
        })

    # Show the form
    $form.ShowDialog()
}

# Run the GUI
Create-RDSLicensingGUI

# End of Script
