#requires -Version 5.1
<#!
.SYNOPSIS
    Compiles failed AD logon attempts (Event ID 4625) from the live Security log or archived Security EVTX files using Log Parser 2.2.

.DESCRIPTION
    Revised for Windows Server 2019 / PowerShell 5.1, following the stable Print Audit architecture:
      - Live log handling through wevtutil snapshot export
      - Archived EVTX parsing through Log Parser COM
      - Count-safe file enumeration
      - Default CSV export path = My Documents
      - Single per-run log file in C:\Logs-TEMP
      - GUI-based execution with stable bottom-aligned actions

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    03-16-2026 - 2.0.0-WS2019-RevA
#>

[CmdletBinding()]
param(
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Console helpers
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
}
catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}

function Set-ConsoleVisibility {
    param([bool]$Visible)
    try {
        $hWnd = [Win32Console]::GetConsoleWindow()
        if ($hWnd -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($hWnd, $(if ($Visible) { 5 } else { 0 }))
        }
    }
    catch {}
}

if (-not $ShowConsole) { Set-ConsoleVisibility -Visible:$false }
#endregion

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load System.Windows.Forms/System.Drawing. $($_.Exception.Message)"
    exit 1
}

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Security'
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:Form = $null

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    try {
        Ensure-Directory -Path $script:LogDir
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
    }
    catch {}
}

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Set-Status {
    param([string]$Text)
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Text
        $script:Form.Refresh()
    }
}

function Set-Progress {
    param([int]$Value)
    if ($script:ProgressBar) {
        if ($Value -lt $script:ProgressBar.Minimum) { $Value = $script:ProgressBar.Minimum }
        if ($Value -gt $script:ProgressBar.Maximum) { $Value = $script:ProgressBar.Maximum }
        $script:ProgressBar.Value = $Value
        $script:Form.Refresh()
    }
}

function Get-LogParserComObjects {
    try {
        $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
        $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        return @($logQuery, $inputFormat, $outputFormat)
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed. $($_.Exception.Message)"
    }
}

function Get-LogParserExePath {
    $candidates = @(
        'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
        'C:\Program Files\Log Parser 2.2\LogParser.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function New-TempPath {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][ValidateSet('.evtx','.csv')][string]$Extension
    )
    $name = '{0}-{1}{2}' -f $Prefix, ([guid]::NewGuid().ToString('N')), $Extension
    return (Join-Path ([IO.Path]::GetTempPath()) $name)
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) {
        throw "wevtutil.exe was not found at '$wevtutil'."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.Arguments = ('epl "{0}" "{1}" /ow:true' -f $ChannelName, $DestinationPath)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($proc.ExitCode). StdErr=$stdErr"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "Snapshot export did not create '$DestinationPath'."
    }

    Write-Log "Live channel '$ChannelName' exported to temporary snapshot '$DestinationPath'."
}

function Build-4625Query {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$CsvPath,
        [string[]]$UserAccounts
    )

    $escapedSource = $SourcePath.Replace("'","''")
    $escapedCsv = $CsvPath.Replace("'","''")

    $userFilter = ''
    if ($UserAccounts -and @($UserAccounts).Count -gt 0) {
        $validUsers = @($UserAccounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
        if (@($validUsers).Count -gt 0) {
            $quoted = @($validUsers | ForEach-Object { "'" + ($_.Replace("'","''")) + "'" })
            $userFilter = ' AND EXTRACT_TOKEN(Strings, 5, ''|'') IN ({0})' -f ($quoted -join ',')
        }
    }

@"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 6, '|') AS DomainName,
    EXTRACT_TOKEN(Strings, 9, '|') AS SubStatusCode,
    EXTRACT_TOKEN(Strings, 10, '|') AS LogonType,
    EXTRACT_TOKEN(Strings, 12, '|') AS StationUser,
    EXTRACT_TOKEN(Strings, 13, '|') AS WorkstationName,
    EXTRACT_TOKEN(Strings, 19, '|') AS SourceIP,
    EXTRACT_TOKEN(Strings, 20, '|') AS SourcePort
INTO '$escapedCsv'
FROM '$escapedSource'
WHERE EventID = 4625$userFilter
"@
}

