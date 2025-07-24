<#
.SYNOPSIS
    PowerShell Script for Resetting and Re-Synchronizing GPOs.

.DESCRIPTION
    This script resets domain Group Policy Objects (GPOs) via a user-friendly GUI and re-synchronizes 
    policies to ensure accurate application across the domain.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
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

# Load necessary assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Function to delete directories where the GPOs are stored
function Remove-GPODirectory {
    param (
        [string]$DirectoryPath
    )

    if (Test-Path -Path $DirectoryPath) {
        Remove-Item -Path $DirectoryPath -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "GPO directory deleted: $DirectoryPath"
    }
}

# Function to reset all GPOs
function Reset-AllGPOs {
    param (
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel
    )

    try {
        # Logging the start of GPO reset process
        Log-Message "Start of GPO reset process."
        $StatusLabel.Text = "Resetting GPOs using setup security.inf..."
        $ProgressBar.Value = 10

        # Resetting GPOs using "setup security.inf"
        $command = "secedit /configure /db reset.sdb /cfg `"C:\Windows\security\templates\setup security.inf`" /overwrite /quiet"
        Invoke-Expression $command
        Log-Message "GPOs reset using setup security.inf"
        $StatusLabel.Text = "GPOs reset using setup security.inf"
        $ProgressBar.Value = 30

        # Resetting GPOs using "defltbase.inf"
        $StatusLabel.Text = "Resetting GPOs using defltbase.inf..."
        $cfgPath = Join-Path -Path $env:windir -ChildPath "inf\defltbase.inf"
        $command = "secedit /configure /db reset.sdb /cfg `"$cfgPath`" /areas USER_POLICY MACHINE_POLICY SECURITYPOLICY /overwrite /quiet"
        Invoke-Expression $command
        Log-Message "GPOs reset using defltbase.inf"
        $StatusLabel.Text = "GPOs reset using defltbase.inf"
        $ProgressBar.Value = 50

        # Deleting the registry key where current GPO settings reside
        $StatusLabel.Text = "Deleting GPO registry key..."
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy" -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Registry key of GPOs deleted."
        $StatusLabel.Text = "GPO registry key deleted."
        $ProgressBar.Value = 70

        # Removing Group Policy directories
        $StatusLabel.Text = "Removing Group Policy directories..."
        Remove-GPODirectory -DirectoryPath "$env:windir\System32\GroupPolicy"
        Remove-GPODirectory -DirectoryPath "$env:windir\System32\GroupPolicyUsers"
        Remove-GPODirectory -DirectoryPath "$env:windir\SysWOW64\GroupPolicy"
        Remove-GPODirectory -DirectoryPath "$env:windir\SysWOW64\GroupPolicyUsers"
        Log-Message "Group Policy directories removed."
        $StatusLabel.Text = "Group Policy directories removed."
        $ProgressBar.Value = 90

        # Logging the successful completion of GPO reset process
        Log-Message "GPO reset process completed successfully."
        $StatusLabel.Text = "GPO reset process completed successfully."
        $ProgressBar.Value = 100

        # Scheduling system reboot after 15 seconds
        Show-InfoMessage "The GPO reset process has been completed successfully. The system will restart in 15 seconds. Please save your work."
        Start-Sleep -Seconds 15
        Restart-Computer -Force
    } catch {
        # Logging any error that occurs during GPO reset process
        Log-Message "An error occurred during the GPO reset process: $($_.Exception.Message)" -MessageType "ERROR"
        Show-ErrorMessage "An error occurred during the GPO reset process: $($_.Exception.Message)"
        $ProgressBar.Value = 0
        $StatusLabel.Text = "An error occurred during the GPO reset process."
    }
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Reset Domain GPOs and Resync Tool'
$form.Size = New-Object System.Drawing.Size(400, 250)
$form.StartPosition = 'CenterScreen'

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 20)
$statusLabel.Size = New-Object System.Drawing.Size(360, 20)
$statusLabel.TextAlign = 'Left'
$form.Controls.Add($statusLabel)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 50)
$progressBar.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($progressBar)

# Reset GPOs button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Location = New-Object System.Drawing.Point(50, 90)
$resetButton.Size = New-Object System.Drawing.Size(300, 40)
$resetButton.Text = 'Reset Domain GPOs and Resync'
$resetButton.Add_Click({ Reset-AllGPOs -ProgressBar $progressBar -StatusLabel $statusLabel })
$form.Controls.Add($resetButton)

# Close button
$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Location = New-Object System.Drawing.Point(300, 150)
$closeButton.Size = New-Object System.Drawing.Size(75, 23)
$closeButton.Text = 'Close'
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

$form.Add_Shown({ $form.Activate() })

[void]$form.ShowDialog()

# End of Script
