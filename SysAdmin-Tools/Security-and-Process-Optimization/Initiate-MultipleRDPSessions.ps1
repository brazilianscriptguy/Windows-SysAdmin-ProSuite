<#
.SYNOPSIS
    PowerShell Script for Initiating Multiple RDP Sessions Simultaneously.

.DESCRIPTION
    This script enables the initiation of multiple Remote Desktop Protocol (RDP) sessions 
    to different servers simultaneously, improving remote management capabilities for IT administrators.

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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name and set up logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$LogLevel = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$LogLevel] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Log the start of the script
Log-Message "Starting Multiple RDP Access script."

# Function to create GUI for file path input or manual server entry
function Get-ServerList {
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Multiple RDP Access'
    $form.Size = New-Object System.Drawing.Size(500, 250)
    $form.StartPosition = 'CenterScreen'

    # Add description label
    $labelDescription = New-Object System.Windows.Forms.Label
    $labelDescription.Location = New-Object System.Drawing.Point(10, 10)
    $labelDescription.Size = New-Object System.Drawing.Size(480, 20)
    $labelDescription.Text = "Provide the Machine Address:"
    $form.Controls.Add($labelDescription)

    # Radio Buttons for input type selection
    $radioFile = New-Object System.Windows.Forms.RadioButton
    $radioFile.Location = New-Object System.Drawing.Point(10, 35)
    $radioFile.Size = New-Object System.Drawing.Size(480, 20)
    $radioFile.Text = 'Select a .TXT file containing IP Addresses or FQDNs'
    $radioFile.Checked = $true
    $form.Controls.Add($radioFile)

    $radioManual = New-Object System.Windows.Forms.RadioButton
    $radioManual.Location = New-Object System.Drawing.Point(10, 60)
    $radioManual.Size = New-Object System.Drawing.Size(480, 20)
    $radioManual.Text = 'Enter IP Addresses/FQDNs separated by commas'
    $form.Controls.Add($radioManual)

    # Add the file path textbox and browse button
    $textBoxFile = New-Object System.Windows.Forms.TextBox
    $textBoxFile.Location = New-Object System.Drawing.Point(10, 90)
    $textBoxFile.Size = New-Object System.Drawing.Size(360, 20)
    $form.Controls.Add($textBoxFile)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Location = New-Object System.Drawing.Point(380, 88)
    $browseButton.Size = New-Object System.Drawing.Size(100, 23)
    $browseButton.Text = 'Browse'
    $browseButton.Add_Click({
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "Text Files (*.txt)|*.txt"
            if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $textBoxFile.Text = $openFileDialog.FileName
            }
        })
    $form.Controls.Add($browseButton)

    # Add the manual entry textbox
    $textBoxManual = New-Object System.Windows.Forms.TextBox
    $textBoxManual.Location = New-Object System.Drawing.Point(10, 120)
    $textBoxManual.Size = New-Object System.Drawing.Size(470, 20)
    $form.Controls.Add($textBoxManual)

    # Toggle visibility based on the selected radio button
    $radioFile.Add_CheckedChanged({
            $textBoxFile.Visible = $true
            $browseButton.Visible = $true
            $textBoxManual.Visible = $false
        })
    $radioManual.Add_CheckedChanged({
            $textBoxFile.Visible = $false
            $browseButton.Visible = $false
            $textBoxManual.Visible = $true
        })

    # Add the submit button
    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Location = New-Object System.Drawing.Point(190, 180)
    $submitButton.Size = New-Object System.Drawing.Size(75, 23)
    $submitButton.Text = 'Submit'
    $submitButton.Add_Click({
            if ($radioFile.Checked -and [string]::IsNullOrWhiteSpace($textBoxFile.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Please select a .TXT file.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                Log-Message "No file selected." "ERROR"
            } elseif ($radioManual.Checked -and [string]::IsNullOrWhiteSpace($textBoxManual.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Please provide IP Addresses or FQDNs.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                Log-Message "No IP Addresses/FQDNs provided." "ERROR"
            } else {
                if ($radioFile.Checked) {
                    $filePath = $textBoxFile.Text
                    if (-not (Test-Path $filePath)) {
                        [System.Windows.Forms.MessageBox]::Show("The specified file was not found: $filePath", "File Not Found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        Log-Message "File not found: $filePath" "ERROR"
                    } else {
                        Log-Message "Server list file selected: $filePath"
                        $servers = Get-Content -Path $filePath
                        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    }
                } elseif ($radioManual.Checked) {
                    $servers = $textBoxManual.Text -split ',\s*'
                    if ($servers.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No valid IP Addresses or FQDNs provided.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        Log-Message "No valid IP Addresses or FQDNs provided in manual entry." "ERROR"
                    } else {
                        Log-Message "Manual entry of IP Addresses/FQDNs: $($textBoxManual.Text)"
                        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    }
                }
            }
        })
    $form.Controls.Add($submitButton)

    # Add the close button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(275, 180)
    $closeButton.Size = New-Object System.Drawing.Size(75, 23)
    $closeButton.Text = 'Close'
    $closeButton.Add_Click({
            Log-Message "Script execution cancelled by the user." "INFO"
            $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $form.Close()
        })
    $form.Controls.Add($closeButton)

    # Initialize visibility states
    $textBoxFile.Visible = $true
    $browseButton.Visible = $true
    $textBoxManual.Visible = $false

    # Show the form
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $servers
    } else {
        Log-Message "Script execution cancelled by the user." "INFO"
        return @()
    }
}

# Main execution loop
$continueScript = $true
while ($continueScript) {
    # Get the list of servers from either the file or manual entry
    $servers = Get-ServerList

    # Exit the loop if the form was cancelled
    if ($servers.Count -eq 0) {
        $continueScript = $false
        break
    }

    # Loop through the list of servers and start Remote Desktop sessions
    foreach ($server in $servers) {
        if ([string]::IsNullOrWhiteSpace($server)) {
            Log-Message "Skipped empty or whitespace server entry." "WARNING"
            continue
        }

        if ($server -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' -or $server -match '^(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$') {
            Log-Message "Initiating RDP session to: $server"
            Start-Process -FilePath "mstsc" -ArgumentList "/v:$server" -Wait
        } else {
            [System.Windows.Forms.MessageBox]::Show("Invalid IP Address or FQDN: $server", "Invalid Entry", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            Log-Message "Invalid IP Address or FQDN: $server" "ERROR"
        }
    }

    # End of the main loop
    break
}

Log-Message "Multiple RDP Access script finished."
# End of script
