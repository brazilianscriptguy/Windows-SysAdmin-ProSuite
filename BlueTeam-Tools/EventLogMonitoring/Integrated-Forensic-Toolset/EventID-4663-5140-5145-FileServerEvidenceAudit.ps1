<#
.SYNOPSIS
    EventID-4663-5140-5145-FileServerEvidenceAudit.ps1 - Enterprise and forensic-grade file server evidence audit tool.

.DESCRIPTION
    Unified Windows EVTX forensic audit tool for Windows file server access and object access events.

    This production version audits Windows Security events related to file access, SMB share access,
    and detailed file share access checks. It supports live Security log acquisition and offline archived
    EVTX analysis using a PATH-AGNOSTIC archive pipeline.

    The archive workflow accepts .evtx files from any evidence location, including local folders,
    external drives, mounted forensic images, network shares, and exported case repositories. Offline
    analysis is strictly separated from live acquisition and uses absolute string EVTX paths only.

    Core capabilities:
      - Live Security channel snapshot acquisition via wevtutil.exe.
      - Resolve Channel function to identify the current live Security.evtx path.
      - Archive normalization safe SourceChannel inference when offline EVTX LogName is empty.
      - PATH-AGNOSTIC archived EVTX processing.
      - Recursive offline EVTX folder enumeration.
      - String-only EVTX path pipeline for parser functions.
      - Fixed forensic CSV evidence schema.
      - EvidenceId and SHA-256 IntegrityHash generation.
      - Full SQL-FIRST field extraction pipeline using LogParser.
      - Date range filtering.
      - User/text filtering.
      - Structured execution logging under C:\Logs-TEMP.
      - Windows Forms GUI with safe execution wrappers.
      - PowerShell 5.1 compatibility.
      - SQL-first LogParser extraction with hydration-independent processing.

.EVENTIDS
    4663 - Object Access.
    5140 - Network Share Access.
    5145 - Detailed File Share Access Check.

.OUTPUTS
    CSV report exported by default to the current user's Documents folder.
    Execution log exported by default to C:\Logs-TEMP\<script-name>.log.

.REQUIREMENTS
    - Windows PowerShell 5.1 or later.
    - Administrator or equivalent event log access rights.
    - Security auditing enabled for Object Access and File Share auditing.
    - For live mode, access to the local Security event log.
    - For archive mode, readable .evtx evidence files.
    - Log Parser 2.2 installed locally.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-08-v2.0.0-PRODUCTION-SQLFIRST-FULLFIELD-EXTRACTION

.NOTES
    Production stable baseline aligned with the enterprise/DFIR EVTX toolkit model:
      - SQL-FIRST full-field extraction architecture.
      - PATH-AGNOSTIC archive processing.
      - Strict separation between live acquisition and offline evidence analysis.
      - Hydration-independent forensic processing pipeline.
      - No FileInfo or descriptor-object leakage into EVTX processing functions.
      - Fixed-schema forensic export suitable for DFIR, audit evidence, and SIEM ingestion.
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

function Hide-PowerShellConsole {
    try {
        $signature = @'
using System;
using System.Runtime.InteropServices;
public static class Win32Console {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        if (-not ([System.Management.Automation.PSTypeName]'Win32Console').Type) {
            Add-Type -TypeDefinition $signature -ErrorAction Stop
        }
        $consolePtr = [Win32Console]::GetConsoleWindow()
        if ($consolePtr -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($consolePtr, 0)
        }
    }
    catch { }
}

if (-not $ShowConsole) { Hide-PowerShellConsole }


$script:Version = '2026-05-08-v2.0.0-PRODUCTION-SQLFIRST-FULLFIELD-EXTRACTION'
$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Security'
$script:ResolvedLiveChannelPath = $null
$script:LastCsvPath = $null
$script:Form = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:RuntimeLogTextBox = $null
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)

$script:ToolName = $script:ScriptName
$script:ToolTitle = 'File Server Evidence Audit'
$script:ToolVersion = $script:Version
$script:DefaultLogDir = $script:LogDir
$script:DefaultOutDir = $script:DefaultOutputDir
$script:LastReport = $script:LastCsvPath
$script:LastOutputDir = $script:DefaultOutputDir
$script:EventIds = @(4663, 5140, 5145)
$script:LiveChannels = @($script:LiveChannelName)
$script:EventCategory = @{
    4663 = 'Object Access / File System Object Access'
    5140 = 'Network Share Access'
    5145 = 'Detailed File Share Access Check'
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

Ensure-Directory -Path $script:LogDir

function Write-GuiLog {
    param(
        [Parameter(Mandatory=$true)][string]$Line
    )

    try {
        if ($null -eq $script:RuntimeLogTextBox) { return }
        if ($script:RuntimeLogTextBox.IsDisposed) { return }

        $appendAction = {
            param([string]$Text)
            try {
                $script:RuntimeLogTextBox.AppendText($Text + [Environment]::NewLine)
                $script:RuntimeLogTextBox.SelectionStart = $script:RuntimeLogTextBox.TextLength
                $script:RuntimeLogTextBox.ScrollToCaret()
            } catch { }
        }

        if ($script:RuntimeLogTextBox.InvokeRequired) {
            [void]$script:RuntimeLogTextBox.BeginInvoke($appendAction, @($Line))
        } else {
            & $appendAction $Line
        }
    }
    catch { }
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

function Format-LogParserSqlLiteral {
    param([Parameter(Mandatory=$true)][string]$Value)
    return ([string]$Value).Replace("'", "''")
}

function Resolve-LogParserPath {
    $candidates = @(
        @($script:LogParserExeCandidates),
        (Join-Path $PSScriptRoot 'LogParser.exe')
    )

    foreach ($candidate in @($candidates | ForEach-Object { $_ })) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Log "Resolved LogParser.exe path: '$candidate'" 'INFO'
            return [string]$candidate
        }
    }

    throw 'LogParser.exe was not found. Install Microsoft Log Parser 2.2 or place LogParser.exe beside this script.'
}

