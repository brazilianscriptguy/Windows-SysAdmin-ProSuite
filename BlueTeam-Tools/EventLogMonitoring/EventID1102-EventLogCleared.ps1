<#
.SYNOPSIS
  Detects Security Event ID 1102 events indicating that the audit log was cleared.

.DESCRIPTION
  Production GUI tool for analyzing live Security snapshots or archived EVTX files with Log Parser 2.2. It follows the established Log Parser-first model, preserves archive-safe processing, supports date range filters, and exports a USA-English forensic CSV report.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-05-v5.1.5-PRODUCTION-DATERANGE-HOTFIX
#>

[CmdletBinding()]
param(
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole,
    [switch]$VerboseSqlLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    if (-not $ShowConsole.IsPresent) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeConsoleWindow {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue
        $consoleHandle = [NativeConsoleWindow]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) { [void][NativeConsoleWindow]::ShowWindow($consoleHandle, 0) }
    }
}
catch { }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
}
catch { }

[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    try {
        $message = $eventArgs.Exception.Message
        Write-Log -Level 'ERROR' -Message ("Unhandled WinForms thread exception. {0}" -f $message)
        [void][System.Windows.Forms.MessageBox]::Show(
            ("An unexpected GUI error occurred.`r`n{0}`r`n`r`nCheck the execution log for details." -f $message),
            'Unhandled GUI Error',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
    catch { }
})

[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    try {
        $message = [string]$eventArgs.ExceptionObject
        Write-Log -Level 'ERROR' -Message ("Unhandled application exception. {0}" -f $message)
    }
    catch { }
})

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:ComputerName = [Environment]::MachineName
$script:DefaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:DefaultLogFolder = 'C:\Logs-TEMP'
$script:LogPath = Join-Path $script:DefaultLogFolder ('{0}.log' -f $script:ScriptName)
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:Form = $null
$script:LastCsv = $null
$script:TempArtifacts = New-Object System.Collections.ArrayList

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    try {
        Ensure-Directory -Path $script:DefaultLogFolder
        $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $script:LogPath -Value $entry -Encoding UTF8
    }
    catch { }
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Information',
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$Context
    )
    try { & $ScriptBlock }
    catch {
        $message = $_.Exception.Message
        Write-Log -Level 'ERROR' -Message ("{0} failed. {1}" -f $Context, $message)
        Update-UiState -Progress 0 -Status ("{0} failed. Check the execution log." -f $Context)
        Show-Message -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) -Message ("{0} failed.`r`n{1}" -f $Context, $message)
    }
}

function Update-UiState {
    param([int]$Progress, [string]$Status)
    if ($script:ProgressBar) { $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Progress)) }
    if ($script:StatusLabel) { $script:StatusLabel.Text = $Status }
    if ($script:Form) { $script:Form.Refresh() }
}

function Register-TempArtifact {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) { [void]$script:TempArtifacts.Add($Path) }
}

function Remove-TempArtifacts {
    foreach ($item in @($script:TempArtifacts)) {
        try { if (Test-Path -LiteralPath $item) { Remove-Item -LiteralPath $item -Force -ErrorAction SilentlyContinue } } catch { }
    }
    $script:TempArtifacts.Clear() | Out-Null
}

function Test-FileLocked {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $false
    }
    catch { return $true }
    finally { if ($stream) { $stream.Dispose() } }
}

function Test-ActiveEvtxName {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    $activeNames = @('Security.evtx','Application.evtx','System.evtx','Setup.evtx','State.evtx','Active Directory Web Services.evtx')
    return ($activeNames -contains $File.Name)
}

