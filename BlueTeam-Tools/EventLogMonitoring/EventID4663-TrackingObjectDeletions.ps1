<#
.SYNOPSIS
    PowerShell Script for Tracking Object Deletions via Event ID 4663 (Access Mask 0x10000) using Log Parser.

.DESCRIPTION
    This script analyzes object deletion events (Event ID 4663 with Access Mask 0x10000) from EVTX files 
    in a selected folder using COM-based LogQuery, exporting results to a CSV with user-configurable settings via a GUI.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: April 4, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the consolidated CSV file after processing.")]
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

$logDir = "C:\Logs-TEMP"
$outputFolderDefault = [Environment]::GetFolderPath('MyDocuments')
$logPath = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path $logDir)) {
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
        Description = "Select a folder containing Security .evtx files"
        ShowNewFolderButton = $false
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
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

function Get-ObjectDeletionEvents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$LogFolderPath,
        [Parameter(Mandatory)]
        [string]$OutputFolder,
        [string[]]$UserAccounts
    )

    Write-Log "Starting analysis in '$LogFolderPath'"
    $evtxFiles = Get-ChildItem -Path $LogFolderPath -Filter "*.evtx" -ErrorAction Stop
    if (-not $evtxFiles) {
        Show-MessageBox -Message "No .evtx files found." -Title "Input Error" -Icon Warning
        return
    }

    $totalFiles = $evtxFiles.Count
    $processedFiles = 0

    $LogQuery = New-Object -ComObject "MSUtil.LogQuery"
    $InputFormat = New-Object -ComObject "MSUtil.LogQuery.EventLogInputFormat"
    $OutputFormat = New-Object -ComObject "MSUtil.LogQuery.CSVOutputFormat"

    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $consolidatedFile = Join-Path $OutputFolder "EventID4663-ObjectDeletionTracking-$timestamp.csv"
    $tempCsvPath = Join-Path $env:TEMP "temp_deletion_$timestamp.csv"
    $outputFiles = [System.Collections.Generic.List[string]]::new()

    $userFilter = if ($UserAccounts -and $UserAccounts.Count -gt 0) {
        "'" + ($UserAccounts -join "';'") + "'"
    } else { "" }

    foreach ($file in $evtxFiles) {
        $processedFiles++
        Update-ProgressBar -Value ([math]::Round(($processedFiles / $totalFiles) * 50))
        $script:labelStatus.Text = "Processing $($file.Name) ($processedFiles of $totalFiles)..."
        $script:form.Refresh()

        $SQLQuery = @"
        SELECT 
            TimeGenerated AS DateTime,
            EventID,
            EXTRACT_TOKEN(Strings, 1, '|') AS UserAccount,
            EXTRACT_TOKEN(Strings, 2, '|') AS Domain,
            EXTRACT_TOKEN(Strings, 4, '|') AS LockoutCode,
            EXTRACT_TOKEN(Strings, 5, '|') AS ObjectType,
            EXTRACT_TOKEN(Strings, 6, '|') AS AccessedObject,
            EXTRACT_TOKEN(Strings, 7, '|') AS SubCode,
            EXTRACT_TOKEN(Strings, 8, '|') AS AccessMask
        INTO '$tempCsvPath'
        FROM '$($file.FullName)'
        WHERE EventID = 4663
            AND EXTRACT_TOKEN(Strings, 8, '|') = '0x10000'
            $(if ($userFilter) { "AND EXTRACT_TOKEN(Strings, 1, '|') IN ($userFilter)" } else { "" })
"@

        $rtnVal = $LogQuery.ExecuteBatch($SQLQuery, $InputFormat, $OutputFormat)
        if ($rtnVal -eq 0) {
            Write-Log "LogQuery failed for '$($file.Name)'" -Level Warning
            continue
        }

        if (Test-Path $tempCsvPath) {
            $outputFile = Join-Path $OutputFolder "$([System.IO.Path]::GetFileNameWithoutExtension($file.Name))_ObjectDeletionTracking.csv"
            if ($processedFiles -eq 1) {
                Get-Content $tempCsvPath | Set-Content $outputFile -Encoding UTF8
            } else {
                Get-Content $tempCsvPath | Select-Object -Skip 1 | Add-Content $outputFile -Encoding UTF8
            }
            $outputFiles.Add($outputFile)
            Remove-Item $tempCsvPath -Force
            Write-Log "Processed $($file.Name)"
        }
    }

    Update-ProgressBar -Value 75
    $script:labelStatus.Text = "Merging results..."
    $script:form.Refresh()

    if ($outputFiles.Count -gt 0) {
        Merge-CsvResults -InputFiles $outputFiles -OutputFile $consolidatedFile
        if (Test-Path $consolidatedFile) {
            $eventCount = (Import-Csv $consolidatedFile).Count
            Write-Log "Total of $eventCount events found"
            Update-ProgressBar -Value 100
            Show-MessageBox -Message "Analysis complete. Found $eventCount events.`nSaved to:`n$consolidatedFile" -Title "Success"
            if ($AutoOpen) { Start-Process -FilePath $consolidatedFile }
            $script:labelStatus.Text = "Completed. Found $eventCount events."
        }
    } else {
        Write-Log "No deletion events found" -Level Warning
        Show-MessageBox -Message "No object deletion events (4663, Access Mask 0x10000) found." -Title "No Results" -Icon Warning
        $script:labelStatus.Text = "No events found."
    }
    Update-ProgressBar -Value 0
    if (Test-Path $tempCsvPath) { Remove-Item $tempCsvPath -Force }
}
#endregion

