<#
.SYNOPSIS
  Audits Event ID 4648 explicit credential usage from Security EVTX logs.

.DESCRIPTION
  Production Log Parser-first GUI tool for extracting explicit credential usage evidence from live Security snapshots or archived EVTX files.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-05-v5.1.3-PRODUCTION-LOGPARSER-FIRST
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$VerboseSqlLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $consoleType = [System.Management.Automation.PSTypeName]'Win32Console'
    if (-not $consoleType.Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32Console {
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
    }
    if (-not $ShowConsole) {
        $hwnd = [Win32Console]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) { [void][Win32Console]::ShowWindow($hwnd, 0) }
    }
} catch { }

Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch { }

$script:ToolName = 'EventID4648-ExplicitCredentialsLogon'
$script:ToolVersion = '2026-05-05-v5.1.3-PRODUCTION-LOGPARSER-FIRST'
$script:ComputerName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:LogPath = Join-Path $script:LogDir ($script:ToolName + '.log')
$script:DefaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:SnapshotRoot = Join-Path ([IO.Path]::GetTempPath()) 'BlueTeam-Tools-Snapshots'
$script:LastCsvPath = $null
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:LogBox = $null

foreach ($dir in @($script:LogDir, $script:SnapshotRoot)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { $line | Out-File -FilePath $script:LogPath -Encoding UTF8 -Append -Force } catch { }
    try {
        if ($script:LogBox -ne $null) {
            $script:LogBox.AppendText(($line + [Environment]::NewLine))
        }
    } catch { }
}

function Set-Status {
    param([string]$Text, [int]$Progress = -1)
    try { if ($script:StatusLabel -ne $null) { $script:StatusLabel.Text = $Text } } catch { }
    try {
        if ($script:ProgressBar -ne $null -and $Progress -ge 0) {
            if ($Progress -lt 0) { $Progress = 0 }
            if ($Progress -gt 100) { $Progress = 100 }
            $script:ProgressBar.Value = $Progress
        }
    } catch { }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-GuiSafe {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock, [string]$Context = 'Operation')
    try { & $ScriptBlock }
    catch {
        $msg = $_.Exception.Message
        Write-Log "$Context failed. $msg" 'ERROR'
        Set-Status "$Context failed. Check the execution log." 0
        [System.Windows.Forms.MessageBox]::Show("$Context failed.`r`n$msg", 'Error', 'OK', 'Error') | Out-Null
    }
}

function New-Point { param([int]$X,[int]$Y) return (New-Object System.Drawing.Point($X,$Y)) }
function New-Size  { param([int]$W,[int]$H) return (New-Object System.Drawing.Size($W,$H)) }

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function New-HeaderOnlyCsv {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Headers)
    Set-Content -LiteralPath $Path -Value ($Headers -join ',') -Encoding UTF8
}

function Get-AccountFilters {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @('*') }
    $items = @($Text -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($items).Count -eq 0) { return @('*') }
    return @($items)
}

function Escape-SqlLiteral {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace "'", "''")
}

function Build-AccountFilterSql {
    param([string[]]$Filters)
    $filtersSafe = @($Filters | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($filtersSafe).Count -eq 0 -or $filtersSafe -contains '*') { return '' }

    $conditions = New-Object System.Collections.ArrayList
    foreach ($filter in $filtersSafe) {
        $value = $filter.Trim()
        if ($value -eq '*') { return '' }
        if ($value -match '^[^\\]+\\[^\\]+$') {
            $parts = $value -split '\\', 2
            $domain = Escape-SqlLiteral $parts[0]
            $user = Escape-SqlLiteral $parts[1]
            [void]$conditions.Add("((EXTRACT_TOKEN(Strings, 1, '|') = '$user' AND EXTRACT_TOKEN(Strings, 2, '|') = '$domain') OR (EXTRACT_TOKEN(Strings, 5, '|') = '$user' AND EXTRACT_TOKEN(Strings, 6, '|') = '$domain'))")
        } else {
            $userOnly = Escape-SqlLiteral $value
            [void]$conditions.Add("(EXTRACT_TOKEN(Strings, 1, '|') = '$userOnly' OR EXTRACT_TOKEN(Strings, 5, '|') = '$userOnly')")
        }
    }

    if ($conditions.Count -eq 0) { return '' }
    return ' AND (' + (($conditions.ToArray()) -join ' OR ') + ')'
}

