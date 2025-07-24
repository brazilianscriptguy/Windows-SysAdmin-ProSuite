<#
.SYNOPSIS
    PowerShell Script for Uninstalling Non-Compliant Software from Workstations.

.DESCRIPTION
    This script uninstalls multiple software applications based on a list provided in a 
    .TXT file. It logs all actions, handles errors gracefully, and allows users to execute, 
    cancel, or close the uninstallation process. It ensures software compliance across 
    workstations by removing unauthorized applications.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

# Hide the PowerShell console window
try {
    # Try to access the class to check if it exists
    [ConsoleWindowHelper] | Out-Null
} catch {
    # If the class doesn't exist, define it
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ConsoleWindowHelper {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetConsoleWindow();
    
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
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
}

# Hide the console window
[ConsoleWindowHelper]::Hide()

# Import Necessary Assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.ComponentModel

# Set up Logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at $logDir. Logging will not be possible.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
}

# Logging function
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
        # If logging fails, notify the user
        [System.Windows.Forms.MessageBox]::Show("Failed to write to log: $_", "Logging Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $message" -MessageType "ERROR"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$message)
    [System.Windows.Forms.MessageBox]::Show($message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $message" -MessageType "INFO"
}

# Function to Load Software Names from a .TXT File
function Load-SoftwareList {
    param (
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Log-Message "The software list file '$FilePath' was not found." -MessageType "ERROR"
        throw "The software list file '$FilePath' was not found."
    }

    try {
        $softwareNames = Get-Content -Path $FilePath -ErrorAction Stop | Where-Object { $_.Trim() -ne "" }
        if ($softwareNames.Count -eq 0) {
            Log-Message "The software list file '$FilePath' is empty." -MessageType "WARNING"
            throw "The software list file '$FilePath' is empty."
        }
        return $softwareNames
    } catch {
        Log-Message "Failed to load software names from file '$FilePath'. Error: $_" -MessageType "ERROR"
        throw "Failed to load software names."
    }
}

# Function to Retrieve Installed Programs
function Get-InstalledPrograms {
    Log-Message "Retrieving the list of installed programs."
    $installedPrograms64Bit = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, UninstallString, @{Name = "Architecture"; Expression = { "64-bit" } }

    $installedPrograms32Bit = Get-ItemProperty -Path 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, UninstallString, @{Name = "Architecture"; Expression = { "32-bit" } }

    return $installedPrograms64Bit + $installedPrograms32Bit
}

# Function to Execute the Uninstall Command
function Execute-UninstallCommand {
    param (
        [string]$UninstallCommand,
        [string]$SoftwareName
    )

    try {
        if ($UninstallCommand -like "*msiexec*") {
            # Modify msiexec command for silent uninstallation
            $uninstallCommand = $UninstallCommand -replace "msiexec.exe", "msiexec.exe /quiet /norestart"
            $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -PassThru -NoNewWindow
        } else {
            # Add silent flags for other uninstallers if necessary
            $uninstallCommand = "$UninstallCommand /S"
            $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -PassThru -NoNewWindow
        }

        if ($processInfo -and $processInfo.ExitCode -ne 0) {
            Log-Message "Error uninstalling '$SoftwareName' with exit code: $($processInfo.ExitCode)" -MessageType "ERROR"
        } elseif ($processInfo) {
            Log-Message "'$SoftwareName' was successfully uninstalled silently." -MessageType "INFO"
        } else {
            Log-Message "No uninstall method found for '$SoftwareName'." -MessageType "WARNING"
        }
    } catch {
        Log-Message "Error executing uninstall command for '$SoftwareName': $_" -MessageType "ERROR"
    }
}

# Function to Uninstall Software
function Uninstall-Software {
    param (
        [string[]]$SoftwareNames,
        [System.ComponentModel.BackgroundWorker]$backgroundWorker
    )

    $installedPrograms = Get-InstalledPrograms

    $totalSoftware = $SoftwareNames.Count
    $currentCount = 0
    $handledCount = 0
    $softwareFound = $false  # Flag to track if any software was found and handled

    foreach ($name in $SoftwareNames) {
        if ($backgroundWorker.CancellationPending) {
            Log-Message "Process canceled by user." -MessageType "INFO"
            break
        }

        # Find the software in the installed programs
        $application = $installedPrograms | Where-Object { $_.DisplayName -like "*$name*" }

        if ($application) {
            $softwareFound = $true
            Log-Message "Software found for removal: $($application.DisplayName)" -MessageType "INFO"
            $uninstallCommand = $application.UninstallString
            if ($uninstallCommand) {
                Execute-UninstallCommand -UninstallCommand $uninstallCommand -SoftwareName $application.DisplayName
                $handledCount++
            } else {
                Log-Message "No uninstall string found for '$($application.DisplayName)'." -MessageType "WARNING"
            }
        } else {
            Log-Message "Software not found: $name" -MessageType "WARNING"
        }

        $currentCount++

        # Calculate progress percentage
        $percentComplete = [math]::Round( ($currentCount / $totalSoftware) * 100 )

        # Report progress
        $message = "Processing $currentCount of ${totalSoftware}: $name"
        $backgroundWorker.ReportProgress($percentComplete, $message)
    }

    if (-not $softwareFound) {
        Log-Message "No software found for uninstallation." -MessageType "INFO"
        $backgroundWorker.ReportProgress(100, "No software found for uninstallation.")
    } else {
        Log-Message "Uninstallation process completed." -MessageType "INFO"
    }
}

