<#
.SYNOPSIS
    Moves all Windows Event Log (.evtx) files from the default folder to a new target folder and updates registry paths.

.DESCRIPTION
    This script moves all .evtx files from 
        C:\Windows\System32\winevt\Logs 
    to a user‐specified target folder while preserving ACLs. For each event log file:
      - A subfolder is used (or created) in the target folder using the log’s name.
      - If a file already exists in that subfolder, it is archived (renamed) with a timestamp (still .evtx) before the new file is copied.
    After moving the files, the registry keys under 
        HKLM:\SYSTEM\CurrentControlSet\Services\EventLog 
    are updated so that the "File" property becomes:
        <TargetFolder>\<EventLogName>\<EventLogName>.evtx
    Additionally, new registry values "AutoBackupLogFiles" and "Flags" are created as required.
    Finally, the script stops and restarts the Event Log service (and restores original states of dependents and DHCP Server).
    **Note:** A full reboot may be required for the changes to take full effect.
    A GUI is provided for user input and progress indication.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy (Refactored with new ACL and registry update techniques)

.VERSION
    6.0.0 - November 6, 2025

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
        if (handle != IntPtr.Zero) ShowWindow(handle, 0); // SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        if (handle != IntPtr.Zero) ShowWindow(handle, 5); // SW_SHOW
    }
}
"@
[Window]::Hide()

# --- Load UI Libraries ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Elevation Check ---
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Administrator)) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator.", "Insufficient Privileges", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit
}

# --- Logging ---
$scriptName  = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir      = 'C:\Logs-TEMP'
$logFileName = "${scriptName}_$(Get-Date -Format 'yyyyMMddHHmmss').log"
$logPath     = Join-Path $logDir $logFileName
if (-not (Test-Path $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch { Write-Error "Failed to create log directory: $logDir"; exit }
}
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $logEntry } catch { Write-Error "Failed to write to log: $_" }
}
function Handle-Error {
    param ([string]$Message, $Exception = $null)
    $exMessage = if ($Exception -and $Exception.PSObject.Properties["Exception"]) { $Exception.Exception.Message } elseif ($Exception -is [System.Exception]) { $Exception.Message } elseif ($Exception) { $Exception.ToString() } else { "" }
    $fullMessage = if ($exMessage) { "$Message`nException: $exMessage" } else { $Message }
    Write-Log -Message $fullMessage -Level "ERROR"
    [System.Windows.Forms.MessageBox]::Show($fullMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
}
Write-Log -Message "Script started." -Level "INFO"

# --- Globals & Helpers ---
$DefaultLogsFolder = "$env:SystemRoot\System32\winevt\Logs"

function Get-SafeName {
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name -replace '%4','-'
    $invalid = ([IO.Path]::GetInvalidFileNameChars() + [IO.Path]::GetInvalidPathChars()) | Sort-Object -Unique
    foreach($c in $invalid){ $n = $n -replace [Regex]::Escape([string]$c), '-' }
    $n = ($n -replace '[\s\-]+','-').Trim().Trim('.').Trim('-')
    if([string]::IsNullOrWhiteSpace($n)){ $n = 'Log' }
    return $n
}

function Files-Differ {
    param([Parameter(Mandatory)][string]$A,[Parameter(Mandatory)][string]$B)
    try {
        $fa = Get-Item -LiteralPath $A -ErrorAction Stop
        $fb = Get-Item -LiteralPath $B -ErrorAction Stop
        if($fa.Length -ne $fb.Length){ return $true }
        if([Math]::Abs(($fa.LastWriteTimeUtc - $fb.LastWriteTimeUtc).TotalSeconds) -gt 2){ return $true }
        return $false
    } catch { return $true }
}

function New-UniqueArchiveName {
    param([Parameter(Mandatory)][string]$Dir,[Parameter(Mandatory)][string]$Base)
    do {
        $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        $candidate = Join-Path $Dir ("{0}_{1}.evtx" -f $Base, $stamp)
        if (Test-Path -LiteralPath $candidate) {
            $candidate = Join-Path $Dir ("{0}_{1}_{2}.evtx" -f $Base, $stamp, (Get-Random -Maximum 10000))
        }
    } until (-not (Test-Path -LiteralPath $candidate))
    return $candidate
}

# --- Service State Snapshot / Restore (EventLog, dependents, DHCP) ---
$Global:ServiceState = @{}

function Snapshot-ServiceState {
    param([string[]]$ServiceNames)
    foreach ($name in $ServiceNames) {
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            $Global:ServiceState[$name] = $svc.Status
            Write-Log -Message "Service state snapshot: $name = $($svc.Status)" -Level "INFO"
        } catch {
            Write-Log -Message "Service not found (snapshot skip): $name" -Level "WARN"
        }
    }
}