function Build-DateFilterSql {
    param([bool]$Enabled, [datetime]$FromTime, [datetime]$ToTime)
    if (-not $Enabled) { return '' }
    if ($ToTime -lt $FromTime) { throw 'The end date/time cannot be earlier than the start date/time.' }
    $fromText = $FromTime.ToString('yyyy-MM-dd HH:mm:ss')
    $toText = $ToTime.ToString('yyyy-MM-dd HH:mm:ss')
    return " AND TimeGenerated >= TO_TIMESTAMP('$fromText', 'yyyy-MM-dd HH:mm:ss') AND TimeGenerated <= TO_TIMESTAMP('$toText', 'yyyy-MM-dd HH:mm:ss')"
}

function Export-LiveSecuritySnapshot {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $path = Join-Path $script:SnapshotRoot ('Security-4648-{0}-{1}.evtx' -f $stamp, ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $wevtutil = Join-Path $env:WINDIR 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) { throw 'wevtutil.exe was not found.' }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.Arguments = 'epl Security "{0}" /ow:true' -f $path
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "wevtutil snapshot failed. ExitCode=$($p.ExitCode); StdErr=$stderr; StdOut=$stdout" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Live Security snapshot was not created.' }
    Write-Log "Live Security snapshot exported: $path"
    return $path
}

function Test-IsFileLocked {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::None)
        return $false
    } catch { return $true }
    finally { if ($stream -ne $null) { $stream.Close(); $stream.Dispose() } }
}

function Test-IsActiveSecurityEvtx {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    return ($File.Name -ieq 'Security.evtx')
}

function Get-ArchiveSafeEvtxFiles {
    param([Parameter(Mandatory)][string]$Folder, [bool]$IncludeSubfolders)
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "EVTX folder does not exist: $Folder" }
    $files = if ($IncludeSubfolders) {
        @(Get-ChildItem -LiteralPath $Folder -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
    } else {
        @(Get-ChildItem -LiteralPath $Folder -Filter '*.evtx' -File -ErrorAction Stop)
    }
    $safe = New-Object System.Collections.ArrayList
    foreach ($file in $files) {
        if (Test-IsActiveSecurityEvtx -File $file) {
            Write-Log "Skipped active/canonical EVTX in archive mode: $($file.FullName)" 'WARN'
            continue
        }
        if (Test-IsFileLocked -Path $file.FullName) {
            Write-Log "Skipped locked EVTX file: $($file.FullName)" 'WARN'
            continue
        }
        [void]$safe.Add($file)
    }
    return @($safe.ToArray())
}

