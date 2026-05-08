<#
.SYNOPSIS
   EventID-307-PrintingService-Audit.ps1 - Enterprise and forensic-grade Windows PrintService Event ID 307 audit tool.

.DESCRIPTION
    Unified Windows EVTX forensic audit tool for PrintService Operational completed print-job events.

    This production version audits Windows PrintService Event ID 307 records related to completed
    print jobs. It supports live PrintService Operational log acquisition and offline archived EVTX
    analysis using a PATH-AGNOSTIC archive pipeline.

    The archive workflow accepts .evtx files from any evidence location, including local folders,
    external drives, mounted forensic images, network shares, and exported case repositories. Offline
    analysis is strictly separated from live acquisition and uses absolute string EVTX paths only.

    Core capabilities:
      - Live PrintService Operational channel snapshot acquisition via wevtutil.exe.
      - Resolve Channel function to identify the current live PrintService Operational .evtx path.
      - PATH-AGNOSTIC archived EVTX processing.
      - Recursive offline EVTX folder enumeration.
      - String-only EVTX path pipeline for parser functions.
      - Fixed forensic CSV evidence schema.
      - EvidenceId and SHA-256 IntegrityHash generation.
      - SQL-FIRST full-field LogParser extraction pipeline for Event ID 307.
      - Hydration-independent CSV generation when LogParser extraction succeeds.
      - Print forensic enrichment for printer, queue, workstation, volume, and document metadata.
      - XML/name-based EventData normalization hotfix for Event ID 307 provider payloads.
      - Local print infrastructure enrichment using printer, queue, driver, port, and share metadata.
      - Get-WinEvent fallback for parser continuity.
      - Date range filtering.
      - User/text filtering.
      - Structured execution logging under C:\Logs-TEMP.
      - Windows Forms GUI with safe execution wrappers.
      - PowerShell 5.1 compatibility.

.EVENTIDS
    307 - Print Job Completed / Print Job Activity.

.OUTPUTS
    CSV report exported by default to the current user's Documents folder.
    Execution log exported by default to C:\Logs-TEMP\<script-name>.log.

.REQUIREMENTS
    - Windows PowerShell 5.1 or later.
    - Administrator or equivalent event log access rights.
    - PrintService Operational logging enabled.
    - For live mode, access to the local PrintService Operational event log.
    - For archive mode, readable .evtx evidence files.
    - Log Parser 2.2 installed locally for SQL-FIRST extraction.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-08-v2.4.1-PRODUCTION-MULTISOURCE-IDENTITY-CORRELATION

.NOTES
    Production stable baseline aligned with the enterprise/DFIR EVTX toolkit model:
      - SQL-FIRST full-field extraction architecture.
      - Print forensic enrichment layer for operational and DFIR triage.
      - Post-extraction timeline continuity and actor classification layer.
      - PATH-AGNOSTIC archive processing.
      - Strict separation between live acquisition and offline evidence analysis.
      - Hydration-independent forensic processing pipeline.
      - No FileInfo or descriptor-object leakage into EVTX processing functions.
      - Fixed-schema forensic export suitable for DFIR, audit evidence, and SIEM ingestion.
      - Extraction/normalization kept separate from reconstruction/enrichment logic.
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
    if ($ShowConsole) { return }
    try {
        Add-Type -Name NativeMethods -Namespace ConsoleWindow -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
        $consolePtr = [ConsoleWindow.NativeMethods]::GetConsoleWindow()
        if ($consolePtr -ne [IntPtr]::Zero) { [void][ConsoleWindow.NativeMethods]::ShowWindow($consolePtr, 0) }
    } catch { }
}
Hide-PowerShellConsole


$script:ScriptName     = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName    = [Environment]::MachineName
$script:ToolName       = $script:ScriptName
$script:ToolTitle      = 'Printing Service Audit (Event ID 307 + Multisource Identity Correlation)'
$script:ToolVersion    = '2026-05-08-v2.4.1-PRODUCTION-MULTISOURCE-IDENTITY-CORRELATION'
$script:DefaultLogDir  = 'C:\Logs-TEMP'
$script:DefaultOutDir  = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath        = Join-Path $script:DefaultLogDir ($script:ScriptName + '.log')
$script:LastReport     = ''
$script:LastOutputDir  = $script:DefaultOutDir
$script:EventIds       = @(307)
$script:PrintLifecycleEventIds = @(300,306,800,801,805,842)
$script:SecurityCorrelationEventIds = @(4624,4634,4647,4672)
$script:TerminalServicesCorrelationEventIds = @(21,22,23,24,25,1149)
$script:CorrelationWindowBeforeMinutes = 480
$script:CorrelationWindowAfterMinutes = 30
$script:LiveChannelName = 'Microsoft-Windows-PrintService/Operational'
$script:LiveChannels   = @(
    $script:LiveChannelName,
    'Security',
    'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'
)
$script:ResolvedLiveChannelPath = ''
$script:RuntimeLogTextBox = $null
$script:StatusLabel = $null
$script:ProgressBar = $null
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)
$script:EventCategory  = @{
    307 = 'Print Job Activity'
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
        if ($null -eq $script:RuntimeLogTextBox -or $script:RuntimeLogTextBox.IsDisposed) { return }
        $append = {
            param($tb, $text)
            $tb.AppendText($text + [Environment]::NewLine)
            $tb.SelectionStart = $tb.TextLength
            $tb.ScrollToCaret()
        }
        if ($script:RuntimeLogTextBox.InvokeRequired) {
            [void]$script:RuntimeLogTextBox.BeginInvoke($append, @($script:RuntimeLogTextBox, $Line))
        } else {
            & $append $script:RuntimeLogTextBox $Line
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
        $output = @(wevtutil.exe gl $ChannelName 2>$null)
        foreach ($line in $output) {
            if ($line -match '^\s*logFileName\s*:\s*(.+?)\s*$') {
                $candidate = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim())
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    Write-Log "Resolved channel '$ChannelName' live EVTX path candidate: $candidate"
                    return [string]$candidate
                }
            }
        }
        Write-Log "Unable to resolve live EVTX path from wevtutil for channel '$ChannelName'." 'WARN'
        return ''
    } catch {
        Write-Log "Channel path resolution failed for '$ChannelName'. Error: $($_.Exception.Message)" 'WARN'
        return ''
    }
}

function Resolve-PrintServiceChannelPath {
    $script:ResolvedLiveChannelPath = Resolve-WindowsEventChannelPath -ChannelName $script:LiveChannelName
    return [string]$script:ResolvedLiveChannelPath
}

function Escape-LogParserLiteral {
    param([Parameter(Mandatory=$true)][string]$Value)
    return ($Value -replace "'", "''")
}

function New-LogParserPrintAuditSql {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$OutputCsvPath
    )
    $inputPath = Escape-LogParserLiteral -Value $EvtxPath
    $outputPath = Escape-LogParserLiteral -Value $OutputCsvPath
@"
SELECT
    RecordNumber,
    TimeGenerated,
    EventID,
    EventTypeName,
    SourceName,
    ComputerName,
    SID,
    Strings,
    Message
INTO '$outputPath'
FROM '$inputPath'
WHERE EventID = 307
"@
}