function Invoke-LogParserQueryToCsv {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationCsv,
        [string[]]$UserAccounts
    )

    $objects = Get-LogParserComObjects
    $logQuery = $objects[0]
    $inputFormat = $objects[1]
    $outputFormat = $objects[2]

    $query = Build-4625Query -SourcePath $SourcePath -CsvPath $DestinationCsv -UserAccounts $UserAccounts
    $result = $logQuery.ExecuteBatch($query, $inputFormat, $outputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $result for source '$SourcePath'."

    if (Test-Path -LiteralPath $DestinationCsv -PathType Leaf) {
        return
    }

    $header = 'EventTime,UserAccount,DomainName,SubStatusCode,LogonType,StationUser,WorkstationName,SourceIP,SourcePort'
    Set-Content -LiteralPath $DestinationCsv -Value $header -Encoding UTF8
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$CsvFiles,
        [Parameter(Mandatory)][string]$OutputCsv
    )

    $headerWritten = $false
    foreach ($csvFile in @($CsvFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) {
        $lines = @(Get-Content -LiteralPath $csvFile -Encoding UTF8)
        if (@($lines).Count -eq 0) { continue }

        if (-not $headerWritten) {
            Set-Content -LiteralPath $OutputCsv -Value $lines -Encoding UTF8
            $headerWritten = $true
        }
        else {
            if (@($lines).Count -gt 1) {
                Add-Content -LiteralPath $OutputCsv -Value ($lines | Select-Object -Skip 1) -Encoding UTF8
            }
        }
    }

    if (-not $headerWritten) {
        Set-Content -LiteralPath $OutputCsv -Value 'EventTime,UserAccount,DomainName,SubStatusCode,LogonType,StationUser,WorkstationName,SourceIP,SourcePort' -Encoding UTF8
    }
}

