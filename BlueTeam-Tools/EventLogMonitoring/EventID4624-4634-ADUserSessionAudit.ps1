<#
.SYNOPSIS
  Unified forensic GUI for Event ID 4624 RDP logon auditing and Event ID 4624/4634 user session tracking.

.DESCRIPTION
  Production-ready Log Parser 2.2 first forensic session auditor for Security.evtx analysis.
  Supports live Security snapshots, archive-safe EVTX processing, date/time range filtering,
  RDP LogonType 10 extraction, user session tracking, 4624/4634 session correlation, EventID inventory, and Strings mapping.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-07-v5.2.1-PATH-AGNOSTIC-ARCHIVE-PIPELINE
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [switch]$VerboseSqlLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ToolName      = 'EventID4624-4634-UserSessionAudit'
$script:ToolVersion   = '2026-05-07-v5.2.1-PATH-AGNOSTIC-ARCHIVE-PIPELINE'
$script:VerboseSqlLog = [bool]$VerboseSqlLog
$script:DefaultLogDir = 'C:\Logs-TEMP'
$script:DefaultOutDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath       = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
$script:LastReport    = ''
$script:LastSnapshot  = ''

function Ensure-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Directory path is empty.' }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Ensure-Directory -Path $script:DefaultLogDir

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','DEBUG')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch { }
}

function Show-ErrorBox { param([string]$Message) [System.Windows.Forms.MessageBox]::Show($Message, 'Error', 'OK', 'Error') | Out-Null }
function Show-InfoBox  { param([string]$Message) [System.Windows.Forms.MessageBox]::Show($Message, 'Information', 'OK', 'Information') | Out-Null }

function Open-CsvReport {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        Start-Process -FilePath $Path | Out-Null
        Write-Log "Generated CSV opened automatically: '$Path'"
    } catch {
        Write-Log "Failed to auto-open generated CSV: '$Path'. Error: $($_.Exception.Message)" 'WARN'
    }
}

function Get-Timestamp { return (Get-Date -Format 'yyyyMMdd_HHmmss') }

function Find-LogParserPath {
    $candidates = @(
        'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
        'C:\Program Files\Log Parser 2.2\LogParser.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $cmd = Get-Command -Name 'LogParser.exe' -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    throw 'Log Parser 2.2 was not found. Install Log Parser 2.2 or add LogParser.exe to PATH.'
}

function Escape-SqlLiteral {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Convert-ToLogParserTimestamp {
    param([Parameter(Mandatory=$true)][datetime]$Value)
    return $Value.ToString('yyyy-MM-dd HH:mm:ss')
}

function Build-DateRangeSqlCondition {
    param(
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    if (-not $UseDateRange) { return '' }
    if ($EndTime -lt $StartTime) { throw 'End date/time must be greater than or equal to start date/time.' }
    $start = Convert-ToLogParserTimestamp -Value $StartTime
    $end   = Convert-ToLogParserTimestamp -Value $EndTime
    return "TimeGenerated >= TO_TIMESTAMP('$start', 'yyyy-MM-dd HH:mm:ss') AND TimeGenerated <= TO_TIMESTAMP('$end', 'yyyy-MM-dd HH:mm:ss')"
}

function Get-ArchiveTimestampFromFileName {
    param([Parameter(Mandatory=$true)][string]$FileName)
    if ($FileName -match 'Archive-[^-]+-(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})') {
        try { return [datetime]::new([int]$matches[1], [int]$matches[2], [int]$matches[3], [int]$matches[4], [int]$matches[5], [int]$matches[6]) } catch { return $null }
    }
    return $null
}

function Test-EvtxFileInDateRange {
    param(
        [Parameter(Mandatory=$true)][System.IO.FileInfo]$File,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    if (-not $UseDateRange) { return $true }
    $nameTime = Get-ArchiveTimestampFromFileName -FileName $File.Name
    if ($null -ne $nameTime) { return ($nameTime -ge $StartTime -and $nameTime -le $EndTime) }
    return ($File.LastWriteTime -ge $StartTime -and $File.LastWriteTime -le $EndTime)
}

function Resolve-AbsolutePathString {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is empty.' }
    return [System.IO.Path]::GetFullPath($Path)
}

function Test-IsLockedFilePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        return $false
    } catch {
        return $true
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-LiveSecurityEvtxPathCandidate {
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
        $fileValue = (Get-ItemProperty -LiteralPath $regPath -Name File -ErrorAction Stop).File
        if ([string]::IsNullOrWhiteSpace([string]$fileValue)) { return '' }
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$fileValue)
        return (Resolve-AbsolutePathString -Path $expanded)
    } catch {
        return ''
    }
}

function Export-LiveSecuritySnapshot {
    param([Parameter(Mandatory=$true)][string]$LogDir)
    Ensure-Directory -Path $LogDir
    $snapshotDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
    Ensure-Directory -Path $snapshotDir
    $snapshot = Join-Path $snapshotDir ('Security-{0}-{1}.evtx' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8)))
    $errPath = Join-Path $LogDir ('wevtutil-security-snapshot-{0}.err' -f (Get-Timestamp))
    $args = @('epl', 'Security', $snapshot, '/ow:true')
    $p = Start-Process -FilePath 'wevtutil.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $errPath
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        $err = if (Test-Path -LiteralPath $errPath) { Get-Content -LiteralPath $errPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "Failed to export live Security snapshot. ExitCode=$($p.ExitCode). $err"
    }
    $script:LastSnapshot = $snapshot
    Write-Log "Live Security snapshot exported: '$snapshot'"
    return $snapshot
}

function Get-OfflineEvtxFiles {
    param(
        [Parameter(Mandatory=$true)][string]$Folder,
        [bool]$IncludeSubfolders,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    if ([string]::IsNullOrWhiteSpace($Folder)) { throw 'EVTX folder is empty.' }

    $rootPath = Resolve-AbsolutePathString -Path $Folder
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw "EVTX folder not found: $rootPath" }

    Write-Log "Enumerating archived EVTX files using PATH-AGNOSTIC string pipeline. RootPath='$rootPath'; IncludeSubfolders=$IncludeSubfolders"

    $liveSecurityPath = Get-LiveSecurityEvtxPathCandidate
    $selected = New-Object System.Collections.ArrayList
    $enumerated = 0
    $activeSkipped = 0
    $lockedSkipped = 0
    $dateSkipped = 0
    $invalidSkipped = 0

    $gciParams = @{ LiteralPath = $rootPath; Filter = '*.evtx'; File = $true; ErrorAction = 'Stop' }
    if ($IncludeSubfolders) { $gciParams.Recurse = $true }

    foreach ($file in @(Get-ChildItem @gciParams)) {
        $enumerated++
        try {
            $absolutePath = Resolve-AbsolutePathString -Path ([string]$file.FullName)
        } catch {
            $invalidSkipped++
            Write-Log "Skipping EVTX with invalid path. RawPath='$($file.FullName)'. Error: $($_.Exception.Message)" 'WARN'
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($liveSecurityPath) -and ($absolutePath -ieq $liveSecurityPath)) {
            $activeSkipped++
            Write-Log "Skipping active live Security.evtx in archive mode by absolute path match: '$absolutePath'" 'WARN'
            continue
        }

        if (Test-IsLockedFilePath -Path $absolutePath) {
            $lockedSkipped++
            Write-Log "Skipping locked/unreadable EVTX in archive mode: '$absolutePath'" 'WARN'
            continue
        }

        if (-not (Test-EvtxFileInDateRange -File $file -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)) {
            $dateSkipped++
            Write-Log "Skipping EVTX outside selected archive file date range: '$absolutePath'" 'DEBUG'
            continue
        }

        [void]$selected.Add([string]$absolutePath)
    }

    Write-Log "Archive-safe PATH-AGNOSTIC EVTX selection completed. Enumerated=$enumerated; Selected=$($selected.Count); ActiveSkipped=$activeSkipped; LockedSkipped=$lockedSkipped; DateSkipped=$dateSkipped; InvalidSkipped=$invalidSkipped"
    return @($selected.ToArray() | ForEach-Object { [string]$_ })
}

