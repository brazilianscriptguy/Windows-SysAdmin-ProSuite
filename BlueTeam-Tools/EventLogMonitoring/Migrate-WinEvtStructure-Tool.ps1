<#
.SYNOPSIS
    PowerShell Script to Move Windows Event Log Default Paths with GUI and Enhanced Permissions Handling

.DESCRIPTION
    Provides a graphical user interface (GUI) for users to confirm the target drive.
    Moves the default paths of Windows Event Logs to the specified drive root and updates the registry accordingly.
    Stops the Event Log service to move locked .evtx files and ensures necessary permissions are set on the new drive.
    Stores script execution logs in 'C:\Logs-TEMP\'.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2.3.0 - January 3, 2025

.NOTES
    - Requires running with administrative privileges.
    - Stops and starts the Windows Event Log service to move .evtx files.
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

# Define global variables
$scriptName     = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir         = 'C:\Logs-TEMP'  # Script's action logs directory
$TargetWinEvtLogs = 'L:\'         # Drive where Windows Event Logs will be moved
$logFileName    = "$scriptName.log"
$logPath        = Join-Path -Path $logDir -ChildPath $logFileName

# Function: Initialize-LogDirectory
function Initialize-LogDirectory {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )
    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log -Message "Log directory created at $Path" -Level "INFO"
        } else {
            Write-Log -Message "Log directory already exists at $Path" -Level "DEBUG"
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to create log directory at $Path. Logging will not be possible.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        throw $_
    }
}

# Function: Initialize-Logging
function Initialize-Logging {
    Initialize-LogDirectory -Path $logDir
}

# Enhanced logging function with error handling
function Write-Log {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp][$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
        if ($script:logBox -and $script:logBox.InvokeRequired -eq $false) {
            $script:logBox.Items.Add($logEntry) | Out-Null
            $script:logBox.TopIndex = $script:logBox.Items.Count - 1
        }
    } catch {
        Write-Error "Failed to write to log file: $_"
    }
}

# Initialize logging
try {
    Initialize-Logging
} catch {
    exit
}

