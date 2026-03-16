<#
.SYNOPSIS
    PowerShell Script for counting Event ID occurrences across EVTX files using Log Parser COM.

.DESCRIPTION
    This WS2019-compatible revision counts Event ID occurrences in archived .evtx files from a selected
    folder, with optional recursion into subfolders. It uses Log Parser COM for parsing and exports the
    consolidated CSV report to My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-16-03 - RevA - WS2019-compatible migration
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true,

    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Native console visibility
try {
    $consoleType = [System.Management.Automation.PSTypeName]'Win32Console'
    if (-not $consoleType.Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Win32Console {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
    }

    if (-not $ShowConsole.IsPresent) {
        $consoleHandle = [Win32Console]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($consoleHandle, 0)
        }
    }
}
catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}
#endregion

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required assemblies. $($_.Exception.Message)"
    exit 1
}

#region Variables
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$computerName = [Environment]::MachineName
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:defaultLogFolder = 'C:\Logs-TEMP'
$script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
$script:tempArtifacts = New-Object System.Collections.ArrayList
$script:progressBar = $null
$script:statusLabel = $null
$script:form = $null
#endregion

#region Helpers
function Initialize-LogDirectory {
    if (-not (Test-Path -LiteralPath $script:defaultLogFolder -PathType Container)) {
        New-Item -Path $script:defaultLogFolder -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    try {
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
    }
    catch {
    }
}

function Show-Info {
    param([string]$Message, [string]$Title = 'Information')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Message, [string]$Title = 'Error')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Update-ProgressSafe {
    param([int]$Value, [string]$StatusText)

    if ($script:progressBar) {
        $bounded = [Math]::Max(0, [Math]::Min(100, $Value))
        $script:progressBar.Value = $bounded
    }

    if ($script:statusLabel -and $StatusText) {
        $script:statusLabel.Text = $StatusText
    }

    if ($script:form) {
        $script:form.Refresh()
    }
}

function Resolve-OutputFolder {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $script:defaultOutputFolder
    }

    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        New-Item -Path $Candidate -ItemType Directory -Force | Out-Null
    }

    return $Candidate
}

function New-FolderPicker {
    param([string]$Description)

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    return $dialog
}

function Register-TempArtifact {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        [void]$script:tempArtifacts.Add($Path)
    }
}

function Remove-TempArtifacts {
    foreach ($artifact in @($script:tempArtifacts)) {
        try {
            if (Test-Path -LiteralPath $artifact) {
                Remove-Item -LiteralPath $artifact -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
    $script:tempArtifacts.Clear() | Out-Null
}

function New-LogParserObjects {
    $objects = [ordered]@{
        Query        = New-Object -ComObject 'MSUtil.LogQuery'
        InputFormat  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        OutputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
    }
    return $objects
}

function New-HeaderOnlyCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $header = 'EventID,Count,SourceFile'
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function Get-RowCountSafe {
    param([string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        return 0
    }

    try {
        $rows = Import-Csv -LiteralPath $CsvPath
        return @($rows).Count
    }
    catch {
        return 0
    }
}

function Get-EvtxFilesSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "The EVTX folder '$RootPath' was not found."
    }

    if ($IncludeSubfolders) {
        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop
    }
    else {
        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -ErrorAction Stop
    }

    return @($files)
}

function Build-QueryForFile {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")

$query = @"
SELECT
    EventID,
    COUNT(*) AS Count,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
GROUP BY EventID
ORDER BY EventID ASC
"@
    return $query
}

function Invoke-EventCountToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath
    )

    $lp = New-LogParserObjects
    $lp.OutputFormat.fileName = $CsvPath
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath

    $result = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $result for '$EvtxPath'"

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }
}

function Merge-CsvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$SourceCsvFiles,
        [Parameter(Mandatory)][string]$DestinationCsv
    )

    $existing = @($SourceCsvFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if (@($existing).Count -eq 0) {
        New-HeaderOnlyCsv -Path $DestinationCsv
        return
    }

    $first = $true
    foreach ($csv in @($existing)) {
        if ($first) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $first = $false
        }
        else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
}

