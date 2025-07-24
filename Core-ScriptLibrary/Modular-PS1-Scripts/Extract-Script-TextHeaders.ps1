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

#region --- Hide Console (optional) ---
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

#region --- Assemblies ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
#endregion

#region --- Initialization & Logging ---

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { [Environment]::CurrentDirectory }
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "HeaderExtractor\Logs"
$LogPath = Join-Path -Path $LogDir -ChildPath "$ScriptName-$Timestamp.log"

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")] [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry
    Write-Host $entry
}

function Handle-Error {
    param ([string]$ErrorMessage)
    Log-Message -Message $ErrorMessage -Level "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", "OK", "Error") | Out-Null
}

Log-Message "=== Launching PowerShell Header Extractor ==="

#endregion

#region --- Header Extraction Logic ---

function Extract-FileHeader {
    param ([string]$FilePath)
    $HeaderLines = @()
    $inHeader = $false

    try {
        foreach ($line in Get-Content -Path $FilePath -ErrorAction Stop) {
            if ($line -match '<#') { $inHeader = $true }
            if ($inHeader) { $HeaderLines += $line }
            if ($line -match '#>') { break }
        }
    } catch {
        Handle-Error "Failed to read file: $FilePath. $_"
    }

    return $HeaderLines
}

function Start-HeaderExtraction {
    param ([string]$RootFolder)

    try {
        Log-Message "Starting header extraction from: $RootFolder"
        $MergedFile = Join-Path $RootFolder "Merged-PowerShellScripts-Headers.txt"
        Set-Content -Path $MergedFile -Value "### Merged Headers from Folder: $RootFolder ###`n"

        $PS1Files = Get-ChildItem -Path $RootFolder -Recurse -Filter "*.ps1" -File -ErrorAction Stop
        $total = $PS1Files.Count
        $index = 0

        foreach ($file in $PS1Files) {
            $index++
            Write-Progress -Activity "Extracting Headers" -Status $file.FullName -PercentComplete (($index / $total) * 100)

            Add-Content -Path $MergedFile -Value "`n### File: $($file.FullName) ###`n"
            $Header = Extract-FileHeader -FilePath $file.FullName

            if ($Header.Count -gt 0) {
                Add-Content -Path $MergedFile -Value ($Header -join "`n")
            } else {
                Add-Content -Path $MergedFile -Value "No header found in $($file.Name)`n"
            }
        }

        Log-Message "Extraction complete. Output saved to: $MergedFile"
        return $MergedFile
    } catch {
        Handle-Error "Extraction failed: $_"
    }
}

#endregion

#region --- GUI ---

function Show-GUI {
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "PowerShell Scripts Headers Extractor"
    $Form.Size = New-Object System.Drawing.Size(640, 180)
    $Form.StartPosition = "CenterScreen"
    $Form.MaximizeBox = $false
    $Form.FormBorderStyle = 'FixedDialog'

    # Label
    $Label = New-Object System.Windows.Forms.Label
    $Label.Text = "Select Root Folder:"
    $Label.Location = New-Object System.Drawing.Point(10, 20)
    $Label.AutoSize = $true
    $Form.Controls.Add($Label)

    # TextBox
    $TextBox = New-Object System.Windows.Forms.TextBox
    $TextBox.Size = New-Object System.Drawing.Size(390, 20)
    $TextBox.Location = New-Object System.Drawing.Point(130, 18)
    $TextBox.Text = (Get-Location).Path
    $Form.Controls.Add($TextBox)

    # Browse Button
    $Browse = New-Object System.Windows.Forms.Button
    $Browse.Text = "Browse"
    $Browse.Size = New-Object System.Drawing.Size(75, 23)
    $Browse.Location = New-Object System.Drawing.Point(530, 16)
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
                Handle-Error "Invalid folder path: $Path"
                return
            }

            $Merged = Start-HeaderExtraction -RootFolder $Path
            if ($Merged) {
                [System.Windows.Forms.MessageBox]::Show("Headers saved to:`n$Merged", "Success", "OK", "Information") | Out-Null
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

    [void]$Form.ShowDialog()
}
#endregion

# Start UI
Show-GUI

# End of script
