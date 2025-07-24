<#
.SYNOPSIS
    PowerShell Script for Removing Empty Files or Files by Date Range.

.DESCRIPTION
    This script detects and removes empty files or files within a specified date range, 
    optimizing file storage and improving system organization.

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

# Function to display messages
function Show-Message {
    param (
        [string]$message,
        [string]$title,
        [string]$icon
    )
    [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
    Log-Message "${title}: ${message}" -MessageType ($title.ToUpper())
}

# Function to select a directory
function Select-Directory {
    Log-Message "Prompting user to select a directory."
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Folders|*.none"
    $openFileDialog.CheckFileExists = $false
    $openFileDialog.CheckPathExists = $true
    $openFileDialog.Title = "Select the directory"
    $openFileDialog.FileName = "Select or Paste a Path"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $directoryPath = [System.IO.Path]::GetDirectoryName($openFileDialog.FileName)
        $directoryPath = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::Default.GetBytes($directoryPath))
        Log-Message "Directory selected: $directoryPath"
        return $directoryPath
    } else {
        Log-Message "Directory selection cancelled by user."
        return $null
    }
}

# Initialize form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'File Operation Tool'
$form.Size = New-Object System.Drawing.Size(600, 550)
$form.StartPosition = 'CenterScreen'

# Initialize reusable UI controls
$labelSelectedFolder = New-Object System.Windows.Forms.Label
$labelSelectedFolder.Location = New-Object System.Drawing.Point(10, 10)
$labelSelectedFolder.Size = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($labelSelectedFolder)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10, 370)
$listBox.Size = New-Object System.Drawing.Size(560, 120)
$form.Controls.Add($listBox)

# ======================================
# Section: Date Range File Deletion
# ======================================

$labelDateSection = New-Object System.Windows.Forms.Label
$labelDateSection.Location = New-Object System.Drawing.Point(10, 40)
$labelDateSection.Size = New-Object System.Drawing.Size(400, 20)
$labelDateSection.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 10, [System.Drawing.FontStyle]::Bold)
$labelDateSection.Text = 'Delete Files by Date Range in Selected Folder'
$form.Controls.Add($labelDateSection)

$buttonSelectDateRangeFolder = New-Object System.Windows.Forms.Button
$buttonSelectDateRangeFolder.Text = 'Select Folder'
$buttonSelectDateRangeFolder.Location = New-Object System.Drawing.Point(10, 70)
$buttonSelectDateRangeFolder.Size = New-Object System.Drawing.Size(100, 30)
$buttonSelectDateRangeFolder.Add_Click({
        $global:selectedFolderPath = Select-Directory
        if ($global:selectedFolderPath) {
            $labelSelectedFolder.Text = "Selected folder: $global:selectedFolderPath"
            Find-DateRangeFiles $global:selectedFolderPath
        }
    })
$form.Controls.Add($buttonSelectDateRangeFolder)

$startDateLabel = New-Object System.Windows.Forms.Label
$startDateLabel.Text = 'Start Date:'
$startDateLabel.Location = New-Object System.Drawing.Point(120, 75)
$form.Controls.Add($startDateLabel)

$startDatePicker = New-Object System.Windows.Forms.DateTimePicker
$startDatePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Long
$startDatePicker.Location = New-Object System.Drawing.Point(240, 70)
$startDatePicker.Width = 240
$form.Controls.Add($startDatePicker)

$endDateLabel = New-Object System.Windows.Forms.Label
$endDateLabel.Text = 'End Date:'
$endDateLabel.Location = New-Object System.Drawing.Point(120, 105)
$form.Controls.Add($endDateLabel)

$endDatePicker = New-Object System.Windows.Forms.DateTimePicker
$endDatePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Long
$endDatePicker.Location = New-Object System.Drawing.Point(240, 100)
$endDatePicker.Width = 240
$form.Controls.Add($endDatePicker)

$deleteByDateButton = New-Object System.Windows.Forms.Button
$deleteByDateButton.Text = 'Delete Files'
$deleteByDateButton.Location = New-Object System.Drawing.Point(10, 130)
$deleteByDateButton.Size = New-Object System.Drawing.Size(100, 30)
$deleteByDateButton.Add_Click({
        if (-not $global:selectedFolderPath) {
            Show-ErrorMessage "Please select a folder first!"
            return
        }
        $startDate = $startDatePicker.Value
        $endDate = $endDatePicker.Value
        $files = Get-ChildItem -Path $global:selectedFolderPath -Recurse -File | Where-Object { $_.LastWriteTime -ge $startDate -and $_.LastWriteTime -le $endDate }
        if ($files.Count -eq 0) {
            Show-InfoMessage "No files found in the selected date range."
            Log-Message "No files found for deletion in date range $startDate to $endDate in folder $global:selectedFolderPath"
            return
        }
        foreach ($file in $files) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
                Log-Message "Deleted file: $($file.FullName)"
            } catch {
                Log-Message "Failed to delete file: $($file.FullName)" -MessageType "ERROR"
            }
        }
        Show-InfoMessage "$($files.Count) file(s) deleted successfully!"
        Log-Message "Deleted $($files.Count) files in $global:selectedFolderPath from $startDate to $endDate"
        Find-DateRangeFiles $global:selectedFolderPath # Refresh the list after deletion
    })
