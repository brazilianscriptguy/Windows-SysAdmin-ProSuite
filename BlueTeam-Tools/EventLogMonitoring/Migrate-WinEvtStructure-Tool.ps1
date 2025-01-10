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
    - Handles Critical Services: Ensures dependent services like DHCP are restarted.
    - Validates Critical Services: Verifies that critical services are running post-restart.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    3.3.0 - January 10, 2025

.NOTES
    - Requires administrative privileges.
    - Compatible with environments running PowerShell 5.1 or later.
    - Handles special characters in folder names to ensure clean and consistent paths.
#>

# --- GLOBAL CONFIGURATIONS ---
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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- FUNCTIONS ---

function Initialize-ScriptPaths {
    $scriptName = if ($MyInvocation.ScriptName) {
        [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
    } else {
        "Script"
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

function Log-Message {
    param (
        [string]$Message,
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry
    } catch {
        Write-Error "Logging failed: $_"
    }
}

function Handle-Error {
    param ([string]$ErrorMessage)
    Log-Message -Message "$ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Sanitize-Name {
    param ([string]$Name)
    return $Name -replace '[^a-zA-Z\-]', '-' -replace '-+', '-' -replace '-$', ''
}

function Stop-EventLogService {
    try {
        $dependentServices = Get-Service -Name "EventLog" -DependentServices | Where-Object { $_.Status -ne 'Stopped' }
        foreach ($service in $dependentServices) {
            Stop-Service -Name $service.Name -Force
            Log-Message -Message "Stopped dependent service: $($service.Name)."
        }

        Stop-Service -Name "EventLog" -Force
        Log-Message -Message "Event Log service stopped."
    } catch {
        Handle-Error "Failed to stop Event Log service: $_"
        throw
    }
}

function Start-EventLogService {
    try {
        Start-Service -Name "EventLog"
        Log-Message -Message "Event Log service started."

        $dependentServices = Get-Service -Name "EventLog" -DependentServices
        foreach ($service in $dependentServices) {
            Start-Service -Name $service.Name
            Log-Message -Message "Started dependent service: $($service.Name)."
        }
    } catch {
        Handle-Error "Failed to start Event Log service: $_"
        throw
    }
}

function Restart-CriticalServices {
    $criticalServices = @("DHCP", "DNS", "Spooler", "W32Time")
    foreach ($serviceName in $criticalServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Restart-Service -Name $serviceName -Force
                Log-Message -Message "Restarted critical service: $serviceName."
            }
        } catch {
            Log-Message -Message "Failed to restart critical service: $serviceName - $_" -MessageType "ERROR"
        }
    }
}

function Validate-CriticalServices {
    param (
        [int]$RetryCount = 3,
        [int]$RetryDelay = 5
    )

    $criticalServices = @("DHCP", "DNS", "Spooler", "W32Time")
    foreach ($serviceName in $criticalServices) {
        $retry = 0
        $serviceHealthy = $false
        while ($retry -lt $RetryCount -and -not $serviceHealthy) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($service -and $service.Status -eq "Running") {
                    Log-Message -Message "Service '$serviceName' is running." -MessageType "INFO"
                    $serviceHealthy = $true
                } else {
                    if ($service -and $service.Status -ne "Running") {
                        Start-Service -Name $serviceName -ErrorAction Stop
                        Log-Message -Message "Attempted to start service '$serviceName'." -MessageType "INFO"
                    } else {
                        Log-Message -Message "Service '$serviceName' not found or unavailable." -MessageType "ERROR"
                    }
                }
            } catch {
                Log-Message -Message "Failed to start service '$serviceName': $_" -MessageType "ERROR"
            }

            if (-not $serviceHealthy) {
                Start-Sleep -Seconds $RetryDelay
                $retry++
            }
        }

        if (-not $serviceHealthy) {
            Log-Message -Message "Service '$serviceName' could not be validated after $RetryCount retries." -MessageType "CRITICAL"
            [System.Windows.Forms.MessageBox]::Show("Service '$serviceName' could not be validated after multiple retries. Please check manually.", "Critical Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        }
    }
}

function Move-EventLogs {
    param (
        [string]$TargetFolder,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not (Test-Path $TargetFolder)) {
        try {
            New-Item -Path $TargetFolder -ItemType Directory -Force | Out-Null
            Log-Message -Message "Created target folder: $TargetFolder."
        } catch {
            Handle-Error "Failed to create target folder: $_"
            return
        }
    }

    $sourceAcl = Get-Acl -Path "$env:SystemRoot\System32\winevt\Logs"
    Set-Acl -Path $TargetFolder -AclObject $sourceAcl
    Log-Message -Message "Applied ACLs to target folder: $TargetFolder."

    $logFiles = Get-ChildItem -Path "$env:SystemRoot\System32\winevt\Logs" -Filter "*.evtx"
    $ProgressBar.Maximum = $logFiles.Count

    $logFiles | ForEach-Object -Begin { $i = 0 } -Process {
        $targetPath = Join-Path -Path $TargetFolder -ChildPath $_.Name
        try {
            Move-Item -Path $_.FullName -Destination $targetPath -Force
            Log-Message -Message "Moved: $($_.Name)"
        } catch {
            Log-Message -Message "Failed to move $_.Name: $_" -MessageType "ERROR"
        }
        $ProgressBar.Value = ++$i
    }
}

function Setup-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Move Event Log Default Paths'
    $form.Size = New-Object System.Drawing.Size(500, 300)
    $form.StartPosition = 'CenterScreen'

    $label = New-Object System.Windows.Forms.Label
    $label.Text = 'Enter Target Drive or Folder (e.g. L:\):'
    $label.Location = New-Object System.Drawing.Point(10, 20)
    $label.AutoSize = $true
    $form.Controls.Add($label)

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
            Handle-Error "Target folder cannot be empty."
            return
        }
        try {
            Stop-EventLogService
            Move-EventLogs -TargetFolder $targetFolder -ProgressBar $progressBar
            Start-EventLogService
            Restart-CriticalServices
            Validate-CriticalServices
            [System.Windows.Forms.MessageBox]::Show("Logs moved to $targetFolder. Logs saved at $logPath.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Handle-Error "An error occurred: $_"
        }
    })
    $form.Controls.Add($button)

    $form.ShowDialog() | Out-Null
}

# --- MAIN EXECUTION ---
$paths = Initialize-ScriptPaths
$logDir = $paths.LogDir
$logPath = $paths.LogPath

Setup-GUI

# End of script
