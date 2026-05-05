#requires -Version 5.1
<#
.SYNOPSIS
  Audits Windows PrintService Event ID 307 records using Log Parser.

.DESCRIPTION
  Uses Log Parser 2.2 as the primary parser. Live mode exports a temporary EVTX snapshot with wevtutil before parsing. Archived mode scans EVTX files safely and skips active or locked canonical files.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-05-v5.1.6-OUTPUT-CLEAN-REGEX-HOTFIX
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
            if ($Visible) {
                [void][Win32Console]::ShowWindow($hWnd, 5)
            }
            else {
                [void][Win32Console]::ShowWindow($hWnd, 0)
            }
        }
    }
    catch {}
}

if (-not $ShowConsole) {
    Set-ConsoleVisibility -Visible:$false
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            Write-Log -Message ("Unhandled UI exception: {0}" -f $e.Exception.Message) -Level 'ERROR'
            [void][System.Windows.Forms.MessageBox]::Show(("Unhandled UI exception:`r`n{0}" -f $e.Exception.Message), 'Print Audit - UI Error', 'OK', 'Error')
        }
        catch {}
    })
}
catch {}

[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    try {
        Write-Log -Message ("Unhandled application exception: {0}" -f $e.ExceptionObject.ToString()) -Level 'ERROR'
    }
    catch {}
})

$script:Version = '2026-05-05-v5.1.6-OUTPUT-CLEAN-REGEX-HOTFIX'
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Microsoft-Windows-PrintService/Operational'
$script:LastCsvPath = $null
$script:Form = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)

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
        Ensure-Directory -Path $script:LogDir
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -FilePath $script:LogPath -Append -Encoding utf8
    }
    catch {}
}

function Show-MessageBox {
    param(
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )

    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$Context = 'GUI action'
    )

    try {
        & $ScriptBlock
    }
    catch {
        $message = "{0} failed. {1}" -f $Context, $_.Exception.Message
        Write-Log -Message $message -Level 'ERROR'
        Set-Status -Text ($Context + ' failed.')
        Show-MessageBox -Message $message -Title $Context -Icon Error
    }
}

function Set-Status {
    param([string]$Text)

    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Text
    }

    if ($script:Form) {
        $script:Form.Refresh()
    }
}

function Update-ProgressSafe {
    param([int]$Value)

    if ($script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
    }

    if ($script:Form) {
        $script:Form.Refresh()
    }
}


function New-UiPoint {
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )

    return (New-Object System.Drawing.Point -ArgumentList @($X, $Y))
}

function New-UiSize {
    param(
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    return (New-Object System.Drawing.Size -ArgumentList @($Width, $Height))
}

function Select-Folder {
    param([string]$Description = 'Select a folder')

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }

        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function Get-LogParserExePath {
    foreach ($candidate in $script:LogParserExeCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    return $null
}

function Escape-LogParserPath {
    param([string]$Path)

    return ($Path -replace "'", "''")
}

function Test-IsLikelyActivePrintServiceEvtx {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    $activeNames = @(
        'Microsoft-Windows-PrintService-Operational.evtx',
        'PrintService-Operational.evtx'
    )

    return ($activeNames -contains $File.Name)
}

function Test-IsFileLocked {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $stream = $null

    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $false
    }
    catch {
        return $true
    }
    finally {
        if ($stream) {
            $stream.Dispose()
        }
    }
}

function New-LogParserComObjects {
    try {
        $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
        $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'

        return [pscustomobject]@{
            LogQuery     = $logQuery
            InputFormat  = $inputFormat
            OutputFormat = $outputFormat
        }
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed correctly. $($_.Exception.Message)"
    }
}

function Invoke-LogParserBatch {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)]$LogQuery,
        [Parameter(Mandatory)]$InputFormat,
        [Parameter(Mandatory)]$OutputFormat,
        [Parameter(Mandatory)][string]$Context
    )

    if ($VerboseSqlLog) {
        Write-Log -Message ("SQL [{0}]: {1}" -f $Context, $Query) -Level 'DEBUG'
    }

    try {
        $result = $LogQuery.ExecuteBatch($Query, $InputFormat, $OutputFormat)
        Write-Log -Message ("Log Parser ExecuteBatch [{0}] returned: {1}" -f $Context, $result)
        return $result
    }
    catch {
        throw "Log Parser ExecuteBatch failed for $Context. $($_.Exception.Message)"
    }
}

