<#
.SYNOPSIS
    PowerShell Script Template with GUI for Enhanced User Interaction

.DESCRIPTION
    Provides a reusable framework for building PowerShell scripts with a graphical user interface (GUI),
    complete with logging, error handling, dynamic file paths, and simple input/output workflow.

.FEATURES
    - Toggle console window visibility
    - Timestamped log file creation with customizable log directory
    - GUI-based input, processing, and message display
    - Integrated error handling with popup alerts
    - Save runtime log output to CSV

.PARAMETERS
    -ShowConsole [switch]: Shows the PowerShell console if set; hides it by default for GUI experience.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Version 3.0 - July 16, 2025

.NOTES
    - Requires .NET Framework and Windows Forms support
    - Tested on Windows PowerShell 5.1 and PowerShell 7+

.EXAMPLES
    Launch GUI with hidden console (default):
    ```powershell
    .\GuiTemplate.ps1
    ```

    Launch GUI with visible console for debugging:
    ```powershell
    .\GuiTemplate.ps1 -ShowConsole
    ```
#>

param (
    [switch]$ShowConsole = $false
)

#region Console Visibility
function Set-ConsoleVisibility {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Window {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        public static void Set(bool visible) {
            var handle = GetConsoleWindow();
            ShowWindow(handle, visible ? 5 : 0);
        }
    }
"@
    [Window]::Set($ShowConsole)
}
Set-ConsoleVisibility
#endregion

#region Logging & Error Handling
function Initialize-ScriptPaths {
    param ([string]$DefaultLogDir = 'C:\Logs-TEMP')

    $scriptName = if ($PSCommandPath) {
        [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
    } else {
        "Script"
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { $DefaultLogDir }
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName
    $csvPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}_${timestamp}.csv"

    return @{
        LogDir     = $logDir
        LogPath    = $logPath
        CsvPath    = $csvPath
        ScriptName = $scriptName
    }
}

function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        if (-not (Test-Path $global:logDir)) {
            New-Item -Path $global:logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $global:logPath -Value $logEntry -Encoding UTF8
    } catch {
        Write-Error "Failed to write to log: $_"
    }

    $global:logBox?.Items.Add($logEntry)
}

function Handle-Error {
    param ([string]$ErrorMessage)

    Log-Message -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage, "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}
#endregion

#region GUI Setup
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$paths = Initialize-ScriptPaths
$global:logDir   = $paths.LogDir
$global:logPath  = $paths.LogPath
$global:csvPath  = $paths.CsvPath

function Create-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "PowerShell Script GUI Template"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"

    # Header Label
    $labelTitle = New-Object System.Windows.Forms.Label
    $labelTitle.Text = "PowerShell Script GUI Template"
    $labelTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $labelTitle.AutoSize = $true
    $labelTitle.Location = New-Object System.Drawing.Point(10, 10)
    $form.Controls.Add($labelTitle)

    # LogBox
    $global:logBox = New-Object System.Windows.Forms.ListBox
    $global:logBox.Size = New-Object System.Drawing.Size(760, 300)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 50)
    $form.Controls.Add($global:logBox)

    # Text Input
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

    # Button Events
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

            $result = "Processed input: $input"
            Log-Message -Message $result -MessageType "INFO"
            $buttonSave.Enabled = $true
        } catch {
            Handle-Error -ErrorMessage $_.Exception.Message
        } finally {
            $buttonStart.Enabled = $true
        }
    })

    $buttonSave.Add_Click({
        try {
            $global:logBox.Items | Out-File -FilePath $global:csvPath -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show(
                "Logs saved to:`n$($global:csvPath)",
                "Save Successful",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Log-Message -Message "Logs saved to: $global:csvPath" -MessageType "INFO"
        } catch {
            Handle-Error -ErrorMessage $_.Exception.Message
        }
    })

    $form.ShowDialog()
}
#endregion

# Start the GUI
Create-GUI
