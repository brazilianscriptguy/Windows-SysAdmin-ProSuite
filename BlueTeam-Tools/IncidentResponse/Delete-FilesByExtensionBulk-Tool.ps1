<#
.SYNOPSIS
    PowerShell Script for Bulk Deleting Files Based on Extension.  

.DESCRIPTION
    This script performs a bulk deletion of files based on specified extensions, helping 
    to remove unwanted or potentially harmful files during post-incident cleanup or 
    routine maintenance. It offers a fast and efficient way to target specific file 
    types across multiple directories.

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

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
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

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message"
}

# Function to select a directory using FolderBrowserDialog with UNC path
function Select-Directory {
    Log-Message "Prompting user to select a directory."
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Folders|*.none"
    $openFileDialog.CheckFileExists = $false
    $openFileDialog.CheckPathExists = $true
    $openFileDialog.Title = "Select the directory to search and delete files"
    $openFileDialog.FileName = "Select Folder Here"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $directoryPath = [System.IO.Path]::GetDirectoryName($openFileDialog.FileName)
        Log-Message "Directory selected: $directoryPath"
        return $directoryPath
    } else {
        Log-Message "Directory selection cancelled by user."
        return $null
    }
}

# Function to select a .txt file using OpenFileDialog
function Select-ExtensionFile {
    Log-Message "Prompting user to select an extension file."
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Text files (*.txt)|*.txt"
    $openFileDialog.Title = "Select the file containing extensions to delete"
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Log-Message "Extension file selected: $($openFileDialog.FileName)"
        return $openFileDialog.FileName
    } else {
        Log-Message "Extension file selection cancelled by user."
        return $null
    }
}

# Function to read file extensions from a text file and return them as an array
function Get-FileExtensions($extensionFilePath) {
    try {
        $extensions = Get-Content -Path $extensionFilePath
        $extensionsArray = $extensions -split '\s+|\,|\;' | Where-Object { $_ -ne '' }
        Log-Message "Extensions loaded: $($extensionsArray -join ', ')"
        return $extensionsArray
    } catch {
        Log-Message "Failed to read extensions from file: $_"
        return $null
    }
}

# Function to delete files based on selected extensions and directory
function Delete-Files($directory, $extensions) {
    $totalFiles = 0
    $progressIncrement = 1

    # Calculate total files for progress bar
    foreach ($extension in $extensions) {
        $filesToDelete = Get-ChildItem -Path $directory -Filter "*.$extension" -File -Recurse -ErrorAction SilentlyContinue
        $totalFiles += $filesToDelete.Count
    }

    # Set progress bar increment value
    if ($totalFiles -gt 0) {
        $progressIncrement = [Math]::Ceiling(100 / $totalFiles)
    }

    $progressBar.Value = 0
    foreach ($extension in $extensions) {
        Log-Message "Starting deletion for extension: $extension"
        $filesToDelete = Get-ChildItem -Path $directory -Filter "*.$extension" -File -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $filesToDelete) {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Log-Message "Deleted file: $($file.FullName)"
                $progressBar.Value = [Math]::Min($progressBar.Value + $progressIncrement, 100)
            } catch {
                Log-Message "Failed to delete file: $($file.FullName) - Error: $_"
            }
        }
    }

    $progressBar.Value = 100
}

# Main GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'File Deletion Tool'
$form.Size = New-Object System.Drawing.Size(400, 300)
$form.StartPosition = 'CenterScreen'

# Add GUI components
$labelSelectedDir = New-Object System.Windows.Forms.Label
$labelSelectedDir.Location = New-Object System.Drawing.Point(50, 20)
$labelSelectedDir.Size = New-Object System.Drawing.Size(300, 20)
$labelSelectedDir.Text = "Selected Directory: Not Selected"
$form.Controls.Add($labelSelectedDir)

$buttonSelectDir = New-Object System.Windows.Forms.Button
$buttonSelectDir.Location = New-Object System.Drawing.Point(50, 45)
$buttonSelectDir.Size = New-Object System.Drawing.Size(300, 30)
$buttonSelectDir.Text = '1. Select Directory'
$buttonSelectDir.Add_Click({
        $global:directory = Select-Directory
        if ($global:directory) {
            $labelSelectedDir.Text = "Selected Directory: $global:directory"
        } else {
            $labelSelectedDir.Text = "Selected Directory: Not Selected"
        }
    })
$form.Controls.Add($buttonSelectDir)

$labelSelectedExt = New-Object System.Windows.Forms.Label
$labelSelectedExt.Location = New-Object System.Drawing.Point(50, 85)
$labelSelectedExt.Size = New-Object System.Drawing.Size(300, 20)
$labelSelectedExt.Text = "Selected Extension File: Not Selected"
$form.Controls.Add($labelSelectedExt)

$buttonSelectExt = New-Object System.Windows.Forms.Button
$buttonSelectExt.Location = New-Object System.Drawing.Point(50, 110)
$buttonSelectExt.Size = New-Object System.Drawing.Size(300, 30)
$buttonSelectExt.Text = '2. Select Extension File'
$buttonSelectExt.Add_Click({
        $global:extensionFile = Select-ExtensionFile
        if ($global:extensionFile) {
            $labelSelectedExt.Text = "Selected Extension File: $global:extensionFile"
        } else {
            $labelSelectedExt.Text = "Selected Extension File: Not Selected"
        }
    })
$form.Controls.Add($buttonSelectExt)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(50, 150)
$progressBar.Size = New-Object System.Drawing.Size(300, 20)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$buttonDeleteFiles = New-Object System.Windows.Forms.Button
$buttonDeleteFiles.Location = New-Object System.Drawing.Point(50, 180)
$buttonDeleteFiles.Size = New-Object System.Drawing.Size(300, 30)
$buttonDeleteFiles.Text = '3. Delete Files'
$buttonDeleteFiles.Add_Click({
        if ($global:directory -and $global:extensionFile) {
            $extensions = Get-FileExtensions $global:extensionFile
            if ($extensions) {
                $progressBar.Value = 0
                Delete-Files $global:directory $extensions
                Show-InfoMessage "Files deleted successfully"
            } else {
                Show-ErrorMessage "Failed to load extensions."
            }
        } else {
            Show-ErrorMessage "Please select a directory and an extension file"
        }
    })
$form.Controls.Add($buttonDeleteFiles)

# Show the form
$form.ShowDialog() | Out-Null

# End of script execution log
Log-Message "Script execution completed."

# End of script
