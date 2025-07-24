<#
.SYNOPSIS
    PowerShell Script for Detecting Empty DNS Reverse Lookup Zones.

.DESCRIPTION
    This script detects and identifies empty DNS reverse lookup zones, assisting in DNS 
    cleanup and ensuring proper zone configuration for efficient network operation.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
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

# Import necessary libraries for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Show-ErrorMessage "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Show-ErrorMessage "Failed to write to log: $_"
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display informational messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Automatically gather the FQDN of the machine
$dnsServerFQDN = [System.Net.Dns]::GetHostByName(($env:COMPUTERNAME)).HostName

# Create the main form
$form = New-Object system.Windows.Forms.Form
$form.Text = "DNS Reverse Lookup Zone Manager"
$form.Size = New-Object System.Drawing.Size(550, 360)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# Create and add a DNS Server label and textbox
$dnsLabel = New-Object system.Windows.Forms.Label
$dnsLabel.Text = "DNS Server:"
$dnsLabel.Location = New-Object System.Drawing.Point(20, 20)
$dnsLabel.Size = New-Object System.Drawing.Size(80, 20)
$form.Controls.Add($dnsLabel)

$dnsTextBox = New-Object system.Windows.Forms.TextBox
$dnsTextBox.Location = New-Object System.Drawing.Point(120, 20)
$dnsTextBox.Size = New-Object System.Drawing.Size(400, 20)
$dnsTextBox.Text = $dnsServerFQDN
$form.Controls.Add($dnsTextBox)

# Create and add a TextBox to display found empty zones
$emptyZonesTextBox = New-Object system.Windows.Forms.TextBox
$emptyZonesTextBox.Location = New-Object System.Drawing.Point(20, 60)
$emptyZonesTextBox.Size = New-Object System.Drawing.Size(500, 200)
$emptyZonesTextBox.Multiline = $true
$emptyZonesTextBox.ScrollBars = "Vertical"
$emptyZonesTextBox.ReadOnly = $true
$form.Controls.Add($emptyZonesTextBox)

# Create and add a Start button
$startButton = New-Object system.Windows.Forms.Button
$startButton.Text = "Start"
$startButton.Location = New-Object System.Drawing.Point(20, 280)
$startButton.Size = New-Object System.Drawing.Size(100, 30)
$form.Controls.Add($startButton)

# Create and add an Exclude Empty Zones button
$excludeButton = New-Object system.Windows.Forms.Button
$excludeButton.Text = "Exclude Empty Zones"
$excludeButton.Location = New-Object System.Drawing.Point(130, 280)
$excludeButton.Size = New-Object System.Drawing.Size(150, 30)
$excludeButton.Enabled = $false
$form.Controls.Add($excludeButton)

# Create and add a Close button
$closeButton = New-Object system.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(290, 280)
$closeButton.Size = New-Object System.Drawing.Size(100, 30)
$form.Controls.Add($closeButton)

$closeButton.Add_Click({
        $form.Close()
    })

# Add an event handler for the Start button
$startButton.Add_Click({
        $dnsServer = $dnsTextBox.Text
        $emptyZonesTextBox.Clear()

        if ([string]::IsNullOrWhiteSpace($dnsServer)) {
            Show-ErrorMessage "Please provide a DNS server."
            return
        }

        # Disable buttons
        $startButton.Enabled = $false
        $excludeButton.Enabled = $false
        $closeButton.Enabled = $false

        # Ensure DNS Server module is loaded
        if (-not (Get-Module -Name DNSServer)) {
            Import-Module DNSServer
        }

        # Initialize an array to hold empty zones
        $emptyZones = @()

        # Log the start of the process
        Log-Message "DNS Reverse Lookup Zones Search Started"

        # Function to check if a DNS reverse lookup zone is empty
        function Check-ZoneEmpty {
            param (
                [string]$zoneName
            )
    
            # Get all records for the zone
            try {
                $records = Get-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $dnsServer -ErrorAction Stop
            } catch {
                Log-Message "Error retrieving records for zone ${zoneName}: $($_.Exception.Message)" -MessageType "ERROR"
                return $false
            }

            # Check if the zone contains only static records (without timestamps)
            $containsTimestampedRecords = $false
            $recordCount = $records.Count

            if ($recordCount -eq 0) {
                Log-Message "Zone ${zoneName} is completely empty (no records found)." -MessageType "INFO"
                $emptyZonesTextBox.AppendText("Zone ${zoneName} is completely empty.`r`n")
                return $true
            }

            foreach ($record in $records) {
                if ($record.TimeStamp -ne $null) { # Records with a timestamp are dynamic
                    $containsTimestampedRecords = $true
                    break
                }
            }

            # A zone is only considered empty if it contains no timestamped records
            if (-not $containsTimestampedRecords) {
                Log-Message "Empty zone found: $($zoneName)" -MessageType "INFO"
                $emptyZonesTextBox.AppendText("Empty zone found: $($zoneName)`r`n")
                return $true
            } else {
                return $false
            }
        }

        # Get all zones
        try {
            $zones = Get-DnsServerZone -ComputerName $dnsServer -ErrorAction Stop
        } catch {
            $zoneError = "Error retrieving DNS zones: $($_.Exception.Message)"
            Log-Message $zoneError -MessageType "ERROR"
            Show-ErrorMessage $zoneError
            $startButton.Enabled = $true
            $excludeButton.Enabled = $false
            $closeButton.Enabled = $true
            return
        }

        # Filter only reverse lookup zones
        $reverseLookupZones = $zones | Where-Object { $_.IsReverseLookupZone -eq $true }

        # Check each reverse lookup zone for being empty and add to the emptyZones array
        foreach ($zone in $reverseLookupZones) {
            if (Check-ZoneEmpty -zoneName $zone.ZoneName) {
                $emptyZones += $zone.ZoneName
            }
        }

        # Log the completion and summary
        if ($emptyZones.Count -gt 0) {
            foreach ($zone in $emptyZones) {
                Log-Message "Empty zone identified: $zone" -MessageType "INFO"
            }
            $excludeButton.Enabled = $true
        } else {
            Log-Message "No empty zones were found." -MessageType "INFO"
            $emptyZonesTextBox.AppendText("No empty zones were found.`r`n")
        }

        Log-Message "DNS Reverse Lookup Zones Search Completed"

        # Show final message with log file path
        Show-InfoMessage "Process completed. Log file saved to $logPath"

        # Re-enable buttons
        $startButton.Enabled = $true
        $closeButton.Enabled = $true
    })

# Add an event handler for the Exclude Empty Zones button
$excludeButton.Add_Click({
        $dnsServer = $dnsTextBox.Text

        if ($emptyZones.Count -eq 0) {
            Show-InfoMessage "No empty zones to exclude."
            return
        }

        # Confirm exclusion action
        $confirmResult = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to exclude all identified empty zones?", "Confirm Exclusion", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirmResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            foreach ($zone in $emptyZones) {
                try {
                    Remove-DnsServerZone -Name $zone -ComputerName $dnsServer -Force -ErrorAction Stop
                    Log-Message "Excluded empty zone: $zone" -MessageType "INFO"
                    $emptyZonesTextBox.AppendText("Excluded empty zone: $zone`r`n")
                } catch {
                    Log-Message "Error excluding zone ${zone}: $($_.Exception.Message)" -MessageType "ERROR"
                    Show-ErrorMessage "Error excluding zone ${zone}: $($_.Exception.Message)"
                }
            }
            Show-InfoMessage "Exclusion of empty zones completed. Log file saved to $logPath"
        }
    })

# Show the form
$form.ShowDialog()

# End of Script
