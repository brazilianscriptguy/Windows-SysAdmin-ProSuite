#requires -Version 5.1
<#
.SYNOPSIS
  Audits Windows PrintService Event ID 307 locally, from archived EVTX files,
  or across selected server roles in every domain of an Active Directory forest.

.DESCRIPTION
  Production, SQL-first Event ID 307 audit tool. The original Log Parser 2.2
  extraction engine, live-channel snapshot workflow, archived-EVTX processing,
  normalization, GUI status, and progress behavior are preserved.

  Forest mode discovers every DHCP server authorized in the forest through
  Get-DhcpServerInDC. The GUI presents that inventory for explicit multi-server
  selection. It then identifies Domain Controllers from AD, verifies selected
  File Server and Print Server roles remotely, exports immutable EVTX snapshots
  with wevtutil, copies them to the management station, and parses them through
  the same Log Parser SQL pipeline used by local and archived modes.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-09-10-v6.6.0-REDUCED-REPORTS-COMPLETION-DIALOG
#>

[CmdletBinding()]
param(
    [ValidateSet('GUI','LocalLive','ForestLive','ArchivedEvtx')]
    [string]$Mode = 'GUI',
    [string]$ForestName,
    [ValidateSet('DomainController','FileServer','PrintServer')]
    [string[]]$ServerRole = @('DomainController','FileServer','PrintServer'),
    [string[]]$AdditionalServer = @(),
    [string[]]$ExcludeServer = @(),
    [string[]]$SelectedServer = @(),
    [ValidateSet('CSV','HTML','LOG')]
    [string[]]$ReportFormat = @('CSV','HTML','LOG'),
    [string]$ArchivedEvtxFolder,
    [switch]$RecurseArchivedEvtx,
    [string]$OutputFolder = ([System.IO.Path]::Combine([Environment]::GetFolderPath('MyDocuments'), 'EventID307-PrintingAudit')),
    [datetime]$StartTime = (Get-Date).Date.AddDays(-30),
    [datetime]$EndTime = (Get-Date),
    [ValidateRange(1,64)][int]$ThrottleLimit = 12,
    [ValidateRange(30,7200)][int]$OperationTimeoutSeconds = 900,
    [switch]$DiscoveryOnly,
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole,
    [switch]$VerboseSqlLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:IsGuiMode = ($Mode -eq 'GUI')

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

$script:Version = '2026-09-10-v6.6.0-REDUCED-REPORTS-COMPLETION-DIALOG'
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [System.IO.Path]::Combine(
    [Environment]::GetFolderPath('MyDocuments'),
    'EventID307-PrintingAudit'
)
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Microsoft-Windows-PrintService/Operational'
$script:LastCsvPath = $null
$script:LastHtmlPath = $null
$script:LastOutputFolder = $null
$script:EventSchema = @('EventTime','UserId','Workstation','PrinterUsed','ByteSize','PagesPrinted')
$script:GuiServerInventory = @()
$script:GuiServerByDisplay = @{}
$script:RuntimeLog = $null
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
        $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
        $line | Out-File -FilePath $script:LogPath -Append -Encoding utf8
        if ($script:RuntimeLog -and -not $script:RuntimeLog.IsDisposed) {
            $script:RuntimeLog.AppendText($line + [Environment]::NewLine)
            $script:RuntimeLog.SelectionStart = $script:RuntimeLog.Text.Length
            $script:RuntimeLog.ScrollToCaret()
            [System.Windows.Forms.Application]::DoEvents()
        }
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

    if ($script:IsGuiMode) {
        [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
    }
    elseif ($Icon -eq [System.Windows.Forms.MessageBoxIcon]::Error) {
        Write-Error $Message
    }
    else {
        Write-Host $Message
    }
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
        Write-Log -Message ("{0} Position='{1}' Stack='{2}'" -f $message,$_.InvocationInfo.PositionMessage,$_.ScriptStackTrace) -Level 'ERROR'
        Update-ProgressSafe -Value 0
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

function Show-ValidationWarning {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'Validation Required'
    )

    Write-Log -Message ("GUI validation: {0}" -f $Message) -Level 'WARN'
    Update-ProgressSafe -Value 0
    Set-Status -Text $Message
    Show-MessageBox -Message $Message -Title $Title -Icon Warning
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
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$File)

    # PATH-AGNOSTIC ARCHIVE RULE:
    # Do not skip archived print evidence by canonical filename.
    return $false
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

    ($script:EventSchema -join ',') |
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

function Get-Event307PropertyValue {
    param(
        [Parameter(Mandatory)]$Event,
        [Parameter(Mandatory)][string[]]$Names,
        [Parameter(Mandatory)][int]$FallbackIndex
    )

    try {
        [xml]$eventXml = $Event.ToXml()
        foreach ($dataNode in @($eventXml.Event.EventData.Data)) {
            $nodeName = [string]$dataNode.GetAttribute('Name')
            if ($Names -contains $nodeName) {
                return [string]$dataNode.InnerText
            }
        }
    }
    catch {}

    $properties = @($Event.Properties)
    if ($FallbackIndex -ge 0 -and $FallbackIndex -lt $properties.Count) {
        return [string]$properties[$FallbackIndex].Value
    }

    return '-'
}

function Get-NativeEvtxPrint307Rows {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][bool]$DateRangeEnabled,
        [Parameter(Mandatory)][datetime]$FromTime,
        [Parameter(Mandatory)][datetime]$ToTime
    )

    $filter = @{ Path = $EvtxPath; Id = 307 }
    if ($DateRangeEnabled) {
        $filter.StartTime = $FromTime
        $filter.EndTime = $ToTime
    }

    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' -or
            $_.Exception.Message -match 'No events were found|Nenhum evento foi encontrado') {
            return @()
        }
        throw "Native EVTX extraction failed for '$EvtxPath'. $($_.Exception.Message)"
    }

    return @(
        foreach ($event in $events) {
            [pscustomobject][ordered]@{
                EventTime    = $event.TimeCreated
                UserId       = Get-Event307PropertyValue -Event $event -Names @('Param2','User','UserName') -FallbackIndex 1
                Workstation  = Get-Event307PropertyValue -Event $event -Names @('Param3','ClientMachine','Workstation') -FallbackIndex 2
                PrinterUsed  = Get-Event307PropertyValue -Event $event -Names @('Param4','PrinterName','Printer') -FallbackIndex 3
                ByteSize     = Get-Event307PropertyValue -Event $event -Names @('Param6','Size','ByteSize') -FallbackIndex 5
                PagesPrinted = Get-Event307PropertyValue -Event $event -Names @('Param7','Pages','PagesPrinted') -FallbackIndex 6
            }
        }
    )
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
        [string]$StatusPrefix = 'Processing EVTX',
        [hashtable]$SourceServerByPath = @{},
        [hashtable]$SourceCountMap = @{},
        [hashtable]$SourceRowsMap = @{}
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
        $evtxPath = if ($file -is [System.IO.FileInfo]) { [string]$file.FullName } elseif ($file -and $file.PSObject.Properties['FullName']) { [string]$file.FullName } else { [string]$file }
        $evtxPath = [System.IO.Path]::GetFullPath($evtxPath)
        $evtxName = [System.IO.Path]::GetFileName($evtxPath)
        $sourceServer = if ($SourceServerByPath.ContainsKey($evtxPath)) { [string]$SourceServerByPath[$evtxPath] } else { $script:MachineName }
        $pct = 10 + [int](((($i + 1) / [double]$fileCount) * 70))
        Update-ProgressSafe -Value $pct
        Set-Status -Text ("{0} {1} of {2}: {3}" -f $StatusPrefix, ($i + 1), $fileCount, $evtxName)

        if (Test-Path -LiteralPath $TempCsvPath -PathType Leaf) {
            Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
        }

        try {
            if (Test-IsFileLocked -Path $evtxPath) {
                Write-Log -Message ("Skipped locked EVTX file: {0}" -f $evtxPath) -Level 'WARN'
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
FROM '$([string](Escape-LogParserPath -Path $evtxPath))'
WHERE EventID = 307$dateSql
ORDER BY EventTime DESC
"@

            $context = "Extraction307:{0}" -f $evtxPath
            $null = Invoke-LogParserBatch -Query $query -LogQuery $LogQuery -InputFormat $InputFormat -OutputFormat $OutputFormat -Context $context

            $sourceRows = @()
            if (Test-Path -LiteralPath $TempCsvPath -PathType Leaf) { $sourceRows = @(Import-Csv -LiteralPath $TempCsvPath -ErrorAction SilentlyContinue) }
            if (@($sourceRows).Count -eq 0) {
                Write-Log -Message ("Log Parser returned no Event ID 307 rows. Trying native Get-WinEvent fallback: {0}" -f $evtxPath) -Level 'WARN'
                $sourceRows = @(Get-NativeEvtxPrint307Rows -EvtxPath $evtxPath -DateRangeEnabled:$DateRangeEnabled -FromTime $FromTime -ToTime $ToTime)
                if (@($sourceRows).Count -gt 0) {
                    $sourceRows | Export-Csv -LiteralPath $TempCsvPath -NoTypeInformation -Encoding UTF8
                    Write-Log -Message ("Native EVTX fallback exported {0} Event ID 307 row(s) from {1}" -f @($sourceRows).Count,$evtxPath)
                }
            }

            $existingSourceCount = if ($SourceCountMap.ContainsKey($sourceServer)) { [int]$SourceCountMap[$sourceServer] } else { 0 }
            $SourceCountMap[$sourceServer] = $existingSourceCount + [int]@($sourceRows).Count
            $existingSourceRows = if ($SourceRowsMap.ContainsKey($sourceServer)) { @($SourceRowsMap[$sourceServer]) } else { @() }
            $SourceRowsMap[$sourceServer] = @($existingSourceRows) + @($sourceRows)
            $merged = Merge-TempCsvIntoFinal -TempCsvPath $TempCsvPath -FinalCsvPath $FinalCsvPath -IsFirstFile:$first

            if ($merged) {
                $first = $false
            }
            else {
                Write-Log -Message ("No Event ID 307 rows exported from {0}" -f $evtxPath)
            }
        }
        catch {
            Write-Log -Message ("Skipped EVTX after non-fatal processing failure: {0}. Error: {1}" -f $evtxPath, $_.Exception.Message) -Level 'WARN'
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

function Get-SafeFileToken {
    param([Parameter(Mandatory)][string]$Value)
    return (($Value.Trim() -replace '[^A-Za-z0-9._-]', '_').Trim('_'))
}

function Get-ForestServerInventory {
    [CmdletBinding()]
    param([string]$RequestedForest)

    if (-not (Get-Module -ListAvailable -Name DhcpServer)) { throw 'The DhcpServer PowerShell module is not installed or available.' }
    Import-Module DhcpServer -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    $forest = if ([string]::IsNullOrWhiteSpace($RequestedForest)) { Get-ADForest -ErrorAction Stop } else { Get-ADForest -Identity $RequestedForest -ErrorAction Stop }

    $dcNames = @{}
    foreach ($domainName in @($forest.Domains)) {
        foreach ($dc in @(Get-ADDomainController -Filter * -Server $domainName -ErrorAction Stop)) {
            if ($dc.HostName) { $dcNames[([string]$dc.HostName).ToLowerInvariant()] = $true }
            if ($dc.Name) { $dcNames[([string]$dc.Name).ToLowerInvariant()] = $true }
        }
    }

    $authorizedDhcp = @(Get-DhcpServerInDC -ErrorAction Stop | Sort-Object DNSName -Unique)
    Write-Log -Message ("Authorized DHCP discovery returned {0} server(s) from forest '{1}'." -f @($authorizedDhcp).Count,$forest.Name)
    $inventory = New-Object System.Collections.ArrayList
    foreach ($dhcp in $authorizedDhcp) {
        $name = [string]$dhcp.DnsName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $shortName = ($name -split '\.')[0]
        $domainName = if ($name.Contains('.')) { $name.Substring($name.IndexOf('.') + 1) } else { [string]$forest.RootDomain }
        [void]$inventory.Add([pscustomobject][ordered]@{
            ComputerName=$name; NetBIOSName=$shortName; Domain=$domainName; OperatingSystem='Not audited'; OperatingSystemVer='Not audited'; IPv4Address=[string]$dhcp.IPAddress; DistinguishedName=''; IsDomainController=[bool]($dcNames.ContainsKey($name.ToLowerInvariant()) -or $dcNames.ContainsKey($shortName.ToLowerInvariant())); DiscoverySource='AuthorizedDHCP'
        })
    }

    foreach ($extra in @($AdditionalServer | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not ($inventory | Where-Object { $_.ComputerName -ieq $extra -or $_.NetBIOSName -ieq $extra })) {
            [void]$inventory.Add([pscustomobject][ordered]@{
                ComputerName=$extra.Trim(); NetBIOSName=(($extra.Trim() -split '\.')[0]); Domain='Manual'; OperatingSystem='Not audited'; OperatingSystemVer='Not audited'; IPv4Address=''; DistinguishedName=''; IsDomainController=$false; DiscoverySource='AdditionalServer'
            })
        }
    }

    $excluded = @($ExcludeServer | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $filtered = @($inventory | Where-Object {
        $excluded -notcontains $_.ComputerName.ToLowerInvariant() -and $excluded -notcontains $_.NetBIOSName.ToLowerInvariant()
    } | Sort-Object ComputerName -Unique)
    $requested = @($SelectedServer | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    if ($requested.Count -gt 0) {
        $filtered = @($filtered | Where-Object { $requested -contains $_.ComputerName.ToLowerInvariant() -or $requested -contains $_.NetBIOSName.ToLowerInvariant() })
    }
    return @($filtered)
}

function Invoke-ForestSnapshotCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Inventory,
        [Parameter(Mandatory)][string]$StagingFolder,
        [Parameter(Mandatory)][datetime]$RangeStart,
        [Parameter(Mandatory)][datetime]$RangeEnd,
        [Parameter(Mandatory)][string[]]$SelectedRoles,
        [Parameter(Mandatory)][int]$Throttle,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [bool]$DiscoveryMode = $false
    )

    Ensure-Directory -Path $StagingFolder
    $targets = @($Inventory.ComputerName)
    $wantDc = $SelectedRoles -contains 'DomainController'
    $wantFile = $SelectedRoles -contains 'FileServer'
    $wantPrint = $SelectedRoles -contains 'PrintServer'
    $dcLookup = @{}
    foreach ($item in $Inventory) { $dcLookup[$item.ComputerName.ToLowerInvariant()] = [bool]$item.IsDomainController }

    $remote = {
        param($Channel,$From,$To,$WantDc,$WantFile,$WantPrint,$KnownDc,$RunToken,$OnlyDiscover)
        $ErrorActionPreference = 'Stop'
        $result = [ordered]@{ ComputerName=$env:COMPUTERNAME; IsDomainController=[bool]$KnownDc; IsFileServer=$false; IsPrintServer=$false; InScope=$false; ChannelEnabled=$null; Status='Unknown'; SnapshotPath=''; Error='' }
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            $result.IsDomainController = [bool]([int]$computerSystem.DomainRole -ge 4)
            Import-Module ServerManager -ErrorAction Stop
            $features = @(Get-WindowsFeature -Name FS-FileServer,Print-Server,AD-Domain-Services -ErrorAction Stop)
            $result.IsFileServer = [bool]($features | Where-Object { $_.Name -eq 'FS-FileServer' -and $_.Installed })
            $result.IsPrintServer = [bool]($features | Where-Object { $_.Name -eq 'Print-Server' -and $_.Installed })
            $result.InScope = [bool](($WantDc -and $result.IsDomainController) -or ($WantFile -and $result.IsFileServer) -or ($WantPrint -and $result.IsPrintServer))
            if (-not $result.InScope) { $result.Status='OutOfScope'; return [pscustomobject]$result }
            $log = Get-WinEvent -ListLog $Channel -ErrorAction Stop
            $result.ChannelEnabled = [bool]$log.IsEnabled
            if (-not $result.ChannelEnabled) { $result.Status='ChannelDisabled'; return [pscustomobject]$result }
            if ($OnlyDiscover) { $result.Status='Discovered'; return [pscustomobject]$result }
            $remotePath = Join-Path $env:windir ("Temp\EventID307-{0}-{1}.evtx" -f $RunToken,$env:COMPUTERNAME)
            $fromUtc = $From.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $toUtc = $To.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            $query = "*[System[(EventID=307) and TimeCreated[@SystemTime>='$fromUtc' and @SystemTime<='$toUtc']]]"
            & "$env:SystemRoot\System32\wevtutil.exe" epl $Channel $remotePath "/q:$query" /ow:true
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $remotePath -PathType Leaf)) { throw "wevtutil snapshot export failed with exit code $LASTEXITCODE." }
            $result.SnapshotPath=$remotePath; $result.Status='SnapshotReady'
        }
        catch { $result.Status='CollectionFailed'; $result.Error=$_.Exception.Message }
        return [pscustomobject]$result
    }

    $runToken = Get-Date -Format 'yyyyMMddHHmmss'
    $job = Invoke-Command -ComputerName $targets -AsJob -ThrottleLimit $Throttle -ScriptBlock $remote -ArgumentList $script:LiveChannelName,$RangeStart,$RangeEnd,$wantDc,$wantFile,$wantPrint,$false,$runToken,$DiscoveryMode -ErrorAction SilentlyContinue
    if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) { Stop-Job -Job $job -ErrorAction SilentlyContinue; Write-Log -Message 'Forest collection reached its operation timeout; unfinished targets were stopped.' -Level 'WARN' }
    $received = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    $childFailures = @($job.ChildJobs | Where-Object { $_.State -ne 'Completed' -or $_.JobStateInfo.Reason })
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    $statusRows = New-Object System.Collections.ArrayList
    $files = New-Object System.Collections.ArrayList
    $sourceMap = @{}
    foreach ($item in $Inventory) {
        $row = @($received | Where-Object { $_.PSComputerName -ieq $item.ComputerName -or $_.ComputerName -ieq $item.NetBIOSName } | Select-Object -First 1)
        if ($row.Count -eq 0) {
            $failure = @($childFailures | Where-Object { $_.Location -ieq $item.ComputerName } | Select-Object -First 1)
            $errorText = if ($failure.Count -and $failure[0].JobStateInfo.Reason) { $failure[0].JobStateInfo.Reason.Message } else { 'No remoting result was returned before completion or timeout.' }
            [void]$statusRows.Add([pscustomobject][ordered]@{ ComputerName=$item.ComputerName; Domain=$item.Domain; IsDomainController=$item.IsDomainController; IsFileServer=$null; IsPrintServer=$null; InScope=$null; ChannelEnabled=$null; Status='UnreachableOrUnauthorized'; SnapshotCopied=$false; EventCount=0; Error=$errorText })
            continue
        }
        $remoteRow = $row[0]
        $status = [ordered]@{ ComputerName=$item.ComputerName; Domain=$item.Domain; IsDomainController=[bool]$remoteRow.IsDomainController; IsFileServer=[bool]$remoteRow.IsFileServer; IsPrintServer=[bool]$remoteRow.IsPrintServer; InScope=[bool]$remoteRow.InScope; ChannelEnabled=$remoteRow.ChannelEnabled; Status=[string]$remoteRow.Status; SnapshotCopied=$false; EventCount=0; Error=[string]$remoteRow.Error }
        if ($remoteRow.Status -eq 'SnapshotReady') {
            try {
                $uncPrefix = '\\{0}\$1$' -f $item.ComputerName
                $remoteDrivePath = ([string]$remoteRow.SnapshotPath) -replace '^([A-Za-z]):', $uncPrefix
                $localPath = Join-Path $StagingFolder ((Get-SafeFileToken -Value $item.ComputerName) + '.evtx')
                Copy-Item -LiteralPath $remoteDrivePath -Destination $localPath -Force -ErrorAction Stop
                $status.SnapshotCopied=$true; $status.Status='SnapshotCopied'
                $fileInfo = Get-Item -LiteralPath $localPath -ErrorAction Stop
                [void]$files.Add($fileInfo); $sourceMap[$fileInfo.FullName]=$item.ComputerName
            }
            catch { $status.Status='SnapshotCopyFailed'; $status.Error=$_.Exception.Message }
            finally { Invoke-Command -ComputerName $item.ComputerName -ScriptBlock { param($p) Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } -ArgumentList ([string]$remoteRow.SnapshotPath) -ErrorAction SilentlyContinue }
        }
        [void]$statusRows.Add([pscustomobject]$status)
    }
    $nativeStatusRows = @($statusRows | ForEach-Object { $_ })
    $nativeFiles = @($files | ForEach-Object { $_ })
    return [pscustomobject]@{ StatusRows=$nativeStatusRows; EvtxFiles=$nativeFiles; SourceMap=$sourceMap }
}

