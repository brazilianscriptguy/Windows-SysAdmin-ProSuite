<#
.SYNOPSIS
    Moves Windows Event Logs to a new location and updates registry paths.

.DESCRIPTION
    - Moves `.evtx` files while preserving ACLs.
    - Updates Event Log registry paths under 
      `HKLM:\SYSTEM\CurrentControlSet\Services\EventLog` so that the "File" value becomes:
      
          <TargetRootFolder>\<EventLogName>\<EventLogName>.evtx

    - Fixes incorrect folder naming (`%4` → `-`).
    - Stops and restarts Event Log services properly.
    - Handles locked log files to avoid script failure.
    - Provides a GUI interface for user interaction.

    For each event log, a subfolder is created in the target folder using the event log’s name.
    The log file is then moved into that subfolder and the registry key is updated accordingly.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    5.0.3 - February 5, 2025

.NOTES
    - Requires administrative privileges.
    - Compatible with PowerShell 5.1 or later.
#>

# --- Hide the PowerShell Console Window ---
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

# --- Elevation Check ---
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator.", "Insufficient Privileges", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

# --- Load UI Libraries ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Enhanced Logging Configuration ---
# Set up logging with a timestamped log file.
$scriptName  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir      = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath     = Join-Path $logDir $logFileName

# Ensure log directory exists.
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create log directory: $logDir"
        return
    }
}

# Enhanced logging function.
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO','ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
        # Uncomment below if you wish to update a GUI log box.
        # $logBox.Items.Add($logEntry)
        # $logBox.TopIndex = $logBox.Items.Count - 1
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# For backward compatibility, alias Write-Log as Log-Message.
function Log-Message {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    Write-Log -Message $Message -Level $Type
}

# Write an initial log entry.
Write-Log -Message "Script started." -Level "INFO"

# --- Error Handling ---
function Handle-Error {
    param (
        [string]$Message,
        $Exception = $null
    )
    $exMessage = ""
    if ($Exception) {
        if ($Exception -is [System.Management.Automation.ErrorRecord] -and $Exception.PSObject.Properties["Exception"]) {
            $exMessage = $Exception.Exception.Message
        }
        elseif ($Exception -is [System.Exception]) {
            $exMessage = $Exception.Message
        }
        else {
            $exMessage = $Exception.ToString()
        }
    }
    $fullMessage = if ($exMessage) { "$Message`nException: $exMessage" } else { $Message }
    Log-Message -Message $fullMessage -Type "ERROR"
    [System.Windows.Forms.MessageBox]::Show($fullMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# --- Service Management ---
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
    }
    catch {
        Handle-Error -Message "Failed to $Action Event Log service." -Exception $_
    }
}

