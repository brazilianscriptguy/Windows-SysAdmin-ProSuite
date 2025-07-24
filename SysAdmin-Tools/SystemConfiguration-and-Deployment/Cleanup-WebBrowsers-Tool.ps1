<#
.SYNOPSIS
    PowerShell Tool for Cleaning Web Browsers and System Residual Files.

.DESCRIPTION
    This script thoroughly removes cookies, cache, session data, history, and other 
    residual files from web browsers (Mozilla Firefox, Google Chrome, Microsoft Edge, 
    Internet Explorer) and WhatsApp. It also performs general system cleanup tasks 
    across all user profiles on a Windows system, improving performance and privacy.

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

# Add necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Define Colors for Logging
$Yellow = "Yellow"
$Green = "Green"
$Cyan = "Cyan"

# Function to Log Messages with Color
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO",
        [Parameter(Mandatory = $false)]
        [string]$Color = "White"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    
    try {
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -ErrorAction Stop | Out-Null
        }
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
        Write-Host $logEntry -ForegroundColor $Color
    }
    
    if ($global:logBox -and $global:logBox.InvokeRequired -eq $false) {
        $global:logBox.Items.Add($logEntry)
        $global:logBox.TopIndex = $global:logBox.Items.Count - 1
    }
}

# Function to Handle Errors
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Write-Log -Message "ERROR: $ErrorMessage" -MessageType "ERROR" -Color $Yellow
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to Remove Items with Error Handling
function Remove-Items {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue -Verbose
            Write-Log -Message "Removed: $Path" -MessageType "INFO" -Color $Cyan
        } else {
            Write-Log -Message "Path does not exist: $Path" -MessageType "WARNING" -Color $Yellow
        }
    } catch {
        Handle-Error "Failed to remove items at path: $Path. Error: $_"
    }
}

# Function to Kill Browser Processes
function Kill-BrowserProcesses {
    param (
        [Parameter(Mandatory = $true)][string[]]$Browsers
    )
    foreach ($browser in $Browsers) {
        try {
            Get-Process -Name $browser -ErrorAction SilentlyContinue | Stop-Process -Force
            Write-Log -Message "Stopped $browser process." -MessageType "INFO" -Color $Cyan
        } catch {
            Write-Log -Message "Failed to stop $browser process." -MessageType "WARNING" -Color $Yellow
        }
    }
}

# Function to Clear Browser Data (Generalized for Reuse)
function Clear-BrowserData {
    param (
        [Parameter(Mandatory = $true)][string]$BrowserName,
        [Parameter(Mandatory = $true)][string[]]$PathsToClear,
        [Parameter(Mandatory = $true)][string]$UserProfileBasePath
    )
    Write-Log -Message "Clearing $BrowserName Data" -MessageType "INFO" -Color $Green
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
        $UserName = $_.Name
        $UserProfilePath = Join-Path $_.FullName $UserProfileBasePath
        if (Test-Path $UserProfilePath) {
            Write-Log -Message "  Processing $BrowserName data for user: $UserName" -MessageType "INFO" -Color $Cyan
            foreach ($Path in $PathsToClear) {
                $FullPath = Join-Path $UserProfilePath $Path
                Remove-Items -Path $FullPath
            }
        } else {
            Write-Log -Message "$BrowserName data path not found for user: $UserName" -MessageType "WARNING" -Color $Yellow
        }
    }
    Write-Log -Message "$BrowserName Data Cleared." -MessageType "INFO" -Color $Green
}

# Function to Clear Browser History
function Clear-BrowserHistory {
    param (
        [Parameter(Mandatory = $true)][string]$BrowserName,
        [Parameter(Mandatory = $true)][string[]]$HistoryPaths,
        [Parameter(Mandatory = $true)][string]$UserProfileBasePath
    )
    Write-Log -Message "Clearing $BrowserName History" -MessageType "INFO" -Color $Green
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
        $UserName = $_.Name
        $UserProfilePath = Join-Path $_.FullName $UserProfileBasePath
        if (Test-Path $UserProfilePath) {
            Write-Log -Message "  Processing $BrowserName history for user: $UserName" -MessageType "INFO" -Color $Cyan
            foreach ($HistoryPath in $HistoryPaths) {
                $FullPath = Join-Path $UserProfilePath $HistoryPath
                if (Test-Path $FullPath) {
                    Remove-Item -Path $FullPath -Force -ErrorAction SilentlyContinue
                    Write-Log -Message "Removed history file: $FullPath" -MessageType "INFO" -Color $Cyan
                } else {
                    Write-Log -Message "History path does not exist: $FullPath" -MessageType "WARNING" -Color $Yellow
                }
            }
        }
    }
    Write-Log -Message "$BrowserName History Cleared." -MessageType "INFO" -Color $Green
}

