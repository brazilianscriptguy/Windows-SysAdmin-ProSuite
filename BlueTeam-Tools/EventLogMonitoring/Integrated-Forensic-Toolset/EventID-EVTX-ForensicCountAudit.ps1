<#
.SYNOPSIS
  EventID-based EVTX Forensic Count Audit.

.DESCRIPTION
  Enterprise and DFIR-grade EVTX counting and forensic audit tool aligned with the
  registered baseline model EventID-5136-5137-5141-ADObjectChangeAudit.ps1
  and the Authentication Timeline Audit pattern.

  Implements:
  - PATH-AGNOSTIC archived EVTX processing
  - live channel resolution using wevtutil
  - manual Resolve Channel GUI button
  - SQL-FIRST LogParser counting pipeline
  - Get-WinEvent fallback for parser continuity
  - GUI runtime logging
  - structured log generation in C:\Logs-TEMP
  - stable script-name-based log naming

.AUTHOR
  Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
  2026-05-08-v1.0.1-PRODUCTION-SQLFIRST-RESOLVECHANNEL-GUILOG-ALIGNMENT
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()


function Hide-PowerShellConsoleWindow {
    try {
        Add-Type -Name NativeConsoleMethods -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue
        $consoleHandle = [Win32.NativeConsoleMethods]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [void][Win32.NativeConsoleMethods]::ShowWindow($consoleHandle, 0)
        }
    } catch { }
}

if (-not $ShowConsole) {
    Hide-PowerShellConsoleWindow
}

$script:Version = '2026-05-08-v1.0.1-PRODUCTION-SQLFIRST-RESOLVECHANNEL-GUILOG-ALIGNMENT'
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($script:ScriptName)) { $script:ScriptName = 'EventID-EVTX-InventoryAudit' }
$script:MachineName = [Environment]::MachineName
$script:ToolName = $script:ScriptName
$script:ToolTitle = 'EVTX Inventory Audit'
$script:ToolVersion = $script:Version
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultLogDir = $script:LogDir
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:DefaultOutDir = $script:DefaultOutputDir
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LastCsvPath = $null
$script:LastReport = ''
$script:LastOutputDir = $script:DefaultOutputDir
$script:Form = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:RuntimeLogTextBox = $null
$script:LiveChannelName = 'Security'
$script:ResolvedLiveChannelPath = $null
$script:EventIds = @()
$script:LiveChannels = @('Security','System','Application','Microsoft-Windows-PrintService/Operational')
$script:EventCategory = @{}
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

Ensure-Directory -Path $script:DefaultLogDir

function Write-GuiLog {
    param(
        [Parameter(Mandatory=$true)][string]$Line
    )
    try {
        if ($null -eq $script:RuntimeLogTextBox -or $script:RuntimeLogTextBox.IsDisposed) { return }
        $append = {
            param([string]$Text)
            $script:RuntimeLogTextBox.AppendText($Text + [Environment]::NewLine)
            $script:RuntimeLogTextBox.SelectionStart = $script:RuntimeLogTextBox.TextLength
            $script:RuntimeLogTextBox.ScrollToCaret()
        }
        if ($script:RuntimeLogTextBox.InvokeRequired) {
            [void]$script:RuntimeLogTextBox.Invoke($append, @($Line))
        } else {
            & $append $Line
        }
    } catch { }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch { }
    Write-GuiLog -Line $line
}

function Show-InfoBox { param([string]$Message) [System.Windows.Forms.MessageBox]::Show($Message, 'Information', 'OK', 'Information') | Out-Null }
function Show-ErrorBox { param([string]$Message) [System.Windows.Forms.MessageBox]::Show($Message, 'Error', 'OK', 'Error') | Out-Null }
function Get-Timestamp { return (Get-Date -Format 'yyyyMMdd_HHmmss') }


function Resolve-LogParserPath {
    foreach ($candidate in @($script:LogParserExeCandidates)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Log "Resolved LogParser.exe path: '$candidate'"
            return [string]$candidate
        }
    }
    throw 'LogParser.exe was not found. Install Microsoft Log Parser 2.2 or update $script:LogParserExeCandidates.'
}