function Invoke-LogParserPrintAuditQuery {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$TempDir
    )
    Ensure-Directory -Path $TempDir
    $sqlAuditDir = Join-Path $script:DefaultLogDir 'SQL'
    Ensure-Directory -Path $sqlAuditDir
    $logParser = Resolve-LogParserPath
    $stamp = Get-Timestamp
    $safeName = ([IO.Path]::GetFileNameWithoutExtension($EvtxPath) -replace '[^A-Za-z0-9_.-]+','_')
    $queryPath = Join-Path $TempDir ('PrintAudit-{0}-{1}.sql' -f $safeName,$stamp)
    $auditedQuery = Join-Path $sqlAuditDir ('PrintAudit-{0}-{1}.sql' -f $safeName,$stamp)
    $outPath = Join-Path $TempDir ('LogParser-PrintAudit-{0}-{1}.csv' -f $safeName,$stamp)
    $stdoutPath = Join-Path $TempDir ('LogParser-PrintAudit-{0}-{1}.out' -f $safeName,$stamp)
    $stderrPath = Join-Path $TempDir ('LogParser-PrintAudit-{0}-{1}.err' -f $safeName,$stamp)
    $sql = New-LogParserPrintAuditSql -EvtxPath $EvtxPath -OutputCsvPath $outPath
    Set-Content -LiteralPath $queryPath -Value $sql -Encoding ASCII
    Set-Content -LiteralPath $auditedQuery -Value $sql -Encoding UTF8
    Write-Log "Executing LogParser SQL. Query='$queryPath'; AuditedQuery='$auditedQuery'; ExpectedOutput='$outPath'"
    $arguments = @(
        ('file:"{0}"' -f $queryPath),
        '-i:EVT',
        '-o:CSV',
        '-headers:ON',
        '-stats:OFF'
    )
    $p = Start-Process -FilePath $logParser -ArgumentList $arguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if ($p.ExitCode -ne 0) {
        $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "LogParser failed. ExitCode=$($p.ExitCode). Query=$queryPath. STDOUT=$stdout STDERR=$stderr"
    }
    if (-not (Test-Path -LiteralPath $outPath)) { throw "LogParser did not generate expected output: $outPath" }
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


function Resolve-SourceChannelForEvidence {
    param(
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$SourceMode
    )
    if ($SourceMode -eq 'LiveSnapshot') { return [string]$script:LiveChannelName }
    $fileName = [IO.Path]::GetFileNameWithoutExtension($EvtxPath)
    if ($fileName -match 'PrintService|Microsoft-Windows-PrintService|Operational') {
        return [string]$script:LiveChannelName
    }
    return [string]$script:LiveChannelName
}

function Split-LogParserStrings {
    param([AllowNull()][string]$Strings)
    if ([string]::IsNullOrWhiteSpace($Strings)) { return @() }
    $s = [string]$Strings
    if ($s -match '\|') { return @($s -split '\|' | ForEach-Object { $_.Trim() }) }
    if ($s -match ';') { return @($s -split ';' | ForEach-Object { $_.Trim() }) }
    return @($s)
}

function Get-FirstNonEmptyValue {
    param([AllowNull()][object[]]$Values)
    foreach ($v in @($Values)) {
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { return [string]$v }
    }
    return ''
}


function Get-Print307ValueFromMap {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Map,
        [Parameter(Mandatory=$true)][string[]]$Names
    )
    foreach ($name in @($Names)) {
        if ($Map.ContainsKey($name) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$name])) {
            return [string]$Map[$name]
        }
    }
    return ''
}

function Resolve-Print307PayloadFromXmlMap {
    param([Parameter(Mandatory=$true)][hashtable]$Map)

    # Event ID 307 commonly carries provider data as:
    # Param1=JobId, Param2=DocumentName, Param3=UserName, Param4=ClientMachine,
    # Param5=PrinterName, Param6=PortName, Param7=PrintSizeBytes, Param8=Pages.
    # Some builds/drivers expose semantic names instead of ParamN. Prefer semantic names,
    # then fall back to the canonical ParamN layout.
    [PSCustomObject][ordered]@{
        JobId          = Get-Print307ValueFromMap -Map $Map -Names @('JobId','JobID','JobIdentifier','Param1')
        Document       = Get-Print307ValueFromMap -Map $Map -Names @('DocumentName','Document','DocumentPrinted','Param2')
        PrintUser      = Get-Print307ValueFromMap -Map $Map -Names @('UserName','User','PrintUser','Owner','Param3')
        ClientComputer = Get-Print307ValueFromMap -Map $Map -Names @('ClientMachine','ClientComputer','ClientName','MachineName','WorkstationName','Param4')
        PrinterName    = Get-Print307ValueFromMap -Map $Map -Names @('PrinterName','Printer','QueueName','Param5')
        PortName       = Get-Print307ValueFromMap -Map $Map -Names @('PortName','PrinterPortName','Port','Param6')
        SizeBytes      = Get-Print307ValueFromMap -Map $Map -Names @('PrintSize','Size','SizeBytes','PrintSizeBytes','Param7')
        Pages          = Get-Print307ValueFromMap -Map $Map -Names @('Pages','TotalPages','PagesPrinted','Param8')
    }
}

function Resolve-Print307PayloadFromStrings {
    param([AllowNull()][object[]]$Strings)

    $s = @($Strings)
    # LogParser exposes EventData as an ordered insertion-string list. For PrintService 307,
    # the stable provider layout observed in forensic exports is:
    # 0 JobId | 1 Document | 2 User | 3 Client | 4 Printer | 5 Port | 6 SizeBytes | 7 Pages.
    [PSCustomObject][ordered]@{
        JobId          = if ($s.Count -gt 0) { [string]$s[0] } else { '' }
        Document       = if ($s.Count -gt 1) { [string]$s[1] } else { '' }
        PrintUser      = if ($s.Count -gt 2) { [string]$s[2] } else { '' }
        ClientComputer = if ($s.Count -gt 3) { [string]$s[3] } else { '' }
        PrinterName    = if ($s.Count -gt 4) { [string]$s[4] } else { '' }
        PortName       = if ($s.Count -gt 5) { [string]$s[5] } else { '' }
        SizeBytes      = if ($s.Count -gt 6) { [string]$s[6] } else { '' }
        Pages          = if ($s.Count -gt 7) { [string]$s[7] } else { '' }
    }
}

function Parse-Print307Message {
    param([AllowNull()][string]$Message)
    $result = @{
        Document = ''
        PrintUser = ''
        PrinterName = ''
        PortName = ''
        SizeBytes = ''
        Pages = ''
        ClientComputer = ''
    }
    if ([string]::IsNullOrWhiteSpace($Message)) { return $result }
    $m = [string]$Message

    # English PrintService 307 common format:
    # Document <jobId>, <document> owned by <user> was printed on <printer> through port <port>. Size in bytes: <size>. Pages printed: <pages>.
    if ($m -match 'Document\s+\d+\s*,\s*(?<doc>.+?)\s+owned by\s+(?<user>.+?)\s+was printed on\s+(?<printer>.+?)\s+through port\s+(?<port>.+?)\.\s+Size in bytes:\s+(?<size>\d+)\.\s+Pages printed:\s+(?<pages>\d+)') {
        $result.Document = $Matches['doc'].Trim()
        $result.PrintUser = $Matches['user'].Trim()
        $result.PrinterName = $Matches['printer'].Trim()
        $result.PortName = $Matches['port'].Trim()
        $result.SizeBytes = $Matches['size'].Trim()
        $result.Pages = $Matches['pages'].Trim()
        return $result
    }

    # PT-BR / localized resilient extraction for size/pages labels.
    if ($m -match '(?i)(Tamanho em bytes|Size in bytes)\s*:\s*(?<size>\d+)') { $result.SizeBytes = $Matches['size'].Trim() }
    if ($m -match '(?i)(P[aá]ginas impressas|Pages printed)\s*:\s*(?<pages>\d+)') { $result.Pages = $Matches['pages'].Trim() }
    return $result
}


function Get-DocumentExtension {
    param([AllowNull()][string]$DocumentName)
    if ([string]::IsNullOrWhiteSpace($DocumentName)) { return '' }
    try {
        $ext = [IO.Path]::GetExtension($DocumentName)
        if ([string]::IsNullOrWhiteSpace($ext)) { return '' }
        return $ext.TrimStart('.').ToLowerInvariant()
    } catch { return '' }
}

function Normalize-ClientWorkstation {
    param([AllowNull()][string]$ClientComputer)
    if ([string]::IsNullOrWhiteSpace($ClientComputer)) { return '' }
    $v = ([string]$ClientComputer).Trim()
    $v = $v.TrimStart('\\')
    if ($v -match '^([^\.]+)\.') { return $Matches[1].ToUpperInvariant() }
    return $v.ToUpperInvariant()
}

