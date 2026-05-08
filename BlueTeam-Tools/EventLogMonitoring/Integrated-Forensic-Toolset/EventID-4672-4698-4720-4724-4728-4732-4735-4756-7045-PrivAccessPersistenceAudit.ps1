<#
.SYNOPSIS
    EventID-4672-4698-4720-4724-4728-4732-4735-4756-7045-PrivAccessPersistenceAudit.ps1 - Enterprise and forensic-grade privileged access and persistence audit tool.

.DESCRIPTION
    Unified Windows EVTX forensic audit tool for privileged access, account persistence,
    scheduled task creation, privileged group membership changes, password reset activity,
    and service installation events.

    This production baseline audits Security and System EVTX sources related to privilege use
    and persistence mechanisms. It supports live channel snapshot acquisition and offline
    archived EVTX analysis using a PATH-AGNOSTIC archive pipeline.

    The archive workflow accepts .evtx files from any evidence location, including local folders,
    external drives, mounted forensic images, network shares, and exported case repositories.
    Offline analysis is strictly separated from live acquisition and uses absolute string EVTX
    paths only.

    Core capabilities:
      - Live Security and System channel snapshot acquisition via wevtutil.exe.
      - Resolve Channel function to identify current live EVTX paths.
      - PATH-AGNOSTIC archived EVTX processing.
      - Recursive offline EVTX folder enumeration.
      - String-only EVTX path pipeline for parser functions.
      - Fixed forensic CSV evidence schema.
      - EvidenceId and SHA-256 IntegrityHash generation.
      - SQL-FIRST LogParser extraction with Get-WinEvent fallback continuity.
      - Date range filtering.
      - User/text filtering.
      - Structured execution logging under C:\Logs-TEMP.
      - Windows Forms GUI with safe execution wrappers.
      - PowerShell 5.1 compatibility.

.EVENTIDS
    4672 - Special Privileges Assigned to New Logon.
    4698 - Scheduled Task Created.
    4720 - User Account Created.
    4724 - Password Reset Attempt.
    4728 - Member Added to Global Security Group.
    4732 - Member Added to Local Security Group.
    4735 - Security Group Modified.
    4756 - Member Added to Universal Security Group.
    7045 - Service Installed.

.OUTPUTS
    CSV report exported by default to the current user's Documents folder.
    Execution log exported by default to C:\Logs-TEMP\<script-name>.log.

.REQUIREMENTS
    - Windows PowerShell 5.1 or later.
    - Administrator or equivalent event log access rights.
    - Security auditing enabled for account management, privileged use, and object access as applicable.
    - For live mode, access to the local Security and System event logs.
    - For archive mode, readable .evtx evidence files.
    - Log Parser 2.2 installed locally for SQL-FIRST processing.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-08-v2.0.2-PRODUCTION-ENRICHMENT-EXPORT-HOOK

.NOTES
    Production baseline aligned with the enterprise/DFIR EVTX toolkit model:
      - SQL-FIRST EVTX extraction architecture.
      - PATH-AGNOSTIC archive processing.
      - Strict separation between live acquisition and offline evidence analysis.
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
        if ($ShowConsole) { return }
        $signature = @'
using System;
using System.Runtime.InteropServices;
public static class Win32ConsoleWindow {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        if (-not ('Win32ConsoleWindow' -as [type])) { Add-Type -TypeDefinition $signature -ErrorAction SilentlyContinue }
        $handle = [Win32ConsoleWindow]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero) { [void][Win32ConsoleWindow]::ShowWindow($handle, 0) }
    } catch { }
}
Hide-PowerShellConsole