function Resolve-WindowsEventChannelPath {
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName
    )
    if ([string]::IsNullOrWhiteSpace($ChannelName)) { throw 'Channel name is empty.' }
    try {
        $output = @(wevtutil.exe gl $ChannelName 2>&1)
        foreach ($line in $output) {
            $text = [string]$line
            if ($text -match '^\s*logFileName:\s*(.+?)\s*$') {
                $candidate = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim())
                if (-not [System.IO.Path]::IsPathRooted($candidate)) {
                    $candidate = Join-Path $env:SystemRoot $candidate
                }
                $script:ResolvedLiveChannelPath = [string]$candidate
                Write-Log "Resolved channel '$ChannelName' live EVTX path candidate: $candidate"
                return [string]$candidate
            }
        }
        throw "wevtutil did not return logFileName for channel '$ChannelName'."
    } catch {
        Write-Log "wevtutil channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
        throw
    }
}

function Resolve-LiveChannelPath {
    param(
        [string]$ChannelName = $script:LiveChannelName
    )
    $resolved = Resolve-WindowsEventChannelPath -ChannelName $ChannelName
    $script:LiveChannelName = $ChannelName
    $script:ResolvedLiveChannelPath = $resolved
    return [string]$resolved
}

function New-LogParserInventorySql {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$OutputCsvPath
    )
@"
SELECT
    EventID,
    COUNT(*) AS EventCount
INTO '$OutputCsvPath'
FROM '$EvtxPath'
GROUP BY EventID
"@
}

function Invoke-LogParserInventoryQuery {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$TempDir
    )
    if (-not (Test-Path -LiteralPath $EvtxPath -PathType Leaf)) { throw "EVTX path not found: $EvtxPath" }
    Ensure-Directory -Path $TempDir
    $logParser = Resolve-LogParserPath
    $stamp = Get-Timestamp
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($EvtxPath) -replace '[^\w\-]+','_')
    $queryPath = Join-Path $TempDir ("Inventory-{0}-{1}.sql" -f $safeName,$stamp)
    $outPath = Join-Path $TempDir ("LogParser-Inventory-{0}-{1}.csv" -f $safeName,$stamp)
    $stdoutPath = Join-Path $TempDir ("LogParser-Inventory-{0}-{1}.stdout" -f $safeName,$stamp)
    $stderrPath = Join-Path $TempDir ("LogParser-Inventory-{0}-{1}.stderr" -f $safeName,$stamp)
    $auditSqlDir = Join-Path $script:LogDir 'SQL'
    Ensure-Directory -Path $auditSqlDir
    $auditQueryPath = Join-Path $auditSqlDir ([IO.Path]::GetFileName($queryPath))
    $sql = New-LogParserInventorySql -EvtxPath $EvtxPath -OutputCsvPath $outPath
    Set-Content -LiteralPath $queryPath -Value $sql -Encoding ASCII
    Set-Content -LiteralPath $auditQueryPath -Value $sql -Encoding ASCII
    $args = @(
        ('file:"{0}"' -f $queryPath),
        '-i:EVT',
        '-o:CSV',
        '-headers:ON',
        '-stats:OFF'
    )
    Write-Log "Executing LogParser inventory SQL. Query='$queryPath'; AuditedQuery='$auditQueryPath'; ExpectedOutput='$outPath'"
    $p = Start-Process -FilePath $logParser -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if ($p.ExitCode -ne 0) {
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "LogParser inventory failed. ExitCode=$($p.ExitCode). Query=$queryPath. STDOUT=$stdout STDERR=$stderr"
    }
    if (-not (Test-Path -LiteralPath $outPath -PathType Leaf)) { throw "LogParser inventory output was not generated: $outPath" }
    return [string]$outPath
}

function ConvertTo-CanonicalString {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [System.Array]) {
        return ((@($Value) | ForEach-Object { ConvertTo-CanonicalString -Value $_ }) -join '; ')
    }
    if ($Value -is [System.Xml.XmlNode]) { return [string]$Value.InnerText }
    if ($Value.PSObject -and $Value.PSObject.Properties['InnerText']) { return [string]$Value.InnerText }
    return [string]$Value
}

function Get-EventDataMap {
    param([Parameter(Mandatory=$true)][xml]$XmlEvent)
    $map = @{}
    try {
        $nodes = @($XmlEvent.Event.EventData.Data)
        foreach ($node in $nodes) {
            $name = ConvertTo-CanonicalString -Value $node.Name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = 'Data' }
            $value = ConvertTo-CanonicalString -Value $node.'#text'
            if ([string]::IsNullOrWhiteSpace($value)) { $value = ConvertTo-CanonicalString -Value $node.InnerText }
            if ($map.ContainsKey($name)) { $map[$name] = (($map[$name], $value) -join '; ') }
            else { $map[$name] = $value }
        }
    } catch { }
    return $map
}