function New-EmptyPrintAuditCsv {
    param([Parameter(Mandatory)][string]$Path)

    'EventTime,UserId,Workstation,PrinterUsed,ByteSize,PagesPrinted' |
        Set-Content -LiteralPath $Path -Encoding UTF8
}


function Normalize-PrintAuditValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return '-'
    }

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '-'
    }

    return $text
}

function Normalize-WorkstationName {
    param([object]$Value)

    $text = Normalize-PrintAuditValue -Value $Value
    if ($text -eq '-') {
        return '-'
    }

    return ($text -replace '^\\+', '').Trim()
}

function Normalize-PrinterName {
    param([object]$Value)

    $text = Normalize-PrintAuditValue -Value $Value
    if ($text -eq '-') {
        return '-'
    }

    return ($text -replace '^\\\\[^\\]+\\', '').Trim()
}

function Normalize-PrintAuditCsv {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        New-EmptyPrintAuditCsv -Path $Path
        return 0
    }

    $rows = @(Import-Csv -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($rows.Count -eq 0) {
        New-EmptyPrintAuditCsv -Path $Path
        return 0
    }

    $normalized = foreach ($row in $rows) {
        [pscustomobject][ordered]@{
            EventTime    = Normalize-PrintAuditValue -Value $row.EventTime
            UserId       = Normalize-PrintAuditValue -Value $row.UserId
            Workstation  = Normalize-WorkstationName -Value $row.Workstation
            PrinterUsed  = Normalize-PrinterName -Value $row.PrinterUsed
            ByteSize     = Normalize-PrintAuditValue -Value $row.ByteSize
            PagesPrinted = Normalize-PrintAuditValue -Value $row.PagesPrinted
        }
    }

    $normalized | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    return @($normalized).Count
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
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $quotedChannel = '"' + ($ChannelName -replace '"','\"') + '"'
    $quotedDestination = '"' + ($DestinationPath -replace '"','\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($proc.ExitCode). StdOut=$stdOut StdErr=$stdErr"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "wevtutil reported success, but the snapshot file was not created at '$DestinationPath'."
    }

    Write-Log -Message ("Live PrintService snapshot exported: {0}" -f $DestinationPath)
    return $DestinationPath
}

function Get-DateRangeSqlFilter {
    param(
        [bool]$DateRangeEnabled,
        [datetime]$FromTime,
        [datetime]$ToTime
    )

    if (-not $DateRangeEnabled) {
        return ''
    }

    if ($FromTime -gt $ToTime) {
        throw 'Invalid date range. From date/time must be earlier than or equal to To date/time.'
    }

    $fromText = $FromTime.ToString('yyyy-MM-dd HH:mm:ss')
    $toText = $ToTime.ToString('yyyy-MM-dd HH:mm:ss')

    return (" AND TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss') AND TimeGenerated <= TO_TIMESTAMP('{1}', 'yyyy-MM-dd HH:mm:ss')" -f $fromText, $toText)
}

function Merge-TempCsvIntoFinal {
    param(
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][bool]$IsFirstFile
    )

    if (-not (Test-Path -LiteralPath $TempCsvPath -PathType Leaf)) {
        return $false
    }

    $lines = @(Get-Content -LiteralPath $TempCsvPath -ErrorAction Stop)

    if ($lines.Count -eq 0) {
        Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    if ($IsFirstFile) {
        $lines | Set-Content -LiteralPath $FinalCsvPath -Encoding UTF8
    }
    else {
        @($lines | Select-Object -Skip 1) | Add-Content -LiteralPath $FinalCsvPath -Encoding UTF8
    }

    Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
    return $true
}

