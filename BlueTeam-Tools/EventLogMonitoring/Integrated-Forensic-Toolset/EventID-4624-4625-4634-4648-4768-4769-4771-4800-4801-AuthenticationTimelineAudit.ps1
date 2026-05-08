<#
.SYNOPSIS
    EventID-4624-4625-4634-4648-4768-4769-4771-4800-4801-AuthenticationTimelineAudit.ps1 - Enterprise and forensic-grade authentication timeline audit tool.

.DESCRIPTION
    Unified Windows EVTX forensic audit tool for authentication, logon, logoff, Kerberos, and workstation
    lock/unlock timeline events.

    This production revision is aligned with the EventID-5136-5137-5141-ADObjectChangeAudit.ps1 baseline
    architecture. It supports live Security log snapshot acquisition and offline archived EVTX analysis using
    a PATH-AGNOSTIC archive pipeline.

    The archive workflow accepts .evtx files from any evidence location, including local folders, external
    drives, mounted forensic images, network shares, and exported case repositories. Offline analysis is
    strictly separated from live acquisition and uses absolute string EVTX paths only.

    Core capabilities:
      - Live Security channel snapshot acquisition via wevtutil.exe.
      - PATH-AGNOSTIC archived EVTX processing.
      - Recursive offline EVTX folder enumeration.
      - String-only EVTX path pipeline for parser functions.
      - Fixed forensic CSV evidence schema.
      - EvidenceId and SHA-256 IntegrityHash generation.
      - Date range filtering.
      - User/text filtering.
      - Structured execution logging under C:\Logs-TEMP.
      - Windows Forms GUI with safe execution wrappers.
      - Manual Resolve Channel button with resolved Security.evtx path visibility.
      - Runtime GUI telemetry textbox, status label, and progress indicator.
      - PowerShell 5.1 compatibility.
      - SQL-first LogParser preselection/inventory with Get-WinEvent fallback.

.EVENTIDS
    4624 - Successful Logon.
    4625 - Failed Logon.
    4634 - Logoff.
    4648 - Explicit Credentials Logon.
    4768 - Kerberos TGT Request.
    4769 - Kerberos Service Ticket Request.
    4771 - Kerberos Pre-Authentication Failure.
    4800 - Workstation Locked.
    4801 - Workstation Unlocked.

.OUTPUTS
    CSV report exported by default to the current user's Documents folder.
    Execution log exported by default to C:\Logs-TEMP\<script-name>.log.
    Audited LogParser SQL files exported to C:\Logs-TEMP\SQL.

.REQUIREMENTS
    - Windows PowerShell 5.1 or later.
    - Administrator or equivalent event log access rights.
    - For live mode, access to the local Security event log.
    - For archive mode, readable .evtx evidence files.
    - Microsoft Log Parser 2.2 for SQL-first acceleration. Get-WinEvent fallback remains available.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-07-v1.0.6-PRODUCTION-RESOLVECHANNEL-BUTTON-INTEGRATION

.NOTES
    Production baseline aligned with the enterprise/DFIR EVTX toolkit model:
      - PATH-AGNOSTIC archive processing.
      - Strict separation between live acquisition and offline evidence analysis.
      - No FileInfo or descriptor-object leakage into EVTX processing functions.
      - Fixed-schema forensic export suitable for DFIR, audit evidence, and SIEM ingestion.
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