function Get-ArchiveSafeEvtxFiles {
    param([Parameter(Mandatory)][string]$RootPath, [bool]$IncludeSubfolders)
    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { throw "EVTX folder not found: $RootPath" }
    if ($IncludeSubfolders) {
        $files = @(Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
    }
    else {
        $files = @(Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -ErrorAction Stop)
    }
    $safe = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        if (Test-ActiveEvtxName -File $file) {
            Write-Log -Level 'WARN' -Message ("Skipped active/canonical EVTX in archived mode: {0}" -f $file.FullName)
            continue
        }
        if (Test-FileLocked -Path $file.FullName) {
            Write-Log -Level 'WARN' -Message ("Skipped locked EVTX in archived mode: {0}" -f $file.FullName)
            continue
        }
        [void]$safe.Add($file)
    }
    return @($safe)
}

function Export-LiveSecuritySnapshot {
    $snapshotDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
    Ensure-Directory -Path $snapshotDir
    $snapshot = Join-Path $snapshotDir ('Security-{0}-{1}.evtx' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    Register-TempArtifact -Path $snapshot
    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) { throw 'wevtutil.exe was not found.' }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.Arguments = ('epl Security "{0}" /ow:true' -f ($snapshot -replace '"','\"'))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $stderr = $p.StandardError.ReadToEnd()
    $null = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw ("wevtutil export failed. ExitCode={0}. {1}" -f $p.ExitCode, $stderr) }
    if (-not (Test-Path -LiteralPath $snapshot -PathType Leaf)) { throw 'Security snapshot was not created.' }
    Write-Log ("Live Security snapshot exported: {0}" -f $snapshot)
    return $snapshot
}

function New-LogParserObjects {
    return [pscustomobject]@{
        Query = New-Object -ComObject 'MSUtil.LogQuery'
        Input = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        Output = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
    }
}