function Get-MapValue {
    param([hashtable]$Map, [string[]]$Names)
    foreach ($name in $Names) {
        if ($Map.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$name])) { return [string]$Map[$name] }
    }
    return ''
}

function Convert-MapToRawEventData {
    param([hashtable]$Map)
    if ($null -eq $Map -or $Map.Count -eq 0) { return '' }
    return ((@($Map.Keys) | Sort-Object | ForEach-Object { '{0}={1}' -f $_, (ConvertTo-CanonicalString -Value $Map[$_]) }) -join ' | ')
}

function Get-Sha256String {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function New-ForensicEvidenceRecord {
    param(
        [Parameter(Mandatory=$true)]$Event,
        [Parameter(Mandatory=$true)][string]$SourceFile,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [Parameter(Mandatory=$true)][string]$SourceChannel
    )
    $xml = [xml]$Event.ToXml()
    $map = Get-EventDataMap -XmlEvent $xml
    $eventId = [int]$Event.Id
    $recordId = [int64]$Event.RecordId
    $computer = ConvertTo-CanonicalString -Value $Event.MachineName
    if ([string]::IsNullOrWhiteSpace($computer)) { $computer = ConvertTo-CanonicalString -Value $xml.Event.System.Computer }
    $category = if ($script:EventCategory.ContainsKey($eventId)) { [string]$script:EventCategory[$eventId] } else { 'Discovered Event ID' }
    $actorUser = Get-MapValue -Map $map -Names @('SubjectUserName','AccountName','UserName','Param1')
    $actorDomain = Get-MapValue -Map $map -Names @('SubjectDomainName','AccountDomain','DomainName')
    $targetUser = Get-MapValue -Map $map -Names @('TargetUserName','TargetAccount','MemberName','ServiceName','ObjectName','TaskName')
    $targetDomain = Get-MapValue -Map $map -Names @('TargetDomainName','TargetAccountDomain','MemberDomain')
    $groupName = Get-MapValue -Map $map -Names @('TargetUserName','GroupName','TargetSid')
    $logonId = Get-MapValue -Map $map -Names @('SubjectLogonId','TargetLogonId','LogonId')
    $ipAddress = Get-MapValue -Map $map -Names @('IpAddress','ClientAddress','WorkstationName')
    $raw = Convert-MapToRawEventData -Map $map
    $evidenceId = '{0}-{1}-{2}-{3}' -f $computer, $eventId, $recordId, (Get-Sha256String -Text $SourceFile).Substring(0,8)
    $hashInput = '{0}|{1}|{2}|{3}|{4}|{5}' -f $evidenceId, $SourceFile, $eventId, $recordId, $Event.TimeCreated.ToString('o'), $raw
    [PSCustomObject][ordered]@{
        EvidenceId      = [string]$evidenceId
        IntegrityHash   = [string](Get-Sha256String -Text $hashInput)
        ToolName        = [string]$script:ToolName
        ToolVersion     = [string]$script:ToolVersion
        SourceMode      = [string]$SourceMode
        SourceChannel   = [string]$SourceChannel
        SourceFile      = [string]$SourceFile
        ComputerName    = [string]$computer
        EventId         = [int]$eventId
        EventCategory   = [string]$category
        RecordId        = [int64]$recordId
        TimeCreated     = [datetime]$Event.TimeCreated
        ProviderName    = [string]$Event.ProviderName
        ActorUser       = [string]$actorUser
        ActorDomain     = [string]$actorDomain
        TargetUser      = [string]$targetUser
        TargetDomain    = [string]$targetDomain
        GroupName       = [string]$groupName
        SubjectLogonId  = [string]$logonId
        IpAddress       = [string]$ipAddress
        RawEventData    = [string]$raw
        Message         = [string]((ConvertTo-CanonicalString -Value $Event.Message) -replace "`r?`n", ' ')
    }
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName,
        [Parameter(Mandatory=$true)][string]$OutputDir
    )
    Ensure-Directory -Path $OutputDir
    $resolvedPath = ''
    try { $resolvedPath = Resolve-LiveChannelPath -ChannelName $ChannelName } catch { $resolvedPath = '' }
    $safeName = ($ChannelName -replace '[\/:*?"<>|]', '_')
    $snapshot = Join-Path $OutputDir ('{0}-{1}-{2}.evtx' -f $safeName, (Get-Timestamp), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $errPath = Join-Path $OutputDir ('wevtutil-{0}-{1}.err' -f $safeName, (Get-Timestamp))
    $args = @('epl', $ChannelName, $snapshot, '/ow:true')
    $p = Start-Process -FilePath 'wevtutil.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errPath
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "Failed to export live channel snapshot. Channel='$ChannelName'; ResolvedLivePath='$resolvedPath'; ExitCode=$($p.ExitCode). $err"
    }
    Write-Log "Live channel snapshot exported. Channel='$ChannelName'; ResolvedLivePath='$resolvedPath'; Snapshot='$snapshot'"
    return [string]$snapshot
}