# Function to Start the Uninstallation Process
function Start-UninstallProcess {
    param (
        [string]$softwareListPath,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$statusLabel,
        [System.Windows.Forms.Button]$executeButton,
        [System.Windows.Forms.Button]$cancelButton,
        [System.Windows.Forms.ListView]$listView
    )

    # Initialize BackgroundWorker
    $backgroundWorker = New-Object System.ComponentModel.BackgroundWorker
    $backgroundWorker.WorkerReportsProgress = $true
    $backgroundWorker.WorkerSupportsCancellation = $true

    # Define DoWork event
    $backgroundWorker.Add_DoWork({
            param ($sender, $e)
            try {
                $softwareNames = Load-SoftwareList -FilePath $e.Argument
                Uninstall-Software -SoftwareNames $softwareNames -backgroundWorker $sender
            } catch {
                Log-Message "Error in DoWork: $_" -MessageType "ERROR"
                $e.Result = $_
            }
        })

    # Define ProgressChanged event
    $backgroundWorker.Add_ProgressChanged({
            param ($sender, $e)
            $progressBar.Value = $e.ProgressPercentage
            $statusLabel.Text = $e.UserState
        })

    # Define RunWorkerCompleted event
    $backgroundWorker.Add_RunWorkerCompleted({
            param ($sender, $e)
            if ($e.Cancelled) {
                $statusLabel.Text = "Process canceled."
                Log-Message "Process was canceled by user." -MessageType "INFO"
            } elseif ($e.Error) {
                $statusLabel.Text = "Error occurred: $($e.Error.Message)"
                Log-Message "Error occurred: $($e.Error.Message)" -MessageType "ERROR"
            } elseif ($e.Result -is [Exception]) {
                $statusLabel.Text = "Error occurred: $($e.Result.Message)"
                Log-Message "Error occurred: $($e.Result.Message)" -MessageType "ERROR"
            } else {
                $statusLabel.Text = "Process completed successfully."
                Log-Message "Script execution completed successfully." -MessageType "INFO"
            }
            $executeButton.Enabled = $true
            $cancelButton.Enabled = $false
        })

    # Start the BackgroundWorker
    $backgroundWorker.RunWorkerAsync($softwareListPath)

    # Enable the cancel button
    $cancelButton.Enabled = $true

    # Define Click event for the Cancel button
    $cancelButton.Add_Click({
            $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to cancel the process?", "Cancel Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                if ($backgroundWorker.IsBusy) {
                    $backgroundWorker.CancelAsync()
                    $statusLabel.Text = "Canceling process..."
                    Log-Message "User requested to cancel the process." -MessageType "INFO"
                }
            }
        })
}