function Process-EvtxEventCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter()][string]$OutputFolder
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ('{0}-AllEvtxEventCounts-{1}.csv' -f $computerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.ArrayList

    Write-Log "Starting EVTX Event ID counting. Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'"

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Enumerating archived EVTX files...'
        $sourceFiles = Get-EvtxFilesSafe -RootPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders

        $sourceCount = @($sourceFiles).Count
        if ($sourceCount -eq 0) {
            throw 'No .evtx files were found to process.'
        }

        $index = 0
        foreach ($source in @($sourceFiles)) {
            $index++
            $percent = 5 + [int]([Math]::Floor(($index / $sourceCount) * 75))
            Update-ProgressSafe -Value $percent -StatusText ("Processing {0} ({1} of {2})..." -f $source.Name, $index, $sourceCount)

            $tempCsv = Join-Path $env:TEMP ('EventCounts-{0}-{1}.csv' -f $index, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
            Register-TempArtifact -Path $tempCsv
            [void]$tempCsvFiles.Add($tempCsv)

            Invoke-EventCountToCsv -EvtxPath $source.FullName -CsvPath $tempCsv
            Write-Log "Processed '$($source.FullName)'."
        }

        Update-ProgressSafe -Value 85 -StatusText 'Merging CSV files...'
        Merge-CsvFiles -SourceCsvFiles @($tempCsvFiles) -DestinationCsv $finalCsv

        $rowCount = Get-RowCountSafe -CsvPath $finalCsv
        Update-ProgressSafe -Value 100 -StatusText ("Completed. Found {0} Event ID rows. Report saved to '{1}'" -f $rowCount, $finalCsv)
        Write-Log "Found $rowCount Event ID count rows. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-Info -Message ("Found {0} Event ID rows.`r`nReport exported to:`r`n{1}" -f $rowCount, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Error counting Event IDs. $($_.Exception.Message)"
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error counting Event IDs.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        Remove-TempArtifacts
    }
}
#endregion

#region GUI
Initialize-LogDirectory

$form = New-Object System.Windows.Forms.Form
$form.Text = 'EVTX Event ID Counter'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 352)
$script:form = $form

$left = 14
$top = 16
$labelWidth = 165
$textWidth = 455
$buttonWidth = 92
$rowHeight = 38
$buttonGap = 10
$buttonX = ($left + $labelWidth + $textWidth + $buttonGap)
$currentY = $top

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtx.Text = 'EVTX folder:'
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textEvtx.Size = New-Object System.Drawing.Size($textWidth, 24)
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$form.Controls.Add($buttonBrowseEvtx)

$currentY = $currentY + $rowHeight

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point($left, $currentY)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(240, 24)
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$form.Controls.Add($checkIncludeSubfolders)

$currentY = $currentY + $rowHeight

$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelOutput.Text = 'CSV output folder:'
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textOutput.Size = New-Object System.Drawing.Size($textWidth, 24)
$textOutput.Text = $script:defaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseOutput.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseOutput.Text = 'Browse'
$form.Controls.Add($buttonBrowseOutput)

$currentY = $currentY + $rowHeight

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelLog.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelLog.Text = 'Log folder:'
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textLog.Size = New-Object System.Drawing.Size($textWidth, 24)
$textLog.Text = $script:defaultLogFolder
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseLog.Text = 'Browse'
$form.Controls.Add($buttonBrowseLog)

$currentY = $currentY + $rowHeight + 4

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point($left, $currentY)
$progressBar.Size = New-Object System.Drawing.Size(716, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)
$script:progressBar = $progressBar

$currentY = $currentY + 28

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point($left, $currentY)
$statusLabel.Size = New-Object System.Drawing.Size(716, 32)
$statusLabel.Text = 'Ready.'
$form.Controls.Add($statusLabel)
$script:statusLabel = $statusLabel

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Size = New-Object System.Drawing.Size(150, 30)
$buttonStart.Location = New-Object System.Drawing.Point(420, 304)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 304)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$buttonBrowseEvtx.Add_Click({
    $dialog = New-FolderPicker -Description 'Select a folder containing EVTX files'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textEvtx.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseOutput.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the folder where the CSV report will be saved'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textOutput.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseLog.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the log folder'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textLog.Text = $dialog.SelectedPath
        $script:defaultLogFolder = $dialog.SelectedPath
        $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
        Initialize-LogDirectory
    }
    $dialog.Dispose()
})

$buttonStart.Add_Click({
    if ([string]::IsNullOrWhiteSpace($textEvtx.Text)) {
        Show-ErrorBox -Message 'Please select a folder containing EVTX files.' -Title 'Input Required'
        return
    }

    $script:defaultLogFolder = $textLog.Text
    $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
    Initialize-LogDirectory

    Process-EvtxEventCounts -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text
})

$buttonClose.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    Write-Log 'Script initialized successfully.'
})

[void]$form.ShowDialog()
#endregion

# End of script