function Test-ReadableEvtxPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $fs.Dispose()
        return $true
    } catch {
        Write-Log "EVTX file is not readable and will be skipped: '$Path'. Error: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Get-PathAgnosticArchiveEvtxPaths {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [bool]$IncludeSubfolders
    )
    if ([string]::IsNullOrWhiteSpace($RootPath)) { throw 'Archive EVTX folder is empty.' }
    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) { throw "Archive EVTX folder not found: $RootPath" }
    Write-Log "Enumerating archived EVTX files. RootPath='$RootPath'; IncludeSubfolders=$IncludeSubfolders"
    $gciParams = @{ LiteralPath = $RootPath; Filter = '*.evtx'; File = $true; ErrorAction = 'Stop' }
    if ($IncludeSubfolders) { $gciParams.Recurse = $true }
    $enumerated = @(Get-ChildItem @gciParams)
    $selected = New-Object System.Collections.ArrayList
    foreach ($file in $enumerated) {
        $fullPath = [string]$file.FullName
        if (Test-ReadableEvtxPath -Path $fullPath) { [void]$selected.Add($fullPath) }
    }
    Write-Log ("Archive-safe EVTX selection completed. Enumerated={0}; Selected={1}" -f @($enumerated).Count, $selected.Count)
    return @($selected | ForEach-Object { [string]$_ })
}

function Get-SourceEvtxPaths {
    param(
        [bool]$UseLiveLog,
        [string]$ArchiveFolder,
        [bool]$IncludeSubfolders,
        [string]$TempDir,
        [string]$LiveChannelName = $script:LiveChannelName
    )
    $paths = New-Object System.Collections.ArrayList
    if ($UseLiveLog) {
        $channel = if ([string]::IsNullOrWhiteSpace($LiveChannelName)) { $script:LiveChannelName } else { $LiveChannelName }
        try { [void]$paths.Add((Export-LiveChannelSnapshot -ChannelName $channel -OutputDir $TempDir)) }
        catch { Write-Log "Live channel snapshot skipped. Channel='$channel'. Error: $($_.Exception.Message)" 'WARN' }
    } else {
        foreach ($path in @(Get-PathAgnosticArchiveEvtxPaths -RootPath $ArchiveFolder -IncludeSubfolders $IncludeSubfolders)) {
            [void]$paths.Add([string]$path)
        }
    }
    return @($paths | ForEach-Object { [string]$_ })
}