$script:ToolName       = 'EventID-4672-4698-4720-4724-4728-4732-4735-4756-7045-PrivAccessPersistenceAudit'
$script:ToolTitle      = 'Privileged Access and Persistence Audit'
$script:ToolVersion    = '2026-05-08-v1.0.1-PRODUCTION-BASELINE-SQLFIRST-ALIGNMENT'
$script:ScriptName    = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName   = [Environment]::MachineName
$script:DefaultLogDir  = 'C:\Logs-TEMP'
$script:DefaultOutDir  = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath        = Join-Path $script:DefaultLogDir ($script:ScriptName + '.log')
$script:LastReport     = ''
$script:LastOutputDir  = $script:DefaultOutDir
$script:EventIds       = @(4672,4698,4720,4724,4728,4732,4735,4756,7045)
$script:LiveChannels   = @('Security','System')
$script:ResolvedLiveChannelPaths = @{}
$script:RuntimeLogTextBox = $null
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)
$script:EventCategory  = @{
    4672 = 'Special Privileges Assigned'
    4698 = 'Scheduled Task Created'
    4720 = 'User Account Created'
    4724 = 'Password Reset Attempt'
    4728 = 'Member Added to Global Security Group'
    4732 = 'Member Added to Local Security Group'
    4735 = 'Security Group Modified'
    4756 = 'Member Added to Universal Security Group'
    7045 = 'Service Installed'
}

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
}

Ensure-Directory -Path $script:DefaultLogDir

function Write-GuiLog {
    param([Parameter(Mandatory=$true)][string]$Line)
    try {
        if ($null -eq $script:RuntimeLogTextBox) { return }
        if ($script:RuntimeLogTextBox.IsDisposed) { return }
        if ($script:RuntimeLogTextBox.InvokeRequired) {
            $script:RuntimeLogTextBox.BeginInvoke([Action[string]]{ param($m) $script:RuntimeLogTextBox.AppendText($m + [Environment]::NewLine) }, $Line) | Out-Null
        } else {
            $script:RuntimeLogTextBox.AppendText($Line + [Environment]::NewLine)
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
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            Write-Log "Resolved LogParser.exe path: '$candidate'"
            return [string]$candidate
        }
    }
    throw 'LogParser.exe was not found. Install Microsoft Log Parser 2.2 or update $script:LogParserExeCandidates.'
}

function Resolve-WindowsEventChannelPath {
    param([Parameter(Mandatory=$true)][string]$ChannelName)
    try {
        $lines = @(wevtutil.exe gl $ChannelName 2>$null)
        foreach ($line in $lines) {
            if ($line -match '^\s*logFileName\s*:\s*(.+)$') {
                $path = $Matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $script:ResolvedLiveChannelPaths[$ChannelName] = $path
                    Write-Log "Resolved channel '$ChannelName' live EVTX path candidate: $path"
                    return $path
                }
            }
        }
    } catch {
        Write-Log "wevtutil channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
    }
    $fallback = if ($ChannelName -eq 'Security') { Join-Path $env:SystemRoot 'System32\winevt\Logs\Security.evtx' } elseif ($ChannelName -eq 'System') { Join-Path $env:SystemRoot 'System32\winevt\Logs\System.evtx' } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($fallback)) {
        $script:ResolvedLiveChannelPaths[$ChannelName] = $fallback
        Write-Log "Resolved channel '$ChannelName' fallback EVTX path candidate: $fallback"
        return $fallback
    }
    return ''
}

function Resolve-AllLiveChannelPaths {
    foreach ($channel in @($script:LiveChannels)) {
        if ([string]::IsNullOrWhiteSpace($channel)) { continue }
        [void](Resolve-WindowsEventChannelPath -ChannelName $channel)
    }
}

function Get-SourceChannelFromEvtxPath {
    param([Parameter(Mandatory=$true)][string]$EvtxPath)
    $leaf = [IO.Path]::GetFileName($EvtxPath)
    if ($leaf -match 'Security') { return 'Security' }
    if ($leaf -match 'System') { return 'System' }
    return 'Unknown'
}