function Get-PrintVolumeCategory {
    param(
        [AllowNull()][string]$Pages,
        [AllowNull()][string]$Bytes
    )
    $p = 0
    $b = 0L
    [void][int]::TryParse(([string]$Pages), [ref]$p)
    [void][int64]::TryParse(([string]$Bytes), [ref]$b)
    if ($p -ge 100 -or $b -ge 104857600) { return 'VERY_HIGH' }
    if ($p -ge 50  -or $b -ge 52428800)  { return 'HIGH' }
    if ($p -ge 10  -or $b -ge 10485760)  { return 'MEDIUM' }
    if ($p -gt 0   -or $b -gt 0)         { return 'LOW' }
    return 'UNKNOWN'
}

function Get-PrinterIpFromPortName {
    param([AllowNull()][string]$PortName)
    if ([string]::IsNullOrWhiteSpace($PortName)) { return '' }
    $v = [string]$PortName
    if ($v -match '(?<ip>\b(?:\d{1,3}\.){3}\d{1,3}\b)') { return $Matches['ip'] }
    return ''
}


function Get-PrinterInfrastructureKey {
    param([AllowNull()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $v = ([string]$Name).Trim().TrimStart([char[]]'\')
    if ($v -match '^[^\\]+\\(?<q>.+)$') { $v = $Matches['q'] }
    return $v.ToLowerInvariant()
}

function Get-PrinterRiskCategory {
    param(
        [AllowNull()][string]$PrinterName,
        [AllowNull()][string]$ShareName,
        [AllowNull()][string]$Location,
        [AllowNull()][string]$Comment
    )
    $haystack = ('{0} {1} {2} {3}' -f $PrinterName,$ShareName,$Location,$Comment).ToLowerInvariant()
    if ($haystack -match 'rh|human|finance|finan|folha|payroll|diretoria|presid|gabinete|jurid|legal|secret|sigil|confid') { return 'SENSITIVE' }
    if ($haystack -match 'public|recep|protocolo|atendimento|balcao|balcão') { return 'PUBLIC_AREA' }
    if (-not [string]::IsNullOrWhiteSpace($ShareName)) { return 'SHARED_PRINTER' }
    return 'STANDARD'
}

function Resolve-PrintInfrastructureInventory {
    $inventory = @{}
    try {
        Write-Log 'Resolving local print infrastructure inventory for enrichment.'
        $printers = @()
        try {
            if (Get-Command -Name Get-Printer -ErrorAction SilentlyContinue) {
                $printers = @(Get-Printer -ErrorAction Stop)
            }
        } catch {
            Write-Log "Get-Printer inventory failed. Falling back to Win32_Printer. Error: $($_.Exception.Message)" 'WARN'
            $printers = @()
        }
        if (@($printers).Count -eq 0) {
            $printers = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue)
        }

        foreach ($printer in @($printers)) {
            $name = [string]$printer.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $key = Get-PrinterInfrastructureKey -Name $name
            if ([string]::IsNullOrWhiteSpace($key)) { continue }

            $portName = Get-SafePropertyValue -InputObject $printer -Name 'PortName'
            $driverName = Get-SafePropertyValue -InputObject $printer -Name 'DriverName'
            $shareName = Get-SafePropertyValue -InputObject $printer -Name 'ShareName'
            $location = Get-SafePropertyValue -InputObject $printer -Name 'Location'
            $comment = Get-SafePropertyValue -InputObject $printer -Name 'Comment'
            $shared = Get-SafePropertyValue -InputObject $printer -Name 'Shared'
            $published = Get-SafePropertyValue -InputObject $printer -Name 'Published'
            $status = Get-SafePropertyValue -InputObject $printer -Name 'PrinterStatus'
            if ([string]::IsNullOrWhiteSpace($status)) { $status = Get-SafePropertyValue -InputObject $printer -Name 'Status' }
            $processor = Get-SafePropertyValue -InputObject $printer -Name 'PrintProcessor'
            $hostAddress = Get-PrinterIpFromPortName -PortName $portName

            $inventory[$key] = [PSCustomObject]@{
                Name = $name
                PortName = $portName
                DriverName = $driverName
                ShareName = $shareName
                Location = $location
                Comment = $comment
                Shared = $shared
                Published = $published
                Status = $status
                PrintProcessor = $processor
                HostAddress = $hostAddress
                InfrastructureSource = 'LocalPrintInventory'
                RiskCategory = Get-PrinterRiskCategory -PrinterName $name -ShareName $shareName -Location $location -Comment $comment
            }
        }
        Write-Log ("Print infrastructure inventory resolved. Printers={0}" -f $inventory.Count)
    } catch {
        Write-Log "Print infrastructure inventory enrichment failed. Continuing without infrastructure metadata. Error: $($_.Exception.Message)" 'WARN'
    }
    return $inventory
}

function Add-OrUpdateNoteProperty {
    param(
        [Parameter(Mandatory=$true)]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$Value
    )
    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        $InputObject.$Name = $Value
    } else {
        Add-Member -InputObject $InputObject -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}


function Get-SafePropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory=$true)][string]$Name
    )
    if ($null -eq $InputObject) { return '' }
    try {
        $prop = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $prop) { return '' }
        if ($null -eq $prop.Value) { return '' }
        return [string]$prop.Value
    } catch {
        return ''
    }
}

function Get-ActorClassification {
    param([AllowNull()][string]$ActorUser)
    if ([string]::IsNullOrWhiteSpace($ActorUser)) { return 'UnknownActor' }
    $v = ([string]$ActorUser).Trim()
    $upper = $v.ToUpperInvariant()
    if ($upper.EndsWith('$')) { return 'MachineAccount' }
    if ($upper -match '^(NT AUTHORITY\\SYSTEM|AUTORIDADE NT\\SISTEMA|SYSTEM|LOCAL SYSTEM|LOCALSYSTEM)$') { return 'SystemService' }
    if ($upper -match '^(NT AUTHORITY\\LOCAL SERVICE|NT AUTHORITY\\NETWORK SERVICE|SERVIÇO LOCAL|SERVICO LOCAL|SERVIÇO DE REDE|SERVICO DE REDE)$') { return 'SystemService' }
    if ($upper -match 'BACKUP|VEEAM|MONITOR|SCCM|MECM|ZABBIX|NAGIOS|PRTG|QRADAR|EDR|SIEM') { return 'MonitoringOrBackupInfrastructure' }
    return 'HumanOperator'
}

function Get-PrintContinuityKey {
    param([AllowNull()]$Record)
    if ($null -eq $Record) { return 'unknown|unknown|unknown' }
    $actor = ([string]$Record.PrintUser).Trim().ToLowerInvariant()
    $printer = ([string]$Record.PrinterName).Trim().ToLowerInvariant()
    $client = ([string]$Record.ClientWorkstation).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($actor)) { $actor = 'unknown-actor' }
    if ([string]::IsNullOrWhiteSpace($printer)) { $printer = 'unknown-printer' }
    if ([string]::IsNullOrWhiteSpace($client)) { $client = 'unknown-client' }
    return ('{0}|{1}|{2}' -f $actor,$printer,$client)
}

