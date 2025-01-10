<#
.SYNOPSIS
    PowerShell Script for Extracting Headers from .ps1 Files into a Single Merged File.

.DESCRIPTION
    This script recursively searches the specified root folder and its subfolders for `.ps1` files,
    extracts their headers, and writes all headers into a single merged `.txt` file in the root folder.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 10, 2025
#>

param (
    [switch]$ShowConsole = $false
)

if (-not $ShowConsole) {
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
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Logging function
function Log-Message {
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
        if (-not (Test-Path $global:LogDir)) {
            New-Item -Path $global:LogDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $global:LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write log: $logEntry"
        Write-Host $logEntry
    }
}

# Error handling function
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    Log-Message -Message "$ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage, 
        "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# Initialize paths
function Initialize-ScriptPaths {
    param (
        [string]$DefaultLogDir = 'C:\Logs-TEMP'
    )
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        ScriptName = $scriptName
    }
}

# Initialize paths globally
$Paths = Initialize-ScriptPaths
$global:LogDir = $Paths.LogDir
$global:LogPath = $Paths.LogPath

# Extract headers from a .ps1 file
function Extract-FileHeader {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $Header = @()
    $CollectingHeader = $false

    try {
        foreach ($Line in Get-Content -Path $FilePath -ErrorAction Stop) {
            if ($Line -match "<#") { $CollectingHeader = $true }
            if ($CollectingHeader) { $Header += $Line }
            if ($Line -match "#>") { break }
        }
    } catch {
        Handle-Error "Error reading file: $FilePath. $_"
    }

    return $Header
}

# Perform header extraction into a single file
function Start-HeaderExtraction {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RootFolder
    )

    try {
        Log-Message -Message "Starting header extraction in: $RootFolder" -MessageType "INFO"
        $MergedFile = Join-Path -Path $RootFolder -ChildPath "Merged-Headers.txt"
        Set-Content -Path $MergedFile -Value "### Merged Headers for Root Folder: $RootFolder ###`n"

        $AllFolders = Get-ChildItem -Path $RootFolder -Directory -Recurse -ErrorAction Stop
        $TotalFiles = (Get-ChildItem -Path $RootFolder -Filter *.ps1 -Recurse -File).Count
        $ProcessedFiles = 0

        foreach ($Folder in $AllFolders) {
            Add-Content -Path $MergedFile -Value "### Folder: $($Folder.FullName) ###`n"

            foreach ($PS1File in Get-ChildItem -Path $Folder.FullName -Filter *.ps1 -File -ErrorAction SilentlyContinue) {
                $ProcessedFiles++
                Write-Progress -Activity "Extracting Headers" -Status "Processing $($PS1File.FullName)" -PercentComplete (($ProcessedFiles / $TotalFiles) * 100)

                Add-Content -Path $MergedFile -Value "### File: $($PS1File.Name) ###`n"

                $Header = Extract-FileHeader -FilePath $PS1File.FullName
                if ($Header.Count -gt 0) {
                    Add-Content -Path $MergedFile -Value ($Header -join "`n")
                } else {
                    Add-Content -Path $MergedFile -Value "No header found in $($PS1File.Name).`n"
                }
                Add-Content -Path $MergedFile -Value "`n"
            }
        }

        Log-Message -Message "Header extraction completed successfully. Merged file: $MergedFile" -MessageType "INFO"
        return $MergedFile
    } catch {
        Handle-Error "An error occurred during header extraction. $_"
    }
}

# GUI for folder selection and execution
function Show-GUI {
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "PowerShell Header Extractor"
    $Form.Size = New-Object System.Drawing.Size(560, 350)
    $Form.StartPosition = "CenterScreen"

    $ProgressBar = New-Object System.Windows.Forms.ProgressBar
    $ProgressBar.Size = New-Object System.Drawing.Size(500, 20)
    $ProgressBar.Location = New-Object System.Drawing.Point(20, 250)
    $Form.Controls.Add($ProgressBar)

    $FolderLabel = New-Object System.Windows.Forms.Label
    $FolderLabel.Text = "Root Folder:"
    $FolderLabel.Location = New-Object System.Drawing.Point(10, 20)
    $FolderLabel.AutoSize = $true
    $Form.Controls.Add($FolderLabel)

    $FolderTextbox = New-Object System.Windows.Forms.TextBox
    $FolderTextbox.Size = New-Object System.Drawing.Size(350, 20)
    $FolderTextbox.Location = New-Object System.Drawing.Point(100, 20)
    $FolderTextbox.Text = (Get-Location).Path
    $Form.Controls.Add($FolderTextbox)

    $BrowseFolderButton = New-Object System.Windows.Forms.Button
    $BrowseFolderButton.Text = "Browse"
    $BrowseFolderButton.Size = New-Object System.Drawing.Size(75, 30)
    $BrowseFolderButton.Location = New-Object System.Drawing.Point(460, 20)
    $BrowseFolderButton.Add_Click({
        $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($FolderBrowser.ShowDialog() -eq "OK") {
            $FolderTextbox.Text = $FolderBrowser.SelectedPath
        }
    })
    $Form.Controls.Add($BrowseFolderButton)

    $RunButton = New-Object System.Windows.Forms.Button
    $RunButton.Text = "Run"
    $RunButton.Size = New-Object System.Drawing.Size(100, 30)
    $RunButton.Location = New-Object System.Drawing.Point(120, 280)
    $RunButton.Add_Click({
        $RootFolder = $FolderTextbox.Text
        if (-not (Test-Path -Path $RootFolder)) {
            Handle-Error "Invalid root folder path."
            return
        }

        $MergedFile = Start-HeaderExtraction -RootFolder $RootFolder
        [System.Windows.Forms.MessageBox]::Show(
            "Header extraction completed successfully. Merged headers are stored in: $MergedFile", 
            "Success", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    })
    $Form.Controls.Add($RunButton)

    $ExitButton = New-Object System.Windows.Forms.Button
    $ExitButton.Text = "Exit"
    $ExitButton.Size = New-Object System.Drawing.Size(100, 30)
    $ExitButton.Location = New-Object System.Drawing.Point(240, 280)
    $ExitButton.Add_Click({ $Form.Close() })
    $Form.Controls.Add($ExitButton)

    $Form.ShowDialog()
}

# Show the GUI
Show-GUI

# End of script