function Get-SourceFilesForMode {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$LogDir,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    $paths = New-Object System.Collections.ArrayList

    if ($UseLiveLog) {
        $snapshotPath = Resolve-AbsolutePathString -Path (Export-LiveSecuritySnapshot -LogDir $LogDir)
        [void]$paths.Add([string]$snapshotPath)
    } else {
        foreach ($path in @(Get-OfflineEvtxFiles -Folder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)) {
            if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
            [void]$paths.Add([string](Resolve-AbsolutePathString -Path ([string]$path)))
        }
    }

    $result = @($paths.ToArray() | ForEach-Object { [string]$_ })
    Write-Log "EVTX source pipeline prepared. UseLiveLog=$UseLiveLog; SourceCount=$($result.Count); PathMode=AbsoluteStringOnly"
    return $result
}

function Invoke-LogParserSql {
    param(
        [Parameter(Mandatory=$true)][string]$Sql,
        [Parameter(Mandatory=$true)][string]$LogParserPath,
        [Parameter(Mandatory=$true)][string]$Context
    )
    Write-Log "Executing Log Parser query [$Context]."
    if ($script:VerboseSqlLog) { Write-Log "SQL [$Context]: $Sql" 'DEBUG' }
    $arguments = @($Sql, '-i:EVT', '-o:CSV', '-headers:ON', '-q:ON')
    $output = & $LogParserPath @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($output) {
        foreach ($line in @($output)) {
            if ($line -match 'Error|Cannot|Falha|erro|failed|O arquivo') { Write-Log "LogParser [$Context]: $line" 'WARN' }
            else { Write-Log "LogParser [$Context]: $line" 'DEBUG' }
        }
    }
    Write-Log "Log Parser exit code [$Context]: $exitCode"
    return [pscustomobject]@{ ExitCode = $exitCode; Output = (@($output) -join [Environment]::NewLine) }
}

function New-EmptyCsv {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string[]]$Headers)
    ($Headers -join ',') | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Merge-CsvFiles {
    param(
        [AllowNull()][AllowEmptyCollection()][string[]]$CsvPaths = @(),
        [Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][string[]]$Headers
    )
    $safePaths = @()
    if ($null -ne $CsvPaths) { $safePaths = @($CsvPaths) }
    $valid = @($safePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) })
    if ($valid.Count -eq 0) {
        New-EmptyCsv -Path $OutputPath -Headers $Headers
        Write-Log "No temporary CSV files were produced. Empty CSV with headers created: '$OutputPath'" 'WARN'
        return
    }
    $first = $true
    foreach ($csv in $valid) {
        $lines = @(Get-Content -LiteralPath $csv -ErrorAction SilentlyContinue)
        if ($lines.Count -eq 0) { continue }
        if ($first) {
            $lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
            $first = $false
        } else {
            $lines | Select-Object -Skip 1 | Add-Content -LiteralPath $OutputPath -Encoding UTF8
        }
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-EmptyCsv -Path $OutputPath -Headers $Headers }
}

function Get-CsvDataRowCount {
    param([Parameter(Mandatory=$true)][string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath)) { return 0 }
    $count = 0
    try {
        Get-Content -LiteralPath $CsvPath -ReadCount 1000 | ForEach-Object { $count += $_.Count }
        if ($count -gt 0) { return ($count - 1) }
        return 0
    } catch { return 0 }
}


function Get-MinuteBucketStart {
    param(
        [Parameter(Mandatory=$true)][datetime]$Value,
        [Parameter(Mandatory=$true)][int]$BucketMinutes
    )
    if ($BucketMinutes -lt 1) { $BucketMinutes = 1 }
    $minute = [math]::Floor($Value.Minute / $BucketMinutes) * $BucketMinutes
    return [datetime]::new($Value.Year, $Value.Month, $Value.Day, $Value.Hour, [int]$minute, 0)
}