function Add-PrintTimelineReconstruction {
    param([AllowNull()][object[]]$Records)
    $items = @($Records)
    if ($items.Count -eq 0) { return @() }

    foreach ($r in $items) {
        Add-OrUpdateNoteProperty -InputObject $r -Name 'ActorClassification' -Value (Get-ActorClassification -ActorUser ([string]$r.PrintUser))
        Add-OrUpdateNoteProperty -InputObject $r -Name 'ContinuityClass' -Value 'PrintJobCompleted'
        Add-OrUpdateNoteProperty -InputObject $r -Name 'TimelineId' -Value ''
        Add-OrUpdateNoteProperty -InputObject $r -Name 'ChronologyIndex' -Value 0
        Add-OrUpdateNoteProperty -InputObject $r -Name 'PreviousEvidenceId' -Value ''
        Add-OrUpdateNoteProperty -InputObject $r -Name 'ReconstructionSummary' -Value ''
    }

    $groups = @($items | Group-Object -Property { Get-PrintContinuityKey -Record $_ })
    foreach ($g in $groups) {
        $timelineId = (Get-Sha256String -Text ([string]$g.Name)).Substring(0,16)
        $ordered = @($g.Group | Sort-Object -Property TimeCreated,RecordId)
        $previous = ''
        $index = 0
        foreach ($r in $ordered) {
            $index++
            $r.TimelineId = $timelineId
            $r.ChronologyIndex = $index
            $r.PreviousEvidenceId = $previous
            $doc = [string]$r.PrintDocument
            if ($doc.Length -gt 120) { $doc = $doc.Substring(0,120) + '...' }
            $r.ReconstructionSummary = ('Print job completed by actor [{0}] on printer [{1}] from client [{2}]. Pages={3}; Bytes={4}; Document="{5}".' -f ([string]$r.PrintUser),([string]$r.PrinterName),([string]$r.ClientWorkstation),([string]$r.PrintPages),([string]$r.PrintSizeBytes),$doc)
            $previous = [string]$r.EvidenceId
        }
    }
    return @($items | Sort-Object -Property TimeCreated,RecordId)
}



function Resolve-PrintIdentityReconstruction {
    param([AllowNull()][object[]]$Records)

    $items = @($Records)
    if ($items.Count -eq 0) { return @() }

    Write-Log ("Starting deferred forensic identity reconstruction. Records={0}" -f $items.Count)

    foreach ($r in $items) {

        Add-OrUpdateNoteProperty -InputObject $r -Name 'ResolvedPrintActor' -Value ''
        Add-OrUpdateNoteProperty -InputObject $r -Name 'IdentityReconstructionMethod' -Value ''
        Add-OrUpdateNoteProperty -InputObject $r -Name 'IdentityConfidence' -Value 'Unresolved'
        Add-OrUpdateNoteProperty -InputObject $r -Name 'SessionOrSpoolerId' -Value ''
        Add-OrUpdateNoteProperty -InputObject $r -Name 'IdentityEvidenceSource' -Value ''

        $rawActor = ([string]$r.PrintUser).Trim()

        if ([string]::IsNullOrWhiteSpace($rawActor)) {
            $r.ResolvedPrintActor = 'UNRESOLVED'
            continue
        }

        if ($rawActor -match '^\d+$') {

            $r.SessionOrSpoolerId = $rawActor

            $candidate = $null

            try {

                $candidate = @($items | Where-Object {
                    $_.ClientWorkstation -eq $r.ClientWorkstation -and
                    $_.PrintUser -notmatch '^\d+$' -and
                    $_.PrintUser -ne ''
                } | Sort-Object TimeCreated -Descending | Select-Object -First 1)

            } catch {}

            if ($candidate.Count -gt 0) {

                $resolved = [string]$candidate[0].PrintUser

                $r.ResolvedPrintActor = $resolved
                $r.IdentityReconstructionMethod = 'TimelineContinuityCorrelation'
                $r.IdentityConfidence = 'Medium'
                $r.IdentityEvidenceSource = 'PrintServiceTimeline'

            }
            else {

                $r.ResolvedPrintActor = ('SESSION_OR_SPOOLER_ID:{0}' -f $rawActor)
                $r.IdentityReconstructionMethod = 'NumericSessionIdentifierDetected'
                $r.IdentityConfidence = 'Low'
                $r.IdentityEvidenceSource = 'EventID307Payload'

            }
        }
        else {

            $r.ResolvedPrintActor = $rawActor
            $r.IdentityReconstructionMethod = 'DirectPayloadIdentity'
            $r.IdentityConfidence = 'High'
            $r.IdentityEvidenceSource = 'EventID307Payload'

        }
    }

    Write-Log "Deferred forensic identity reconstruction completed."

    return @($items)
}


function Get-ContextField {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Map,
        [Parameter(Mandatory=$true)][string[]]$Names
    )
    return (Get-MapValue -Map $Map -Names $Names)
}

function New-CorrelationEvidenceRecord {
    param(
        [Parameter(Mandatory=$true)]$Event,
        [Parameter(Mandatory=$true)][string]$SourceFile,
        [Parameter(Mandatory=$true)][string]$SourceMode
    )
    try {
        $xml = [xml]$Event.ToXml()
        $map = Get-EventDataMap -XmlEvent $xml
        $eventId = [int]$Event.Id
        $computer = ConvertTo-CanonicalString -Value $Event.MachineName
        if ([string]::IsNullOrWhiteSpace($computer)) { $computer = ConvertTo-CanonicalString -Value $xml.Event.System.Computer }
        $user = Get-ContextField -Map $map -Names @('TargetUserName','User','UserName','AccountName','SubjectUserName','Param1','Param2')
        $domain = Get-ContextField -Map $map -Names @('TargetDomainName','Domain','UserDomain','AccountDomain','SubjectDomainName')
        $logonId = Get-ContextField -Map $map -Names @('TargetLogonId','LogonId','SubjectLogonId')
        $logonType = Get-ContextField -Map $map -Names @('LogonType')
        $ip = Get-ContextField -Map $map -Names @('IpAddress','ClientAddress','SourceNetworkAddress','Address')
        $workstation = Get-ContextField -Map $map -Names @('WorkstationName','ClientName','ClientMachine','MachineName','Param3','Param4')
        $sessionId = Get-ContextField -Map $map -Names @('SessionID','SessionId','Session','SessionName','Param1','Param2','Param3')
        if ($eventId -eq 1149) {
            if ([string]::IsNullOrWhiteSpace($user)) { $user = Get-ContextField -Map $map -Names @('Param1') }
            if ([string]::IsNullOrWhiteSpace($domain)) { $domain = Get-ContextField -Map $map -Names @('Param2') }
            if ([string]::IsNullOrWhiteSpace($ip)) { $ip = Get-ContextField -Map $map -Names @('Param3') }
        }
        $class = 'OtherCorrelation'
        if ($script:PrintLifecycleEventIds -contains $eventId) { $class = 'PrintLifecycle' }
        elseif ($script:SecurityCorrelationEventIds -contains $eventId) { $class = 'SecurityLogonContinuity' }
        elseif ($script:TerminalServicesCorrelationEventIds -contains $eventId) { $class = 'TerminalServicesSession' }
        $raw = Convert-MapToRawEventData -Map $map
        [PSCustomObject][ordered]@{
            EvidenceId = ('CTX-{0}-{1}-{2}-{3}' -f $computer,$eventId,[int64]$Event.RecordId,(Get-Sha256String -Text $SourceFile).Substring(0,8))
            SourceMode = [string]$SourceMode
            SourceFile = [string]$SourceFile
            SourceChannel = [string](Resolve-SourceChannelForEvidence -EvtxPath $SourceFile -SourceMode $SourceMode)
            ComputerName = [string]$computer
            EventId = [int]$eventId
            EventClass = [string]$class
            RecordId = [int64]$Event.RecordId
            TimeCreated = [datetime]$Event.TimeCreated
            ProviderName = [string]$Event.ProviderName
            UserName = [string]$user
            DomainName = [string]$domain
            LogonId = [string]$logonId
            LogonType = [string]$logonType
            IpAddress = [string]$ip
            WorkstationName = [string](Normalize-ClientWorkstation -ClientComputer $workstation)
            SessionId = [string]$sessionId
            RawEventData = [string]$raw
        }
    } catch {
        Write-Log "Skipped correlation evidence event. Source='$SourceFile'; Error=$($_.Exception.Message)" 'WARN'
        return $null
    }
}

