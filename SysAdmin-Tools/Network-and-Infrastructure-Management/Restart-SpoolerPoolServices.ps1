<#
.SYNOPSIS
    PowerShell Script to Restart Spooler and LPD Services with Enhanced GUI, Logging, and Debug Information.

.DESCRIPTION
    This script provides a user-friendly GUI to restart both the Spooler and LPD (Line Printer Daemon) 
    services. It includes enhanced logging for auditing purposes and detailed debug information 
    for troubleshooting. The script ensures smooth management of printing services while tracking 
    actions taken during its execution.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 16, 2024
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
}
"@
[Window]::Hide()

# Enhanced logging function with error handling and validation
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
        # Ensure the log path exists, create if necessary
        if (-not (Test-Path $global:logDir)) {
            New-Item -Path $global:logDir -ItemType Directory -ErrorAction Stop
        }
        # Attempt to write to the log file
        Add-Content -Path $global:logPath -Value $logEntry -ErrorAction Stop
    } catch {
        # Fallback: Log to console if writing to the log file fails
        Write-Error "Failed to write to log: $_"
        Write-Output $logEntry
    }

    # Add log entry to listBox (GUI) if available
    if ($global:listBox) {
        $global:listBox.Items.Add($logEntry)
    }
}

# Unified error handling function
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Log-Message -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to initialize script name and file paths
function Initialize-ScriptPaths {
    param (
        [string]$defaultLogDir = 'C:\Logs-TEMP'
    )

    # Determine script name and set up file paths dynamically based on the calling script
    $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.PSCommandPath)
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    # Set log path allowing dynamic configuration or fallback to defaults
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $defaultLogDir }
    $logFileName = "${scriptName}-${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    return @{
        LogDir = $logDir
        LogPath = $logPath
        ScriptName = $scriptName
    }
}

# Initialize paths for logging and directories
$paths = Initialize-ScriptPaths
$global:logDir = $paths.LogDir
$global:logPath = $paths.LogPath

# Log directory and path verification
Log-Message -Message "DEBUG: Log directory verified: $global:logDir"

# Load the required assemblies for Windows Forms and Drawing
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Log-Message -Message "DEBUG: Loaded System.Windows.Forms and System.Drawing assemblies."
} catch {
    Handle-Error "Failed to load necessary assemblies for GUI: $($_.Exception.Message)"
    exit 1
}

# Debug: Log startup
Log-Message -Message "DEBUG: Script started."

# Ensure required module is loaded (needed for AD-related cmdlets)
if (-not (Get-Module -Name ActiveDirectory)) {
    try {
        Log-Message -Message "DEBUG: Importing ActiveDirectory module."
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Log-Message -Message "ERROR: Failed to import the Active Directory module."
        exit 1
    }
}

# Ensure DHCP Server Tools are installed (needed for Get-DhcpServerInDC)
if (-not (Get-Command -Name Get-DhcpServerInDC -ErrorAction SilentlyContinue)) {
    try {
        Log-Message -Message "DEBUG: Importing DHCP Server module."
        Import-Module DhcpServer -ErrorAction Stop
    } catch {
        Log-Message -Message "ERROR: Failed to import the DHCP Server module."
        exit 1
    }
}

# Function to gather all authorized DHCP servers from Active Directory
function Get-ForestServers {
    try {
        Log-Message -Message "DEBUG: Gathering DHCP servers from Active Directory."
        $dhcpServers = Get-DhcpServerInDC | Select-Object -ExpandProperty DNSName

        # Remove any null, empty entries, and duplicates (case-insensitive)
        $dhcpServers = $dhcpServers | Where-Object { $_ -and $_.Trim() -ne "" } | Sort-Object -Unique

        return $dhcpServers
    } catch {
        Handle-Error "Failed to retrieve DHCP servers: $($_.Exception.Message)"
        return @() # Return an empty array if the query fails
    }
}