function Invoke-LogParserBatch {
    param([Parameter(Mandatory)][string]$Sql, [Parameter(Mandatory)][string]$Context)
    if ($VerboseSqlLog) { Write-Log "SQL [$Context]: $Sql" 'DEBUG' }
    $query = $null; $input = $null; $output = $null
    try {
        $query = New-Object -ComObject 'MSUtil.LogQuery'
        $input = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $output = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        $result = $query.ExecuteBatch($Sql, $input, $output)
        Write-Log "Log Parser ExecuteBatch [$Context] returned: $result"
        return $result
    } finally {
        foreach ($obj in @($output,$input,$query)) {
            if ($null -ne $obj) { try { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch { } }
        }
    }
}

function Get-RowsFromCsv {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
    if (@($lines).Count -le 1) { return @() }
    return @(Import-Csv -LiteralPath $Path)
}

function Merge-CsvFiles {
    param([string[]]$CsvPaths, [string]$FinalCsv, [string[]]$Headers)
    $allRows = @()
    foreach ($csv in @($CsvPaths)) {
        if (-not [string]::IsNullOrWhiteSpace($csv) -and (Test-Path -LiteralPath $csv -PathType Leaf)) {
            $rows = @(Get-RowsFromCsv -Path $csv)
            if (@($rows).Count -gt 0) { $allRows += $rows }
        }
    }
    if (@($allRows).Count -gt 0) {
        $allRows | Export-Csv -LiteralPath $FinalCsv -NoTypeInformation -Encoding UTF8
    } else {
        New-HeaderOnlyCsv -Path $FinalCsv -Headers $Headers
    }
    return @($allRows).Count
}

function New-ExtractionSql {
    param([string]$SourceEvtx, [string]$OutputCsv, [string]$AccountFilterSql, [string]$DateFilterSql)
    $safeSource = Escape-SqlLiteral $SourceEvtx
    $safeCsv = Escape-SqlLiteral $OutputCsv
@"
SELECT
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS EventCollector,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 1, '|') AS SubjectAccountName,
  EXTRACT_TOKEN(Strings, 2, '|') AS SubjectAccountDomain,
  EXTRACT_TOKEN(Strings, 3, '|') AS SubjectLogonId,
  EXTRACT_TOKEN(Strings, 5, '|') AS TargetAccountName,
  EXTRACT_TOKEN(Strings, 6, '|') AS TargetAccountDomain,
  EXTRACT_TOKEN(Strings, 8, '|') AS TargetServerName,
  EXTRACT_TOKEN(Strings, 9, '|') AS TargetInfo,
  EXTRACT_TOKEN(Strings, 11, '|') AS ProcessName,
  EXTRACT_TOKEN(Strings, 12, '|') AS SourceIpAddress,
  EXTRACT_TOKEN(Strings, 13, '|') AS SourcePort
INTO '$safeCsv'
FROM '$safeSource'
WHERE EventID = 4648$AccountFilterSql$DateFilterSql
ORDER BY EventTime DESC
"@
}

function Start-ExplicitCredentialAudit {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string]$AccountFilterText,
        [bool]$DateRangeEnabled,
        [datetime]$FromTime,
        [datetime]$ToTime
    )

    $headers = @('SourceEvtxPath','RecordNumber','EventTime','EventCollector','EventId','SubjectAccountName','SubjectAccountDomain','SubjectLogonId','TargetAccountName','TargetAccountDomain','TargetServerName','TargetInfo','ProcessName','SourceIpAddress','SourcePort')
    Ensure-Directory -Path $OutputFolder
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $OutputFolder ('{0}-EventID4648-ExplicitCredentialUsage-{1}.csv' -f $script:ComputerName, $stamp)
    $tempCsvPaths = @()
    $sources = @()

    Write-Log "Starting Event ID 4648 analysis. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$OutputFolder'; DateRange=$DateRangeEnabled"
    Set-Status 'Preparing source files...' 10

    $filters = @(Get-AccountFilters -Text $AccountFilterText)
    $accountFilterSql = Build-AccountFilterSql -Filters $filters
    $dateFilterSql = Build-DateFilterSql -Enabled $DateRangeEnabled -FromTime $FromTime -ToTime $ToTime

    if ($UseLiveLog) {
        $sources = @(Export-LiveSecuritySnapshot)
    } else {
        if ([string]::IsNullOrWhiteSpace($EvtxFolder)) { throw 'EVTX folder is required when live mode is disabled.' }
        $sourceFiles = @(Get-ArchiveSafeEvtxFiles -Folder $EvtxFolder -IncludeSubfolders $IncludeSubfolders)
        if (@($sourceFiles).Count -eq 0) { throw "No archive-safe EVTX files found in '$EvtxFolder'." }
        $sources = @($sourceFiles | ForEach-Object { $_.FullName })
    }

    $total = @($sources).Count
    $index = 0
    foreach ($source in @($sources)) {
        $index++
        $tempCsv = Join-Path $script:SnapshotRoot ('Event4648-{0}-{1}.csv' -f $stamp, ([guid]::NewGuid().ToString('N').Substring(0,8)))
        $sql = New-ExtractionSql -SourceEvtx $source -OutputCsv $tempCsv -AccountFilterSql $accountFilterSql -DateFilterSql $dateFilterSql
        $ctx = 'Extraction4648:{0}' -f $source
        try {
            [void](Invoke-LogParserBatch -Sql $sql -Context $ctx)
            if (Test-Path -LiteralPath $tempCsv -PathType Leaf) { $tempCsvPaths += $tempCsv }
        } catch {
            Write-Log "Skipped EVTX after non-fatal processing failure: $source. Error: $($_.Exception.Message)" 'WARN'
        }
        $pct = 20 + [int](($index / [Math]::Max($total,1)) * 60)
        Set-Status ('Processing source {0} of {1}...' -f $index, $total) $pct
    }

    Set-Status 'Merging CSV output...' 90
    $count = Merge-CsvFiles -CsvPaths @($tempCsvPaths) -FinalCsv $finalCsv -Headers $headers
    $script:LastCsvPath = $finalCsv
    Set-Status ('Completed. Events found: {0}' -f $count) 100
    Write-Log "Found $count Event ID 4648 records. Report exported: $finalCsv"
    try { Start-Process -FilePath $finalCsv | Out-Null } catch { Write-Log "Auto-open failed: $($_.Exception.Message)" 'WARN' }
    return [pscustomobject]@{ CsvPath = $finalCsv; EventCount = $count; SourceCount = $total }
}

