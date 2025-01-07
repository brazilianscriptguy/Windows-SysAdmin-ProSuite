<#
.SYNOPSIS
    PowerShell Script to Move Event Log Default Paths with GUI and Enhanced Error Handling.

.DESCRIPTION
    Provides a graphical interface for moving Windows Event Logs to a new location.
    The script stops the Event Log service and dependencies, transfers logs to the specified
    folder, applies original ACLs to the new location, and restarts services.

.FEATURES
    - Stops Windows Event Log Service and Dependencies: Ensures smooth stopping and restarting.
    - Moves Logs: Transfers `.evtx` files to the specified folder.
    - Preserves ACLs: Retains permissions from the source to the target folder.
    - User-Friendly GUI: Allows the user to specify the target folder with progress indication.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2.2.0 - January 7, 2025

.NOTES
    - Requires administrative privileges.
    - Designed for environments running PowerShell 5.1 or later.
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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global Variables
$defaultLogDir = 'C:\Logs-TEMP'
$logPath       = Join-Path -Path $defaultLogDir -ChildPath "EventLogsMigration.log"

# Initialize Logging
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$Level] $Message"
    Add-Content -Path $logPath -Value $entry
}

# Function: Stop Windows Event Log Service and Dependencies
function Stop-WindowsEventLogService {
    try {
        $dependentServices = Get-Service -Name "EventLog" -DependentServices
        foreach ($service in $dependentServices) {
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name $service.Name -Force -ErrorAction Stop
                Write-Log -Message "Stopped dependent service: $($service.Name)." -Level "INFO"
            }
        }

        Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        Write-Log -Message "Stopped Windows Event Log service." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to stop Windows Event Log service or dependencies: $_" -Level "ERROR"
        throw
    }
}

# Function: Start Windows Event Log Service and Dependencies
function Start-WindowsEventLogService {
    try {
        Start-Service -Name "EventLog" -ErrorAction Stop
        Write-Log -Message "Started Windows Event Log service." -Level "INFO"

        $dependentServices = Get-Service -Name "EventLog" -DependentServices
        foreach ($service in $dependentServices) {
            Start-Service -Name $service.Name -ErrorAction Stop
            Write-Log -Message "Started dependent service: $($service.Name)." -Level "INFO"
        }
    } catch {
        Write-Log -Message "Failed to start Windows Event Log service or dependencies: $_" -Level "ERROR"
        throw
    }
}

# Function: Move Event Logs
function Move-EventLogs {
    param(
        [string]$TargetFolder
    )

    # Create Target Folder
    if (-not (Test-Path -Path $TargetFolder)) {
        New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
        Write-Log -Message "Created target folder: $TargetFolder." -Level "INFO"
    }

    # Preserve ACLs
    $sourceAcl = Get-Acl -Path "$env:SystemRoot\System32\winevt\Logs"
    Set-Acl -Path $TargetFolder -AclObject $sourceAcl
    Write-Log -Message "Applied ACLs to target folder: $TargetFolder." -Level "INFO"

    # Move Each Event Log
    $logFiles = Get-ChildItem -Path "$env:SystemRoot\System32\winevt\Logs" -Filter "*.evtx"
    foreach ($logFile in $logFiles) {
        $targetPath = Join-Path -Path $TargetFolder -ChildPath $logFile.Name
        Move-Item -Path $logFile.FullName -Destination $targetPath -Force
        Write-Log -Message "Moved log file: $($logFile.Name) to $targetPath." -Level "INFO"
    }
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Move Event Log Default Paths'
$form.Size = New-Object System.Drawing.Size(500, 300)
$form.StartPosition = 'CenterScreen'

$label = New-Object System.Windows.Forms.Label
$label.Text = 'Enter Target Folder (e.g., L:\Logs):'
$label.Location = New-Object System.Drawing.Point(10, 20)
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 50)
$textBox.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($textBox)

$button = New-Object System.Windows.Forms.Button
$button.Text = "Move Logs"
$button.Location = New-Object System.Drawing.Point(10, 90)
$form.Controls.Add($button)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 120)
$progressBar.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($progressBar)

$button.Add_Click({
    $targetFolder = $textBox.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($targetFolder)) {
        [System.Windows.Forms.MessageBox]::Show("Target folder cannot be empty.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Write-Log -Message "Error: Target folder is empty." -Level "ERROR"
        return
    }

    try {
        # Stop Services
        Stop-WindowsEventLogService

        # Move Logs
        Move-EventLogs -TargetFolder $targetFolder

        # Start Services
        Start-WindowsEventLogService

        [System.Windows.Forms.MessageBox]::Show("Event Logs moved successfully to $targetFolder.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Write-Log -Message "Event Logs moved successfully to $targetFolder." -Level "INFO"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Write-Log -Message "Error during operation: $_" -Level "ERROR"
    }
})

$form.ShowDialog() | Out-Null

# End of script
