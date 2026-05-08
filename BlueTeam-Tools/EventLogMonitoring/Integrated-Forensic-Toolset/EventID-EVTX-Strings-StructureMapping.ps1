<#
.SYNOPSIS
    EventID-EVTX-Strings-StructureMapping.ps1 - Enterprise and forensic-grade EVTX Strings structure mapping tool.

.DESCRIPTION
    Unified Windows EVTX forensic utility for EventID inventory, Strings token mapping,
    EventData structure discovery, and parser-engineering support across selectable
    Windows event log channels and offline EVTX evidence files.

    This production baseline helps the analyst identify how each EventID serializes its
    EventData fields into the LogParser Strings field, producing dynamically reconstructed CSV outputs
    suitable for parser construction, DFIR validation, audit review, and evidence
    normalization engineering.

    The toolkit supports live channel snapshot acquisition and offline archived EVTX
    analysis using a PATH-AGNOSTIC archive pipeline.

    The archive workflow accepts .evtx files from any evidence location, including local folders,
    external drives, mounted forensic images, network shares, and exported case repositories.
    Offline analysis is strictly separated from live acquisition and uses absolute string EVTX
    paths only.

    Core capabilities:
      - User-selectable Windows EVTX channel mapping.
      - Live channel snapshot acquisition via wevtutil.exe.
      - Resolve Channel function to identify current live EVTX paths.
      - PATH-AGNOSTIC archived EVTX processing.
      - Recursive offline EVTX folder enumeration.
      - String-only EVTX path pipeline for parser functions.
      - EventID inventory by source file.
      - Query-2-style positional Strings mapping with dynamic token schema reconstruction.
      - EXTRACT_TOKEN(Strings, 0..N, '|') CSV columns generated from discovered EventID token depth.
      - SQL-FIRST LogParser extraction with Get-WinEvent XML fallback continuity.
      - Provider-agnostic XML EventData/UserData name/value auxiliary schema discovery.
      - Canonical field lineage mapping: XML field name ↔ token index ↔ EXTRACT_TOKEN parser expression.
      - XML structure classification for schema discovery.
      - Stable forensic CSV evidence schema with dynamic String_XX token columns.
      - EvidenceId and SHA-256 IntegrityHash generation.
      - Date range filtering.
      - EventID filtering.
      - Provider filtering.
      - Text filtering.
      - Structured execution logging under C:\Logs-TEMP.
      - Windows Forms GUI with safe execution wrappers.
      - PowerShell 5.1 compatibility.

.EVENTIDS
    Dynamic by selected EVTX channel and optional EventID filter.

    The tool is intentionally EventID-agnostic and is designed to discover the Strings
    structure of any EventID present in the selected source.

.OUTPUTS
    CSV reports exported by default to the current user's Documents folder:
      - EventID inventory report.
      - Dynamic Strings structure mapping report.
      - Schema intelligence report with discovered token depth and sparse-token analytics.
      - Canonical field lineage report linking XML field names to String_XX token positions.
      - Provider-agnostic XML auxiliary mapping report when LogParser fallback is explicitly used.

    Execution log exported by default to C:\Logs-TEMP\<script-name>.log.

.REQUIREMENTS
    - Windows PowerShell 5.1 or later.
    - Administrator or equivalent event log access rights recommended.
    - Access to selected event log channels or readable .evtx evidence files.
    - For live mode, access to local event log channels.
    - For archive mode, readable .evtx evidence files.
    - Log Parser 2.2 installed locally for SQL-FIRST processing.
    - Get-WinEvent available for XML fallback continuity.

.AUTHOR
    Luiz Hamilton Roberto da Silva - @brazilianscriptguy

.VERSION
    2026-05-08-v1.2.0-PRODUCTION-CANONICAL-FIELD-LINEAGE-MAPPING

.NOTES
    Production baseline aligned with the enterprise/DFIR EVTX toolkit model:
      - SQL-FIRST EVTX extraction architecture.
      - PATH-AGNOSTIC archive processing.
      - Strict separation between live acquisition and offline evidence analysis.
      - No FileInfo or descriptor-object leakage into EVTX processing functions.
      - Fixed-schema forensic export suitable for DFIR, audit evidence, and SIEM ingestion.
      - Designed to support parser engineering before field-specific forensic reconstruction.
      - Dynamic token ceiling discovery before final Query-2-style EXTRACT_TOKEN export.
      - Canonical XML field-to-String token lineage mapping for parser blueprint generation.
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Global State

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
if ([string]::IsNullOrWhiteSpace($script:ScriptName)) {
    $script:ScriptName = 'EventID-EVTX-Strings-StructureMapping'
}

$script:ScriptVersion = '2026-05-08-v1.2.0-PRODUCTION-CANONICAL-FIELD-LINEAGE-MAPPING'
$script:LogDir = 'C:\Logs-TEMP'
$script:LogPath = Join-Path -Path $script:LogDir -ChildPath ($script:ScriptName + '.log')
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:TempRoot = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'EventID-EVTX-Strings-StructureMapping-Snapshots'

$script:CommonChannels = @(
    'Application',
    'System',
    'Security',
    'Setup',
    'Windows PowerShell',
    'Microsoft-Windows-PowerShell/Operational',
    'Microsoft-Windows-PrintService/Operational',
    'Microsoft-Windows-PrintService/Admin',
    'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
    'Microsoft-Windows-TaskScheduler/Operational',
    'Microsoft-Windows-Windows Defender/Operational',
    'Microsoft-Windows-Sysmon/Operational',
    'Microsoft-Windows-WMI-Activity/Operational',
    'Microsoft-Windows-DNS-Client/Operational',
    'Microsoft-Windows-Dhcp-Client/Operational',
    'Microsoft-Windows-SMBClient/Security',
    'Microsoft-Windows-SmbClient/Operational',
    'Microsoft-Windows-SMBServer/Security',
    'Microsoft-Windows-WinRM/Operational',
    'Directory Service',
    'DNS Server',
    'DFS Replication'
)

#endregion Global State

#region Console Handling

function Hide-ConsoleWindow {
    try {
        if ($ShowConsole) {
            return
        }

        Add-Type -Namespace NativeMethods -Name ConsoleWindow -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern System.IntPtr GetConsoleWindow();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@ -ErrorAction SilentlyContinue

        $handle = [NativeMethods.ConsoleWindow]::GetConsoleWindow()
        if ($handle -ne [IntPtr]::Zero) {
            [void][NativeMethods.ConsoleWindow]::ShowWindow($handle, 0)
        }
    }
    catch {
        # Console hiding must never block DFIR execution.
    }
}

#endregion Console Handling

#region Logging

function Initialize-Log {
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) {
            New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
        }

        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ''
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ('[{0}] [INFO] ========== START: {1} ==========' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $script:ScriptName)
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ('[{0}] [INFO] Script version: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $script:ScriptVersion)
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value ('[{0}] [INFO] PowerShell version: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PSVersionTable.PSVersion.ToString())
    }
    catch {
        # Logging must be best-effort.
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) {
            New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
        }

        $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -Value $line
    }
    catch {
        # Never crash on logging failure.
    }
}

#endregion Logging

#region Utility

function Show-Message {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Title = $script:ScriptName,

        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

function Test-IsWindows {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $Value
    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, '_')
    }

    $safe = $safe.Replace('/', '_').Replace('\', '_').Replace(':', '_')
    return $safe
}

function ConvertTo-SqlLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return $Value.Replace("'", "''")
}

function New-EvidenceId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Seed
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Seed)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-StringHash {
    param(
        [AllowNull()]
        [string]$Value
    )

    if ($null -eq $Value) {
        $Value = ''
    }

    return New-EvidenceId -Seed $Value
}