function New-LogParserPrivilegedSql {
    param([Parameter(Mandatory=$true)][string]$EvtxPath,[Parameter(Mandatory=$true)][string]$OutputCsvPath)
    $where = (($script:EventIds | ForEach-Object { 'EventID = ' + [int]$_ }) -join ' OR ')
@"
SELECT
    RecordNumber,
    TimeGenerated,
    EventID,
    EventTypeName,
    SourceName,
    ComputerName,
    Message
INTO '$OutputCsvPath'
FROM '$EvtxPath'
WHERE ($where)
"@
}

function Invoke-LogParserPrivilegedAccessQuery {
    param([Parameter(Mandatory=$true)][string]$EvtxPath,[Parameter(Mandatory=$true)][string]$TempDir)
    Ensure-Directory -Path $TempDir
    $logParser = Resolve-LogParserPath
    $stamp = Get-Timestamp
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($EvtxPath) -replace '[^\w\-]+','_')
    $queryPath = Join-Path $TempDir ("PrivilegedAccess-{0}-{1}.sql" -f $safeName,$stamp)
    $outPath = Join-Path $TempDir ("LogParser-PrivilegedAccess-{0}-{1}.csv" -f $safeName,$stamp)
    $errPath = Join-Path $TempDir ("LogParser-PrivilegedAccess-{0}-{1}.err" -f $safeName,$stamp)
    $sqlDir = Join-Path $script:DefaultLogDir 'SQL'
    Ensure-Directory -Path $sqlDir
    $auditedQueryPath = Join-Path $sqlDir ([IO.Path]::GetFileName($queryPath))
    $sql = New-LogParserPrivilegedSql -EvtxPath $EvtxPath -OutputCsvPath $outPath
    Set-Content -LiteralPath $queryPath -Value $sql -Encoding ASCII
    Set-Content -LiteralPath $auditedQueryPath -Value $sql -Encoding ASCII
    $args = @("file:$queryPath", '-i:EVT', '-o:CSV', '-headers:ON', '-stats:OFF')
    Write-Log "Executing LogParser SQL. Query='$queryPath'; AuditedQuery='$auditedQueryPath'; ExpectedOutput='$outPath'"
    $p = Start-Process -FilePath $logParser -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errPath
    if ($p.ExitCode -ne 0) {
        $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "LogParser failed. ExitCode=$($p.ExitCode). Query=$queryPath. STDERR=$err"
    }
    if (-not (Test-Path -LiteralPath $outPath)) { throw "LogParser did not generate output CSV: $outPath" }
    return [string]$outPath
}

function Get-MessageFieldValue {
    param([string]$Message,[string[]]$Labels)
    if ([string]::IsNullOrWhiteSpace($Message)) { return '' }
    foreach ($label in $Labels) {
        $pattern = '(?im)^\s*' + [regex]::Escape($label) + '\s*:\s*(.+?)\s*$'
        $m = [regex]::Match($Message, $pattern)
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    }
    return ''
}