function Read-EvtxEvidenceRecords {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [bool]$UseDateRange,
        [string]$UserFilter
    )
    if ([string]::IsNullOrWhiteSpace($EvtxPath)) { throw 'EVTX path is empty.' }
    Write-Log "Processing EVTX source: '$EvtxPath'"
    $filter = @{ Path = $EvtxPath }
    if (@($script:EventIds).Count -gt 0) { $filter.Id = [int[]]$script:EventIds }
    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) }
    catch {
        if ($_.Exception.Message -match 'No events|não foi encontrado|No events were found') {
            Write-Log "No matching events found in '$EvtxPath'." 'INFO'
            return @()
        }
        throw
    }
    $records = New-Object System.Collections.ArrayList
    $sourceChannel = ''
    foreach ($event in $events) {
        try {
            if ($UseDateRange) {
                if ($event.TimeCreated -lt $StartTime -or $event.TimeCreated -gt $EndTime) { continue }
            }
            $record = New-ForensicEvidenceRecord -Event $event -SourceFile $EvtxPath -SourceMode $SourceMode -SourceChannel $sourceChannel
            if (-not [string]::IsNullOrWhiteSpace($UserFilter)) {
                $terms = @($UserFilter -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($terms.Count -gt 0 -and $terms[0] -ne '*') {
                    $haystack = ('{0} {1} {2} {3} {4} {5}' -f $record.ActorUser,$record.ActorDomain,$record.TargetUser,$record.TargetDomain,$record.GroupName,$record.RawEventData)
                    $matched = $false
                    foreach ($term in $terms) { if ($haystack -like ('*' + $term + '*')) { $matched = $true; break } }
                    if (-not $matched) { continue }
                }
            }
            [void]$records.Add($record)
        } catch {
            Write-Log "Skipped event during forensic normalization. Source='$EvtxPath'; Error=$($_.Exception.Message)" 'WARN'
        }
    }
    Write-Log ("EVTX processing completed. Source='{0}'; Records={1}" -f $EvtxPath, $records.Count)
    return @($records)
}

function Invoke-ForensicAudit {
    param(
        [bool]$UseLiveLog,
        [string]$LiveChannelName,
        [string]$ArchiveFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$UserFilter
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $script:DefaultLogDir = $LogDir
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
    $script:LastOutputDir = $OutputDir
    $mode = if ($UseLiveLog) { 'LiveSnapshot' } else { 'Archive' }
    Write-Log "Starting forensic audit. Mode=$mode; ArchiveFolder='$ArchiveFolder'; IncludeSubfolders=$IncludeSubfolders; OutputDir='$OutputDir'; UseDateRange=$UseDateRange; StartTime=$StartTime; EndTime=$EndTime; UserFilter='$UserFilter'"
    $tempDir = Join-Path $env:TEMP ($script:ToolName + '-Snapshots')
    Ensure-Directory -Path $tempDir
    $sources = @(Get-SourceEvtxPaths -UseLiveLog $UseLiveLog -ArchiveFolder $ArchiveFolder -IncludeSubfolders $IncludeSubfolders -TempDir $tempDir -LiveChannelName $LiveChannelName)
    if ($sources.Count -eq 0) { Write-Log 'No EVTX sources selected for processing.' 'WARN' }
    $allRecords = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        foreach ($record in @(Read-EvtxEvidenceRecords -EvtxPath ([string]$source) -SourceMode $mode -StartTime $StartTime -EndTime $EndTime -UseDateRange $UseDateRange -UserFilter $UserFilter)) {
            [void]$allRecords.Add($record)
        }
    }
    $csvPath = Join-Path $OutputDir ('{0}-{1}.csv' -f $script:ToolName, (Get-Timestamp))
    @($allRecords) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $script:LastReport = $csvPath
    Write-Log ("Forensic audit completed. Records={0}; Csv='{1}'" -f $allRecords.Count, $csvPath)
    return $csvPath
}

