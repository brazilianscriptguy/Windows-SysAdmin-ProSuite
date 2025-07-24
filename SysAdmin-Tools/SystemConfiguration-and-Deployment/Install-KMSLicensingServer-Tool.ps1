<#
.SYNOPSIS
    PowerShell Tool for Installing and Configuring KMS Licensing Server on Windows Server Forest Environment.

.DESCRIPTION
    This script installs the Volume Activation Services role and configures the KMS Licensing Server if no other KMS server exists within the AD forest.
    The tool includes a graphical user interface (GUI) and standardized logging for ease of use.

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

# Import the Active Directory module with error handling
function Import-RequiredModule {
    param (
        [string]$ModuleName
    )
    if (-not (Get-Module -Name $ModuleName)) {
        try {
            Import-Module -Name $ModuleName -ErrorAction Stop
            Write-Log -Message "Module $ModuleName imported successfully." -MessageType "INFO"
        } catch {
            Handle-Error "Failed to import $ModuleName module. Ensure it's installed and you have the necessary permissions."
            exit
        }
    }
}

Import-RequiredModule -ModuleName 'ActiveDirectory'

# Check if a KMS server already exists in the AD forest
function Verify-KMSServer {
    try {
        $existingKMS = Get-ADObject -Filter { servicePrincipalName -like "VAMT/KMS" } -SearchBase (Get-ADForest).RootDomain -ErrorAction Stop
        if ($existingKMS) {
            Write-Log "An existing KMS server was found in the forest. Aborting installation." -MessageType "WARNING"
            [System.Windows.Forms.MessageBox]::Show("A KMS server already exists in the AD forest. Installation is disabled.", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $true
        } else {
            Write-Log "No existing KMS server found in the forest." -MessageType "INFO"
            [System.Windows.Forms.MessageBox]::Show("No KMS server was found in the AD forest. You may proceed with the installation.", "Verification Result", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return $false
        }
    } catch {
        Handle-Error "Failed to check for existing KMS server in the forest."
        return $false
    }
}

# Execute commands with logging
function Execute-Command {
    param (
        [string]$Command,
        [string]$Arguments
    )
    try {
        Write-Log "Executing: $Command $Arguments" -MessageType "DEBUG"
        & $Command $Arguments
    } catch {
        Write-Log "Error executing command '$Command $Arguments': $_" -MessageType "ERROR"
        throw
    }
}

# Main Execution Function for KMS Installation
function Install-KMS {
    try {
        Write-Log "Installing Volume Activation Services role..." -MessageType "INFO"
        Install-WindowsFeature -Name VolumeActivation -IncludeAllSubFeature -IncludeManagementTools | Out-Null

        Write-Log "Configuring KMS settings..." -MessageType "INFO"
        Execute-Command "slmgr" "/ipk $KMSKey"
        Execute-Command "slmgr" "/ato"
        Execute-Command "slmgr" "/skms $($env:COMPUTERNAME):$KMSPort"
        Execute-Command "slmgr" "/sai $ActivationID"

        Write-Log "Configuring firewall to allow KMS traffic on port $KMSPort..." -MessageType "INFO"
        New-NetFirewallRule -DisplayName "KMS Server" -Direction Inbound -Protocol TCP -LocalPort $KMSPort -Action Allow | Out-Null

        Write-Log "KMS Server installation and configuration completed successfully." -MessageType "INFO"
        [System.Windows.Forms.MessageBox]::Show("KMS Server installed and configured successfully.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Handle-Error "An error occurred during KMS server installation: $_"
    }
}

# GUI Creation Function
function Create-KMSGUI {
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "KMS Server Installation Tool"
    $form.Size = New-Object System.Drawing.Size(800, 500)
    $form.StartPosition = "CenterScreen"

    # Input for KMS Key
    $labelKey = New-Object System.Windows.Forms.Label
    $labelKey.Text = "Enter KMS Key:"
    $labelKey.Location = New-Object System.Drawing.Point(10, 20)
    $labelKey.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($labelKey)

    $textBoxKey = New-Object System.Windows.Forms.TextBox
    $textBoxKey.Text = $KMSKey
    $textBoxKey.Location = New-Object System.Drawing.Point(140, 20)
    $textBoxKey.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($textBoxKey)

    # Button to verify KMS Server
    $buttonVerify = New-Object System.Windows.Forms.Button
    $buttonVerify.Text = "Verify KMS Server"
    $buttonVerify.Size = New-Object System.Drawing.Size(150, 30)
    $buttonVerify.Location = New-Object System.Drawing.Point(10, 60)
    $form.Controls.Add($buttonVerify)

    # Button to start installation
    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Text = "Start Installation"
    $buttonStart.Size = New-Object System.Drawing.Size(150, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(170, 60)
    $buttonStart.Enabled = $false
    $form.Controls.Add($buttonStart)

    # ListBox for displaying log messages
    $global:logBox = New-Object System.Windows.Forms.ListBox
    $global:logBox.Size = New-Object System.Drawing.Size(760, 320)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 100)
    $form.Controls.Add($global:logBox)

    # Event handler for Verify KMS Server button
    $buttonVerify.Add_Click({
            if (Verify-KMSServer) {
                $buttonStart.Enabled = $false
            } else {
                $buttonStart.Enabled = $true
            }
        })

    # Event handler for Start Installation button
    $buttonStart.Add_Click({
            $KMSKey = $textBoxKey.Text
            $buttonStart.Enabled = $false
            Install-KMS
            $buttonStart.Enabled = $true
        })

    # Show the form
    $form.ShowDialog()
}

# Run the GUI
Create-KMSGUI

# End of Script