function Invoke-EvtxPrint307Extraction {
    param(
        [Parameter(Mandatory)]$EvtxFiles,
        [Parameter(Mandatory)]$LogQuery,
        [Parameter(Mandatory)]$InputFormat,
        [Parameter(Mandatory)]$OutputFormat,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][bool]$DateRangeEnabled,
        [Parameter(Mandatory)][datetime]$FromTime,
        [Parameter(Mandatory)][datetime]$ToTime,
        [string]$StatusPrefix = 'Processing EVTX'
    )

    $safeEvtxFiles = @($EvtxFiles)
    $fileCount = $safeEvtxFiles.Count

    if ($fileCount -eq 0) {
        New-EmptyPrintAuditCsv -Path $FinalCsvPath
        return 0
    }

    $dateSql = Get-DateRangeSqlFilter -DateRangeEnabled:$DateRangeEnabled -FromTime $FromTime -ToTime $ToTime
    $first = $true

    for ($i = 0; $i -lt $fileCount; $i++) {
        $file = $safeEvtxFiles[$i]
        $pct = 10 + [int](((($i + 1) / [double]$fileCount) * 70))
        Update-ProgressSafe -Value $pct
        Set-Status -Text ("{0} {1} of {2}: {3}" -f $StatusPrefix, ($i + 1), $fileCount, $file.Name)

        if (Test-Path -LiteralPath $TempCsvPath -PathType Leaf) {
            Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
        }

        try {
            if (Test-IsLikelyActivePrintServiceEvtx -File $file) {
                Write-Log -Message ("Skipped active/canonical PrintService EVTX in archive mode: {0}" -f $file.FullName) -Level 'WARN'
                continue
            }

            if (Test-IsFileLocked -Path $file.FullName) {
                Write-Log -Message ("Skipped locked EVTX file: {0}" -f $file.FullName) -Level 'WARN'
                continue
            }

            $query = @"
SELECT
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 2, '|') AS UserId,
  EXTRACT_TOKEN(Strings, 3, '|') AS Workstation,
  EXTRACT_TOKEN(Strings, 4, '|') AS PrinterUsed,
  EXTRACT_TOKEN(Strings, 6, '|') AS ByteSize,
  EXTRACT_TOKEN(Strings, 7, '|') AS PagesPrinted
INTO '$([string](Escape-LogParserPath -Path $TempCsvPath))'
FROM '$([string](Escape-LogParserPath -Path $file.FullName))'
WHERE EventID = 307$dateSql
ORDER BY EventTime DESC
"@

            $context = "Extraction307:{0}" -f $file.FullName
            $null = Invoke-LogParserBatch -Query $query -LogQuery $LogQuery -InputFormat $InputFormat -OutputFormat $OutputFormat -Context $context

            $merged = Merge-TempCsvIntoFinal -TempCsvPath $TempCsvPath -FinalCsvPath $FinalCsvPath -IsFirstFile:$first

            if ($merged) {
                $first = $false
            }
            else {
                Write-Log -Message ("No Event ID 307 rows exported from {0}" -f $file.FullName)
            }
        }
        catch {
            Write-Log -Message ("Skipped EVTX after non-fatal processing failure: {0}. Error: {1}" -f $file.FullName, $_.Exception.Message) -Level 'WARN'
            continue
        }
    }

    if (-not (Test-Path -LiteralPath $FinalCsvPath -PathType Leaf)) {
        New-EmptyPrintAuditCsv -Path $FinalCsvPath
    }

    return @((Import-Csv -LiteralPath $FinalCsvPath -ErrorAction SilentlyContinue)).Count
}