function Resolve-SecurityChannel {
    param([string]$OutputFolder)
    Ensure-Directory -Path $OutputFolder
    $snapshot = Export-LiveSecuritySnapshot
    $probeCsv = Join-Path $script:SnapshotRoot ('Resolve4648-{0}.csv' -f ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $sql = @"
SELECT TOP 1
  TimeGenerated AS EventTime,
  ComputerName AS EventCollector,
  EventID AS EventId
INTO '$probeCsv'
FROM '$snapshot'
WHERE EventID = 4648
"@
    [void](Invoke-LogParserBatch -Sql $sql -Context 'ResolveSecurityChannel')
    Write-Log 'Security channel probe completed successfully.'
    Set-Status 'Security channel probe completed successfully.' 100
}

function Select-Folder {
    param([string]$Description, [string]$InitialPath)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Description
    $dlg.ShowNewFolderButton = $true
    if (-not [string]::IsNullOrWhiteSpace($InitialPath) -and (Test-Path -LiteralPath $InitialPath -PathType Container)) { $dlg.SelectedPath = $InitialPath }
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

Write-Log "Script started. Version=$script:ToolVersion"

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Explicit Credential Usage Auditor - Event ID 4648'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Size 1040 700
$form.MinimumSize = New-Size 1040 700
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

[System.Windows.Forms.Application]::add_ThreadException({ param($sender,$e) Write-Log "UI exception: $($e.Exception.Message)" 'ERROR' })
[AppDomain]::CurrentDomain.add_UnhandledException({ param($sender,$e) Write-Log "Unhandled exception: $($e.ExceptionObject.ToString())" 'ERROR' })

$left = 24; $labelW = 150; $inputX = 180; $inputW = 640; $buttonX = 850; $buttonW = 150; $rowH = 36; $y = 24

$chkLive = New-Object System.Windows.Forms.CheckBox
$chkLive.Text = 'Use live Security channel (snapshot via wevtutil)'
$chkLive.Location = New-Point $inputX $y
$chkLive.Size = New-Size 360 24
$chkLive.Checked = $true
$form.Controls.Add($chkLive)

$btnResolve = New-Object System.Windows.Forms.Button
$btnResolve.Text = 'Resolve Channel'
$btnResolve.Location = New-Point $buttonX ($y - 4)
$btnResolve.Size = New-Size $buttonW 32
$form.Controls.Add($btnResolve)
$y += $rowH

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = 'Account Filter:'
$lblFilter.Location = New-Point $left $y
$lblFilter.Size = New-Size $labelW 24
$form.Controls.Add($lblFilter)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Point $inputX $y
$txtFilter.Size = New-Size $inputW 70
$txtFilter.Multiline = $true
$txtFilter.ScrollBars = 'Vertical'
$txtFilter.Text = '*'
$form.Controls.Add($txtFilter)
$y += 82

$lblEvtx = New-Object System.Windows.Forms.Label
$lblEvtx.Text = 'EVTX Folder:'
$lblEvtx.Location = New-Point $left $y
$lblEvtx.Size = New-Size $labelW 24
$form.Controls.Add($lblEvtx)

$txtEvtx = New-Object System.Windows.Forms.TextBox
$txtEvtx.Location = New-Point $inputX $y
$txtEvtx.Size = New-Size $inputW 24
$txtEvtx.Text = 'L:\Security'
$form.Controls.Add($txtEvtx)

$btnEvtx = New-Object System.Windows.Forms.Button
$btnEvtx.Text = 'Browse...'
$btnEvtx.Location = New-Point $buttonX ($y - 3)
$btnEvtx.Size = New-Size $buttonW 30
$form.Controls.Add($btnEvtx)
$y += $rowH

$chkSub = New-Object System.Windows.Forms.CheckBox
$chkSub.Text = 'Include subfolders when scanning archived EVTX'
$chkSub.Location = New-Point $inputX $y
$chkSub.Size = New-Size 400 24
$chkSub.Checked = $true
$form.Controls.Add($chkSub)
$y += $rowH

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Text = 'Apply event time range'
$chkDate.Location = New-Point $inputX $y
$chkDate.Size = New-Size 220 24
$chkDate.Checked = $false
$form.Controls.Add($chkDate)
$y += $rowH

$lblFrom = New-Object System.Windows.Forms.Label
$lblFrom.Text = 'From:'
$lblFrom.Location = New-Point $inputX $y
$lblFrom.Size = New-Size 50 24
$form.Controls.Add($lblFrom)

$dtFrom = New-Object System.Windows.Forms.DateTimePicker
$dtFrom.Location = New-Point ($inputX + 55) ($y - 2)
$dtFrom.Size = New-Size 220 24
$dtFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtFrom.Value = (Get-Date).AddDays(-1)
$form.Controls.Add($dtFrom)

$lblTo = New-Object System.Windows.Forms.Label
$lblTo.Text = 'To:'
$lblTo.Location = New-Point ($inputX + 310) $y
$lblTo.Size = New-Size 30 24
$form.Controls.Add($lblTo)

$dtTo = New-Object System.Windows.Forms.DateTimePicker
$dtTo.Location = New-Point ($inputX + 345) ($y - 2)
$dtTo.Size = New-Size 220 24
$dtTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtTo.Value = Get-Date
$form.Controls.Add($dtTo)
$y += $rowH + 4

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = 'Output Folder:'
$lblOut.Location = New-Point $left $y
$lblOut.Size = New-Size $labelW 24
$form.Controls.Add($lblOut)

$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Location = New-Point $inputX $y
$txtOut.Size = New-Size $inputW 24
$txtOut.Text = $script:DefaultOutputFolder
$form.Controls.Add($txtOut)

$btnOut = New-Object System.Windows.Forms.Button
$btnOut.Text = 'Browse...'
$btnOut.Location = New-Point $buttonX ($y - 3)
$btnOut.Size = New-Size $buttonW 30
$form.Controls.Add($btnOut)
$y += $rowH

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log Folder:'
$lblLog.Location = New-Point $left $y
$lblLog.Size = New-Size $labelW 24
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Point $inputX $y
$txtLog.Size = New-Size $inputW 24
$txtLog.Text = $script:LogDir
$form.Controls.Add($txtLog)

$btnLog = New-Object System.Windows.Forms.Button
$btnLog.Text = 'Browse...'
$btnLog.Location = New-Point $buttonX ($y - 3)
$btnLog.Size = New-Size $buttonW 30
$form.Controls.Add($btnLog)
$y += 48

$status = New-Object System.Windows.Forms.Label
$status.Location = New-Point $left $y
$status.Size = New-Size 980 24
$status.Text = 'Ready.'
$form.Controls.Add($status)
$script:StatusLabel = $status
$y += 28

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Point $left $y
$progress.Size = New-Size 980 24
$progress.Minimum = 0; $progress.Maximum = 100; $progress.Value = 0
$form.Controls.Add($progress)
$script:ProgressBar = $progress
$y += 40

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Analysis'
$btnStart.Location = New-Point $left $y
$btnStart.Size = New-Size 170 38
$form.Controls.Add($btnStart)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open CSV'
$btnOpen.Location = New-Point 650 $y
$btnOpen.Size = New-Size 150 38
$form.Controls.Add($btnOpen)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Point 820 $y
$btnClose.Size = New-Size 150 38
$form.Controls.Add($btnClose)
$y += 52

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Point $left $y
$logBox.Size = New-Size 980 140
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)
$script:LogBox = $logBox

$toggleLive = {
    $isLive = $chkLive.Checked
    $txtEvtx.Enabled = -not $isLive
    $btnEvtx.Enabled = -not $isLive
    $chkSub.Enabled = -not $isLive
}
$chkLive.Add_CheckedChanged($toggleLive)
& $toggleLive

$btnEvtx.Add_Click({ Invoke-GuiSafe -Context 'Select EVTX folder' -ScriptBlock { $p = Select-Folder -Description 'Select EVTX folder' -InitialPath $txtEvtx.Text; if ($p) { $txtEvtx.Text = $p } } })
$btnOut.Add_Click({ Invoke-GuiSafe -Context 'Select output folder' -ScriptBlock { $p = Select-Folder -Description 'Select output folder' -InitialPath $txtOut.Text; if ($p) { $txtOut.Text = $p } } })
$btnLog.Add_Click({ Invoke-GuiSafe -Context 'Select log folder' -ScriptBlock { $p = Select-Folder -Description 'Select log folder' -InitialPath $txtLog.Text; if ($p) { $txtLog.Text = $p; $script:LogDir = $p; Ensure-Directory -Path $script:LogDir; $script:LogPath = Join-Path $script:LogDir ($script:ToolName + '.log') } } })
$btnResolve.Add_Click({ Invoke-GuiSafe -Context 'Resolve Channel' -ScriptBlock { Resolve-SecurityChannel -OutputFolder $txtOut.Text } })
$btnOpen.Add_Click({ Invoke-GuiSafe -Context 'Open CSV' -ScriptBlock { if ($script:LastCsvPath -and (Test-Path -LiteralPath $script:LastCsvPath -PathType Leaf)) { Start-Process -FilePath $script:LastCsvPath | Out-Null } else { [System.Windows.Forms.MessageBox]::Show('No CSV has been generated yet.', 'Information', 'OK', 'Information') | Out-Null } } })
$btnClose.Add_Click({ $form.Close() })

$btnStart.Add_Click({
    Invoke-GuiSafe -Context 'Event ID 4648 analysis' -ScriptBlock {
        $btnStart.Enabled = $false; $btnResolve.Enabled = $false
        try {
            [void](Start-ExplicitCredentialAudit -UseLiveLog $chkLive.Checked -EvtxFolder $txtEvtx.Text -IncludeSubfolders $chkSub.Checked -OutputFolder $txtOut.Text -AccountFilterText $txtFilter.Text -DateRangeEnabled $chkDate.Checked -FromTime $dtFrom.Value -ToTime $dtTo.Value)
        } finally {
            $btnStart.Enabled = $true; $btnResolve.Enabled = $true
        }
    }
})

$form.Add_FormClosed({ Write-Log 'Script ended.' })
[void]$form.ShowDialog()

# End of script