# Function to Clear WhatsApp Data
function Clear-WhatsAppData {
    Write-Log -Message "Clearing WhatsApp Data" -MessageType "INFO" -Color $Green
    Get-ChildItem "C:\Users" -Directory | ForEach-Object {
        $UserName = $_.Name
        $UserProfilePath = $_.FullName
        $WhatsAppPaths = @(
            "$UserProfilePath\AppData\Roaming\WhatsApp",
            "$UserProfilePath\AppData\Local\WhatsApp"
        )
        foreach ($Path in $WhatsAppPaths) {
            if (Test-Path $Path) {
                Write-Log -Message "  Processing WhatsApp data for user: $UserName" -MessageType "INFO" -Color $Cyan
                $PathsToClear = @(
                    "$Path\Cache",
                    "$Path\Local Storage",
                    "$Path\*.*_lock",
                    "$Path\Sessions",
                    "$Path\Databases",
                    "$Path\IndexedDB",
                    "$Path\Media Cache",
                    "$Path\*.*"
                )
                foreach ($ClearPath in $PathsToClear) {
                    Remove-Items -Path $ClearPath
                }
            } else {
                Write-Log -Message "WhatsApp data path not found for user: $UserName" -MessageType "WARNING" -Color $Yellow
            }
        }
    }
    Write-Log -Message "WhatsApp Data Cleared." -MessageType "INFO" -Color $Green
}

# Function to Perform General System Cleanup
function Clear-SystemTemp {
    Write-Log -Message "Performing General System Cleanup" -MessageType "INFO" -Color $Green
    $GeneralTempPaths = @(
        "C:\Users\*\AppData\Local\Temp\*",
        "C:\Windows\Temp\*",
        "C:\Windows\Prefetch\*",
        "C:\$Recycle.Bin\*",
        "C:\ProgramData\Microsoft\Windows\WER\*"
    )
    foreach ($Path in $GeneralTempPaths) {
        Remove-Items -Path $Path
    }
    Write-Log -Message "General System Cleanup Completed." -MessageType "INFO" -Color $Green
}

# Function to Clear Application Data (%APPDATA%) and %TEMP% related to Web Browsers
function Clear-ApplicationData {
    Write-Log -Message "Clearing Application Data (%APPDATA%) and %TEMP% related to browsers" -MessageType "INFO" -Color $Green
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
        $UserName = $_.Name
        $UserProfilePath = $_.FullName
        $PathsToClear = @(
            "$UserProfilePath\AppData\Roaming\Mozilla",
            "$UserProfilePath\AppData\Roaming\Google",
            "$UserProfilePath\AppData\Roaming\Microsoft\Edge",
            "$UserProfilePath\AppData\Local\Temp\*",
            "$UserProfilePath\AppData\Local\Google",
            "$UserProfilePath\AppData\Local\Mozilla",
            "$UserProfilePath\AppData\Local\Microsoft\Edge"
        )
        foreach ($Path in $PathsToClear) {
            Remove-Items -Path $Path
        }
    }
    Write-Log -Message "Application Data (%APPDATA%) and %TEMP% related to browsers cleaned." -MessageType "INFO" -Color $Green
}

# Set log and CSV paths, allow dynamic configuration or fallback to defaults
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = if ($env:LOG_PATH -and $env:LOG_PATH -ne "") { $env:LOG_PATH } else { 'C:\Logs-TEMP' }
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName
$csvPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}-$timestamp.csv"

# Global Variables Initialization
$global:logBox = New-Object System.Windows.Forms.ListBox
$global:results = @{}