function Get-EventRowCount {
    param([Parameter(Mandatory)][string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    $rows = @(Import-Csv -LiteralPath $CsvPath)
    return @($rows).Count
}

function Resolve-OutputFolder {
    param([string]$RequestedPath)
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $script:DefaultOutputDir
    }
    return $RequestedPath
}

function Select-FolderDialog {
    param(
        [Parameter(Mandatory)][string]$Description,
        [string]$InitialPath
    )
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-UserAccountFilter {
    param([string]$RawText)
    if ([string]::IsNullOrWhiteSpace($RawText)) { return @() }
    return @($RawText -split '[,;\r\n]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
}

function Test-LiveChannelAccess {
    Set-Progress 5
    Set-Status 'Testing Security live channel snapshot...'

    $snapshotPath = New-TempPath -Prefix 'Security4625Probe' -Extension '.evtx'
    $probeCsv = New-TempPath -Prefix 'Security4625Probe' -Extension '.csv'
    try {
        Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $snapshotPath
        Invoke-LogParserQueryToCsv -SourcePath $snapshotPath -DestinationCsv $probeCsv -UserAccounts @()
        $count = Get-EventRowCount -CsvPath $probeCsv
        if ($count -gt 0) {
            Write-Log "Live channel probe completed successfully with $count sample row(s)."
        }
        else {
            Write-Log 'Live channel probe completed without sample rows. Treating channel access as valid.'
        }
        Set-Status 'Live Security channel is reachable.'
        Show-MessageBox -Message 'Live Security channel snapshot and parsing completed successfully.' -Title 'Resolve Channel'
    }
    finally {
        foreach ($p in @($snapshotPath, $probeCsv)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            }
        }
        Set-Progress 0
    }
}

function Start-Event4625Processing {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string[]]$UserAccounts
    )

    $resolvedOutputFolder = Resolve-OutputFolder -RequestedPath $OutputFolder
    Ensure-Directory -Path $resolvedOutputFolder

    $logParserExe = Get-LogParserExePath
    if ($logParserExe) {
        Write-Log "Using Log Parser executable: '$logParserExe'"
    }
    else {
        Write-Log 'LogParser.exe path not found, but COM objects will still be used if registered.' -Level 'WARN'
    }

    Write-Log "Starting Event ID 4625 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutputFolder'"

    $finalCsv = Join-Path $resolvedOutputFolder ('{0}-FailedLogons4625-{1}.csv' -f $script:MachineName, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $tempArtifacts = New-Object System.Collections.Generic.List[string]
    $intermediateCsvs = New-Object System.Collections.Generic.List[string]

    try {
        Set-Progress 10
        Set-Status 'Preparing input sources...'

        if ($UseLiveLog) {
            $snapshotPath = New-TempPath -Prefix 'Security4625Live' -Extension '.evtx'
            $tempCsv = New-TempPath -Prefix 'Security4625Live' -Extension '.csv'
            $tempArtifacts.Add($snapshotPath) | Out-Null
            $tempArtifacts.Add($tempCsv) | Out-Null

            Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $snapshotPath
            Set-Progress 45
            Set-Status 'Parsing live Security snapshot with Log Parser...'
            Invoke-LogParserQueryToCsv -SourcePath $snapshotPath -DestinationCsv $tempCsv -UserAccounts $UserAccounts
            $intermediateCsvs.Add($tempCsv) | Out-Null
        }
        else {
            if ([string]::IsNullOrWhiteSpace($EvtxFolder)) {
                throw 'An EVTX folder must be informed when live Security mode is disabled.'
            }
            if (-not (Test-Path -LiteralPath $EvtxFolder -PathType Container)) {
                throw "The EVTX folder '$EvtxFolder' does not exist."
            }

            $searchOption = if ($IncludeSubfolders) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
            $evtxFiles = @([System.IO.Directory]::EnumerateFiles($EvtxFolder, '*.evtx', $searchOption))
            if (@($evtxFiles).Count -eq 0) {
                throw "No .evtx files were found in '$EvtxFolder'."
            }

            $index = 0
            foreach ($evtxFile in $evtxFiles) {
                $index++
                $pct = [math]::Min(85, (10 + [int](($index / [double]@($evtxFiles).Count) * 70)))
                Set-Progress $pct
                Set-Status ('Parsing archived EVTX {0} of {1}...' -f $index, @($evtxFiles).Count)

                $tempCsv = New-TempPath -Prefix 'Security4625File' -Extension '.csv'
                $tempArtifacts.Add($tempCsv) | Out-Null
                Invoke-LogParserQueryToCsv -SourcePath $evtxFile -DestinationCsv $tempCsv -UserAccounts $UserAccounts
                $intermediateCsvs.Add($tempCsv) | Out-Null
                Write-Log "Processed archived EVTX '$evtxFile'."
            }
        }

        Set-Progress 90
        Set-Status 'Consolidating CSV output...'
        Merge-CsvFiles -CsvFiles @($intermediateCsvs) -OutputCsv $finalCsv

        $rowCount = Get-EventRowCount -CsvPath $finalCsv
        Write-Log "Found $rowCount failed logon event(s). Report exported to '$finalCsv'"
        Set-Progress 100
        Set-Status ("Completed. Found $rowCount failed logon event(s).")

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-MessageBox -Message "Found $rowCount failed logon event(s).`n`nReport exported to:`n$finalCsv" -Title 'Success'
    }
    catch {
        Write-Log "Error processing Event ID 4625: $($_.Exception.Message)" -Level 'ERROR'
        Set-Status 'Error occurred. Check log for details.'
        Show-MessageBox -Message "Error processing Event ID 4625: $($_.Exception.Message)" -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        foreach ($artifact in $tempArtifacts) {
            if ($artifact -and (Test-Path -LiteralPath $artifact)) {
                Remove-Item -LiteralPath $artifact -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Milliseconds 200
        Set-Progress 0
    }
}

Ensure-Directory -Path $script:LogDir
Write-Log "=== Starting $($script:ScriptName) ==="

#region GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Failed Logon Auditor - Event ID 4625'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 420)
$form.MinimumSize = New-Object System.Drawing.Size(760, 420)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Topmost = $false

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Font = $font

$leftLabel = 15
$leftControl = 185
$controlWidth = 440
$buttonBrowseX = 635
$rowY = 20
$rowStep = 34

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Text = 'Use live Security channel'
$checkUseLive.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkUseLive.AutoSize = $true
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$labelResolve = New-Object System.Windows.Forms.Label
$labelResolve.Text = 'Live channel test:'
$labelResolve.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 2))
$labelResolve.AutoSize = $true
$form.Controls.Add($labelResolve)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Size = New-Object System.Drawing.Size(120, 26)
$buttonResolve.Location = New-Object System.Drawing.Point(515, ($rowY - 2))
$form.Controls.Add($buttonResolve)

$rowY += $rowStep
$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Text = 'EVTX folder:'
$labelEvtx.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelEvtx.AutoSize = $true
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textEvtx.Size = New-Object System.Drawing.Size($controlWidth, 24)
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = '...'
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(35, 24)
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonBrowseX, ($rowY - 1))
$form.Controls.Add($buttonBrowseEvtx)

$rowY += $rowStep
$checkSubfolders = New-Object System.Windows.Forms.CheckBox
$checkSubfolders.Text = 'Include subfolders'
$checkSubfolders.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkSubfolders.AutoSize = $true
$checkSubfolders.Checked = $true
$form.Controls.Add($checkSubfolders)