function Invoke-EvtxInventoryAudit {
    param(
        [bool]$UseLiveLog,
        [string]$LiveChannelName,
        [string]$ArchiveFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $script:DefaultLogDir = $LogDir
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
    $tempDir = Join-Path $env:TEMP ($script:ToolName + '-Snapshots')
    Ensure-Directory -Path $tempDir
    $mode = if ($UseLiveLog) { 'LiveSnapshot' } else { 'Archive' }
    $sources = @(Get-SourceEvtxPaths -UseLiveLog $UseLiveLog -ArchiveFolder $ArchiveFolder -IncludeSubfolders $IncludeSubfolders -TempDir $tempDir -LiveChannelName $LiveChannelName)
    $rows = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        Write-Log "Inventory processing EVTX source: '$source'"
        $sqlSucceeded = $false
        try {
            $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')
            $sqlCsv = Invoke-LogParserInventoryQuery -EvtxPath ([string]$source) -TempDir $sqlTempDir
            $sqlRows = @(Import-Csv -LiteralPath $sqlCsv)
            foreach ($r in $sqlRows) {
                $eventIdValue = if ($r.PSObject.Properties['EventID']) { $r.EventID } else { $r.EventId }
                $countValue = if ($r.PSObject.Properties['EventCount']) { $r.EventCount } elseif ($r.PSObject.Properties['Count']) { $r.Count } else { 0 }
                if ([string]::IsNullOrWhiteSpace([string]$eventIdValue)) { continue }
                [void]$rows.Add([PSCustomObject][ordered]@{
                    SourceMode = $mode
                    SourceFile = [string]$source
                    EventId    = [int]$eventIdValue
                    Count      = [int]$countValue
                    ParserEngine = 'LogParser'
                })
            }
            Write-Log "LogParser inventory completed for '$source'. Rows=$($sqlRows.Count)."
            $sqlSucceeded = $true
        } catch {
            Write-Log "SQL-first LogParser inventory failed for '$source'. Falling back to Get-WinEvent. Error: $($_.Exception.Message)" 'WARN'
        }
        if (-not $sqlSucceeded) {
            try {
                $events = @(Get-WinEvent -Path ([string]$source) -ErrorAction Stop)
                $groups = @($events | Group-Object -Property Id | Sort-Object { [int]$_.Name })
                foreach ($g in $groups) {
                    [void]$rows.Add([PSCustomObject][ordered]@{
                        SourceMode = $mode
                        SourceFile = [string]$source
                        EventId    = [int]$g.Name
                        Count      = [int]$g.Count
                        ParserEngine = 'Get-WinEvent'
                    })
                }
            } catch {
                Write-Log "Inventory skipped EVTX source: '$source'. Error: $($_.Exception.Message)" 'WARN'
            }
        }
    }
    $csvPath = Join-Path $OutputDir ('{0}-{1}.csv' -f $script:ToolName, (Get-Timestamp))
    @($rows) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $script:LastReport = $csvPath
    Write-Log ("EVTX inventory completed. Rows={0}; Csv='{1}'" -f $rows.Count, $csvPath)
    return $csvPath
}

function Open-LastReport {
    if (-not [string]::IsNullOrWhiteSpace($script:LastReport) -and (Test-Path -LiteralPath $script:LastReport)) {
        Start-Process -FilePath $script:LastReport | Out-Null
    }
}

Write-Log "========== START: $($script:ToolTitle) =========="
Write-Log "Script version: $($script:ToolVersion)"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Log "Execution user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Computer name: $env:COMPUTERNAME"
Write-Log "Log path: $($script:LogPath)"

$form = New-Object System.Windows.Forms.Form
$script:Form = $form
$form.Text = $script:ToolTitle
$form.Size = New-Object System.Drawing.Size(900,560)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font('Segoe UI',9)
$form.Font = $font

function Add-Label { param([string]$Text,[int]$X,[int]$Y,[int]$W=130) $l=New-Object System.Windows.Forms.Label; $l.Text=$Text; $l.Location=New-Object System.Drawing.Point($X,$Y); $l.Size=New-Object System.Drawing.Size($W,22); $form.Controls.Add($l); return $l }

$chkLive = New-Object System.Windows.Forms.CheckBox
$chkLive.Text = 'Live Log Mode'
$chkLive.Checked = $true
$chkLive.Location = New-Object System.Drawing.Point(20,20)
$chkLive.Size = New-Object System.Drawing.Size(160,24)
$form.Controls.Add($chkLive)

Add-Label 'Live Channel:' 190 22 85 | Out-Null
$cmbLiveChannel = New-Object System.Windows.Forms.ComboBox
$cmbLiveChannel.DropDownStyle = 'DropDownList'
[void]$cmbLiveChannel.Items.AddRange([object[]]$script:LiveChannels)
$cmbLiveChannel.SelectedItem = $script:LiveChannelName
$cmbLiveChannel.Location = New-Object System.Drawing.Point(275,18)
$cmbLiveChannel.Size = New-Object System.Drawing.Size(260,24)
$form.Controls.Add($cmbLiveChannel)

$btnResolveChannel = New-Object System.Windows.Forms.Button
$btnResolveChannel.Text = 'Resolve Channel'
$btnResolveChannel.Location = New-Object System.Drawing.Point(545,16)
$btnResolveChannel.Size = New-Object System.Drawing.Size(120,28)
$form.Controls.Add($btnResolveChannel)

$txtResolvedChannel = New-Object System.Windows.Forms.TextBox
$txtResolvedChannel.ReadOnly = $true
$txtResolvedChannel.Location = New-Object System.Drawing.Point(675,18)
$txtResolvedChannel.Size = New-Object System.Drawing.Size(175,24)
$form.Controls.Add($txtResolvedChannel)