function Export-CollapsedSessionSummary {
    param(
        [Parameter(Mandatory=$true)][string]$RawCsvPath,
        [Parameter(Mandatory=$true)][string]$SummaryCsvPath,
        [Parameter(Mandatory=$true)][int]$BucketMinutes
    )
    $headers = @('SessionAction','FirstEventTime','LastEventTime','EventCount','SourceEvtxPath','FirstRecordNumber','LastRecordNumber','EventCollector','EventId','AccountName','AccountDomain','LogonType','SourceIpAddress','ProcessName','FirstLogonId','LastLogonId')
    if (-not (Test-Path -LiteralPath $RawCsvPath)) {
        New-EmptyCsv -Path $SummaryCsvPath -Headers $headers
        return
    }
    $rows = @(Import-Csv -LiteralPath $RawCsvPath)
    if ($rows.Count -eq 0) {
        New-EmptyCsv -Path $SummaryCsvPath -Headers $headers
        return
    }

    $expanded = New-Object System.Collections.Generic.List[object]
    $networkLogons = New-Object System.Collections.Generic.List[object]

    foreach ($row in $rows) {
        $isNetworkLogon = ($row.SessionAction -eq 'LOGON' -and $row.EventId -eq '4624' -and $row.LogonType -eq '3')
        if (-not $isNetworkLogon) {
            $expanded.Add([pscustomobject]@{
                SessionAction     = $row.SessionAction
                FirstEventTime    = $row.EventTime
                LastEventTime     = $row.EventTime
                EventCount        = 1
                SourceEvtxPath    = $row.SourceEvtxPath
                FirstRecordNumber = $row.RecordNumber
                LastRecordNumber  = $row.RecordNumber
                EventCollector    = $row.ComputerName
                EventId           = $row.EventId
                AccountName       = $row.AccountName
                AccountDomain     = $row.AccountDomain
                LogonType         = $row.LogonType
                SourceIpAddress   = $row.SourceIpAddress
                ProcessName       = $row.ProcessName
                FirstLogonId      = $row.LogonId
                LastLogonId       = $row.LogonId
            })
            continue
        }

        $eventTime = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$row.EventTime, [ref]$eventTime)) {
            $expanded.Add([pscustomobject]@{
                SessionAction     = $row.SessionAction
                FirstEventTime    = $row.EventTime
                LastEventTime     = $row.EventTime
                EventCount        = 1
                SourceEvtxPath    = $row.SourceEvtxPath
                FirstRecordNumber = $row.RecordNumber
                LastRecordNumber  = $row.RecordNumber
                EventCollector    = $row.ComputerName
                EventId           = $row.EventId
                AccountName       = $row.AccountName
                AccountDomain     = $row.AccountDomain
                LogonType         = $row.LogonType
                SourceIpAddress   = $row.SourceIpAddress
                ProcessName       = $row.ProcessName
                FirstLogonId      = $row.LogonId
                LastLogonId       = $row.LogonId
            })
            continue
        }

        $bucket = Get-MinuteBucketStart -Value $eventTime -BucketMinutes $BucketMinutes
        $networkLogons.Add([pscustomobject]@{
            Row        = $row
            EventTime  = $eventTime
            BucketTime = $bucket
            GroupKey   = ('{0}|{1}|{2}|{3}|{4}|{5}' -f $row.AccountName, $row.AccountDomain, $row.SourceIpAddress, $row.LogonType, $row.ComputerName, $bucket.ToString('yyyy-MM-dd HH:mm:ss'))
        })
    }

    foreach ($group in ($networkLogons | Group-Object -Property GroupKey)) {
        $items = @($group.Group | Sort-Object -Property EventTime)
        if ($items.Count -eq 0) { continue }
        $first = $items[0].Row
        $last  = $items[$items.Count - 1].Row
        $expanded.Add([pscustomobject]@{
            SessionAction     = 'NETWORK_LOGON_SUMMARY'
            FirstEventTime    = $items[0].EventTime.ToString('yyyy-MM-dd HH:mm:ss')
            LastEventTime     = $items[$items.Count - 1].EventTime.ToString('yyyy-MM-dd HH:mm:ss')
            EventCount        = $items.Count
            SourceEvtxPath    = $first.SourceEvtxPath
            FirstRecordNumber = $first.RecordNumber
            LastRecordNumber  = $last.RecordNumber
            EventCollector    = $first.ComputerName
            EventId           = $first.EventId
            AccountName       = $first.AccountName
            AccountDomain     = $first.AccountDomain
            LogonType         = $first.LogonType
            SourceIpAddress   = $first.SourceIpAddress
            ProcessName       = $first.ProcessName
            FirstLogonId      = $first.LogonId
            LastLogonId       = $last.LogonId
        })
    }

    $ordered = @($expanded | Sort-Object -Property @{ Expression = { [datetime]($_.FirstEventTime) }; Descending = $true })
    if ($ordered.Count -eq 0) {
        New-EmptyCsv -Path $SummaryCsvPath -Headers $headers
    } else {
        $ordered | Select-Object $headers | Export-Csv -LiteralPath $SummaryCsvPath -NoTypeInformation -Encoding UTF8
    }
}


function Format-DurationText {
    param([int]$Seconds)
    if ($Seconds -lt 0) { return '' }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalDays -ge 1) { return ('{0}d {1:00}:{2:00}:{3:00}' -f [int]$ts.TotalDays, $ts.Hours, $ts.Minutes, $ts.Seconds) }
    return ('{0:00}:{1:00}:{2:00}' -f $ts.Hours, $ts.Minutes, $ts.Seconds)
}

function Export-CorrelatedSessionReport {
    param(
        [Parameter(Mandatory=$true)][string]$RawCsvPath,
        [Parameter(Mandatory=$true)][string]$CorrelationCsvPath
    )
    $headers = @(
        'SessionStatus','AccountName','AccountDomain','LogonType','SourceIpAddress','EventCollector',
        'LogonTime','LogoffTime','DurationSeconds','DurationText',
        'LogonRecordNumber','LogoffRecordNumber','LogonId','LogonSourceEvtxPath','LogoffSourceEvtxPath','ProcessName'
    )
    if (-not (Test-Path -LiteralPath $RawCsvPath)) {
        New-EmptyCsv -Path $CorrelationCsvPath -Headers $headers
        return
    }

    $rows = @(Import-Csv -LiteralPath $RawCsvPath)
    if ($rows.Count -eq 0) {
        New-EmptyCsv -Path $CorrelationCsvPath -Headers $headers
        return
    }

    $pending = @{}
    $output = New-Object System.Collections.Generic.List[object]

    foreach ($row in ($rows | Sort-Object -Property @{ Expression = { [datetime]($_.EventTime) }; Descending = $false }, RecordNumber)) {
        $eventTime = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$row.EventTime, [ref]$eventTime)) { continue }

        $key = ('{0}|{1}|{2}' -f $row.ComputerName, $row.AccountName, $row.LogonId)

        if ($row.SessionAction -eq 'LOGON') {
            if (-not $pending.ContainsKey($key)) {
                $pending[$key] = New-Object System.Collections.Generic.Queue[object]
            }
            $pending[$key].Enqueue([pscustomobject]@{ Row = $row; Time = $eventTime })
            continue
        }

        if ($row.SessionAction -eq 'LOGOFF') {
            if ($pending.ContainsKey($key) -and $pending[$key].Count -gt 0) {
                $logon = $pending[$key].Dequeue()
                $durationSeconds = [int][math]::Max(0, ($eventTime - $logon.Time).TotalSeconds)
                $output.Add([pscustomobject]@{
                    SessionStatus       = 'MATCHED'
                    AccountName         = $logon.Row.AccountName
                    AccountDomain       = $logon.Row.AccountDomain
                    LogonType           = $logon.Row.LogonType
                    SourceIpAddress     = $logon.Row.SourceIpAddress
                    EventCollector      = $logon.Row.ComputerName
                    LogonTime           = $logon.Time.ToString('yyyy-MM-dd HH:mm:ss')
                    LogoffTime          = $eventTime.ToString('yyyy-MM-dd HH:mm:ss')
                    DurationSeconds     = $durationSeconds
                    DurationText        = Format-DurationText -Seconds $durationSeconds
                    LogonRecordNumber   = $logon.Row.RecordNumber
                    LogoffRecordNumber  = $row.RecordNumber
                    LogonId             = $logon.Row.LogonId
                    LogonSourceEvtxPath = $logon.Row.SourceEvtxPath
                    LogoffSourceEvtxPath= $row.SourceEvtxPath
                    ProcessName         = $logon.Row.ProcessName
                })
            } else {
                $output.Add([pscustomobject]@{
                    SessionStatus       = 'LOGOFF_WITHOUT_MATCHING_LOGON'
                    AccountName         = $row.AccountName
                    AccountDomain       = $row.AccountDomain
                    LogonType           = $row.LogonType
                    SourceIpAddress     = ''
                    EventCollector      = $row.ComputerName
                    LogonTime           = ''
                    LogoffTime          = $eventTime.ToString('yyyy-MM-dd HH:mm:ss')
                    DurationSeconds     = ''
                    DurationText        = ''
                    LogonRecordNumber   = ''
                    LogoffRecordNumber  = $row.RecordNumber
                    LogonId             = $row.LogonId
                    LogonSourceEvtxPath = ''
                    LogoffSourceEvtxPath= $row.SourceEvtxPath
                    ProcessName         = ''
                })
            }
        }
    }

    foreach ($key in @($pending.Keys)) {
        while ($pending[$key].Count -gt 0) {
            $logon = $pending[$key].Dequeue()
            $output.Add([pscustomobject]@{
                SessionStatus       = 'OPEN_SESSION_NO_LOGOFF_FOUND'
                AccountName         = $logon.Row.AccountName
                AccountDomain       = $logon.Row.AccountDomain
                LogonType           = $logon.Row.LogonType
                SourceIpAddress     = $logon.Row.SourceIpAddress
                EventCollector      = $logon.Row.ComputerName
                LogonTime           = $logon.Time.ToString('yyyy-MM-dd HH:mm:ss')
                LogoffTime          = ''
                DurationSeconds     = ''
                DurationText        = ''
                LogonRecordNumber   = $logon.Row.RecordNumber
                LogoffRecordNumber  = ''
                LogonId             = $logon.Row.LogonId
                LogonSourceEvtxPath = $logon.Row.SourceEvtxPath
                LogoffSourceEvtxPath= ''
                ProcessName         = $logon.Row.ProcessName
            })
        }
    }

    $ordered = @($output | Sort-Object -Property @{ Expression = { if ($_.LogonTime) { [datetime]$_.LogonTime } else { [datetime]$_.LogoffTime } }; Descending = $true })
    if ($ordered.Count -eq 0) {
        New-EmptyCsv -Path $CorrelationCsvPath -Headers $headers
    } else {
        $ordered | Select-Object $headers | Export-Csv -LiteralPath $CorrelationCsvPath -NoTypeInformation -Encoding UTF8
    }
}

