<#
.SYNOPSIS
    PowerShell Script for Analyzing AD Object Changes via Event IDs 5136, 5137, and 5141.

.DESCRIPTION
    This script analyzes Active Directory object changes and deletions based on Event IDs 5136, 
    5137, and 5141, generating a CSV report for auditing AD modifications and tracking security changes.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 28, 2025
#>

Param(
    [Bool]$AutoOpen = $false
)

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

# Import necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name for logging purposes
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Get the Domain Server Name
$DomainServerName = [System.Environment]::MachineName

# Set up logging
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
        [Parameter(Mandatory=$true)]
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

# Function to display a message box for notifications
function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title)
}

# Function to update the progress bar in the GUI
function Update-ProgressBar {
    param (
        [int]$Value
    )
    $progressBar.Value = $Value
    $form.Refresh()
}

# Function to select files via OpenFileDialog
function Select-Files {
    param (
        [string]$Filter,
        [string]$Title,
        [bool]$Multiselect
    )
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = $Filter
    $openFileDialog.Title = $Title
    $openFileDialog.Multiselect = $Multiselect
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $openFileDialog.FileNames
    }
}

# Function to select EVTX files using GUI
function Select-EvtxFiles {
    Select-Files -Filter "EVTX Files (*.evtx)|*.evtx" -Title "Select EVTX Files" -Multiselect $true
}

# Function to search for Events ID 5136, 5137, and 5141 in a given EVTX file
function Search-EventIDs5136_5137_5141 {
    param (
        [string]$EvtxFilePath
    )

    $results = @()

    try {
        Log-Message "Searching Events ID 5136, 5137, and 5141 in $EvtxFilePath"
        # Query for Events ID 5136, 5137, and 5141
        $events = Get-WinEvent -Path $EvtxFilePath -FilterXPath "*[System[(EventID=5136 or EventID=5137 or EventID=5141)]]"

        # Extract relevant information and create custom objects
        foreach ($event in $events) {
            $eventProperties = $event.Properties
            $eventTime = $event.TimeCreated
            $eventID = $event.Id
            $userAccount = $eventProperties[1].Value
            $objectClass = $eventProperties[4].Value
            $objectDN = $eventProperties[5].Value
            $attribute = if ($eventID -eq 5136) { $eventProperties[6].Value } else { '' }

            $result = [PSCustomObject]@{
                EventTime = $eventTime
                EventID = $eventID
                UserAccount = $userAccount
                ObjectClass = $objectClass
                ObjectDN = $objectDN
                Attribute = $attribute
            }

            $results += $result
        }

        Log-Message "Finished searching $EvtxFilePath"
    } catch {
        $errorMsg = "Error searching Events ID 5136, 5137, and 5141 in ${EvtxFilePath}: $($_.Exception.Message)"
        Log-Message $errorMsg
        Show-MessageBox -Message $errorMsg -Title "Search Error"
    }

    return $results
}

# Function to export search results to a CSV file
function Export-SearchResultsToCSV {
    param (
        [array]$Results,
        [string]$OutputFilePath
    )

    try {
        Log-Message "Exporting results to $OutputFilePath"
        $Results | Export-Csv -Path $OutputFilePath -NoTypeInformation
        Log-Message "Exported results to $OutputFilePath"
    } catch {
        $errorMsg = "Error exporting results to ${OutputFilePath}: $($_.Exception.Message)"
        Log-Message $errorMsg
        Show-MessageBox -Message $errorMsg -Title "Export Error"
    }
}

# Function to consolidate individual results into a single CSV file
function Consolidate-SearchResults {
    param (
        [array]$OutputFilePaths,
        [string]$ConsolidatedFilePath
    )

    try {
        Log-Message "Consolidating results to $ConsolidatedFilePath"
        $allResults = @()
        foreach ($outputFile in $OutputFilePaths) {
            $allResults += Import-Csv -Path $outputFile
        }
        $allResults | Export-Csv -Path $ConsolidatedFilePath -NoTypeInformation
        Log-Message "Consolidated results exported to $ConsolidatedFilePath"
    } catch {
        $errorMsg = "Error consolidating results to ${ConsolidatedFilePath}: $($_.Exception.Message)"
        Log-Message $errorMsg
        Show-MessageBox -Message $errorMsg -Title "Consolidation Error"
    }
}

# Main script logic with GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Event IDs 5136, 5137, and 5141 Parser'
$form.Size = New-Object System.Drawing.Size @(350, 250)
$form.StartPosition = 'CenterScreen'

# Progress bar setup
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point @(10, 70)
$progressBar.Size = New-Object System.Drawing.Size @(310, 20)
$form.Controls.Add($progressBar)

# Start button setup
$button = New-Object System.Windows.Forms.Button
$button.Location = New-Object System.Drawing.Point @(10, 100)
$button.Size = New-Object System.Drawing.Size @(100, 30)
$button.Text = 'Start Analysis'
$button.Add_Click({
    Log-Message "Starting analysis for Events IDs 5136, 5137, and 5141 (AD Changes and Object Deletions)"

    # Start the process when the button is clicked
    $evtxFiles = Select-EvtxFiles
    if ($evtxFiles) {
        $outputFolderPath = [Environment]::GetFolderPath("MyDocuments")
        $outputFiles = @()
        $totalFiles = $evtxFiles.Count
        $currentIndex = 0
        foreach ($evtxFile in $evtxFiles) {
            $currentIndex++
            Update-ProgressBar -Value ($currentIndex / $totalFiles * 100)
            $results = Search-EventIDs5136_5137_5141 -EvtxFilePath $evtxFile
            $outputFilePath = Join-Path $outputFolderPath ([System.IO.Path]::GetFileNameWithoutExtension($evtxFile) + "_ADChangesAndObjectDeletions.csv")
            Export-SearchResultsToCSV -Results $results -OutputFilePath $outputFilePath
            $outputFiles += $outputFilePath
        }

        $consolidatedFilePath = Join-Path $outputFolderPath "EventID5136_5137_5141-ADChangesAndObjectDeletions.csv"
        Consolidate-SearchResults -OutputFilePaths $outputFiles -ConsolidatedFilePath $consolidatedFilePath

        if (Test-Path $consolidatedFilePath) {
            Show-MessageBox -Message "Consolidated results saved to:`n$consolidatedFilePath" -Title "Analysis Complete"
            if ($AutoOpen) {
                Start-Process $consolidatedFilePath
            }
        } else {
            Show-MessageBox -Message "No AD changes or object deletion events found." -Title "No Results"
        }
    } else {
        Show-MessageBox -Message "No EVTX files selected." -Title "No Input"
    }
})
$form.Controls.Add($button)

# Display the GUI form
$form.Add_Shown({$form.Activate()})
[void]$form.ShowDialog()

# End of script
