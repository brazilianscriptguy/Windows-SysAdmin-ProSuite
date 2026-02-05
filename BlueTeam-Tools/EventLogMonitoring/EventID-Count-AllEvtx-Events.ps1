<#
.SYNOPSIS
    PowerShell Script for Counting EventID Occurrences in EVTX Files using Log Parser.
    
.DESCRIPTION
    This script counts occurrences of each EventID in EVTX files within a selected folder using 
    COM-based LogQuery, exporting the results to a CSV file with user-configurable paths via a GUI.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 25, 2025
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

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = "Select a folder containing .evtx files"
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
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$LogFolderPath,
        [Parameter(Mandatory)]
        [string]$OutputFolder
    )
    Write-Log "Starting to count Event IDs in .evtx files from '$LogFolderPath'"

    try {
        $evtxFiles = Get-ChildItem -Path $LogFolderPath -Filter "*.evtx" -ErrorAction Stop
        if (-not $evtxFiles) {
            throw "No .evtx files found in '$LogFolderPath'"
        }

        $totalFiles = $evtxFiles.Count
        $processedFiles = 0

        $LogQuery = New-Object -ComObject "MSUtil.LogQuery"
        $InputFormat = New-Object -ComObject "MSUtil.LogQuery.EventLogInputFormat"
        $OutputFormat = New-Object -ComObject "MSUtil.LogQuery.CSVOutputFormat"

        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $csvPath = Join-Path $OutputFolder "${scriptName}_${timestamp}.csv"
        $tempCsvPath = Join-Path $env:TEMP "temp_eventids_$timestamp.csv"

        foreach ($file in $evtxFiles) {
            $processedFiles++
            Update-ProgressBar -Value ([math]::Round(($processedFiles / $totalFiles) * 50))
            $script:statusLabel.Text = "Processing $($file.Name) ($processedFiles of $totalFiles)..."
            $script:form.Refresh()

            $SQLQuery = @"
            SELECT 
                EventID,
                COUNT(*) AS Counting
            INTO '$tempCsvPath'
            FROM '$($file.FullName)'
            GROUP BY EventID
            ORDER BY EventID ASC
"@

            $rtnVal = $LogQuery.ExecuteBatch($SQLQuery, $InputFormat, $OutputFormat)
            if ($rtnVal -eq 0) {
                throw "LogQuery execution failed for '$($file.FullName)'"
            }

            # Append temp CSV to final CSV (avoiding header duplication after first file)
            if (Test-Path $tempCsvPath) {
                $content = Get-Content $tempCsvPath
                if ($processedFiles -eq 1) {
                    $content | Set-Content $csvPath -Encoding UTF8
                } else {
                    $content | Select-Object -Skip 1 | Add-Content $csvPath -Encoding UTF8
                }
                Remove-Item $tempCsvPath -Force
                Write-Log "Processed $($file.Name) for Event ID counts"
            }
        }

        Update-ProgressBar -Value 75
        $script:statusLabel.Text = "Finalizing report..."
        $script:form.Refresh()

        # Count total unique Event IDs from the final CSV
        $eventIdCount = if (Test-Path $csvPath) { (Import-Csv $csvPath).Count } else { 0 }

        Update-ProgressBar -Value 90
        Write-Log "Found $eventIdCount unique Event IDs. Report exported to '$csvPath'"
        $script:statusLabel.Text = "Completed. Found $eventIdCount unique Event IDs. Report saved to '$csvPath'"

        if ($AutoOpen -and (Test-Path $csvPath)) { Start-Process $csvPath }
        Update-ProgressBar -Value 100
        Show-MessageBox -Message "Found $eventIdCount unique Event IDs.`nReport exported to:`n$csvPath" -Title "Success"
    } catch {
        $errorMsg = "Error counting Event IDs: $($_.Exception.Message)"
        Write-Log -Message $errorMsg -Level Error
        Show-MessageBox -Message $errorMsg -Title "Error" -Icon Error
        $script:statusLabel.Text = "Error occurred. Check log for details."
    } finally {
        Update-ProgressBar -Value 0
        if (Test-Path $tempCsvPath) { Remove-Item $tempCsvPath -Force }
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text = 'Event ID Counter (EVTX Files)'
    Size = [System.Drawing.Size]::new(450, 300)
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox = $false
}

# Log Directory
$labelLogDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 20)
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "Log Directory:"
}
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 20)
    Size = [System.Drawing.Size]::new(200, 20)
    Text = $logDir
}
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 20)
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "Browse"
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
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "Output Folder:"
}
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 50)
    Size = [System.Drawing.Size]::new(200, 20)
    Text = $outputFolder
}
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 50)
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "Browse"
}
$buttonBrowseOutputDir.Add_Click({
        $folder = Select-Folder
        if ($folder) { 
            $textBoxOutputDir.Text = $folder 
            Write-Log "Output Folder updated to: '$folder' via browse"
        }
    })
$form.Controls.Add($buttonBrowseOutputDir)

# EVTX Folder
$labelBrowse = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 80)
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "EVTX Folder:"
}
$form.Controls.Add($labelBrowse)

$textBoxEvtxFolder = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 80)
    Size = [System.Drawing.Size]::new(200, 20)
    Text = ""
}
$form.Controls.Add($textBoxEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 80)
    Size = [System.Drawing.Size]::new(100, 20)
    Text = "Browse"
}
$buttonBrowseEvtx.Add_Click({
        $folder = Select-Folder
        if ($folder) { 
            $textBoxEvtxFolder.Text = $folder 
            $script:buttonStartAnalysis.Enabled = $true
            Write-Log "Selected EVTX folder: '$folder'"
        } else {
            $textBoxEvtxFolder.Text = ""
            $script:buttonStartAnalysis.Enabled = $false
        }
    })
$form.Controls.Add($buttonBrowseEvtx)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 110)
    Size = [System.Drawing.Size]::new(430, 20)
    Text = "Ready"
}
$form.Controls.Add($statusLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = [System.Drawing.Point]::new(10, 140)
    Size = [System.Drawing.Size]::new(430, 20)
    Minimum = 0
    Maximum = 100
}
$form.Controls.Add($progressBar)

# Start Button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 170)
    Size = [System.Drawing.Size]::new(100, 30)
    Text = "Start Analysis"
    Enabled = $false
}
$buttonStartAnalysis.Add_Click({
        $script:logDir = $textBoxLogDir.Text
        $script:logPath = Join-Path $script:logDir "${scriptName}.log"
        $outputFolder = $textBoxOutputDir.Text
        $evtxFolder = $textBoxEvtxFolder.Text

        if (-not (Test-Path $script:logDir)) {
            New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
        }

        if (-not $evtxFolder) {
            Show-MessageBox -Message "Please select a folder containing EVTX files." -Title "Input Required" -Icon Warning
            $script:statusLabel.Text = "Ready"
            return
        }

        Write-Log "Starting Event ID analysis in folder '$evtxFolder'"
        $script:statusLabel.Text = "Processing..."
        $script:form.Refresh()

        Count-EventIDs -LogFolderPath $evtxFolder -OutputFolder $outputFolder
        $script:statusLabel.Text = "Ready"
    })
$form.Controls.Add($buttonStartAnalysis)

# Script scope variables
$script:form = $form
$script:progressBar = $progressBar
$script:statusLabel = $statusLabel
$script:buttonStartAnalysis = $buttonStartAnalysis

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion

# End of script