$form.Controls.Add($deleteByDateButton)

function Find-DateRangeFiles {
    param ($folderPath)
    $listBox.Items.Clear()
    $startDate = $startDatePicker.Value
    $endDate = $endDatePicker.Value
    $files = Get-ChildItem -Path $folderPath -Recurse -File | Where-Object { $_.LastWriteTime -ge $startDate -and $_.LastWriteTime -le $endDate }
    $listBox.Items.AddRange($files.FullName)
    Show-InfoMessage "$($files.Count) file(s) found in the selected date range."
    Log-Message "Found $($files.Count) files in date range $startDate to $endDate in folder $folderPath"
}

# Graphical Separator
$separatorPanel = New-Object System.Windows.Forms.Panel
$separatorPanel.Location = New-Object System.Drawing.Point(10, 180)
$separatorPanel.Size = New-Object System.Drawing.Size(560, 2)
$separatorPanel.BackColor = [System.Drawing.Color]::Gray
$form.Controls.Add($separatorPanel)

# ======================================
# Section: Empty Files Deletion
# ======================================

$labelEmptyFilesSection = New-Object System.Windows.Forms.Label
$labelEmptyFilesSection.Location = New-Object System.Drawing.Point(10, 200)
$labelEmptyFilesSection.Size = New-Object System.Drawing.Size(400, 20)
$labelEmptyFilesSection.Font = New-Object System.Drawing.Font('Microsoft Sans Serif', 10, [System.Drawing.FontStyle]::Bold)
$labelEmptyFilesSection.Text = 'Find and Delete Empty Files'
$form.Controls.Add($labelEmptyFilesSection)

$buttonSelectEmptyFilesFolder = New-Object System.Windows.Forms.Button
$buttonSelectEmptyFilesFolder.Text = 'Select Folder'
$buttonSelectEmptyFilesFolder.Location = New-Object System.Drawing.Point(10, 230)
$buttonSelectEmptyFilesFolder.Size = New-Object System.Drawing.Size(100, 30)
$buttonSelectEmptyFilesFolder.Add_Click({
        $global:selectedFolderPath = Select-Directory
        if ($global:selectedFolderPath) {
            $labelSelectedFolder.Text = "Selected folder: $global:selectedFolderPath"
            Find-EmptyFiles $global:selectedFolderPath
        }
    })
$form.Controls.Add($buttonSelectEmptyFilesFolder)

$buttonDeleteFiles = New-Object System.Windows.Forms.Button
$buttonDeleteFiles.Text = 'Delete Files'
$buttonDeleteFiles.Location = New-Object System.Drawing.Point(120, 230)
$buttonDeleteFiles.Size = New-Object System.Drawing.Size(100, 30)
$buttonDeleteFiles.Add_Click({
        if (-not $global:selectedFolderPath) {
            Show-ErrorMessage "Please select a folder first!"
            return
        }
        $foundFiles = Get-ChildItem -Path $global:selectedFolderPath -Recurse -File | Where-Object { $_.Length -eq 0 }
        if ($foundFiles.Count -eq 0) {
            Show-InfoMessage "No empty files found to delete."
            Log-Message "No empty files found for deletion in folder $global:selectedFolderPath"
            return
        }
        foreach ($file in $foundFiles) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
                Log-Message "Deleted empty file: $($file.FullName)"
            } catch {
                Log-Message "Failed to delete empty file: $($file.FullName)" -MessageType "ERROR"
            }
        }
        Show-InfoMessage "$($foundFiles.Count) empty file(s) deleted successfully!"
        Log-Message "Deleted $($foundFiles.Count) empty files in $global:selectedFolderPath"
        Find-EmptyFiles $global:selectedFolderPath # Refresh the list after deletion
    })
$form.Controls.Add($buttonDeleteFiles)

$buttonOpenFolder = New-Object System.Windows.Forms.Button
$buttonOpenFolder.Text = 'Open Folder'
$buttonOpenFolder.Location = New-Object System.Drawing.Point(230, 230)
$buttonOpenFolder.Size = New-Object System.Drawing.Size(100, 30)
$buttonOpenFolder.Add_Click({
        if ($global:selectedFolderPath) {
            Start-Process explorer.exe -ArgumentList $global:selectedFolderPath
        } else {
            Show-ErrorMessage "Please select a folder first!"
        }
    })
$form.Controls.Add($buttonOpenFolder)

# Progress Bar for Empty File Detection
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 320)
$progressBar.Size = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($progressBar)

function Find-EmptyFiles {
    param ($folderPath)
    if (-not $folderPath) {
        Show-ErrorMessage "Please select a folder first!"
        return
    }
    $listBox.Items.Clear()
    $files = Get-ChildItem -Path $folderPath -Recurse -File | Where-Object { $_.Length -eq 0 }
    $progressBar.Maximum = $files.Count
    $progressBar.Value = 0
    $foundFiles = @()
    foreach ($file in $files) {
        $foundFiles += $file.FullName
        $progressBar.PerformStep()
    }
    $listBox.Items.AddRange($foundFiles)
    Show-InfoMessage "$($foundFiles.Count) empty file(s) found."
    Log-Message "Found $($foundFiles.Count) empty files in folder $folderPath"
}

$form.ShowDialog()

# End of script