# Function to Create and Show the GUI
function Show-GUI {
    # Create and configure the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Software Uninstaller from a List"
    $form.Size = New-Object System.Drawing.Size(640, 630)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

    # Create and configure the TabControl
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(600, 550)
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)

    # Create the Uninstall Software tab
    $tabUninstall = New-Object System.Windows.Forms.TabPage
    $tabUninstall.Text = "Uninstall Software"

    # Add controls to the Uninstall Software tab
    # Label to select the .txt file
    $labelSoftwareList = New-Object System.Windows.Forms.Label
    $labelSoftwareList.Location = New-Object System.Drawing.Point(10, 20)
    $labelSoftwareList.Size = New-Object System.Drawing.Size(580, 20)
    $labelSoftwareList.Text = "Select the .TXT file containing the software names:"
    $tabUninstall.Controls.Add($labelSoftwareList)

    # TextBox for the .txt file path
    $textBoxSoftwareList = New-Object System.Windows.Forms.TextBox
    $textBoxSoftwareList.Location = New-Object System.Drawing.Point(10, 50)
    $textBoxSoftwareList.Size = New-Object System.Drawing.Size(450, 20)
    $tabUninstall.Controls.Add($textBoxSoftwareList)

    # Execute, Cancel, Browse, and Close buttons aligned on the same line
    # Browse Button
    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Location = New-Object System.Drawing.Point(10, 80)
    $browseButton.Size = New-Object System.Drawing.Size(120, 30)
    $browseButton.Text = "Browse"
    $tabUninstall.Controls.Add($browseButton)

    # Execute Button
    $executeButton = New-Object System.Windows.Forms.Button
    $executeButton.Location = New-Object System.Drawing.Point(140, 80)
    $executeButton.Size = New-Object System.Drawing.Size(120, 30)
    $executeButton.Text = "Execute"
    $tabUninstall.Controls.Add($executeButton)

    # Cancel Button
    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(270, 80)
    $cancelButton.Size = New-Object System.Drawing.Size(120, 30)
    $cancelButton.Text = "Cancel"
    $cancelButton.Enabled = $false
    $tabUninstall.Controls.Add($cancelButton)

    # Close Button
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Location = New-Object System.Drawing.Point(400, 80)
    $closeButton.Size = New-Object System.Drawing.Size(120, 30)
    $closeButton.Text = "Close"
    $tabUninstall.Controls.Add($closeButton)

    # ProgressBar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 130)
    $progressBar.Size = New-Object System.Drawing.Size(580, 20)
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $tabUninstall.Controls.Add($progressBar)

    # Status Label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 160)
    $statusLabel.Size = New-Object System.Drawing.Size(580, 20)
    $statusLabel.Text = "Status: Idle"
    $tabUninstall.Controls.Add($statusLabel)

    # ListView to display matched installed software
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(10, 190)
    $listView.Size = New-Object System.Drawing.Size(580, 350)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.Columns.Add("Software Name", 300)
    $listView.Columns.Add("Version", 100)
    $listView.Columns.Add("Architecture", 100)
    $listView.CheckBoxes = $true
    $tabUninstall.Controls.Add($listView)

    # Define Click event for the Browse button
    $browseButton.Add_Click({
            $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $fileDialog.Filter = "Text files (*.txt)|*.txt"
            if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $textBoxSoftwareList.Text = $fileDialog.FileName
            }
        })

    # Define Click event for Execute button
    $executeButton.Add_Click({
            $softwareListPath = $textBoxSoftwareList.Text.Trim()
            if ($softwareListPath -and (Test-Path $softwareListPath)) {
                $executeButton.Enabled = $false
                $cancelButton.Enabled = $true
                $statusLabel.Text = "Starting uninstallation process..."
                $progressBar.Value = 0
                $listView.Items.Clear()

                try {
                    $softwareNames = Load-SoftwareList -FilePath $softwareListPath
                    $installedPrograms = Get-InstalledPrograms
                    $matchedPrograms = @()

                    foreach ($name in $softwareNames) {
                        $matched = $installedPrograms | Where-Object { $_.DisplayName -like "*$name*" }
                        if ($matched) {
                            foreach ($app in $matched) {
                                $matchedPrograms += $app
                                # Add to ListView
                                $listItem = New-Object System.Windows.Forms.ListViewItem
                                $listItem.Text = $app.DisplayName
                                $listItem.SubItems.Add($app.DisplayVersion)
                                $listItem.SubItems.Add($app.Architecture)
                                $listView.Items.Add($listItem)
                            }
                        } else {
                            Log-Message "Software not found: $name" -MessageType "WARNING"
                        }
                    }

                    if ($matchedPrograms.Count -eq 0) {
                        Show-InfoMessage "No matching installed software found for the provided list."
                        $statusLabel.Text = "Status: No matches found."
                        $executeButton.Enabled = $true
                        $cancelButton.Enabled = $false
                    } else {
                        Log-Message "$($matchedPrograms.Count) matching software(s) found for uninstallation."
                        $statusLabel.Text = "Status: Ready to uninstall."

                        # Start the uninstallation process in background
                        Start-UninstallProcess -softwareListPath $softwareListPath -progressBar $progressBar -statusLabel $statusLabel -executeButton $executeButton -cancelButton $cancelButton -listView $listView
                    }
                } catch {
                    Show-ErrorMessage $_.Exception.Message
                    $statusLabel.Text = "Status: An error occurred."
                    $executeButton.Enabled = $true
                    $cancelButton.Enabled = $false
                }
            } else {
                Show-ErrorMessage "Please provide a valid path to the software list file."
            }
        })

    # Add the Uninstall Software tab to the TabControl
    $tabControl.TabPages.Add($tabUninstall)

    # Add the TabControl to the form
    $form.Controls.Add($tabControl)

    # Define Click event for Close button
    $closeButton.Add_Click({
            $form.Close()
        })

    # Show the form
    [System.Windows.Forms.Application]::Run($form)
}

# Start the GUI
Show-GUI

# Final Log Entry
Log-Message "Script execution finished." -MessageType "INFO"

# End of script
