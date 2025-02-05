<#
.SYNOPSIS
    PowerShell Script to Move Event Log Default Paths and Update Registry.

.DESCRIPTION
    Provides a GUI for moving Windows Event Logs while preserving ACLs, updating registry paths, and restarting services.

.FEATURES
    - Moves `.evtx` files to a new location.
    - Fixes incorrect folder naming (`%4` → `-`).
    - Stops and restarts EventLog and dependent services.
    - Ensures ACLs are preserved on the new files and folders.
    - Provides comprehensive logging.
    - User-friendly GUI with clear folder input instructions.
    - Compatible with UTF-8 without BOM encoding.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    4.6.0 - February 5, 2025

.NOTES
    - Requires administrative privileges.
    - Compatible with PowerShell 5.1 or later.
    - Ensure the script is saved in UTF-8 **without BOM** for PowerShell ISE compatibility.
#>

# Hide Console Window
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

# Load UI Libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Initialize Logging with Requested Characteristics
function Initialize-ScriptPaths {
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
    $logDir = 'C:\Scripts-LOGS'
    $logFileName = "${scriptName}.log"
    $logPath = Join-Path $logDir $logFileName

    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    return @{ "LogDir" = $logDir; "LogPath" = $logPath }
}

$paths = Initialize-ScriptPaths
$logDir = $paths.LogDir
$logPath = $paths.LogPath

function Log-Message {
    param ([string]$Message, [string]$Type = "INFO")
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Type] $Message"
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
}

function Handle-Error {
    param ([string]$Message)
    Log-Message -Message $Message -Type "ERROR"
    [System.Windows.Forms.MessageBox]::Show($Message, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Stop-Start-Services {
    param ([string]$Action) # "Stop" or "Start"
    try {
        $eventLogService = Get-Service -Name "EventLog"
        $dependencies = Get-Service -Name "EventLog" -DependentServices | Where-Object { $_.Status -ne 'Stopped' }

        if ($Action -eq "Stop") {
            $dependencies | ForEach-Object { Stop-Service -Name $_.Name -Force -ErrorAction Stop }
            Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        } else {
            Start-Service -Name "EventLog" -ErrorAction Stop
            $dependencies | ForEach-Object { Start-Service -Name $_.Name -ErrorAction Stop }
        }
        Log-Message -Message "$Action Event Log service and dependencies."
    } catch {
        Handle-Error "Failed to $Action Event Log service: $_"
    }
}

function Move-EventLogs {
    param ([string]$TargetFolder, [System.Windows.Forms.ProgressBar]$ProgressBar)

    if (-not (Test-Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
        Log-Message -Message "Created Target Folder: $TargetFolder"
    }

    $originalACL = Get-Acl -Path "$env:SystemRoot\System32\winevt\Logs"

    $logFiles = Get-ChildItem -Path "$env:SystemRoot\System32\winevt\Logs" -Filter "*.evtx"

    if ($logFiles.Count -gt 0) {
        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = $logFiles.Count
        $ProgressBar.Value = 0
    } else {
        $ProgressBar.Minimum = 0
        $ProgressBar.Maximum = 1
        $ProgressBar.Value = 0
    }

    $i = 0

    foreach ($logFile in $logFiles) {
        $folderName = $logFile.BaseName -replace "%4", "-"
        $targetPath = Join-Path -Path $TargetFolder -ChildPath $folderName

        if (-not (Test-Path $targetPath)) {
            New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
            Log-Message -Message "Created folder: $targetPath."
            Set-Acl -Path $targetPath -AclObject $originalACL
        }

        $destinationFile = Join-Path -Path $targetPath -ChildPath $logFile.Name

        try {
            Move-Item -Path $logFile.FullName -Destination $destinationFile -Force
            Set-Acl -Path $destinationFile -AclObject $originalACL
            Log-Message -Message "Moved: $($logFile.Name) and applied ACLs."
        } catch {
            Handle-Error "Failed to move $($logFile.Name): $_"
        }

        $ProgressBar.Value = $i
        $i++
    }

    Set-Acl -Path $TargetFolder -AclObject $originalACL
    Log-Message -Message "Applied ACLs to the entire $TargetFolder directory."
}

function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Paths'
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = 'CenterScreen'

    # Label to indicate the target folder
    $labelTargetRootFolder = New-Object System.Windows.Forms.Label
    $labelTargetRootFolder.Text = 'Enter the target root folder (e.g., "L:\"):'
    $labelTargetRootFolder.Location = New-Object System.Drawing.Point(10, 20)
    $labelTargetRootFolder.Size = New-Object System.Drawing.Size(460, 20)
    $form.Controls.Add($labelTargetRootFolder)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 50)
    $textBox.Size = New-Object System.Drawing.Size(460, 20)
    $form.Controls.Add($textBox)

    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 90)
    $progressBar.Size = New-Object System.Drawing.Size(460, 20)
    $progressBar.Minimum = 0
    $progressBar.Maximum = 1
    $progressBar.Value = 0
    $form.Controls.Add($progressBar)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Move Logs"
    $button.Location = New-Object System.Drawing.Point(200, 130)
    $button.Add_Click({
        $targetFolder = $textBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetFolder)) {
            Handle-Error "Target folder cannot be empty."
            return
        }
        try {
            Stop-Start-Services -Action "Stop"
            Move-EventLogs -TargetFolder $targetFolder -ProgressBar $progressBar
            Stop-Start-Services -Action "Start"
            Log-Message -Message "Logs moved successfully to $targetFolder."
            [System.Windows.Forms.MessageBox]::Show("Logs moved successfully to $targetFolder.", "Success")
        } catch {
            Handle-Error "An error occurred: $_"
        }
    })
    $form.Controls.Add($button)

    $form.ShowDialog() | Out-Null
}

Setup-GUI

# End of script
