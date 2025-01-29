<#
.SYNOPSIS
    PowerShell Script for Tracking Privileged Access Events.

.DESCRIPTION
    This script tracks privileged access events (Event IDs 4720, 4732, 4735, 4728, 4756, 4672, and 4724) 
    and organizes the data into a CSV report. It aids in auditing security changes and monitoring 
    privileged account activities.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 29, 2025
#>

Param(
    [Bool]$AutoOpen = $true
)

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
        ShowWindow(handle, 0);
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5);
    }
}
"@

[Window]::Hide()

# Import necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name for logging purposes
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Get the Domain Server Name
$DomainServerName = [System.Environment]::MachineName

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
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to display a message box
function Show-MessageBox {
    param ([string]$Message, [string]$Title)
    [System.Windows.Forms.MessageBox]::Show($Message, $Title)
}

# Function to update the progress bar
function Update-ProgressBar {
    param ([int]$Value)
    $progressBar.Value = $Value
    $form.Refresh()
}

# Function to select files via OpenFileDialog
function Select-Files {
    param ([string]$Filter, [string]$Title, [bool]$Multiselect)
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = $Filter
    $openFileDialog.Title = $Title
    $openFileDialog.Multiselect = $Multiselect
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $openFileDialog.FileNames
    }
}

# Function to retrieve privileged access events with detailed information
function Search-PrivilegedEvents {
    param ([string]$EvtxFilePath)

    $results = @()
    try {
        Log-Message "Searching Events IDs in $EvtxFilePath"
        $events = Get-WinEvent -Path $EvtxFilePath -FilterXPath "*[System[(EventID=4720 or EventID=4732 or EventID=4735 or EventID=4728 or EventID=4756 or EventID=4672 or EventID=4724)]]"
        
        foreach ($event in $events) {
            $properties = $event.Properties
            $result = [PSCustomObject]@{
                DateTime = $event.TimeCreated
                EventID = $event.Id
                AccountName = if ($properties.Count -gt 0) { $properties[0].Value } else { "N/A" }
                CallerUser = if ($properties.Count -gt 1) { $properties[1].Value } else { "N/A" }
                Domain = if ($properties.Count -gt 2) { $properties[2].Value } else { "N/A" }
                Message = $event.Message -replace "`r`n", " "
            }
            $results += $result
        }
        Log-Message "Finished searching $EvtxFilePath"
    } catch {
        $errorMsg = "Error searching Events in ${EvtxFilePath}: $($_.Exception.Message)"
        Log-Message $errorMsg
        Show-MessageBox -Message $errorMsg -Title "Search Error"
    }
    return $results
}

# GUI Configuration
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Privileged Access Event Tracker'
$form.Size = New-Object System.Drawing.Size @(400, 250)
$form.StartPosition = 'CenterScreen'

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point @(20, 80)
$progressBar.Size = New-Object System.Drawing.Size @(350, 20)
$form.Controls.Add($progressBar)

$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point @(20, 120)
$button.Size = New-Object System.Drawing.Size @(350, 40)
$button.Text = 'Start Analysis'
$button.Add_Click({
    Log-Message "Starting Privileged Access Event Analysis"
    $evtxFiles = Select-Files -Filter "EVTX Files (*.evtx)|*.evtx" -Title "Select EVTX Files" -Multiselect $true
    if ($evtxFiles) {
        $outputFilePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Privileged_Access_Logs_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $results = @()
        $totalFiles = $evtxFiles.Count
        $currentIndex = 0
        
        foreach ($evtxFile in $evtxFiles) {
            $currentIndex++
            Update-ProgressBar -Value ($currentIndex / $totalFiles * 100)
            $results += Search-PrivilegedEvents -EvtxFilePath $evtxFile
        }
        
        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $outputFilePath -NoTypeInformation -Encoding UTF8
            Show-MessageBox -Message "Results saved to: $outputFilePath" -Title "Analysis Complete"
            if ($AutoOpen) { Start-Process $outputFilePath }
        } else {
            Show-MessageBox -Message "No relevant events found." -Title "No Data"
        }
    } else {
        Show-MessageBox -Message "No EVTX files selected." -Title "No Input"
    }
})
$form.Controls.Add($button)
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()

# End of script