function Read-MultisourceCorrelationEvidence {
    param(
        [Parameter(Mandatory=$true)][string[]]$EvtxPaths,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [bool]$UseDateRange
    )
    $records = New-Object System.Collections.ArrayList
    $ids = @($script:PrintLifecycleEventIds + $script:SecurityCorrelationEventIds + $script:TerminalServicesCorrelationEventIds | Sort-Object -Unique)
    foreach ($path in @($EvtxPaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        try {
            $filter = @{ Path = [string]$path; Id = [int[]]$ids }
            if ($UseDateRange) {
                $filter.StartTime = $StartTime.AddMinutes(-1 * [int]$script:CorrelationWindowBeforeMinutes)
                $filter.EndTime = $EndTime.AddMinutes([int]$script:CorrelationWindowAfterMinutes)
            }
            $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
            foreach ($evt in $events) {
                $ctx = New-CorrelationEvidenceRecord -Event $evt -SourceFile ([string]$path) -SourceMode $SourceMode
                if ($null -ne $ctx) { [void]$records.Add($ctx) }
            }
            Write-Log ("Correlation evidence parsed. Source='{0}'; Events={1}" -f $path, @($events).Count)
        } catch {
            if ($_.Exception.Message -match 'No events|não foi encontrado|No events were found') {
                Write-Log "No correlation evidence found in '$path'." 'DEBUG'
            } else {
                Write-Log "Correlation evidence parsing skipped for '$path'. Error: $($_.Exception.Message)" 'WARN'
            }
        }
    }
    Write-Log ("Multisource correlation evidence collection completed. Sources={0}; ContextEvents={1}" -f @($EvtxPaths).Count, $records.Count)
    return @($records)
}

function Initialize-IdentityCorrelationFields {
    param([Parameter(Mandatory=$true)]$Record)
    $fields = @{
        ResolvedPrintActor = ''
        IdentityReconstructionMethod = ''
        IdentityConfidence = 'Unresolved'
        SessionOrSpoolerId = ''
        IdentityEvidenceSource = ''
        CorrelationSources = ''
        CorrelatedSecurityLogonId = ''
        CorrelatedSessionId = ''
        CorrelatedLogonType = ''
        CorrelatedIpAddress = ''
        CorrelatedWorkstation = ''
        CorrelationWindowSeconds = ''
        PrintLifecycleEvents = ''
        IdentityCorrelationSummary = ''
    }
    foreach ($k in $fields.Keys) { Add-OrUpdateNoteProperty -InputObject $Record -Name $k -Value $fields[$k] }
}

function Find-NearestCorrelationContext {
    param(
        [Parameter(Mandatory=$true)]$PrintRecord,
        [Parameter(Mandatory=$true)][object[]]$Contexts,
        [Parameter(Mandatory=$true)][string]$ClassName,
        [switch]$RequireUser
    )
    $printTime = [datetime]$PrintRecord.TimeCreated
    $client = ([string]$PrintRecord.ClientWorkstation).Trim().ToUpperInvariant()
    $rawActor = ([string]$PrintRecord.PrintUser).Trim()
    $before = $printTime.AddMinutes(-1 * [int]$script:CorrelationWindowBeforeMinutes)
    $after = $printTime.AddMinutes([int]$script:CorrelationWindowAfterMinutes)

    $candidates = @($Contexts | Where-Object {
        $_.EventClass -eq $ClassName -and
        ([datetime]$_.TimeCreated) -ge $before -and
        ([datetime]$_.TimeCreated) -le $after
    })

    if (-not [string]::IsNullOrWhiteSpace($client)) {
        $clientCandidates = @($candidates | Where-Object {
            ([string]$_.WorkstationName).ToUpperInvariant() -eq $client -or
            ([string]$_.ComputerName).ToUpperInvariant() -eq $client -or
            ([string]$_.RawEventData).ToUpperInvariant().Contains($client)
        })
        if ($clientCandidates.Count -gt 0) { $candidates = $clientCandidates }
    }

    if ($rawActor -match '^\d+$') {
        $sessionCandidates = @($candidates | Where-Object { ([string]$_.SessionId) -eq $rawActor -or ([string]$_.RawEventData) -match ('\b' + [regex]::Escape($rawActor) + '\b') })
        if ($sessionCandidates.Count -gt 0) { $candidates = $sessionCandidates }
    }

    if ($RequireUser) {
        $candidates = @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.UserName) -and [string]$_.UserName -notmatch '^\d+$' -and [string]$_.UserName -notmatch '^(SYSTEM|ANONYMOUS LOGON|DWM-|UMFD-)' })
    }

    if ($candidates.Count -eq 0) { return $null }
    return @($candidates | Sort-Object -Property @{ Expression = { [math]::Abs((New-TimeSpan -Start ([datetime]$_.TimeCreated) -End $printTime).TotalSeconds) } } | Select-Object -First 1)[0]
}