# Function: Check-AdminPrivileges
function Check-AdminPrivileges {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$IsAdmin = Check-AdminPrivileges

if (-not $IsAdmin) {
    [System.Windows.Forms.MessageBox]::Show(
        "This script must be run as an administrator.",
        "Insufficient Privileges",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    Write-Log -Message "Script is not running with administrative privileges." -Level "ERROR"
    exit
}

# Function: Grant-Permissions
function Grant-Permissions {
    param (
        [Parameter(Mandatory)]
        [string]$FolderPath
    )
    try {
        $acl = Get-Acl -Path $FolderPath

        # Define the accounts to grant permissions
        $accounts = @("SYSTEM", "Administrators", "LOCAL SERVICE", "NETWORK SERVICE")

        foreach ($account in $accounts) {
            switch ($account) {
                "SYSTEM" {
                    $permission = "FullControl"
                }
                "Administrators" {
                    $permission = "FullControl"
                }
                "LOCAL SERVICE" {
                    $permission = "ReadAndExecute, Read"
                }
                "NETWORK SERVICE" {
                    $permission = "ReadAndExecute, Read"
                }
                default {
                    $permission = "ReadAndExecute, Read"
                }
            }

            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $account,
                $permission,
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.SetAccessRule($accessRule)
        }

        Set-Acl -Path $FolderPath -AclObject $acl -ErrorAction Stop
        Write-Log -Message "Granted necessary permissions to $FolderPath." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to set permissions on ${FolderPath}: $_" -Level "ERROR"
        throw $_
    }
}

# Function: Retrieve-EventLogs
function Retrieve-EventLogs {
    try {
        Write-Log -Message "Retrieving event log names from registry and Logs directory." -Level "INFO"

        # Get event log names from the registry
        $registryLogsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"
        $regLogs = Get-ChildItem -Path $registryLogsPath -ErrorAction Stop | Select-Object -ExpandProperty PSChildName

        # Get event log files from the Logs directory
        $logFilesPath = "$env:SystemRoot\system32\winevt\Logs"
        $logFiles = Get-ChildItem -Path $logFilesPath -Filter *.evtx -ErrorAction SilentlyContinue | 
                    Select-Object -ExpandProperty BaseName

        # Combine and remove duplicates
        $logNames = ($regLogs + $logFiles) | Sort-Object -Unique

        Write-Log -Message "Retrieved $($logNames.Count) unique event logs." -Level "INFO"
        return $logNames
    } catch {
        Write-Log -Message "Failed to retrieve event logs: $_" -Level "ERROR"
        throw $_
    }
}

# Function: Stop-EventLogService
function Stop-EventLogService {
    try {
        Write-Log -Message "Stopping Windows Event Log service..." -Level "INFO"
        Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        Write-Log -Message "Windows Event Log service stopped." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to stop Windows Event Log service: $_" -Level "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to stop Windows Event Log service. Please ensure you have administrative privileges.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        throw $_
    }
}

# Function: Start-EventLogService
function Start-EventLogService {
    try {
        Write-Log -Message "Starting Windows Event Log service..." -Level "INFO"
        Start-Service -Name "EventLog" -ErrorAction Stop
        Write-Log -Message "Windows Event Log service started." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to start Windows Event Log service: $_" -Level "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to start Windows Event Log service. Please start it manually.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Function: Update-RegistryPath
function Update-RegistryPath {
    param (
        [Parameter(Mandatory)]
        [string]$LogName,

        [Parameter(Mandatory)]
        [string]$NewLogFilePath
    )
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$LogName"
        Set-ItemProperty -Path $regPath -Name "File" -Value $NewLogFilePath -ErrorAction Stop
        Write-Log -Message "Updated registry path for '$LogName' to '$NewLogFilePath'." -Level "INFO"
    } catch {
        Write-Log -Message "Failed to update registry for '$LogName': $_" -Level "ERROR"
        throw $_
    }
}

# Function: Move-LogFile
function Move-LogFile {
    param (
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    try {
        if (Test-Path -Path $SourcePath) {
            Move-Item -Path $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
            Write-Log -Message "Moved log file from '$SourcePath' to '$DestinationPath'." -Level "INFO"
        } else {
            Write-Log -Message "Source log file '$SourcePath' does not exist. Skipping move." -Level "WARN"
        }
    } catch {
        Write-Log -Message "Failed to move log file from '$SourcePath' to '$DestinationPath': $_" -Level "ERROR"
        throw $_
    }
}

# Function: Apply-Default-ACLs-to-Drive
function Apply-Default-ACLs-to-Drive {
    param (
        [Parameter(Mandatory)]
        [string]$DrivePath
    )
    try {
        Write-Log -Message "Applying default ACLs to drive '$DrivePath'." -Level "INFO"
        Grant-Permissions -FolderPath $DrivePath
    } catch {
        Write-Log -Message "Failed to apply default ACLs to drive '$DrivePath': $_" -Level "ERROR"
        throw $_
    }
}

# Function: Move-EventLogs
function Move-EventLogs {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetWinEvtLogs,

        [Parameter(Mandatory)]
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    try {
        Write-Log -Message "Script execution started." -Level "INFO"

        # Validate and create the script's log directory
        Initialize-LogDirectory -Path $logDir

        # Validate and confirm the target drive path
        if (-not (Test-Path -Path $TargetWinEvtLogs)) {
            [System.Windows.Forms.MessageBox]::Show(
                "The specified drive '$TargetWinEvtLogs' does not exist.",
                "Invalid Drive",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            Write-Log -Message "Specified drive '$TargetWinEvtLogs' does not exist." -Level "ERROR"
            return
        }

        # Apply default ACLs to the target drive
        Apply-Default-ACLs-to-Drive -DrivePath $TargetWinEvtLogs

        # Retrieve all event log names
        $logNames = Retrieve-EventLogs

        $totalLogs = $logNames.Count

        if ($totalLogs -eq 0) {
            Write-Log -Message "No event logs found to move." -Level "INFO"
            [System.Windows.Forms.MessageBox]::Show(
                "No event logs found to move.",
                "Information",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            return
        }

        $ProgressBar.Maximum = $totalLogs
        $ProgressBar.Value = 0

        # Stop the Event Log service
        Stop-EventLogService

        $currentLogNumber = 0

        foreach ($logName in $logNames) {
            try {
                $currentLogNumber++

                # Escape log name by replacing invalid characters with '-'
                $escapedLogName = $logName -replace '[\\/:"*?<>|]', '-'
                $targetLogFile = Join-Path -Path $TargetWinEvtLogs -ChildPath "$escapedLogName.evtx"

                # Define new log file path
                $newLogFilePath = $targetLogFile

                # Update the registry to point to the new log file location
                Update-RegistryPath -LogName $logName -NewLogFilePath $newLogFilePath

                # Move existing log file if it exists
                $originalLogFile = Join-Path -Path "$env:SystemRoot\system32\winevt\Logs" -ChildPath "$escapedLogName.evtx"
                Move-LogFile -SourcePath $originalLogFile -DestinationPath $newLogFilePath

                Write-Log -Message "Processed log '$logName'." -Level "INFO"
            } catch {
                Write-Log -Message "An error occurred while processing log '$logName': $_" -Level "ERROR"
            } finally {
                # Update progress bar
                $ProgressBar.Value = $currentLogNumber
            }
        }

        # Start the Event Log service
        Start-EventLogService

        Write-Log -Message "Script completed successfully." -Level "INFO"
        [System.Windows.Forms.MessageBox]::Show(
            "Event logs have been successfully moved and reconfigured. Please check the log for details.",
            "Completed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    } catch {
        Write-Log -Message "An unexpected error occurred: $_" -Level "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "An unexpected error occurred. Please check the log for details.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
}

# Create and configure the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Move Event Log Default Paths'
$form.Size = New-Object System.Drawing.Size(500, 550)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Label for Target Drive
$labelTargetDrive = New-Object System.Windows.Forms.Label
$labelTargetDrive.Text = 'Enter the target drive letter for Event Logs (e.g., "L:\"):'
$labelTargetDrive.Location = New-Object System.Drawing.Point(10, 20)
$labelTargetDrive.AutoSize = $true
$form.Controls.Add($labelTargetDrive)

# TextBox for Target Drive
$textBoxTargetDrive = New-Object System.Windows.Forms.TextBox
$textBoxTargetDrive.Location = New-Object System.Drawing.Point(10, 40)
$textBoxTargetDrive.Size = New-Object System.Drawing.Size(460, 20)
$textBoxTargetDrive.Text = $TargetWinEvtLogs  # Default to 'L:\'
$form.Controls.Add($textBoxTargetDrive)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 70)
$progressBar.Size = New-Object System.Drawing.Size(460, 20)
$progressBar.Minimum = 0
$form.Controls.Add($progressBar)

# Log Box
$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location = New-Object System.Drawing.Point(10, 100)
$logBox.Size = New-Object System.Drawing.Size(460, 350)
$form.Controls.Add($logBox)
$script:logBox = $logBox  # Make logBox accessible globally for logging

# Execute Button
$executeButton = New-Object System.Windows.Forms.Button
$executeButton.Text = 'Move Logs'
$executeButton.Location = New-Object System.Drawing.Point(10, 470)
$executeButton.Size = New-Object System.Drawing.Size(100, 30)
$executeButton.Enabled = $true

# Add Click Event
$executeButton.Add_Click({
    $targetWinEvtLogs = $textBoxTargetDrive.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($targetWinEvtLogs)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter the target drive letter.",
            "Input Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        Write-Log -Message "Target drive input was empty." -Level "WARN"
        return
    }

    # Validate target drive path format
    if (-not ($targetWinEvtLogs -match '^[A-Z]:\\$')) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a valid drive letter path (e.g., 'L:\').",
            "Invalid Path",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        Write-Log -Message "Invalid target drive path: $targetWinEvtLogs" -Level "WARN"
        return
    }

    Move-EventLogs -TargetWinEvtLogs $targetWinEvtLogs -ProgressBar $progressBar
})

$form.Controls.Add($executeButton)

# Show the form
$form.ShowDialog() | Out-Null

# End of script