function Get-TokenCount {
    param(
        [AllowNull()]
        [string]$StringsRaw
    )

    if ([string]::IsNullOrEmpty($StringsRaw)) {
        return 0
    }

    return @($StringsRaw -split '\|', -1).Count
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

#endregion Utility

#region Evidence Source Handling

function Resolve-ChannelEvtxPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Channel
    )

    try {
        $output = & wevtutil.exe gl $Channel 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "wevtutil gl failed for channel '$Channel': $($output -join ' ')"
        }

        $logFileLine = @($output | Where-Object { $_ -match '^\s*logFileName\s*:' } | Select-Object -First 1)
        if ($logFileLine.Count -eq 0) {
            return ''
        }

        $value = ($logFileLine[0] -replace '^\s*logFileName\s*:\s*', '').Trim()
        return [Environment]::ExpandEnvironmentVariables($value)
    }
    catch {
        Write-Log -Level 'WARN' -Message ("Unable to resolve live EVTX path for channel '{0}'. {1}" -f $Channel, $_.Exception.Message)
        return ''
    }
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Channel
    )

    Ensure-Directory -Path $script:TempRoot

    $safeChannel = ConvertTo-SafeFileName -Value $Channel
    $snapshot = Join-Path -Path $script:TempRoot -ChildPath ('{0}-{1}-{2}.evtx' -f $safeChannel, (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8)))

    Write-Log -Level 'INFO' -Message ("Exporting live channel snapshot. Channel='{0}', Snapshot='{1}'" -f $Channel, $snapshot)

    $output = & wevtutil.exe epl $Channel $snapshot 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        throw "Failed to export live channel '$Channel'. wevtutil output: $($output -join ' ')"
    }

    Write-Log -Level 'INFO' -Message ("Live channel snapshot exported successfully. Snapshot='{0}'" -f $snapshot)

    return $snapshot
}

function Get-ArchiveEvtxPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [bool]$Recurse
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw 'Archive input path is empty.'
    }

    $absolute = [IO.Path]::GetFullPath($InputPath)

    if (Test-Path -LiteralPath $absolute -PathType Leaf) {
        if ([IO.Path]::GetExtension($absolute) -ne '.evtx') {
            throw "Archive file is not an .evtx file: $absolute"
        }
        return @($absolute)
    }

    if (Test-Path -LiteralPath $absolute -PathType Container) {
        $option = if ($Recurse) { [IO.SearchOption]::AllDirectories } else { [IO.SearchOption]::TopDirectoryOnly }
        $files = [IO.Directory]::GetFiles($absolute, '*.evtx', $option)
        return @($files | Sort-Object)
    }

    throw "Archive input path does not exist: $absolute"
}

#endregion Evidence Source Handling

#region LogParser SQL-FIRST

function Resolve-LogParserPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Log Parser 2.2\LogParser.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Log Parser 2.2\LogParser.exe'),
        'C:\Program Files\Log Parser 2.2\LogParser.exe',
        'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe'
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $cmd = Get-Command -Name 'LogParser.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    return ''
}