function Restore-ServiceState {
    foreach ($kvp in $Global:ServiceState.GetEnumerator()) {
        $name  = $kvp.Key
        $state = $kvp.Value
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            if ($state -eq 'Running') {
                if ($svc.Status -ne 'Running') {
                    Start-Service -Name $name -ErrorAction Stop
                    Write-Log -Message "Restored service to Running: $name" -Level "INFO"
                } else {
                    Write-Log -Message "Service already Running: $name" -Level "INFO"
                }
            } elseif ($state -eq 'Stopped') {
                if ($svc.Status -ne 'Stopped') {
                    Stop-Service -Name $name -Force -ErrorAction Stop
                    Write-Log -Message "Restored service to Stopped: $name" -Level "INFO"
                } else {
                    Write-Log -Message "Service already Stopped: $name" -Level "INFO"
                }
            } else {
                Write-Log -Message "Service state unchanged ($state): $name" -Level "INFO"
            }
        } catch {
            Write-Log -Message "Failed to restore service state: $name" -Level "ERROR"
        }
    }
}

function Stop-For-Migration {
    # Collect EventLog dependents (they must be stopped first)
    $deps = @(Get-Service -Name "EventLog" -DependentServices 2>$null)
    $depNames = @()
    if ($deps) { $depNames = $deps.Name }
    # Explicitly include DHCP Server for safe migration (per requirement)
    $special = @('DhcpServer')
    $allToTrack = ($depNames + $special) | Select-Object -Unique
    if (-not $allToTrack) { $allToTrack = @() }

    # Snapshot states (so we can restore exactly as before)
    Snapshot-ServiceState -ServiceNames ($allToTrack + @('EventLog'))

    # Stop dependents first
    foreach ($svcName in $depNames) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ($svc.Status -ne 'Stopped') {
                Write-Log -Message "Stopping dependent service: $svcName" -Level "INFO"
                Stop-Service -Name $svcName -Force -ErrorAction Stop
            }
        } catch { Write-Log -Message "Failed stopping dependent service: $svcName" -Level "ERROR" }
    }

    # Stop DHCP if present and running
    try {
        $dhcp = Get-Service -Name 'DhcpServer' -ErrorAction Stop
        if ($dhcp.Status -ne 'Stopped') {
            Write-Log -Message "Stopping DHCP Server service for migration..." -Level "INFO"
            Stop-Service -Name 'DhcpServer' -Force -ErrorAction Stop
        }
    } catch { Write-Log -Message "DHCP Server service not found or not stoppable." -Level "WARN" }

    # Finally stop EventLog
    try {
        $ev = Get-Service -Name "EventLog" -ErrorAction Stop
        if ($ev.Status -ne 'Stopped') {
            Write-Log -Message "Stopping Event Log service..." -Level "INFO"
            Stop-Service -Name "EventLog" -Force -ErrorAction Stop
        }
    } catch {
        Handle-Error -Message "Failed to stop Event Log service." -Exception $_
        throw
    }
}

function Start-After-Migration {
    # Start EventLog first
    try {
        Start-Service -Name "EventLog" -ErrorAction Stop
        Write-Log -Message "Started Event Log service." -Level "INFO"
    } catch {
        Handle-Error -Message "Failed to start Event Log service." -Exception $_
    }

    # Restore all tracked services (dependents + DHCP) to their previous state
    Restore-ServiceState
}

