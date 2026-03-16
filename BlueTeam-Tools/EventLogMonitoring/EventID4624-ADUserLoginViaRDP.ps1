<#
.SYNOPSIS
    Audits successful RDP logons via Event ID 4624 (Logon Type 10) using Log Parser on Windows Server 2019.

.DESCRIPTION
    Supports live Security log analysis through a temporary EVTX snapshot created with wevtutil,
    and archived EVTX analysis from a selected folder. Results are exported to CSV in the user's
    My Documents folder by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-03-16 - WS2019-RevA
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Automatically open the consolidated CSV file after processing.')]
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
    if (-not $ShowConsole) {
        $consoleHwnd = [Win32Console]::GetConsoleWindow()
        if ($consoleHwnd -ne [IntPtr]::Zero) { [void][Win32Console]::ShowWindow($consoleHwnd, 0) }
    }
}
catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}
#endregion

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($scriptName + '.log')
$script:LiveChannelName = 'Security'
$script:ProgressBar = $null
$script:Form = $null
$script:StatusLabel = $null

if (-not (Test-Path -LiteralPath $script:LogDir)) {
    New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $entry = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    try { Add-Content -Path $script:LogPath -Value $entry -Encoding UTF8 } catch {}
}

function Show-UiMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Set-Status {
    param([string]$Text, [int]$Progress = -1)
    if ($script:StatusLabel) { $script:StatusLabel.Text = $Text }
    if ($script:ProgressBar -and $Progress -ge 0) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Progress))
    }
    if ($script:Form) {
        $script:Form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-DefaultOutputFolder {
    param([string]$Preferred)
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) { return $Preferred }
    return $script:DefaultOutputFolder
}

function Select-FolderPath {
    param([Parameter(Mandatory)][string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-LogParserComObjects {
    try {
        return [pscustomobject]@{
            Query  = New-Object -ComObject 'MSUtil.LogQuery'
            Input  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
            Output = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        }
    }
    catch {
        throw 'Microsoft Log Parser 2.2 COM components are not available.'
    }
}

function New-EmptyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    Set-Content -Path $Path -Value ($Headers -join ',') -Encoding UTF8
}

function Export-LiveChannelSnapshot {
    param([Parameter(Mandatory)][string]$ChannelName)

    $tempDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
    Ensure-Directory -Path $tempDir
    $snapshotPath = Join-Path $tempDir ('{0}-{1}.evtx' -f ($ChannelName -replace '[^A-Za-z0-9_-]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wevtutil.exe'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = ('epl "{0}" "{1}" /ow:true' -f $ChannelName, $snapshotPath)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshotPath)) {
        throw ("wevtutil export failed. ExitCode={0}. StdErr={1}" -f $process.ExitCode, $stdErr.Trim())
    }

    Write-Log "Live channel snapshot exported to '$snapshotPath'."
    return $snapshotPath
}

function Get-SanitizedUserList {
    param([string]$RawText)

    if ([string]::IsNullOrWhiteSpace($RawText)) { return @() }

    $items = $RawText -split '[,;\r\n]'
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        $value = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $value = $value.Replace("'", "''")
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$list.Add($value)
        }
    }
    return @($list.ToArray())
}

function Invoke-RdpQuery {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [string[]]$UserAccounts
    )

    $com = Get-LogParserComObjects
    $com.Output.fileName = $CsvPath

    $userPredicate = ''
    if (@($UserAccounts).Count -gt 0) {
        $quotedUsers = @($UserAccounts | ForEach-Object { "'$_'" })
        $userPredicate = (' AND EXTRACT_TOKEN(Strings, 5, ''|'') IN ({0})' -f ($quotedUsers -join ','))
    }

    $safePath = $EvtxPath.Replace("'", "''")
    $safeCsv = $CsvPath.Replace("'", "''")
    $sql = @"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 6, '|') AS Domain,
    EXTRACT_TOKEN(Strings, 11, '|') AS Workstation,
    EXTRACT_TOKEN(Strings, 18, '|') AS SourceIP,
    EXTRACT_TOKEN(Strings, 10, '|') AS SubStatusCode,
    EXTRACT_TOKEN(Strings, 11, '|') AS AccessedResource,
    EXTRACT_TOKEN(Strings, 8, '|') AS LogonType,
    ComputerName AS ComputerName,
    '$safePath' AS SourceFile