function ConvertTo-ProcessArgumentString {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $escaped = New-Object System.Collections.Generic.List[string]

    foreach ($arg in $Arguments) {
        if ($null -eq $arg) {
            continue
        }

        $value = [string]$arg
        if ($value.Length -eq 0) {
            [void]$escaped.Add('\"\"')
            continue
        }

        if ($value -match '[\s\"\&\(\)\[\]\{\}\^=;!,`~]') {
            $value = $value.Replace('\', '\\').Replace('"', '\"')
            [void]$escaped.Add('"{0}"' -f $value)
        }
        else {
            [void]$escaped.Add($value)
        }
    }

    return ($escaped -join ' ')
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "External process not found: $FilePath"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    Write-Log -Level 'DEBUG' -Message ("External process command line: `"{0}`" {1}" -f $psi.FileName, $psi.Arguments)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Invoke-LogParserCsvQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $logParser = Resolve-LogParserPath
    if ([string]::IsNullOrWhiteSpace($logParser)) {
        throw 'LogParser.exe was not found. Install Microsoft Log Parser 2.2 or use XML fallback.'
    }

    Write-Log -Level 'INFO' -Message ("Executing SQL-FIRST LogParser query. Output='{0}'" -f $OutputPath)
    Write-Log -Level 'DEBUG' -Message ("LogParser query: {0}" -f $Query)

    $arguments = @(
        $Query,
        '-i:EVT',
        '-o:CSV',
        '-headers:ON',
        '-q:ON',
        '-stats:OFF'
    )

    $result = Invoke-ExternalProcess -FilePath $logParser -Arguments $arguments

    if ($result.ExitCode -ne 0) {
        Write-Log -Level 'ERROR' -Message ("LogParser failed. ExitCode={0}; StdErr={1}; StdOut={2}" -f $result.ExitCode, $result.StdErr, $result.StdOut)
        throw "LogParser failed with exit code $($result.ExitCode). $($result.StdErr)"
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "LogParser completed but output CSV was not created: $OutputPath"
    }

    Write-Log -Level 'INFO' -Message ("LogParser output created. Output='{0}'" -f $OutputPath)
}

function New-EventIdInventorySql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePattern,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [datetime]$StartTime,

        [datetime]$EndTime
    )

    $source = ConvertTo-SqlLiteral -Value $SourcePattern
    $output = ConvertTo-SqlLiteral -Value $OutputPath

    $where = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($EventIdFilter)) {
        $ids = @($EventIdFilter -split '[,; ]+' | Where-Object { $_ -match '^\d+$' })
        if ($ids.Count -gt 0) {
            [void]$where.Add(('EventID IN ({0})' -f ($ids -join ';')))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProviderFilter)) {
        [void]$where.Add(("SourceName LIKE '%{0}%'" -f (ConvertTo-SqlLiteral -Value $ProviderFilter)))
    }

    if ($StartTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $StartTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    if ($EndTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $EndTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    $whereSql = ''
    if ($where.Count -gt 0) {
        $whereSql = ' WHERE ' + ($where -join ' AND ')
    }

    return @"
SELECT
  [EventLog] AS SourceFile,
  EventID AS EventId,
  SourceName AS ProviderName,
  COUNT(*) AS EventCount
INTO '$output'
FROM '$source'
$whereSql
GROUP BY [EventLog], EventID, SourceName
ORDER BY EventCount DESC
"@.Trim()
}


function New-StringsDiscoverySql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePattern,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [int]$MaxRows
    )

    $source = ConvertTo-SqlLiteral -Value $SourcePattern
    $output = ConvertTo-SqlLiteral -Value $OutputPath
    $where = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($EventIdFilter)) {
        $ids = @($EventIdFilter -split '[,; ]+' | Where-Object { $_ -match '^\d+$' })
        if ($ids.Count -gt 0) {
            [void]$where.Add(('EventID IN ({0})' -f ($ids -join ';')))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProviderFilter)) {
        [void]$where.Add(("SourceName LIKE '%{0}%'" -f (ConvertTo-SqlLiteral -Value $ProviderFilter)))
    }

    if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
        $safeText = ConvertTo-SqlLiteral -Value $TextFilter
        [void]$where.Add(("(Strings LIKE '%{0}%' OR Message LIKE '%{0}%')" -f $safeText))
    }

    if ($StartTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $StartTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    if ($EndTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $EndTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    $whereSql = ''
    if ($where.Count -gt 0) {
        $whereSql = ' WHERE ' + ($where -join ' AND ')
    }

    $topSql = ''
    if ($MaxRows -gt 0) {
        $topSql = "TOP $MaxRows "
    }

    return @"
SELECT $topSql
  [EventLog] AS SourceFile,
  TimeGenerated AS TimeGenerated,
  RecordNumber AS RecordNumber,
  EventID AS EventId,
  SourceName AS ProviderName,
  ComputerName AS ComputerName,
  Strings AS StringsRaw
INTO '$output'
FROM '$source'
$whereSql
ORDER BY TimeGenerated ASC
"@.Trim()
}

function New-StringsMappingSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePattern,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [int]$MaxTokens,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [int]$MaxRows
    )

    $source = ConvertTo-SqlLiteral -Value $SourcePattern
    $output = ConvertTo-SqlLiteral -Value $OutputPath

    # Query-2-style positional mapping: Strings is the primary evidence-mapping source.
    # XML discovery is intentionally not used here because parser engineering requires
    # the exact LogParser Strings token layout: EXTRACT_TOKEN(Strings, 0..N, '|').
    $select = New-Object System.Collections.Generic.List[string]
    [void]$select.Add('  [EventLog] AS SourceFile')
    [void]$select.Add('  TimeGenerated AS TimeGenerated')
    [void]$select.Add('  TimeWritten AS TimeWritten')
    [void]$select.Add('  RecordNumber AS RecordNumber')
    [void]$select.Add('  EventID AS EventId')
    [void]$select.Add('  EventType AS EventType')
    [void]$select.Add('  SourceName AS ProviderName')
    [void]$select.Add('  ComputerName AS ComputerName')
    [void]$select.Add('  SID AS SID')
    [void]$select.Add('  Strings AS StringsRaw')
    [void]$select.Add('  Message AS Message')

    for ($i = 0; $i -lt $MaxTokens; $i++) {
        [void]$select.Add(("  EXTRACT_TOKEN(Strings, {0}, '|') AS String_{1:00}" -f $i, $i))
    }

    $where = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($EventIdFilter)) {
        $ids = @($EventIdFilter -split '[,; ]+' | Where-Object { $_ -match '^\d+$' })
        if ($ids.Count -gt 0) {
            [void]$where.Add(('EventID IN ({0})' -f ($ids -join ';')))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ProviderFilter)) {
        [void]$where.Add(("SourceName LIKE '%{0}%'" -f (ConvertTo-SqlLiteral -Value $ProviderFilter)))
    }

    if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
        $safeText = ConvertTo-SqlLiteral -Value $TextFilter
        [void]$where.Add(("(Strings LIKE '%{0}%' OR Message LIKE '%{0}%')" -f $safeText))
    }

    if ($StartTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $StartTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    if ($EndTime -ne [datetime]::MinValue) {
        [void]$where.Add(("TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $EndTime.ToString('yyyy-MM-dd HH:mm:ss')))
    }

    $whereSql = ''
    if ($where.Count -gt 0) {
        $whereSql = ' WHERE ' + ($where -join ' AND ')
    }

    $topSql = ''
    if ($MaxRows -gt 0) {
        $topSql = "TOP $MaxRows "
    }

    return @"
SELECT $topSql
$($select -join ",`r`n")
INTO '$output'
FROM '$source'
$whereSql
ORDER BY TimeGenerated ASC
"@.Trim()
}

#endregion LogParser SQL-FIRST

#region CSV Post Processing


function Get-MaxTokenCountFromCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [int]$SafetyMaxTokens
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        throw "Discovery CSV path not found: $CsvPath"
    }

    $max = 0
    $rows = @(Import-Csv -LiteralPath $CsvPath)
    foreach ($row in $rows) {
        $count = Get-TokenCount -StringsRaw $row.StringsRaw
        if ($count -gt $max) { $max = $count }
    }

    if ($max -lt 1) { $max = 1 }
    if ($SafetyMaxTokens -gt 0 -and $max -gt $SafetyMaxTokens) {
        Write-Log -Level 'WARN' -Message ("Discovered token count exceeded safety ceiling. Discovered={0}; Ceiling={1}; UsingCeiling={1}" -f $max, $SafetyMaxTokens)
        $max = $SafetyMaxTokens
    }

    return $max
}

function Export-StringsSchemaIntelligence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MappingCsvPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [int]$DiscoveredMaxTokens,

        [Parameter(Mandatory = $true)]
        [int]$SafetyMaxTokens,

        [Parameter(Mandatory = $true)]
        [string]$ParserEngine
    )

    if (-not (Test-Path -LiteralPath $MappingCsvPath)) {
        throw "Mapping CSV path not found for schema intelligence: $MappingCsvPath"
    }

    $rows = @(Import-Csv -LiteralPath $MappingCsvPath)
    $groups = $rows | Group-Object SourceFile, EventId, ProviderName
    $out = New-Object System.Collections.Generic.List[object]

    foreach ($group in $groups) {
        $first = $group.Group | Select-Object -First 1
        $maxTokenCount = 0
        $tokenPresence = @{}
        $layoutSet = @{}

        foreach ($row in $group.Group) {
            $tokens = @()
            if (-not [string]::IsNullOrEmpty($row.StringsRaw)) {
                $tokens = @(([string]$row.StringsRaw).Split('|'))
            }

            $tokenCount = $tokens.Count
            if ($tokenCount -eq 1 -and [string]::IsNullOrEmpty($tokens[0])) { $tokenCount = 0 }
            if ($tokenCount -gt $maxTokenCount) { $maxTokenCount = $tokenCount }

            $layoutKey = "Tokens=$tokenCount"
            if (-not $layoutSet.ContainsKey($layoutKey)) { $layoutSet[$layoutKey] = 0 }
            $layoutSet[$layoutKey]++

            for ($i = 0; $i -lt $DiscoveredMaxTokens; $i++) {
                $name = ('String_{0:00}' -f $i)
                if ($row.PSObject.Properties.Name -contains $name) {
                    $value = [string]$row.$name
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        if (-not $tokenPresence.ContainsKey($name)) { $tokenPresence[$name] = 0 }
                        $tokenPresence[$name]++
                    }
                }
            }
        }

        $populated = @($tokenPresence.Keys | Sort-Object)
        $tokenPopulationMap = ($populated | ForEach-Object { '{0}={1}' -f $_, $tokenPresence[$_] }) -join ';'
        $nullTokenCount = [Math]::Max(0, ($DiscoveredMaxTokens - $populated.Count))
        $layoutSummary = ($layoutSet.Keys | Sort-Object | ForEach-Object { '{0}:{1}' -f $_, $layoutSet[$_] }) -join ';'
        $templateSeed = '{0}|{1}|{2}|{3}|{4}' -f $first.SourceFile, $first.EventId, $first.ProviderName, $DiscoveredMaxTokens, $layoutSummary

        [void]$out.Add([pscustomobject]@{
            SourceFile            = $first.SourceFile
            EventId               = $first.EventId
            ProviderName          = $first.ProviderName
            EventCount            = $group.Count
            ParserEngine          = $ParserEngine
            DiscoveredMaxTokens   = $DiscoveredMaxTokens
            EventIdMaxTokenCount  = $maxTokenCount
            SafetyMaxTokens       = $SafetyMaxTokens
            PopulatedTokenColumns = ($populated -join '|')
            TokenPopulationMap    = $tokenPopulationMap
            NullTokenColumnCount  = $nullTokenCount
            DistinctTokenLayouts  = $layoutSummary
            XmlTemplateHash       = Get-StringHash -Value $templateSeed
            SchemaPurpose         = 'Dynamic Strings schema reconstruction for parser engineering'
        })
    }

    $out | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log -Level 'INFO' -Message ("Schema intelligence exported. Output='{0}', Rows={1}" -f $OutputPath, $out.Count)
}

function Add-ForensicColumnsToCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $true)]
        [string]$SourceMode,

        [Parameter(Mandatory = $true)]
        [string]$ChannelOrSource,

        [Parameter(Mandatory = $true)]
        [string]$ParserEngine
    )

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        throw "CSV path not found for post-processing: $CsvPath"
    }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    $outRows = New-Object System.Collections.Generic.List[object]
    $index = 0

    foreach ($row in $rows) {
        $index++

        $seed = '{0}|{1}|{2}|{3}|{4}|{5}' -f $SourceMode, $ChannelOrSource, $row.SourceFile, $row.RecordNumber, $row.EventId, $row.TimeGenerated
        $evidenceId = New-EvidenceId -Seed $seed
        $integritySeed = ($row.PSObject.Properties | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join '|'
        $hash = Get-StringHash -Value $integritySeed
        $tokenCount = Get-TokenCount -StringsRaw $row.StringsRaw

        $ordered = [ordered]@{
            EvidenceId       = $evidenceId
            IntegrityHash    = $hash
            ParserEngine     = $ParserEngine
            SourceMode       = $SourceMode
            ChannelOrSource  = $ChannelOrSource
            ChronologyIndex  = $index
            StringTokenCount = $tokenCount
        }

        foreach ($prop in $row.PSObject.Properties) {
            $ordered[$prop.Name] = $prop.Value
        }

        [void]$outRows.Add([pscustomobject]$ordered)
    }

    $outRows | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Log -Level 'INFO' -Message ("Forensic columns added to CSV. CsvPath='{0}', Rows={1}" -f $CsvPath, $outRows.Count)
}


#endregion CSV Post Processing

#region Provider-Agnostic XML Normalization

function Get-XmlNodeTextSafe {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Node
    )

    try {
        if ($null -ne $Node.'#text') {
            return [string]$Node.'#text'
        }
    }
    catch {
        # Continue with InnerText fallback.
    }

    try {
        return [string]$Node.InnerText
    }
    catch {
        return ''
    }
}

function Get-XmlNodeFieldNameSafe {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlNode]$Node,

        [Parameter(Mandatory = $true)]
        [int]$Position
    )

    $name = ''

    try {
        $name = [string]$Node.GetAttribute('Name')
    }
    catch {
        $name = ''
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        try {
            $name = [string]$Node.Name
        }
        catch {
            $name = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = 'Field_{0:00}' -f $Position
    }

    return $name
}

function Get-ProviderAgnosticEventPayload {
    param(
        [Parameter(Mandatory = $true)]
        [xml]$Xml
    )

    $strings = New-Object System.Collections.Generic.List[string]
    $nameValue = New-Object System.Collections.Generic.List[string]
    $fieldNames = New-Object System.Collections.Generic.List[string]
    $structureParts = New-Object System.Collections.Generic.List[string]
    $position = 0
    $structureType = 'EmptyPayload'

    try {
        # Provider-agnostic and StrictMode-safe XML discovery.
        # Avoid direct dot-property access such as $Xml.Event.EventData because some providers
        # expose UserData/provider-specific wrappers or omit EventData entirely.
        $eventDataNodes = @($Xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="EventData"]/*[local-name()="Data"]'))
        $userDataContainers = @($Xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="UserData"]'))

        if ($eventDataNodes.Count -gt 0) {
            $structureType = 'EventData'
            [void]$structureParts.Add('EventData/Data')

            foreach ($node in $eventDataNodes) {
                if ($null -eq $node) { continue }

                $name = Get-XmlNodeFieldNameSafe -Node $node -Position $position
                $value = Get-XmlNodeTextSafe -Node $node

                [void]$strings.Add($value)
                [void]$fieldNames.Add(('{0:00}:{1}' -f $position, $name))
                [void]$nameValue.Add(('{0:00}:{1}={2}' -f $position, $name, $value))
                $position++
            }
        }
        elseif ($userDataContainers.Count -gt 0) {
            $structureType = 'UserData'
            [void]$structureParts.Add('UserData')

            foreach ($container in $userDataContainers) {
                foreach ($wrapper in @($container.ChildNodes)) {
                    if ($null -eq $wrapper) { continue }
                    if ($wrapper.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                    [void]$structureParts.Add(('UserData/{0}' -f $wrapper.Name))
                    $childElementCount = 0

                    foreach ($node in @($wrapper.ChildNodes)) {
                        if ($null -eq $node) { continue }
                        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

                        $childElementCount++
                        $name = Get-XmlNodeFieldNameSafe -Node $node -Position $position
                        $value = Get-XmlNodeTextSafe -Node $node

                        [void]$strings.Add($value)
                        [void]$fieldNames.Add(('{0:00}:{1}' -f $position, $name))
                        [void]$nameValue.Add(('{0:00}:{1}={2}' -f $position, $name, $value))
                        $position++
                    }

                    if ($childElementCount -eq 0) {
                        $value = Get-XmlNodeTextSafe -Node $wrapper
                        if (-not [string]::IsNullOrWhiteSpace($value)) {
                            [void]$strings.Add($value)
                            [void]$fieldNames.Add(('{0:00}:{1}' -f $position, $wrapper.Name))
                            [void]$nameValue.Add(('{0:00}:{1}={2}' -f $position, $wrapper.Name, $value))
                            $position++
                        }
                    }
                }
            }
        }

        if ($strings.Count -eq 0) {
            $renderingInfo = @($Xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="RenderingInfo"]/*[local-name()="Message"]'))
            if ($renderingInfo.Count -gt 0) {
                $structureType = 'RenderingInfoOnly'
                [void]$structureParts.Add('RenderingInfo/Message')
            }
            else {
                $structureType = 'NoEventDataOrUserData'
            }
        }
    }
    catch {
        $structureType = 'XmlDiscoveryError'
        [void]$structureParts.Add('XmlDiscoveryError')
        Write-Log -Level 'WARN' -Message ("Provider-agnostic XML payload parsing warning: {0}" -f $_.Exception.Message)
    }

    $structurePath = ($structureParts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ' || '
    if ([string]::IsNullOrWhiteSpace($structurePath)) {
        $structurePath = $structureType
    }

    return [pscustomobject]@{
        StructureType         = $structureType
        StructurePath         = $structurePath
        Strings               = @($strings)
        NameValueMap          = ($nameValue -join ' || ')
        XmlFieldNameSequence  = ($fieldNames -join ' || ')
        TokenCount            = $strings.Count
    }
}


function Convert-XmlFieldSequenceToMap {
    param(
        [string]$XmlFieldNameSequence
    )

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($XmlFieldNameSequence)) {
        return $map
    }

    foreach ($part in @($XmlFieldNameSequence -split '\s*\|\|\s*')) {
        if ($part -match '^(?<Index>\d+):(?<Name>.+)$') {
            $idx = [int]$Matches['Index']
            $name = [string]$Matches['Name']
            if (-not $map.ContainsKey($idx)) {
                $map[$idx] = $name
            }
        }
    }

    return $map
}

function Convert-XmlNameValueToMap {
    param(
        [string]$NameValueMap
    )

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($NameValueMap)) {
        return $map
    }

    foreach ($part in @($NameValueMap -split '\s*\|\|\s*')) {
        if ($part -match '^(?<Index>\d+):(?<Name>[^=]+)=(?<Value>.*)$') {
            $idx = [int]$Matches['Index']
            if (-not $map.ContainsKey($idx)) {
                $map[$idx] = [pscustomobject]@{
                    Name  = [string]$Matches['Name']
                    Value = [string]$Matches['Value']
                }
            }
        }
    }

    return $map
}

function Convert-ToParserSafeAlias {
    param(
        [string]$FieldName,
        [int]$Index
    )

    $alias = [string]$FieldName
    if ([string]::IsNullOrWhiteSpace($alias)) {
        $alias = 'Field_{0:00}' -f $Index
    }

    $alias = $alias -replace '[^A-Za-z0-9_]', '_'
    $alias = $alias.Trim('_')
    if ([string]::IsNullOrWhiteSpace($alias)) {
        $alias = 'Field_{0:00}' -f $Index
    }
    if ($alias -match '^\d') {
        $alias = 'Field_' + $alias
    }

    return $alias
}

function Export-CanonicalFieldLineage {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$EvtxPaths,

        [Parameter(Mandatory = $true)]
        [string]$MappingCsvPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [int]$MaxSamples,

        [int]$DiscoveredMaxTokens
    )

    if (-not (Test-Path -LiteralPath $MappingCsvPath)) {
        throw "Mapping CSV path not found for canonical lineage export: $MappingCsvPath"
    }

    if ($MaxSamples -lt 1) { $MaxSamples = 500 }
    if ($DiscoveredMaxTokens -lt 1) { $DiscoveredMaxTokens = 1 }

    Write-Log -Level 'INFO' -Message ("Starting canonical XML field-to-Strings lineage export. Output='{0}', MaxSamples={1}" -f $OutputPath, $MaxSamples)

    $mappingRows = @(Import-Csv -LiteralPath $MappingCsvPath)
    $sampleByKey = @{}
    foreach ($row in $mappingRows) {
        $key = '{0}|{1}|{2}' -f $row.SourceFile, $row.EventId, $row.RecordNumber
        if (-not $sampleByKey.ContainsKey($key)) {
            $sampleByKey[$key] = $row
        }
    }

    $ids = @()
    if (-not [string]::IsNullOrWhiteSpace($EventIdFilter)) {
        $ids = @($EventIdFilter -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    }

    $out = New-Object System.Collections.Generic.List[object]
    $sampleCount = 0

    foreach ($path in $EvtxPaths) {
        if ($sampleCount -ge $MaxSamples) { break }
        if (-not (Test-Path -LiteralPath $path)) { continue }

        $filter = @{ Path = $path }
        if ($ids.Count -gt 0) { $filter['Id'] = $ids }
        if ($StartTime -ne [datetime]::MinValue) { $filter['StartTime'] = $StartTime }
        if ($EndTime -ne [datetime]::MinValue) { $filter['EndTime'] = $EndTime }

        try {
            $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            Write-Log -Level 'WARN' -Message ("Canonical lineage skipped EVTX due to Get-WinEvent read failure. Path='{0}', Error='{1}'" -f $path, $_.Exception.Message)
            continue
        }

        foreach ($event in $events) {
            if ($sampleCount -ge $MaxSamples) { break }

            if (-not [string]::IsNullOrWhiteSpace($ProviderFilter) -and $event.ProviderName -notlike "*$ProviderFilter*") { continue }

            $xmlText = ''
            try { $xmlText = $event.ToXml() } catch { $xmlText = '' }
            if ([string]::IsNullOrWhiteSpace($xmlText)) { continue }

            $message = ''
            try { $message = $event.FormatDescription() } catch { $message = '' }
            if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
                if (($xmlText -notlike "*$TextFilter*") -and ($message -notlike "*$TextFilter*")) { continue }
            }

            [xml]$xml = $xmlText
            $payload = Get-ProviderAgnosticEventPayload -Xml $xml
            $fieldMap = Convert-XmlFieldSequenceToMap -XmlFieldNameSequence $payload.XmlFieldNameSequence
            $valueMap = Convert-XmlNameValueToMap -NameValueMap $payload.NameValueMap
            $xmlStrings = @($payload.Strings)
            $fieldSequence = [string]$payload.XmlFieldNameSequence
            $templateHash = Get-StringHash -Value ('{0}|{1}|{2}|{3}' -f $event.ProviderName, $event.Id, $payload.StructurePath, $fieldSequence)

            $recordNumber = $event.RecordId
            $key = '{0}|{1}|{2}' -f $path, $event.Id, $recordNumber
            $mappingRow = $null
            if ($sampleByKey.ContainsKey($key)) { $mappingRow = $sampleByKey[$key] }

            $upper = [Math]::Max($DiscoveredMaxTokens, $xmlStrings.Count)
            if ($upper -lt 1) { $upper = 1 }

            for ($i = 0; $i -lt $upper; $i++) {
                $tokenColumn = 'String_{0:00}' -f $i
                $tokenValue = ''
                if ($null -ne $mappingRow -and ($mappingRow.PSObject.Properties.Name -contains $tokenColumn)) {
                    $tokenValue = [string]$mappingRow.$tokenColumn
                }
                elseif ($i -lt $xmlStrings.Count) {
                    $tokenValue = [string]$xmlStrings[$i]
                }

                $xmlFieldName = ''
                $xmlFieldValue = ''
                if ($fieldMap.ContainsKey($i)) { $xmlFieldName = [string]$fieldMap[$i] }
                if ($valueMap.ContainsKey($i)) { $xmlFieldValue = [string]$valueMap[$i].Value }

                $confidence = 'Unmapped'
                if (-not [string]::IsNullOrWhiteSpace($xmlFieldName)) {
                    if ($tokenValue -eq $xmlFieldValue) {
                        $confidence = 'High'
                    }
                    elseif ([string]::IsNullOrWhiteSpace($tokenValue) -and [string]::IsNullOrWhiteSpace($xmlFieldValue)) {
                        $confidence = 'EmptyField'
                    }
                    else {
                        $confidence = 'FieldNameOnly'
                    }
                }
                elseif (-not [string]::IsNullOrWhiteSpace($tokenValue)) {
                    $confidence = 'StringOnly'
                }

                $alias = Convert-ToParserSafeAlias -FieldName $xmlFieldName -Index $i
                $parserExpression = "EXTRACT_TOKEN(Strings, $i, '|') AS $alias"

                [void]$out.Add([pscustomobject]@{
                    SourceFile             = $path
                    RecordNumber           = $recordNumber
                    TimeGenerated          = $event.TimeCreated
                    EventId                = $event.Id
                    ProviderName           = $event.ProviderName
                    ComputerName           = $event.MachineName
                    XmlStructureType       = $payload.StructureType
                    XmlStructurePath       = $payload.StructurePath
                    XmlTemplateHash        = $templateHash
                    TokenIndex             = $i
                    TokenColumn            = $tokenColumn
                    XmlFieldName           = $xmlFieldName
                    ParserSafeAlias        = $alias
                    StringTokenValue       = $tokenValue
                    XmlFieldValue          = $xmlFieldValue
                    LineageConfidence      = $confidence
                    ParserBlueprint        = $parserExpression
                    XmlFieldNameSequence   = $fieldSequence
                })
            }

            $sampleCount++
        }
    }

    $out | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log -Level 'INFO' -Message ("Canonical field lineage exported. Output='{0}', Rows={1}, SampledEvents={2}" -f $OutputPath, $out.Count, $sampleCount)
}

#region Get-WinEvent XML Fallback

function Get-XmlFallbackEvents {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$EvtxPaths,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [int]$MaxRows
    )

    $ids = @()
    if (-not [string]::IsNullOrWhiteSpace($EventIdFilter)) {
        $ids = @($EventIdFilter -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    }

    $result = New-Object System.Collections.Generic.List[object]
    $count = 0

    foreach ($path in $EvtxPaths) {
        Write-Log -Level 'INFO' -Message ("XML fallback reading EVTX. Path='{0}'" -f $path)

        $filter = @{ Path = $path }
        if ($ids.Count -gt 0) {
            $filter['Id'] = $ids
        }
        if ($StartTime -ne [datetime]::MinValue) {
            $filter['StartTime'] = $StartTime
        }
        if ($EndTime -ne [datetime]::MinValue) {
            $filter['EndTime'] = $EndTime
        }

        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        foreach ($event in $events) {
            if ($MaxRows -gt 0 -and $count -ge $MaxRows) {
                break
            }

            if (-not [string]::IsNullOrWhiteSpace($ProviderFilter) -and $event.ProviderName -notlike "*$ProviderFilter*") {
                continue
            }

            $message = ''
            try {
                $message = $event.FormatDescription()
            }
            catch {
                $message = ''
            }

            $xmlText = $event.ToXml()

            if (-not [string]::IsNullOrWhiteSpace($TextFilter)) {
                if (($xmlText -notlike "*$TextFilter*") -and ($message -notlike "*$TextFilter*")) {
                    continue
                }
            }

            [xml]$xml = $xmlText
            $payload = Get-ProviderAgnosticEventPayload -Xml $xml
            $strings = @($payload.Strings)

            $sourceFile = $path
            $seed = 'XML|{0}|{1}|{2}|{3}|{4}' -f $sourceFile, $event.RecordId, $event.Id, $event.TimeCreated, $event.ProviderName
            $record = [ordered]@{
                EvidenceId             = New-EvidenceId -Seed $seed
                IntegrityHash          = Get-StringHash -Value $xmlText
                ParserEngine           = 'Get-WinEvent-XML-Fallback'
                SourceMode             = 'ArchiveOrSnapshot'
                ChannelOrSource        = $sourceFile
                ChronologyIndex        = ($count + 1)
                SourceFile             = $sourceFile
                TimeGenerated          = $event.TimeCreated
                TimeWritten            = $event.TimeCreated
                RecordNumber           = $event.RecordId
                EventId                = $event.Id
                ProviderName           = $event.ProviderName
                ComputerName           = $event.MachineName
                StringTokenCount       = $payload.TokenCount
                XmlStructureType       = $payload.StructureType
                XmlStructurePath       = $payload.StructurePath
                StringsRaw             = ($strings -join '|')
                EventDataNameValueMap  = $payload.NameValueMap
                XmlFieldNameSequence   = $payload.XmlFieldNameSequence
                Message                = $message
            }

            for ($i = 0; $i -lt 80; $i++) {
                $value = ''
                if ($i -lt $strings.Count) {
                    $value = $strings[$i]
                }
                $record[('String_{0:00}' -f $i)] = $value
            }

            [void]$result.Add([pscustomobject]$record)
            $count++
        }
    }

    return @($result | Sort-Object TimeGenerated, RecordNumber)
}

function Export-XmlFallbackMapping {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$EvtxPaths,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [int]$MaxRows
    )

    $rows = @(Get-XmlFallbackEvents -EvtxPaths $EvtxPaths -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxRows $MaxRows)
    $rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
    Write-Log -Level 'INFO' -Message ("XML fallback mapping exported. Output='{0}', Rows={1}" -f $OutputPath, $rows.Count)
}

#endregion Get-WinEvent XML Fallback

#region Execution Pipeline

function Invoke-StringsStructureMapping {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('LiveChannel','Archive')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$Channel,

        [string]$ArchivePath,

        [bool]$Recurse,

        [string]$EventIdFilter,

        [string]$ProviderFilter,

        [string]$TextFilter,

        [int]$MaxTokens,

        [int]$MaxRows,

        [datetime]$StartTime,

        [datetime]$EndTime,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir,

        [bool]$UseXmlFallbackIfNeeded
    )

    Ensure-Directory -Path $OutputDir

    if ($MaxTokens -lt 1) {
        $MaxTokens = 30
    }
    if ($MaxTokens -gt 500) {
        $MaxTokens = 500
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $sourceLabel = if ($Mode -eq 'LiveChannel') { ConvertTo-SafeFileName -Value $Channel } else { 'Archive' }

    $inventoryCsv = Join-Path -Path $OutputDir -ChildPath ("{0}-EventID-Inventory-{1}.csv" -f $script:ScriptName, $timestamp)
    $mappingCsv   = Join-Path -Path $OutputDir -ChildPath ("{0}-Strings-StructureMapping-{1}.csv" -f $script:ScriptName, $timestamp)
    $schemaCsv    = Join-Path -Path $OutputDir -ChildPath ("{0}-Schema-Intelligence-{1}.csv" -f $script:ScriptName, $timestamp)
    $lineageCsv   = Join-Path -Path $OutputDir -ChildPath ("{0}-Canonical-Field-Lineage-{1}.csv" -f $script:ScriptName, $timestamp)
    $discoveryCsv = Join-Path -Path $OutputDir -ChildPath ("{0}-Strings-Discovery-{1}.csv" -f $script:ScriptName, $timestamp)

    $evtxPaths = @()
    $sourcePattern = ''
    $channelOrSource = ''

    if ($Mode -eq 'LiveChannel') {
        if ([string]::IsNullOrWhiteSpace($Channel)) {
            throw 'Live channel was not specified.'
        }

        $resolvedPath = Resolve-ChannelEvtxPath -Channel $Channel
        if (-not [string]::IsNullOrWhiteSpace($resolvedPath)) {
            Write-Log -Level 'INFO' -Message ("Live channel current EVTX path resolved. Channel='{0}', Path='{1}'" -f $Channel, $resolvedPath)
        }

        $snapshot = Export-LiveChannelSnapshot -Channel $Channel
        $evtxPaths = @($snapshot)
        $sourcePattern = $snapshot
        $channelOrSource = $Channel
    }
    else {
        $evtxPaths = @(Get-ArchiveEvtxPaths -InputPath $ArchivePath -Recurse $Recurse)
        if ($evtxPaths.Count -eq 0) {
            throw 'No .evtx files were found in the selected archive path.'
        }

        if ((Test-Path -LiteralPath ([IO.Path]::GetFullPath($ArchivePath)) -PathType Container) -and -not $Recurse) {
            $sourcePattern = Join-Path -Path ([IO.Path]::GetFullPath($ArchivePath)) -ChildPath '*.evtx'
        }
        elseif ((Test-Path -LiteralPath ([IO.Path]::GetFullPath($ArchivePath)) -PathType Container) -and $Recurse) {
            # LogParser EVT input does not recurse safely by itself. Use semicolon-separated source files only through multiple executions fallback.
            # For deterministic behavior, recursive archive mode uses XML fallback when multiple nested files are selected.
            $sourcePattern = ''
        }
        else {
            $sourcePattern = [IO.Path]::GetFullPath($ArchivePath)
        }

        $channelOrSource = [IO.Path]::GetFullPath($ArchivePath)
    }

    $parserEngine = 'LogParser'

    try {
        if ([string]::IsNullOrWhiteSpace($sourcePattern)) {
            throw 'Recursive archive source requires XML fallback because LogParser EVT input does not provide deterministic recursive expansion.'
        }

        $inventorySql = New-EventIdInventorySql -SourcePattern $sourcePattern -OutputPath $inventoryCsv -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -StartTime $StartTime -EndTime $EndTime
        Invoke-LogParserCsvQuery -Query $inventorySql -OutputPath $inventoryCsv

        $discoverySql = New-StringsDiscoverySql -SourcePattern $sourcePattern -OutputPath $discoveryCsv -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxRows $MaxRows
        Invoke-LogParserCsvQuery -Query $discoverySql -OutputPath $discoveryCsv

        $discoveredMaxTokens = Get-MaxTokenCountFromCsv -CsvPath $discoveryCsv -SafetyMaxTokens $MaxTokens
        Write-Log -Level 'INFO' -Message ("Dynamic Strings schema discovered. MaxTokens={0}; SafetyCeiling={1}" -f $discoveredMaxTokens, $MaxTokens)

        $mappingSql = New-StringsMappingSql -SourcePattern $sourcePattern -OutputPath $mappingCsv -MaxTokens $discoveredMaxTokens -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxRows $MaxRows
        Invoke-LogParserCsvQuery -Query $mappingSql -OutputPath $mappingCsv

        Add-ForensicColumnsToCsv -CsvPath $mappingCsv -SourceMode $Mode -ChannelOrSource $channelOrSource -ParserEngine $parserEngine
        Export-StringsSchemaIntelligence -MappingCsvPath $mappingCsv -OutputPath $schemaCsv -DiscoveredMaxTokens $discoveredMaxTokens -SafetyMaxTokens $MaxTokens -ParserEngine $parserEngine
        Export-CanonicalFieldLineage -EvtxPaths $evtxPaths -MappingCsvPath $mappingCsv -OutputPath $lineageCsv -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxSamples $MaxRows -DiscoveredMaxTokens $discoveredMaxTokens

        try { Remove-Item -LiteralPath $discoveryCsv -Force -ErrorAction SilentlyContinue } catch { }
    }
    catch {
        Write-Log -Level 'WARN' -Message ("SQL-FIRST mapping failed or unavailable. Error='{0}'" -f $_.Exception.Message)

        if (-not $UseXmlFallbackIfNeeded) {
            throw
        }

        $parserEngine = 'Get-WinEvent-XML-Fallback'
        Write-Log -Level 'INFO' -Message 'Starting Get-WinEvent XML fallback mapping.'

        # Inventory fallback.
        $fallbackEvents = @(Get-XmlFallbackEvents -EvtxPaths $evtxPaths -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxRows 0)

        $inventory = $fallbackEvents |
            Group-Object SourceFile, EventId, ProviderName |
            ForEach-Object {
                $first = $_.Group | Select-Object -First 1
                [pscustomobject]@{
                    SourceFile   = $first.SourceFile
                    EventId      = $first.EventId
                    ProviderName = $first.ProviderName
                    EventCount   = $_.Count
                    ParserEngine = $parserEngine
                }
            } |
            Sort-Object EventCount -Descending

        $inventory | Export-Csv -LiteralPath $inventoryCsv -NoTypeInformation -Encoding UTF8

        Export-XmlFallbackMapping -EvtxPaths $evtxPaths -OutputPath $mappingCsv -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxRows $MaxRows
        try {
            Export-StringsSchemaIntelligence -MappingCsvPath $mappingCsv -OutputPath $schemaCsv -DiscoveredMaxTokens $MaxTokens -SafetyMaxTokens $MaxTokens -ParserEngine $parserEngine
            Export-CanonicalFieldLineage -EvtxPaths $evtxPaths -MappingCsvPath $mappingCsv -OutputPath $lineageCsv -EventIdFilter $EventIdFilter -ProviderFilter $ProviderFilter -TextFilter $TextFilter -StartTime $StartTime -EndTime $EndTime -MaxSamples $MaxRows -DiscoveredMaxTokens $MaxTokens
        }
        catch {
            Write-Log -Level 'WARN' -Message ("Schema intelligence export skipped during XML fallback. Error='{0}'" -f $_.Exception.Message)
        }
    }

    Write-Log -Level 'INFO' -Message ("Strings structure mapping completed. Inventory='{0}', Mapping='{1}', Schema='{2}'" -f $inventoryCsv, $mappingCsv, $schemaCsv)

    return [pscustomobject]@{
        InventoryCsv = $inventoryCsv
        MappingCsv   = $mappingCsv
        SchemaCsv    = $schemaCsv
        LineageCsv   = $lineageCsv
        ParserEngine = $parserEngine
        SourceCount  = $evtxPaths.Count
    }
}

#endregion Execution Pipeline

#region GUI


function Set-TextBoxCueBanner {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox]$TextBox,

        [Parameter(Mandatory = $true)]
        [string]$CueText
    )

    try {
        # Windows PowerShell 5.1 commonly runs on .NET Framework WinForms,
        # where TextBox.PlaceholderText does not exist. EM_SETCUEBANNER provides
        # a native, PS 5.1-safe placeholder/cue banner without breaking StrictMode.
        if (-not ('NativeMethods.TextBoxCueBanner' -as [type])) {
            Add-Type -Namespace NativeMethods -Name TextBoxCueBanner -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, string lParam);
'@ -ErrorAction Stop
        }

        $EM_SETCUEBANNER = 0x1501
        [void][NativeMethods.TextBoxCueBanner]::SendMessage($TextBox.Handle, $EM_SETCUEBANNER, [IntPtr]::Zero, $CueText)
    }
    catch {
        # Cue banner is visual-only. It must never block GUI initialization.
    }
}

function Start-Gui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'EVTX Strings Structure Mapping - DFIR Toolkit'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(920, 660)
    $form.MinimumSize = New-Object System.Drawing.Size(920, 660)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    $font = New-Object System.Drawing.Font('Segoe UI', 9)
    $form.Font = $font

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = 'EventID-EVTX-Strings-StructureMapping.ps1'
    $lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(18, 15)
    $lblTitle.Size = New-Object System.Drawing.Size(860, 26)
    $form.Controls.Add($lblTitle)

    $lblSubtitle = New-Object System.Windows.Forms.Label
    $lblSubtitle.Text = 'Select a live Windows event channel or offline EVTX source to map the LogParser Strings token structure.'
    $lblSubtitle.Location = New-Object System.Drawing.Point(20, 43)
    $lblSubtitle.Size = New-Object System.Drawing.Size(860, 24)
    $form.Controls.Add($lblSubtitle)

    $groupSource = New-Object System.Windows.Forms.GroupBox
    $groupSource.Text = 'Evidence Source'
    $groupSource.Location = New-Object System.Drawing.Point(20, 75)
    $groupSource.Size = New-Object System.Drawing.Size(860, 170)
    $form.Controls.Add($groupSource)

    $rbLive = New-Object System.Windows.Forms.RadioButton
    $rbLive.Text = 'Live channel snapshot'
    $rbLive.Location = New-Object System.Drawing.Point(20, 30)
    $rbLive.Size = New-Object System.Drawing.Size(180, 24)
    $rbLive.Checked = $true
    $groupSource.Controls.Add($rbLive)

    $rbArchive = New-Object System.Windows.Forms.RadioButton
    $rbArchive.Text = 'Offline EVTX archive'
    $rbArchive.Location = New-Object System.Drawing.Point(210, 30)
    $rbArchive.Size = New-Object System.Drawing.Size(180, 24)
    $groupSource.Controls.Add($rbArchive)

    $lblChannel = New-Object System.Windows.Forms.Label
    $lblChannel.Text = 'Channel:'
    $lblChannel.Location = New-Object System.Drawing.Point(20, 66)
    $lblChannel.Size = New-Object System.Drawing.Size(90, 23)
    $groupSource.Controls.Add($lblChannel)

    $cmbChannel = New-Object System.Windows.Forms.ComboBox
    $cmbChannel.Location = New-Object System.Drawing.Point(115, 63)
    $cmbChannel.Size = New-Object System.Drawing.Size(590, 24)
    $cmbChannel.DropDownStyle = 'DropDown'
    [void]$cmbChannel.Items.AddRange($script:CommonChannels)
    $cmbChannel.Text = 'Security'
    $groupSource.Controls.Add($cmbChannel)

    $btnResolve = New-Object System.Windows.Forms.Button
    $btnResolve.Text = 'Resolve Channel'
    $btnResolve.Location = New-Object System.Drawing.Point(715, 61)
    $btnResolve.Size = New-Object System.Drawing.Size(120, 28)
    $groupSource.Controls.Add($btnResolve)

    $lblArchive = New-Object System.Windows.Forms.Label
    $lblArchive.Text = 'Archive path:'
    $lblArchive.Location = New-Object System.Drawing.Point(20, 105)
    $lblArchive.Size = New-Object System.Drawing.Size(90, 23)
    $groupSource.Controls.Add($lblArchive)

    $txtArchive = New-Object System.Windows.Forms.TextBox
    $txtArchive.Location = New-Object System.Drawing.Point(115, 102)
    $txtArchive.Size = New-Object System.Drawing.Size(590, 24)
    $txtArchive.Enabled = $false
    $groupSource.Controls.Add($txtArchive)

    $btnBrowseArchive = New-Object System.Windows.Forms.Button
    $btnBrowseArchive.Text = 'Browse'
    $btnBrowseArchive.Location = New-Object System.Drawing.Point(715, 100)
    $btnBrowseArchive.Size = New-Object System.Drawing.Size(120, 28)
    $btnBrowseArchive.Enabled = $false
    $groupSource.Controls.Add($btnBrowseArchive)

    $chkRecurse = New-Object System.Windows.Forms.CheckBox
    $chkRecurse.Text = 'Recursive archive enumeration'
    $chkRecurse.Location = New-Object System.Drawing.Point(115, 134)
    $chkRecurse.Size = New-Object System.Drawing.Size(230, 24)
    $chkRecurse.Enabled = $false
    $groupSource.Controls.Add($chkRecurse)

    $groupFilters = New-Object System.Windows.Forms.GroupBox
    $groupFilters.Text = 'Mapping Filters'
    $groupFilters.Location = New-Object System.Drawing.Point(20, 255)
    $groupFilters.Size = New-Object System.Drawing.Size(860, 160)
    $form.Controls.Add($groupFilters)

    $lblEventIds = New-Object System.Windows.Forms.Label
    $lblEventIds.Text = 'EventID(s):'
    $lblEventIds.Location = New-Object System.Drawing.Point(20, 32)
    $lblEventIds.Size = New-Object System.Drawing.Size(90, 23)
    $groupFilters.Controls.Add($lblEventIds)

    $txtEventIds = New-Object System.Windows.Forms.TextBox
    $txtEventIds.Location = New-Object System.Drawing.Point(115, 29)
    $txtEventIds.Size = New-Object System.Drawing.Size(180, 24)
    Set-TextBoxCueBanner -TextBox $txtEventIds -CueText 'e.g. 4624,4625'
    $groupFilters.Controls.Add($txtEventIds)

    $lblProvider = New-Object System.Windows.Forms.Label
    $lblProvider.Text = 'Provider:'
    $lblProvider.Location = New-Object System.Drawing.Point(320, 32)
    $lblProvider.Size = New-Object System.Drawing.Size(70, 23)
    $groupFilters.Controls.Add($lblProvider)

    $txtProvider = New-Object System.Windows.Forms.TextBox
    $txtProvider.Location = New-Object System.Drawing.Point(390, 29)
    $txtProvider.Size = New-Object System.Drawing.Size(180, 24)
    $groupFilters.Controls.Add($txtProvider)

    $lblText = New-Object System.Windows.Forms.Label
    $lblText.Text = 'Text filter:'
    $lblText.Location = New-Object System.Drawing.Point(590, 32)
    $lblText.Size = New-Object System.Drawing.Size(70, 23)
    $groupFilters.Controls.Add($lblText)

    $txtText = New-Object System.Windows.Forms.TextBox
    $txtText.Location = New-Object System.Drawing.Point(665, 29)
    $txtText.Size = New-Object System.Drawing.Size(170, 24)
    $groupFilters.Controls.Add($txtText)

    $lblMaxTokens = New-Object System.Windows.Forms.Label
    $lblMaxTokens.Text = 'Token ceiling:'
    $lblMaxTokens.Location = New-Object System.Drawing.Point(20, 72)
    $lblMaxTokens.Size = New-Object System.Drawing.Size(90, 23)
    $groupFilters.Controls.Add($lblMaxTokens)

    $numMaxTokens = New-Object System.Windows.Forms.NumericUpDown
    $numMaxTokens.Location = New-Object System.Drawing.Point(115, 69)
    $numMaxTokens.Size = New-Object System.Drawing.Size(90, 24)
    $numMaxTokens.Minimum = 1
    $numMaxTokens.Maximum = 500
    $numMaxTokens.Value = 120
    $groupFilters.Controls.Add($numMaxTokens)

    $lblMaxRows = New-Object System.Windows.Forms.Label
    $lblMaxRows.Text = 'Max rows:'
    $lblMaxRows.Location = New-Object System.Drawing.Point(230, 72)
    $lblMaxRows.Size = New-Object System.Drawing.Size(80, 23)
    $groupFilters.Controls.Add($lblMaxRows)

    $numMaxRows = New-Object System.Windows.Forms.NumericUpDown
    $numMaxRows.Location = New-Object System.Drawing.Point(310, 69)
    $numMaxRows.Size = New-Object System.Drawing.Size(100, 24)
    $numMaxRows.Minimum = 0
    $numMaxRows.Maximum = 1000000
    $numMaxRows.Value = 5000
    $groupFilters.Controls.Add($numMaxRows)

    $chkFallback = New-Object System.Windows.Forms.CheckBox
    $chkFallback.Text = 'Use Get-WinEvent XML fallback if LogParser fails'
    $chkFallback.Location = New-Object System.Drawing.Point(440, 69)
    $chkFallback.Size = New-Object System.Drawing.Size(360, 24)
    $chkFallback.Checked = $true
    $groupFilters.Controls.Add($chkFallback)

    $lblStart = New-Object System.Windows.Forms.Label
    $lblStart.Text = 'Start:'
    $lblStart.Location = New-Object System.Drawing.Point(20, 112)
    $lblStart.Size = New-Object System.Drawing.Size(90, 23)
    $groupFilters.Controls.Add($lblStart)

    $dtStart = New-Object System.Windows.Forms.DateTimePicker
    $dtStart.Location = New-Object System.Drawing.Point(115, 109)
    $dtStart.Size = New-Object System.Drawing.Size(190, 24)
    $dtStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtStart.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
    $dtStart.ShowCheckBox = $true
    $dtStart.Checked = $false
    $groupFilters.Controls.Add($dtStart)

    $lblEnd = New-Object System.Windows.Forms.Label
    $lblEnd.Text = 'End:'
    $lblEnd.Location = New-Object System.Drawing.Point(330, 112)
    $lblEnd.Size = New-Object System.Drawing.Size(50, 23)
    $groupFilters.Controls.Add($lblEnd)

    $dtEnd = New-Object System.Windows.Forms.DateTimePicker
    $dtEnd.Location = New-Object System.Drawing.Point(390, 109)
    $dtEnd.Size = New-Object System.Drawing.Size(190, 24)
    $dtEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtEnd.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
    $dtEnd.ShowCheckBox = $true
    $dtEnd.Checked = $false
    $groupFilters.Controls.Add($dtEnd)

    $groupOutput = New-Object System.Windows.Forms.GroupBox
    $groupOutput.Text = 'Output'
    $groupOutput.Location = New-Object System.Drawing.Point(20, 425)
    $groupOutput.Size = New-Object System.Drawing.Size(860, 85)
    $form.Controls.Add($groupOutput)

    $lblOutput = New-Object System.Windows.Forms.Label
    $lblOutput.Text = 'Output folder:'
    $lblOutput.Location = New-Object System.Drawing.Point(20, 35)
    $lblOutput.Size = New-Object System.Drawing.Size(90, 23)
    $groupOutput.Controls.Add($lblOutput)

    $txtOutput = New-Object System.Windows.Forms.TextBox
    $txtOutput.Location = New-Object System.Drawing.Point(115, 32)
    $txtOutput.Size = New-Object System.Drawing.Size(590, 24)
    $txtOutput.Text = $script:DefaultOutputDir
    $groupOutput.Controls.Add($txtOutput)

    $btnBrowseOutput = New-Object System.Windows.Forms.Button
    $btnBrowseOutput.Text = 'Browse'
    $btnBrowseOutput.Location = New-Object System.Drawing.Point(715, 30)
    $btnBrowseOutput.Size = New-Object System.Drawing.Size(120, 28)
    $groupOutput.Controls.Add($btnBrowseOutput)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(20, 525)
    $progress.Size = New-Object System.Drawing.Size(860, 22)
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0
    $form.Controls.Add($progress)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = 'Ready.'
    $lblStatus.Location = New-Object System.Drawing.Point(20, 555)
    $lblStatus.Size = New-Object System.Drawing.Size(860, 24)
    $form.Controls.Add($lblStatus)

    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = 'Start Mapping'
    $btnRun.Location = New-Object System.Drawing.Point(520, 585)
    $btnRun.Size = New-Object System.Drawing.Size(120, 32)
    $form.Controls.Add($btnRun)

    $btnOpenOutput = New-Object System.Windows.Forms.Button
    $btnOpenOutput.Text = 'Open Output'
    $btnOpenOutput.Location = New-Object System.Drawing.Point(650, 585)
    $btnOpenOutput.Size = New-Object System.Drawing.Size(110, 32)
    $form.Controls.Add($btnOpenOutput)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Location = New-Object System.Drawing.Point(770, 585)
    $btnClose.Size = New-Object System.Drawing.Size(110, 32)
    $form.Controls.Add($btnClose)

    $setSourceState = {
        $isLive = $rbLive.Checked
        $cmbChannel.Enabled = $isLive
        $btnResolve.Enabled = $isLive
        $txtArchive.Enabled = -not $isLive
        $btnBrowseArchive.Enabled = -not $isLive
        $chkRecurse.Enabled = -not $isLive
    }

    $rbLive.Add_CheckedChanged($setSourceState)
    $rbArchive.Add_CheckedChanged($setSourceState)

    $btnResolve.Add_Click({
        try {
            $path = Resolve-ChannelEvtxPath -Channel $cmbChannel.Text
            if ([string]::IsNullOrWhiteSpace($path)) {
                Show-Message -Message 'Channel resolved, but no logFileName was returned.' -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
            }
            else {
                Show-Message -Message ("Current live EVTX path:`r`n{0}" -f $path)
            }
        }
        catch {
            Show-Message -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnBrowseArchive.Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select EVTX file or cancel to choose folder'
        $dialog.Filter = 'EVTX files (*.evtx)|*.evtx|All files (*.*)|*.*'
        $dialog.CheckFileExists = $true

        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtArchive.Text = $dialog.FileName
            return
        }

        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = 'Select folder containing EVTX files'
        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtArchive.Text = $folderDialog.SelectedPath
        }
    })

    $btnBrowseOutput.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = 'Select output folder'
        if (Test-Path -LiteralPath $txtOutput.Text) {
            $folderDialog.SelectedPath = $txtOutput.Text
        }

        if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtOutput.Text = $folderDialog.SelectedPath
        }
    })

    $btnOpenOutput.Add_Click({
        try {
            if (Test-Path -LiteralPath $txtOutput.Text) {
                Start-Process -FilePath $txtOutput.Text
            }
        }
        catch {
            Show-Message -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $btnClose.Add_Click({
        $form.Close()
    })

    $btnRun.Add_Click({
        try {
            $btnRun.Enabled = $false
            $progress.Value = 10
            $lblStatus.Text = 'Starting mapping...'
            $form.Refresh()

            $mode = if ($rbLive.Checked) { 'LiveChannel' } else { 'Archive' }
            $start = [datetime]::MinValue
            $end = [datetime]::MinValue

            if ($dtStart.Checked) {
                $start = $dtStart.Value
            }
            if ($dtEnd.Checked) {
                $end = $dtEnd.Value
            }

            $progress.Value = 30
            $lblStatus.Text = 'Executing SQL-FIRST mapping or XML fallback...'
            $form.Refresh()

            $result = Invoke-StringsStructureMapping `
                -Mode $mode `
                -Channel $cmbChannel.Text `
                -ArchivePath $txtArchive.Text `
                -Recurse ([bool]$chkRecurse.Checked) `
                -EventIdFilter $txtEventIds.Text `
                -ProviderFilter $txtProvider.Text `
                -TextFilter $txtText.Text `
                -MaxTokens ([int]$numMaxTokens.Value) `
                -MaxRows ([int]$numMaxRows.Value) `
                -StartTime $start `
                -EndTime $end `
                -OutputDir $txtOutput.Text `
                -UseXmlFallbackIfNeeded ([bool]$chkFallback.Checked)

            $progress.Value = 100
            $lblStatus.Text = 'Completed.'
            $form.Refresh()

            Show-Message -Message ("Mapping completed successfully.`r`n`r`nParser: {0}`r`nSources: {1}`r`n`r`nInventory:`r`n{2}`r`n`r`nMapping:`r`n{3}" -f $result.ParserEngine, $result.SourceCount, $result.InventoryCsv, $result.MappingCsv)
        }
        catch {
            $progress.Value = 0
            $lblStatus.Text = 'Failed.'
            Write-Log -Level 'ERROR' -Message $_.Exception.Message
            Show-Message -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        }
        finally {
            $btnRun.Enabled = $true
        }
    })

    & $setSourceState

    [void]$form.ShowDialog()
}

#endregion GUI

#region Main

try {
    if (-not (Test-IsWindows)) {
        throw 'This tool requires Microsoft Windows.'
    }

    Hide-ConsoleWindow
    Initialize-Log

    Write-Log -Level 'INFO' -Message 'Initializing GUI.'
    Start-Gui

    Write-Log -Level 'INFO' -Message ('========== END: {0} ==========' -f $script:ScriptName)
}
catch {
    Write-Log -Level 'ERROR' -Message $_.Exception.Message
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Show-Message -Message $_.Exception.Message -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
    catch {
        Write-Error $_.Exception.Message
    }
}

#endregion Main

# End of script