function New-HeaderOnlyCsv {
    param([Parameter(Mandatory)][string]$Path)
    $header = 'EventAction,SourceEvtxPath,RecordNumber,EventTime,EventCollector,EventId,ActorSecurityId,ActorAccountName,ActorAccountDomain,ActorLogonId'
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function Get-CsvDataRowCount {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    try { return @((Import-Csv -LiteralPath $Path)).Count } catch { return 0 }
}

function Convert-FilterToSqlClause {
    param([string]$FilterText)
    $items = @($FilterText -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (@($items).Count -eq 0 -or $items -contains '*') { return '' }
    $clauses = New-Object System.Collections.Generic.List[string]
    foreach ($item in $items) {
        if ($item -match '^[^\\]+\\[^\\]+$') {
            $domain, $user = $item -split '\\', 2
            $domain = $domain.Replace("'", "''")
            $user = $user.Replace("'", "''")
            [void]$clauses.Add(("(EXTRACT_TOKEN(Strings, 2, '|') = '{0}' AND EXTRACT_TOKEN(Strings, 1, '|') = '{1}')" -f $domain, $user))
        }
        else {
            $user = $item.Replace("'", "''")
            [void]$clauses.Add(("EXTRACT_TOKEN(Strings, 1, '|') = '{0}'" -f $user))
        }
    }
    if ($clauses.Count -eq 0) { return '' }
    return 'AND (' + (@($clauses) -join ' OR ') + ')'
}

function Convert-DateRangeToSqlClause {
    param(
        [object]$FromTime,
        [object]$ToTime
    )

    $parts = New-Object System.Collections.Generic.List[string]

    if ($null -ne $FromTime) {
        $fromDate = [datetime]$FromTime
        [void]$parts.Add(("TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $fromDate.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    if ($null -ne $ToTime) {
        $toDate = [datetime]$ToTime
        [void]$parts.Add(("TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $toDate.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    if ($parts.Count -eq 0) { return '' }
    return 'AND ' + (@($parts) -join ' AND ')
}

function New-Event1102Sql {
    param(
        [Parameter(Mandatory)][string]$SourceEvtx,
        [Parameter(Mandatory)][string]$OutputCsv,
        [string]$UserClause,
        [string]$DateClause
    )
    $src = $SourceEvtx.Replace("'", "''")
    $dst = $OutputCsv.Replace("'", "''")
    return @"
SELECT
  'LOG_CLEARED' AS EventAction,
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS EventCollector,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 0, '|') AS ActorSecurityId,
  EXTRACT_TOKEN(Strings, 1, '|') AS ActorAccountName,
  EXTRACT_TOKEN(Strings, 2, '|') AS ActorAccountDomain,
  EXTRACT_TOKEN(Strings, 3, '|') AS ActorLogonId
INTO '$dst'
FROM '$src'
WHERE EventID = 1102
$UserClause
$DateClause
ORDER BY EventTime DESC
"@
}

function Invoke-LogParserCsvQuery {
    param([Parameter(Mandatory)][string]$Sql, [Parameter(Mandatory)][string]$OutputCsv, [Parameter(Mandatory)][string]$Context)
    if ($VerboseSqlLog.IsPresent) { Write-Log -Level 'DEBUG' -Message ("SQL [{0}]: {1}" -f $Context, $Sql) }
    $lp = New-LogParserObjects
    try {
        $result = $lp.Query.ExecuteBatch($Sql, $lp.Input, $lp.Output)
        Write-Log ("Log Parser ExecuteBatch [{0}] returned: {1}" -f $Context, $result)
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Skipped source after Log Parser failure [{0}]. {1}" -f $Context, $_.Exception.Message)
        return $false
    }
    if (-not (Test-Path -LiteralPath $OutputCsv -PathType Leaf)) { New-HeaderOnlyCsv -Path $OutputCsv }
    return $true
}

function Merge-CsvFilesSafe {
    param([string[]]$CsvPaths, [Parameter(Mandatory)][string]$DestinationCsv)
    $existing = @($CsvPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if (@($existing).Count -eq 0) { New-HeaderOnlyCsv -Path $DestinationCsv; return }
    $wrote = $false
    foreach ($csv in $existing) {
        if (-not $wrote) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $wrote = $true
        }
        else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
    if (-not $wrote) { New-HeaderOnlyCsv -Path $DestinationCsv }
}

function Invoke-Event1102Analysis {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string]$UserFilter,
        [Nullable[datetime]]$FromTime,
        [Nullable[datetime]]$ToTime
    )
    Ensure-Directory -Path $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $OutputFolder ('{0}-EventID1102-EventLogCleared-{1}.csv' -f $script:ComputerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.Generic.List[string]
    $userClause = Convert-FilterToSqlClause -FilterText $UserFilter
    $dateClause = Convert-DateRangeToSqlClause -FromTime $FromTime -ToTime $ToTime
    Write-Log ("Starting Event ID 1102 analysis. UseLiveLog={0}; Folder='{1}'; OutputFolder='{2}'" -f $UseLiveLog, $EvtxFolder, $OutputFolder)
    try {
        Update-UiState -Progress 5 -Status 'Preparing sources...'
        if ($UseLiveLog) {
            $snapshot = Export-LiveSecuritySnapshot
            $sources = @([pscustomobject]@{ FullName = $snapshot; Name = [IO.Path]::GetFileName($snapshot) })
        }
        else {
            $sources = @(Get-ArchiveSafeEvtxFiles -RootPath $EvtxFolder -IncludeSubfolders $IncludeSubfolders)
        }
        if (@($sources).Count -eq 0) { throw 'No EVTX sources were available for analysis.' }
        $index = 0
        foreach ($source in $sources) {
            $index++
            Update-UiState -Progress (10 + [int](($index / @($sources).Count) * 70)) -Status ("Processing {0} of {1}: {2}" -f $index, @($sources).Count, $source.Name)
            $tempCsv = Join-Path $env:TEMP ('Event1102-{0}-{1}.csv' -f $index, ([guid]::NewGuid().ToString('N').Substring(0,8)))
            Register-TempArtifact -Path $tempCsv
            $sql = New-Event1102Sql -SourceEvtx $source.FullName -OutputCsv $tempCsv -UserClause $userClause -DateClause $dateClause
            $ok = Invoke-LogParserCsvQuery -Sql $sql -OutputCsv $tempCsv -Context ([string]::Format('Event1102:{0}', $source.FullName))
            if ($ok -and (Test-Path -LiteralPath $tempCsv -PathType Leaf)) { [void]$tempCsvFiles.Add($tempCsv) }
        }
        Update-UiState -Progress 88 -Status 'Merging CSV output...'
        Merge-CsvFilesSafe -CsvPaths @($tempCsvFiles) -DestinationCsv $finalCsv
        $count = Get-CsvDataRowCount -Path $finalCsv
        $script:LastCsv = $finalCsv
        Write-Log ("Event ID 1102 analysis completed. Records={0}; Csv='{1}'" -f $count, $finalCsv)
        Update-UiState -Progress 100 -Status ("Completed. Records: {0}. CSV: {1}" -f $count, $finalCsv)
        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) { Start-Process -FilePath $finalCsv }
        Show-Message -Title 'Completed' -Message ("Event ID 1102 analysis completed.`r`nRecords: {0}`r`nCSV: {1}" -f $count, $finalCsv)
    }
    catch {
        Write-Log -Level 'ERROR' -Message ("Event ID 1102 analysis failed. {0}" -f $_.Exception.Message)
        Update-UiState -Progress 0 -Status 'Error occurred. Check the log.'
        Show-Message -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error) -Message ("Event ID 1102 analysis failed.`r`n{0}" -f $_.Exception.Message)
    }
    finally { Remove-TempArtifacts }
}

function Resolve-SecurityChannelProbe {
    Update-UiState -Progress 10 -Status 'Exporting Security snapshot for probe...'
    $snapshot = Export-LiveSecuritySnapshot
    $tempCsv = Join-Path $env:TEMP ('Event1102-Probe-{0}.csv' -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
    Register-TempArtifact -Path $tempCsv
    $sql = New-Event1102Sql -SourceEvtx $snapshot -OutputCsv $tempCsv -UserClause '' -DateClause ''
    $ok = Invoke-LogParserCsvQuery -Sql $sql -OutputCsv $tempCsv -Context 'ResolveSecurityChannel'
    if (-not $ok) { throw 'Log Parser probe failed.' }
    Update-UiState -Progress 0 -Status 'Ready.'
    Write-Log 'Security channel probe completed successfully.'
}

Ensure-Directory -Path $script:DefaultLogFolder
Write-Log 'Script started.'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Event Log Cleared Auditor - Event ID 1102 v5.1.5'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(850, 470)
$script:Form = $form

$left = 18
$labelW = 150
$fieldX = 175
$fieldW = 520
$buttonX = 710
$buttonW = 110
$y = 18
$row = 34

$checkLive = New-Object System.Windows.Forms.CheckBox
$checkLive.Text = 'Use live Security channel (snapshot via wevtutil)'
$checkLive.Location = New-Object System.Drawing.Point($left, $y)
$checkLive.Size = New-Object System.Drawing.Size(350, 24)
$checkLive.Checked = $true
$form.Controls.Add($checkLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Location = New-Object System.Drawing.Point($buttonX, $y)
$buttonResolve.Size = New-Object System.Drawing.Size($buttonW, 28)
$form.Controls.Add($buttonResolve)
$y += $row

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Text = 'EVTX Folder:'
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($y + 4))
$labelEvtx.Size = New-Object System.Drawing.Size($labelW, 22)
$form.Controls.Add($labelEvtx)
$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point($fieldX, $y)
$textEvtx.Size = New-Object System.Drawing.Size($fieldW, 24)
$textEvtx.Text = 'L:\Security'
$form.Controls.Add($textEvtx)
$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = 'Browse...'
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, ($y - 1))
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonW, 28)
$form.Controls.Add($buttonBrowseEvtx)
$y += $row

$checkSub = New-Object System.Windows.Forms.CheckBox
$checkSub.Text = 'Include subfolders when scanning archived EVTX'
$checkSub.Location = New-Object System.Drawing.Point($fieldX, $y)
$checkSub.Size = New-Object System.Drawing.Size(350, 24)
$checkSub.Checked = $true
$form.Controls.Add($checkSub)
$y += $row

$labelUser = New-Object System.Windows.Forms.Label
$labelUser.Text = 'Actor Filter:'
$labelUser.Location = New-Object System.Drawing.Point($left, ($y + 4))
$labelUser.Size = New-Object System.Drawing.Size($labelW, 22)
$form.Controls.Add($labelUser)
$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point($fieldX, $y)
$textUsers.Size = New-Object System.Drawing.Size($fieldW, 24)
$textUsers.Text = '*'
$form.Controls.Add($textUsers)
$y += $row

$checkDate = New-Object System.Windows.Forms.CheckBox
$checkDate.Text = 'Apply event time range'
$checkDate.Location = New-Object System.Drawing.Point($fieldX, $y)
$checkDate.Size = New-Object System.Drawing.Size(180, 24)
$checkDate.Checked = $false
$form.Controls.Add($checkDate)
$y += $row

$labelFrom = New-Object System.Windows.Forms.Label
$labelFrom.Text = 'From:'
$labelFrom.Location = New-Object System.Drawing.Point($fieldX, ($y + 4))
$labelFrom.Size = New-Object System.Drawing.Size(45, 22)
$form.Controls.Add($labelFrom)
$dateFrom = New-Object System.Windows.Forms.DateTimePicker
$dateFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateFrom.Location = New-Object System.Drawing.Point(($fieldX + 50), $y)
$dateFrom.Size = New-Object System.Drawing.Size(180, 24)
$form.Controls.Add($dateFrom)
$labelTo = New-Object System.Windows.Forms.Label
$labelTo.Text = 'To:'
$labelTo.Location = New-Object System.Drawing.Point(($fieldX + 250), ($y + 4))
$labelTo.Size = New-Object System.Drawing.Size(30, 22)
$form.Controls.Add($labelTo)
$dateTo = New-Object System.Windows.Forms.DateTimePicker
$dateTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateTo.Location = New-Object System.Drawing.Point(($fieldX + 285), $y)
$dateTo.Size = New-Object System.Drawing.Size(180, 24)
$form.Controls.Add($dateTo)
$y += $row

$labelOut = New-Object System.Windows.Forms.Label
$labelOut.Text = 'Output Folder:'
$labelOut.Location = New-Object System.Drawing.Point($left, ($y + 4))
$labelOut.Size = New-Object System.Drawing.Size($labelW, 22)
$form.Controls.Add($labelOut)
$textOut = New-Object System.Windows.Forms.TextBox
$textOut.Location = New-Object System.Drawing.Point($fieldX, $y)
$textOut.Size = New-Object System.Drawing.Size($fieldW, 24)
$textOut.Text = $script:DefaultOutputFolder
$form.Controls.Add($textOut)
$buttonBrowseOut = New-Object System.Windows.Forms.Button
$buttonBrowseOut.Text = 'Browse...'
$buttonBrowseOut.Location = New-Object System.Drawing.Point($buttonX, ($y - 1))
$buttonBrowseOut.Size = New-Object System.Drawing.Size($buttonW, 28)
$form.Controls.Add($buttonBrowseOut)
$y += $row

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Text = 'Log Folder:'
$labelLog.Location = New-Object System.Drawing.Point($left, ($y + 4))
$labelLog.Size = New-Object System.Drawing.Size($labelW, 22)
$form.Controls.Add($labelLog)
$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point($fieldX, $y)
$textLog.Size = New-Object System.Drawing.Size($fieldW, 24)
$textLog.Text = $script:DefaultLogFolder
$form.Controls.Add($textLog)
$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = 'Browse...'
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, ($y - 1))
$buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonW, 28)
$form.Controls.Add($buttonBrowseLog)
$y += ($row + 10)

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point($left, $y)
$script:ProgressBar.Size = New-Object System.Drawing.Size(802, 22)
$form.Controls.Add($script:ProgressBar)
$y += 34

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Location = New-Object System.Drawing.Point($left, $y)
$script:StatusLabel.Size = New-Object System.Drawing.Size(802, 40)
$script:StatusLabel.Text = 'Ready.'
$form.Controls.Add($script:StatusLabel)
$y += 52

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Location = New-Object System.Drawing.Point(520, 420)
$buttonStart.Size = New-Object System.Drawing.Size(130, 32)
$form.Controls.Add($buttonStart)
$buttonOpen = New-Object System.Windows.Forms.Button
$buttonOpen.Text = 'Open CSV'
$buttonOpen.Location = New-Object System.Drawing.Point(660, 420)
$buttonOpen.Size = New-Object System.Drawing.Size(90, 32)
$form.Controls.Add($buttonOpen)
$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Location = New-Object System.Drawing.Point(760, 420)
$buttonClose.Size = New-Object System.Drawing.Size(70, 32)
$form.Controls.Add($buttonClose)

$folderPicker = {
    param([string]$Description, [System.Windows.Forms.TextBox]$Target)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    try { if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Target.Text = $dialog.SelectedPath } }
    finally { $dialog.Dispose() }
}