INTO '$safeCsv'
FROM '$safePath'
WHERE EventID = 4624
  AND EXTRACT_TOKEN(Strings, 8, '|') = '10'
  AND EXTRACT_TOKEN(Strings, 5, '|') NOT IN ('SYSTEM','ANONYMOUS LOGON','LOCAL SERVICE','NETWORK SERVICE')
  AND EXTRACT_TOKEN(Strings, 6, '|') NOT IN ('NT AUTHORITY')$userPredicate
"@

    try {
        $result = $com.Query.ExecuteBatch($sql, $com.Input, $com.Output)
        Write-Log ("Log Parser ExecuteBatch returned: {0}" -f $result)
    }
    catch {
        throw ("Log Parser query failed for '{0}'. {1}" -f $EvtxPath, $_.Exception.Message)
    }

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        New-EmptyCsv -Path $CsvPath -Headers @('EventTime','UserAccount','Domain','Workstation','SourceIP','SubStatusCode','AccessedResource','LogonType','ComputerName','SourceFile')
    }
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$CsvPaths,
        [Parameter(Mandatory)][string]$FinalCsvPath
    )

    $headerWritten = $false
    foreach ($csvPath in $CsvPaths) {
        if (-not (Test-Path -LiteralPath $csvPath)) { continue }
        $lines = @(Get-Content -LiteralPath $csvPath -ErrorAction Stop)
        if (@($lines).Count -eq 0) { continue }

        if (-not $headerWritten) {
            Set-Content -Path $FinalCsvPath -Value $lines -Encoding UTF8
            $headerWritten = $true
        }
        else {
            @($lines | Select-Object -Skip 1) | Add-Content -Path $FinalCsvPath -Encoding UTF8
        }
    }

    if (-not $headerWritten) {
        New-EmptyCsv -Path $FinalCsvPath -Headers @('EventTime','UserAccount','Domain','Workstation','SourceIP','SubStatusCode','AccessedResource','LogonType','ComputerName','SourceFile')
    }
}