function New-ForensicEvidenceRecordFromSqlRow {
    param(
        [Parameter(Mandatory=$true)]$Row,
        [Parameter(Mandatory=$true)][string]$SourceFile,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [Parameter(Mandatory=$true)][string]$SourceChannel
    )
    $eventId = [int]$Row.EventID
    $recordId = if ($Row.RecordNumber -match '^\d+$') { [int64]$Row.RecordNumber } else { 0 }
    $timeCreated = try { [datetime]$Row.TimeGenerated } catch { [datetime]::MinValue }
    $message = [string]$Row.Message
    $computer = [string]$Row.ComputerName
    $category = if ($script:EventCategory.ContainsKey($eventId)) { [string]$script:EventCategory[$eventId] } else { 'Discovered Event ID' }
    $actorUser = Get-MessageFieldValue -Message $message -Labels @('Account Name','Subject User Name','Nome da Conta','Nome de Usuário','User Name')
    $actorDomain = Get-MessageFieldValue -Message $message -Labels @('Account Domain','Subject Domain Name','Domínio da Conta','Domínio')
    $targetUser = Get-MessageFieldValue -Message $message -Labels @('Target Account Name','Target User Name','New Account Name','Service Name','Task Name','Member Name','Nome da Conta de Destino','Nome do Serviço','Nome da Tarefa','Nome do Membro')
    $targetDomain = Get-MessageFieldValue -Message $message -Labels @('Target Domain','Target Domain Name','Account Domain','Domínio de Destino')
    $groupName = Get-MessageFieldValue -Message $message -Labels @('Group Name','Target Account Name','Nome do Grupo')
    $logonId = Get-MessageFieldValue -Message $message -Labels @('Logon ID','Subject Logon ID','ID de Logon')
    $ipAddress = Get-MessageFieldValue -Message $message -Labels @('Source Network Address','Client Address','Endereço de Rede de Origem','Endereço do Cliente')
    $raw = $message -replace "`r?`n", ' | '
    $evidenceId = '{0}-{1}-{2}-{3}' -f $computer, $eventId, $recordId, (Get-Sha256String -Text $SourceFile).Substring(0,8)
    $hashInput = '{0}|{1}|{2}|{3}|{4}|{5}' -f $evidenceId, $SourceFile, $eventId, $recordId, $timeCreated.ToString('o'), $raw
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
        TimeCreated     = [datetime]$timeCreated
        ProviderName    = [string]$Row.SourceName
        ActorUser       = [string]$actorUser
        ActorDomain     = [string]$actorDomain
        TargetUser      = [string]$targetUser
        TargetDomain    = [string]$targetDomain
        GroupName       = [string]$groupName
        SubjectLogonId  = [string]$logonId
        IpAddress       = [string]$ipAddress
        RawEventData    = [string]$raw
        Message         = [string]$raw
        ParserEngine    = 'LogParser'
        ParseStatus     = 'SUCCESS'
    }
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
        ParserEngine    = 'Get-WinEvent'
        ParseStatus     = 'SUCCESS'
    }
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$ChannelName,
        [Parameter(Mandatory=$true)][string]$OutputDir
    )
    Ensure-Directory -Path $OutputDir
    $safeName = ($ChannelName -replace '[\\/:*?"<>|]', '_')
    $snapshot = Join-Path $OutputDir ('{0}-{1}-{2}.evtx' -f $safeName, (Get-Timestamp), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $errPath = Join-Path $OutputDir ('wevtutil-{0}-{1}.err' -f $safeName, (Get-Timestamp))
    $resolvedLivePath = Resolve-WindowsEventChannelPath -ChannelName $ChannelName
    $args = @('epl', $ChannelName, $snapshot, '/ow:true')
    $p = Start-Process -FilePath 'wevtutil.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errPath
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "Failed to export live channel snapshot. Channel='$ChannelName'; ExitCode=$($p.ExitCode). $err"
    }
    Write-Log "Live channel snapshot exported. Channel='$ChannelName'; ResolvedLivePath='$resolvedLivePath'; Snapshot='$snapshot'"
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
    $records = New-Object System.Collections.ArrayList
    $sourceChannel = Get-SourceChannelFromEvtxPath -EvtxPath $EvtxPath
    $sqlRows = @()
    $usedSql = $false
    try {
        $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')
        $sqlCsv = Invoke-LogParserPrivilegedAccessQuery -EvtxPath $EvtxPath -TempDir $sqlTempDir
        $sqlRows = @(Import-Csv -LiteralPath $sqlCsv)
        if ($sqlRows.Count -gt 0) {
            $usedSql = $true
            foreach ($row in $sqlRows) {
                $record = New-ForensicEvidenceRecordFromSqlRow -Row $row -SourceFile $EvtxPath -SourceMode $SourceMode -SourceChannel $sourceChannel
                if ($UseDateRange) {
                    if ($record.TimeCreated -lt $StartTime -or $record.TimeCreated -gt $EndTime) { continue }
                }
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
            Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; SQLFullFieldRecords={2}; HydratedEvents=0; Records={3}; UsedSqlFullFieldExtraction=True" -f $EvtxPath, $sqlRows.Count, $sqlRows.Count, $records.Count)
            return @($records)
        }
    } catch {
        Write-Log "SQL-FIRST LogParser extraction failed for '$EvtxPath'. Falling back to Get-WinEvent parser. Error: $($_.Exception.Message)" 'WARN'
    }

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
    Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; HydratedEvents={2}; Records={3}; UsedSqlFullFieldExtraction={4}" -f $EvtxPath, @($sqlRows).Count, @($events).Count, $records.Count, $usedSql)
    return @($records)
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
    $script:DefaultLogDir = $LogDir
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ScriptName + '.log')
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
    if (Get-Command -Name Invoke-SafeInvestigativeEnrichment -ErrorAction SilentlyContinue) {
        Write-Log ("Applying safe investigative enrichment before CSV export. Records={0}" -f $allRecords.Count)
        $enrichedRecords = Invoke-SafeInvestigativeEnrichment -Records @($allRecords)
        $allRecords = New-Object System.Collections.ArrayList
        foreach ($enrichedRecord in @($enrichedRecords)) {
            [void]$allRecords.Add($enrichedRecord)
        }
        Write-Log ("Safe investigative enrichment completed. Records={0}" -f $allRecords.Count)
    }
    @($allRecords) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
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
    $script:DefaultLogDir = $LogDir
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ScriptName + '.log')
    $tempDir = Join-Path $env:TEMP ($script:ToolName + '-Snapshots')
    Ensure-Directory -Path $tempDir
    $mode = if ($UseLiveLog) { 'LiveSnapshot' } else { 'Archive' }
    $sources = @(Get-SourceEvtxPaths -UseLiveLog $UseLiveLog -ArchiveFolder $ArchiveFolder -IncludeSubfolders $IncludeSubfolders -TempDir $tempDir)
    $rows = New-Object System.Collections.ArrayList
    foreach ($source in $sources) {
        Write-Log "Inventory processing EVTX source: '$source'"
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
Resolve-AllLiveChannelPaths
try { [void](Resolve-LogParserPath); Write-Log "LogParser available for SQL-FIRST extraction." } catch { Write-Log $_.Exception.Message 'WARN' }

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:ToolTitle
$form.Size = New-Object System.Drawing.Size(900,610)
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

Add-Label 'Resolved Live Channels:' 20 195 150 | Out-Null
$txtResolvedChannel = New-Object System.Windows.Forms.TextBox
$txtResolvedChannel.ReadOnly = $true
$txtResolvedChannel.Location = New-Object System.Drawing.Point(170,193)
$txtResolvedChannel.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtResolvedChannel)
$btnResolveChannel = New-Object System.Windows.Forms.Button
$btnResolveChannel.Text = 'Resolve Channel'
$btnResolveChannel.Location = New-Object System.Drawing.Point(740,191)
$btnResolveChannel.Size = New-Object System.Drawing.Size(110,28)
$form.Controls.Add($btnResolveChannel)

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Text = 'Use date range'
$chkDate.Location = New-Object System.Drawing.Point(20,235)
$chkDate.Size = New-Object System.Drawing.Size(140,24)
$form.Controls.Add($chkDate)
$dtFrom = New-Object System.Windows.Forms.DateTimePicker
$dtFrom.Format = 'Custom'
$dtFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtFrom.Value = (Get-Date).AddDays(-7)
$dtFrom.Location = New-Object System.Drawing.Point(170,233)
$dtFrom.Size = New-Object System.Drawing.Size(180,24)
$form.Controls.Add($dtFrom)
$dtTo = New-Object System.Windows.Forms.DateTimePicker
$dtTo.Format = 'Custom'
$dtTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtTo.Value = Get-Date
$dtTo.Location = New-Object System.Drawing.Point(370,233)
$dtTo.Size = New-Object System.Drawing.Size(180,24)
$form.Controls.Add($dtTo)

