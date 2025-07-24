<#
.SYNOPSIS
    PowerShell Script for Uninstalling Selected Applications from Workstations.

.DESCRIPTION
    This script provides a user-friendly graphical interface for selecting and uninstalling 
    applications from workstations. It automates the detection and removal of unwanted or 
    potentially malicious software, ensuring effective uninstallation with minimal manual 
    intervention.

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

# Import necessary libraries for GUI
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
function Write-Log {
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

# Function to extract GUID from registry path
function Get-GUIDFromPath {
    param ([string]$Path)
    $regex = [regex]'Uninstall\\(.*)'
    $matches = $regex.Match($Path)
    if ($matches.Success) {
        return $matches.Groups[1].Value
    }
    return $null
}

# Function to retrieve installed programs from both 32-bit and 64-bit registries
function Get-InstalledPrograms {
    Write-Log -Message "Retrieving list of installed programs"
    $installedPrograms64Bit = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, 
        @{Name = "IdentifyingNumber"; Expression = { Get-GUIDFromPath $_.PSPath } },
        @{Name = "UninstallString"; Expression = { $_.UninstallString } },
        @{Name = "Architecture"; Expression = { "64-bit" } }

    $installedPrograms32Bit = Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, 
        @{Name = "IdentifyingNumber"; Expression = { Get-GUIDFromPath $_.PSPath } },
        @{Name = "UninstallString"; Expression = { $_.UninstallString } },
        @{Name = "Architecture"; Expression = { "32-bit" } }

    return $installedPrograms64Bit + $installedPrograms32Bit
}

# Function to uninstall a selected application
function Uninstall-Application {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SelectedAppName
    )
    $application = Get-InstalledPrograms | Where-Object { $_.DisplayName -eq $SelectedAppName }

    if ($application) {
        try {
            Write-Log -Message "Attempting to uninstall application: $($application.DisplayName)"
            $uninstallPath = Get-ChildItem -Path "C:\Program Files\$($application.DisplayName)", "C:\Program Files (x86)\$($application.DisplayName)" -Filter 'uninstall*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

            if ($uninstallPath) {
                $uninstallString = "`"$uninstallPath`" /SILENT"
            } elseif ($application.UninstallString) {
                $uninstallString = $application.UninstallString
            } else {
                [System.Windows.Forms.MessageBox]::Show("No uninstall method found for application: $($application.DisplayName)")
                Write-Log -Message "No uninstall method found for application: $($application.DisplayName)" -MessageType "ERROR"
                return
            }

            Start-Process cmd -ArgumentList "/c $uninstallString" -Wait
            [System.Windows.Forms.MessageBox]::Show("Uninstall command executed for application: $($application.DisplayName)")
            Write-Log -Message "Uninstall command executed for application: $($application.DisplayName)"
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error uninstalling application: $($application.DisplayName)")
            Write-Log -Message "Error uninstalling application: $($application.DisplayName)" -MessageType "ERROR"
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Application not found: $SelectedAppName")
        Write-Log -Message "Application not found: $SelectedAppName" -MessageType "ERROR"
    }
}

# Function to create the GUI for uninstalling applications
function Create-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Uninstall Applications'
    $form.Size = New-Object System.Drawing.Size(520, 400)
    $form.StartPosition = 'CenterScreen'

    # Application Name label and textbox
    $labelAppName = New-Object System.Windows.Forms.Label
    $labelAppName.Text = 'Enter Application Name:'
    $labelAppName.Location = New-Object System.Drawing.Point(10, 10)
    $labelAppName.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($labelAppName)

    $textBoxAppName = New-Object System.Windows.Forms.TextBox
    $textBoxAppName.Location = New-Object System.Drawing.Point(10, 40)
    $textBoxAppName.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($textBoxAppName)

    # ListBox to display matching applications
    $listBoxApps = New-Object System.Windows.Forms.ListBox
    $listBoxApps.Location = New-Object System.Drawing.Point(10, 70)
    $listBoxApps.Size = New-Object System.Drawing.Size(480, 200)
    $form.Controls.Add($listBoxApps)

    # Search button
    $searchButton = New-Object System.Windows.Forms.Button
    $searchButton.Location = New-Object System.Drawing.Point(10, 280)
    $searchButton.Size = New-Object System.Drawing.Size(100, 30)
    $searchButton.Text = 'Search'
    $searchButton.Add_Click({
            $listBoxApps.Items.Clear()
            $applications = Get-InstalledPrograms | Where-Object { $_.DisplayName -like "*$($textBoxAppName.Text)*" }
            foreach ($app in $applications) {
                $listBoxApps.Items.Add($app.DisplayName)
            }
        })
    $form.Controls.Add($searchButton)

    # Uninstall button
    $uninstallButton = New-Object System.Windows.Forms.Button
    $uninstallButton.Location = New-Object System.Drawing.Point(120, 280)
    $uninstallButton.Size = New-Object System.Drawing.Size(100, 30)
    $uninstallButton.Text = 'Uninstall'
    $uninstallButton.Add_Click({
            $selectedApp = $listBoxApps.SelectedItem
            if ($selectedApp -ne $null) {
                Uninstall-Application -SelectedAppName $selectedApp
            }
        })
    $form.Controls.Add($uninstallButton)

    # Close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(390, 280)
    $closeButton.Size = New-Object System.Drawing.Size(100, 30)
    $closeButton.Text = 'Close'
    $closeButton.Add_Click({ $form.Close() })
    $form.Controls.Add($closeButton)

    # Show the form
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
}

# Start of the script
Write-Log -Message "Script execution started"

# Call the function to create the GUI
Create-GUI

# End of the script
Write-Log -Message "Script execution completed"
