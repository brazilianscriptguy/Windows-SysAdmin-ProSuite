<#
.SYNOPSIS
    PowerShell Script for Retrieving Disk Space Usage Data from Servers.

.DESCRIPTION
    This script collects disk space usage data from multiple AD servers, providing insights 
    into system health and ensuring compliance with storage capacity policies.

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

# Load necessary assemblies for Windows Forms and drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Disk Space Monitor'
$form.Size = New-Object System.Drawing.Size(800, 630)
$form.StartPosition = 'CenterScreen'

# Label for server input
$serverLabel = New-Object System.Windows.Forms.Label
$serverLabel.Location = New-Object System.Drawing.Point(10, 10)
$serverLabel.Size = New-Object System.Drawing.Size(240, 20)
$serverLabel.Text = 'FQDN Server Names (comma-separated):'
$form.Controls.Add($serverLabel)

# TextBox for server input
$serverInput = New-Object System.Windows.Forms.TextBox
$serverInput.Location = New-Object System.Drawing.Point(260, 10)
$serverInput.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($serverInput)

# DataGridView for displaying results
$dataGridView = New-Object System.Windows.Forms.DataGridView
$dataGridView.Location = New-Object System.Drawing.Point(10, 40)
$dataGridView.Size = New-Object System.Drawing.Size(760, 470)
$dataGridView.AutoSizeColumnsMode = 'Fill'
$dataGridView.Columns.AddRange(
    (New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{ Name = 'Server'; HeaderText = 'Server' }),
    (New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{ Name = 'Drive'; HeaderText = 'Drive' }),
    (New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{ Name = 'FreeSpace'; HeaderText = 'Free Space (GB)' }),
    (New-Object System.Windows.Forms.DataGridViewTextBoxColumn -Property @{ Name = 'TotalSpace'; HeaderText = 'Total Space (GB)' })
)
$form.Controls.Add($dataGridView)

# Progress bar to indicate the status of the disk usage check
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 520)
$progressBar.Size = New-Object System.Drawing.Size(760, 20)
$form.Controls.Add($progressBar)

# Function to fetch and display disk usage
function Update-DiskUsage {
    $dataGridView.Rows.Clear()
    $serverNames = $serverInput.Text.Trim() -split ','

    $totalServers = $serverNames.Count
    $progressBar.Maximum = $totalServers
    $currentServer = 0

    foreach ($serverName in $serverNames) {
        $currentServer++
        $progressBar.Value = $currentServer
        $serverName = $serverName.Trim()

        if (-not [string]::IsNullOrEmpty($serverName)) {
            try {
                $diskData = Invoke-Command -ComputerName $serverName -ScriptBlock {
                    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
                        [PSCustomObject]@{
                            Server = $env:COMPUTERNAME
                            Drive = $_.Name
                            FreeSpace = [math]::Round($_.Free / 1GB, 2)
                            TotalSpace = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
                        }
                    }
                }

                if ($diskData.Count -gt 0) {
                    foreach ($disk in $diskData) {
                        $row = $dataGridView.Rows.Add()
                        $dataGridView.Rows[$row].Cells[0].Value = $disk.Server
                        $dataGridView.Rows[$row].Cells[1].Value = $disk.Drive
                        $dataGridView.Rows[$row].Cells[2].Value = [decimal]$disk.FreeSpace
                        $dataGridView.Rows[$row].Cells[3].Value = [decimal]$disk.TotalSpace
                    }
                } else {
                    $row = $dataGridView.Rows.Add()
                    $dataGridView.Rows[$row].Cells[0].Value = $serverName
                    $dataGridView.Rows[$row].Cells[1].Value = 'No Drives'
                    $dataGridView.Rows[$row].Cells[2].Value = 'N/A'
                    $dataGridView.Rows[$row].Cells[3].Value = 'N/A'
                }

                # Add a separating line
                $separatorRow = $dataGridView.Rows.Add()
                $dataGridView.Rows[$separatorRow].Cells[0].Value = '---'
                $dataGridView.Rows[$separatorRow].Cells[1].Value = '---'
                $dataGridView.Rows[$separatorRow].Cells[2].Value = '---'
                $dataGridView.Rows[$separatorRow].Cells[3].Value = '---'

                Log-Message "Successfully retrieved disk usage for server: $serverName"
            } catch {
                $errorMsg = "Error retrieving disk usage for server: $serverName. $_"
                Log-Message $errorMsg
                Write-Error $errorMsg
            }
        } else {
            Write-Output "Please enter a valid FQDN server name."
        }
    }

    $progressBar.Value = 0
}

# Button to trigger disk usage check
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point(10, 550)
$button.Size = New-Object System.Drawing.Size(200, 30)
$button.Text = 'Check Disk Space'
$button.Add_Click({ Update-DiskUsage })
$form.Controls.Add($button)

# Show the form
$form.Add_Shown({ $form.Activate() })
[void] $form.ShowDialog()

# End of script