function Add-MultisourceIdentityCorrelation {
    param(
        [AllowNull()][object[]]$PrintRecords,
        [AllowNull()][object[]]$ContextRecords
    )
    $prints = @($PrintRecords)
    $contexts = @($ContextRecords)
    if ($prints.Count -eq 0) { return @() }

    Write-Log ("Starting multisource identity correlation. PrintRecords={0}; ContextRecords={1}" -f $prints.Count,$contexts.Count)

    foreach ($r in $prints) {
        Initialize-IdentityCorrelationFields -Record $r
        $rawActor = ([string]$r.PrintUser).Trim()
        $r.SessionOrSpoolerId = if ($rawActor -match '^\d+$') { $rawActor } else { '' }
        $sources = New-Object System.Collections.ArrayList

        $lifecycle = @($contexts | Where-Object {
            $_.EventClass -eq 'PrintLifecycle' -and
            [math]::Abs((New-TimeSpan -Start ([datetime]$_.TimeCreated) -End ([datetime]$r.TimeCreated)).TotalMinutes) -le 10 -and
            ( [string]$_.RawEventData -like ('*' + [string]$r.PrinterName + '*') -or [string]$_.RawEventData -like ('*' + [string]$r.PrintJobId + '*') )
        })
        if ($lifecycle.Count -gt 0) {
            $r.PrintLifecycleEvents = ((@($lifecycle | Select-Object -ExpandProperty EventId -Unique | Sort-Object) | ForEach-Object { [string]$_ }) -join ';')
            [void]$sources.Add('PrintServiceLifecycle')
        }

        $ts = Find-NearestCorrelationContext -PrintRecord $r -Contexts $contexts -ClassName 'TerminalServicesSession' -RequireUser
        $sec = Find-NearestCorrelationContext -PrintRecord $r -Contexts $contexts -ClassName 'SecurityLogonContinuity' -RequireUser

        $selected = $null
        $method = ''
        $confidence = 'Unresolved'
        if ($null -ne $ts -and -not [string]::IsNullOrWhiteSpace([string]$ts.UserName)) {
            $selected = $ts
            $method = 'TerminalServicesSessionCorrelation'
            $confidence = 'High'
            [void]$sources.Add('TerminalServices')
        } elseif ($null -ne $sec -and -not [string]::IsNullOrWhiteSpace([string]$sec.UserName)) {
            $selected = $sec
            $method = 'SecurityLogonContinuityCorrelation'
            $confidence = 'Medium'
            [void]$sources.Add('Security')
        }

        if ($null -ne $selected) {
            $domainPrefix = if ([string]::IsNullOrWhiteSpace([string]$selected.DomainName)) { '' } else { ([string]$selected.DomainName + '\') }
            $resolved = $domainPrefix + [string]$selected.UserName
            $r.ResolvedPrintActor = $resolved
            $r.IdentityReconstructionMethod = $method
            $r.IdentityConfidence = $confidence
            $r.IdentityEvidenceSource = [string]$selected.EvidenceId
            $r.CorrelatedSecurityLogonId = [string]$selected.LogonId
            $r.CorrelatedSessionId = [string]$selected.SessionId
            $r.CorrelatedLogonType = [string]$selected.LogonType
            $r.CorrelatedIpAddress = [string]$selected.IpAddress
            $r.CorrelatedWorkstation = [string]$selected.WorkstationName
            $r.CorrelationWindowSeconds = [string][int][math]::Abs((New-TimeSpan -Start ([datetime]$selected.TimeCreated) -End ([datetime]$r.TimeCreated)).TotalSeconds)
        } elseif (-not [string]::IsNullOrWhiteSpace($rawActor) -and $rawActor -notmatch '^\d+$') {
            $r.ResolvedPrintActor = $rawActor
            $r.IdentityReconstructionMethod = 'DirectPayloadIdentity'
            $r.IdentityConfidence = 'High'
            $r.IdentityEvidenceSource = 'EventID307Payload'
        } elseif ($rawActor -match '^\d+$') {
            $r.ResolvedPrintActor = ('SESSION_OR_SPOOLER_ID:{0}' -f $rawActor)
            $r.IdentityReconstructionMethod = 'NumericIdentifierPreservedNoExternalMatch'
            $r.IdentityConfidence = 'Low'
            $r.IdentityEvidenceSource = 'EventID307Payload'
        } else {
            $r.ResolvedPrintActor = 'UNRESOLVED'
        }

        if ($sources.Count -gt 0) { $r.CorrelationSources = ((@($sources) | Sort-Object -Unique) -join ';') }
        $r.IdentityCorrelationSummary = ('Actor="{0}"; Method={1}; Confidence={2}; Sources={3}; SessionOrSpoolerId={4}; Lifecycle={5}' -f ([string]$r.ResolvedPrintActor),([string]$r.IdentityReconstructionMethod),([string]$r.IdentityConfidence),([string]$r.CorrelationSources),([string]$r.SessionOrSpoolerId),([string]$r.PrintLifecycleEvents))
    }

    Write-Log 'Multisource identity correlation completed.'
    return @($prints)
}

function Apply-PrintInfrastructureEnrichment {
    param([AllowNull()][object[]]$Records)
    $items = @($Records)
    if ($items.Count -eq 0) { return @() }

    $inventory = Resolve-PrintInfrastructureInventory
    foreach ($r in $items) {
        $printerName = [string]$r.PrinterName
        $queueName = [string]$r.QueueName
        $keyCandidates = @(
            (Get-PrinterInfrastructureKey -Name $printerName),
            (Get-PrinterInfrastructureKey -Name $queueName)
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $info = $null
        foreach ($k in $keyCandidates) {
            if ($inventory.ContainsKey($k)) { $info = $inventory[$k]; break }
        }

        if ($null -ne $info) {
            if ([string]::IsNullOrWhiteSpace([string]$r.PrinterPortName)) { $r.PrinterPortName = [string]$info.PortName }
            if ([string]::IsNullOrWhiteSpace([string]$r.PrinterIpAddress)) { $r.PrinterIpAddress = [string]$info.HostAddress }
            if ([string]::IsNullOrWhiteSpace([string]$r.PrinterDriverName)) { $r.PrinterDriverName = [string]$info.DriverName }
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterShareName' -Value ([string]$info.ShareName)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterLocation' -Value ([string]$info.Location)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterComment' -Value ([string]$info.Comment)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterShared' -Value ([string]$info.Shared)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterPublished' -Value ([string]$info.Published)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterStatus' -Value ([string]$info.Status)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrintProcessor' -Value ([string]$info.PrintProcessor)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterHostAddress' -Value ([string]$info.HostAddress)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterInfrastructureSource' -Value ([string]$info.InfrastructureSource)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterRiskCategory' -Value ([string]$info.RiskCategory)
        } else {
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterShareName' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterLocation' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterComment' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterShared' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterPublished' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterStatus' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrintProcessor' -Value ''
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterHostAddress' -Value ([string]$r.PrinterIpAddress)
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterInfrastructureSource' -Value 'EventOnly'
            Add-OrUpdateNoteProperty -InputObject $r -Name 'PrinterRiskCategory' -Value (Get-PrinterRiskCategory -PrinterName $printerName -ShareName '' -Location '' -Comment '')
        }
    }
    return @($items)
}

function Add-PrintBurstIndicators {
    param([AllowNull()][object[]]$Records)
    $items = @($Records)
    if ($items.Count -eq 0) { return @() }

    foreach ($r in $items) {
        if (-not ($r.PSObject.Properties.Name -contains 'PrintBurstIndicator')) {
            Add-Member -InputObject $r -NotePropertyName 'PrintBurstIndicator' -NotePropertyValue 'NO' -Force
        } else {
            $r.PrintBurstIndicator = 'NO'
        }
    }

    $groups = @($items | Group-Object -Property {
        $t = try { [datetime]$_.TimeCreated } catch { Get-Date }
        $bucket = $t.ToString('yyyyMMddHHmm')
        '{0}|{1}|{2}' -f ([string]$_.PrintUser).ToLowerInvariant(), ([string]$_.PrinterName).ToLowerInvariant(), $bucket
    })

    foreach ($g in $groups) {
        if (@($g.Group).Count -ge 5) {
            foreach ($r in @($g.Group)) { $r.PrintBurstIndicator = 'YES' }
        }
    }
    return @($items)
}

function Convert-LogParserPrintRowsToForensicRecords {
    param(
        [Parameter(Mandatory=$true)][object[]]$Rows,
        [Parameter(Mandatory=$true)][string]$EvtxPath,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [bool]$UseDateRange,
        [string]$UserFilter
    )

    $records = New-Object System.Collections.ArrayList
    $sourceChannel = Resolve-SourceChannelForEvidence -EvtxPath $EvtxPath -SourceMode $SourceMode

    foreach ($row in @($Rows)) {
        try {
            $eventId = 0
            [void][int]::TryParse([string]$row.EventID, [ref]$eventId)
            if ($eventId -ne 307) { continue }

            $recordId = 0L
            [void][int64]::TryParse([string]$row.RecordNumber, [ref]$recordId)

            $timeCreated = $null
            try { $timeCreated = [datetime]::Parse([string]$row.TimeGenerated) } catch { $timeCreated = Get-Date }
            if ($UseDateRange) {
                if ($timeCreated -lt $StartTime -or $timeCreated -gt $EndTime) { continue }
            }

            $strings = Split-LogParserStrings -Strings ([string]$row.Strings)
            $payload = Resolve-Print307PayloadFromStrings -Strings $strings
            $msgParts = Parse-Print307Message -Message ([string]$row.Message)

            $document = Get-FirstNonEmptyValue -Values @($payload.Document, $msgParts.Document)
            $printUser = Get-FirstNonEmptyValue -Values @($payload.PrintUser, $msgParts.PrintUser)
            $printerName = Get-FirstNonEmptyValue -Values @($payload.PrinterName, $msgParts.PrinterName)
            $clientComputer = Get-FirstNonEmptyValue -Values @($payload.ClientComputer, $msgParts.ClientComputer)
            $sizeBytes = Get-FirstNonEmptyValue -Values @($payload.SizeBytes, $msgParts.SizeBytes)
            $pages = Get-FirstNonEmptyValue -Values @($payload.Pages, $msgParts.Pages)
            $portName = Get-FirstNonEmptyValue -Values @($payload.PortName, $msgParts.PortName)

            $computer = Get-FirstNonEmptyValue -Values @($row.ComputerName, $script:MachineName)
            $provider = Get-FirstNonEmptyValue -Values @($row.SourceName, 'Microsoft-Windows-PrintService')
            $category = if ($script:EventCategory.ContainsKey($eventId)) { [string]$script:EventCategory[$eventId] } else { 'Print Job Activity' }
            $raw = 'Strings={0}' -f ([string]$row.Strings)
            $evidenceId = '{0}-{1}-{2}-{3}' -f $computer, $eventId, $recordId, (Get-Sha256String -Text $EvtxPath).Substring(0,8)
            $hashInput = '{0}|{1}|{2}|{3}|{4}|{5}' -f $evidenceId, $EvtxPath, $eventId, $recordId, $timeCreated.ToString('o'), $raw

            $obj = [PSCustomObject][ordered]@{
                EvidenceId      = [string]$evidenceId
                IntegrityHash   = [string](Get-Sha256String -Text $hashInput)
                ToolName        = [string]$script:ToolName
                ToolVersion     = [string]$script:ToolVersion
                SourceMode      = [string]$SourceMode
                SourceChannel   = [string]$sourceChannel
                SourceFile      = [string]$EvtxPath
                ComputerName    = [string]$computer
                EventId         = [int]$eventId
                EventCategory   = [string]$category
                RecordId        = [int64]$recordId
                TimeCreated     = [datetime]$timeCreated
                ProviderName    = [string]$provider
                ActorUser       = [string]$printUser
                ActorDomain     = ''
                TargetUser      = ''
                TargetDomain    = ''
                GroupName       = ''
                SubjectLogonId  = ''
                IpAddress       = [string]$clientComputer
                PrintJobId      = [string]$payload.JobId
                PrintDocument   = [string]$document
                PrintUser       = [string]$printUser
                ClientComputer  = [string]$clientComputer
                PrinterName     = [string]$printerName
                PrintSizeBytes  = [string]$sizeBytes
                PrintPages      = [string]$pages
                PrinterIpAddress = [string](Get-PrinterIpFromPortName -PortName $portName)
                PrinterPortName  = [string]$portName
                PrinterDriverName = ''
                PrintServerName  = [string]$computer
                QueueName        = [string]$printerName
                ClientWorkstation = [string](Normalize-ClientWorkstation -ClientComputer $clientComputer)
                EstimatedPrintDurationSeconds = ''
                PrintVolumeCategory = [string](Get-PrintVolumeCategory -Pages $pages -Bytes $sizeBytes)
                PrintBurstIndicator = 'NO'
                DocumentExtension = [string](Get-DocumentExtension -DocumentName $document)
                PrinterShareName = ''
                PrinterLocation = ''
                PrinterComment = ''
                PrinterShared = ''
                PrinterPublished = ''
                PrinterStatus = ''
                PrintProcessor = ''
                PrinterHostAddress = [string](Get-PrinterIpFromPortName -PortName $portName)
                PrinterInfrastructureSource = 'EventOnly'
                PrinterRiskCategory = [string](Get-PrinterRiskCategory -PrinterName $printerName -ShareName '' -Location '' -Comment '')
                RawEventData    = [string]$raw
                Message         = [string](([string]$row.Message) -replace "`r?`n", ' ')
            }

            if (-not [string]::IsNullOrWhiteSpace($UserFilter)) {
                $terms = @($UserFilter -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($terms.Count -gt 0 -and $terms[0] -ne '*') {
                    $haystack = ('{0} {1} {2} {3} {4}' -f $obj.PrintUser,$obj.PrintDocument,$obj.ClientComputer,$obj.PrinterName,$obj.Message)
                    $matched = $false
                    foreach ($term in $terms) { if ($haystack -like ('*' + $term + '*')) { $matched = $true; break } }
                    if (-not $matched) { continue }
                }
            }

            [void]$records.Add($obj)
        } catch {
            Write-Log "Skipped LogParser row during SQL-FIRST print normalization. Source='$EvtxPath'; Error=$($_.Exception.Message)" 'WARN'
        }
    }

    return @($records)
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
    $payload = Resolve-Print307PayloadFromXmlMap -Map $map
    $actorUser = Get-FirstNonEmptyValue -Values @($payload.PrintUser, (Get-MapValue -Map $map -Names @('SubjectUserName','AccountName','UserName')))
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
        PrintJobId      = [string]$payload.JobId
        PrintDocument   = [string]$payload.Document
        PrintUser       = [string]$payload.PrintUser
        ClientComputer  = [string]$payload.ClientComputer
        PrinterName     = [string]$payload.PrinterName
        PrintSizeBytes  = [string]$payload.SizeBytes
        PrintPages      = [string]$payload.Pages
        PrinterIpAddress = [string](Get-PrinterIpFromPortName -PortName $payload.PortName)
        PrinterPortName  = [string]$payload.PortName
        PrinterDriverName = ''
        PrintServerName  = [string]$computer
        QueueName        = [string]$payload.PrinterName
        ClientWorkstation = [string](Normalize-ClientWorkstation -ClientComputer $payload.ClientComputer)
        EstimatedPrintDurationSeconds = ''
        PrintVolumeCategory = [string](Get-PrintVolumeCategory -Pages $payload.Pages -Bytes $payload.SizeBytes)
        PrintBurstIndicator = 'NO'
        DocumentExtension = [string](Get-DocumentExtension -DocumentName $payload.Document)
        PrinterShareName = ''
        PrinterLocation = ''
        PrinterComment = ''
        PrinterShared = ''
        PrinterPublished = ''
        PrinterStatus = ''
        PrintProcessor = ''
        PrinterHostAddress = [string](Get-PrinterIpFromPortName -PortName $payload.PortName)
        PrinterInfrastructureSource = 'EventOnly'
        PrinterRiskCategory = [string](Get-PrinterRiskCategory -PrinterName $payload.PrinterName -ShareName '' -Location '' -Comment '')
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
    $filter = @{ Path = $EvtxPath }
    if (@($script:EventIds).Count -gt 0) { $filter.Id = [int[]]$script:EventIds }

    $sqlRows = @()
    $records = @()
    $usedSqlFullFieldExtraction = $false

    try {
        $sqlTempDir = Join-Path $env:TEMP ($script:ToolName + '-LogParser')
        $sqlCsv = Invoke-LogParserPrintAuditQuery -EvtxPath $EvtxPath -TempDir $sqlTempDir
        $sqlRows = @(Import-Csv -LiteralPath $sqlCsv -ErrorAction Stop)
        if ($sqlRows.Count -eq 0) {
            Write-Log "LogParser found no matching print audit events in '$EvtxPath'." 'INFO'
            return @()
        }

        $records = @(Convert-LogParserPrintRowsToForensicRecords `
            -Rows $sqlRows `
            -EvtxPath $EvtxPath `
            -SourceMode $SourceMode `
            -StartTime $StartTime `
            -EndTime $EndTime `
            -UseDateRange $UseDateRange `
            -UserFilter $UserFilter)

        $usedSqlFullFieldExtraction = $true
        Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; SQLFullFieldRecords={2}; HydratedEvents=0; Records={3}; UsedSqlFullFieldExtraction={4}" -f $EvtxPath, @($sqlRows).Count, @($records).Count, @($records).Count, $usedSqlFullFieldExtraction)
        return @($records)
    } catch {
        Write-Log "SQL-FIRST full-field extraction failed for '$EvtxPath'. Falling back to Get-WinEvent parser. Error: $($_.Exception.Message)" 'WARN'
    }

    $events = @()
    try { $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) }
    catch {
        if ($_.Exception.Message -match 'No events|não foi encontrado|No events were found') {
            Write-Log "No matching events found in '$EvtxPath'." 'INFO'
            return @()
        }
        throw
    }

    $recordsList = New-Object System.Collections.ArrayList
    $sourceChannel = Resolve-SourceChannelForEvidence -EvtxPath $EvtxPath -SourceMode $SourceMode
    foreach ($event in $events) {
        try {
            if ($UseDateRange) {
                if ($event.TimeCreated -lt $StartTime -or $event.TimeCreated -gt $EndTime) { continue }
            }
            $record = New-ForensicEvidenceRecord -Event $event -SourceFile $EvtxPath -SourceMode $SourceMode -SourceChannel $sourceChannel
            if (-not [string]::IsNullOrWhiteSpace($UserFilter)) {
                $terms = @($UserFilter -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                if ($terms.Count -gt 0 -and $terms[0] -ne '*') {
                    $haystack = ('{0} {1} {2} {3} {4} {5}' -f $record.ActorUser,$record.ActorDomain,$record.PrintUser,$record.PrintDocument,$record.PrinterName,$record.RawEventData)
                    $matched = $false
                    foreach ($term in $terms) { if ($haystack -like ('*' + $term + '*')) { $matched = $true; break } }
                    if (-not $matched) { continue }
                }
            }
            [void]$recordsList.Add($record)
        } catch {
            Write-Log "Skipped event during forensic fallback normalization. Source='$EvtxPath'; Error=$($_.Exception.Message)" 'WARN'
        }
    }
    Write-Log ("EVTX processing completed. Source='{0}'; SQLPreselected={1}; SQLFullFieldRecords=0; HydratedEvents={2}; Records={3}; UsedSqlFullFieldExtraction={4}" -f $EvtxPath, @($sqlRows).Count, @($events).Count, $recordsList.Count, $usedSqlFullFieldExtraction)
    return @($recordsList)
}

function Get-ForensicCsvColumns {
    return @(
        'EvidenceId','IntegrityHash','ToolName','ToolVersion','SourceMode','SourceChannel','SourceFile',
        'ComputerName','EventId','EventCategory','RecordId','TimeCreated','ProviderName',
        'ActorUser','ActorDomain','TargetUser','TargetDomain','GroupName','SubjectLogonId','IpAddress',
        'PrintJobId','PrintDocument','PrintUser','ClientComputer','PrinterName','PrintSizeBytes','PrintPages',
        'PrinterIpAddress','PrinterPortName','PrinterDriverName','PrintServerName','QueueName',
        'ClientWorkstation','EstimatedPrintDurationSeconds','PrintVolumeCategory','PrintBurstIndicator','DocumentExtension',
        'PrinterShareName','PrinterLocation','PrinterComment','PrinterShared','PrinterPublished','PrinterStatus',
        'PrintProcessor','PrinterHostAddress','PrinterInfrastructureSource','PrinterRiskCategory',
        'ActorClassification','ContinuityClass','TimelineId','ChronologyIndex','PreviousEvidenceId','ReconstructionSummary',
        'ResolvedPrintActor','IdentityReconstructionMethod','IdentityConfidence','SessionOrSpoolerId','IdentityEvidenceSource',
        'CorrelationSources','CorrelatedSecurityLogonId','CorrelatedSessionId','CorrelatedLogonType','CorrelatedIpAddress','CorrelatedWorkstation','CorrelationWindowSeconds','PrintLifecycleEvents','IdentityCorrelationSummary',
        'RawEventData','Message'
    )
}

function Export-ForensicCsv {
    param(
        [AllowNull()][object[]]$Records,
        [Parameter(Mandatory=$true)][string]$CsvPath
    )
    $columns = Get-ForensicCsvColumns
    $safeRecords = @($Records)
    if ($safeRecords.Count -eq 0) {
        $empty = [PSCustomObject]([ordered]@{})
        foreach ($c in $columns) { Add-Member -InputObject $empty -NotePropertyName $c -NotePropertyValue '' }
        @($empty) | Select-Object $columns | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
        $lines = Get-Content -LiteralPath $CsvPath -ErrorAction SilentlyContinue
        if ($lines.Count -gt 0) { Set-Content -LiteralPath $CsvPath -Value $lines[0] -Encoding UTF8 }
    } else {
        $safeRecords | Select-Object $columns | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    }
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
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
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
    $timelineRecords = @(Add-PrintTimelineReconstruction -Records @($allRecords))
    $correlationEvidence = @(Read-MultisourceCorrelationEvidence -EvtxPaths @($sources) -SourceMode $mode -StartTime $StartTime -EndTime $EndTime -UseDateRange $UseDateRange)
    $identityRecords = @(Add-MultisourceIdentityCorrelation -PrintRecords $timelineRecords -ContextRecords $correlationEvidence)
    $burstRecords = @(Add-PrintBurstIndicators -Records $identityRecords)
    $finalRecords = @(Apply-PrintInfrastructureEnrichment -Records $burstRecords)
    $csvPath = Join-Path $OutputDir ('{0}-{1}.csv' -f $script:ToolName, (Get-Timestamp))
    Export-ForensicCsv -Records @($finalRecords) -CsvPath $csvPath
    $script:LastReport = $csvPath
    Write-Log ("Forensic audit completed. Records={0}; Csv='{1}'" -f @($finalRecords).Count, $csvPath)
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
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
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
try {
    $script:ResolvedLiveChannelPath = Resolve-PrintServiceChannelPath
    Write-Log "Resolved live PrintService channel path during startup: $($script:ResolvedLiveChannelPath)"
} catch { Write-Log "Startup channel resolution failed: $($_.Exception.Message)" 'WARN' }
try {
    $lp = Resolve-LogParserPath
    Write-Log "LogParser available for SQL-first preselection: $lp"
} catch { Write-Log "LogParser not available. Get-WinEvent fallback will be used. Error: $($_.Exception.Message)" 'WARN' }

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

Add-Label 'Resolved Live EVTX:' 200 22 130 | Out-Null
$txtResolvedChannel = New-Object System.Windows.Forms.TextBox
$txtResolvedChannel.Location = New-Object System.Drawing.Point(330,20)
$txtResolvedChannel.Size = New-Object System.Drawing.Size(400,24)
$txtResolvedChannel.ReadOnly = $true
$form.Controls.Add($txtResolvedChannel)
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
$script:StatusLabel.Size = New-Object System.Drawing.Size(500,22)
$form.Controls.Add($script:StatusLabel)
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(20,465)
$script:ProgressBar.Size = New-Object System.Drawing.Size(480,18)
$script:ProgressBar.Style = 'Continuous'
$form.Controls.Add($script:ProgressBar)

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

function Add-UiLog { param([string]$Message) $txtStatus.AppendText(('[{0}] {1}{2}' -f (Get-Date -Format 'HH:mm:ss'), $Message, [Environment]::NewLine)) }
function Set-Busy { param([bool]$Busy) $btnStart.Enabled = -not $Busy; $btnClose.Enabled = -not $Busy; $form.Cursor = if ($Busy) { 'WaitCursor' } else { 'Default' }; if ($script:StatusLabel) { $script:StatusLabel.Text = if ($Busy) { 'Running analysis...' } else { 'Ready.' } }; if ($script:ProgressBar) { $script:ProgressBar.Style = if ($Busy) { 'Marquee' } else { 'Continuous' } } }

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
        $resolved = Resolve-PrintServiceChannelPath
        $txtResolvedChannel.Text = $resolved
        $msg = "Manual Resolve Channel completed. Channel='$($script:LiveChannelName)'; ResolvedPath='$resolved'"
        Write-Log $msg
        Show-InfoBox $msg
    } catch {
        $msg = "Resolve Channel failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Show-ErrorBox $msg
    }
}.GetNewClosure())

$chkLive.Add_CheckedChanged({
    $archive = -not $chkLive.Checked
    $txtArchive.Enabled = $archive
    $btnBrowseArchive.Enabled = $archive
    $chkSub.Enabled = $archive
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

$archive = -not $chkLive.Checked
$txtArchive.Enabled = $archive
$btnBrowseArchive.Enabled = $archive
$chkSub.Enabled = $archive
$form.Add_Shown({
    try {
        $resolved = Resolve-PrintServiceChannelPath
        $txtResolvedChannel.Text = $resolved
        Write-Log "Resolved live PrintService channel path during GUI startup: $resolved"
        Write-Log 'GUI loaded. Runtime textbox logging is active.'
        Write-Log "Script version: $($script:ToolVersion)"
        Write-Log "Live channel name: $($script:LiveChannelName)"
    } catch { Write-Log "GUI startup channel resolution failed: $($_.Exception.Message)" 'WARN' }
}.GetNewClosure())
$form.Add_FormClosed({ Write-Log "========== END: $($script:ToolTitle) ==========" }.GetNewClosure())
[void]$form.ShowDialog()

# End of script
