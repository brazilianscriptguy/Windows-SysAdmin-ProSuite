<#
.SYNOPSIS
    PowerShell Script for Restarting Network Adapters via GUI.

.DESCRIPTION
    This script provides a quick and user-friendly way to restart network adapters through a GUI, 
    helping maintain network connectivity without requiring manual intervention.

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

# Load necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Function to check the status of the interface
function Check-NetAdapterStatus {
    param (
        [string]$InterfaceAlias
    )
    $status = (Get-NetAdapter -Name $InterfaceAlias).Status
    return $status
}

# Function to disable the network adapter
function Disable-Adapter {
    param (
        [string]$InterfaceAlias
    )
    Disable-NetAdapter -Name $InterfaceAlias -Confirm:$false
    Start-Sleep -Seconds 5
}

# Function to enable the network adapter
function Enable-Adapter {
    param (
        [string]$InterfaceAlias
    )
    Enable-NetAdapter -Name $InterfaceAlias -Confirm:$false
    Start-Sleep -Seconds 5
}

# Function to log messages
function Log-Message {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logPath -Value $logEntry -ErrorAction SilentlyContinue
}

# Initialize the log path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Network Adapter Manager"
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = "CenterScreen"

# Create the list box to display network adapters
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Size = New-Object System.Drawing.Size(360, 150)
$listBox.Location = New-Object System.Drawing.Point(10, 10)
$form.Controls.Add($listBox)

# Create the restart button
$restartButton = New-Object System.Windows.Forms.Button
$restartButton.Text = "Restart the Network Card"
$restartButton.Size = New-Object System.Drawing.Size(150, 23)
$restartButton.Location = New-Object System.Drawing.Point(10, 170)
$restartButton.Add_Click({
        $selectedAdapter = $listBox.SelectedItem
        if ($selectedAdapter) {
            $InterfaceAlias = $selectedAdapter.Split(" ")[0]
            Disable-Adapter -InterfaceAlias $InterfaceAlias
            if ((Check-NetAdapterStatus -InterfaceAlias $InterfaceAlias) -eq 'Disabled') {
                Log-Message "Network adapter $InterfaceAlias disabled successfully."
                Enable-Adapter -InterfaceAlias $InterfaceAlias
                if ((Check-NetAdapterStatus -InterfaceAlias $InterfaceAlias) -eq 'Up') {
                    [System.Windows.Forms.MessageBox]::Show("Network adapter $InterfaceAlias restarted successfully.", 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    Log-Message "Network adapter $InterfaceAlias re-enabled successfully."
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Failed to re-enable the network adapter $InterfaceAlias.", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    Log-Message "Failed to re-enable the network adapter $InterfaceAlias."
                }
            } else {
                [System.Windows.Forms.MessageBox]::Show("Failed to disable the network adapter $InterfaceAlias.", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                Log-Message "Failed to disable the network adapter $InterfaceAlias."
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Please select a network adapter first.", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
$form.Controls.Add($restartButton)

# Load the network adapters into the list box
$EthernetAdapters = Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq '802.3' -or $_.MediaType -eq 'Ethernet' -or $_.InterfaceDescription -match 'Ethernet' }
foreach ($adapter in $EthernetAdapters) {
    $listBox.Items.Add("$($adapter.Name) ($($adapter.InterfaceDescription))")
}

# Show the form
[void]$form.ShowDialog()

[Window]::Show()

# End of script