function Invoke-RdpAudit {
    param(
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter()][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter()][string]$OutputFolder,
        [Parameter()][string]$UserFilterText
    )

    $resolvedOutput = Get-DefaultOutputFolder -Preferred $OutputFolder
    Ensure-Directory -Path $resolvedOutput

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $computerName = $env:COMPUTERNAME
    $finalCsv = Join-Path $resolvedOutput ('{0}-RDPLogons-{1}.csv' -f $computerName, $timestamp)
    $tempDir = Join-Path $env:TEMP ('RdpAudit-{0}' -f $timestamp)
    Ensure-Directory -Path $tempDir

    $tempCsvFiles = New-Object System.Collections.Generic.List[string]
    $snapshotPath = $null

    try {
        Write-Log "Starting Event ID 4624 RDP processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'"
        Set-Status -Text 'Preparing audit...' -Progress 5

        $userAccounts = Get-SanitizedUserList -RawText $UserFilterText

        $evtxFiles = @()
        if ($UseLiveLog) {
            Set-Status -Text 'Exporting live Security snapshot...' -Progress 15
            $snapshotPath = Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName
            $evtxFiles = @([IO.FileInfo]::new($snapshotPath))
        }
        else {
            if ([string]::IsNullOrWhiteSpace($EvtxFolder) -or -not (Test-Path -LiteralPath $EvtxFolder -PathType Container)) {
                throw 'The EVTX folder is invalid or was not provided.'
            }

            Set-Status -Text 'Enumerating EVTX files...' -Progress 15
            $searchOption = if ($IncludeSubfolders) { '-Recurse' } else { '' }
            if ($IncludeSubfolders) {
                $evtxFiles = @(Get-ChildItem -Path $EvtxFolder -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
            }
            else {
                $evtxFiles = @(Get-ChildItem -Path $EvtxFolder -Filter '*.evtx' -File -ErrorAction Stop)
            }
        }

        if (@($evtxFiles).Count -eq 0) {
            throw 'No EVTX files were found to process.'
        }

        $total = @($evtxFiles).Count
        $index = 0
        foreach ($evtxFile in $evtxFiles) {
            $index++
            $progress = 20 + [int]([Math]::Round(($index / $total) * 60))
            Set-Status -Text ("Processing {0} ({1} of {2})..." -f $evtxFile.Name, $index, $total) -Progress $progress

            $tempCsv = Join-Path $tempDir ('rdp_{0:0000}.csv' -f $index)
            Invoke-RdpQuery -EvtxPath $evtxFile.FullName -CsvPath $tempCsv -UserAccounts $userAccounts
            [void]$tempCsvFiles.Add($tempCsv)
            Write-Log "Processed '$($evtxFile.FullName)'."
        }

        Set-Status -Text 'Consolidating CSV output...' -Progress 90
        Merge-CsvFiles -CsvPaths @($tempCsvFiles.ToArray()) -FinalCsvPath $finalCsv

        $eventCount = [Math]::Max(0, (@(Get-Content -LiteralPath $finalCsv).Count - 1))
        Write-Log "Found $eventCount RDP logon events. Report exported to '$finalCsv'"
        Set-Status -Text ("Completed. Found {0} RDP logon events." -f $eventCount) -Progress 100

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv)) {
            Start-Process -FilePath $finalCsv
        }

        Show-UiMessage -Message ("Found {0} RDP logon events.`nReport exported to:`n{1}" -f $eventCount, $finalCsv) -Title 'Success'
    }
    finally {
        foreach ($tempCsv in @($tempCsvFiles.ToArray())) {
            if (Test-Path -LiteralPath $tempCsv) {
                Remove-Item -LiteralPath $tempCsv -Force -ErrorAction SilentlyContinue
            }
        }
        if ($snapshotPath -and (Test-Path -LiteralPath $snapshotPath)) {
            Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-LiveChannelProbe {
    $snapshot = $null
    $probeCsv = $null
    try {
        Set-Status -Text 'Resolving Security channel...' -Progress 10
        $snapshot = Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName
        $probeCsv = Join-Path $env:TEMP ('rdp_probe_{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
        Invoke-RdpQuery -EvtxPath $snapshot -CsvPath $probeCsv -UserAccounts @()
        Write-Log 'Live channel probe completed successfully.'
        Set-Status -Text 'Security channel probe completed successfully.' -Progress 100
        Show-UiMessage -Message 'Live Security channel is accessible through snapshot export and Log Parser.' -Title 'Resolve Channel'
    }
    finally {
        if ($probeCsv -and (Test-Path -LiteralPath $probeCsv)) {
            Remove-Item -LiteralPath $probeCsv -Force -ErrorAction SilentlyContinue
        }
        if ($snapshot -and (Test-Path -LiteralPath $snapshot)) {
            Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue
        }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'RDP Logon Auditor - Event ID 4624 (Logon Type 10)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 385)
$script:Form = $form

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Font = $font

$rowY = 18
$labelWidth = 150
$controlWidth = 470
$leftMargin = 14
$controlX = 170

$checkLive = New-Object System.Windows.Forms.CheckBox
$checkLive.Text = 'Use live Security channel'
$checkLive.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$checkLive.Size = New-Object System.Drawing.Size(220, 24)
$checkLive.Checked = $true
$form.Controls.Add($checkLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Location = New-Object System.Drawing.Point(590, ($rowY - 2))
$buttonResolve.Size = New-Object System.Drawing.Size(140, 28)
$form.Controls.Add($buttonResolve)

$rowY += 38
$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'User Accounts Filter:'
$labelUsers.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 22)
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point($controlX, ($rowY - 2))
$textUsers.Size = New-Object System.Drawing.Size($controlWidth, 52)
$textUsers.Multiline = $true
$textUsers.ScrollBars = 'Vertical'
$textUsers.Text = 'user01, user02, user03'
$form.Controls.Add($textUsers)

$rowY += 64
$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Text = 'EVTX Folder:'
$labelEvtx.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 22)
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point($controlX, ($rowY - 2))
$textEvtx.Size = New-Object System.Drawing.Size(390, 24)
$textEvtx.Enabled = $false
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = 'Browse...'
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(90, 26)
$buttonBrowseEvtx.Enabled = $false
$form.Controls.Add($buttonBrowseEvtx)

$rowY += 34
$checkSubfolders = New-Object System.Windows.Forms.CheckBox
$checkSubfolders.Text = 'Include subfolders when scanning archived EVTX files'
$checkSubfolders.Location = New-Object System.Drawing.Point($controlX, $rowY)
$checkSubfolders.Size = New-Object System.Drawing.Size(360, 24)
$checkSubfolders.Checked = $true
$checkSubfolders.Enabled = $false
$form.Controls.Add($checkSubfolders)

$rowY += 34
$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = 'Output Folder:'
$labelOutput.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 22)
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point($controlX, ($rowY - 2))
$textOutput.Size = New-Object System.Drawing.Size(390, 24)
$textOutput.Text = $script:DefaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = 'Browse...'
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($buttonBrowseOutput)

$rowY += 34
$labelLogFolder = New-Object System.Windows.Forms.Label
$labelLogFolder.Text = 'Log Folder:'
$labelLogFolder.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$labelLogFolder.Size = New-Object System.Drawing.Size($labelWidth, 22)
$form.Controls.Add($labelLogFolder)

$textLogFolder = New-Object System.Windows.Forms.TextBox
$textLogFolder.Location = New-Object System.Drawing.Point($controlX, ($rowY - 2))
$textLogFolder.Size = New-Object System.Drawing.Size(390, 24)
$textLogFolder.Text = $script:LogDir
$form.Controls.Add($textLogFolder)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = 'Browse...'
$buttonBrowseLog.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseLog.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($buttonBrowseLog)

$rowY += 42
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$script:ProgressBar.Size = New-Object System.Drawing.Size(716, 22)
$script:ProgressBar.Style = 'Continuous'
$form.Controls.Add($script:ProgressBar)

$rowY += 30
$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.Location = New-Object System.Drawing.Point($leftMargin, $rowY)
$script:StatusLabel.Size = New-Object System.Drawing.Size(716, 22)
$form.Controls.Add($script:StatusLabel)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Size = New-Object System.Drawing.Size(120, 30)
$buttonStart.Location = New-Object System.Drawing.Point(486, 335)
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(616, 335)
$form.Controls.Add($buttonClose)

$toggleMode = {
    $isLive = $checkLive.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
    $checkSubfolders.Enabled = (-not $isLive)
}

$checkLive.Add_CheckedChanged($toggleMode)
& $toggleMode

$buttonBrowseEvtx.Add_Click({
    $selected = Select-FolderPath -Description 'Select a folder containing Security EVTX files'
    if ($selected) { $textEvtx.Text = $selected }
})

$buttonBrowseOutput.Add_Click({
    $selected = Select-FolderPath -Description 'Select an output folder for the CSV report'
    if ($selected) { $textOutput.Text = $selected }
})

$buttonBrowseLog.Add_Click({
    $selected = Select-FolderPath -Description 'Select the folder that will store the execution log'
    if ($selected) {
        $textLogFolder.Text = $selected
        $script:LogDir = $selected
        Ensure-Directory -Path $script:LogDir
        $script:LogPath = Join-Path $script:LogDir ($scriptName + '.log')
    }
})

$buttonResolve.Add_Click({
    try {
        Test-LiveChannelProbe
    }
    catch {
        Write-Log -Message ("Resolve Channel failed: {0}" -f $_.Exception.Message) -Level 'ERROR'
        Set-Status -Text 'Resolve Channel failed.' -Progress 0
        Show-UiMessage -Message ("Resolve Channel failed: {0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonStart.Add_Click({
    try {
        Write-Log 'Starting print audit analysis.'
        Invoke-RdpAudit -UseLiveLog $checkLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders $checkSubfolders.Checked -OutputFolder $textOutput.Text -UserFilterText $textUsers.Text
    }
    catch {
        Write-Log -Message ("Error processing Event ID 4624 RDP: {0}" -f $_.Exception.Message) -Level 'ERROR'
        Set-Status -Text 'Error occurred. Check the execution log.' -Progress 0
        Show-UiMessage -Message ("Error processing Event ID 4624 RDP: {0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonClose.Add_Click({ $form.Close() })

Write-Log 'RDP Logon Auditor initialized.'
[void]$form.ShowDialog()

# End of script