Add-Label 'User/Text Filter:' 20 275 150 | Out-Null
$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Text = ''
$txtFilter.Location = New-Object System.Drawing.Point(170,273)
$txtFilter.Size = New-Object System.Drawing.Size(560,24)
$form.Controls.Add($txtFilter)

$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Multiline = $true
$txtStatus.ScrollBars = 'Vertical'
$txtStatus.ReadOnly = $true
$txtStatus.Location = New-Object System.Drawing.Point(20,320)
$txtStatus.Size = New-Object System.Drawing.Size(830,145)
$form.Controls.Add($txtStatus)
$script:RuntimeLogTextBox = $txtStatus

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = 'Start Analysis'
$btnStart.Location = New-Object System.Drawing.Point(520,500)
$btnStart.Size = New-Object System.Drawing.Size(130,34)
$form.Controls.Add($btnStart)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open Last CSV'
$btnOpen.Location = New-Object System.Drawing.Point(660,500)
$btnOpen.Size = New-Object System.Drawing.Size(120,34)
$form.Controls.Add($btnOpen)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(790,500)
$btnClose.Size = New-Object System.Drawing.Size(60,34)
$form.Controls.Add($btnClose)

function Add-UiLog { param([string]$Message) Write-GuiLog -Line ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) }
function Set-Busy { param([bool]$Busy) $btnStart.Enabled = -not $Busy; $btnClose.Enabled = -not $Busy; $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' } }

$browseAction = {
    param([System.Windows.Forms.TextBox]$Target)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $Target.Text
    if ($dlg.ShowDialog() -eq 'OK') { $Target.Text = $dlg.SelectedPath }
}

function Update-ResolvedChannelTextBox {
    $parts = New-Object System.Collections.ArrayList
    foreach ($channel in @($script:LiveChannels)) {
        $path = Resolve-WindowsEventChannelPath -ChannelName $channel
        if (-not [string]::IsNullOrWhiteSpace($path)) { [void]$parts.Add(("{0}={1}" -f $channel,$path)) }
    }
    $txtResolvedChannel.Text = (@($parts) -join ' | ')
}
$btnResolveChannel.Add_Click({
    try {
        Update-ResolvedChannelTextBox
        $msg = "Manual Resolve Channel completed. $($txtResolvedChannel.Text)"
        Write-Log $msg
        Show-InfoBox $msg
    } catch {
        $msg = "Resolve Channel failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Show-ErrorBox $msg
    }
}.GetNewClosure())

$btnBrowseArchive.Add_Click({ & $browseAction $txtArchive }.GetNewClosure())
$btnBrowseOut.Add_Click({ & $browseAction $txtOut }.GetNewClosure())
$btnOpen.Add_Click({ Open-LastReport }.GetNewClosure())
$btnClose.Add_Click({ $form.Close() }.GetNewClosure())

$updateLiveArchiveState = {
    $archive = -not $chkLive.Checked
    $txtArchive.Enabled = $archive
    $btnBrowseArchive.Enabled = $archive
    $chkSub.Enabled = $archive
}
$chkLive.Add_CheckedChanged({ & $updateLiveArchiveState }.GetNewClosure())

$btnStart.Add_Click({
    try {
        Set-Busy -Busy $true
        Add-UiLog 'Analysis started.'
        Write-Log 'GUI execution started.'
        $isInventory = ($script:EventIds.Count -eq 0)
        if ($isInventory) {
            $result = Invoke-EvtxInventoryAudit -UseLiveLog ([bool]$chkLive.Checked) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim())
        } else {
            $result = Invoke-ForensicAudit -UseLiveLog ([bool]$chkLive.Checked) -ArchiveFolder ([string]$txtArchive.Text.Trim()) -IncludeSubfolders ([bool]$chkSub.Checked) -OutputDir ([string]$txtOut.Text.Trim()) -LogDir ([string]$txtLog.Text.Trim()) -UseDateRange ([bool]$chkDate.Checked) -StartTime ([datetime]$dtFrom.Value) -EndTime ([datetime]$dtTo.Value) -UserFilter ([string]$txtFilter.Text.Trim())
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

& $updateLiveArchiveState
Update-ResolvedChannelTextBox
Write-Log 'GUI loaded. Runtime textbox logging is active.'
$form.Add_FormClosed({ Write-Log "========== END: $($script:ToolTitle) ==========" }.GetNewClosure())
[void]$form.ShowDialog()


# =================================================================================================
# SAFE INVESTIGATIVE ENRICHMENT LAYER
# Version: 2026-05-08-v2.0.2-PRODUCTION-ENRICHMENT-EXPORT-HOOK
# Purpose:
#   Post-process already normalized records without modifying the SQL-FIRST extraction engine.
#   This layer is intentionally conservative and PowerShell 5.1-safe.
# =================================================================================================

function Get-SafeStringValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$InputObject,

        [Parameter(Mandatory = $false)]
        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace($PropertyName)) {
        return ''
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]

    if ($null -eq $property) {
        return ''
    }

    if ($null -eq $property.Value) {
        return ''
    }

    return ([string]$property.Value).Trim()
}

function Add-OrUpdateNoteProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [object]$Value
    )

    if ($null -eq $InputObject) {
        return
    }

    $existing = $InputObject.PSObject.Properties[$Name]

    if ($null -ne $existing) {
        $existing.Value = $Value
    }
    else {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Get-InvestigativeActorType {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ActorUser,

        [Parameter(Mandatory = $false)]
        [string]$ActorDomain
    )

    $actor = ([string]$ActorUser).Trim()

    if ([string]::IsNullOrWhiteSpace($actor)) {
        return 'Unknown'
    }

    if ($actor -match '\$$') {
        return 'MachineAccount'
    }

    if ($actor -match '^(SYSTEM|LOCAL SERVICE|NETWORK SERVICE|LocalSystem)$') {
        return 'SystemService'
    }

    if ($actor -match '^(ANONYMOUS LOGON|DWM-|UMFD-)$') {
        return 'SystemGenerated'
    }

    return 'HumanOrServiceAccount'
}

function Get-PersistenceTechniqueFromEvent {
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventId,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $id = ([string]$EventId).Trim()

    switch ($id) {
        '4698' { return 'Scheduled Task Persistence' }
        '7045' { return 'Service Installation Persistence' }
        '4720' { return 'Account Creation' }
        '4724' { return 'Password Reset / Credential Control' }
        '4728' { return 'Global Group Privilege Assignment' }
        '4732' { return 'Local Group Privilege Assignment' }
        '4735' { return 'Security Group Modification' }
        '4756' { return 'Universal Group Privilege Assignment' }
        '4672' { return 'Special Privilege Assignment' }
        default { return 'Privileged Access Activity' }
    }
}

function Get-InvestigationPriority {
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventId,

        [Parameter(Mandatory = $false)]
        [string]$ActorType,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $id = ([string]$EventId).Trim()
    $msg = ([string]$Message)

    if ($id -eq '7045') {
        if ($msg -match '(?i)veeam|vss|backup|monitoring|agent') {
            return 'MEDIUM'
        }
        return 'HIGH'
    }

    if ($id -eq '4698') {
        return 'HIGH'
    }

    if ($id -in @('4728', '4732', '4756')) {
        return 'HIGH'
    }

    if ($id -eq '4720') {
        return 'MEDIUM'
    }

    if ($id -eq '4724') {
        return 'MEDIUM'
    }

    if ($id -eq '4672') {
        if ($ActorType -in @('MachineAccount', 'SystemService', 'SystemGenerated')) {
            return 'LOW'
        }
        return 'MEDIUM'
    }

    return 'LOW'
}

function Get-InfrastructureClassification {
    param(
        [Parameter(Mandatory = $false)]
        [string]$EventId,

        [Parameter(Mandatory = $false)]
        [string]$ActorType,

        [Parameter(Mandatory = $false)]
        [string]$Message
    )

    $msg = ([string]$Message)

    if ($ActorType -eq 'MachineAccount') {
        return 'Machine Account Activity'
    }

    if ($ActorType -eq 'SystemService') {
        return 'Local System / Service Activity'
    }

    if ($msg -match '(?i)veeam|vss|backup') {
        return 'Backup Infrastructure'
    }

    if ($msg -match '(?i)monitoring|agent|health|inventory') {
        return 'Monitoring / Management Infrastructure'
    }

    return 'Not Classified As Infrastructure'
}

function New-PersistenceChainId {
    param(
        [Parameter(Mandatory = $false)]
        [object]$Record
    )

    $computer = Get-SafeStringValue -InputObject $Record -PropertyName 'ComputerName'
    $eventId  = Get-SafeStringValue -InputObject $Record -PropertyName 'EventId'
    $actor    = Get-SafeStringValue -InputObject $Record -PropertyName 'ActorUser'
    $target   = Get-SafeStringValue -InputObject $Record -PropertyName 'TargetUser'
    $group    = Get-SafeStringValue -InputObject $Record -PropertyName 'GroupName'

    $basis = @($computer, $eventId, $actor, $target, $group) -join '|'

    if ([string]::IsNullOrWhiteSpace($basis.Replace('|', ''))) {
        return ([guid]::NewGuid().Guid)
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($basis)
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16)
    }
    finally {
        $sha.Dispose()
    }
}

