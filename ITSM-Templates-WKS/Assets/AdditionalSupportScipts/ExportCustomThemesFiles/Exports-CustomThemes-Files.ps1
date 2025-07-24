<#
.SYNOPSIS
    PowerShell GUI to Export Windows Theme Customization Files.

.DESCRIPTION
    - Exports: LayoutModification.xml, current .msstyles, and TranscodedWallpaper
    - Output saved to ITSM-Logs-WKS\Exported-Themes
    - ANSI encoded .log is created
    - Includes friendly GUI, progress feedback, and error handling

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.3.0 - June 19, 2025
#>

# Hide PowerShell console window
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

# Load .NET GUI libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Setup paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\ITSM-Logs-WKS"
$outputFolder = Join-Path $logDir "Exported-Themes"
$logPath = Join-Path $logDir "$scriptName.log"

# Create directories if needed
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $outputFolder)) { New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null }

# Write to log
function Write-Log {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "[$timestamp] $Message" -Encoding Default
}

# Show error dialog and log
function Show-Error {
    param([string]$msg)
    Write-Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
}

# Export files
function Export-ThemeFiles {
    $exportButton.Enabled = $false
    $statusLabel.Text = "Exporting, please wait..."
    $form.UseWaitCursor = $true
    $form.Refresh()

    Write-Log "Export started."

    try {
        $layoutPath = Join-Path $outputFolder "LayoutModification.xml"
        Export-StartLayout -Path $layoutPath
        Write-Log "LayoutModification.xml exported to $layoutPath"
    } catch {
        Show-Error "Failed to export LayoutModification.xml: $_"
    }

    try {
        $msstylesPath = Join-Path $outputFolder "CurrentTheme.msstyles"
        $srcMsStyles = "$env:SystemRoot\Resources\Themes\aero\aero.msstyles"
        Copy-Item -Path $srcMsStyles -Destination $msstylesPath -Force
        Write-Log ".msstyles exported to $msstylesPath"
    } catch {
        Show-Error "Failed to export .msstyles: $_"
    }

    try {
        $wallpaperSource = "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper"
        $wallpaperDest = Join-Path $outputFolder "CurrentTheme.deskthemepack"
        Copy-Item -Path $wallpaperSource -Destination $wallpaperDest -Force
        Write-Log "Wallpaper exported to $wallpaperDest"
    } catch {
        Show-Error "Failed to export TranscodedWallpaper: $_"
    }

    [System.Windows.Forms.MessageBox]::Show(
        "Theme files exported to:`n$outputFolder",
        "Export Complete",
        'OK',
        'Information'
    )

    $statusLabel.Text = "Export completed successfully."
    $form.UseWaitCursor = $false
    $exportButton.Enabled = $true
    Write-Log "Export completed successfully."
}

# GUI setup
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Export Windows Theme Customization Files'
$form.Size = New-Object System.Drawing.Size(500, 230)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$labelFiles = New-Object System.Windows.Forms.Label
$labelFiles.Text = "Files to be exported:"
$labelFiles.Location = New-Object System.Drawing.Point(30, 20)
$labelFiles.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($labelFiles)

$listBoxFiles = New-Object System.Windows.Forms.ListBox
$listBoxFiles.Location = New-Object System.Drawing.Point(30, 45)
$listBoxFiles.Size = New-Object System.Drawing.Size(420, 60)
$listBoxFiles.Items.Add("1. LayoutModification.xml")
$listBoxFiles.Items.Add("2. CurrentTheme.msstyles")
$listBoxFiles.Items.Add("3. CurrentTheme.deskthemepack")
$form.Controls.Add($listBoxFiles)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = 'Export Files'
$exportButton.Location = New-Object System.Drawing.Point(180, 120)
$exportButton.Size = New-Object System.Drawing.Size(140, 40)
$exportButton.Add_Click({ Export-ThemeFiles })
$form.Controls.Add($exportButton)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(30, 175)
$statusLabel.Size = New-Object System.Drawing.Size(420, 20)
$form.Controls.Add($statusLabel)

$form.ShowDialog() | Out-Null

Write-Log "Session ended."

# End of script