# --- Move Event Logs ---
function Move-EventLogs {
    param (
        [string]$TargetFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    # Ensure target folder exists.
    if (-not (Test-Path $TargetFolder)) {
        try {
            New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
            Log-Message -Message "Created Target Folder: $TargetFolder"
        }
        catch {
            Handle-Error -Message "Failed to create target folder: $TargetFolder" -Exception $_
            return
        }
    }

    # Get original ACL from the default logs folder.
    try {
        $originalACL = Get-Acl -Path "$env:SystemRoot\System32\winevt\Logs"
    }
    catch {
        Handle-Error -Message "Failed to retrieve ACL from default logs folder." -Exception $_
        return
    }

    # Retrieve all .evtx files from the default logs folder.
    try {
        $logFiles = Get-ChildItem -Path "$env:SystemRoot\System32\winevt\Logs" -Filter "*.evtx"
    }
    catch {
        Handle-Error -Message "Failed to retrieve event log files." -Exception $_
        return
    }

    # Initialize the progress bar on the UI thread.
    $ProgressBar.Invoke([Action] { $ProgressBar.Minimum = 0 })
    $ProgressBar.Invoke([Action] { $ProgressBar.Maximum = $logFiles.Count })
    $ProgressBar.Invoke([Action] { $ProgressBar.Value   = 0 })

    $i = 0
    foreach ($logFile in $logFiles) {
        try {
            # Clean up the folder name by replacing "%4" with "-" if needed.
            $folderName = $logFile.BaseName -replace "%4", "-"
            $targetPath = Join-Path -Path $TargetFolder -ChildPath $folderName

            if (-not (Test-Path $targetPath)) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                Log-Message -Message "Created folder: $targetPath"
                Set-Acl -Path $targetPath -AclObject $originalACL
            }

            $destinationFile = Join-Path -Path $targetPath -ChildPath $logFile.Name

            try {
                Copy-Item -Path $logFile.FullName -Destination $destinationFile -Force -ErrorAction Stop
                Remove-Item -Path $logFile.FullName -Force -ErrorAction Stop
                Set-Acl -Path $destinationFile -AclObject $originalACL
                Log-Message -Message "Moved: $($logFile.Name) to $targetPath and applied ACLs."
            }
            catch {
                Log-Message -Message "Skipped locked or inaccessible file: $($logFile.Name)" -Type "WARNING"
            }
        }
        catch {
            Log-Message -Message "Error processing file: $($logFile.FullName)" -Type "ERROR"
        }
        finally {
            # Update the progress bar value on the UI thread.
            $ProgressBar.Invoke([Action] { $ProgressBar.Value = $i })
            $i++
        }
    }

    try {
        Set-Acl -Path $TargetFolder -AclObject $originalACL
        Log-Message -Message "Applied ACLs to the entire $TargetFolder directory."
    }
    catch {
        Handle-Error -Message "Failed to apply ACLs to $TargetFolder" -Exception $_
    }
}

# --- Update Registry Paths ---
function Update-RegistryPaths {
    param ([string]$NewPath)

    $registryBasePath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"

    try {
        # Iterate recursively over all keys under the EventLog base.
        $keysWithFile = Get-ChildItem -Path $registryBasePath -Recurse | Where-Object {
            (Get-ItemProperty -Path $_.PSPath -Name "File" -ErrorAction SilentlyContinue) -ne $null
        }
        foreach ($key in $keysWithFile) {
            # Use the key's leaf name as the log name.
            $logName = Split-Path -Path $key.PSPath -Leaf
            # Build the new file location: <NewPath>\<logName>\<logName>.evtx
            $newFolderPath = Join-Path -Path $NewPath -ChildPath $logName
            $newLogFilePath = Join-Path -Path $newFolderPath -ChildPath ("$logName.evtx")
            Set-ItemProperty -Path $key.PSPath -Name "File" -Value $newLogFilePath -ErrorAction Stop
            Log-Message -Message "Updated registry: $($key.PSPath) -> $newLogFilePath"
        }
        Log-Message -Message "All event log paths updated in the registry."
    }
    catch {
        Handle-Error -Message "Failed to update registry paths." -Exception $_
    }
}

# --- GUI Setup ---
function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Paths'
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = 'CenterScreen'

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
    $form.Controls.Add($progressBar)

    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Move Logs"
    $button.Location = New-Object System.Drawing.Point(200, 130)
    $button.Add_Click({
        $targetFolder = $textBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetFolder)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter the target root folder.", "Input Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Log-Message -Message "Error: Target root folder not entered." -Type "ERROR"
            return
        }
        try {
            Stop-Start-Services -Action "Stop"
            Move-EventLogs -TargetFolder $targetFolder -ProgressBar $progressBar
            Update-RegistryPaths -NewPath $targetFolder
            Stop-Start-Services -Action "Start"
            [System.Windows.Forms.MessageBox]::Show("Event logs have been moved to '$targetFolder'.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Log-Message -Message "Event logs successfully moved to $targetFolder."
        }
        catch {
            Handle-Error -Message "An error occurred during the log moving process." -Exception $_
        }
    })
    $form.Controls.Add($button)

    $form.ShowDialog() | Out-Null
}

# Launch the GUI.
Setup-GUI

# End of script