# Function to Create the GUI
function Create-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Web Browser Cleanup Tool"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = "CenterScreen"
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Size = New-Object System.Drawing.Size(760, 300)
    $textBox.Location = New-Object System.Drawing.Point(10, 10)
    $textBox.ReadOnly = $true
    $form.Controls.Add($textBox)
    $instructionLabel = New-Object System.Windows.Forms.Label
    $instructionLabel.Text = "Click 'Start' to begin the cleanup process:"
    $instructionLabel.Location = New-Object System.Drawing.Point(10, 320)
    $instructionLabel.Size = New-Object System.Drawing.Size(300, 20)
    $form.Controls.Add($instructionLabel)
    $global:logBox = New-Object System.Windows.Forms.ListBox
    $global:logBox.Size = New-Object System.Drawing.Size(760, 100)
    $global:logBox.Location = New-Object System.Drawing.Point(10, 385)
    $form.Controls.Add($global:logBox)
    $buttonStart = New-Object System.Windows.Forms.Button
    $buttonStart.Text = "Start"
    $buttonStart.Size = New-Object System.Drawing.Size(100, 30)
    $buttonStart.Location = New-Object System.Drawing.Point(10, 500)
    $form.Controls.Add($buttonStart)
    $buttonSave = New-Object System.Windows.Forms.Button
    $buttonSave.Text = "Save to CSV"
    $buttonSave.Size = New-Object System.Drawing.Size(100, 30)
    $buttonSave.Location = New-Object System.Drawing.Point(120, 500)
    $buttonSave.Enabled = $false
    $form.Controls.Add($buttonSave)
    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = "Close"
    $buttonClose.Size = New-Object System.Drawing.Size(100, 30)
    $buttonClose.Location = New-Object System.Drawing.Point(230, 500)
    $form.Controls.Add($buttonClose)
    $buttonStart.Add_Click({
            $buttonStart.Enabled = $false
            $buttonSave.Enabled = $false
            $textBox.Clear()
            $textBox.Text = "Process started, please wait..."
            try {
                # Kill browser processes to prevent issues during cleanup
                Kill-BrowserProcesses -Browsers @("firefox", "chrome", "msedge", "iexplore")
            
                # Execute cleanup functions
                Clear-BrowserData -BrowserName "Mozilla Firefox" -PathsToClear @("cookies.sqlite", "cache2\entries", "places.sqlite", "sessionstore.jsonlz4", "webappsstore.sqlite", "downloads.json", "storage\default", "thumbnails", "cache", "extensions") -UserProfileBasePath "AppData\Local\Mozilla\Firefox\Profiles"
                Clear-BrowserData -BrowserName "Google Chrome" -PathsToClear @("Cookies", "Cache", "History", "Local Storage", "Sessions") -UserProfileBasePath "AppData\Local\Google\Chrome\User Data\Default"
                Clear-BrowserData -BrowserName "Microsoft Edge" -PathsToClear @("Cookies", "Cache", "History", "Local Storage", "Sessions") -UserProfileBasePath "AppData\Local\Microsoft\Edge\User Data\Default"
                Clear-BrowserData -BrowserName "Internet Explorer" -PathsToClear @("INetCache\*", "INetCookies\*", "History\*") -UserProfileBasePath "AppData\Local\Microsoft\Windows"
                Clear-BrowserHistory -BrowserName "Mozilla Firefox" -HistoryPaths @("places.sqlite*") -UserProfileBasePath "AppData\Local\Mozilla\Firefox\Profiles"
                Clear-WhatsAppData
                Clear-SystemTemp
                Clear-ApplicationData

                $textBox.Text = "Cleanup process completed successfully."
                Write-Log -Message "Cleanup process completed successfully." -MessageType "INFO" -Color $Green

                if ($ShowConsole) {
                    Write-Host "Cleanup process completed successfully." -ForegroundColor Green
                }

                $buttonSave.Enabled = $true
            } catch {
                Handle-Error "An error occurred during the cleanup process: $_"
                $textBox.Text = "An error occurred. Check the logs for details."
                if ($ShowConsole) {
                    Write-Host "An error occurred during the cleanup process. Check the logs for details." -ForegroundColor Red
                }
            } finally {
                $buttonStart.Enabled = $true
            }
        })
    $buttonSave.Add_Click({
            if ($null -eq $global:results -or $global:results.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show("No data to save. Please ensure the process has completed successfully.", "No Data", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            try {
                $csvData = @()
                foreach ($category in $global:results.Keys) {
                    $row = New-Object PSObject
                    $row | Add-Member -MemberType NoteProperty -Name "Category" -Value $category
                    foreach ($item in $global:results[$category]) {
                        $row | Add-Member -MemberType NoteProperty -Name $item -Value ($item -join ', ')
                    }
                    $csvData += $row
                }
                $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
                [System.Windows.Forms.MessageBox]::Show("Results saved to " + $csvPath, "Save Successful", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                Write-Log -Message "Results saved to CSV file: $csvPath" -MessageType "INFO" -Color $Green
            } catch {
                Handle-Error "Failed to save results to CSV: $_"
            }
        })
    $buttonClose.Add_Click({
            $form.Close()
        })
    $form.ShowDialog()
}

# Main Script Execution
Write-Log -Message "#######################################################" -MessageType "INFO" -Color $Yellow
Write-Log -Message "PowerShell commands to delete cookies, cache, history, and other data" -MessageType "INFO" -Color $Green
Write-Log -Message "in Firefox, Chrome, Edge, Internet Explorer, WhatsApp," -MessageType "INFO" -Color $Green
Write-Log -Message "and perform general system cleanup" -MessageType "INFO" -Color $Green
Write-Log -Message "By Luiz Hamilton Silva - @brazilianscriptguy" -MessageType "INFO" -Color $Green
Write-Log -Message "Updated: October 06, 2024" -MessageType "INFO" -Color $Green
Write-Log -Message "#######################################################`n" -MessageType "INFO" -Color $Yellow

# Create the GUI
Create-GUI

# End of script