function Invoke-SafeInvestigativeEnrichment {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Records
    )

    if ($null -eq $Records -or @($Records).Count -eq 0) {
        return @()
    }

    $output = New-Object System.Collections.Generic.List[object]

    foreach ($record in @($Records)) {

        if ($null -eq $record) {
            continue
        }

        $eventId = Get-SafeStringValue -InputObject $record -PropertyName 'EventId'
        $actorUser = Get-SafeStringValue -InputObject $record -PropertyName 'ActorUser'
        $actorDomain = Get-SafeStringValue -InputObject $record -PropertyName 'ActorDomain'
        $message = Get-SafeStringValue -InputObject $record -PropertyName 'Message'

        $actorType = Get-InvestigativeActorType -ActorUser $actorUser -ActorDomain $actorDomain
        $technique = Get-PersistenceTechniqueFromEvent -EventId $eventId -Message $message
        $infraClass = Get-InfrastructureClassification -EventId $eventId -ActorType $actorType -Message $message
        $priority = Get-InvestigationPriority -EventId $eventId -ActorType $actorType -Message $message
        $chainId = New-PersistenceChainId -Record $record

        $summary = ('EventID={0}; Technique={1}; ActorType={2}; Infrastructure={3}; Priority={4}' -f `
            $eventId, $technique, $actorType, $infraClass, $priority)

        Add-OrUpdateNoteProperty -InputObject $record -Name 'PersistenceChainId' -Value $chainId
        Add-OrUpdateNoteProperty -InputObject $record -Name 'PersistenceTechnique' -Value $technique
        Add-OrUpdateNoteProperty -InputObject $record -Name 'ActorType' -Value $actorType
        Add-OrUpdateNoteProperty -InputObject $record -Name 'InfrastructureClassification' -Value $infraClass
        Add-OrUpdateNoteProperty -InputObject $record -Name 'InvestigationPriority' -Value $priority
        Add-OrUpdateNoteProperty -InputObject $record -Name 'PersistenceChainSummary' -Value $summary

        $output.Add($record)
    }

    return @($output.ToArray())
}

# End of script
