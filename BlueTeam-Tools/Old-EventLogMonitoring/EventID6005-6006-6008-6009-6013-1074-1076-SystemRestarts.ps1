<#
.SYNOPSIS
    PowerShell Script for Tracking System Restarts and Shutdowns via Get-EventLog and Event IDs 6005, 6006, 6008, 6009, 6013, 1074, and 1076.

.DESCRIPTION
    This script retrieves details on system restarts and unexpected shutdowns based on Event IDs 
    6005, 6006, 6008, 6009, 6013, 1074, and 1076 using Get-EventLog, and exports the results to a CSV file.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 7, 2024
#>

Param(
    [Bool]$AutoOpen = $true
)

# Import necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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

# Determine the script name for logging purposes
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Set up logging
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
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Convert seconds to hh:mm:ss format
function Convert-SecondsToTime {
    param (
        [int]$Seconds
    )
    [TimeSpan]::FromSeconds($Seconds).ToString("hh\:mm\:ss")
}

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Monitor System Restarts and Shutdowns"
$form.Size = New-Object System.Drawing.Size @(500, 300)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Create a label for the number of days input
$labelDays = New-Object System.Windows.Forms.Label
$labelDays.Text = "Last days to process including today:"
$labelDays.AutoSize = $true
$labelDays.Location = New-Object System.Drawing.Point @(20, 20)
$form.Controls.Add($labelDays)

# Create a text box for entering the number of days
$textBoxDays = New-Object System.Windows.Forms.TextBox
$textBoxDays.Size = New-Object System.Drawing.Size @(50, 20)
$textBoxDays.Location = New-Object System.Drawing.Point @(20, 50)
$form.Controls.Add($textBoxDays)

# Create the Start Analysis button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Text = "Start Analysis"
$buttonStartAnalysis.Size = New-Object System.Drawing.Size @(120, 30)
$buttonStartAnalysis.Location = New-Object System.Drawing.Point @(20, 90)
$form.Controls.Add($buttonStartAnalysis)

# Create a progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Location = New-Object System.Drawing.Point @(20, 130)
$progressBar.Size = New-Object System.Drawing.Size @(450, 20)
$form.Controls.Add($progressBar)

# Create a label to display messages
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point @(20, 160)
$form.Controls.Add($statusLabel)

# Function to process the events using Get-EventLog
function Process-LogFiles {
    param (
        [Bool]$AutoOpen,
        [int]$daysToProcess
    )

    Log-Message "Starting to process Event IDs 6005, 6006, 6008, 6009, 6013, 1074, and 1076 in System log"
    try {
        $progressBar.Value = 25
        $statusLabel.Text = "Processing the log files..."
        $form.Refresh()

        $DefaultFolder = [Environment]::GetFolderPath("MyDocuments")
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $Destination = Join-Path $DefaultFolder "${scriptName}_${timestamp}.csv"

        # Get the date threshold for filtering
        $dateThreshold = (Get-Date).AddDays(-$daysToProcess)

        # Retrieve and filter events directly from System log
        $allEvents = Get-EventLog -LogName System | Where-Object {
            $_.EventID -in 6005, 6006, 6008, 6009, 6013, 1074, 1076 -and $_.TimeGenerated -ge $dateThreshold
        }

        $progressBar.Value = 50

        $eventDetails = $allEvents | Select-Object @{
            Name = 'Date'
            Expression = { $_.TimeGenerated.ToString("yyyy-MM-dd") }
        }, @{
            Name = 'Hour'
            Expression = { $_.TimeGenerated.ToString("HH:mm:ss") }
        }, @{
            Name = 'EventID'
            Expression = { $_.EventID }
        }, @{
            Name = 'MachineName'
            Expression = { $_.MachineName }
        }, @{
            Name = 'UserName'
            Expression = { $_.UserName }
        }, @{
            Name = 'Message'
            Expression = { $_.Message }
        }, @{
            Name = 'Uptime (hh:mm:ss)'
            Expression = { if ($_.EventID -eq 6013) { Convert-SecondsToTime($_.Message -replace "\D", "") } else { "" } }
        }

        # Export to CSV
        $eventDetails | Export-Csv -Path $Destination -NoTypeInformation -Delimiter ',' -Encoding UTF8 -Force

        $progressBar.Value = 75
        $statusLabel.Text = "Completed. Event counts exported to $Destination"
        Log-Message "Event counts exported to $Destination"

        if ($AutoOpen) {
            Start-Process $Destination
        }

        [System.Windows.Forms.MessageBox]::Show("Event counts exported to $Destination", 'Report Generated', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $progressBar.Value = 100
    } catch {
        $errorMsg = "Error processing Event IDs 6005, 6006, 6008, 6009, 6013, 1074, and 1076: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($errorMsg, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Log-Message $errorMsg
        $progressBar.Value = 0
        $statusLabel.Text = "Error occurred. Check log for details."
    } finally {
        $progressBar.Value = 0
    }
}

# Start Analysis button click event
$buttonStartAnalysis.Add_Click({
        $daysToProcess = $textBoxDays.Text
        $daysToProcessInt = 0
        if (-not [int]::TryParse($daysToProcess, [ref]$daysToProcessInt)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a valid number of days.", 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        Log-Message "Starting analysis of System log for Event IDs 6005, 6006, 6008, 6009, 6013, 1074, and 1076"
        $statusLabel.Text = "Processing..."
        $progressBar.Value = 0
        $form.Refresh()

        # Process the log files
        Process-LogFiles -AutoOpen $AutoOpen -daysToProcess $daysToProcessInt

        # Reset progress bar
        $progressBar.Value = 0
    })

# Show the main form
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

#End of script