$labelSubfolders = New-Object System.Windows.Forms.Label
$labelSubfolders.Text = 'Folder search:'
$labelSubfolders.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 2))
$labelSubfolders.AutoSize = $true
$form.Controls.Add($labelSubfolders)

$rowY += $rowStep
$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'User filter:'
$labelUsers.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelUsers.AutoSize = $true
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textUsers.Size = New-Object System.Drawing.Size(($controlWidth + 70), 24)
$textUsers.Text = ''
$form.Controls.Add($textUsers)

$rowY += $rowStep
$labelUsersHelp = New-Object System.Windows.Forms.Label
$labelUsersHelp.Text = 'Separate multiple accounts with comma, semicolon, or new line.'
$labelUsersHelp.Location = New-Object System.Drawing.Point($leftControl, ($rowY + 3))
$labelUsersHelp.AutoSize = $true
$form.Controls.Add($labelUsersHelp)

$rowY += $rowStep
$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = 'Output folder:'
$labelOutput.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelOutput.AutoSize = $true
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textOutput.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textOutput.Text = $script:DefaultOutputDir
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = '...'
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(35, 24)
$buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonBrowseX, ($rowY - 1))
$form.Controls.Add($buttonBrowseOutput)

$rowY += $rowStep
$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Text = 'Log folder:'
$labelLog.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelLog.AutoSize = $true
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textLog.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textLog.Text = $script:LogDir
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = '...'
$buttonBrowseLog.Size = New-Object System.Drawing.Size(35, 24)
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonBrowseX, ($rowY - 1))
$form.Controls.Add($buttonBrowseLog)

$rowY += 45
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(18, $rowY)
$script:ProgressBar.Size = New-Object System.Drawing.Size(690, 20)
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$form.Controls.Add($script:ProgressBar)

$rowY += 28
$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.Location = New-Object System.Drawing.Point(18, $rowY)
$script:StatusLabel.Size = New-Object System.Drawing.Size(690, 22)
$form.Controls.Add($script:StatusLabel)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Size = New-Object System.Drawing.Size(120, 32)
$buttonStart.Location = New-Object System.Drawing.Point(458, 320)
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Size = New-Object System.Drawing.Size(120, 32)
$buttonClose.Location = New-Object System.Drawing.Point(588, 320)
$form.Controls.Add($buttonClose)

$toggleMode = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = -not $isLive
    $buttonBrowseEvtx.Enabled = -not $isLive
    $checkSubfolders.Enabled = -not $isLive
}

$checkUseLive.Add_CheckedChanged($toggleMode)
& $toggleMode

$buttonBrowseEvtx.Add_Click({
    $selected = Select-FolderDialog -Description 'Select a folder containing Security EVTX files' -InitialPath $textEvtx.Text
    if ($selected) { $textEvtx.Text = $selected }
})

$buttonBrowseOutput.Add_Click({
    $selected = Select-FolderDialog -Description 'Select the CSV output folder' -InitialPath $textOutput.Text
    if ($selected) { $textOutput.Text = $selected }
})

$buttonBrowseLog.Add_Click({
    $selected = Select-FolderDialog -Description 'Select the log folder' -InitialPath $textLog.Text
    if ($selected) {
        $textLog.Text = $selected
        $script:LogDir = $selected
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        Ensure-Directory -Path $script:LogDir
    }
})

$buttonResolve.Add_Click({
    try {
        Test-LiveChannelAccess
    }
    catch {
        Write-Log "Resolve Channel failed: $($_.Exception.Message)" -Level 'ERROR'
        Set-Status 'Resolve Channel failed.'
        Show-MessageBox -Message "Resolve Channel failed: $($_.Exception.Message)" -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        Set-Progress 0
    }
})

$buttonStart.Add_Click({
    $buttonStart.Enabled = $false
    $buttonResolve.Enabled = $false
    try {
        Start-Event4625Processing -UseLiveLog $checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders $checkSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts (Get-UserAccountFilter -RawText $textUsers.Text)
    }
    finally {
        $buttonStart.Enabled = $true
        $buttonResolve.Enabled = $true
    }
})

$buttonClose.Add_Click({ $form.Close() })
$form.Add_Shown({ $form.Activate() })
$script:Form = $form
#endregion

[void]$form.ShowDialog()
Write-Log "=== Closing $($script:ScriptName) ==="

# End of script
