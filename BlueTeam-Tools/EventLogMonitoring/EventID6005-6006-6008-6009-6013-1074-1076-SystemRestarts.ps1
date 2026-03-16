<#
.SYNOPSIS
    System Restart Event Tracker (EventID 6005, 6006, 6008, 6009, 6013, 1074, 1076)

.DESCRIPTION
    WS2019 / PowerShell 5.1 compatible script for tracking restart-related events from the live
    System log or from archived EVTX files. Includes a minimal WinForms GUI, CSV export to
    My Documents by default, and logging to C:\Logs-TEMP.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-16-03 - WS2019-RevA2-GUI
#>

[CmdletBinding()]
param(
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:defaultLogFolder = 'C:\Logs-TEMP'
$script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
$script:progressBar = $null
$script:statusLabel = $null
$script:form = $null

function Initialize-LogDirectory {
    if (-not (Test-Path -LiteralPath $script:defaultLogFolder -PathType Container)) {
        New-Item -Path $script:defaultLogFolder -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARNING','ERROR')][string]$Level='INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    try { Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8 } catch {}
}

function Show-Info {
    param([string]$Message,[string]$Title='Information')
    [void][System.Windows.Forms.MessageBox]::Show($Message,$Title,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Message,[string]$Title='Error')
    [void][System.Windows.Forms.MessageBox]::Show($Message,$Title,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
}

function Update-ProgressSafe {
    param([int]$Value,[string]$StatusText)
    if ($script:progressBar) {
        $script:progressBar.Value = [Math]::Max(0,[Math]::Min(100,$Value))
    }
    if ($script:statusLabel -and $StatusText) {
        $script:statusLabel.Text = $StatusText
    }
    if ($script:form) { $script:form.Refresh() }
}

function Resolve-OutputFolder {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $script:defaultOutputFolder }
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

function Get-RestartEventsLive {
    Write-Log "Reading restart events from live System log."
    $ids = 6005,6006,6008,6009,6013,1074,1076
    $events = Get-WinEvent -FilterHashtable @{ LogName='System'; Id=$ids } -ErrorAction Stop |
        Select-Object TimeCreated, Id, MachineName, ProviderName, Message
    return @($events)
}

function Get-RestartEventsFromEvtx {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    Write-Log "Scanning EVTX folder '$Path'."

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "The EVTX folder '$Path' was not found."
    }

    if ($IncludeSubfolders) {
        $files = Get-ChildItem -LiteralPath $Path -Filter '*.evtx' -File -Recurse -ErrorAction Stop
    }
    else {
        $files = Get-ChildItem -LiteralPath $Path -Filter '*.evtx' -File -ErrorAction Stop
    }

    $files = @($files)
    if ($files.Count -eq 0) {
        throw "No .evtx files were found in '$Path'."
    }

    $ids = 6005,6006,6008,6009,6013,1074,1076
    $results = New-Object System.Collections.ArrayList
    $index = 0

    foreach ($file in $files) {
        $index++
        $percent = 10 + [int]([Math]::Floor(($index / $files.Count) * 75))
        Update-ProgressSafe -Value $percent -StatusText ("Processing {0} ({1} of {2})..." -f $file.Name, $index, $files.Count)
        Write-Log "Processing '$($file.FullName)'."

        $evts = Get-WinEvent -Path $file.FullName -ErrorAction Stop | Where-Object { $ids -contains $_.Id } |
            Select-Object TimeCreated, Id, MachineName, ProviderName, Message

        foreach ($evt in @($evts)) { [void]$results.Add($evt) }
    }

    return @($results)
}

function Process-SystemRestartEvents {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = Join-Path $resolvedOutput ("{0}-SystemRestarts-{1}.csv" -f $env:COMPUTERNAME, $timestamp)

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Preparing...'

        if ($UseLiveLog -or [string]::IsNullOrWhiteSpace($EvtxFolder)) {
            Write-Log "Using live System log mode."
            Update-ProgressSafe -Value 20 -StatusText 'Reading live System log...'
            $events = Get-RestartEventsLive
        }
        else {
            Write-Log "Using archived EVTX mode."
            $events = Get-RestartEventsFromEvtx -Path $EvtxFolder -IncludeSubfolders:$IncludeSubfolders
        }

        $events = @($events)
        Update-ProgressSafe -Value 92 -StatusText 'Exporting CSV...'
        $events | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

        Update-ProgressSafe -Value 100 -StatusText ("Completed. Found {0} events. Report saved to '{1}'" -f $events.Count, $csvPath)
        Write-Log "Export complete. Found $($events.Count) restart events. CSV: '$csvPath'"

        if ($AutoOpen -and (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
            Start-Process -FilePath $csvPath
        }

        Show-Info -Message ("Found {0} restart events.`r`nReport exported to:`r`n{1}" -f $events.Count, $csvPath) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message $_.Exception.Message
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error processing restart events.`r`n{0}" -f $_.Exception.Message)
    }
}

Initialize-LogDirectory

$form = New-Object System.Windows.Forms.Form
$form.Text = 'System Restarts Auditor (6005 / 6006 / 6008 / 6009 / 6013 / 1074 / 1076)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 350)
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

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Location = New-Object System.Drawing.Point($left, $currentY)
$checkUseLive.Size = New-Object System.Drawing.Size(250, 24)
$checkUseLive.Text = 'Use live System log'
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$currentY = $currentY + $rowHeight

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtx.Text = 'EVTX folder:'
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textEvtx.Size = New-Object System.Drawing.Size($textWidth, 24)
$textEvtx.Enabled = $false
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Enabled = $false
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
$buttonStart.Location = New-Object System.Drawing.Point(420, 302)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 302)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$toggleInputs = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
}
& $toggleInputs
$checkUseLive.Add_CheckedChanged($toggleInputs)

$buttonBrowseEvtx.Add_Click({
    $dialog = New-FolderPicker -Description 'Select a folder containing System EVTX files'
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
    $script:defaultLogFolder = $textLog.Text
    $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
    Initialize-LogDirectory

    Process-SystemRestartEvents -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text
})

$buttonClose.Add_Click({ $form.Close() })

$form.Add_Shown({ Write-Log 'Script initialized successfully.' })

[void]$form.ShowDialog()

# End of script