function New-LogParserFileServerEvidenceSql {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$OutputCsvPath
    )

    $source = Format-LogParserSqlLiteral -Value $EvtxPath
    $target = Format-LogParserSqlLiteral -Value $OutputCsvPath

@"
SELECT
    RecordNumber,
    TimeGenerated,
    EventID,
    EventTypeName,
    SourceName,
    ComputerName,
    Message
INTO '$target'
FROM '$source'
WHERE
(
    EventID = 4663
    OR EventID = 5140
    OR EventID = 5145
)
"@
}

function New-LogParserEventInventorySql {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$OutputCsvPath
    )

    $source = Format-LogParserSqlLiteral -Value $EvtxPath
    $target = Format-LogParserSqlLiteral -Value $OutputCsvPath

@"
SELECT
    EventID,
    COUNT(*) AS Count
INTO '$target'
FROM '$source'
GROUP BY EventID
"@
}

function Invoke-LogParserSqlFile {
    param(
        [Parameter(Mandatory=$true)][string]$QueryText,
        [Parameter(Mandatory=$true)][string]$TempDir,
        [Parameter(Mandatory=$true)][string]$BaseName,
        [Parameter(Mandatory=$true)][string]$ExpectedOutputPath
    )

    Ensure-Directory -Path $TempDir

    $logParser = Resolve-LogParserPath
    $stamp = Get-Timestamp
    $safeBaseName = ([string]$BaseName -replace '[^A-Za-z0-9_\-]+','_')
    if ([string]::IsNullOrWhiteSpace($safeBaseName)) { $safeBaseName = 'LogParserQuery' }

    $queryPath = Join-Path $TempDir ('{0}-{1}.sql' -f $safeBaseName,$stamp)
    $stdoutPath = Join-Path $TempDir ('{0}-{1}.out' -f $safeBaseName,$stamp)
    $stderrPath = Join-Path $TempDir ('{0}-{1}.err' -f $safeBaseName,$stamp)

    Set-Content -LiteralPath $queryPath -Value $QueryText -Encoding ASCII

    $sqlAuditDir = Join-Path $script:LogDir 'SQL'
    Ensure-Directory -Path $sqlAuditDir
    $auditedQueryPath = Join-Path $sqlAuditDir ([IO.Path]::GetFileName($queryPath))
    Copy-Item -LiteralPath $queryPath -Destination $auditedQueryPath -Force

    $queryArgument = ('file:"{0}"' -f $queryPath)
    $arguments = @(
        $queryArgument,
        '-i:EVT',
        '-o:CSV',
        '-headers:ON',
        '-stats:OFF'
    )

    Write-Log "Executing LogParser SQL. Query='$queryPath'; AuditedQuery='$auditedQueryPath'; ExpectedOutput='$ExpectedOutputPath'" 'INFO'

    $process = Start-Process `
        -FilePath $logParser `
        -ArgumentList $arguments `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    if ($process.ExitCode -ne 0) {
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "LogParser failed. ExitCode=$($process.ExitCode). Query=$queryPath. STDOUT=$stdout STDERR=$stderr"
    }

    if (-not (Test-Path -LiteralPath $ExpectedOutputPath -PathType Leaf)) {
        throw "LogParser completed but did not generate the expected output file: $ExpectedOutputPath"
    }

    return [string]$ExpectedOutputPath
}

function Invoke-LogParserFileServerEvidenceQuery {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$TempDir
    )

    if ([string]::IsNullOrWhiteSpace($EvtxPath)) { throw 'EVTX path is empty.' }
    if (-not (Test-Path -LiteralPath $EvtxPath -PathType Leaf)) { throw "EVTX path not found: $EvtxPath" }

    Ensure-Directory -Path $TempDir

    $stamp = Get-Timestamp
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($EvtxPath) -replace '[^A-Za-z0-9_\-]+','_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'Evidence' }
    $outputCsv = Join-Path $TempDir ('LogParser-FileServerEvidence-{0}-{1}.csv' -f $safeName,$stamp)

    $sql = New-LogParserFileServerEvidenceSql -EvtxPath $EvtxPath -OutputCsvPath $outputCsv

    return (Invoke-LogParserSqlFile -QueryText $sql -TempDir $TempDir -BaseName ('FileServerEvidence-' + $safeName) -ExpectedOutputPath $outputCsv)
}

function Invoke-LogParserEventInventoryQuery {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$TempDir
    )

    if ([string]::IsNullOrWhiteSpace($EvtxPath)) { throw 'EVTX path is empty.' }
    if (-not (Test-Path -LiteralPath $EvtxPath -PathType Leaf)) { throw "EVTX path not found: $EvtxPath" }

    Ensure-Directory -Path $TempDir

    $stamp = Get-Timestamp
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($EvtxPath) -replace '[^A-Za-z0-9_\-]+','_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'Evidence' }
    $outputCsv = Join-Path $TempDir ('LogParser-Inventory-{0}-{1}.csv' -f $safeName,$stamp)

    $sql = New-LogParserEventInventorySql -EvtxPath $EvtxPath -OutputCsvPath $outputCsv

    return (Invoke-LogParserSqlFile -QueryText $sql -TempDir $TempDir -BaseName ('Inventory-' + $safeName) -ExpectedOutputPath $outputCsv)
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


function ConvertTo-SafeDateTime {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }

    try {
        if ($Value -is [datetime]) { return [datetime]$Value }
        $text = ConvertTo-CanonicalString -Value $Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, [ref]$parsed)) { return $parsed }
    }
    catch { }

    return $null
}

function Get-MessageFieldValue {
    param(
        [AllowNull()][string]$Message,
        [Parameter(Mandatory=$true)][string]$Label,
        [int]$Occurrence = 1
    )

    if ([string]::IsNullOrWhiteSpace($Message)) { return '' }
    if ($Occurrence -lt 1) { $Occurrence = 1 }

    $escaped = [regex]::Escape($Label)
    $matches = [regex]::Matches($Message, "(?im)^\s*$escaped\s*:\s*(?<value>.*)$")

    if ($matches.Count -lt $Occurrence) { return '' }

    $match = $matches[$Occurrence - 1]
    $value = ConvertTo-CanonicalString -Value $match.Groups['value'].Value

    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }

    try {
        $lines = @($Message -split "`r?`n")
        $startIndex = -1
        $seen = 0

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*$escaped\s*:") {
                $seen++
                if ($seen -eq $Occurrence) { $startIndex = $i; break }
            }
        }

        if ($startIndex -ge 0) {
            for ($j = $startIndex + 1; $j -lt $lines.Count; $j++) {
                $candidate = (ConvertTo-CanonicalString -Value $lines[$j]).Trim()
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                if ($candidate -match '^\S[^:]{1,80}:') { break }
                return $candidate
            }
        }
    }
    catch { }

    return ''
}

function New-ForensicEvidenceRecordFromSqlRow {
    param(
        [Parameter(Mandatory=$true)]$Row,
        [Parameter(Mandatory=$true)][string]$SourceFile,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [Parameter(Mandatory=$true)][string]$SourceChannel
    )

    $eventId = 0
    if (-not [int]::TryParse((ConvertTo-CanonicalString -Value $Row.EventID), [ref]$eventId)) { return $null }

    $recordId = [int64]0
    [void][int64]::TryParse((ConvertTo-CanonicalString -Value $Row.RecordNumber), [ref]$recordId)

    $timeCreated = ConvertTo-SafeDateTime -Value $Row.TimeGenerated
    if ($null -eq $timeCreated) { $timeCreated = Get-Date }

    $message = [string]((ConvertTo-CanonicalString -Value $Row.Message) -replace "`r?`n", ' ')
    $rawMessage = ConvertTo-CanonicalString -Value $Row.Message
    $computer = ConvertTo-CanonicalString -Value $Row.ComputerName
    $providerName = ConvertTo-CanonicalString -Value $Row.SourceName
    $category = if ($script:EventCategory.ContainsKey($eventId)) { [string]$script:EventCategory[$eventId] } else { 'Discovered Event ID' }

    $actorUser = Get-MessageFieldValue -Message $rawMessage -Label 'Account Name' -Occurrence 1
    $actorDomain = Get-MessageFieldValue -Message $rawMessage -Label 'Account Domain' -Occurrence 1
    $subjectLogonId = Get-MessageFieldValue -Message $rawMessage -Label 'Logon ID' -Occurrence 1

    $objectName = Get-MessageFieldValue -Message $rawMessage -Label 'Object Name'
    $objectType = Get-MessageFieldValue -Message $rawMessage -Label 'Object Type'
    $objectServer = Get-MessageFieldValue -Message $rawMessage -Label 'Object Server'
    $handleId = Get-MessageFieldValue -Message $rawMessage -Label 'Handle ID'
    $accessMask = Get-MessageFieldValue -Message $rawMessage -Label 'Access Mask'
    $accesses = Get-MessageFieldValue -Message $rawMessage -Label 'Accesses'
    $processId = Get-MessageFieldValue -Message $rawMessage -Label 'Process ID'
    $processName = Get-MessageFieldValue -Message $rawMessage -Label 'Process Name'

    $shareName = Get-MessageFieldValue -Message $rawMessage -Label 'Share Name'
    $sharePath = Get-MessageFieldValue -Message $rawMessage -Label 'Share Path'
    $relativeTargetName = Get-MessageFieldValue -Message $rawMessage -Label 'Relative Target Name'
    $sourceAddress = Get-MessageFieldValue -Message $rawMessage -Label 'Source Address'
    $sourcePort = Get-MessageFieldValue -Message $rawMessage -Label 'Source Port'
    $ipAddress = $sourceAddress
    if ([string]::IsNullOrWhiteSpace($ipAddress)) { $ipAddress = Get-MessageFieldValue -Message $rawMessage -Label 'Client Address' }

    $targetUser = $objectName
    if ([string]::IsNullOrWhiteSpace($targetUser)) { $targetUser = $relativeTargetName }
    if ([string]::IsNullOrWhiteSpace($targetUser)) { $targetUser = $shareName }

    $raw = @(
        "ObjectServer=$objectServer",
        "ObjectType=$objectType",
        "ObjectName=$objectName",
        "HandleId=$handleId",
        "Accesses=$accesses",
        "AccessMask=$accessMask",
        "ProcessId=$processId",
        "ProcessName=$processName",
        "ShareName=$shareName",
        "SharePath=$sharePath",
        "RelativeTargetName=$relativeTargetName",
        "SourceAddress=$sourceAddress",
        "SourcePort=$sourcePort"
    ) -join ' | '

    $evidenceId = '{0}-{1}-{2}-{3}' -f $computer, $eventId, $recordId, (Get-Sha256String -Text $SourceFile).Substring(0,8)
    $hashInput = '{0}|{1}|{2}|{3}|{4}|{5}' -f $evidenceId, $SourceFile, $eventId, $recordId, $timeCreated.ToString('o'), $raw

    [PSCustomObject][ordered]@{
        EvidenceId          = [string]$evidenceId
        IntegrityHash       = [string](Get-Sha256String -Text $hashInput)
        ToolName            = [string]$script:ToolName
        ToolVersion         = [string]$script:ToolVersion
        ParserEngine        = 'LogParser-SQL-FullField'
        ParseStatus         = 'SQL_FULLFIELD'
        SourceMode          = [string]$SourceMode
        SourceChannel       = [string]$SourceChannel
        SourceFile          = [string]$SourceFile
        ComputerName        = [string]$computer
        EventId             = [int]$eventId
        EventCategory       = [string]$category
        RecordId            = [int64]$recordId
        TimeCreated         = [datetime]$timeCreated
        ProviderName        = [string]$providerName
        ActorUser           = [string]$actorUser
        ActorDomain         = [string]$actorDomain
        TargetUser          = [string]$targetUser
        TargetDomain        = ''
        GroupName           = ''
        SubjectLogonId      = [string]$subjectLogonId
        IpAddress           = [string]$ipAddress
        SourceAddress       = [string]$sourceAddress
        SourcePort          = [string]$sourcePort
        ObjectServer        = [string]$objectServer
        ObjectType          = [string]$objectType
        ObjectName          = [string]$objectName
        HandleId            = [string]$handleId
        Accesses            = [string]$accesses
        AccessMask          = [string]$accessMask
        ProcessId           = [string]$processId
        ProcessName         = [string]$processName
        ShareName           = [string]$shareName
        SharePath           = [string]$sharePath
        RelativeTargetName  = [string]$relativeTargetName
        RawEventData        = [string]$raw
        Message             = [string]$message
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
    $ipAddress = Get-MapValue -Map $map -Names @('IpAddress','ClientAddress','WorkstationName','SourceAddress')
    $sourceAddress = Get-MapValue -Map $map -Names @('SourceAddress','IpAddress','ClientAddress')
    $sourcePort = Get-MapValue -Map $map -Names @('SourcePort','ClientPort')
    $objectServer = Get-MapValue -Map $map -Names @('ObjectServer')
    $objectType = Get-MapValue -Map $map -Names @('ObjectType')
    $objectName = Get-MapValue -Map $map -Names @('ObjectName')
    $handleId = Get-MapValue -Map $map -Names @('HandleId','HandleID')
    $accesses = Get-MapValue -Map $map -Names @('Accesses','AccessList')
    $accessMask = Get-MapValue -Map $map -Names @('AccessMask')
    $processId = Get-MapValue -Map $map -Names @('ProcessId','ProcessID')
    $processName = Get-MapValue -Map $map -Names @('ProcessName')
    $shareName = Get-MapValue -Map $map -Names @('ShareName')
    $sharePath = Get-MapValue -Map $map -Names @('ShareLocalPath','SharePath')
    $relativeTargetName = Get-MapValue -Map $map -Names @('RelativeTargetName')
    $raw = Convert-MapToRawEventData -Map $map
    $evidenceId = '{0}-{1}-{2}-{3}' -f $computer, $eventId, $recordId, (Get-Sha256String -Text $SourceFile).Substring(0,8)
    $hashInput = '{0}|{1}|{2}|{3}|{4}|{5}' -f $evidenceId, $SourceFile, $eventId, $recordId, $Event.TimeCreated.ToString('o'), $raw
    [PSCustomObject][ordered]@{
        EvidenceId      = [string]$evidenceId
        IntegrityHash   = [string](Get-Sha256String -Text $hashInput)
        ToolName        = [string]$script:ToolName
        ToolVersion     = [string]$script:ToolVersion
        ParserEngine    = 'Get-WinEvent-Fallback'
        ParseStatus     = 'POWERSHELL_XML_FALLBACK'
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
        SourceAddress   = [string]$sourceAddress
        SourcePort      = [string]$sourcePort
        ObjectServer    = [string]$objectServer
        ObjectType      = [string]$objectType
        ObjectName      = [string]$objectName
        HandleId        = [string]$handleId
        Accesses        = [string]$accesses
        AccessMask      = [string]$accessMask
        ProcessId       = [string]$processId
        ProcessName     = [string]$processName
        ShareName       = [string]$shareName
        SharePath       = [string]$sharePath
        RelativeTargetName = [string]$relativeTargetName
        RawEventData    = [string]$raw
        Message         = [string]((ConvertTo-CanonicalString -Value $Event.Message) -replace "`r?`n", ' ')
    }
}

function Resolve-WindowsEventChannelPath {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ChannelName
    )

    $resolved = $null
    $channelForDefaultPath = ($ChannelName -replace '/', '%4')

    try {
        $textLines = @(& wevtutil.exe gl $ChannelName 2>$null)
        foreach ($line in $textLines) {
            if ($line -match '^\s*logFileName\s*:\s*(?<path>.+?)\s*$') {
                $resolved = [string]$Matches['path']
                break
            }
        }
    }
    catch {
        Write-Log "wevtutil text channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
    }

    if ([string]::IsNullOrWhiteSpace($resolved)) {
        try {
            $xmlLines = @(& wevtutil.exe gl $ChannelName /f:xml 2>$null)
            $xmlText = ($xmlLines -join [Environment]::NewLine)

            if (-not [string]::IsNullOrWhiteSpace($xmlText)) {
                try {
                    [xml]$xml = $xmlText
                    $node = $xml.SelectSingleNode('//*[local-name()="logFileName"]')
                    if ($null -ne $node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
                        $resolved = [string]$node.InnerText
                    }
                }
                catch {
                    Write-Log "wevtutil XML parsing failed for channel '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
                }

                if ([string]::IsNullOrWhiteSpace($resolved) -and $xmlText -match '(?is)<logFileName>\s*(?<path>.*?)\s*</logFileName>') {
                    $resolved = [string]$Matches['path']
                }
            }
        }
        catch {
            Write-Log "wevtutil XML channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolved)) {
        try {
            $classicName = if ($ChannelName -eq 'Security') { 'Security' } elseif ($ChannelName -eq 'Application') { 'Application' } elseif ($ChannelName -eq 'System') { 'System' } else { $ChannelName }
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$classicName"
            if (Test-Path -LiteralPath $regPath) {
                $reg = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
                if ($null -ne $reg.File -and -not [string]::IsNullOrWhiteSpace([string]$reg.File)) {
                    $resolved = [string]$reg.File
                }
            }
        }
        catch {
            Write-Log "Registry channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
        }
    }

    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = Join-Path $env:SystemRoot ("System32\winevt\Logs\{0}.evtx" -f $channelForDefaultPath)
    }

    $resolved = [Environment]::ExpandEnvironmentVariables([string]$resolved)

    if (-not [IO.Path]::IsPathRooted($resolved)) {
        $resolved = Join-Path $env:SystemRoot $resolved
    }

    $script:ResolvedLiveChannelPath = [string]$resolved
    Write-Log "Resolved channel '$ChannelName' live EVTX path candidate: $resolved" 'INFO'
    return [string]$resolved
}

function Resolve-SecurityChannelPath {
    $resolved = Resolve-WindowsEventChannelPath -ChannelName 'Security'
    $script:ResolvedLiveChannelPath = [string]$resolved
    return [string]$resolved
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName,
        [Parameter(Mandatory=$true)][string]$OutputDir
    )
    Ensure-Directory -Path $OutputDir

    $liveEvtxPath = if ($ChannelName -eq 'Security') {
        Resolve-SecurityChannelPath
    } else {
        Resolve-WindowsEventChannelPath -ChannelName $ChannelName
    }

    if (-not (Test-Path -LiteralPath $liveEvtxPath -PathType Leaf)) {
        Write-Log "Resolved live channel path does not currently exist or is not directly readable. Channel='$ChannelName'; Candidate='$liveEvtxPath'. Snapshot export will still use wevtutil channel name." 'WARN'
    }

    $safeName = ($ChannelName -replace '[\\/:*?"<>|]', '_')
    $snapshot = Join-Path $OutputDir ('{0}-{1}-{2}.evtx' -f $safeName, (Get-Timestamp), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $errPath = Join-Path $OutputDir ('wevtutil-{0}-{1}.err' -f $safeName, (Get-Timestamp))
    $args = @('epl', $ChannelName, $snapshot, '/ow:true')
    $p = Start-Process -FilePath 'wevtutil.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errPath
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "Failed to export live channel snapshot. Channel='$ChannelName'; ResolvedLivePath='$liveEvtxPath'; ExitCode=$($p.ExitCode). $err"
    }
    Write-Log "Live channel snapshot exported. Channel='$ChannelName'; ResolvedLivePath='$liveEvtxPath'; Snapshot='$snapshot'"
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
        [string]$TempDir
    )
    $paths = New-Object System.Collections.ArrayList
    if ($UseLiveLog) {
        foreach ($channel in @($script:LiveChannels)) {
            if ([string]::IsNullOrWhiteSpace($channel)) { continue }
            try { [void]$paths.Add((Export-LiveChannelSnapshot -ChannelName $channel -OutputDir $TempDir)) }
            catch { Write-Log "Live channel snapshot skipped. Channel='$channel'. Error: $($_.Exception.Message)" 'WARN' }
        }
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
    $sqlPreselectedCount = 0
    $usedSqlPreselection = $false

    try {
        $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')
        $sqlCsv = Invoke-LogParserFileServerEvidenceQuery -EvtxPath $EvtxPath -TempDir $sqlTempDir
        $sqlRows = @(Import-Csv -LiteralPath $sqlCsv)
        $sqlPreselectedCount = $sqlRows.Count

        if ($sqlPreselectedCount -eq 0) {
            Write-Log "LogParser found no matching file server evidence events in '$EvtxPath'." 'INFO'
            return @()
        }

        $sourceChannel = if ($SourceMode -eq 'LiveSnapshot') { $script:LiveChannelName } else { '' }
        $sqlDirectRecords = New-Object System.Collections.ArrayList

        foreach ($row in $sqlRows) {
            try {
                $record = New-ForensicEvidenceRecordFromSqlRow -Row $row -SourceFile $EvtxPath -SourceMode $SourceMode -SourceChannel $sourceChannel
                if ($null -eq $record) { continue }

                if ($UseDateRange) {
                    if ($record.TimeCreated -lt $StartTime -or $record.TimeCreated -gt $EndTime) { continue }
                }

                if (-not [string]::IsNullOrWhiteSpace($UserFilter)) {
                    $terms = @($UserFilter -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    if ($terms.Count -gt 0 -and $terms[0] -ne '*') {
                        $haystack = ('{0} {1} {2} {3} {4} {5} {6} {7} {8}' -f $record.ActorUser,$record.ActorDomain,$record.TargetUser,$record.ObjectName,$record.ShareName,$record.SharePath,$record.RelativeTargetName,$record.IpAddress,$record.RawEventData)
                        $matched = $false
                        foreach ($term in $terms) { if ($haystack -like ('*' + $term + '*')) { $matched = $true; break } }
                        if (-not $matched) { continue }
                    }
                }

                [void]$sqlDirectRecords.Add($record)
            }
            catch {
                Write-Log "Skipped SQL row during full-field normalization. Source='$EvtxPath'; Error=$($_.Exception.Message)" 'WARN'
            }
        }

        if ($sqlDirectRecords.Count -gt 0) {
            Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; SQLFullFieldRecords={2}; HydratedEvents=0; Records={2}; UsedSqlFullFieldExtraction=True" -f $EvtxPath, $sqlPreselectedCount, $sqlDirectRecords.Count)
            return @($sqlDirectRecords)
        }

        Write-Log "SQL full-field extraction returned zero normalized records from $sqlPreselectedCount candidate rows. Falling back to Get-WinEvent hydration pipeline." 'WARN'

        $recordSet = New-Object 'System.Collections.Generic.HashSet[Int64]'
        foreach ($row in $sqlRows) {
            if ($row.RecordNumber -match '^\d+$') { [void]$recordSet.Add([int64]$row.RecordNumber) }
        }

        Write-Log "LogParser preselected $($recordSet.Count) candidate file server evidence records from '$EvtxPath'." 'INFO'

        $events = @(
            Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
            Where-Object { $recordSet.Contains([int64]$_.RecordId) }
        )
        $usedSqlPreselection = $true

        if ($events.Count -eq 0 -and $sqlPreselectedCount -gt 0) {
            Write-Log "SQL preselection returned $sqlPreselectedCount candidate rows, but RecordNumber/RecordId hydration returned 0 events. Retrying Get-WinEvent without RecordId correlation for parser continuity." 'WARN'
            $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
    }
    catch {
        Write-Log "SQL-first LogParser preselection failed for '$EvtxPath'. Falling back to Get-WinEvent parser. Error: $($_.Exception.Message)" 'WARN'
        try { $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) }
        catch {
            if ($_.Exception.Message -match 'No events|não foi encontrado|No events were found') {
                Write-Log "No matching events found in '$EvtxPath'." 'INFO'
                return @()
            }
            throw
        }
    }

    $records = New-Object System.Collections.ArrayList
    $sourceChannel = if ($SourceMode -eq 'LiveSnapshot') { $script:LiveChannelName } else { '' }

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
        }
        catch {
            Write-Log "Skipped event during forensic normalization. Source='$EvtxPath'; EventId='$($event.Id)'; RecordId='$($event.RecordId)'; Error=$($_.Exception.Message)" 'WARN'
        }
    }

    Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; HydratedEvents={2}; Records={3}; UsedSqlPreselection={4}" -f $EvtxPath, $sqlPreselectedCount, @($events).Count, $records.Count, $usedSqlPreselection)
    return @($records)
}

function Get-ForensicEvidenceCsvHeaderLine {
    $columns = @(
        'EvidenceId',
        'IntegrityHash',
        'ToolName',
        'ToolVersion',
        'ParserEngine',
        'ParseStatus',
        'SourceMode',
        'SourceChannel',
        'SourceFile',
        'ComputerName',
        'EventId',
        'EventCategory',
        'RecordId',
        'TimeCreated',
        'ProviderName',
        'ActorUser',
        'ActorDomain',
        'TargetUser',
        'TargetDomain',
        'GroupName',
        'SubjectLogonId',
        'IpAddress',
        'SourceAddress',
        'SourcePort',
        'ObjectServer',
        'ObjectType',
        'ObjectName',
        'HandleId',
        'Accesses',
        'AccessMask',
        'ProcessId',
        'ProcessName',
        'ShareName',
        'SharePath',
        'RelativeTargetName',
        'RawEventData',
        'Message'
    )
    return ($columns -join ',')
}

function Export-ForensicEvidenceCsv {
    param(
        [AllowNull()][object[]]$Records,
        [Parameter(Mandatory=$true)][string]$CsvPath
    )

    if ($null -eq $Records) { $Records = @() }
    $count = @($Records).Count
    if ($count -gt 0) {
        @($Records) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Log "CSV export completed with $count record(s): '$CsvPath'" 'INFO'
        return
    }

    Get-ForensicEvidenceCsvHeaderLine | Set-Content -LiteralPath $CsvPath -Encoding UTF8
    Write-Log "CSV export completed with 0 records; header-only fixed schema written: '$CsvPath'" 'WARN'
}

function Invoke-ForensicAudit {
    param(
        [bool]$UseLiveLog,
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
    $script:LogDir = $LogDir
    $script:DefaultLogDir = $script:LogDir
    $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
    $script:LastOutputDir = $OutputDir
    $mode = if ($UseLiveLog) { 'LiveSnapshot' } else { 'Archive' }
    Write-Log "Starting forensic audit. Mode=$mode; ArchiveFolder='$ArchiveFolder'; IncludeSubfolders=$IncludeSubfolders; OutputDir='$OutputDir'; UseDateRange=$UseDateRange; StartTime=$StartTime; EndTime=$EndTime; UserFilter='$UserFilter'"
    $tempDir = Join-Path $env:TEMP ($script:ToolName + '-Snapshots')
    Ensure-Directory -Path $tempDir
    $sources = @(Get-SourceEvtxPaths -UseLiveLog $UseLiveLog -ArchiveFolder $ArchiveFolder -IncludeSubfolders $IncludeSubfolders -TempDir $tempDir)
    if ($sources.Count -eq 0) { Write-Log 'No EVTX sources selected for processing.' 'WARN' }
    $allRecords = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        foreach ($record in @(Read-EvtxEvidenceRecords -EvtxPath ([string]$source) -SourceMode $mode -StartTime $StartTime -EndTime $EndTime -UseDateRange $UseDateRange -UserFilter $UserFilter)) {
            [void]$allRecords.Add($record)
        }
    }
    $csvPath = Join-Path $OutputDir ('{0}-{1}.csv' -f $script:ToolName, (Get-Timestamp))
    $recordsToExport = @($allRecords | ForEach-Object { $_ })
    Export-ForensicEvidenceCsv -Records $recordsToExport -CsvPath $csvPath
    $script:LastReport = $csvPath
    Write-Log ("Forensic audit completed. Records={0}; Csv='{1}'" -f $allRecords.Count, $csvPath)
    return $csvPath
}

function Invoke-EvtxInventoryAudit {
    param(
        [bool]$UseLiveLog,
        [string]$ArchiveFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $script:LogDir = $LogDir
    $script:DefaultLogDir = $script:LogDir
    $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
    $tempDir = Join-Path $env:TEMP ($script:ToolName + '-Snapshots')
    Ensure-Directory -Path $tempDir
    $mode = if ($UseLiveLog) { 'LiveSnapshot' } else { 'Archive' }
    $sources = @(Get-SourceEvtxPaths -UseLiveLog $UseLiveLog -ArchiveFolder $ArchiveFolder -IncludeSubfolders $IncludeSubfolders -TempDir $tempDir)
    $rows = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        Write-Log "Inventory processing EVTX source: '$source'"
        try {
            $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')
            $sqlCsv = Invoke-LogParserEventInventoryQuery -EvtxPath ([string]$source) -TempDir $sqlTempDir
            $groups = @(Import-Csv -LiteralPath $sqlCsv | Sort-Object { [int]$_.EventID })
            foreach ($g in $groups) {
                [void]$rows.Add([PSCustomObject][ordered]@{
                    SourceMode = $mode
                    SourceFile = [string]$source
                    EventId    = [int]$g.EventID
                    Count      = [int]$g.Count
                })
            }
        } catch {
            Write-Log "SQL-first inventory failed for '$source'. Falling back to Get-WinEvent inventory. Error: $($_.Exception.Message)" 'WARN'
            try {
                $events = @(Get-WinEvent -Path ([string]$source) -ErrorAction Stop)
                $groups = @($events | Group-Object -Property Id | Sort-Object { [int]$_.Name })
                foreach ($g in $groups) {
                    [void]$rows.Add([PSCustomObject][ordered]@{
                        SourceMode = $mode
                        SourceFile = [string]$source
                        EventId    = [int]$g.Name
                        Count      = [int]$g.Count
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
Write-Log "Script version: $($script:Version)"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Log "Execution user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Computer name: $($script:MachineName)"
Write-Log "Log path: $($script:LogPath)"
try {
    $startupResolved = Resolve-SecurityChannelPath
    Write-Log "Resolved live Security channel path during startup: $startupResolved"
} catch {
    Write-Log "Startup live channel resolution failed. Error: $($_.Exception.Message)" 'WARN'
}
try {
    $startupLogParser = Resolve-LogParserPath
    Write-Log "LogParser available for SQL-first preselection: $startupLogParser"
} catch {
    Write-Log "LogParser not available during startup validation. SQL-first layer will use fallback if needed. Error: $($_.Exception.Message)" 'WARN'
}


$form = New-Object System.Windows.Forms.Form
$form.Text = $script:ToolTitle + " - " + $script:Version
$form.Size = New-Object System.Drawing.Size(900,620)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$script:Form = $form

$font = New-Object System.Drawing.Font('Segoe UI',9)
$form.Font = $font

function Add-Label { param([string]$Text,[int]$X,[int]$Y,[int]$W=130) $l=New-Object System.Windows.Forms.Label; $l.Text=$Text; $l.Location=New-Object System.Drawing.Point($X,$Y); $l.Size=New-Object System.Drawing.Size($W,22); $form.Controls.Add($l); return $l }

$chkLive = New-Object System.Windows.Forms.CheckBox
$chkLive.Text = 'Live Log Mode'
$chkLive.Checked = $true
$chkLive.Location = New-Object System.Drawing.Point(20,20)
$chkLive.Size = New-Object System.Drawing.Size(160,24)
$form.Controls.Add($chkLive)

Add-Label 'Live Security EVTX:' 190 22 125 | Out-Null
$txtLivePath = New-Object System.Windows.Forms.TextBox
$txtLivePath.Text = ''
$txtLivePath.Location = New-Object System.Drawing.Point(315,20)
$txtLivePath.Size = New-Object System.Drawing.Size(410,24)
$txtLivePath.ReadOnly = $true
$form.Controls.Add($txtLivePath)

$btnResolveChannel = New-Object System.Windows.Forms.Button
$btnResolveChannel.Text = 'Resolve Channel'
$btnResolveChannel.Location = New-Object System.Drawing.Point(740,18)
$btnResolveChannel.Size = New-Object System.Drawing.Size(110,28)
$form.Controls.Add($btnResolveChannel)


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


$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.Location = New-Object System.Drawing.Point(20,440)
$script:StatusLabel.Size = New-Object System.Drawing.Size(480,20)
$form.Controls.Add($script:StatusLabel)

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20,465)
$script:ProgressBar.Size = New-Object System.Drawing.Size(480,18)
$script:ProgressBar.Style = 'Continuous'
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$script:ProgressBar.Value = 0
$form.Controls.Add($script:ProgressBar)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Analysis'
$btnStart.Location = New-Object System.Drawing.Point(520,505)
$btnStart.Size = New-Object System.Drawing.Size(130,34)
$form.Controls.Add($btnStart)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open Last CSV'
$btnOpen.Location = New-Object System.Drawing.Point(660,505)
$btnOpen.Size = New-Object System.Drawing.Size(120,34)
$form.Controls.Add($btnOpen)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(790,505)
$btnClose.Size = New-Object System.Drawing.Size(60,34)
$form.Controls.Add($btnClose)

function Add-UiLog {
    param([string]$Message)
    Write-Log $Message 'INFO'
}
function Set-Busy { param([bool]$Busy) $btnStart.Enabled = -not $Busy; $btnClose.Enabled = -not $Busy; $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' } }


$resolveChannelAction = {
    try {
        $resolved = Resolve-SecurityChannelPath
        $txtLivePath.Text = $resolved
        $message = "Manual Resolve Channel completed. Channel='$($script:LiveChannelName)'; ResolvedPath='$resolved'"
        Write-Log $message 'INFO'
        if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = 'Resolved Security channel.' }
        Show-InfoBox $message
    } catch {
        $msg = "Manual Resolve Channel failed. Error: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Show-ErrorBox $msg
    }
}

$btnResolveChannel.Add_Click($resolveChannelAction.GetNewClosure())

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
    if ($archive) {
        Write-Log "Mode changed to Archive Mode. ArchiveFolder='$($txtArchive.Text)'" 'INFO'
        if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = 'Archive Mode selected.' }
    } else {
        Write-Log 'Current GUI mode: Live Log Mode. Archive folder controls are disabled.' 'INFO'
        if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = 'Live Log Mode selected.' }
    }
}
$chkLive.Add_CheckedChanged($updateLiveArchiveState.GetNewClosure())

$btnStart.Add_Click({
    try {
        Set-Busy -Busy $true
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 10 }
        if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = 'Analysis running...' }
        Add-UiLog 'Analysis started.'
        Write-Log 'GUI execution started.'
        $isInventory = ($script:EventIds.Count -eq 0)
        if ($isInventory) {
            $result = Invoke-EvtxInventoryAudit -UseLiveLog ([bool]$chkLive.Checked) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim())
        } else {
            $result = Invoke-ForensicAudit -UseLiveLog ([bool]$chkLive.Checked) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim()) -UseDateRange ([bool]$chkDate.Checked) -StartTime ([datetime]$dtFrom.Value) -EndTime ([datetime]$dtTo.Value) -UserFilter ([string]$txtFilter.Text.Trim())
        }
        if ($null -ne $script:ProgressBar) { $script:ProgressBar.Value = 100 }
        if ($null -ne $script:StatusLabel) { $script:StatusLabel.Text = 'Analysis completed.' }
        Add-UiLog "Analysis completed. CSV: $result"
        Show-InfoBox "Analysis completed.`n$result"
    } catch {
        $msg = "Analysis failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Add-UiLog $msg
        Show-ErrorBox $msg
    } finally {
        Write-Log 'GUI execution finished.'
        if ($null -ne $script:ProgressBar -and $script:ProgressBar.Value -ne 100) { $script:ProgressBar.Value = 0 }
        Set-Busy -Busy $false
    }
}.GetNewClosure())

& $updateLiveArchiveState
$form.Add_Shown({
    Write-Log 'GUI loaded. Runtime textbox logging is active.' 'INFO'
    Write-Log "Script version: $($script:Version)" 'INFO'
    Write-Log "Live channel name: $($script:LiveChannelName)" 'INFO'
    try {
        $resolved = Resolve-SecurityChannelPath
        $txtLivePath.Text = $resolved
        Write-Log "Resolved live Security channel path during GUI startup: $resolved" 'INFO'
    } catch {
        Write-Log "GUI startup Resolve Channel failed. Error: $($_.Exception.Message)" 'WARN'
    }
}.GetNewClosure())
$form.Add_FormClosed({ Write-Log "========== END: $($script:ToolTitle) ==========" }.GetNewClosure())
[void]$form.ShowDialog()

# End of script