function Hide-PowerShellConsole {
    try {
        if (-not ("ConsoleWindow.NativeMethods" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace ConsoleWindow {
    public static class NativeMethods {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
}
"@ -ErrorAction Stop
        }

        $handle = [ConsoleWindow.NativeMethods]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero) {
            [void][ConsoleWindow.NativeMethods]::ShowWindow($handle, 0)
        }
    } catch { }
}

if (-not $ShowConsole) { Hide-PowerShellConsole }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Version = '2026-05-07-v1.0.6-PRODUCTION-RESOLVECHANNEL-BUTTON-INTEGRATION'
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

# Compatibility aliases retained to avoid broad functional churn during baseline alignment.
$script:ToolName = $script:ScriptName
$script:ToolTitle = 'Authentication Timeline Audit'
$script:ToolVersion = $script:Version
$script:DefaultLogDir = $script:LogDir
$script:DefaultOutDir = $script:DefaultOutputDir
$script:LastReport = $script:LastCsvPath
$script:LastOutputDir = $script:DefaultOutputDir
$script:EventIds = @(4624,4625,4634,4648,4768,4769,4771,4800,4801)
$script:LiveChannels = @($script:LiveChannelName)
$script:EventCategory = @{
    4624 = 'Successful Logon'
    4625 = 'Failed Logon'
    4634 = 'Logoff'
    4648 = 'Explicit Credentials Logon'
    4768 = 'Kerberos TGT Request'
    4769 = 'Kerberos Service Ticket Request'
    4771 = 'Kerberos Pre-Authentication Failure'
    4800 = 'Workstation Locked'
    4801 = 'Workstation Unlocked'
}

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
        }
        else {
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

function New-LogParserAuthenticationTimelineSql {
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
    EventID = 4624
    OR EventID = 4625
    OR EventID = 4634
    OR EventID = 4648
    OR EventID = 4768
    OR EventID = 4769
    OR EventID = 4771
    OR EventID = 4800
    OR EventID = 4801
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

    # LogParser 2.2 is not BOM-safe for SQL files in several Windows PowerShell 5.1 environments.
    Set-Content -LiteralPath $queryPath -Value $QueryText -Encoding ASCII

    # Preserve exact SQL used for DFIR reproducibility under the active log directory.
    $sqlAuditDir = Join-Path $script:LogDir 'SQL'
    Ensure-Directory -Path $sqlAuditDir
    $auditedQueryPath = Join-Path $sqlAuditDir ([IO.Path]::GetFileName($queryPath))
    Copy-Item -LiteralPath $queryPath -Destination $auditedQueryPath -Force

    # Canonical LogParser query-file syntax is file:<path>. Keep it as the first argument and quote the path.
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

function Invoke-LogParserAuthenticationTimelineQuery {
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
    $outputCsv = Join-Path $TempDir ('LogParser-AuthenticationTimeline-{0}-{1}.csv' -f $safeName,$stamp)

    $sql = New-LogParserAuthenticationTimelineSql -EvtxPath $EvtxPath -OutputCsvPath $outputCsv

    return (Invoke-LogParserSqlFile -QueryText $sql -TempDir $TempDir -BaseName ('AuthenticationTimeline-' + $safeName) -ExpectedOutputPath $outputCsv)
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


function Resolve-WindowsEventChannelPath {
    <#
    .SYNOPSIS
        Resolves the physical .evtx path currently configured for a Windows Event channel.

    .DESCRIPTION
        Baseline-compatible Resolve Channel implementation.
        This function is intentionally used before live snapshot export so the tool records
        the current live .evtx location even when the event log has been redirected from
        the default %SystemRoot%\System32\winevt\Logs path.

        Resolution order:
          1. wevtutil gl <ChannelName> text output
          2. wevtutil gl <ChannelName> /f:xml output
          3. registry mapping for classic logs
          4. canonical default winevt\Logs fallback
    #>
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
    <#
    .SYNOPSIS
        Baseline wrapper for resolving the Security live .evtx path.
    #>
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

    # Mandatory baseline behavior: resolve live channel path immediately before snapshot export.
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
    $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')

    try {
        $sqlCsv = Invoke-LogParserAuthenticationTimelineQuery -EvtxPath $EvtxPath -TempDir $sqlTempDir
        $sqlRows = @(Import-Csv -LiteralPath $sqlCsv)

        if ($sqlRows.Count -eq 0) {
            Write-Log "LogParser found no matching authentication timeline events in '$EvtxPath'." 'INFO'
            return @()
        }

        $recordIds = @(
            $sqlRows |
            Where-Object { $_.RecordNumber -match '^\d+$' } |
            ForEach-Object { [int64]$_.RecordNumber }
        )

        Write-Log "LogParser preselected $($recordIds.Count) candidate authentication timeline records from '$EvtxPath'." 'INFO'

        if ($recordIds.Count -eq 0) {
            Write-Log "LogParser output did not contain valid RecordNumber values for '$EvtxPath'. Falling back to Get-WinEvent filter only." 'WARN'
            $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        else {
            $recordSet = @{}
            foreach ($id in $recordIds) { $recordSet[[int64]$id] = $true }
            $events = @(
                Get-WinEvent -FilterHashtable $filter -ErrorAction Stop |
                Where-Object { $null -ne $_.RecordId -and $recordSet.ContainsKey([int64]$_.RecordId) }
            )
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
    $sourceChannel = $script:LiveChannelName
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
    @($allRecords) | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $script:LastReport = $csvPath
    $script:LastCsvPath = $csvPath
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
            $inventoryCsv = Invoke-LogParserEventInventoryQuery -EvtxPath ([string]$source) -TempDir $sqlTempDir
            $groups = @(Import-Csv -LiteralPath $inventoryCsv)
            foreach ($g in $groups) {
                [void]$rows.Add([PSCustomObject][ordered]@{
                    SourceMode = $mode
                    SourceFile = [string]$source
                    EventId    = [int]$g.EventID
                    Count      = [int]$g.Count
                })
            }
            Write-Log "Inventory completed with LogParser SQL for source: '$source'. Rows=$($groups.Count)" 'INFO'
        } catch {
            Write-Log "LogParser inventory failed for '$source'. Falling back to Get-WinEvent inventory. Error: $($_.Exception.Message)" 'WARN'
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
    $script:LastCsvPath = $csvPath
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
try { [void](Resolve-SecurityChannelPath) } catch { Write-Log "Initial Security live channel resolution failed. Channel='$($script:LiveChannelName)'. Error: $($_.Exception.Message)" 'WARN' }

$form = New-Object System.Windows.Forms.Form
$script:Form = $form
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

Add-Label 'Live Security EVTX:' 190 22 120 | Out-Null
$txtLivePath = New-Object System.Windows.Forms.TextBox
$txtLivePath.Text = ''
$txtLivePath.ReadOnly = $true
$txtLivePath.Location = New-Object System.Drawing.Point(310,20)
$txtLivePath.Size = New-Object System.Drawing.Size(420,24)
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
$script:StatusLabel.Location = New-Object System.Drawing.Point(20,438)
$script:StatusLabel.Size = New-Object System.Drawing.Size(830,22)
$form.Controls.Add($script:StatusLabel)

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20,465)
$script:ProgressBar.Size = New-Object System.Drawing.Size(830,16)
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
    Write-GuiLog -Line ('[{0}] [GUI] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    if ($script:StatusLabel) { $script:StatusLabel.Text = $Message }
}
function Set-Busy {
    param([bool]$Busy)
    $btnStart.Enabled = -not $Busy
    $btnClose.Enabled = -not $Busy
    $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' }
    if ($script:ProgressBar) {
        if ($Busy) {
            $script:ProgressBar.Style = 'Marquee'
        }
        else {
            $script:ProgressBar.Style = 'Continuous'
            $script:ProgressBar.Value = 0
        }
    }
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

$btnResolveChannel.Add_Click({
    try {
        $resolved = Resolve-SecurityChannelPath
        $txtLivePath.Text = $resolved
        Add-UiLog "Security channel resolved: $resolved"
        Write-Log "Manual Resolve Channel completed. Channel='$($script:LiveChannelName)'; ResolvedPath='$resolved'" 'INFO'

        if (Test-Path -LiteralPath $resolved -PathType Leaf) {
            Add-UiLog 'Resolved live EVTX path exists.'
        }
        else {
            Add-UiLog 'Resolved live EVTX path does not exist or is not directly readable. Live snapshot will still use wevtutil channel export.'
        }
    }
    catch {
        $msg = "Resolve Channel failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Add-UiLog $msg
        Show-ErrorBox $msg
    }
}.GetNewClosure())

$updateLiveArchiveState = {
    $archive = -not $chkLive.Checked
    $txtArchive.Enabled = $archive
    $btnBrowseArchive.Enabled = $archive
    $chkSub.Enabled = $archive
    $btnResolveChannel.Enabled = [bool]$chkLive.Checked
}

$chkLive.Add_CheckedChanged({
    & $updateLiveArchiveState
    if ($chkLive.Checked) {
        Write-Log 'Mode changed to Live Log Mode.' 'INFO'
    }
    else {
        Write-Log "Mode changed to Archive Mode. ArchiveFolder='$($txtArchive.Text)'" 'INFO'
    }
}.GetNewClosure())

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

$form.Add_Shown({
    try {
        Write-Log 'GUI loaded. Runtime textbox logging is active.' 'INFO'
        Write-Log "Script version: $($script:ToolVersion)" 'INFO'
        Write-Log "Live channel name: $($script:LiveChannelName)" 'INFO'
        try {
            $resolved = Resolve-SecurityChannelPath
            $txtLivePath.Text = $resolved
            Write-Log "Resolved live Security channel path during GUI startup: $resolved" 'INFO'
            Add-UiLog "Security channel resolved during startup: $resolved"
        }
        catch {
            $txtLivePath.Text = ''
            Write-Log "GUI startup channel resolution failed. Channel='$($script:LiveChannelName)'. Error: $($_.Exception.Message)" 'WARN'
        }
        try {
            $lp = Resolve-LogParserPath
            Write-Log "LogParser available for SQL-first preselection: $lp" 'INFO'
        }
        catch {
            Write-Log "LogParser not available. Get-WinEvent fallback remains active. Error: $($_.Exception.Message)" 'WARN'
        }
        if ($chkLive.Checked) {
            Write-Log 'Current GUI mode: Live Log Mode. Archive folder controls are disabled.' 'INFO'
        }
        else {
            Write-Log "Current GUI mode: Archive Mode. ArchiveFolder='$($txtArchive.Text)'" 'INFO'
        }
    }
    catch {
        Write-Log "GUI shown initialization failed: $($_.Exception.Message)" 'ERROR'
    }
}.GetNewClosure())

try { $txtLivePath.Text = Resolve-SecurityChannelPath } catch { Write-Log "Initial Resolve Channel failed: $($_.Exception.Message)" 'WARN' }
& $updateLiveArchiveState
$form.Add_FormClosed({ Write-Log "========== END: $($script:ToolTitle) ==========" }.GetNewClosure())
[void]$form.ShowDialog()
