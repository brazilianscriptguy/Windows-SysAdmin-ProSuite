<#
.SYNOPSIS
    Moves all Windows Event Log (.evtx) files from the default folder to a new target folder and updates registry paths.

.DESCRIPTION
    This script moves all .evtx files from 
        C:\Windows\System32\winevt\Logs 
    to a user‐specified target folder while preserving ACLs. For each event log file:
      - A subfolder is used (or created) in the target folder using the log’s name.
      - If a file already exists in that subfolder, it is renamed (backed up) before the new file is copied.
    After moving the files, the registry keys under 
        HKLM:\SYSTEM\CurrentControlSet\Services\EventLog 
    are updated so that the "File" property becomes:
        <TargetFolder>\<EventLogName>\<EventLogName>.evtx
    Additionally, new registry values "AutoBackupLogFiles" and "Flags" are created as required.
    Finally, the script stops and restarts the Event Log service.
    **Note:** A full reboot may be required for the changes to take full effect.
    A GUI is provided for user input and progress indication.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy (Refactored with new ACL and registry update techniques)

.VERSION
    5.0.5 - February 6, 2025

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
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath = Join-Path $logDir $logFileName

if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create log directory: $logDir"
        exit
    }
}

function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter()][ValidateSet('INFO', 'ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
        # Optionally update a GUI log control here.
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}
# Alias Write-Log as Log-Message.
function Log-Message {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    Write-Log -Message $Message -Level $Type
}

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
        $dependencies = Get-Service -Name "EventLog" -DependentServices | Where-Object { $_.Status -ne 'Stopped' -and $_.CanStop }
        if ($Action -eq "Stop") {
            $dependencies | ForEach-Object { Stop-Service -Name $_.Name -Force -ErrorAction Stop }
            Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        } else {
            Start-Service -Name "EventLog" -ErrorAction Stop
            $dependencies | ForEach-Object { Start-Service -Name $_.Name -ErrorAction Stop }
        }
        Log-Message -Message "$Action Event Log service and dependencies." -Type "INFO"
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
            Log-Message -Message "Created Target Folder: $TargetFolder" -Type "INFO"
        }
        catch {
            Handle-Error -Message "Failed to create target folder: $TargetFolder" -Exception $_
            return
        }
    }
    # Retrieve the original ACL from the default logs folder using extended parameters.
    try {
        $defaultLogsFolder = "$env:SystemRoot\System32\winevt\Logs"
        $originalACL = Get-Acl -Path $defaultLogsFolder -Audit -AllCentralAccessPolicies
    }
    catch {
        Handle-Error -Message "Failed to retrieve ACL from default logs folder ($defaultLogsFolder)." -Exception $_
        return
    }
    # Retrieve all .evtx files from the default logs folder.
    try {
        $logFiles = Get-ChildItem -Path $defaultLogsFolder -Filter "*.evtx"
    }
    catch {
        Handle-Error -Message "Failed to retrieve event log files." -Exception $_
        return
    }
    # Initialize the progress bar on the UI thread.
    $ProgressBar.Invoke([System.Action] { $ProgressBar.Minimum = 0 })
    $ProgressBar.Invoke([System.Action] { $ProgressBar.Maximum = $logFiles.Count })
    $ProgressBar.Invoke([System.Action] { $ProgressBar.Value = 0 })
    $i = 0
    foreach ($logFile in $logFiles) {
        try {
            # Use the log file's base name (with "%4" replaced by "-") as the folder name.
            $folderName = $logFile.BaseName -replace "%4", "-"
            $targetPath = Join-Path -Path $TargetFolder -ChildPath $folderName

            # If the folder does not exist, create it and apply the new ACL technique.
            if (-not (Test-Path $targetPath)) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                Log-Message -Message "Created folder: $targetPath" -Type "INFO"
                try {
                    # Apply the ACL from the default logs folder with the new parameters.
                    Set-Acl -Path $targetPath -AclObject $originalACL -ClearCentralAccessPolicy
                    $targetAcl = Get-Acl -Path $targetPath -Audit -AllCentralAccessPolicies
                    $targetAcl.SetOwner([System.Security.Principal.NTAccount]::new("SYSTEM"))
                }
                catch {
                    Handle-Error -Message "Failed to set ACLs on $targetPath." -Exception $_
                }
            } else {
                Log-Message -Message "Reusing existing folder: $targetPath" -Type "INFO"
            }

            # Define the destination file path.
            $destinationFile = Join-Path -Path $targetPath -ChildPath $logFile.Name

            # If a file already exists, rename it as a backup.
            if (Test-Path $destinationFile) {
                $backupFile = "$destinationFile.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Rename-Item -Path $destinationFile -NewName $backupFile -Force
                Log-Message -Message "Renamed existing file: $destinationFile to $backupFile" -Type "INFO"
            }

            try {
                Copy-Item -Path $logFile.FullName -Destination $destinationFile -Force -ErrorAction Stop
                Remove-Item -Path $logFile.FullName -Force -ErrorAction Stop
                # Apply the same ACL to the copied file.
                Set-Acl -Path $destinationFile -AclObject $originalACL
                Log-Message -Message "Moved: $($logFile.Name) to $targetPath and applied ACLs." -Type "INFO"
            }
            catch {
                Log-Message -Message "Skipped locked or inaccessible file: $($logFile.Name)" -Type "ERROR"
            }
        }
        catch {
            Log-Message -Message "Error processing file: $($logFile.FullName)" -Type "ERROR"
        }
        finally {
            # Update the progress bar value on the UI thread.
            $ProgressBar.Invoke([System.Action] { $ProgressBar.Value = $i })
            $i++
        }
    }
    try {
        # Also apply ACLs to the target folder itself using the new technique.
        Set-Acl -Path $TargetFolder -AclObject $originalACL -ClearCentralAccessPolicy
        $tgtFolderAcl = Get-Acl -Path $TargetFolder -Audit -AllCentralAccessPolicies
        $tgtFolderAcl.SetOwner([System.Security.Principal.NTAccount]::new("SYSTEM"))
        Log-Message -Message "Applied ACLs to the entire $TargetFolder directory." -Type "INFO"
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
        # Enumerate each immediate subkey under EventLog (e.g. Application, System, Security, etc.)
        $subKeys = Get-ChildItem -Path $registryBasePath
        foreach ($subKey in $subKeys) {
            # Check if the subkey has a "File" property.
            $fileProp = Get-ItemProperty -Path $subKey.PSPath -Name "File" -ErrorAction SilentlyContinue
            if ($fileProp -ne $null) {
                $logName = $subKey.PSChildName
                # Build the new file location: <NewPath>\<logName>\<logName>.evtx
                $newFolderPath = Join-Path -Path $NewPath -ChildPath $logName
                $newLogFilePath = Join-Path -Path $newFolderPath -ChildPath ("$logName.evtx")
                
                # Use the new technique: create or update registry values required.
                New-ItemProperty -Path $subKey.PSPath -Name "AutoBackupLogFiles" -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $subKey.PSPath -Name "Flags" -Value 1 -PropertyType DWord -Force | Out-Null
                Set-ItemProperty -Path $subKey.PSPath -Name "File" -Value $newLogFilePath -ErrorAction Stop
                
                Log-Message -Message "Updated registry: $($subKey.PSPath) -> $newLogFilePath" -Type "INFO"
            }
        }
        Log-Message -Message "All event log paths updated in the registry." -Type "INFO"
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
                [System.Windows.Forms.MessageBox]::Show("Event logs have been moved to '$targetFolder'.`nA reboot may be required for changes to take effect.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                Log-Message -Message "Event logs successfully moved to $targetFolder." -Type "INFO"
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