function Build-FromClause { param([Parameter(Mandatory=$true)][string]$Path) return "'$(Escape-SqlLiteral $Path)'" }

function Convert-UserFilterToSqlCondition {
    param(
        [Parameter(Mandatory=$true)][string]$FilterText,
        [Parameter(Mandatory=$true)][int]$UserIndex,
        [Parameter(Mandatory=$true)][int]$DomainIndex
    )
    $rawItems = @($FilterText -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($rawItems.Count -eq 0 -or $rawItems -contains '*') { return '' }
    $conditions = New-Object System.Collections.Generic.List[string]
    foreach ($item in $rawItems) {
        if ($item -match '^[^\\]+\\[^\\]+$') {
            $parts = $item -split '\\', 2
            $domain = $parts[0]
            $user = $parts[1]
            $conditions.Add("(EXTRACT_TOKEN(Strings, $DomainIndex, '|') = '$(Escape-SqlLiteral $domain)' AND EXTRACT_TOKEN(Strings, $UserIndex, '|') = '$(Escape-SqlLiteral $user)')")
        } else {
            $conditions.Add("EXTRACT_TOKEN(Strings, $UserIndex, '|') = '$(Escape-SqlLiteral $item)'")
        }
    }
    if ($conditions.Count -eq 0) { return '' }
    return '(' + ($conditions -join ' OR ') + ')'
}

function Invoke-Inventory {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $logParser = Find-LogParserPath
    $sources = @(Get-SourceFilesForMode -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -LogDir $LogDir -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)
    if ($sources.Count -eq 0) { throw 'No EVTX source files available for inventory.' }
    $out = Join-Path $OutputDir ((hostname) + '-EventID4624-4634-Inventory-' + (Get-Timestamp) + '.csv')
    $tempFiles = New-Object System.Collections.Generic.List[string]
    foreach ($src in $sources) {
        $tmp = Join-Path $env:TEMP ('InventorySession_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        $dateCondition = Build-DateRangeSqlCondition -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime
        $where = if ([string]::IsNullOrWhiteSpace($dateCondition)) { '' } else { " WHERE $dateCondition" }
        $sql = "SELECT [EventLog] AS SourceEvtxPath, EventID AS EventId, COUNT(*) AS TotalOccurrences INTO '$(Escape-SqlLiteral $tmp)' FROM $(Build-FromClause -Path $src)$where GROUP BY [EventLog], EventID ORDER BY TotalOccurrences DESC"
        try {
            [void](Invoke-LogParserSql -Sql $sql -LogParserPath $logParser -Context "Inventory:$src")
            if (Test-Path -LiteralPath $tmp) { $tempFiles.Add($tmp) }
        } catch { Write-Log "Inventory skipped source after non-fatal failure: '$src'. Error: $($_.Exception.Message)" 'WARN' }
    }
    Merge-CsvFiles -CsvPaths @($tempFiles.ToArray()) -OutputPath $out -Headers @('SourceEvtxPath','EventId','TotalOccurrences')
    $script:LastReport = $out
    Write-Log "Inventory report exported: '$out'"
    return $out
}

function Invoke-Mapping {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir,
        [int]$EventId,
        [int]$MaxToken,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $logParser = Find-LogParserPath
    $sources = @(Get-SourceFilesForMode -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -LogDir $LogDir -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)
    if ($sources.Count -eq 0) { throw "No EVTX source files available for EventID $EventId mapping." }
    $out = Join-Path $OutputDir ((hostname) + "-EventID$EventId-StringsMapping-" + (Get-Timestamp) + '.csv')
    $selectTokens = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -le $MaxToken; $i++) { $selectTokens.Add("EXTRACT_TOKEN(Strings, $i, '|') AS String$('{0:D2}' -f $i)") }
    $tempFiles = New-Object System.Collections.Generic.List[string]
    foreach ($src in $sources) {
        $tmp = Join-Path $env:TEMP ("Mapping$EventId`_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
        $dateCondition = Build-DateRangeSqlCondition -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime
        $dateSql = if ([string]::IsNullOrWhiteSpace($dateCondition)) { '' } else { " AND $dateCondition" }
        $sql = "SELECT [EventLog] AS SourceEvtxPath, TimeGenerated AS EventTime, EventID AS EventId, $($selectTokens -join ', ') INTO '$(Escape-SqlLiteral $tmp)' FROM $(Build-FromClause -Path $src) WHERE EventID = $EventId$dateSql"
        try {
            [void](Invoke-LogParserSql -Sql $sql -LogParserPath $logParser -Context ([string]::Format("Mapping{0}:{1}", $EventId, $src)))
            if (Test-Path -LiteralPath $tmp) { $tempFiles.Add($tmp) }
        } catch { Write-Log "Mapping EventID $EventId skipped source after non-fatal failure: '$src'. Error: $($_.Exception.Message)" 'WARN' }
    }
    $headers = @('SourceEvtxPath','EventTime','EventId') + (0..$MaxToken | ForEach-Object { 'String{0:D2}' -f $_ })
    Merge-CsvFiles -CsvPaths @($tempFiles.ToArray()) -OutputPath $out -Headers $headers
    $script:LastReport = $out
    Write-Log "Mapping EventID $EventId report exported: '$out'"
    return $out
}

function Invoke-RdpExtraction4624 {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir,
        [string]$UserFilter,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $logParser = Find-LogParserPath
    $sources = @(Get-SourceFilesForMode -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -LogDir $LogDir -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)
    if ($sources.Count -eq 0) { throw 'No EVTX source files available for RDP extraction.' }
    $out = Join-Path $OutputDir ((hostname) + '-EventID4624-RDP-LogonType10-' + (Get-Timestamp) + '.csv')
    $tempFiles = New-Object System.Collections.Generic.List[string]
    $where = "EventID = 4624 AND EXTRACT_TOKEN(Strings, 8, '|') = '10'"
    $dateCondition = Build-DateRangeSqlCondition -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime
    if (-not [string]::IsNullOrWhiteSpace($dateCondition)) { $where += " AND $dateCondition" }
    $userCondition = Convert-UserFilterToSqlCondition -FilterText $UserFilter -UserIndex 5 -DomainIndex 6
    if (-not [string]::IsNullOrWhiteSpace($userCondition)) { $where += " AND $userCondition" }
    foreach ($src in $sources) {
        $tmp = Join-Path $env:TEMP ('Rdp4624_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        $sql = @"
SELECT
  'RDP_LOGON' AS EvidenceType,
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS ComputerName,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 5, '|') AS AccountName,
  EXTRACT_TOKEN(Strings, 6, '|') AS AccountDomain,
  EXTRACT_TOKEN(Strings, 8, '|') AS LogonType,
  EXTRACT_TOKEN(Strings, 18, '|') AS SourceIpAddress,
  EXTRACT_TOKEN(Strings, 17, '|') AS ProcessName,
  EXTRACT_TOKEN(Strings, 7, '|') AS LogonId
INTO '$(Escape-SqlLiteral $tmp)'
FROM $(Build-FromClause -Path $src)
WHERE $where
ORDER BY EventTime DESC
"@
        try {
            [void](Invoke-LogParserSql -Sql $sql -LogParserPath $logParser -Context "RDP4624:$src")
            if (Test-Path -LiteralPath $tmp) { $tempFiles.Add($tmp) }
        } catch { Write-Log "RDP extraction skipped source after non-fatal failure: '$src'. Error: $($_.Exception.Message)" 'WARN' }
    }
    $headers = @('EvidenceType','SourceEvtxPath','RecordNumber','EventTime','ComputerName','EventId','AccountName','AccountDomain','LogonType','SourceIpAddress','ProcessName','LogonId')
    Merge-CsvFiles -CsvPaths @($tempFiles.ToArray()) -OutputPath $out -Headers $headers
    $script:LastReport = $out
    $rows = Get-CsvDataRowCount -CsvPath $out
    if ($rows -eq 0) { Write-Log "RDP extraction completed with zero matching records for filter: '$UserFilter'. This is not an execution failure." 'WARN' }
    Write-Log "RDP extraction report exported: '$out'. Rows=$rows"
    return $out
}

function Invoke-SessionTrackingExtraction {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputDir,
        [string]$LogDir,
        [string]$UserFilter,
        [bool]$UseDateRange,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [bool]$CollapseNetworkLogons = $false,
        [int]$BucketMinutes = 1,
        [bool]$CorrelateSessions = $false
    )
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $logParser = Find-LogParserPath
    $sources = @(Get-SourceFilesForMode -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -LogDir $LogDir -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime)
    if ($sources.Count -eq 0) { throw 'No EVTX source files available for session tracking.' }
    $timestamp = Get-Timestamp
    if ($CorrelateSessions) {
        $out = Join-Path $OutputDir ((hostname) + '-EventID4624-4634-UserSessionCorrelation-' + $timestamp + '.csv')
        $rawOut = Join-Path $OutputDir ((hostname) + '-EventID4624-4634-UserSessionTracking-RAW-' + $timestamp + '.csv')
    } else {
        $out = Join-Path $OutputDir ((hostname) + '-EventID4624-4634-UserSessionTracking-' + $timestamp + '.csv')
        $rawOut = if ($CollapseNetworkLogons) { Join-Path $OutputDir ((hostname) + '-EventID4624-4634-UserSessionTracking-RAW-' + $timestamp + '.csv') } else { $out }
    }
    $tempFiles = New-Object System.Collections.Generic.List[string]
    $dateCondition = Build-DateRangeSqlCondition -UseDateRange $UseDateRange -StartTime $StartTime -EndTime $EndTime

    foreach ($src in $sources) {
        $tmp4624 = Join-Path $env:TEMP ('Session4624_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        $where4624 = 'EventID = 4624'
        if (-not [string]::IsNullOrWhiteSpace($dateCondition)) { $where4624 += " AND $dateCondition" }
        $user4624 = Convert-UserFilterToSqlCondition -FilterText $UserFilter -UserIndex 5 -DomainIndex 6
        if (-not [string]::IsNullOrWhiteSpace($user4624)) { $where4624 += " AND $user4624" }
        $sql4624 = @"
SELECT
  'LOGON' AS SessionAction,
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS ComputerName,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 5, '|') AS AccountName,
  EXTRACT_TOKEN(Strings, 6, '|') AS AccountDomain,
  EXTRACT_TOKEN(Strings, 8, '|') AS LogonType,
  EXTRACT_TOKEN(Strings, 18, '|') AS SourceIpAddress,
  EXTRACT_TOKEN(Strings, 17, '|') AS ProcessName,
  EXTRACT_TOKEN(Strings, 7, '|') AS LogonId
INTO '$(Escape-SqlLiteral $tmp4624)'
FROM $(Build-FromClause -Path $src)
WHERE $where4624
"@
        try {
            [void](Invoke-LogParserSql -Sql $sql4624 -LogParserPath $logParser -Context "Session4624:$src")
            if (Test-Path -LiteralPath $tmp4624) { $tempFiles.Add($tmp4624) }
        } catch { Write-Log "Session 4624 extraction skipped source after non-fatal failure: '$src'. Error: $($_.Exception.Message)" 'WARN' }

        $tmp4634 = Join-Path $env:TEMP ('Session4634_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        $where4634 = 'EventID = 4634'
        if (-not [string]::IsNullOrWhiteSpace($dateCondition)) { $where4634 += " AND $dateCondition" }
        $user4634 = Convert-UserFilterToSqlCondition -FilterText $UserFilter -UserIndex 1 -DomainIndex 2
        if (-not [string]::IsNullOrWhiteSpace($user4634)) { $where4634 += " AND $user4634" }
        $sql4634 = @"
SELECT
  'LOGOFF' AS SessionAction,
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS ComputerName,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 1, '|') AS AccountName,
  EXTRACT_TOKEN(Strings, 2, '|') AS AccountDomain,
  EXTRACT_TOKEN(Strings, 4, '|') AS LogonType,
  '' AS SourceIpAddress,
  '' AS ProcessName,
  EXTRACT_TOKEN(Strings, 3, '|') AS LogonId
INTO '$(Escape-SqlLiteral $tmp4634)'
FROM $(Build-FromClause -Path $src)
WHERE $where4634
"@
        try {
            [void](Invoke-LogParserSql -Sql $sql4634 -LogParserPath $logParser -Context "Session4634:$src")
            if (Test-Path -LiteralPath $tmp4634) { $tempFiles.Add($tmp4634) }
        } catch { Write-Log "Session 4634 extraction skipped source after non-fatal failure: '$src'. Error: $($_.Exception.Message)" 'WARN' }
    }
    $headers = @('SessionAction','SourceEvtxPath','RecordNumber','EventTime','ComputerName','EventId','AccountName','AccountDomain','LogonType','SourceIpAddress','ProcessName','LogonId')
    Merge-CsvFiles -CsvPaths @($tempFiles.ToArray()) -OutputPath $rawOut -Headers $headers
    if ($CorrelateSessions) {
        Export-CorrelatedSessionReport -RawCsvPath $rawOut -CorrelationCsvPath $out
        Write-Log "Correlated session report exported: '$out'. Raw report preserved: '$rawOut'."
    } elseif ($CollapseNetworkLogons) {
        Export-CollapsedSessionSummary -RawCsvPath $rawOut -SummaryCsvPath $out -BucketMinutes $BucketMinutes
        Write-Log "Collapsed network logon summary exported: '$out'. Raw report preserved: '$rawOut'. BucketMinutes=$BucketMinutes"
    }
    $script:LastReport = $out
    $rows = Get-CsvDataRowCount -CsvPath $out
    if ($rows -eq 0) { Write-Log "Session tracking extraction completed with zero matching 4624/4634 records for filter: '$UserFilter'. This is not an execution failure." 'WARN' }
    Write-Log "Session tracking report exported: '$out'. Rows=$rows"
    return $out
}

function Resolve-SecurityChannelLightweight {
    param([string]$OutputDir, [string]$LogDir)
    Ensure-Directory -Path $OutputDir
    Ensure-Directory -Path $LogDir
    $logParser = Find-LogParserPath
    $snapshot = Export-LiveSecuritySnapshot -LogDir $LogDir
    $tmp = Join-Path $env:TEMP ('ResolveSession_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
    $sql = "SELECT EventID AS EventId, COUNT(*) AS TotalOccurrences INTO '$(Escape-SqlLiteral $tmp)' FROM '$(Escape-SqlLiteral $snapshot)' WHERE EventID IN (4624;4634) GROUP BY EventID"
    [void](Invoke-LogParserSql -Sql $sql -LogParserPath $logParser -Context 'ResolveChannel4624-4634')
    if (Test-Path -LiteralPath $tmp) { return "Security channel resolved. Probe CSV: $tmp. Snapshot: $snapshot" }
    return "Security channel resolved, but no 4624/4634 probe CSV was created. Snapshot: $snapshot"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Forensic Session Auditor v5.2.0 - Event IDs 4624 / 4634'
$form.Size = New-Object System.Drawing.Size(920, 780)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$left = 18
$fieldX = 170
$fieldW = 560
$btnX = 755
$btnW = 135
$btnH = 30
$y = 18

function Add-Label($text, $x, $y, $w=145, $h=22) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x,$y)
    $label.Size = New-Object System.Drawing.Size($w,$h)
    $form.Controls.Add($label)
    return $label
}

Add-Label 'User Accounts Filter:' $left ($y + 6) | Out-Null
$txtUsers = New-Object System.Windows.Forms.TextBox
$txtUsers.Multiline = $true
$txtUsers.ScrollBars = 'Vertical'
$txtUsers.Text = '*'
$txtUsers.Location = New-Object System.Drawing.Point($fieldX,$y)
$txtUsers.Size = New-Object System.Drawing.Size($fieldW,60)
$form.Controls.Add($txtUsers)

$btnResolve = New-Object System.Windows.Forms.Button
$btnResolve.Text = 'Resolve Channel'
$btnResolve.Location = New-Object System.Drawing.Point($btnX,$y)
$btnResolve.Size = New-Object System.Drawing.Size($btnW,$btnH)
$form.Controls.Add($btnResolve)
$y += 72

$chkLive = New-Object System.Windows.Forms.CheckBox
$chkLive.Text = 'Use live Security channel (snapshot via wevtutil)'
$chkLive.Checked = $true
$chkLive.Location = New-Object System.Drawing.Point($fieldX,$y)
$chkLive.Size = New-Object System.Drawing.Size(360,22)
$form.Controls.Add($chkLive)
$y += 36

Add-Label 'EVTX Folder:' $left ($y + 4) | Out-Null
$txtEvtx = New-Object System.Windows.Forms.TextBox
$txtEvtx.Text = 'L:\Security'
$txtEvtx.Location = New-Object System.Drawing.Point($fieldX,$y)
$txtEvtx.Size = New-Object System.Drawing.Size($fieldW,24)
$form.Controls.Add($txtEvtx)
$btnBrowseEvtx = New-Object System.Windows.Forms.Button
$btnBrowseEvtx.Text = 'Browse...'
$btnBrowseEvtx.Location = New-Object System.Drawing.Point($btnX,$y)
$btnBrowseEvtx.Size = New-Object System.Drawing.Size($btnW,$btnH)
$form.Controls.Add($btnBrowseEvtx)
$y += 34

$chkSub = New-Object System.Windows.Forms.CheckBox
$chkSub.Text = 'Include subfolders when scanning archived EVTX'
$chkSub.Checked = $true
$chkSub.Location = New-Object System.Drawing.Point($fieldX,$y)
$chkSub.Size = New-Object System.Drawing.Size(360,22)
$form.Controls.Add($chkSub)
$y += 36

Add-Label 'Output Folder:' $left ($y + 4) | Out-Null
$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Text = $script:DefaultOutDir
$txtOut.Location = New-Object System.Drawing.Point($fieldX,$y)
$txtOut.Size = New-Object System.Drawing.Size($fieldW,24)
$form.Controls.Add($txtOut)
$btnBrowseOut = New-Object System.Windows.Forms.Button
$btnBrowseOut.Text = 'Browse...'
$btnBrowseOut.Location = New-Object System.Drawing.Point($btnX,$y)
$btnBrowseOut.Size = New-Object System.Drawing.Size($btnW,$btnH)
$form.Controls.Add($btnBrowseOut)
$y += 36

Add-Label 'Log Folder:' $left ($y + 4) | Out-Null
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Text = $script:DefaultLogDir
$txtLog.Location = New-Object System.Drawing.Point($fieldX,$y)
$txtLog.Size = New-Object System.Drawing.Size($fieldW,24)
$form.Controls.Add($txtLog)
$btnBrowseLog = New-Object System.Windows.Forms.Button
$btnBrowseLog.Text = 'Browse...'
$btnBrowseLog.Location = New-Object System.Drawing.Point($btnX,$y)
$btnBrowseLog.Size = New-Object System.Drawing.Size($btnW,$btnH)
$form.Controls.Add($btnBrowseLog)
$y += 42

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Text = 'Use date/time range'
$chkDate.Checked = $true
$chkDate.Location = New-Object System.Drawing.Point($fieldX,$y)
$chkDate.Size = New-Object System.Drawing.Size(180,22)
$form.Controls.Add($chkDate)
Add-Label 'From:' 355 ($y + 4) 40 22 | Out-Null
$dtFrom = New-Object System.Windows.Forms.DateTimePicker
$dtFrom.Format = 'Custom'
$dtFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtFrom.Value = (Get-Date).AddDays(-1)
$dtFrom.Location = New-Object System.Drawing.Point(400,$y)
$dtFrom.Size = New-Object System.Drawing.Size(160,24)
$form.Controls.Add($dtFrom)
Add-Label 'To:' 575 ($y + 4) 30 22 | Out-Null
$dtTo = New-Object System.Windows.Forms.DateTimePicker
$dtTo.Format = 'Custom'
$dtTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dtTo.Value = (Get-Date)
$dtTo.Location = New-Object System.Drawing.Point(610,$y)
$dtTo.Size = New-Object System.Drawing.Size(160,24)
$form.Controls.Add($dtTo)
$y += 42

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point($left,$y)
$tabs.Size = New-Object System.Drawing.Size(872,180)
$form.Controls.Add($tabs)

$tabRdp = New-Object System.Windows.Forms.TabPage
$tabRdp.Text = 'RDP Logon Audit'
$tabs.TabPages.Add($tabRdp)
$btnRdp = New-Object System.Windows.Forms.Button
$btnRdp.Text = 'Extract RDP 4624'
$btnRdp.Location = New-Object System.Drawing.Point(20,25)
$btnRdp.Size = New-Object System.Drawing.Size(180,34)
$tabRdp.Controls.Add($btnRdp)
$lblRdp = New-Object System.Windows.Forms.Label
$lblRdp.Text = 'Extracts EventID 4624 RDP logons where LogonType = 10. Output uses a compact USA-English evidence schema.'
$lblRdp.Location = New-Object System.Drawing.Point(220,32)
$lblRdp.Size = New-Object System.Drawing.Size(610,50)
$tabRdp.Controls.Add($lblRdp)

$tabSession = New-Object System.Windows.Forms.TabPage
$tabSession.Text = 'User Session Tracking'
$tabs.TabPages.Add($tabSession)
$btnSession = New-Object System.Windows.Forms.Button
$btnSession.Text = 'Extract 4624 + 4634'
$btnSession.Location = New-Object System.Drawing.Point(20,25)
$btnSession.Size = New-Object System.Drawing.Size(180,34)
$tabSession.Controls.Add($btnSession)
$lblSession = New-Object System.Windows.Forms.Label
$lblSession.Text = 'Tracks LOGON and LOGOFF activity using independent token mappings for Event IDs 4624 and 4634.'
$lblSession.Location = New-Object System.Drawing.Point(220,32)
$lblSession.Size = New-Object System.Drawing.Size(610,50)
$tabSession.Controls.Add($lblSession)
$chkCollapseNetwork = New-Object System.Windows.Forms.CheckBox
$chkCollapseNetwork.Text = 'Collapse repeated LogonType 3 network logons'
$chkCollapseNetwork.Checked = $true
$chkCollapseNetwork.Location = New-Object System.Drawing.Point(20,82)
$chkCollapseNetwork.Size = New-Object System.Drawing.Size(300,24)
$tabSession.Controls.Add($chkCollapseNetwork)
$lblBucket = New-Object System.Windows.Forms.Label
$lblBucket.Text = 'Bucket minutes:'
$lblBucket.Location = New-Object System.Drawing.Point(340,86)
$lblBucket.Size = New-Object System.Drawing.Size(95,22)
$tabSession.Controls.Add($lblBucket)
$numBucket = New-Object System.Windows.Forms.NumericUpDown
$numBucket.Minimum = 1
$numBucket.Maximum = 60
$numBucket.Value = 1
$numBucket.Location = New-Object System.Drawing.Point(440,82)
$numBucket.Size = New-Object System.Drawing.Size(70,24)
$tabSession.Controls.Add($numBucket)
$chkCorrelateSessions = New-Object System.Windows.Forms.CheckBox
$chkCorrelateSessions.Text = 'Correlate 4624 logons with 4634 logoffs'
$chkCorrelateSessions.Checked = $true
$chkCorrelateSessions.Location = New-Object System.Drawing.Point(20,112)
$chkCorrelateSessions.Size = New-Object System.Drawing.Size(330,24)
$tabSession.Controls.Add($chkCorrelateSessions)
$lblCorrelation = New-Object System.Windows.Forms.Label
$lblCorrelation.Text = 'Correlation uses AccountName + LogonId + EventCollector. SourceIpAddress is preserved from the 4624 logon event.'
$lblCorrelation.Location = New-Object System.Drawing.Point(360,116)
$lblCorrelation.Size = New-Object System.Drawing.Size(500,34)
$tabSession.Controls.Add($lblCorrelation)


$tabForensic = New-Object System.Windows.Forms.TabPage
$tabForensic.Text = 'Inventory / Mapping'
$tabs.TabPages.Add($tabForensic)
$btnInventory = New-Object System.Windows.Forms.Button
$btnInventory.Text = '1. Inventory'
$btnInventory.Location = New-Object System.Drawing.Point(20,25)
$btnInventory.Size = New-Object System.Drawing.Size(140,34)
$tabForensic.Controls.Add($btnInventory)
$btnMap4624 = New-Object System.Windows.Forms.Button
$btnMap4624.Text = '2. Mapping 4624'
$btnMap4624.Location = New-Object System.Drawing.Point(170,25)
$btnMap4624.Size = New-Object System.Drawing.Size(140,34)
$tabForensic.Controls.Add($btnMap4624)
$btnMap4634 = New-Object System.Windows.Forms.Button
$btnMap4634.Text = '3. Mapping 4634'
$btnMap4634.Location = New-Object System.Drawing.Point(320,25)
$btnMap4634.Size = New-Object System.Drawing.Size(140,34)
$tabForensic.Controls.Add($btnMap4634)
$btnFull = New-Object System.Windows.Forms.Button
$btnFull.Text = 'Full Workflow'
$btnFull.Location = New-Object System.Drawing.Point(470,25)
$btnFull.Size = New-Object System.Drawing.Size(140,34)
$tabForensic.Controls.Add($btnFull)
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = 'Open Output'
$btnOpen.Location = New-Object System.Drawing.Point(620,25)
$btnOpen.Size = New-Object System.Drawing.Size(140,34)
$tabForensic.Controls.Add($btnOpen)
$lblForensic = New-Object System.Windows.Forms.Label
$lblForensic.Text = 'Workflow: Inventory -> Mapping -> Extraction. Mapping reports validate Strings token positions used by the parsers.'
$lblForensic.Location = New-Object System.Drawing.Point(20,80)
$lblForensic.Size = New-Object System.Drawing.Size(820,50)
$tabForensic.Controls.Add($lblForensic)

$y += 198
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Location = New-Object System.Drawing.Point($left,$y)
$lblStatus.Size = New-Object System.Drawing.Size(872,24)
$form.Controls.Add($lblStatus)
$y += 28
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point($left,$y)
$progress.Size = New-Object System.Drawing.Size(872,24)
$progress.Style = 'Blocks'
$form.Controls.Add($progress)
$y += 36
$txtLogView = New-Object System.Windows.Forms.TextBox
$txtLogView.Multiline = $true
$txtLogView.ScrollBars = 'Vertical'
$txtLogView.ReadOnly = $true
$txtLogView.Location = New-Object System.Drawing.Point($left,$y)
$txtLogView.Size = New-Object System.Drawing.Size(872,105)
$form.Controls.Add($txtLogView)
$y += 118
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(755,$y)
$btnClose.Size = New-Object System.Drawing.Size(135,34)
$form.Controls.Add($btnClose)

function Add-UiLog {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    $txtLogView.AppendText($line + [Environment]::NewLine)
}

function Set-Busy {
    param([bool]$Busy, [string]$Status = '')
    foreach ($ctl in @($btnResolve,$btnBrowseEvtx,$btnBrowseOut,$btnBrowseLog,$btnRdp,$btnSession,$btnInventory,$btnMap4624,$btnMap4634,$btnFull,$btnOpen,$btnClose,$chkCollapseNetwork,$numBucket,$chkCorrelateSessions)) { $ctl.Enabled = -not $Busy }
    $progress.Style = if ($Busy) { 'Marquee' } else { 'Blocks' }
    if ($Status) { $lblStatus.Text = $Status }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-CommonParams {
    $script:DefaultLogDir = $txtLog.Text.Trim()
    Ensure-Directory -Path $script:DefaultLogDir
    $script:LogPath = Join-Path $script:DefaultLogDir ($script:ToolName + '.log')
    return @{
        UseLiveLog       = [bool]$chkLive.Checked
        EvtxFolder       = $txtEvtx.Text.Trim()
        IncludeSubfolders= [bool]$chkSub.Checked
        OutputDir        = $txtOut.Text.Trim()
        LogDir           = $txtLog.Text.Trim()
        UserFilter       = $txtUsers.Text.Trim()
        UseDateRange     = [bool]$chkDate.Checked
        StartTime        = [datetime]$dtFrom.Value
        EndTime          = [datetime]$dtTo.Value
        CollapseNetworkLogons = [bool]$chkCollapseNetwork.Checked
        BucketMinutes    = [int]$numBucket.Value
        CorrelateSessions = [bool]$chkCorrelateSessions.Checked
    }
}

function Invoke-GuiOperation {
    param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][scriptblock]$Action)
    try {
        Set-Busy -Busy $true -Status "$Name running..."
        Write-Log "$Name started."
        Add-UiLog "$Name started."
        $result = & $Action
        if ($result) { Add-UiLog "$Name report: $result" }
        $lblStatus.Text = "$Name completed."
        Write-Log "$Name completed."
        if (-not [string]::IsNullOrWhiteSpace($script:LastReport)) { Open-CsvReport -Path $script:LastReport }
        if ($result) { Show-InfoBox "$Name completed.`n$result" }
    } catch {
        $msg = "$Name failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Add-UiLog $msg
        $lblStatus.Text = $msg
        Show-ErrorBox $msg
    } finally {
        Set-Busy -Busy $false
    }
}

