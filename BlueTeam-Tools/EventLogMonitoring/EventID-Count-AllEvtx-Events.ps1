<#
.SYNOPSIS
    PowerShell Script for Counting EventID Occurrences in EVTX Files.

.DESCRIPTION
    This script counts occurrences of each EventID in one or more EVTX files, exporting the results 
    to a CSV file with user-configurable paths via a GUI. It aids in analyzing event log patterns.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 24, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

#region Initialization
Add-Type -Name Window -Namespace Console -MemberDefinition @"
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        ShowWindow(GetConsoleWindow(), 0); // 0 = SW_HIDE
    }
"@ -ErrorAction Stop
[Console.Window]::Hide()

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    Write-Error "Failed to load required assemblies: $_"
    exit 1
}

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Define default paths
$logDir = "C:\Logs-TEMP"
$outputFolder = [Environment]::GetFolderPath('MyDocuments')
$logPath = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path $logDir -PathType Container)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at '$logDir': $_"
        exit 1
    }
}
#endregion

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $script:logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$script:logPath': $_"
    }
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Update-ProgressBar {
    param (
        [ValidateRange(0, 100)]
        [int]$Value
    )
    $script:progressBar.Value = $Value
    $script:form.Refresh()
}

function Select-EvtxFiles {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        Filter      = "Event Log files (*.evtx)|*.evtx"
        Title       = "Select one or more .evtx files"
        Multiselect = $true
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileNames
    }
    return $null
}

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = "Select a folder"
        ShowNewFolderButton = $false
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

function Count-EventIDs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | ForEach-Object { Test-Path $_ -PathType Leaf } })]
        [string[]]$EvtxFilePaths,
        [Parameter(Mandatory)]
        [string]$OutputFolder
    )
    Write-Log "Starting to count Event IDs in $($EvtxFilePaths.Count) .evtx files"

    try {
        $totalFiles = $EvtxFilePaths.Count
        $processedFiles = 0
        $eventCounts = [System.Collections.Generic.Dictionary[string,int]]::new()

        foreach ($file in $EvtxFilePaths) {
            $processedFiles++
            Update-ProgressBar -Value ([math]::Round(($processedFiles / $totalFiles) * 50))
            $script:statusLabel.Text = "Processing $file ($processedFiles of $totalFiles)..."
            $script:form.Refresh()

            $events = Get-WinEvent -Path $file -ErrorAction Stop
            foreach ($event in $events) {
                $eventId = $event.Id.ToString()
                if ($eventCounts.ContainsKey($eventId)) {
                    $eventCounts[$eventId]++
                } else {
                    $eventCounts[$eventId] = 1
                }
            }
            Write-Log "Processed $($events.Count) events from '$file'"
        }

        Update-ProgressBar -Value 75
        $script:statusLabel.Text = "Exporting results..."
        $script:form.Refresh()

        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $csvPath = Join-Path $OutputFolder "${scriptName}_${timestamp}.csv"
        $eventCounts.GetEnumerator() | Sort-Object Name | Select-Object @{
            Name = 'EventID'
            Expression = { $_.Key }
        }, @{
            Name = 'Counting'
            Expression = { $_.Value }
        } | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop

        Update-ProgressBar -Value 90
        Write-Log "Event counts exported to '$csvPath'"
        $script:statusLabel.Text = "Completed. Report saved to '$csvPath'"

        if ($AutoOpen) { Start-Process $csvPath }
        Update-ProgressBar -Value 100
        Show-MessageBox -Message "Event counts exported to:`n$csvPath" -Title "Success"
    } catch {
        $errorMsg = "Error counting Event IDs: $($_.Exception.Message)"
        Write-Log -Message $errorMsg -Level Error
        Show-MessageBox -Message $errorMsg -Title "Error" -Icon Error
        $script:statusLabel.Text = "Error occurred. Check log for details."
    } finally {
        Update-ProgressBar -Value 0
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'Event ID Counter (EVTX Files)'
    Size          = [System.Drawing.Size]::new(450, 300)
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox     = $false
}

# Log Directory
$labelLogDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 20)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Log Directory:"
}
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 20)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $logDir
}
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 20)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseLogDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { 
        $textBoxLogDir.Text = $folder 
        Write-Log "Log Directory updated to: '$folder' via browse"
    }
})
$form.Controls.Add($buttonBrowseLogDir)

# Output Folder
$labelOutputDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 50)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Output Folder:"
}
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 50)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $outputFolder
}
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 50)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseOutputDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { 
        $textBoxOutputDir.Text = $folder 
        Write-Log "Output Folder updated to: '$folder' via browse"
    }
})
$form.Controls.Add($buttonBrowseOutputDir)

# EVTX Files
$labelBrowse = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 80)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "EVTX Files:"
}
$form.Controls.Add($labelBrowse)

$textBoxEvtxFiles = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 80)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = ""
    ReadOnly = $true
}
$form.Controls.Add($textBoxEvtxFiles)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 80)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseEvtx.Add_Click({
    $files = Select-EvtxFiles
    if ($files) { 
        $script:evtxFiles = $files
        $textBoxEvtxFiles.Text = "$($files.Count) file(s) selected"
        $script:buttonStartAnalysis.Enabled = $true
        Write-Log "Selected $($files.Count) .evtx files: $($files -join ', ')"
    } else {
        $script:evtxFiles = @()
        $textBoxEvtxFiles.Text = ""
        $script:buttonStartAnalysis.Enabled = $false
    }
})
$form.Controls.Add($buttonBrowseEvtx)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 110)
    Size     = [System.Drawing.Size]::new(430, 20)
    Text     = "Ready"
}
$form.Controls.Add($statusLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = [System.Drawing.Point]::new(10, 140)
    Size     = [System.Drawing.Size]::new(430, 20)
    Minimum  = 0
    Maximum  = 100
}
$form.Controls.Add($progressBar)

# Start Button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 170)
    Size     = [System.Drawing.Size]::new(100, 30)
    Text     = "Start Analysis"
    Enabled  = $false
}
$buttonStartAnalysis.Add_Click({
    $script:logDir = $textBoxLogDir.Text
    $script:logPath = Join-Path $script:logDir "${scriptName}.log"
    $outputFolder = $textBoxOutputDir.Text
    $evtxFiles = $script:evtxFiles

    if (-not (Test-Path $script:logDir)) {
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }

    if (-not $evtxFiles) {
        Show-MessageBox -Message "Please select one or more EVTX files." -Title "Input Required" -Icon Warning
        $script:statusLabel.Text = "Ready"
        return
    }

    Write-Log "Starting analysis of Event IDs in $($evtxFiles.Count) files"
    $script:statusLabel.Text = "Processing..."
    $script:form.Refresh()

    Count-EventIDs -EvtxFilePaths $evtxFiles -OutputFolder $outputFolder
    $script:statusLabel.Text = "Ready"
})
$form.Controls.Add($buttonStartAnalysis)

# Script scope variables
$script:form = $form
$script:progressBar = $progressBar
$script:statusLabel = $statusLabel
$script:buttonStartAnalysis = $buttonStartAnalysis
$script:evtxFiles = @()

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