# Function to restart the Spooler and LPD services on a selected server
function Restart-PrintServices {
    param (
        [string]$serverName
    )
    $spoolerServiceName = "Spooler"
    $lpdServiceName = "LPDSVC"

    Log-Message -Message "DEBUG: Starting service restart on $serverName."

    try {
        Invoke-Command -ComputerName $serverName -ScriptBlock {
            param ($spoolerServiceName, $lpdServiceName)

            # Get Spooler service and its dependent services
            $spoolerService = Get-Service -Name $spoolerServiceName
            $dependentServices = $spoolerService.DependentServices

            # Stop dependent services
            foreach ($dependentService in $dependentServices) {
                if ($dependentService.Status -ne 'Stopped') {
                    Stop-Service -Name $dependentService.Name -Force
                }
            }

            # Stop and restart the Spooler service
            if ($spoolerService.Status -ne 'Stopped') {
                Stop-Service -Name $spoolerServiceName -Force
            }
            Start-Service -Name $spoolerServiceName

            # Restart dependent services if necessary
            foreach ($dependentService in $dependentServices) {
                $currentStatus = Get-Service -Name $dependentService.Name
                if ($currentStatus.Status -ne 'Running' -and $currentStatus.StartType -ne 'Disabled') {
                    Start-Service -Name $dependentService.Name
                }
            }

            # Check and restart the LPD service if it exists
            try {
                $lpdService = Get-Service -Name $lpdServiceName -ErrorAction Stop
                if ($lpdService.Status -ne 'Stopped') {
                    Stop-Service -Name $lpdServiceName -Force
                }
                Start-Service -Name $lpdServiceName
            } catch {
                Write-Host "LPD service ($lpdServiceName) not found on $serverName. Skipping LPD operations."
            }

        } -ArgumentList $spoolerServiceName, $lpdServiceName -ErrorAction Stop
        
        Log-Message "Spooler and LPD services restarted successfully on ${serverName}."
        [System.Windows.Forms.MessageBox]::Show("Spooler and LPD services restarted successfully on $serverName!", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Handle-Error "An error occurred while restarting services on ${serverName}: $($_.Exception.Message)"
    }
}

# Function to create the graphical user interface (GUI)
function Create-GUI {
    try {
        Log-Message -Message "DEBUG: Creating GUI."
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Restart Spooler & LPD Services'
        $form.Size = New-Object System.Drawing.Size(500, 400)
        $form.StartPosition = 'CenterScreen'
        
        # Title Label
        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = 'Manage Print Services'
        $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
        $lblTitle.Size = New-Object System.Drawing.Size(300, 30)
        $lblTitle.Location = New-Object System.Drawing.Point(100, 10)
        $form.Controls.Add($lblTitle)

        # Server Label
        $lblServer = New-Object System.Windows.Forms.Label
        $lblServer.Text = 'Select Server:'
        $lblServer.Location = New-Object System.Drawing.Point(30, 60)
        $form.Controls.Add($lblServer)
        
        # ComboBox to select a server
        $comboBoxServers = New-Object System.Windows.Forms.ComboBox
        $comboBoxServers.Location = New-Object System.Drawing.Point(140, 60)
        $comboBoxServers.Size = New-Object System.Drawing.Size(300, 20)
        $comboBoxServers.DropDownStyle = 'DropDownList'
        
        # Populate ComboBox with the list of DHCP servers
        $servers = Get-ForestServers
        if ($servers.Count -eq 0) {
            Log-Message -Message "ERROR: No servers found in Active Directory."
            Handle-Error "No servers found in Active Directory."
            return
        }
        $comboBoxServers.Items.AddRange($servers)
        $comboBoxServers.SelectedIndex = 0
        $form.Controls.Add($comboBoxServers)

        # Restart Button
        $btnRestart = New-Object System.Windows.Forms.Button
        $btnRestart.Text = 'Restart Spooler & LPD Services'
        $btnRestart.Location = New-Object System.Drawing.Point(30, 100)
        $btnRestart.Size = New-Object System.Drawing.Size(400, 30)
        $btnRestart.Add_Click({
                $selectedServer = $comboBoxServers.SelectedItem
                if ($selectedServer) {
                    $listBox.Items.Clear()
                    Restart-PrintServices -serverName $selectedServer
                } else {
                    Log-Message -Message "ERROR: No server selected."
                    Handle-Error "Please select a server."
                }
            })
        $form.Controls.Add($btnRestart)

        # ListBox to display logs
        $listBox = New-Object System.Windows.Forms.ListBox
        $listBox.Location = New-Object System.Drawing.Point(30, 140)
        $listBox.Size = New-Object System.Drawing.Size(400, 150)
        $form.Controls.Add($listBox)
        $global:listBox = $listBox

        # Exit Button
        $btnExit = New-Object System.Windows.Forms.Button
        $btnExit.Text = 'Exit'
        $btnExit.Location = New-Object System.Drawing.Point(350, 320)
        $btnExit.Size = New-Object System.Drawing.Size(80, 30)
        $btnExit.Add_Click({ $form.Close() })
        $form.Controls.Add($btnExit)

        $form.ShowDialog()
    } catch {
        Log-Message -Message "ERROR: Failed to initialize GUI: $($_.Exception.Message)"
    }
}

# Start the GUI
Create-GUI

# End of script