$chkLive.Add_CheckedChanged({
    $archive = -not $chkLive.Checked
    $txtEvtx.Enabled = $archive
    $btnBrowseEvtx.Enabled = $archive
    $chkSub.Enabled = $archive
})
$chkLive.Checked = $true

$btnBrowseEvtx.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $txtEvtx.Text = $dialog.SelectedPath }
})
$btnBrowseOut.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $txtOut.Text = $dialog.SelectedPath }
})
$btnBrowseLog.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $txtLog.Text = $dialog.SelectedPath }
})
$btnClose.Add_Click({ $form.Close() })
$btnOpen.Add_Click({
    try {
        if (-not [string]::IsNullOrWhiteSpace($script:LastReport) -and (Test-Path -LiteralPath $script:LastReport)) {
            Start-Process -FilePath $script:LastReport
        } else {
            Start-Process -FilePath $txtOut.Text.Trim()
        }
    } catch { Show-ErrorBox $_.Exception.Message }
})

$btnResolve.Add_Click({
    Invoke-GuiOperation -Name 'Resolve Channel' -Action {
        $p = Get-CommonParams
        Resolve-SecurityChannelLightweight -OutputDir $p.OutputDir -LogDir $p.LogDir
    }
})
$btnInventory.Add_Click({
    Invoke-GuiOperation -Name 'Inventory' -Action {
        $p = Get-CommonParams
        Invoke-Inventory -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime
    }
})
$btnMap4624.Add_Click({
    Invoke-GuiOperation -Name 'Mapping 4624' -Action {
        $p = Get-CommonParams
        Invoke-Mapping -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -EventId 4624 -MaxToken 20 -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime
    }
})
$btnMap4634.Add_Click({
    Invoke-GuiOperation -Name 'Mapping 4634' -Action {
        $p = Get-CommonParams
        Invoke-Mapping -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -EventId 4634 -MaxToken 8 -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime
    }
})
$btnRdp.Add_Click({
    Invoke-GuiOperation -Name 'RDP 4624 Extraction' -Action {
        $p = Get-CommonParams
        Invoke-RdpExtraction4624 -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UserFilter $p.UserFilter -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime
    }
})
$btnSession.Add_Click({
    Invoke-GuiOperation -Name 'Session Tracking Extraction' -Action {
        $p = Get-CommonParams
        Invoke-SessionTrackingExtraction -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UserFilter $p.UserFilter -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime -CollapseNetworkLogons $p.CollapseNetworkLogons -BucketMinutes $p.BucketMinutes -CorrelateSessions $p.CorrelateSessions
    }
})
$btnFull.Add_Click({
    Invoke-GuiOperation -Name 'Full Forensic Workflow' -Action {
        $p = Get-CommonParams
        [void](Invoke-Inventory -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime)
        [void](Invoke-Mapping -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -EventId 4624 -MaxToken 20 -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime)
        [void](Invoke-Mapping -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -EventId 4634 -MaxToken 8 -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime)
        $rdp = Invoke-RdpExtraction4624 -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UserFilter $p.UserFilter -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime
        $session = Invoke-SessionTrackingExtraction -UseLiveLog $p.UseLiveLog -EvtxFolder $p.EvtxFolder -IncludeSubfolders $p.IncludeSubfolders -OutputDir $p.OutputDir -LogDir $p.LogDir -UserFilter $p.UserFilter -UseDateRange $p.UseDateRange -StartTime $p.StartTime -EndTime $p.EndTime -CollapseNetworkLogons $p.CollapseNetworkLogons -BucketMinutes $p.BucketMinutes -CorrelateSessions $p.CorrelateSessions
        "RDP: $rdp`nSession: $session"
    }
})

[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    try { Write-Log "Unhandled UI exception: $($e.Exception.Message)" 'ERROR' } catch { }
    Show-ErrorBox "Unhandled UI exception: $($e.Exception.Message)"
})

Write-Log "Script initialized successfully. Version=$script:ToolVersion"
[void]$form.ShowDialog()
Write-Log 'Script ended.'

# End of Script