$toggleControls = {
    $archiveMode = -not $checkLive.Checked
    $textEvtx.Enabled = $archiveMode
    $buttonBrowseEvtx.Enabled = $archiveMode
    $checkSub.Enabled = $archiveMode
}
$checkLive.Add_CheckedChanged($toggleControls)
& $toggleControls

$buttonBrowseEvtx.Add_Click({
    Invoke-GuiSafe -Context 'Browse EVTX folder' -ScriptBlock { & $folderPicker 'Select a folder containing Security EVTX files.' $textEvtx }
})
$buttonBrowseOut.Add_Click({
    Invoke-GuiSafe -Context 'Browse output folder' -ScriptBlock { & $folderPicker 'Select the CSV output folder.' $textOut }
})
$buttonBrowseLog.Add_Click({
    Invoke-GuiSafe -Context 'Browse log folder' -ScriptBlock {
        & $folderPicker 'Select the log folder.' $textLog
        $script:DefaultLogFolder = $textLog.Text
        $script:LogPath = Join-Path $script:DefaultLogFolder ('{0}.log' -f $script:ScriptName)
        Ensure-Directory -Path $script:DefaultLogFolder
    }
})

$buttonResolve.Add_Click({
    Invoke-GuiSafe -Context 'Resolve Channel' -ScriptBlock {
        Resolve-SecurityChannelProbe
        Show-Message -Title 'Resolve Channel' -Message 'Security channel probe completed successfully.'
    }
})

$buttonStart.Add_Click({
    Invoke-GuiSafe -Context 'Event ID 1102 analysis' -ScriptBlock {
        $fromValue = $null
        $toValue = $null
        if ($checkDate.Checked) {
            $fromValue = [datetime]$dateFrom.Value
            $toValue = [datetime]$dateTo.Value
        }
        Invoke-Event1102Analysis -UseLiveLog:$checkLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkSub.Checked -OutputFolder $textOut.Text -UserFilter $textUsers.Text -FromTime $fromValue -ToTime $toValue
    }
})

$buttonOpen.Add_Click({
    Invoke-GuiSafe -Context 'Open CSV' -ScriptBlock {
        if ($script:LastCsv -and (Test-Path -LiteralPath $script:LastCsv -PathType Leaf)) { Start-Process -FilePath $script:LastCsv }
        else { Show-Message -Title 'Open CSV' -Message 'No generated CSV is available yet.' }
    }
})
$buttonClose.Add_Click({ Invoke-GuiSafe -Context 'Close' -ScriptBlock { $form.Close() } })
$form.Add_FormClosed({ try { Write-Log 'Script ended.' } catch { } })
[void]$form.ShowDialog()

# End of script
