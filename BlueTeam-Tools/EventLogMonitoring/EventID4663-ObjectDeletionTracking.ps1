<#
.SYNOPSIS
    PowerShell Script for Tracking Object Deletions via Event IDs 4660 and 4663.

.DESCRIPTION
    This script analyzes object deletion events (Event IDs 4660 and 4663) from EVTX files, 
    generating a consolidated CSV report for auditing and monitoring purposes.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 24, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the consolidated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

#region Initialization
# Hide the console window
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

# Load required assemblies
try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    Write-Error "Failed to load required assemblies: $_"
    exit 1
}

# Script metadata and logging setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "${scriptName}.log"

# Ensure log directory exists with proper error handling
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
        [ValidateSet('Info', 'Error')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$logPath': $_"
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
        Filter      = "EVTX Files (*.evtx)|*.evtx"
        Title       = "Select EVTX Files"
        Multiselect = $true
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileNames
    }
    return $null
}

function Get-ObjectDeletionEvents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$EvtxFilePath
    )
    Write-Log "Processing '$EvtxFilePath' for Event IDs 4660 and 4663"
    $results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        $events = Get-WinEvent -Path $EvtxFilePath -FilterXPath "*[System[(EventID=4660 or EventID=4663)]]" -ErrorAction Stop
        foreach ($event in $events) {
            $props = $event.Properties
            $results.Add([PSCustomObject]@{
                DateTime       = $event.TimeCreated
                EventID        = $event.Id
                UserAccount    = $props[1].Value
                Domain         = $props[2].Value
                LockoutCode    = $props[4].Value
                ObjectType     = $props[5].Value
                AccessedObject = $props[6].Value
                SubCode        = $props[7].Value
            })
        }
        Write-Log "Found $($results.Count) events in '$EvtxFilePath'"
    } catch {
        Write-Log -Message "Failed to process '$EvtxFilePath': $_" -Level Error
        Show-MessageBox -Message "Error processing '$EvtxFilePath': $_" -Title "Processing Error" -Icon Error
    }
    return $results
}

function Export-ResultsToCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Results,
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    Write-Log "Exporting $($Results.Count) results to '$FilePath'"
    try {
        $Results | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Export completed for '$FilePath'"
    } catch {
        Write-Log -Message "Failed to export to '$FilePath': $_" -Level Error
        Show-MessageBox -Message "Export failed for '$FilePath': $_" -Title "Export Error" -Icon Error
    }
}

function Merge-CsvResults {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$InputFiles,
        [Parameter(Mandatory)]
        [string]$OutputFile
    )
    Write-Log "Merging $($InputFiles.Count) CSV files into '$OutputFile'"
    try {
        $allResults = $InputFiles | ForEach-Object { Import-Csv -Path $_ -ErrorAction Stop }
        $allResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Merge completed for '$OutputFile'"
    } catch {
        Write-Log -Message "Failed to merge results into '$OutputFile': $_" -Level Error
        Show-MessageBox -Message "Merge failed: $_" -Title "Merge Error" -Icon Error
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'Object Deletion Event Parser (4660, 4663)'
    Size          = [System.Drawing.Size]::new(350, 250)
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox   = $false
}

$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = [System.Drawing.Point]::new(10, 70)
    Size     = [System.Drawing.Size]::new(310, 20)
}
$form.Controls.Add($progressBar)

$button = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 100)
    Size     = [System.Drawing.Size]::new(100, 30)
    Text     = 'Start Analysis'
}
$button.Add_Click({
    Write-Log "Analysis started by user"
    $evtxFiles = Select-EvtxFiles
    if (-not $evtxFiles) {
        Show-MessageBox -Message "No EVTX files selected." -Title "Input Required" -Icon Warning
        return
    }

    $outputFolder = [Environment]::GetFolderPath('MyDocuments')
    $outputFiles = [System.Collections.Generic.List[string]]::new()
    $totalFiles = $evtxFiles.Count

    $evtxFiles | ForEach-Object -Begin { $i = 0 } -Process {
        $i++
        Update-ProgressBar -Value ([math]::Round($i / $totalFiles * 100))
        $results = Get-ObjectDeletionEvents -EvtxFilePath $_
        if ($results) {
            $outputFile = Join-Path $outputFolder "$([System.IO.Path]::GetFileNameWithoutExtension($_))_ObjectDeletionTracking.csv"
            Export-ResultsToCsv -Results $results -FilePath $outputFile
            $outputFiles.Add($outputFile)
        }
    }

    if ($outputFiles.Count -gt 0) {
        $consolidatedFile = Join-Path $outputFolder "EventID4660and4663-ObjectDeletionTracking.csv"
        Merge-CsvResults -InputFiles $outputFiles -OutputFile $consolidatedFile
        if (Test-Path $consolidatedFile) {
            Show-MessageBox -Message "Analysis complete. Results saved to:`n$consolidatedFile" -Title "Success"
            if ($AutoOpen) { Start-Process -FilePath $consolidatedFile }
        }
    } else {
        Show-MessageBox -Message "No object deletion events found in selected files." -Title "No Results" -Icon Warning
    }
})
$form.Controls.Add($button)

# Make variables accessible in event handler
$script:form = $form
$script:progressBar = $progressBar

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
