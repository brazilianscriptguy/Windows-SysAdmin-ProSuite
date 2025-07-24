<#
.SYNOPSIS
    PowerShell Script for Organizing SSL/TLS Certificates in the Repository.

.DESCRIPTION
    This script organizes SSL/TLS certificates within the repository by issuer, improving 
    the management of certificates and ensuring compliance with security standards. It 
    helps to maintain a clean and structured certificate repository.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Hide PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
}
"@
[Window]::Hide()

# Library Imports
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
        $logBox.Items.Add($logEntry)
        $logBox.TopIndex = $logBox.Items.Count - 1
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

function Remove-EmptyDirectories {
    param ([string]$DirectoryPath)
    $directories = Get-ChildItem -Path $DirectoryPath -Directory -Recurse | Where-Object { $_.GetFileSystemInfos().Count -eq 0 }
    foreach ($dir in $directories) {
        Remove-Item -Path $dir.FullName -Force
        Write-Log "Removed empty folder: $($dir.FullName)"
    }
}

function Select-Directory {
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select a Folder"
    if ($folderBrowser.ShowDialog() -eq "OK") {
        $directoryPath = $folderBrowser.SelectedPath
        Write-Log "Directory selected: $directoryPath"
        return $directoryPath
    } else {
        Write-Log "Directory selection cancelled by user."
        return $null
    }
}

function ExtractCommonName {
    param ([string]$issuerName)
    $pattern = 'CN\s*=\s*([^,]+)'
    $match = [regex]::Match($issuerName, $pattern)
    if ($match.Success) {
        return $match.Groups[1].Value
    } else {
        return "Unknown"  # Fallback if no common name is found
    }
}

# Variable Definitions and Configuration
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir."
        return
    }
}

# GUI Creation
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Certificate Organizer'
$form.Size = New-Object System.Drawing.Size(700, 400)
$form.StartPosition = 'CenterScreen'

# Source Directory UI Components
$sourceLabel = New-Object System.Windows.Forms.Label
$sourceLabel.Location = New-Object System.Drawing.Point(10, 20)
$sourceLabel.Size = New-Object System.Drawing.Size(180, 20)
$sourceLabel.Text = 'Source Directory:'
$form.Controls.Add($sourceLabel)

$sourceTextBox = New-Object System.Windows.Forms.TextBox
$sourceTextBox.Location = New-Object System.Drawing.Point(200, 20)
$sourceTextBox.Size = New-Object System.Drawing.Size(380, 20)
$form.Controls.Add($sourceTextBox)

$sourceBrowseButton = New-Object System.Windows.Forms.Button
$sourceBrowseButton.Location = New-Object System.Drawing.Point(590, 20)
$sourceBrowseButton.Size = New-Object System.Drawing.Size(80, 20)
$sourceBrowseButton.Text = 'Browse'
$form.Controls.Add($sourceBrowseButton)
$sourceBrowseButton.Add_Click({
        $selectedPath = Select-Directory
        if ($selectedPath -ne $null) {
            $sourceTextBox.Text = $selectedPath
        }
    })

# Target Directory UI Components
$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Location = New-Object System.Drawing.Point(10, 50)
$targetLabel.Size = New-Object System.Drawing.Size(180, 20)
$targetLabel.Text = 'Target Directory:'
$form.Controls.Add($targetLabel)

$targetTextBox = New-Object System.Windows.Forms.TextBox
$targetTextBox.Location = New-Object System.Drawing.Point(200, 50)
$targetTextBox.Size = New-Object System.Drawing.Size(380, 20)
$form.Controls.Add($targetTextBox)

$targetBrowseButton = New-Object System.Windows.Forms.Button
$targetBrowseButton.Location = New-Object System.Drawing.Point(590, 50)
$targetBrowseButton.Size = New-Object System.Drawing.Size(80, 20)
$targetBrowseButton.Text = 'Browse'
$form.Controls.Add($targetBrowseButton)
$targetBrowseButton.Add_Click({
        $selectedPath = Select-Directory
        if ($selectedPath -ne $null) {
            $targetTextBox.Text = $selectedPath
        }
    })

# Start Button and Log Box
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point(10, 80)
$button.Size = New-Object System.Drawing.Size(100, 23)
$button.Text = 'Start'
$form.Controls.Add($button)

$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location = New-Object System.Drawing.Point(10, 110)
$logBox.Size = New-Object System.Drawing.Size(660, 230)
$logBox.ScrollAlwaysVisible = $true
$form.Controls.Add($logBox)

# Start button click event
$button.Add_Click({
        $logPath = Join-Path $targetTextBox.Text "process-events_$(Get-Date -Format 'yyyyMMddHHmmss').log"
        Write-Log "Process started."
    
        if ([string]::IsNullOrWhiteSpace($sourceTextBox.Text) -or [string]::IsNullOrWhiteSpace($targetTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in all required fields.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Write-Log "Missing required fields."
            return
        }

        if (-not (Test-Path $sourceTextBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Source directory does not exist", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Write-Log "Source directory does not exist."
            return
        }

        if (-not (Test-Path $targetTextBox.Text)) {
            New-Item -Path $targetTextBox.Text -ItemType Directory | Out-Null
            Write-Log "Created target directory."
        }

        $extensions = '*.cer', '*.crl', '*.crt', '*.der', '*.pem', '*.pfx', '*.p12', '*.p7b'
        $certFiles = Get-ChildItem -Path $sourceTextBox.Text -Include $extensions -Recurse -ErrorAction SilentlyContinue
        $processedFiles = 0

        foreach ($file in $certFiles) {
            try {
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $file.FullName
                $commonName = ExtractCommonName -issuerName $cert.Issuer
                $commonNameFolder = $commonName -replace '[\\\/:*?"<>|]', ''  # Clean folder name of invalid characters
                $commonNameFolderPath = Join-Path $targetTextBox.Text $commonNameFolder

                if (-not (Test-Path $commonNameFolderPath)) {
                    New-Item -Path $commonNameFolderPath -ItemType Directory | Out-Null
                    Write-Log "Created folder for common name: $commonName"
                }

                $targetFilePath = Join-Path $commonNameFolderPath $file.Name
                Move-Item -Path $file.FullName -Destination $targetFilePath -Force
                Write-Log "Moved $file to $commonNameFolderPath"
                $processedFiles++
            } catch {
                Write-Log "Error processing file $($file.FullName): $_"
            }
        }

        Remove-EmptyDirectories -DirectoryPath $sourceTextBox.Text

        Write-Log "Processed $processedFiles files."
        [System.Windows.Forms.MessageBox]::Show("Certificates have been organized by common name. Processed $processedFiles files.", "Process Completed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Write-Log "All operations completed."
    })

$form.ShowDialog()

# End of script