function Export-PrintAuditHtml {
    param([Parameter(Mandatory)][string]$CsvPath,[Parameter(Mandatory)][object[]]$StatusRows,[Parameter(Mandatory)][string]$Path,[string]$ScopeName)
    $events = @(if (Test-Path -LiteralPath $CsvPath) { Import-Csv -LiteralPath $CsvPath })
    $safeStatusRows = @($StatusRows)
    $css = '<style>body{font-family:Segoe UI,Arial;margin:28px;color:#17233b}h1{color:#0b3d91}h2{border-bottom:2px solid #2f75b5;padding-bottom:5px}table{border-collapse:collapse;width:100%;font-size:9pt}th{background:#17365d;color:white}th,td{border:1px solid #cbd5e1;padding:5px;text-align:left}tr:nth-child(even){background:#f4f7fb}.meta{color:#475569}@media print{body{margin:10mm}table{font-size:8pt}h1{page-break-before:auto}}</style>'
    $summary = @([pscustomobject]@{Scope=$ScopeName;Generated=(Get-Date);Events=@($events).Count;Servers=@($safeStatusRows).Count;Successful=@($safeStatusRows|Where-Object{$_.Status -match 'SnapshotCopied|Success|Discovered'}).Count;Exceptions=@($safeStatusRows|Where-Object{$_.Status -match 'Failed|Unauthorized|Disabled'}).Count})
    $summaryHtml = ($summary | ConvertTo-Html -Fragment | Out-String)
    $coverageHtml = ($safeStatusRows | ConvertTo-Html -Fragment | Out-String)
    $eventHtml = if (@($events).Count -gt 0) { ($events | ConvertTo-Html -Fragment | Out-String) } else { '<p>No Event ID 307 records were found.</p>' }
    $body = @('<h1>Event ID 307 Print Audit</h1>',("<p class='meta'>Version {0}</p>" -f $script:Version),'<h2>Executive Summary</h2>',$summaryHtml,'<h2>Server Coverage</h2>',$coverageHtml,'<h2>Event Detail</h2>',$eventHtml) -join "`r`n"
    ConvertTo-Html -Title 'Event ID 307 Print Audit' -Head $css -Body $body | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Export-PerServerReportPackages {
    param(
        [Parameter(Mandatory)][object[]]$StatusRows,
        [Parameter(Mandatory)][hashtable]$SourceRowsMap,
        [Parameter(Mandatory)][string]$DestinationFolder,
        [Parameter(Mandatory)][string[]]$SelectedReports,
        [Parameter(Mandatory)][string]$Timestamp
    )

    $packages = New-Object System.Collections.ArrayList
    $statusCount = @($StatusRows).Count
    $packageIndex = 0
    foreach ($serverStatus in @($StatusRows)) {
        $packageIndex++
        $computerName = [string]$serverStatus.ComputerName
        if ([string]::IsNullOrWhiteSpace($computerName)) { continue }

        Set-Status -Text ("Generating server report {0} of {1}: {2}" -f $packageIndex,$statusCount,$computerName)
        Update-ProgressSafe -Value (82 + [int](($packageIndex / [double][Math]::Max(1,$statusCount)) * 14))

        $shortName = ($computerName -split '\.')[0]
        $matchingShortNames = @($StatusRows | Where-Object { (([string]$_.ComputerName -split '\.')[0]) -ieq $shortName })
        $nameForToken = if ($matchingShortNames.Count -gt 1) { $computerName } else { $shortName }
        $serverToken = Get-SafeFileToken -Value ($nameForToken.ToUpperInvariant())
        $baseName = '{0}-EventID307-PrintAudit-{1}' -f $serverToken,$Timestamp
        $eventPath = Join-Path $DestinationFolder ($baseName + '-Events.csv')
        $htmlPath = Join-Path $DestinationFolder ($baseName + '.html')
        $serverRows = @(if ($SourceRowsMap.ContainsKey($computerName)) { @($SourceRowsMap[$computerName]) })

        if ($serverRows.Count -gt 0) {
            $serverRows | Export-Csv -LiteralPath $eventPath -NoTypeInformation -Encoding UTF8
            $null = Normalize-PrintAuditCsv -Path $eventPath
        }
        else {
            New-EmptyPrintAuditCsv -Path $eventPath
        }

        if ($SelectedReports -contains 'HTML') {
            Export-PrintAuditHtml -CsvPath $eventPath -StatusRows @($serverStatus) -Path $htmlPath -ScopeName $computerName
        }
        if ($SelectedReports -notcontains 'CSV') {
            Remove-Item -LiteralPath $eventPath -Force -ErrorAction SilentlyContinue
        }
        Write-Log -Message ("SERVER-REPORT ComputerName='{0}'; Events={1}; BaseName='{2}'" -f $computerName,$serverRows.Count,$baseName)

        [void]$packages.Add([pscustomobject][ordered]@{
            ComputerName = $computerName
            Events       = $serverRows.Count
            EventCsv     = if ($SelectedReports -contains 'CSV') { $eventPath } else { $null }
            Html         = if ($SelectedReports -contains 'HTML') { $htmlPath } else { $null }
        })
    }

    return @($packages | ForEach-Object { $_ })
}

function Start-PrintAudit307 {
    param(
        [string]$LogFolderPath,
        [Parameter(Mandatory)][string]$OutputFolder,
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter(Mandatory)][bool]$DateRangeEnabled,
        [Parameter(Mandatory)][datetime]$FromTime,
        [Parameter(Mandatory)][datetime]$ToTime,
        [string[]]$SelectedReports = @('CSV','HTML','LOG')
    )

    $tempCsvPath = $null
    $snapshotEvtxPath = $null

    try {
        if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
            $OutputFolder = [System.IO.Path]::Combine(
                [Environment]::GetFolderPath('MyDocuments'),
                'EventID307-PrintingAudit'
            )
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

        $status = @([pscustomobject][ordered]@{ComputerName=$script:MachineName;Domain='Local/Archive';IsDomainController=$null;IsFileServer=$null;IsPrintServer=$null;InScope=$true;ChannelEnabled=$null;Status=$(if($count -gt 0){'Success'}else{'SuccessNoEvents'});SnapshotCopied=$UseLiveLog;EventCount=$count;Error=''})
        $htmlPath = [System.IO.Path]::ChangeExtension($csvPath,'.html')
        $runLogPath = Join-Path $OutputFolder (([System.IO.Path]::GetFileNameWithoutExtension($csvPath)) + '-Execution.log')
        if ($SelectedReports -contains 'HTML') { Export-PrintAuditHtml -CsvPath $csvPath -StatusRows $status -Path $htmlPath -ScopeName $(if($UseLiveLog){$script:MachineName}else{$LogFolderPath}); $script:LastHtmlPath=$htmlPath }
        if ($SelectedReports -contains 'LOG') { Copy-Item -LiteralPath $script:LogPath -Destination $runLogPath -Force -ErrorAction SilentlyContinue }
        if ($SelectedReports -contains 'CSV') { $script:LastCsvPath = $csvPath } else { Remove-Item -LiteralPath $csvPath -Force -ErrorAction SilentlyContinue; $script:LastCsvPath=$null }
        $script:LastOutputFolder = $OutputFolder
        Write-Log -Message ("Print audit completed. Events found={0}; Report={1}" -f $count, $csvPath)
        Update-ProgressSafe -Value 100
        Set-Status -Text ("Completed. Events found={0}; Report={1}" -f $count, $csvPath)
        Show-MessageBox -Message ("Events found: {0}`r`nOutput folder:`r`n{1}" -f $count, $OutputFolder) -Title 'Print Audit Completed'

        if ($AutoOpen) {
            if (($SelectedReports -contains 'HTML') -and (Test-Path -LiteralPath $htmlPath)) { Start-Process -FilePath $htmlPath }
            elseif (($SelectedReports -contains 'CSV') -and (Test-Path -LiteralPath $csvPath)) { Start-Process -FilePath $csvPath }
        }
    }
    catch {
        $message = "Event ID 307 print audit failed. $($_.Exception.Message)"
        Write-Log -Message ("{0} Position='{1}' Stack='{2}'" -f $message,$_.InvocationInfo.PositionMessage,$_.ScriptStackTrace) -Level 'ERROR'
        Update-ProgressSafe -Value 0
        Set-Status -Text 'Error occurred. Check log for details.'
        Show-MessageBox -Message $message -Title 'Print Audit Error' -Icon Error
    }
    finally {
        if ($tempCsvPath -and (Test-Path -LiteralPath $tempCsvPath)) {
            Remove-Item -LiteralPath $tempCsvPath -Force -ErrorAction SilentlyContinue
        }

        if ($snapshotEvtxPath -and (Test-Path -LiteralPath $snapshotEvtxPath)) {
            Remove-Item -LiteralPath $snapshotEvtxPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-ForestPrintAudit307 {
    [CmdletBinding()]
    param(
        [string]$RequestedForest,
        [Parameter(Mandatory)][string]$DestinationFolder,
        [Parameter(Mandatory)][string[]]$SelectedRoles,
        [Parameter(Mandatory)][string[]]$SelectedReports,
        [Parameter(Mandatory)][datetime]$FromTime,
        [Parameter(Mandatory)][datetime]$ToTime,
        [Parameter(Mandatory)][int]$Throttle,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [bool]$DiscoveryMode = $false
    )

    if ($FromTime -gt $ToTime) { throw 'StartTime must be earlier than or equal to EndTime.' }
    if (@($SelectedRoles).Count -eq 0) { throw 'Select at least one server role.' }
    if (@($SelectedReports).Count -eq 0) { throw 'Select at least one report format.' }
    Ensure-Directory -Path $DestinationFolder
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $inventory = @(Get-ForestServerInventory -RequestedForest $RequestedForest)
    if ($inventory.Count -eq 0) { throw 'Forest discovery returned no enabled Windows Server computer accounts.' }
    $resolvedForest = if ([string]::IsNullOrWhiteSpace($RequestedForest)) { (Get-ADForest).Name } else { (Get-ADForest -Identity $RequestedForest).Name }
    $domains = @($inventory | Select-Object -ExpandProperty Domain -Unique)
    if (@($domains).Count -eq 1 -and $domains[0] -ne 'Manual') { $scopeToken = (($domains[0] -split '\.')[0]).ToUpperInvariant() }
    elseif (@($inventory).Count -eq 1) { $scopeToken = (($inventory[0].ComputerName -split '\.')[0]).ToUpperInvariant() }
    else { $scopeToken = (Get-SafeFileToken -Value $resolvedForest).ToUpperInvariant() }
    $base = '{0}-EventID307-PrintAudit-{1}-Consolidated' -f $scopeToken,$stamp
    $discoveryPath = Join-Path $DestinationFolder ($base + '-Discovery.csv')
    $statusPath = Join-Path $DestinationFolder ($base + '-ServerSummary.csv')
    $htmlPath = Join-Path $DestinationFolder ($base + '-Summary.html')
    $runLogPath = Join-Path $DestinationFolder ($base + '-Execution.log')
    $staging = Join-Path $env:TEMP ('EventID307-Forest-' + [guid]::NewGuid().ToString('N'))
    $csvPath = Join-Path $staging 'Consolidated-Events-Internal.csv'

    try {
        Set-Status -Text ("Forest discovery completed: {0} candidate servers." -f $inventory.Count)
        Update-ProgressSafe -Value 10
        if ($SelectedReports -contains 'CSV') { $inventory | Export-Csv -LiteralPath $discoveryPath -NoTypeInformation -Encoding UTF8 }
        $collection = Invoke-ForestSnapshotCollection -Inventory $inventory -StagingFolder $staging -RangeStart $FromTime -RangeEnd $ToTime -SelectedRoles $SelectedRoles -Throttle $Throttle -TimeoutSeconds $TimeoutSeconds -DiscoveryMode:$DiscoveryMode
        $statusRows = @($collection.StatusRows)
        Update-ProgressSafe -Value 55
        if (-not $DiscoveryMode -and @($collection.EvtxFiles).Count -gt 0) {
            $objects = New-LogParserComObjects
            $tempCsv = Join-Path $env:TEMP ('PrintAudit307_' + [guid]::NewGuid().ToString('N') + '.csv')
            $sourceCounts = @{}
            $sourceRows = @{}
            $null = Invoke-EvtxPrint307Extraction -EvtxFiles $collection.EvtxFiles -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $tempCsv -DateRangeEnabled:$true -FromTime $FromTime -ToTime $ToTime -StatusPrefix 'Parsing forest snapshot' -SourceServerByPath $collection.SourceMap -SourceCountMap $sourceCounts -SourceRowsMap $sourceRows
            $eventCount = Normalize-PrintAuditCsv -Path $csvPath
            foreach ($serverStatus in $statusRows) {
                $serverStatus.EventCount = if ($sourceCounts.ContainsKey([string]$serverStatus.ComputerName)) { [int]$sourceCounts[[string]$serverStatus.ComputerName] } else { 0 }
                if ($serverStatus.Status -eq 'SnapshotCopied') { $serverStatus.Status = if ($serverStatus.EventCount -gt 0) { 'Success' } else { 'SuccessNoEvents' } }
            }
        }
        else { New-EmptyPrintAuditCsv -Path $csvPath; $eventCount=0; $sourceRows=@{} }

        Write-Log -Message ("Forest audit collection completed. Forest={0}; Servers={1}; Events={2}; Output={3}" -f $resolvedForest,$statusRows.Count,$eventCount,$DestinationFolder)
        foreach ($serverStatus in $statusRows) {
            Write-Log -Message ("SERVER-COVERAGE ComputerName='{0}'; Domain='{1}'; DC={2}; File={3}; Print={4}; InScope={5}; ChannelEnabled={6}; Status='{7}'; Events={8}; Error='{9}'" -f $serverStatus.ComputerName,$serverStatus.Domain,$serverStatus.IsDomainController,$serverStatus.IsFileServer,$serverStatus.IsPrintServer,$serverStatus.InScope,$serverStatus.ChannelEnabled,$serverStatus.Status,$serverStatus.EventCount,(([string]$serverStatus.Error) -replace "[\r\n]+",' '))
        }

        $serverPackages = @()
        if (-not $DiscoveryMode) {
            $serverPackages = @(Export-PerServerReportPackages -StatusRows $statusRows -SourceRowsMap $sourceRows -DestinationFolder $DestinationFolder -SelectedReports $SelectedReports -Timestamp $stamp)
        }

        if ($SelectedReports -contains 'HTML' -and -not $DiscoveryMode) {
            $summaryEventsPath = Join-Path $staging 'Summary-No-Event-Detail.csv'
            New-EmptyPrintAuditCsv -Path $summaryEventsPath
            Export-PrintAuditHtml -CsvPath $summaryEventsPath -StatusRows $statusRows -Path $htmlPath -ScopeName ($scopeToken + ' - Consolidated Summary')
        }
        if ($SelectedReports -contains 'CSV') {
            $statusRows | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8
        }
        Write-Log -Message ("Forest per-server report generation completed. Packages={0}." -f $serverPackages.Count)
        if ($SelectedReports -contains 'LOG') { Copy-Item -LiteralPath $script:LogPath -Destination $runLogPath -Force -ErrorAction SilentlyContinue }
        $script:LastCsvPath = if (($SelectedReports -contains 'CSV') -and $serverPackages.Count -gt 0) { $serverPackages[0].EventCsv } elseif ($SelectedReports -contains 'CSV') { $statusPath } else { $null }
        $script:LastHtmlPath = if (($SelectedReports -contains 'HTML') -and $serverPackages.Count -gt 0) { $serverPackages[0].Html } elseif ($SelectedReports -contains 'HTML') { $htmlPath } else { $null }
        $script:LastOutputFolder = $DestinationFolder
        Update-ProgressSafe -Value 100
        Set-Status -Text ("Forest audit completed. Servers={0}; Events={1}." -f $statusRows.Count,$eventCount)
        if ($AutoOpen) {
            if ($script:LastHtmlPath -and (Test-Path -LiteralPath $script:LastHtmlPath)) { Start-Process -FilePath $script:LastHtmlPath }
            elseif ($script:LastCsvPath -and (Test-Path -LiteralPath $script:LastCsvPath)) { Start-Process -FilePath $script:LastCsvPath }
        }
        return [pscustomobject]@{ Forest=$resolvedForest; CandidateServers=$inventory.Count; CoveredServers=$statusRows.Count; Events=$eventCount; OutputFolder=$DestinationFolder; PerServerReports=$serverPackages; ConsolidatedSummary=$(if($SelectedReports -contains 'CSV'){$statusPath}else{$null}); Html=$script:LastHtmlPath; ExecutionLog=$(if($SelectedReports -contains 'LOG'){$runLogPath}else{$null}) }
    }
    finally {
        if (Test-Path -LiteralPath $staging -PathType Container) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-ServerNameArray {
    param([AllowEmptyString()][string]$Text)
    return @($Text -split '[,;\r\n\s]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function New-ManualServerInventory {
    param([Parameter(Mandatory)][string[]]$ComputerNames)
    return @($ComputerNames | ForEach-Object {
        [pscustomobject][ordered]@{ComputerName=[string]$_;NetBIOSName=(([string]$_ -split '\.')[0]);Domain='Manual';OperatingSystem='Not audited';OperatingSystemVer='Not audited';IPv4Address='';DistinguishedName='';IsDomainController=$false;DiscoverySource='ManualServer'}
    })
}

function Invoke-RemoteArchivedEvtxCollection {
    param(
        [object[]]$Inventory, [string]$RemoteFolder, [bool]$Recurse,
        [string]$StagingFolder, [string[]]$SelectedRoles,
        [int]$Throttle, [int]$TimeoutSeconds
    )
    Ensure-Directory -Path $StagingFolder
    $targets = @($Inventory.ComputerName)
    $wantDc = $SelectedRoles -contains 'DomainController'
    $wantFile = $SelectedRoles -contains 'FileServer'
    $wantPrint = $SelectedRoles -contains 'PrintServer'
    $remote = {
        param($Folder,$Recursive,$WantDc,$WantFile,$WantPrint)
        $ErrorActionPreference = 'Stop'
        try {
            $cs = Get-WmiObject Win32_ComputerSystem -ErrorAction Stop
            $isDc = [bool]([int]$cs.DomainRole -ge 4)
            Import-Module ServerManager -ErrorAction Stop
            $features = @(Get-WindowsFeature -Name FS-FileServer,Print-Server -ErrorAction Stop)
            $isFile = [bool]($features | Where-Object { $_.Name -eq 'FS-FileServer' -and $_.Installed })
            $isPrint = [bool]($features | Where-Object { $_.Name -eq 'Print-Server' -and $_.Installed })
            $inScope = [bool](($WantDc -and $isDc) -or ($WantFile -and $isFile) -or ($WantPrint -and $isPrint))
            if (-not $inScope) {
                [pscustomobject]@{RecordType='Status';IsDomainController=$isDc;IsFileServer=$isFile;IsPrintServer=$isPrint;InScope=$false;Status='OutOfScope';Error='Selected role filters did not match.'}
                return
            }
            if (-not (Test-Path -LiteralPath $Folder -PathType Container)) {
                [pscustomobject]@{RecordType='Status';IsDomainController=$isDc;IsFileServer=$isFile;IsPrintServer=$isPrint;InScope=$true;Status='ArchivedFolderUnavailable';Error="Folder not found: $Folder"}
                return
            }
            $files = @(if ($Recursive) { Get-ChildItem -LiteralPath $Folder -Filter '*.evtx' -File -Recurse -ErrorAction Stop } else { Get-ChildItem -LiteralPath $Folder -Filter '*.evtx' -File -ErrorAction Stop })
            [pscustomobject]@{RecordType='Status';IsDomainController=$isDc;IsFileServer=$isFile;IsPrintServer=$isPrint;InScope=$true;Status=$(if (@($files).Count -gt 0) {'ArchiveDiscovered'} else {'SuccessNoEvtxFiles'});Error=''}
            foreach ($f in @($files)) { [pscustomobject]@{RecordType='File';FullName=[string]$f.FullName;Name=[string]$f.Name} }
        }
        catch { [pscustomobject]@{RecordType='Status';IsDomainController=$false;IsFileServer=$false;IsPrintServer=$false;InScope=$null;Status='CollectionFailed';Error=$_.Exception.Message} }
    }
    $job = Invoke-Command -ComputerName $targets -AsJob -ThrottleLimit $Throttle -ScriptBlock $remote -ArgumentList $RemoteFolder,$Recurse,$wantDc,$wantFile,$wantPrint -ErrorAction SilentlyContinue
    if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) { Stop-Job -Job $job -ErrorAction SilentlyContinue }
    $received = @(Receive-Job -Job $job -ErrorAction SilentlyContinue)
    $childFailures = @($job.ChildJobs | Where-Object { $_.State -ne 'Completed' -or $_.JobStateInfo.Reason })
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    $statusRows = New-Object System.Collections.ArrayList
    $localFiles = New-Object System.Collections.ArrayList
    $sourceMap = @{}
    foreach ($item in @($Inventory)) {
        $serverResults = @($received | Where-Object { $_.PSComputerName -ieq $item.ComputerName })
        $remoteStatus = @($serverResults | Where-Object { $_.RecordType -eq 'Status' } | Select-Object -First 1)
        if (@($remoteStatus).Count -eq 0) {
            $failure = @($childFailures | Where-Object { $_.Location -ieq $item.ComputerName } | Select-Object -First 1)
            $detail = if (@($failure).Count -gt 0 -and $failure[0].JobStateInfo.Reason) { $failure[0].JobStateInfo.Reason.Message } else { 'No remoting result returned.' }
            [void]$statusRows.Add([pscustomobject][ordered]@{ComputerName=$item.ComputerName;Domain=$item.Domain;IsDomainController=$item.IsDomainController;IsFileServer=$null;IsPrintServer=$null;InScope=$null;ChannelEnabled=$null;Status='UnreachableOrUnauthorized';SnapshotCopied=$false;EventCount=0;Error=$detail})
            continue
        }
        $rs = $remoteStatus[0]; $copied = 0; $copyErrors = New-Object System.Collections.ArrayList
        foreach ($rf in @($serverResults | Where-Object { $_.RecordType -eq 'File' })) {
            try {
                $uncPrefix = '\\{0}\$1$' -f $item.ComputerName
                $source = ([string]$rf.FullName) -replace '^([A-Za-z]):', $uncPrefix
                $dest = Join-Path $StagingFolder ('{0}-{1}-{2}' -f (Get-SafeFileToken $item.ComputerName),([guid]::NewGuid().ToString('N').Substring(0,8)),$rf.Name)
                Copy-Item -LiteralPath $source -Destination $dest -Force -ErrorAction Stop
                $fi = Get-Item -LiteralPath $dest -ErrorAction Stop
                [void]$localFiles.Add($fi); $sourceMap[$fi.FullName] = $item.ComputerName; $copied++
            }
            catch { [void]$copyErrors.Add($_.Exception.Message) }
        }
        $finalStatus = if (@($copyErrors).Count -gt 0) {'ArchiveCopyPartial'} elseif ($rs.Status -eq 'ArchiveDiscovered') {'ArchiveCopied'} else {$rs.Status}
        [void]$statusRows.Add([pscustomobject][ordered]@{ComputerName=$item.ComputerName;Domain=$item.Domain;IsDomainController=[bool]$rs.IsDomainController;IsFileServer=[bool]$rs.IsFileServer;IsPrintServer=[bool]$rs.IsPrintServer;InScope=$rs.InScope;ChannelEnabled=$null;Status=$finalStatus;SnapshotCopied=($copied -gt 0);EventCount=0;Error=(@($copyErrors) -join ' | ')})
    }
    return [pscustomobject]@{StatusRows=@($statusRows | ForEach-Object {$_});EvtxFiles=@($localFiles | ForEach-Object {$_});SourceMap=$sourceMap}
}

function Start-RemoteArchivedPrintAudit307 {
    param(
        [object[]]$Inventory,
        [string]$RemoteFolder,
        [bool]$Recurse,
        [string]$DestinationFolder,
        [string[]]$SelectedRoles,
        [string[]]$SelectedReports,
        [bool]$DateRangeEnabled,
        [datetime]$FromTime,
        [datetime]$ToTime,
        [int]$Throttle,
        [int]$TimeoutSeconds
    )
    Ensure-Directory -Path $DestinationFolder
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $domains = @($Inventory | Select-Object -ExpandProperty Domain -Unique)
    if (@($domains).Count -eq 1 -and $domains[0] -ne 'Manual') { $scopeToken = (($domains[0] -split '\.')[0]).ToUpperInvariant() }
    elseif (@($Inventory).Count -eq 1) { $scopeToken = (($Inventory[0].ComputerName -split '\.')[0]).ToUpperInvariant() }
    else { $scopeToken = 'MULTISERVER' }
    $base = '{0}-EventID307-PrintAudit-{1}-Consolidated' -f $scopeToken,$stamp
    $statusPath = Join-Path $DestinationFolder ($base + '-ServerSummary.csv')
    $htmlPath = Join-Path $DestinationFolder ($base + '-Summary.html')
    $staging = Join-Path $env:TEMP ('EventID307-RemoteArchive-' + [guid]::NewGuid().ToString('N'))
    $csvPath = Join-Path $staging 'Consolidated-Events-Internal.csv'
    try {
        Update-ProgressSafe -Value 5
        Set-Status -Text 'Discovering and copying archived EVTX evidence from the selected server(s)...'
        Write-Log -Message ("Starting remote archived EVTX audit. Servers={0}; Folder='{1}'; Recurse={2}; DateRangeEnabled={3}; From='{4}'; To='{5}'" -f @($Inventory).Count,$RemoteFolder,$Recurse,$DateRangeEnabled,$FromTime,$ToTime)
        $collection = Invoke-RemoteArchivedEvtxCollection -Inventory @($Inventory) -RemoteFolder $RemoteFolder -Recurse:$Recurse -StagingFolder $staging -SelectedRoles $SelectedRoles -Throttle $Throttle -TimeoutSeconds $TimeoutSeconds
        Update-ProgressSafe -Value 10
        Write-Log -Message ("Remote archived EVTX collection completed. StatusRows={0}; CopiedFiles={1}" -f @($collection.StatusRows).Count,@($collection.EvtxFiles).Count)
        $status = @($collection.StatusRows); $counts = @{}; $sourceRows = @{}
        if (@($collection.EvtxFiles).Count -gt 0) {
            $o = New-LogParserComObjects; $temp = Join-Path $env:TEMP ('PrintAudit307_' + [guid]::NewGuid().ToString('N') + '.csv')
            $null = Invoke-EvtxPrint307Extraction -EvtxFiles $collection.EvtxFiles -LogQuery $o.LogQuery -InputFormat $o.InputFormat -OutputFormat $o.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $temp -DateRangeEnabled:$DateRangeEnabled -FromTime $FromTime -ToTime $ToTime -SourceServerByPath $collection.SourceMap -SourceCountMap $counts -SourceRowsMap $sourceRows
            $eventCount = Normalize-PrintAuditCsv -Path $csvPath
        }
        else { New-EmptyPrintAuditCsv -Path $csvPath; $eventCount = 0 }
        foreach ($row in $status) {
            $row.EventCount = if ($counts.ContainsKey([string]$row.ComputerName)) { [int]$counts[[string]$row.ComputerName] } else { 0 }
            if ($row.Status -eq 'ArchiveCopied') {
                $row.Status = if ($row.EventCount -gt 0) { 'Success' } else { 'SuccessNoEventsInRange' }
            }
        }
        Write-Log -Message ("Remote archived EVTX extraction completed. Servers={0}; Events={1}" -f @($status).Count,$eventCount)
        foreach ($serverStatus in $status) {
            Write-Log -Message ("SERVER-COVERAGE ComputerName='{0}'; Domain='{1}'; DC={2}; File={3}; Print={4}; InScope={5}; ChannelEnabled={6}; Status='{7}'; Events={8}; Error='{9}'" -f $serverStatus.ComputerName,$serverStatus.Domain,$serverStatus.IsDomainController,$serverStatus.IsFileServer,$serverStatus.IsPrintServer,$serverStatus.InScope,$serverStatus.ChannelEnabled,$serverStatus.Status,$serverStatus.EventCount,(([string]$serverStatus.Error) -replace "[\r\n]+",' '))
        }
        $serverPackages = @(Export-PerServerReportPackages -StatusRows $status -SourceRowsMap $sourceRows -DestinationFolder $DestinationFolder -SelectedReports $SelectedReports -Timestamp $stamp)
        if ($SelectedReports -contains 'HTML') {
            $summaryEventsPath = Join-Path $staging 'Summary-No-Event-Detail.csv'
            New-EmptyPrintAuditCsv -Path $summaryEventsPath
            Export-PrintAuditHtml -CsvPath $summaryEventsPath -StatusRows $status -Path $htmlPath -ScopeName ($scopeToken + ' - Consolidated Summary')
        }
        if ($SelectedReports -contains 'CSV') { $status | Export-Csv -LiteralPath $statusPath -NoTypeInformation -Encoding UTF8 }
        if ($SelectedReports -contains 'LOG') { Copy-Item -LiteralPath $script:LogPath -Destination (Join-Path $DestinationFolder ($base + '-Execution.log')) -Force -ErrorAction SilentlyContinue }
        $script:LastCsvPath = if (($SelectedReports -contains 'CSV') -and $serverPackages.Count -gt 0) { $serverPackages[0].EventCsv } elseif ($SelectedReports -contains 'CSV') { $statusPath } else { $null }
        $script:LastHtmlPath = if (($SelectedReports -contains 'HTML') -and $serverPackages.Count -gt 0) { $serverPackages[0].Html } elseif ($SelectedReports -contains 'HTML') { $htmlPath } else { $null }
        $script:LastOutputFolder=$DestinationFolder
        Update-ProgressSafe -Value 100
        Set-Status -Text ("Completed. Server reports={0}; Events={1}." -f $serverPackages.Count,$eventCount)
        return [pscustomobject]@{CoveredServers=@($status).Count;Events=$eventCount;OutputFolder=$DestinationFolder;PerServerReports=$serverPackages;ConsolidatedSummary=$(if($SelectedReports -contains 'CSV'){$statusPath}else{$null})}
    }
    finally { if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue } }
}

Ensure-Directory -Path $script:LogDir
Write-Log -Message ("Script started. Version={0}" -f $script:Version)
Write-Log -Message "Output-clean CSV schema initialized."

if ($Mode -ne 'GUI') {
    try {
        switch ($Mode) {
            'ForestLive' {
                $result = Start-ForestPrintAudit307 -RequestedForest $ForestName -DestinationFolder $OutputFolder -SelectedRoles $ServerRole -SelectedReports $ReportFormat -FromTime $StartTime -ToTime $EndTime -Throttle $ThrottleLimit -TimeoutSeconds $OperationTimeoutSeconds -DiscoveryMode:$DiscoveryOnly.IsPresent
                $result | Format-List | Out-Host
            }
            'LocalLive' {
                Start-PrintAudit307 -LogFolderPath '' -OutputFolder $OutputFolder -UseLiveLog:$true -IncludeSubfolders:$false -DateRangeEnabled:$true -FromTime $StartTime -ToTime $EndTime -SelectedReports $ReportFormat
            }
            'ArchivedEvtx' {
                if ([string]::IsNullOrWhiteSpace($ArchivedEvtxFolder)) { throw '-ArchivedEvtxFolder is required when Mode is ArchivedEvtx.' }
                Start-PrintAudit307 -LogFolderPath $ArchivedEvtxFolder -OutputFolder $OutputFolder -UseLiveLog:$false -IncludeSubfolders:$RecurseArchivedEvtx.IsPresent -DateRangeEnabled:$true -FromTime $StartTime -ToTime $EndTime -SelectedReports $ReportFormat
            }
        }
        Write-Log -Message 'Script ended successfully.'
        return
    }
    catch {
        Write-Log -Message ("CLI execution failed. {0}" -f $_.Exception.Message) -Level 'ERROR'
        throw
    }
}

function Show-Event307EnterpriseGui {
    [CmdletBinding()]
    param()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Event ID 307 Print Audit - Enterprise Edition'
    $form.Size = New-Object System.Drawing.Size(1320,820)
    $form.MinimumSize = New-Object System.Drawing.Size(1080,700)
    $form.StartPosition = 'CenterScreen'

    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = 'Fill'; $main.Padding = New-Object System.Windows.Forms.Padding(10)
    $main.ColumnCount = 1; $main.RowCount = 9
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',55)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',45)))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $form.Controls.Add($main)

    $pathPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $pathPanel.Dock='Fill'; $pathPanel.AutoSize=$true; $pathPanel.WrapContents=$false
    $labelOutput=New-Object System.Windows.Forms.Label; $labelOutput.Text='Output folder:'; $labelOutput.AutoSize=$true; $labelOutput.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
    $txtOutput=New-Object System.Windows.Forms.TextBox; $txtOutput.Width=710; $txtOutput.Text=$script:DefaultOutputDir
    $btnBrowseOutput=New-Object System.Windows.Forms.Button; $btnBrowseOutput.Text='Browse'; $btnBrowseOutput.Width=90
    $labelLog=New-Object System.Windows.Forms.Label; $labelLog.Text='Log folder:'; $labelLog.AutoSize=$true; $labelLog.Margin=New-Object System.Windows.Forms.Padding(18,7,3,3)
    $txtLog=New-Object System.Windows.Forms.TextBox; $txtLog.Width=230; $txtLog.Text=$script:LogDir
    [void]$pathPanel.Controls.Add($labelOutput); [void]$pathPanel.Controls.Add($txtOutput); [void]$pathPanel.Controls.Add($btnBrowseOutput); [void]$pathPanel.Controls.Add($labelLog); [void]$pathPanel.Controls.Add($txtLog)
    $main.Controls.Add($pathPanel,0,0)

    $scopePanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $scopePanel.Dock='Fill'; $scopePanel.AutoSize=$true; $scopePanel.WrapContents=$true
    $labelScope=New-Object System.Windows.Forms.Label; $labelScope.Text='Target scope:'; $labelScope.AutoSize=$true; $labelScope.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
    $comboScope=New-Object System.Windows.Forms.ComboBox; $comboScope.Width=225; $comboScope.DropDownStyle='DropDownList'
    [void]$comboScope.Items.AddRange(@('Local Computer','Selected Authorized DHCP Servers','Manual Servers')); $comboScope.SelectedIndex=0
    $labelSource=New-Object System.Windows.Forms.Label; $labelSource.Text='Evidence source:'; $labelSource.AutoSize=$true; $labelSource.Margin=New-Object System.Windows.Forms.Padding(18,7,3,3)
    $comboSource=New-Object System.Windows.Forms.ComboBox; $comboSource.Width=210; $comboSource.DropDownStyle='DropDownList'
    [void]$comboSource.Items.AddRange(@('Live PrintService Channel','Archived EVTX Folder')); $comboSource.SelectedIndex=0
    $labelForest=New-Object System.Windows.Forms.Label; $labelForest.Text='Forest:'; $labelForest.AutoSize=$true; $labelForest.Margin=New-Object System.Windows.Forms.Padding(18,7,3,3)
    $txtForest=New-Object System.Windows.Forms.TextBox; $txtForest.Width=190; $txtForest.Text=$ForestName; $txtForest.Enabled=$false
    $labelManual=New-Object System.Windows.Forms.Label; $labelManual.Text='Manual servers:'; $labelManual.AutoSize=$true; $labelManual.Margin=New-Object System.Windows.Forms.Padding(18,7,3,3)
    $txtManual=New-Object System.Windows.Forms.TextBox; $txtManual.Width=300; $txtManual.Enabled=$false
    $labelArchive=New-Object System.Windows.Forms.Label; $labelArchive.Text='EVTX folder:'; $labelArchive.AutoSize=$true; $labelArchive.Margin=New-Object System.Windows.Forms.Padding(18,7,3,3)
    $txtArchive=New-Object System.Windows.Forms.TextBox; $txtArchive.Width=300; $txtArchive.Text='L:\Microsoft-Windows-PrintService-Operational'; $txtArchive.Enabled=$false
    $btnBrowseArchive=New-Object System.Windows.Forms.Button; $btnBrowseArchive.Text='Browse'; $btnBrowseArchive.Width=85; $btnBrowseArchive.Enabled=$false
    [void]$scopePanel.Controls.Add($labelScope); [void]$scopePanel.Controls.Add($comboScope); [void]$scopePanel.Controls.Add($labelSource); [void]$scopePanel.Controls.Add($comboSource); [void]$scopePanel.Controls.Add($labelForest); [void]$scopePanel.Controls.Add($txtForest); [void]$scopePanel.Controls.Add($labelManual); [void]$scopePanel.Controls.Add($txtManual); [void]$scopePanel.Controls.Add($labelArchive); [void]$scopePanel.Controls.Add($txtArchive); [void]$scopePanel.Controls.Add($btnBrowseArchive)
    $main.Controls.Add($scopePanel,0,1)

    $optionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $optionPanel.Dock='Fill'; $optionPanel.AutoSize=$true; $optionPanel.WrapContents=$false
    $btnLoad=New-Object System.Windows.Forms.Button; $btnLoad.Text='Load DHCP Servers'; $btnLoad.Width=145; $btnLoad.Enabled=$false
    $btnAll=New-Object System.Windows.Forms.Button; $btnAll.Text='Select All'; $btnAll.Width=90; $btnAll.Enabled=$false
    $btnNone=New-Object System.Windows.Forms.Button; $btnNone.Text='Clear Selection'; $btnNone.Width=105; $btnNone.Enabled=$false
    $chkDc=New-Object System.Windows.Forms.CheckBox; $chkDc.Text='Domain Controllers'; $chkDc.Checked=$true; $chkDc.AutoSize=$true; $chkDc.Enabled=$false; $chkDc.Margin=New-Object System.Windows.Forms.Padding(18,6,3,3)
    $chkFile=New-Object System.Windows.Forms.CheckBox; $chkFile.Text='File Servers'; $chkFile.Checked=$true; $chkFile.AutoSize=$true; $chkFile.Enabled=$false
    $chkPrint=New-Object System.Windows.Forms.CheckBox; $chkPrint.Text='Print Servers'; $chkPrint.Checked=$true; $chkPrint.AutoSize=$true; $chkPrint.Enabled=$false
    $chkRecurse=New-Object System.Windows.Forms.CheckBox; $chkRecurse.Text='Include EVTX subfolders'; $chkRecurse.Checked=$true; $chkRecurse.AutoSize=$true; $chkRecurse.Enabled=$false; $chkRecurse.Margin=New-Object System.Windows.Forms.Padding(18,6,3,3)
    $btnResolve=New-Object System.Windows.Forms.Button; $btnResolve.Text='Resolve Channel'; $btnResolve.Width=115
    [void]$optionPanel.Controls.Add($btnLoad); [void]$optionPanel.Controls.Add($btnAll); [void]$optionPanel.Controls.Add($btnNone); [void]$optionPanel.Controls.Add($chkDc); [void]$optionPanel.Controls.Add($chkFile); [void]$optionPanel.Controls.Add($chkPrint); [void]$optionPanel.Controls.Add($chkRecurse); [void]$optionPanel.Controls.Add($btnResolve)
    $main.Controls.Add($optionPanel,0,2)

    $listServers = New-Object System.Windows.Forms.ListView
    $listServers.Dock='Fill'; $listServers.View='Details'; $listServers.FullRowSelect=$true; $listServers.GridLines=$true; $listServers.CheckBoxes=$true; $listServers.HideSelection=$false; $listServers.Enabled=$false
    [void]$listServers.Columns.Add('Server',330); [void]$listServers.Columns.Add('IP Address',130); [void]$listServers.Columns.Add('Domain',220); [void]$listServers.Columns.Add('Discovery Source',160); [void]$listServers.Columns.Add('DC',60)
    $main.Controls.Add($listServers,0,3)

    $reportPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $reportPanel.Dock='Fill'; $reportPanel.AutoSize=$true; $reportPanel.WrapContents=$false
    $labelReports=New-Object System.Windows.Forms.Label; $labelReports.Text='Reports:'; $labelReports.AutoSize=$true; $labelReports.Margin=New-Object System.Windows.Forms.Padding(3,7,3,3)
    $chkCsv=New-Object System.Windows.Forms.CheckBox; $chkCsv.Text='CSV'; $chkCsv.Checked=$true; $chkCsv.AutoSize=$true
    $chkHtml=New-Object System.Windows.Forms.CheckBox; $chkHtml.Text='Printable HTML'; $chkHtml.Checked=$true; $chkHtml.AutoSize=$true
    $chkLog=New-Object System.Windows.Forms.CheckBox; $chkLog.Text='Consolidated execution log'; $chkLog.Checked=$true; $chkLog.AutoSize=$true
    $chkDates=New-Object System.Windows.Forms.CheckBox; $chkDates.Text='Use date range'; $chkDates.Checked=$true; $chkDates.AutoSize=$true; $chkDates.Margin=New-Object System.Windows.Forms.Padding(25,6,3,3)
    $labelFrom=New-Object System.Windows.Forms.Label; $labelFrom.Text='From:'; $labelFrom.AutoSize=$true; $labelFrom.Margin=New-Object System.Windows.Forms.Padding(12,7,3,3)
    $dateFrom=New-Object System.Windows.Forms.DateTimePicker; $dateFrom.Width=190; $dateFrom.Format='Custom'; $dateFrom.CustomFormat='yyyy-MM-dd HH:mm:ss'; $dateFrom.Value=$StartTime
    $labelTo=New-Object System.Windows.Forms.Label; $labelTo.Text='To:'; $labelTo.AutoSize=$true; $labelTo.Margin=New-Object System.Windows.Forms.Padding(12,7,3,3)
    $dateTo=New-Object System.Windows.Forms.DateTimePicker; $dateTo.Width=190; $dateTo.Format='Custom'; $dateTo.CustomFormat='yyyy-MM-dd HH:mm:ss'; $dateTo.Value=$EndTime
    foreach($control in @($labelReports,$chkCsv,$chkHtml,$chkLog,$chkDates,$labelFrom,$dateFrom,$labelTo,$dateTo)){[void]$reportPanel.Controls.Add($control)}
    $main.Controls.Add($reportPanel,0,4)

    $summary=New-Object System.Windows.Forms.Label; $summary.AutoSize=$true; $summary.Text='Ready. Select an audit scope.'
    $summary.Dock='Fill'; $summary.TextAlign='MiddleLeft'; $main.Controls.Add($summary,0,5)

    $runtime=New-Object System.Windows.Forms.TextBox; $runtime.Dock='Fill'; $runtime.Multiline=$true; $runtime.ReadOnly=$true; $runtime.ScrollBars='Vertical'; $runtime.Font=New-Object System.Drawing.Font('Consolas',8.5)
    $main.Controls.Add($runtime,0,6)

    $actionPanel=New-Object System.Windows.Forms.FlowLayoutPanel; $actionPanel.Dock='Fill'; $actionPanel.AutoSize=$true; $actionPanel.FlowDirection='RightToLeft'; $actionPanel.WrapContents=$false
    $btnClose=New-Object System.Windows.Forms.Button; $btnClose.Text='Close'; $btnClose.Width=100
    $btnOpen=New-Object System.Windows.Forms.Button; $btnOpen.Text='Open Output'; $btnOpen.Width=120
    $btnStart=New-Object System.Windows.Forms.Button; $btnStart.Text='Start Analysis'; $btnStart.Width=130
    [void]$actionPanel.Controls.Add($btnClose); [void]$actionPanel.Controls.Add($btnOpen); [void]$actionPanel.Controls.Add($btnStart); $main.Controls.Add($actionPanel,0,7)

    $statusStrip=New-Object System.Windows.Forms.StatusStrip
    $progress=New-Object System.Windows.Forms.ToolStripProgressBar; $progress.Name='AuditProgress'; $progress.Minimum=0; $progress.Maximum=100; $progress.Value=0; $progress.Width=240; $progress.Alignment='Left'; [void]$statusStrip.Items.Add($progress)
    $statusMain=New-Object System.Windows.Forms.ToolStripStatusLabel; $statusMain.Spring=$true; $statusMain.TextAlign='MiddleLeft'; $statusMain.Text='Ready'; [void]$statusStrip.Items.Add($statusMain)
    $statusLog=New-Object System.Windows.Forms.ToolStripStatusLabel; $statusLog.Text="Log: $($script:LogPath)"; [void]$statusStrip.Items.Add($statusLog); $main.Controls.Add($statusStrip,0,8)

    $script:Form=$form; $script:StatusLabel=$statusMain; $script:ProgressBar=$progress; $script:RuntimeLog=$runtime

    $btnBrowseOutput.Add_Click({$folder=Select-Folder -Description 'Select output folder';if($folder){$txtOutput.Text=$folder}})
    $btnBrowseArchive.Add_Click({$folder=Select-Folder -Description 'Select archived EVTX folder';if($folder){$txtArchive.Text=$folder}})
    $updateScopeControls={
        $remoteMode=($comboScope.SelectedItem -ne 'Local Computer');$dhcpMode=($comboScope.SelectedItem -eq 'Selected Authorized DHCP Servers');$manualMode=($comboScope.SelectedItem -eq 'Manual Servers');$archiveMode=($comboSource.SelectedItem -eq 'Archived EVTX Folder')
        foreach($c in @($txtForest,$btnLoad,$btnAll,$btnNone,$listServers)){$c.Enabled=$dhcpMode}
        foreach($c in @($chkDc,$chkFile,$chkPrint)){$c.Enabled=$remoteMode}
        $txtManual.Enabled=$manualMode;$txtArchive.Enabled=$archiveMode;$btnBrowseArchive.Enabled=$archiveMode;$chkRecurse.Enabled=$archiveMode;$btnResolve.Enabled=(-not $remoteMode -and -not $archiveMode)
        if($archiveMode -and $remoteMode){$summary.Text='EVTX folder is interpreted as the same local path on every selected remote server.'}
    }
    $comboScope.Add_SelectedIndexChanged($updateScopeControls)
    $comboSource.Add_SelectedIndexChanged($updateScopeControls)
    $btnLoad.Add_Click({
        Invoke-GuiSafe -Context 'Load DHCP Servers' -ScriptBlock {
            try{$script:SelectedServer=@();$items=@(Get-ForestServerInventory -RequestedForest $txtForest.Text);$script:GuiServerInventory=@($items);$listServers.Items.Clear();foreach($server in $items){$li=New-Object System.Windows.Forms.ListViewItem([string]$server.ComputerName);[void]$li.SubItems.Add([string]$server.IPv4Address);[void]$li.SubItems.Add([string]$server.Domain);[void]$li.SubItems.Add([string]$server.DiscoverySource);[void]$li.SubItems.Add([string]$server.IsDomainController);$li.Tag=$server;[void]$listServers.Items.Add($li)};$summary.Text="Discovered $(@($items).Count) authorized DHCP server(s). Select the target rows."}finally{Update-ProgressSafe 0}
        }
    })
    $btnAll.Add_Click({foreach($li in $listServers.Items){$li.Checked=$true};$summary.Text="Selected $($listServers.CheckedItems.Count) server(s)."})
    $btnNone.Add_Click({foreach($li in $listServers.Items){$li.Checked=$false};$summary.Text='No servers selected.'})
    $btnResolve.Add_Click({Invoke-GuiSafe -Context 'Resolve Channel' -ScriptBlock {$null=Test-LivePrintChannel;$summary.Text='Local PrintService channel and Log Parser validation succeeded.'}})
    $chkDates.Add_CheckedChanged({$dateFrom.Enabled=$chkDates.Checked;$dateTo.Enabled=$chkDates.Checked})
    $btnClose.Add_Click({$form.Close()})
    $btnOpen.Add_Click({if($script:LastHtmlPath -and (Test-Path $script:LastHtmlPath)){Start-Process $script:LastHtmlPath}elseif($script:LastCsvPath -and (Test-Path $script:LastCsvPath)){Start-Process $script:LastCsvPath}elseif($script:LastOutputFolder){Start-Process $script:LastOutputFolder}})
    $btnStart.Add_Click({
        Invoke-GuiSafe -Context 'Start Analysis' -ScriptBlock {
            Update-ProgressSafe -Value 0
            Set-Status -Text 'Starting analysis...'
            $script:LogDir = $txtLog.Text
            $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
            Ensure-Directory $script:LogDir
            $statusLog.Text = "Log: $($script:LogPath)"

            $reports = @()
            if ($chkCsv.Checked) { $reports += 'CSV' }
            if ($chkHtml.Checked) { $reports += 'HTML' }
            if ($chkLog.Checked) { $reports += 'LOG' }
            if (@($reports).Count -eq 0) {
                Show-ValidationWarning -Message 'Select at least one report output.' -Title 'Report Selection Required'
                return
            }

            if ($chkDates.Checked -and $dateFrom.Value -gt $dateTo.Value) {
                Show-ValidationWarning -Message 'The From date/time must be earlier than or equal to To date/time.' -Title 'Invalid Date Range'
                return
            }

            $targetScope = [string]$comboScope.SelectedItem
            $evidenceSource = [string]$comboSource.SelectedItem
            if ($targetScope -eq 'Local Computer') {
                if ($evidenceSource -eq 'Live PrintService Channel') {
                    Start-PrintAudit307 -LogFolderPath '' -OutputFolder $txtOutput.Text -UseLiveLog:$true -IncludeSubfolders:$false -DateRangeEnabled:$chkDates.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value -SelectedReports $reports
                }
                else {
                    Start-PrintAudit307 -LogFolderPath $txtArchive.Text -OutputFolder $txtOutput.Text -UseLiveLog:$false -IncludeSubfolders:$chkRecurse.Checked -DateRangeEnabled:$chkDates.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value -SelectedReports $reports
                }
                $summary.Text = 'Local audit completed.'
            }
            else {
                if ($targetScope -eq 'Selected Authorized DHCP Servers') {
                    $selected = @($listServers.CheckedItems | ForEach-Object { $_.Tag.ComputerName })
                    if (@($selected).Count -eq 0) {
                        Show-ValidationWarning -Message 'Load and select at least one authorized DHCP server.' -Title 'Server Selection Required'
                        return
                    }
                    $script:SelectedServer = @($selected)
                    $inventory = @($script:GuiServerInventory | Where-Object { $selected -contains $_.ComputerName })
                }
                else {
                    $selected = @(ConvertTo-ServerNameArray $txtManual.Text)
                    if (@($selected).Count -eq 0) {
                        Show-ValidationWarning -Message 'Enter at least one manual server name or FQDN.' -Title 'Manual Server Required'
                        return
                    }
                    $inventory = @(New-ManualServerInventory $selected)
                    $script:AdditionalServer = @($selected)
                    $script:SelectedServer = @($selected)
                }

                $roles = @()
                if ($chkDc.Checked) { $roles += 'DomainController' }
                if ($chkFile.Checked) { $roles += 'FileServer' }
                if ($chkPrint.Checked) { $roles += 'PrintServer' }
                if (@($roles).Count -eq 0) {
                    Show-ValidationWarning -Message 'Select at least one server role.' -Title 'Role Selection Required'
                    return
                }

                if ($evidenceSource -eq 'Live PrintService Channel') {
                    $result = Start-ForestPrintAudit307 -RequestedForest $txtForest.Text -DestinationFolder $txtOutput.Text -SelectedRoles $roles -SelectedReports $reports -FromTime $dateFrom.Value -ToTime $dateTo.Value -Throttle $ThrottleLimit -TimeoutSeconds $OperationTimeoutSeconds
                }
                else {
                    $result = Start-RemoteArchivedPrintAudit307 -Inventory $inventory -RemoteFolder $txtArchive.Text -Recurse:$chkRecurse.Checked -DestinationFolder $txtOutput.Text -SelectedRoles $roles -SelectedReports $reports -DateRangeEnabled:$chkDates.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value -Throttle $ThrottleLimit -TimeoutSeconds $OperationTimeoutSeconds
                }
                $summary.Text = "Completed: $($result.CoveredServers) remote server(s), $($result.Events) event(s)."
                Update-ProgressSafe -Value 100
                Set-Status -Text ("Completed. Server reports={0}; Events={1}." -f @($result.PerServerReports).Count,$result.Events)
                Show-MessageBox -Message ("Event ID 307 print audit completed successfully.`r`n`r`nServers processed: {0}`r`nServer report packages: {1}`r`nEvents found: {2}`r`n`r`nReports folder:`r`n{3}" -f $result.CoveredServers,@($result.PerServerReports).Count,$result.Events,$result.OutputFolder) -Title 'Print Audit Completed' -Icon Information
            }
        }
    })

    Write-Log -Message ("Enterprise GUI initialized. PowerShell={0}; OS={1}" -f $PSVersionTable.PSVersion,[Environment]::OSVersion.VersionString)
    [void]$form.ShowDialog()
    $script:RuntimeLog=$null; $script:Form=$null; $script:StatusLabel=$null; $script:ProgressBar=$null
}

Show-Event307EnterpriseGui
Write-Log -Message 'Script ended.'
return

$form = New-Object System.Windows.Forms.Form
$form.Text = 'EventID307 Print Audit - Output Clean'
$form.Size = New-UiSize -Width 1040 -Height 900
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.AutoScroll = $true

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

$checkBoxForestMode = New-Object System.Windows.Forms.CheckBox
$checkBoxForestMode.Location = New-UiPoint -X $left -Y $top
$checkBoxForestMode.Size = New-UiSize -Width 250 -Height 24
$checkBoxForestMode.Text = 'Use forest-wide live collection'
$checkBoxForestMode.Checked = $false
$form.Controls.Add($checkBoxForestMode)

$labelForest = New-Object System.Windows.Forms.Label
$labelForest.Location = New-UiPoint -X 285 -Y $top
$labelForest.Size = New-UiSize -Width 90 -Height 24
$labelForest.Text = 'Forest:'
$form.Controls.Add($labelForest)

$textBoxForest = New-Object System.Windows.Forms.TextBox
$textBoxForest.Location = New-UiPoint -X 350 -Y ([int]($top - 2))
$textBoxForest.Size = New-UiSize -Width 260 -Height 24
$textBoxForest.Text = $ForestName
$textBoxForest.Enabled = $false
$form.Controls.Add($textBoxForest)

$top += $rowHeight

$labelRoles = New-Object System.Windows.Forms.Label
$labelRoles.Location = New-UiPoint -X $left -Y $top
$labelRoles.Size = New-UiSize -Width 145 -Height 24
$labelRoles.Text = 'Forest roles:'
$form.Controls.Add($labelRoles)

$checkBoxDc = New-Object System.Windows.Forms.CheckBox
$checkBoxDc.Location = New-UiPoint -X $inputLeft -Y $top
$checkBoxDc.Size = New-UiSize -Width 160 -Height 24
$checkBoxDc.Text = 'Domain Controllers'
$checkBoxDc.Checked = $true
$checkBoxDc.Enabled = $false
$form.Controls.Add($checkBoxDc)

$checkBoxFile = New-Object System.Windows.Forms.CheckBox
$checkBoxFile.Location = New-UiPoint -X 365 -Y $top
$checkBoxFile.Size = New-UiSize -Width 125 -Height 24
$checkBoxFile.Text = 'File Servers'
$checkBoxFile.Checked = $true
$checkBoxFile.Enabled = $false
$form.Controls.Add($checkBoxFile)

$checkBoxPrint = New-Object System.Windows.Forms.CheckBox
$checkBoxPrint.Location = New-UiPoint -X 510 -Y $top
$checkBoxPrint.Size = New-UiSize -Width 135 -Height 24
$checkBoxPrint.Text = 'Print Servers'
$checkBoxPrint.Checked = $true
$checkBoxPrint.Enabled = $false
$form.Controls.Add($checkBoxPrint)

$buttonLoadDhcp = New-Object System.Windows.Forms.Button
$buttonLoadDhcp.Location = New-UiPoint -X 665 -Y ([int]($top - 4))
$buttonLoadDhcp.Size = New-UiSize -Width 145 -Height 28
$buttonLoadDhcp.Text = 'Load DHCP Servers'
$buttonLoadDhcp.Enabled = $false
$form.Controls.Add($buttonLoadDhcp)

$buttonSelectAllServers = New-Object System.Windows.Forms.Button
$buttonSelectAllServers.Location = New-UiPoint -X 820 -Y ([int]($top - 4))
$buttonSelectAllServers.Size = New-UiSize -Width 80 -Height 28
$buttonSelectAllServers.Text = 'All/None'
$buttonSelectAllServers.Enabled = $false
$form.Controls.Add($buttonSelectAllServers)

$top += $rowHeight

$labelServerSelection = New-Object System.Windows.Forms.Label
$labelServerSelection.Location = New-UiPoint -X $left -Y $top
$labelServerSelection.Size = New-UiSize -Width 145 -Height 24
$labelServerSelection.Text = 'Target servers:'
$form.Controls.Add($labelServerSelection)

$checkedListServers = New-Object System.Windows.Forms.CheckedListBox
$checkedListServers.Location = New-UiPoint -X $inputLeft -Y $top
$checkedListServers.Size = New-UiSize -Width 715 -Height 124
$checkedListServers.CheckOnClick = $true
$checkedListServers.HorizontalScrollbar = $true
$checkedListServers.Enabled = $false
$form.Controls.Add($checkedListServers)

$top += 132

$labelReports = New-Object System.Windows.Forms.Label
$labelReports.Location = New-UiPoint -X $left -Y $top
$labelReports.Size = New-UiSize -Width 145 -Height 24
$labelReports.Text = 'Reports:'
$form.Controls.Add($labelReports)

$checkBoxCsv = New-Object System.Windows.Forms.CheckBox
$checkBoxCsv.Location = New-UiPoint -X $inputLeft -Y $top
$checkBoxCsv.Size = New-UiSize -Width 85 -Height 24
$checkBoxCsv.Text = 'CSV'
$checkBoxCsv.Checked = $true
$form.Controls.Add($checkBoxCsv)

$checkBoxHtml = New-Object System.Windows.Forms.CheckBox
$checkBoxHtml.Location = New-UiPoint -X 285 -Y $top
$checkBoxHtml.Size = New-UiSize -Width 145 -Height 24
$checkBoxHtml.Text = 'Printable HTML'
$checkBoxHtml.Checked = $true
$form.Controls.Add($checkBoxHtml)

$checkBoxExecutionLog = New-Object System.Windows.Forms.CheckBox
$checkBoxExecutionLog.Location = New-UiPoint -X 450 -Y $top
$checkBoxExecutionLog.Size = New-UiSize -Width 140 -Height 24
$checkBoxExecutionLog.Text = 'Execution log'
$checkBoxExecutionLog.Checked = $true
$form.Controls.Add($checkBoxExecutionLog)

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

$buttonY = 780
$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Location = New-UiPoint -X 535 -Y $buttonY
$buttonStartAnalysis.Size = New-UiSize -Width 120 -Height 34
$buttonStartAnalysis.Text = 'Start Analysis'

$buttonLoadDhcp.Add_Click({
    Invoke-GuiSafe -Context 'Load Authorized DHCP Servers' -ScriptBlock {
        try {
            Set-Status -Text 'Discovering all AD-authorized DHCP servers in the forest...'
            Update-ProgressSafe -Value 20
            $script:SelectedServer = @()
            $script:GuiServerInventory = @(Get-ForestServerInventory -RequestedForest $textBoxForest.Text)
            $script:GuiServerByDisplay = @{}
            $checkedListServers.Items.Clear()
            foreach ($serverItem in @($script:GuiServerInventory)) {
                $display = '{0} | {1} | {2}' -f $serverItem.ComputerName,$serverItem.IPv4Address,$serverItem.DiscoverySource
                $script:GuiServerByDisplay[$display] = $serverItem
                [void]$checkedListServers.Items.Add($display,$false)
            }
            Set-Status -Text ("Discovered {0} authorized DHCP server(s). Select the required targets." -f @($script:GuiServerInventory).Count)
        }
        finally { Update-ProgressSafe -Value 0 }
    }
})

$buttonSelectAllServers.Add_Click({
    $select = ($checkedListServers.CheckedItems.Count -lt $checkedListServers.Items.Count)
    for ($serverIndex=0; $serverIndex -lt $checkedListServers.Items.Count; $serverIndex++) { $checkedListServers.SetItemChecked($serverIndex,$select) }
    Set-Status -Text ("Selected {0} of {1} discovered server(s)." -f $checkedListServers.CheckedItems.Count,$checkedListServers.Items.Count)
})

$buttonStartAnalysis.Add_Click({
    Invoke-GuiSafe -Context 'Start Analysis' -ScriptBlock {
        $script:LogDir = $textBoxLogDir.Text
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        Ensure-Directory -Path $script:LogDir

        if ($checkBoxDateRange.Checked -and $dateFrom.Value -gt $dateTo.Value) {
            Show-MessageBox -Message 'The From date/time must be earlier than or equal to the To date/time.' -Title 'Invalid Date Range' -Icon Warning
            return
        }

        if (-not $checkBoxForestMode.Checked -and -not $checkBoxLiveLog.Checked -and [string]::IsNullOrWhiteSpace($textBoxEvtxFolder.Text)) {
            Show-MessageBox -Message 'Please select an EVTX folder or enable live mode.' -Title 'Input Required' -Icon Warning
            return
        }
        $selectedReports = @()
        if ($checkBoxCsv.Checked) { $selectedReports += 'CSV' }
        if ($checkBoxHtml.Checked) { $selectedReports += 'HTML' }
        if ($checkBoxExecutionLog.Checked) { $selectedReports += 'LOG' }
        if ($selectedReports.Count -eq 0) { Show-MessageBox -Message 'Select at least one report output.' -Title 'Output Required' -Icon Warning; return }

        if ($checkBoxForestMode.Checked) {
            $chosenServers = @($checkedListServers.CheckedItems | ForEach-Object { $script:GuiServerByDisplay[[string]$_].ComputerName })
            if (@($chosenServers).Count -eq 0) { Show-MessageBox -Message 'Load the authorized DHCP servers and select at least one target server.' -Title 'Server Selection Required' -Icon Warning; return }
            $script:SelectedServer = @($chosenServers)
            $selectedRoles = @()
            if ($checkBoxDc.Checked) { $selectedRoles += 'DomainController' }
            if ($checkBoxFile.Checked) { $selectedRoles += 'FileServer' }
            if ($checkBoxPrint.Checked) { $selectedRoles += 'PrintServer' }
            if ($selectedRoles.Count -eq 0) { Show-MessageBox -Message 'Select at least one forest server role.' -Title 'Role Required' -Icon Warning; return }
            $result = Start-ForestPrintAudit307 -RequestedForest $textBoxForest.Text -DestinationFolder $textBoxOutputDir.Text -SelectedRoles $selectedRoles -SelectedReports $selectedReports -FromTime $dateFrom.Value -ToTime $dateTo.Value -Throttle $ThrottleLimit -TimeoutSeconds $OperationTimeoutSeconds
            Show-MessageBox -Message ("Forest audit completed.`r`nServers covered: {0}`r`nEvents: {1}`r`nOutput: {2}" -f $result.CoveredServers,$result.Events,$result.OutputFolder) -Title 'Forest Print Audit Completed'
        }
        else {
            Start-PrintAudit307 -LogFolderPath $textBoxEvtxFolder.Text -OutputFolder $textBoxOutputDir.Text -UseLiveLog $checkBoxLiveLog.Checked -IncludeSubfolders $checkBoxIncludeSubfolders.Checked -DateRangeEnabled:$checkBoxDateRange.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value -SelectedReports $selectedReports
        }
    }
})
$form.Controls.Add($buttonStartAnalysis)

$buttonOpenOutput = New-Object System.Windows.Forms.Button
$buttonOpenOutput.Location = New-UiPoint -X 665 -Y $buttonY
$buttonOpenOutput.Size = New-UiSize -Width 120 -Height 34
$buttonOpenOutput.Text = 'Open Output'
$buttonOpenOutput.Add_Click({
    Invoke-GuiSafe -Context 'Open Output' -ScriptBlock {
        if ($script:LastHtmlPath -and (Test-Path -LiteralPath $script:LastHtmlPath -PathType Leaf)) {
            Start-Process -FilePath $script:LastHtmlPath
        }
        elseif ($script:LastCsvPath -and (Test-Path -LiteralPath $script:LastCsvPath -PathType Leaf)) {
            Start-Process -FilePath $script:LastCsvPath
        }
        elseif ($script:LastOutputFolder -and (Test-Path -LiteralPath $script:LastOutputFolder -PathType Container)) {
            Start-Process -FilePath $script:LastOutputFolder
        }
        else {
            Show-MessageBox -Message 'No generated report is available yet.' -Title 'Open Output' -Icon Information
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

# Bottom-docked action panel keeps all primary buttons visible when Windows
# constrains the form to the monitor working area or applies high-DPI scaling.
$actionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$actionPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$actionPanel.Height = 62
$actionPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$actionPanel.WrapContents = $false
$actionPanel.Padding = New-Object System.Windows.Forms.Padding(8,12,12,8)
$actionPanel.BackColor = $form.BackColor

$form.Controls.Remove($buttonStartAnalysis)
$form.Controls.Remove($buttonOpenOutput)
$form.Controls.Remove($buttonClose)
$buttonStartAnalysis.Margin = New-Object System.Windows.Forms.Padding(8,0,0,0)
$buttonOpenOutput.Margin = New-Object System.Windows.Forms.Padding(8,0,0,0)
$buttonClose.Margin = New-Object System.Windows.Forms.Padding(8,0,0,0)
[void]$actionPanel.Controls.Add($buttonClose)
[void]$actionPanel.Controls.Add($buttonOpenOutput)
[void]$actionPanel.Controls.Add($buttonStartAnalysis)
$form.Controls.Add($actionPanel)
$actionPanel.BringToFront()

$checkBoxLiveLog.Add_CheckedChanged({
    if ($checkBoxForestMode.Checked) { return }
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

$checkBoxForestMode.Add_CheckedChanged({
    $forestEnabled = $checkBoxForestMode.Checked
    $textBoxForest.Enabled = $forestEnabled
    $checkBoxDc.Enabled = $forestEnabled
    $checkBoxFile.Enabled = $forestEnabled
    $checkBoxPrint.Enabled = $forestEnabled
    $buttonLoadDhcp.Enabled = $forestEnabled
    $buttonSelectAllServers.Enabled = $forestEnabled
    $checkedListServers.Enabled = $forestEnabled
    $checkBoxLiveLog.Enabled = -not $forestEnabled
    $buttonResolveChannel.Enabled = -not $forestEnabled
    $textBoxEvtxFolder.Enabled = (-not $forestEnabled -and -not $checkBoxLiveLog.Checked)
    $buttonBrowseEvtx.Enabled = $textBoxEvtxFolder.Enabled
    $checkBoxIncludeSubfolders.Enabled = $textBoxEvtxFolder.Enabled
    if ($forestEnabled) { Set-Status -Text 'Ready. Forest mode discovers roles, exports remote EVTX snapshots, and parses them locally with Log Parser.' }
    else { Set-Status -Text 'Ready. Select local live or archived EVTX mode.' }
})

$script:Form = $form
$script:ProgressBar = $progressBar
$script:StatusLabel = $statusLabel

$form.Add_Shown({
    # AutoScale runs before Shown. Clamp the real, post-DPI window dimensions
    # to the monitor working area so the action panel cannot sit under the taskbar.
    $workingArea = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $horizontalMargin = 20
    $verticalMargin = 20
    $maximumWidth = [Math]::Max(800, ($workingArea.Width - $horizontalMargin))
    $maximumHeight = [Math]::Max(650, ($workingArea.Height - $verticalMargin))

    if ($form.Width -gt $maximumWidth) { $form.Width = $maximumWidth }
    if ($form.Height -gt $maximumHeight) { $form.Height = $maximumHeight }

    $form.Left = $workingArea.Left + [Math]::Max(0, [int](($workingArea.Width - $form.Width) / 2))
    $form.Top = $workingArea.Top + [Math]::Max(0, [int](($workingArea.Height - $form.Height) / 2))
    $form.PerformLayout()
    $actionPanel.BringToFront()
    $form.Activate()
})
[void]$form.ShowDialog()

Write-Log -Message 'Script ended.'

# End of script
