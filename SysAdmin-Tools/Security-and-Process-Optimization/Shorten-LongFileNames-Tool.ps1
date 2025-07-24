<#
.SYNOPSIS
    PowerShell Script for Automatically Shortening Long File Names.

.DESCRIPTION
    This script shortens file names that exceed a specified length, preventing file 
    system errors and ensuring compliance with file naming standards in the organization.

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

# Logging function with error handling
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

# Function to select a directory using OpenFileDialog for UNC paths
function Select-Directory {
    Log-Message "Prompting user to select a directory."
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Folders|*.none"
    $openFileDialog.CheckFileExists = $false
    $openFileDialog.CheckPathExists = $true
    $openFileDialog.Title = "Select the directory to search for long file names"
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

# Function to get user input via an input dialog
function Get-UserInput {
    param ([string]$message, [string]$defaultText)
    $inputForm = New-Object System.Windows.Forms.Form
    $inputForm.StartPosition = 'CenterScreen'
    $inputForm.Size = New-Object System.Drawing.Size(300, 150)
    $inputForm.Topmost = $true
    $inputForm.Text = "Input Required"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $message
    $label.Location = New-Object System.Drawing.Point(10, 10)
    $label.Size = New-Object System.Drawing.Size(280, 20)
    $inputForm.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 40)
    $textBox.Size = New-Object System.Drawing.Size(260, 20)
    $textBox.Text = $defaultText
    $inputForm.Controls.Add($textBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(180, 70)
    $okButton.Size = New-Object System.Drawing.Size(75, 23)
    $okButton.Text = "OK"
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $inputForm.AcceptButton = $okButton
    $inputForm.Controls.Add($okButton)

    $inputForm.ShowDialog() | Out-Null

    return $textBox.Text
}

# Function to truncate and rename long file names
function Shorten-LongFileNames($directory, $maxLength) {
    Get-ChildItem -Path $directory -File -Recurse | ForEach-Object {
        if ($_.BaseName.Length -gt $maxLength) {
            $truncatedFolders = $_.Directory.FullName.Substring($directory.Length + 1).Split('\') | ForEach-Object { $_.Substring(0, [Math]::Min($_.Length, $maxLength)) }
            $newName = ($truncatedFolders -join '_') + '_' + $_.BaseName.Substring(0, $maxLength) + $_.Extension
            $newPath = Join-Path -Path $_.Directory.FullName -ChildPath $newName
            Rename-Item -Path $_.FullName -NewName $newPath
            Log-Message "Renamed `"$($_.FullName)`" to `"$newPath`""
        }
    }
}

# Main GUI Setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'File Name Shortening Tool'
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

$labelMaxLength = New-Object System.Windows.Forms.Label
$labelMaxLength.Location = New-Object System.Drawing.Point(50, 85)
$labelMaxLength.Size = New-Object System.Drawing.Size(300, 20)
$labelMaxLength.Text = "Maximum File Name Length: Not Set"
$form.Controls.Add($labelMaxLength)

$buttonSetMaxLength = New-Object System.Windows.Forms.Button
$buttonSetMaxLength.Location = New-Object System.Drawing.Point(50, 110)
$buttonSetMaxLength.Size = New-Object System.Drawing.Size(300, 30)
$buttonSetMaxLength.Text = '2. Set Maximum Length'
$buttonSetMaxLength.Add_Click({
        $global:maxLength = Get-UserInput -message "Please enter the maximum length for file names" -defaultText "25"
        if ($global:maxLength) {
            $labelMaxLength.Text = "Maximum File Name Length: $global:maxLength"
        } else {
            $labelMaxLength.Text = "Maximum File Name Length: Not Set"
        }
    })
$form.Controls.Add($buttonSetMaxLength)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(50, 150)
$progressBar.Size = New-Object System.Drawing.Size(300, 20)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$buttonShortenFiles = New-Object System.Windows.Forms.Button
$buttonShortenFiles.Location = New-Object System.Drawing.Point(50, 180)
$buttonShortenFiles.Size = New-Object System.Drawing.Size(300, 30)
$buttonShortenFiles.Text = '3. Shorten File Names'
$buttonShortenFiles.Add_Click({
        if ($global:directory -and $global:maxLength) {
            $progressBar.Value = 0
            Log-Message "Script start: Processing files in $global:directory with max length $global:maxLength"
            Shorten-LongFileNames $global:directory $global:maxLength
            Log-Message "Script completed. Log file at $logPath"
            Show-InfoMessage "Script execution completed. Please check the log for details:`nLog file: $logPath"
        } else {
            Show-ErrorMessage "Please select a directory and set the maximum length"
        }
    })
$form.Controls.Add($buttonShortenFiles)

# Show the form
$form.ShowDialog() | Out-Null

# End of script execution log
Log-Message "Script execution completed."

# End of script