#region GUI
$form = New-Object System.Windows.Forms.Form -Property @{
    Text = 'Object Deletion Event Parser (4663, Access Mask 0x10000)'
    Size = '450,350'
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox = $false
}

$labelUsers = New-Object System.Windows.Forms.Label -Property @{
    Location = '10,20'
    Size = '100,20'
    Text = 'User Accounts:'
}
$form.Controls.Add($labelUsers)

$textBoxUsers = New-Object System.Windows.Forms.TextBox -Property @{
    Location = '120,20'
    Size = '320,60'
    Multiline = $true
    Text = 'user01, user02, user03'
}
$form.Controls.Add($textBoxUsers)

$labelLogDir = New-Object System.Windows.Forms.Label -Property @{
    Location = '10,90'
    Size = '100,20'
    Text = 'Log Directory:'
}
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = '120,90'
    Size = '200,20'
    Text = $logDir
}
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button -Property @{
    Location = '330,90'
    Size = '100,20'
    Text = 'Browse'
}
$buttonBrowseLogDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { $textBoxLogDir.Text = $folder }
})
$form.Controls.Add($buttonBrowseLogDir)

$labelOutputDir = New-Object System.Windows.Forms.Label -Property @{
    Location = '10,120'
    Size = '100,20'
    Text = 'Output Folder:'
}
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = '120,120'
    Size = '200,20'
    Text = $outputFolderDefault
}
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button -Property @{
    Location = '330,120'
    Size = '100,20'
    Text = 'Browse'
}
$buttonBrowseOutputDir.Add_Click({
    $folder = Select-Folder
    if ($folder) { $textBoxOutputDir.Text = $folder }
})
$form.Controls.Add($buttonBrowseOutputDir)

$labelStatus = New-Object System.Windows.Forms.Label -Property @{
    Location = '10,180'
    Size = '430,20'
    Text = 'Ready'
}
$form.Controls.Add($labelStatus)

$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = '10,210'
    Size = '430,20'
}
$form.Controls.Add($progressBar)

$button = New-Object System.Windows.Forms.Button -Property @{
    Location = '10,240'
    Size = '100,30'
    Text = 'Start Analysis'
}
$button.Add_Click({
    $script:logDir = $textBoxLogDir.Text
    $script:logPath = Join-Path $script:logDir "${scriptName}.log"
    $outputFolder = $textBoxOutputDir.Text
    if (-not (Test-Path $script:logDir)) {
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }
    $userAccounts = if ($textBoxUsers.Text) { $textBoxUsers.Text -split ',\s*' | ForEach-Object { $_.Trim() } } else { @() }

    Write-Log "Analysis started for users: $($userAccounts -join ', ')"
    $script:labelStatus.Text = "Selecting folder..."
    $script:form.Refresh()

    $evtxFolder = Select-Folder
    if (-not $evtxFolder) {
        Show-MessageBox -Message "No folder selected." -Title "Input Required" -Icon Warning
        $script:labelStatus.Text = "Ready"
        return
    }

    $script:labelStatus.Text = "Processing files..."
    $script:form.Refresh()
    Get-ObjectDeletionEvents -LogFolderPath $evtxFolder -OutputFolder $outputFolder -UserAccounts $userAccounts
})
$form.Controls.Add($button)

$script:form = $form
$script:progressBar = $progressBar
$script:labelStatus = $labelStatus

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
