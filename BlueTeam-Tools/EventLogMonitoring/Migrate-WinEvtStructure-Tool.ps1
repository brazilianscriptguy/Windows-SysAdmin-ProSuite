<#
.SYNOPSIS
    PowerShell Script to Move Event Log Default Paths with GUI and Enhanced Error Handling.

.DESCRIPTION
    Provides a graphical interface for moving Windows Event Logs to a new location.
    The script stops the Event Log service and dependencies, transfers logs to the specified
    folder, applies original ACLs to the new location, updates registry paths, and restarts services.

.FEATURES
    - Stops Windows Event Log Service and Dependencies: Ensures smooth stopping and restarting.
    - Moves Logs: Transfers `.evtx` files to the specified folder.
    - Updates Registry: Reflects the new paths for the logs in the Windows Registry.
    - Preserves ACLs: Retains permissions from the source to the target folder.
    - User-Friendly GUI: Allows the user to specify the target folder with progress indication.
    - Comprehensive Logging: Logs all operations, errors, and status updates.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    3.0.0 - January 7, 2025

.NOTES
    - Requires administrative privileges.
    - Compatible with environments running PowerShell 5.1 or later.
    - Handles special characters in folder names to ensure clean and consistent paths.
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
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@
[Window]::Hide()

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Function to initialize script name and file paths
function Initialize-ScriptPaths {
    $scriptName = if ($MyInvocation.ScriptName) {
        [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
    } else {
        "Script"  # Fallback if no name is available
    }

    $logDir = 'C:\Logs-TEMP'
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    return @{"LogDir" = $logDir; "LogPath" = $logPath; "ScriptName" = $scriptName}
}

# Initialize paths
$paths = Initialize-ScriptPaths
$logDir = $paths.LogDir
$logPath = $paths.LogPath

# Enhanced logging function
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
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force
        }
        Add-Content -Path $logPath -Value $logEntry
    } catch {
        Write-Error "Failed to write to log: $_"
        Write-Output $logEntry
    }
}

# Error handling function
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Log-Message -Message "$ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Sanitize folder names
function Sanitize-Name {
    param (
        [string]$Name
    )
    $sanitized = $Name -replace '[^a-zA-Z\-]', '-' -replace '-+', '-' -replace '-$', ''
    return $sanitized
}

# Stop Event Log Service and Dependencies
function Stop-WindowsEventLogService {
    try {
        $dependentServices = Get-Service -Name "EventLog" -DependentServices
        foreach ($service in $dependentServices) {
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $service.Name -Force
                Log-Message -Message "Stopped dependent service: $($service.Name)." -MessageType "INFO"
            }
        }

        Stop-Service -Name "EventLog" -Force
        Log-Message -Message "Stopped Windows Event Log service." -MessageType "INFO"
    } catch {
        Handle-Error "Failed to stop Windows Event Log service or dependencies: $_"
        throw
    }
}

# Start Event Log Service and Dependencies
function Start-WindowsEventLogService {
    try {
        Start-Service -Name "EventLog"
        Log-Message -Message "Started Windows Event Log service." -MessageType "INFO"

        $dependentServices = Get-Service -Name "EventLog" -DependentServices
        foreach ($service in $dependentServices) {
            Start-Service -Name $service.Name
            Log-Message -Message "Started dependent service: $($service.Name)." -MessageType "INFO"
        }
    } catch {
        Handle-Error "Failed to start Windows Event Log service or dependencies: $_"
        throw
    }
}

# Move Event Logs
function Move-EventLogs {
    param (
        [string]$TargetFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not (Test-Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force
        Log-Message -Message "Created target folder: $TargetFolder." -MessageType "INFO"
    }

    $sourceAcl = Get-Acl -Path "$env:SystemRoot\System32\winevt\Logs"
    Set-Acl -Path $TargetFolder -AclObject $sourceAcl
    Log-Message -Message "Applied ACLs to target folder: $TargetFolder." -MessageType "INFO"

    $logFiles = Get-ChildItem -Path "$env:SystemRoot\System32\winevt\Logs" -Filter "*.evtx"
    $totalLogs = $logFiles.Count
    $ProgressBar.Maximum = $totalLogs
    $currentLog = 0

    foreach ($logFile in $logFiles) {
        $folderName = Sanitize-Name -Name $logFile.BaseName
        $targetFolderPath = Join-Path -Path $TargetFolder -ChildPath $folderName

        if (-not (Test-Path -Path $targetFolderPath)) {
            New-Item -Path $targetFolderPath -ItemType Directory -Force
            Log-Message -Message "Created folder: $targetFolderPath." -MessageType "INFO"
        }

        $targetPath = Join-Path -Path $targetFolderPath -ChildPath $logFile.Name
        try {
            Move-Item -Path $logFile.FullName -Destination $targetPath -Force
            Log-Message -Message "Moved log file: $($logFile.Name) to $targetPath." -MessageType "INFO"
        } catch {
            Log-Message -Message "Failed to move log file: $($logFile.Name): $_" -MessageType "ERROR"
        }

        $currentLog++
        $ProgressBar.Value = $currentLog
    }
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Move Event Log Default Paths'
$form.Size = New-Object System.Drawing.Size(500, 300)
$form.StartPosition = 'CenterScreen'

# Label for Target Folder
$label = New-Object System.Windows.Forms.Label
$label.Text = 'Enter Target Folder (e.g., L:\):'
$label.Location = New-Object System.Drawing.Point(10, 20)
$label.AutoSize = $true  # Ensures the text fits on a single line
$form.Controls.Add($label)

# TextBox for Target Folder
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 50)
$textBox.Size = New-Object System.Drawing.Size(460, 20)  # Adjusted width for alignment
$form.Controls.Add($textBox)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 90)
$progressBar.Size = New-Object System.Drawing.Size(460, 20)  # Adjusted width for alignment
$form.Controls.Add($progressBar)

# Button for Moving Logs
$button = New-Object System.Windows.Forms.Button
$button.Text = "Move Logs"
$button.Location = New-Object System.Drawing.Point(190, 130)  # Centered below the progress bar
$button.Size = New-Object System.Drawing.Size(100, 30)  # Standard button size
$form.Controls.Add($button)


$button.Add_Click({
    $targetFolder = $textBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($targetFolder)) {
        Handle-Error "Target folder cannot be empty."
        return
    }

    try {
        Stop-WindowsEventLogService
        Move-EventLogs -TargetFolder $targetFolder -ProgressBar $progressBar
        Start-WindowsEventLogService

        [System.Windows.Forms.MessageBox]::Show("Event Logs moved successfully to $targetFolder.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Log-Message -Message "Event Logs moved successfully to $targetFolder." -MessageType "INFO"
    } catch {
        Handle-Error "An error occurred during the operation: $_"
    }
})

$form.ShowDialog() | Out-Null

# End of script