Add-Label 'Archive EVTX Folder:' 20 60 150 | Out-Null
$txtArchive = New-Object System.Windows.Forms.TextBox
$txtArchive.Text = $script:DefaultOutDir
$txtArchive.Location = New-Object System.Drawing.Point(170,58)
$txtArchive.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtArchive)
$btnBrowseArchive = New-Object System.Windows.Forms.Button
$btnBrowseArchive.Text = 'Browse'
$btnBrowseArchive.Location = New-Object System.Drawing.Point(740,56)
$btnBrowseArchive.Size = New-Object System.Drawing.Size(110,28)
$form.Controls.Add($btnBrowseArchive)

$chkSub = New-Object System.Windows.Forms.CheckBox
$chkSub.Text = 'Include subfolders'
$chkSub.Checked = $true
$chkSub.Location = New-Object System.Drawing.Point(170,88)
$chkSub.Size = New-Object System.Drawing.Size(180,24)
$form.Controls.Add($chkSub)

Add-Label 'Output Folder:' 20 125 150 | Out-Null
$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Text = $script:DefaultOutDir
$txtOut.Location = New-Object System.Drawing.Point(170,123)
$txtOut.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtOut)
$btnBrowseOut = New-Object System.Windows.Forms.Button
$btnBrowseOut.Text = 'Browse'
$btnBrowseOut.Location = New-Object System.Drawing.Point(740,121)
$btnBrowseOut.Size = New-Object System.Drawing.Size(110,28)
$form.Controls.Add($btnBrowseOut)

Add-Label 'Log Folder:' 20 160 150 | Out-Null
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Text = $script:DefaultLogDir
$txtLog.Location = New-Object System.Drawing.Point(170,158)
$txtLog.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtLog)

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Text = 'Use date range'
$chkDate.Location = New-Object System.Drawing.Point(20,200)
$chkDate.Size = New-Object System.Drawing.Size(140,24)
$form.Controls.Add($chkDate)
$dtFrom = New-Object System.Windows.Forms.DateTimePicker
$dtFrom.Format = 'Custom'
$dtFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtFrom.Value = (Get-Date).AddDays(-7)
$dtFrom.Location = New-Object System.Drawing.Point(170,198)
$dtFrom.Size = New-Object System.Drawing.Size(180,24)
$form.Controls.Add($dtFrom)
$dtTo = New-Object System.Windows.Forms.DateTimePicker
$dtTo.Format = 'Custom'
$dtTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtTo.Value = Get-Date
$dtTo.Location = New-Object System.Drawing.Point(370,198)
$dtTo.Size = New-Object System.Drawing.Size(180,24)
$form.Controls.Add($dtTo)

Add-Label 'User/Text Filter:' 20 240 150 | Out-Null
$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Text = ''
$txtFilter.Location = New-Object System.Drawing.Point(170,238)
$txtFilter.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtFilter)

$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Multiline = $true
$txtStatus.ScrollBars = 'Vertical'
$txtStatus.ReadOnly = $true
$txtStatus.Location = New-Object System.Drawing.Point(20,285)
$txtStatus.Size = New-Object System.Drawing.Size(830,145)
$form.Controls.Add($txtStatus)
$script:RuntimeLogTextBox = $txtStatus

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point(20,438)
$lblStatus.Size = New-Object System.Drawing.Size(500,22)
$form.Controls.Add($lblStatus)
$script:StatusLabel = $lblStatus

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20,465)
$progress.Size = New-Object System.Drawing.Size(480,18)
$progress.Style = 'Continuous'
$form.Controls.Add($progress)
$script:ProgressBar = $progress

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Analysis'
$btnStart.Location = New-Object System.Drawing.Point(520,455)
$btnStart.Size = New-Object System.Drawing.Size(130,34)
$form.Controls.Add($btnStart)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open Last CSV'
$btnOpen.Location = New-Object System.Drawing.Point(660,455)
$btnOpen.Size = New-Object System.Drawing.Size(120,34)
$form.Controls.Add($btnOpen)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(790,455)
$btnClose.Size = New-Object System.Drawing.Size(60,34)
$form.Controls.Add($btnClose)

