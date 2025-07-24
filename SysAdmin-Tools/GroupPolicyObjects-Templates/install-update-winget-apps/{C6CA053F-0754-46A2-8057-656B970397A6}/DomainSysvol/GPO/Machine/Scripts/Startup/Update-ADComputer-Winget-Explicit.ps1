<#
.SYNOPSIS
    PowerShell Script for Updating Software on AD Computers via Winget.

.DESCRIPTION
    This script uses the winget tool to explicitly update software on workstations, 
    improving software management and ensuring that systems have the latest versions installed.

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
    if (![string]::IsNullOrWhiteSpace($Message)) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] $Message"
        try {
            Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
        } catch {
            Write-Error "Failed to write to log: $_"
        }
    } else {
        Write-Warning "Attempted to log an empty message."
    }
}

# Function to display progress
function Show-Progress {
    param (
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete
    )
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

# Function to find the winget executable path
function Find-WingetPath {
    param (
        [string]$SearchBase = "C:\Program Files\WindowsApps",
        [string]$SearchPattern = 'Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe'
    )

    try {
        Log-Message "Searching for winget executable..."
        $wingetPath = Get-ChildItem -Path $SearchBase -Filter 'winget.exe' -Recurse -ErrorAction Ignore |
            Where-Object { $_.FullName -like "*$SearchPattern" } |
            Select-Object -ExpandProperty FullName -First 1
        if ($wingetPath -and (Test-Path -Path $wingetPath -Type Leaf)) {
            Log-Message "winget found at: $wingetPath"
            return $wingetPath
        } else {
            throw "winget not found."
        }
    } catch {
        $errorMsg = "An error occurred while searching for winget: $($_.Exception.Message)"
        Log-Message $errorMsg
        return $null
    }
}

# Function to update software using winget
function Update-Software {
    param (
        [string]$WingetPath,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [System.Windows.Forms.Label]$StatusLabel,
        [ref]$CancelRequested,
        [System.Windows.Forms.Button]$StartButton,
        [System.Windows.Forms.Button]$CancelButton
    )

    try {
        Log-Message "Starting software updates with winget..."
        $StatusLabel.Text = "Preparing to update all packages..."
        $ProgressBar.Value = 10

        $wingetCommandQuery = "& `"$WingetPath`" upgrade --query"
        $wingetUpdateAvailable = Invoke-Expression $wingetCommandQuery | Out-String

        if ($wingetUpdateAvailable -match "No applicable updates found") {
            Log-Message "No updates available for any packages."
            $StatusLabel.Text = "No updates available for any packages."
        } else {
            $StatusLabel.Text = "Performing package updates..."
            $ProgressBar.Value = 50
            $wingetCommandUpgrade = "& `"$WingetPath`" upgrade --all --include-unknown --silent --accept-package-agreements --accept-source-agreements"
            $process = Start-Process -FilePath $WingetPath -ArgumentList "upgrade --all --include-unknown --silent --accept-package-agreements --accept-source-agreements" -PassThru -NoNewWindow -Wait
            while (!$process.HasExited) {
                if ($CancelRequested.Value) {
                    $process.Kill()
                    Log-Message "Update process canceled by user."
                    $StatusLabel.Text = "Update process canceled."
                    $ProgressBar.Value = 0
                    return
                }
                Start-Sleep -Milliseconds 500
            }

            Log-Message "All package updates completed successfully."
            $StatusLabel.Text = "All package updates completed successfully."
        }

        $ProgressBar.Value = 100
        Start-Sleep -Seconds 2
    } catch {
        $ProgressBar.Value = 100
        $errorMsg = "An error occurred during the software update process: $($_.Exception.Message)"
        Log-Message $errorMsg
        $StatusLabel.Text = $errorMsg
    } finally {
        $StartButton.Enabled = $true
        $CancelButton.Enabled = $false
    }
}

# Main script logic with GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Automate Software Updates'
$form.Size = New-Object System.Drawing.Size(400, 250)
$form.StartPosition = 'CenterScreen'

# Progress bar setup
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 70)
$progressBar.Size = New-Object System.Drawing.Size(360, 20)
$form.Controls.Add($progressBar)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 100)
$statusLabel.Size = New-Object System.Drawing.Size(360, 20)
$statusLabel.Text = ''
$form.Controls.Add($statusLabel)

# Variable to track cancellation status
$CancelRequested = $false

# Start button setup
$startButton = New-Object System.Windows.Forms.Button
$startButton.Location = New-Object System.Drawing.Point(10, 20)
$startButton.Size = New-Object System.Drawing.Size(170, 30)
$startButton.Text = 'Start Update'
$startButton.Add_Click({
        Log-Message "winget update process started by user."

        $CancelRequested = $false

        $wingetPath = Get-Command "winget" -ErrorAction SilentlyContinue

        if ($wingetPath) {
            Log-Message "winget found. Proceeding with the update."
            Update-Software -WingetPath $wingetPath -ProgressBar $progressBar -StatusLabel $statusLabel -CancelRequested ([ref]$CancelRequested) -StartButton $startButton -CancelButton $cancelButton
        } else {
            Log-Message "Winget is not installed or not found in the PATH. Attempting to find it..."
            $wingetPath = Find-WingetPath

            if ($wingetPath) {
                Update-Software -WingetPath $wingetPath -ProgressBar $progressBar -StatusLabel $statusLabel -CancelRequested ([ref]$CancelRequested) -StartButton $startButton -CancelButton $cancelButton
            } else {
                $statusLabel.Text = "winget not found. Please verify the installation and path."
                Log-Message "winget not found. Please verify the installation and path."
            }
        }
    })
$form.Controls.Add($startButton)

# Cancel button setup
$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(200, 20)
$cancelButton.Size = New-Object System.Drawing.Size(170, 30)
$cancelButton.Text = 'Cancel Update'
$cancelButton.Enabled = $false
$cancelButton.Add_Click({
        $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to cancel the update?", "Confirm Cancellation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $CancelRequested = $true
            Log-Message "User requested cancellation of update."
            $statusLabel.Text = "Update cancellation requested..."
        }
    })
$form.Controls.Add($cancelButton)

# Enable/disable buttons based on update status
function Update-ButtonStates {
    param (
        [System.Windows.Forms.Button]$StartButton,
        [System.Windows.Forms.Button]$CancelButton,
        [bool]$StartEnabled,
        [bool]$CancelEnabled
    )

    $StartButton.Enabled = $StartEnabled
    $CancelButton.Enabled = $CancelEnabled
}

$form.Add_Shown({
        $form.Activate()
        Update-ButtonStates -StartButton $startButton -CancelButton $cancelButton -StartEnabled $true -CancelEnabled $false
    })

[void]$form.ShowDialog()

# End of script