function Test-LivePrintChannel {
    $probeCsv = $null
    $probeEvtx = $null

    try {
        $objects = New-LogParserComObjects
        $snapshotDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
        Ensure-Directory -Path $snapshotDir

        $probeEvtx = Join-Path $snapshotDir ("PrintService-307-Probe-{0}.evtx" -f ([guid]::NewGuid().ToString('N')))
        $probeCsv = Join-Path $snapshotDir ("PrintService-307-Probe-{0}.csv" -f ([guid]::NewGuid().ToString('N')))

        Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $probeEvtx | Out-Null

        $query = @"
SELECT TOP 1
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 4, '|') AS PrinterName
INTO '$([string](Escape-LogParserPath -Path $probeCsv))'
FROM '$([string](Escape-LogParserPath -Path $probeEvtx))'
WHERE EventID = 307
ORDER BY EventTime DESC
"@

        $null = Invoke-LogParserBatch -Query $query -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -Context 'ResolvePrintServiceChannel'
        Write-Log -Message 'PrintService channel probe completed successfully.'
        return $true
    }
    catch {
        throw "PrintService channel probe failed. $($_.Exception.Message)"
    }
    finally {
        if ($probeCsv -and (Test-Path -LiteralPath $probeCsv)) {
            Remove-Item -LiteralPath $probeCsv -Force -ErrorAction SilentlyContinue
        }

        if ($probeEvtx -and (Test-Path -LiteralPath $probeEvtx)) {
            Remove-Item -LiteralPath $probeEvtx -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-PrintAudit307 {
    param(
        [string]$LogFolderPath,
        [Parameter(Mandatory)][string]$OutputFolder,
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter(Mandatory)][bool]$DateRangeEnabled,
        [Parameter(Mandatory)][datetime]$FromTime,
        [Parameter(Mandatory)][datetime]$ToTime
    )

    $tempCsvPath = $null
    $snapshotEvtxPath = $null

    try {
        if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
            $OutputFolder = [Environment]::GetFolderPath('MyDocuments')
        }

        Ensure-Directory -Path $OutputFolder

        $logParserExe = Get-LogParserExePath

        if ($logParserExe) {
            Write-Log -Message ("Using Log Parser executable: {0}" -f $logParserExe)
        }
        else {
            Write-Log -Message 'LogParser.exe path was not found. COM automation will be used.' -Level 'WARN'
        }

        $objects = New-LogParserComObjects
        Write-Log -Message ("Starting Event ID 307 print audit. UseLiveLog={0}; Folder='{1}'; IncludeSubfolders={2}; OutputFolder='{3}'; DateRange={4}" -f $UseLiveLog, $LogFolderPath, $IncludeSubfolders, $OutputFolder, $DateRangeEnabled)

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $csvPath = Join-Path $OutputFolder ("{0}-EventID307-PrintAudit-{1}.csv" -f $script:MachineName, $timestamp)
        $tempCsvPath = Join-Path $env:TEMP ("PrintAudit307_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

        if ($UseLiveLog) {
            $snapshotDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
            Ensure-Directory -Path $snapshotDir
            $snapshotEvtxPath = Join-Path $snapshotDir ("PrintService-Operational-{0}-{1}.evtx" -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)))

            Update-ProgressSafe -Value 10
            Set-Status -Text 'Exporting live PrintService Operational snapshot...'
            Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $snapshotEvtxPath | Out-Null

            $rows = Invoke-EvtxPrint307Extraction -EvtxFiles @([System.IO.FileInfo](Get-Item -LiteralPath $snapshotEvtxPath -ErrorAction Stop)) -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $tempCsvPath -DateRangeEnabled:$DateRangeEnabled -FromTime $FromTime -ToTime $ToTime -StatusPrefix 'Processing live snapshot'
        }
        else {
            if ([string]::IsNullOrWhiteSpace($LogFolderPath) -or -not (Test-Path -LiteralPath $LogFolderPath -PathType Container)) {
                throw "Invalid EVTX folder path: '$LogFolderPath'"
            }

            if ($IncludeSubfolders) {
                $evtxFiles = @(Get-ChildItem -LiteralPath $LogFolderPath -Filter '*.evtx' -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
            }
            else {
                $evtxFiles = @(Get-ChildItem -LiteralPath $LogFolderPath -Filter '*.evtx' -ErrorAction Stop | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
            }

            if (@($evtxFiles).Count -eq 0) {
                throw "No .evtx files were found in '$LogFolderPath'."
            }

            Write-Log -Message ("Archived EVTX discovery completed. Files discovered={0}." -f @($evtxFiles).Count)
            $rows = Invoke-EvtxPrint307Extraction -EvtxFiles @($evtxFiles) -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $tempCsvPath -DateRangeEnabled:$DateRangeEnabled -FromTime $FromTime -ToTime $ToTime
        }

        Update-ProgressSafe -Value 90
        $count = Normalize-PrintAuditCsv -Path $csvPath

        $script:LastCsvPath = $csvPath
        Write-Log -Message ("Print audit completed. Events found={0}; Report={1}" -f $count, $csvPath)
        Update-ProgressSafe -Value 100
        Set-Status -Text ("Completed. Events found={0}; Report={1}" -f $count, $csvPath)
        Show-MessageBox -Message ("Events found: {0}`r`nReport exported to:`r`n{1}" -f $count, $csvPath) -Title 'Print Audit Completed'

        if ($AutoOpen -and (Test-Path -LiteralPath $csvPath)) {
            Start-Process -FilePath $csvPath
        }
    }
    catch {
        $message = "Event ID 307 print audit failed. $($_.Exception.Message)"
        Write-Log -Message $message -Level 'ERROR'
        Set-Status -Text 'Error occurred. Check log for details.'
        Show-MessageBox -Message $message -Title 'Print Audit Error' -Icon Error
    }
    finally {
        Update-ProgressSafe -Value 0

        if ($tempCsvPath -and (Test-Path -LiteralPath $tempCsvPath)) {
            Remove-Item -LiteralPath $tempCsvPath -Force -ErrorAction SilentlyContinue
        }

        if ($snapshotEvtxPath -and (Test-Path -LiteralPath $snapshotEvtxPath)) {
            Remove-Item -LiteralPath $snapshotEvtxPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Ensure-Directory -Path $script:LogDir
Write-Log -Message ("Script started. Version={0}" -f $script:Version)
Write-Log -Message "Output-clean CSV schema initialized."

$form = New-Object System.Windows.Forms.Form
$form.Text = 'EventID307 Print Audit - Output Clean'
$form.Size = New-UiSize -Width 940 -Height 620
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$left = 20
$labelWidth = 145
$inputLeft = 185
$inputWidth = 555
$buttonLeft = 760
$buttonWidth = 130
$rowHeight = 32
$top = 20

$labelLogDir = New-Object System.Windows.Forms.Label
$labelLogDir.Location = New-UiPoint -X $left -Y $top
$labelLogDir.Size = New-UiSize -Width $labelWidth -Height 24
$labelLogDir.Text = 'Log Folder:'
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox
$textBoxLogDir.Location = New-UiPoint -X $inputLeft -Y ([int]($top - 2))
$textBoxLogDir.Size = New-UiSize -Width $inputWidth -Height 24
$textBoxLogDir.Text = $script:LogDir
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button
$buttonBrowseLogDir.Location = New-UiPoint -X $buttonLeft -Y ([int]($top - 4))
$buttonBrowseLogDir.Size = New-UiSize -Width $buttonWidth -Height 28
$buttonBrowseLogDir.Text = 'Browse'
$buttonBrowseLogDir.Add_Click({ Invoke-GuiSafe -Context 'Browse Log Folder' -ScriptBlock { $folder = Select-Folder -Description 'Select the log folder'; if ($folder) { $textBoxLogDir.Text = $folder } } })
$form.Controls.Add($buttonBrowseLogDir)

$top += $rowHeight

$labelOutputDir = New-Object System.Windows.Forms.Label
$labelOutputDir.Location = New-UiPoint -X $left -Y $top
$labelOutputDir.Size = New-UiSize -Width $labelWidth -Height 24
$labelOutputDir.Text = 'Output Folder:'
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox
$textBoxOutputDir.Location = New-UiPoint -X $inputLeft -Y ([int]($top - 2))
$textBoxOutputDir.Size = New-UiSize -Width $inputWidth -Height 24
$textBoxOutputDir.Text = $script:DefaultOutputDir
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button
$buttonBrowseOutputDir.Location = New-UiPoint -X $buttonLeft -Y ([int]($top - 4))
$buttonBrowseOutputDir.Size = New-UiSize -Width $buttonWidth -Height 28
$buttonBrowseOutputDir.Text = 'Browse'
$buttonBrowseOutputDir.Add_Click({ Invoke-GuiSafe -Context 'Browse Output Folder' -ScriptBlock { $folder = Select-Folder -Description 'Select the output folder'; if ($folder) { $textBoxOutputDir.Text = $folder } } })
$form.Controls.Add($buttonBrowseOutputDir)

$top += $rowHeight + 8

$checkBoxLiveLog = New-Object System.Windows.Forms.CheckBox
$checkBoxLiveLog.Location = New-UiPoint -X $left -Y $top
$checkBoxLiveLog.Size = New-UiSize -Width 350 -Height 24
$checkBoxLiveLog.Text = 'Use live PrintService Operational channel'
$checkBoxLiveLog.Checked = $true
$form.Controls.Add($checkBoxLiveLog)

$buttonResolveChannel = New-Object System.Windows.Forms.Button
$buttonResolveChannel.Location = New-UiPoint -X $buttonLeft -Y ([int]($top - 4))
$buttonResolveChannel.Size = New-UiSize -Width $buttonWidth -Height 28
$buttonResolveChannel.Text = 'Resolve Channel'
$buttonResolveChannel.Add_Click({
    Invoke-GuiSafe -Context 'Resolve Channel' -ScriptBlock {
        $script:LogDir = $textBoxLogDir.Text
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        Ensure-Directory -Path $script:LogDir
        Set-Status -Text 'Testing live PrintService channel export and Log Parser access...'
        Update-ProgressSafe -Value 15
        $null = Test-LivePrintChannel
        Update-ProgressSafe -Value 0
        Set-Status -Text 'PrintService channel validation completed successfully.'
        Show-MessageBox -Message ("The live PrintService channel can be exported and parsed with Log Parser.`r`n`r`nChannel:`r`n{0}" -f $script:LiveChannelName) -Title 'Resolve Channel'
    }
})
$form.Controls.Add($buttonResolveChannel)

$top += $rowHeight + 4

$labelEvtxFolder = New-Object System.Windows.Forms.Label
$labelEvtxFolder.Location = New-UiPoint -X $left -Y $top
$labelEvtxFolder.Size = New-UiSize -Width $labelWidth -Height 24
$labelEvtxFolder.Text = 'EVTX Folder:'
$form.Controls.Add($labelEvtxFolder)

$textBoxEvtxFolder = New-Object System.Windows.Forms.TextBox
$textBoxEvtxFolder.Location = New-UiPoint -X $inputLeft -Y ([int]($top - 2))
$textBoxEvtxFolder.Size = New-UiSize -Width $inputWidth -Height 24
$textBoxEvtxFolder.Text = 'L:\Microsoft-Windows-PrintService-Operational'
$textBoxEvtxFolder.Enabled = $false
$form.Controls.Add($textBoxEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-UiPoint -X $buttonLeft -Y ([int]($top - 4))
$buttonBrowseEvtx.Size = New-UiSize -Width $buttonWidth -Height 28
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Enabled = $false
$buttonBrowseEvtx.Add_Click({ Invoke-GuiSafe -Context 'Browse EVTX Folder' -ScriptBlock { $folder = Select-Folder -Description 'Select the folder containing archived EVTX files'; if ($folder) { $textBoxEvtxFolder.Text = $folder } } })
$form.Controls.Add($buttonBrowseEvtx)

$top += $rowHeight

$checkBoxIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkBoxIncludeSubfolders.Location = New-UiPoint -X $inputLeft -Y $top
$checkBoxIncludeSubfolders.Size = New-UiSize -Width 360 -Height 24
$checkBoxIncludeSubfolders.Text = 'Include subfolders for archived EVTX scan'
$checkBoxIncludeSubfolders.Checked = $true
$checkBoxIncludeSubfolders.Enabled = $false
$form.Controls.Add($checkBoxIncludeSubfolders)

$top += $rowHeight + 8

$checkBoxDateRange = New-Object System.Windows.Forms.CheckBox
$checkBoxDateRange.Location = New-UiPoint -X $left -Y $top
$checkBoxDateRange.Size = New-UiSize -Width 160 -Height 24
$checkBoxDateRange.Text = 'Use date range'
$checkBoxDateRange.Checked = $true
$form.Controls.Add($checkBoxDateRange)

$labelFrom = New-Object System.Windows.Forms.Label
$labelFrom.Location = New-UiPoint -X $inputLeft -Y $top
$labelFrom.Size = New-UiSize -Width 45 -Height 24
$labelFrom.Text = 'From:'
$form.Controls.Add($labelFrom)

$dateFrom = New-Object System.Windows.Forms.DateTimePicker
$dateFrom.Location = New-UiPoint -X ([int]($inputLeft + 50)) -Y ([int]($top - 2))
$dateFrom.Size = New-UiSize -Width 190 -Height 24
$dateFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateFrom.ShowUpDown = $false
$dateFrom.Value = (Get-Date).Date
$form.Controls.Add($dateFrom)

$labelTo = New-Object System.Windows.Forms.Label
$labelTo.Location = New-UiPoint -X ([int]($inputLeft + 260)) -Y $top
$labelTo.Size = New-UiSize -Width 30 -Height 24
$labelTo.Text = 'To:'
$form.Controls.Add($labelTo)

$dateTo = New-Object System.Windows.Forms.DateTimePicker
$dateTo.Location = New-UiPoint -X ([int]($inputLeft + 295)) -Y ([int]($top - 2))
$dateTo.Size = New-UiSize -Width 190 -Height 24
$dateTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateTo.ShowUpDown = $false
$dateTo.Value = Get-Date
$form.Controls.Add($dateTo)

$checkBoxDateRange.Add_CheckedChanged({
    $enabled = $checkBoxDateRange.Checked
    $dateFrom.Enabled = $enabled
    $dateTo.Enabled = $enabled
})

$top += $rowHeight + 18

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-UiPoint -X $left -Y $top
$statusLabel.Size = New-UiSize -Width 870 -Height 24
$statusLabel.Text = 'Ready.'
$form.Controls.Add($statusLabel)

$top += $rowHeight

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-UiPoint -X $left -Y $top
$progressBar.Size = New-UiSize -Width 870 -Height 28
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$buttonY = 520
$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Location = New-UiPoint -X 535 -Y $buttonY
$buttonStartAnalysis.Size = New-UiSize -Width 120 -Height 34
$buttonStartAnalysis.Text = 'Start Analysis'
$buttonStartAnalysis.Add_Click({
    Invoke-GuiSafe -Context 'Start Analysis' -ScriptBlock {
        $script:LogDir = $textBoxLogDir.Text
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        Ensure-Directory -Path $script:LogDir

        if ($checkBoxDateRange.Checked -and $dateFrom.Value -gt $dateTo.Value) {
            Show-MessageBox -Message 'The From date/time must be earlier than or equal to the To date/time.' -Title 'Invalid Date Range' -Icon Warning
            return
        }

        if (-not $checkBoxLiveLog.Checked -and [string]::IsNullOrWhiteSpace($textBoxEvtxFolder.Text)) {
            Show-MessageBox -Message 'Please select an EVTX folder or enable live mode.' -Title 'Input Required' -Icon Warning
            return
        }

        Start-PrintAudit307 -LogFolderPath $textBoxEvtxFolder.Text -OutputFolder $textBoxOutputDir.Text -UseLiveLog $checkBoxLiveLog.Checked -IncludeSubfolders $checkBoxIncludeSubfolders.Checked -DateRangeEnabled:$checkBoxDateRange.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value
    }
})
$form.Controls.Add($buttonStartAnalysis)

$buttonOpenOutput = New-Object System.Windows.Forms.Button
$buttonOpenOutput.Location = New-UiPoint -X 665 -Y $buttonY
$buttonOpenOutput.Size = New-UiSize -Width 120 -Height 34
$buttonOpenOutput.Text = 'Open Output'
$buttonOpenOutput.Add_Click({
    Invoke-GuiSafe -Context 'Open Output' -ScriptBlock {
        if ($script:LastCsvPath -and (Test-Path -LiteralPath $script:LastCsvPath -PathType Leaf)) {
            Start-Process -FilePath $script:LastCsvPath
        }
        else {
            Show-MessageBox -Message 'No generated CSV report is available yet.' -Title 'Open Output' -Icon Information
        }
    }
})
$form.Controls.Add($buttonOpenOutput)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Location = New-UiPoint -X 795 -Y $buttonY
$buttonClose.Size = New-UiSize -Width 95 -Height 34
$buttonClose.Text = 'Close'
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

$checkBoxLiveLog.Add_CheckedChanged({
    $useLive = $checkBoxLiveLog.Checked
    $textBoxEvtxFolder.Enabled = -not $useLive
    $buttonBrowseEvtx.Enabled = -not $useLive
    $checkBoxIncludeSubfolders.Enabled = -not $useLive

    if ($useLive) {
        Set-Status -Text 'Ready. Live mode exports a temporary EVTX snapshot before Log Parser processing.'
    }
    else {
        Set-Status -Text 'Ready. Archived EVTX mode scans files safely and skips active/locked files.'
    }
})

$script:Form = $form
$script:ProgressBar = $progressBar
$script:StatusLabel = $statusLabel

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

Write-Log -Message 'Script ended.'

# End of script