# --- Move Event Logs (idempotent; .evtx-only) ---
function Move-EventLogs {
    param (
        [string]$TargetFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    # Ensure target folder exists (do NOT touch root ACL).
    if (-not (Test-Path $TargetFolder)) {
        try {
            New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created Target Folder: $TargetFolder" -Level "INFO"
        }
        catch {
            Handle-Error -Message "Failed to create target folder: $TargetFolder" -Exception $_
            return
        }
    }

    # Retrieve ACL from the default logs folder (apply only to new per-log subfolders/files)
    try {
        $originalACL = Get-Acl -Path $DefaultLogsFolder
    }
    catch {
        Handle-Error -Message "Failed to retrieve ACL from default logs folder ($DefaultLogsFolder)." -Exception $_
        return
    }

    # Retrieve all .evtx files from the default logs folder.
    try {
        $logFiles = Get-ChildItem -Path $DefaultLogsFolder -Filter "*.evtx" -File
    }
    catch {
        Handle-Error -Message "Failed to retrieve event log files." -Exception $_
        return
    }

    # Initialize the progress bar on the UI thread.
    $ProgressBar.Invoke([System.Action]{ $ProgressBar.Minimum = 0 })
    $ProgressBar.Invoke([System.Action]{ $ProgressBar.Maximum = $logFiles.Count })
    $ProgressBar.Invoke([System.Action]{ $ProgressBar.Value   = 0 })
    $i = 0

    foreach ($logFile in $logFiles) {
        try {
            # Sanitize folder and active filename: <Target>\<Base>\<Base>.evtx
            $baseName   = Get-SafeName -Name $logFile.BaseName
            $targetPath = Join-Path -Path $TargetFolder -ChildPath $baseName

            # If the folder does not exist, create it and apply ACL from original logs folder.
            $created = $false
            if (-not (Test-Path $targetPath)) {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                $created = $true
                Write-Log -Message "Created folder: $targetPath" -Level "INFO"
            } else {
                Write-Log -Message "Reusing existing folder: $targetPath" -Level "INFO"
            }
            if ($created) {
                try { Set-Acl -Path $targetPath -AclObject $originalACL } catch { Write-Log -Message "Failed to set ACLs on $targetPath." -Level "WARN" }
            }

            # Define destination file path.
            $destinationFile = Join-Path -Path $targetPath -ChildPath ("{0}.evtx" -f $baseName)

            # If a file already exists in destination, archive it (still .evtx) when differs.
            if (Test-Path $destinationFile) {
                if (Files-Differ -A $logFile.FullName -B $destinationFile) {
                    $dir = Split-Path $destinationFile -Parent
                    $base = [IO.Path]::GetFileNameWithoutExtension($destinationFile)
                    $archive = New-UniqueArchiveName -Dir $dir -Base $base
                    try {
                        Rename-Item -LiteralPath $destinationFile -NewName (Split-Path $archive -Leaf) -Force -ErrorAction Stop
                        Write-Log -Message "Archived previous active: $destinationFile -> $archive" -Level "INFO"
                    } catch {
                        Write-Log -Message "Failed to archive existing destination (locked?): $destinationFile. Skipping this log." -Level "WARN"
                        $i++; $ProgressBar.Invoke([System.Action]{ $ProgressBar.Value = [Math]::Min($i, $logFiles.Count) }); continue
                    }
                } else {
                    Write-Log -Message "Active up-to-date: $destinationFile" -Level "INFO"
                }
            }

            try {
                # Copy then remove source (MOVE behavior), now safe because EventLog is stopped
                Copy-Item -Path $logFile.FullName -Destination $destinationFile -Force -ErrorAction Stop
                Remove-Item -Path $logFile.FullName -Force -ErrorAction Stop
                # Apply the same ACL to the copied file.
                try { Set-Acl -Path $destinationFile -AclObject $originalACL } catch { Write-Log -Message "Failed to set ACLs on file: $destinationFile" -Level "WARN" }
                Write-Log -Message "Moved: $($logFile.Name) to $targetPath and applied ACLs." -Level "INFO"
            }
            catch {
                Write-Log -Message "Skipped inaccessible source file (unexpected): $($logFile.Name)" -Level "WARN"
            }
        }
        catch {
            Write-Log -Message "Error processing file: $($logFile.FullName)" -Level "WARN"
        }
        finally {
            $i++
            $ProgressBar.Invoke([System.Action]{ $ProgressBar.Value = [Math]::Min($i, $logFiles.Count) })
        }
    }

    Write-Log -Message "Move phase completed. Root ACL untouched: $TargetFolder" -Level "INFO"
}

# --- Update Registry Paths (CLASSIC) ---
function Update-RegistryPaths {
    param ([string]$NewPath)
    $registryBasePath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog"
    try {
        # Enumerate each immediate subkey under EventLog (e.g., Application, System, Security, etc.)
        $subKeys = Get-ChildItem -Path $registryBasePath
        foreach ($subKey in $subKeys) {
            # Check if the subkey has a "File" property.
            $fileProp = Get-ItemProperty -Path $subKey.PSPath -Name "File" -ErrorAction SilentlyContinue
            if ($fileProp -ne $null) {
                $logName = $subKey.PSChildName
                # Build the new file location: <NewPath>\<logName>\<logName>.evtx
                $sanLog   = Get-SafeName -Name $logName
                $newFolderPath = Join-Path -Path $NewPath -ChildPath $sanLog
                $newLogFilePath = Join-Path -Path $newFolderPath -ChildPath ("{0}.evtx" -f $sanLog)

                if (-not (Test-Path $newFolderPath)) { New-Item -Path $newFolderPath -ItemType Directory -Force | Out-Null }

                # Create or update registry values required.
                New-ItemProperty -Path $subKey.PSPath -Name "AutoBackupLogFiles" -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $subKey.PSPath -Name "Flags"             -Value 1 -PropertyType DWord -Force | Out-Null

                $current = [string](Get-ItemProperty -Path $subKey.PSPath -Name "File" -ErrorAction SilentlyContinue).File
                if ($current -ne $newLogFilePath) {
                    Set-ItemProperty -Path $subKey.PSPath -Name "File" -Value $newLogFilePath -ErrorAction Stop
                }
                Write-Log -Message "Updated registry: $($subKey.PSPath) -> $newLogFilePath" -Level "INFO"
            }
        }
        Write-Log -Message "All event log paths updated in the registry (classic logs)." -Level "INFO"
    }
    catch {
        Handle-Error -Message "Failed to update registry paths." -Exception $_
    }
}

# --- GUI Setup ---
function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Paths'
    $form.Size = New-Object System.Drawing.Size(520, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    
    $labelTargetRootFolder = New-Object System.Windows.Forms.Label
    $labelTargetRootFolder.Text = 'Enter the target root folder (e.g., "L:\"):'
    $labelTargetRootFolder.Location = New-Object System.Drawing.Point(10, 20)
    $labelTargetRootFolder.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($labelTargetRootFolder)
    
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(10, 45)
    $textBox.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($textBox)
    
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 80)
    $progressBar.Size = New-Object System.Drawing.Size(480, 20)
    $form.Controls.Add($progressBar)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 110)
    $statusLabel.Size = New-Object System.Drawing.Size(480, 40)
    $statusLabel.Text = "Ready."
    $form.Controls.Add($statusLabel)
    
    $buttonMove = New-Object System.Windows.Forms.Button
    $buttonMove.Text = "Move Logs"
    $buttonMove.Location = New-Object System.Drawing.Point(210, 160)
    $form.Controls.Add($buttonMove)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = "Close"
    $buttonClose.Location = New-Object System.Drawing.Point(310, 160)
    $buttonClose.Enabled = $false
    $buttonClose.Add_Click({ $form.Close() })
    $form.Controls.Add($buttonClose)

    $buttonMove.Add_Click({
        $targetFolder = $textBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetFolder)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter the target root folder.", "Input Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            Write-Log -Message "Error: Target root folder not entered." -Level "ERROR"
            return
        }
        try {
            $statusLabel.Text = "Stopping services (EventLog, dependents, DHCP)..."
            Stop-For-Migration

            $statusLabel.Text = "Moving .evtx files..."
            Move-EventLogs -TargetFolder $targetFolder -ProgressBar $progressBar

            $statusLabel.Text = "Updating registry (classic logs)..."
            Update-RegistryPaths -NewPath $targetFolder

            $statusLabel.Text = "Restoring services..."
            Start-After-Migration

            # Ensure progress shows 100%
            $progressBar.Value = $progressBar.Maximum

            $buttonMove.Enabled = $false
            $buttonClose.Enabled = $true

            $finalMsg = @"
Event logs have been moved to:
  $targetFolder

Log file:
  $logPath

Rotation and file sizes must be controlled by GPO.
A reboot may be required for all changes to take effect.

⚠ DHCP SERVER NOTICE (REVIEW REQUIRED)
- The DHCP Server service was stopped during the migration and then restored to its previous state.
- Please verify after migration:
    • Service status (running/stopped as expected)
    • Leases and reservations are active
    • Event log paths are valid and writable
    • 'L:\DHCP Server\' and 'L:\DHCP Server\Backup\' remain intact
"@
            [System.Windows.Forms.MessageBox]::Show($finalMsg, "Migration Completed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            $statusLabel.Text = "Completed. You may close this window."
            Write-Log -Message "Process finished with exit code 0. Target: $targetFolder" -Level "INFO"
            Write-Log -Message "DHCP Server requires validation after migration (status, leases, reservations, log paths)." -Level "WARN"
        }
        catch {
            Handle-Error -Message "An error occurred during the log moving process." -Exception $_
        }
    })
    
    $form.ShowDialog() | Out-Null
}

# Launch the GUI.
Setup-GUI

# End of script
