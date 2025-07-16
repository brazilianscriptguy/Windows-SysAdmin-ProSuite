<#
.SYNOPSIS
    PowerShell Script for Extracting Headers from .ps1 Files into a Single Merged File

.DESCRIPTION
    Recursively scans the selected root folder for `.ps1` files,
    extracts the initial comment-based help (header) from each script,
    and writes them to a single consolidated `.txt` file.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Version 2.0 - July 16, 2025
#>

param (
    [switch]$ShowConsole = $false
)

#region --- Console Visibility ---
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
            ShowWindow(handle, 0);
        }
    }
"@
    [Window]::Hide()
}
#endregion

#region --- Assembly References ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
#endregion

#region --- Logging & Initialization ---
function Initialize-ScriptPaths {
    param (
        [string]$DefaultLogDir = 'C:\Logs-TEMP'
    )
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logPath = Join-Path $logDir "${scriptName}_${timestamp}.log"

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        ScriptName = $scriptName
    }
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        if (-not (Test-Path $global:LogDir)) {
            New-Item -Path $global:LogDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $global:LogPath -Value $logEntry
    } catch {
        Write-Warning "Log write failed: $logEntry"
    }

    Write-Host $logEntry
}

function Handle-Error {
    param ([string]$ErrorMessage)

    Log-Message -Message $ErrorMessage -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage,
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
#endregion

#region --- Header Extraction Logic ---
function Extract-FileHeader {
    param ([string]$FilePath)

    $Header = @()
    $Collecting = $false

    try {
        foreach ($line in Get-Content -Path $FilePath -ErrorAction Stop) {
            if ($line -match '<#') { $Collecting = $true }
            if ($Collecting) { $Header += $line }
            if ($line -match '#>') { break }
        }
    } catch {
        Handle-Error "Failed to read file: $FilePath. $_"
    }

    return $Header
}

function Start-HeaderExtraction {
    param ([string]$RootFolder)

    try {
        Log-Message -Message "Header extraction started in: $RootFolder"

        $MergedFile = Join-Path $RootFolder "Merged-Headers.txt"
        Set-Content -Path $MergedFile -Value "### Merged Headers from Folder: $RootFolder ###`n"

        $PS1Files = Get-ChildItem -Path $RootFolder -Recurse -Filter *.ps1 -File -ErrorAction Stop
        $Total = $PS1Files.Count
        $Index = 0

        foreach ($File in $PS1Files) {
            $Index++
            Write-Progress -Activity "Extracting Headers" -Status $File.FullName -PercentComplete (($Index / $Total) * 100)

            Add-Content -Path $MergedFile -Value "### File: $($File.FullName) ###`n"

            $Header = Extract-FileHeader -FilePath $File.FullName
            if ($Header.Count -gt 0) {
                Add-Content -Path $MergedFile -Value ($Header -join "`n")
            } else {
                Add-Content -Path $MergedFile -Value "No header found in: $($File.Name)`n"
            }

            Add-Content -Path $MergedFile -Value "`n"
        }

        Log-Message -Message "Header extraction complete. Output: $MergedFile"
        return $MergedFile
    } catch {
        Handle-Error "Extraction failed: $_"
    }
}
#endregion

#region --- GUI Logic ---
function Show-GUI {
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "PowerShell Header Extractor"
    $Form.Size = New-Object System.Drawing.Size(560, 320)
    $Form.StartPosition = "CenterScreen"

    # Folder Label
    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = "Select Root Folder:"
    $Label.Location = New-Object System.Drawing.Point(10, 20)
    $Label.AutoSize = $true
    $Form.Controls.Add($Label)

    # TextBox
    $TextBox = New-Object System.Windows.Forms.TextBox
    $TextBox.Size = New-Object System.Drawing.Size(350, 20)
    $TextBox.Location = New-Object System.Drawing.Point(130, 20)
    $TextBox.Text = (Get-Location).Path
    $Form.Controls.Add($TextBox)

    # Browse Button
    $Browse = New-Object System.Windows.Forms.Button
    $Browse.Text = "Browse"
    $Browse.Size = New-Object System.Drawing.Size(75, 23)
    $Browse.Location = New-Object System.Drawing.Point(490, 18)
    $Browse.Add_Click({
        $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($Dialog.ShowDialog() -eq "OK") {
            $TextBox.Text = $Dialog.SelectedPath
        }
    })
    $Form.Controls.Add($Browse)

    # Run Button
    $Run = New-Object System.Windows.Forms.Button
    $Run.Text = "Run"
    $Run.Size = New-Object System.Drawing.Size(100, 30)
    $Run.Location = New-Object System.Drawing.Point(130, 70)
    $Run.Add_Click({
        $Path = $TextBox.Text.Trim()
        if (-not (Test-Path $Path)) {
            Handle-Error "Invalid folder path."
            return
        }

        $MergedFile = Start-HeaderExtraction -RootFolder $Path
        if ($MergedFile) {
            [System.Windows.Forms.MessageBox]::Show(
                "Extraction completed. Merged file:`n$MergedFile",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })
    $Form.Controls.Add($Run)

    # Exit Button
    $Exit = New-Object System.Windows.Forms.Button
    $Exit.Text = "Exit"
    $Exit.Size = New-Object System.Drawing.Size(100, 30)
    $Exit.Location = New-Object System.Drawing.Point(250, 70)
    $Exit.Add_Click({ $Form.Close() })
    $Form.Controls.Add($Exit)

    $Form.ShowDialog()
}
#endregion

# Global Path Init
$global:Paths = Initialize-ScriptPaths
$global:LogDir = $Paths.LogDir
$global:LogPath = $Paths.LogPath

# Run GUI
Show-GUI
