<#
.SYNOPSIS
    PowerShell Script Template with GUI for Enhanced User Interaction.

.DESCRIPTION
    Provides a reusable framework for creating PowerShell scripts with a graphical user interface (GUI).
    Includes standardized logging, error handling, dynamic paths, and customizable GUI components.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 10, 2025
#>

param (
    [switch]$ShowConsole = $false
)

# Manage PowerShell console visibility
if (-not $ShowConsole) {
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
}

# Logging function
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
        if (-not (Test-Path $global:logDir)) {
            New-Item -Path $global:logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $global:logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
        Write-Output $logEntry
    }
}

# Error handling function
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )
    Log-Message -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage, 
        "Error", 
        [System.Windows.Forms.MessageBoxButtons]::OK, 
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# Initialize paths dynamically
function Initialize-ScriptPaths {
    param (
        [string]$DefaultLogDir = 'C:\Logs-TEMP'
    )
    $scriptName = if ($PSCommandPath) {
        [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    } else {
        "Script"
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName
    $csvPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}-${timestamp}.csv"

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        CsvPath    = $csvPath
        ScriptName = $scriptName
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Initialize paths
$paths = Initialize-ScriptPaths
$global:logDir = $paths.LogDir
$global:logPath = $paths.LogPath
$global:csvPath = $paths.CsvPath

# GUI creation
function Create-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PowerShell Script GUI Template"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"

    # Title Label
    $labelTitle = New-Object System.Windows.Forms.Label
    $labelTitle.Text = "PowerShell Script GUI Template"
    $labelTitle.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $labelTitle.AutoSize = $true
    $labelTitle.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($labelTitle)

    # Log Output (ListBox)
    $global:logBox = New-Object System.Windows.Forms.ListBox
    $global:logBox.Size = New-Object System.Drawing.Size(760, 300)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 50)
    $form.Controls.Add($global:logBox)

    # Input TextBox
    $textBoxInput = New-Object System.Windows.Forms.TextBox
    $textBoxInput.Size = New-Object System.Drawing.Size(760, 30)
    $textBoxInput.Location = New-Object System.Drawing.Point(10, 370)
    $form.Controls.Add($textBoxInput)

    # Start Button
    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Text = "Start"
    $buttonStart.Size = New-Object System.Drawing.Size(100, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(10, 420)
    $form.Controls.Add($buttonStart)

    # Save Button
    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = "Save Logs"
    $buttonSave.Size = New-Object System.Drawing.Size(100, 30)
    $buttonSave.Location = New-Object System.Drawing.Point(120, 420)
    $buttonSave.Enabled = $false
    $form.Controls.Add($buttonSave)

    # Start Button Event
    $buttonStart.Add_Click({
        $buttonStart.Enabled = $false
        $buttonSave.Enabled = $false
        $global:logBox.Items.Clear()
        Log-Message -Message "Process started." -MessageType "INFO"

        try {
            $input = $textBoxInput.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($input)) {
                throw "Input cannot be empty."
            }

            $result = "Processing input: $input" # Simulated processing
            $global:logBox.Items.Add($result)
            Log-Message -Message "Processing completed for input: $input." -MessageType "INFO"
            $buttonSave.Enabled = $true
        } catch {
            Handle-Error -ErrorMessage $_.Exception.Message
        } finally {
            $buttonStart.Enabled = $true
        }
    })

    # Save Button Event
    $buttonSave.Add_Click({
        try {
            $global:logBox.Items | Out-File -FilePath $global:csvPath -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show(
                "Logs saved to $global:csvPath", 
                "Save Successful", 
                [System.Windows.Forms.MessageBoxButtons]::OK, 
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Log-Message -Message "Logs saved to $global:csvPath" -MessageType "INFO"
        } catch {
            Handle-Error -ErrorMessage $_.Exception.Message
        }
    })

    $form.ShowDialog()
}

# Launch the GUI
Create-GUI