function Add-UiLog { param([string]$Message) Write-Log -Message $Message -Level 'INFO' }
function Set-Busy {
    param([bool]$Busy)
    $btnStart.Enabled = -not $Busy
    $btnClose.Enabled = -not $Busy
    $btnResolveChannel.Enabled = -not $Busy
    $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' }
    if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = if ($Busy) { 'Processing...' } else { 'Ready.' } }
    if ($null -ne $script:ProgressBar) { $script:ProgressBar.Style = if ($Busy) { 'Marquee' } else { 'Continuous' } }
}

$browseAction = {
    param([System.Windows.Forms.TextBox]$Target)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $Target.Text
    if ($dlg.ShowDialog() -eq 'OK') { $Target.Text = $dlg.SelectedPath }
}
$btnBrowseArchive.Add_Click({ & $browseAction $txtArchive }.GetNewClosure())
$btnBrowseOut.Add_Click({ & $browseAction $txtOut }.GetNewClosure())
$btnOpen.Add_Click({ Open-LastReport }.GetNewClosure())
$btnClose.Add_Click({ $form.Close() }.GetNewClosure())

$updateLiveArchiveState = {
    $archive = -not $chkLive.Checked
    $txtArchive.Enabled = $archive
    $btnBrowseArchive.Enabled = $archive
    $chkSub.Enabled = $archive
    $cmbLiveChannel.Enabled = $chkLive.Checked
    $btnResolveChannel.Enabled = $chkLive.Checked
    if ($chkLive.Checked) {
        Write-Log "Current GUI mode: Live Log Mode. Archive folder controls are disabled."
    } else {
        Write-Log "Mode changed to Archive Mode. ArchiveFolder='$($txtArchive.Text)'"
    }
}

$resolveSelectedChannel = {
    try {
        $selectedChannel = [string]$cmbLiveChannel.Text
        if ([string]::IsNullOrWhiteSpace($selectedChannel)) { $selectedChannel = $script:LiveChannelName }
        $resolved = Resolve-LiveChannelPath -ChannelName $selectedChannel
        $txtResolvedChannel.Text = $resolved
        Write-Log "Manual Resolve Channel completed. Channel='$selectedChannel'; ResolvedPath='$resolved'"
    } catch {
        $txtResolvedChannel.Text = ''
        $msg = "Resolve Channel failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Show-ErrorBox $msg
    }
}

$chkLive.Add_CheckedChanged({ & $updateLiveArchiveState }.GetNewClosure())
$cmbLiveChannel.Add_SelectedIndexChanged({ & $resolveSelectedChannel }.GetNewClosure())
$btnResolveChannel.Add_Click({ & $resolveSelectedChannel }.GetNewClosure())

$btnStart.Add_Click({
    try {
        Set-Busy -Busy $true
        Add-UiLog 'Analysis started.'
        Write-Log 'GUI execution started.'
        $isInventory = ($script:EventIds.Count -eq 0)
        if ($isInventory) {
            $result = Invoke-EvtxInventoryAudit -UseLiveLog ([bool]$chkLive.Checked) -LiveChannelName ([string]$cmbLiveChannel.Text) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim())
        } else {
            $result = Invoke-ForensicAudit -UseLiveLog ([bool]$chkLive.Checked) -LiveChannelName ([string]$cmbLiveChannel.Text) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim()) -UseDateRange ([bool]$chkDate.Checked) -StartTime ([datetime]$dtFrom.Value) -EndTime ([datetime]$dtTo.Value) -UserFilter ([string]$txtFilter.Text.Trim())
        }
        Add-UiLog "Analysis completed. CSV: $result"
        Show-InfoBox "Analysis completed.`n$result"
    } catch {
        $msg = "Analysis failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Add-UiLog $msg
        Show-ErrorBox $msg
    } finally {
        Write-Log 'GUI execution finished.'
        Set-Busy -Busy $false
    }
}.GetNewClosure())

$form.Add_Shown({
    Write-Log 'GUI loaded. Runtime textbox logging is active.'
    Write-Log "Script version: $($script:Version)"
    Write-Log "Default live channel name: $($script:LiveChannelName)"
    try { & $resolveSelectedChannel } catch { }
    & $updateLiveArchiveState
}.GetNewClosure())
$form.Add_FormClosed({ Write-Log "========== END: $($script:ToolTitle) ==========" }.GetNewClosure())
[void]$form.ShowDialog()
