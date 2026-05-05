#requires -Version 5.1
<#!
.SYNOPSIS
  Audits failed Active Directory logon attempts using Event ID 4625 from live or archived Security EVTX files.

.DESCRIPTION
  Production Log Parser-first GUI tool for Event ID 4625. Uses wevtutil snapshots for live Security analysis, archive-safe EVTX scanning, USA-English CSV output, calendar-based date/time filtering, failed-logon classification, risk scoring, compact intelligence summaries, and strict-mode-safe GUI error handling.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-05-v5.2.5-FAILED-LOGON-INTELLIGENCE-SUMMARY-CLEANUP
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
            [void][Win32Console]::ShowWindow($hWnd, $(if ($Visible) { 5 } else { 0 }))
        }
    }
    catch {}
}

if (-not $ShowConsole) { Set-ConsoleVisibility -Visible:$false }

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    }
    catch {}
}
catch {
    Write-Error "Failed to load WinForms assemblies. $($_.Exception.Message)"
    exit 1
}

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Security'
$script:SnapshotDir = Join-Path ([IO.Path]::GetTempPath()) 'BlueTeam-Tools-Snapshots'
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:Form = $null
$script:LastCsvPath = $null

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
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
    }
    catch {}
}

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory)][string]$Context
    )
    try { & $ScriptBlock }
    catch {
        Write-Log "$Context failed. $($_.Exception.Message)" 'ERROR'
        Set-Status "$Context failed. Check the execution log."
        Show-MessageBox -Message "$Context failed.`n$($_.Exception.Message)" -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    Write-Log "Unhandled WinForms exception. $($e.Exception.Message)" 'ERROR'
    Show-MessageBox -Message "Unhandled GUI exception.`n$($e.Exception.Message)" -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
})

[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    try { Write-Log "Unhandled AppDomain exception. $($e.ExceptionObject.ToString())" 'ERROR' } catch {}
})

function Set-Status {
    param([string]$Text)
    if ($script:StatusLabel -and $script:Form) {
        $script:StatusLabel.Text = $Text
        $script:Form.Refresh()
    }
}

function Set-Progress {
    param([int]$Value)
    if ($script:ProgressBar -and $script:Form) {
        if ($Value -lt $script:ProgressBar.Minimum) { $Value = $script:ProgressBar.Minimum }
        if ($Value -gt $script:ProgressBar.Maximum) { $Value = $script:ProgressBar.Maximum }
        $script:ProgressBar.Value = $Value
        $script:Form.Refresh()
    }
}

function Get-LogParserComObjects {
    try {
        $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
        $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        return @($logQuery, $inputFormat, $outputFormat)
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed. $($_.Exception.Message)"
    }
}

function Test-IsFileLocked {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $false
    }
    catch { return $true }
    finally { if ($stream) { $stream.Dispose() } }
}

function Test-IsActiveSecurityEvtx {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)
    return ($File.Name -ieq 'Security.evtx')
}

function Get-ArchiveSafeEvtxFiles {
    param([Parameter(Mandatory)][string[]]$Paths)
    $safe = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $path -ErrorAction Stop
        if (Test-IsActiveSecurityEvtx -File $file) {
            Write-Log "Skipped active/canonical Security.evtx in archived mode: $($file.FullName)" 'WARN'
            continue
        }
        if (Test-IsFileLocked -Path $file.FullName) {
            Write-Log "Skipped locked EVTX in archived mode: $($file.FullName)" 'WARN'
            continue
        }
        [void]$safe.Add($file.FullName)
    }
    return @($safe)
}

function New-TempPath {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][ValidateSet('.evtx','.csv')][string]$Extension
    )
    Ensure-Directory -Path $script:SnapshotDir
    return (Join-Path $script:SnapshotDir ('{0}-{1}{2}' -f $Prefix, ([guid]::NewGuid().ToString('N')), $Extension))
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) { throw "wevtutil.exe was not found at '$wevtutil'." }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.Arguments = ('epl "{0}" "{1}" /ow:true' -f $ChannelName, $DestinationPath)
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdErr = $proc.StandardError.ReadToEnd()
    [void]$proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "wevtutil export failed. ExitCode=$($proc.ExitCode). StdErr=$stdErr" }
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) { throw "Snapshot export did not create '$DestinationPath'." }
    Write-Log "Live Security snapshot exported: $DestinationPath"
}

function Convert-ToLogParserTimestamp {
    param([datetime]$Value)
    return $Value.ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-UserFilters {
    param([string]$RawText)
    if ([string]::IsNullOrWhiteSpace($RawText)) { return @('*') }
    $items = @($RawText -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (@($items).Count -eq 0) { return @('*') }
    return @($items | Select-Object -Unique)
}

function New-4625WhereClause {
    param(
        [string[]]$UserAccounts,
        [bool]$UseDateRange,
        [object]$FromTime,
        [object]$ToTime
    )
    $parts = New-Object System.Collections.Generic.List[string]
    [void]$parts.Add('EventID = 4625')

    $filters = @($UserAccounts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if (($filters -notcontains '*') -and @($filters).Count -gt 0) {
        $userClauses = New-Object System.Collections.Generic.List[string]
        foreach ($filter in $filters) {
            $escaped = $filter.Replace("'", "''")
            if ($escaped -match '^[^\\]+\\[^\\]+$') {
                $domain = ($escaped -split '\\', 2)[0]
                $user = ($escaped -split '\\', 2)[1]
                [void]$userClauses.Add("(EXTRACT_TOKEN(Strings, 6, '|') = '$domain' AND EXTRACT_TOKEN(Strings, 5, '|') = '$user')")
            }
            else {
                [void]$userClauses.Add("EXTRACT_TOKEN(Strings, 5, '|') = '$escaped'")
            }
        }
        if ($userClauses.Count -gt 0) { [void]$parts.Add(('({0})' -f ($userClauses -join ' OR '))) }
    }

    if ($UseDateRange) {
        if ($null -ne $FromTime) {
            $fromDate = [datetime]$FromTime
            [void]$parts.Add("TimeGenerated >= TO_TIMESTAMP('$(Convert-ToLogParserTimestamp -Value $fromDate)', 'yyyy-MM-dd HH:mm:ss')")
        }
        if ($null -ne $ToTime) {
            $toDate = [datetime]$ToTime
            [void]$parts.Add("TimeGenerated <= TO_TIMESTAMP('$(Convert-ToLogParserTimestamp -Value $toDate)', 'yyyy-MM-dd HH:mm:ss')")
        }
    }

    return ($parts -join ' AND ')
}

function Get-4625Header {
    return 'SourceEvtxPath,RecordNumber,EventTime,EventCollector,EventId,AccountName,AccountDomain,FailureStatus,FailureSubStatus,FailureReason,LogonType,SourceIpAddress,SourcePort,WorkstationName,ProcessName,SubjectAccountName,SubjectAccountDomain'
}

function Build-4625Query {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$CsvPath,
        [string[]]$UserAccounts,
        [bool]$UseDateRange,
        [object]$FromTime,
        [object]$ToTime
    )
    $escapedSource = $SourcePath.Replace("'", "''")
    $escapedCsv = $CsvPath.Replace("'", "''")
    $where = New-4625WhereClause -UserAccounts $UserAccounts -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime
@"
SELECT
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS EventCollector,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 5, '|') AS AccountName,
  EXTRACT_TOKEN(Strings, 6, '|') AS AccountDomain,
  EXTRACT_TOKEN(Strings, 7, '|') AS FailureStatus,
  EXTRACT_TOKEN(Strings, 9, '|') AS FailureSubStatus,
  EXTRACT_TOKEN(Strings, 8, '|') AS FailureReason,
  EXTRACT_TOKEN(Strings, 10, '|') AS LogonType,
  EXTRACT_TOKEN(Strings, 19, '|') AS SourceIpAddress,
  EXTRACT_TOKEN(Strings, 20, '|') AS SourcePort,
  EXTRACT_TOKEN(Strings, 13, '|') AS WorkstationName,
  EXTRACT_TOKEN(Strings, 18, '|') AS ProcessName,
  EXTRACT_TOKEN(Strings, 1, '|') AS SubjectAccountName,
  EXTRACT_TOKEN(Strings, 2, '|') AS SubjectAccountDomain
INTO '$escapedCsv'
FROM '$escapedSource'
WHERE $where
ORDER BY EventTime DESC
"@
}

function Invoke-LogParser4625ToCsv {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationCsv,
        [string[]]$UserAccounts,
        [bool]$UseDateRange,
        [object]$FromTime,
        [object]$ToTime,
        [Parameter(Mandatory)][string]$Context
    )
    $objects = Get-LogParserComObjects
    $query = Build-4625Query -SourcePath $SourcePath -CsvPath $DestinationCsv -UserAccounts $UserAccounts -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime
    if ($VerboseSqlLog) { Write-Log ("SQL [{0}]: {1}" -f $Context, $query) 'DEBUG' }
    $result = $objects[0].ExecuteBatch($query, $objects[1], $objects[2])
    Write-Log ("Log Parser ExecuteBatch [{0}] returned: {1}" -f $Context, $result)
    if (-not (Test-Path -LiteralPath $DestinationCsv -PathType Leaf)) {
        Set-Content -LiteralPath $DestinationCsv -Value (Get-4625Header) -Encoding UTF8
        Write-Log "No matching rows returned for source '$SourcePath'. Header-only CSV created." 'WARN'
    }
}

function Merge-CsvFiles {
    param(
        [string[]]$CsvPaths,
        [Parameter(Mandatory)][string]$OutputCsv
    )
    $valid = @($CsvPaths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if (@($valid).Count -eq 0) {
        Set-Content -LiteralPath $OutputCsv -Value (Get-4625Header) -Encoding UTF8
        return
    }
    $headerWritten = $false
    foreach ($csv in $valid) {
        $lines = @(Get-Content -LiteralPath $csv -Encoding UTF8)
        if (@($lines).Count -eq 0) { continue }
        if (-not $headerWritten) {
            Set-Content -LiteralPath $OutputCsv -Value $lines -Encoding UTF8
            $headerWritten = $true
        }
        elseif (@($lines).Count -gt 1) {
            Add-Content -LiteralPath $OutputCsv -Value ($lines | Select-Object -Skip 1) -Encoding UTF8
        }
    }
    if (-not $headerWritten) { Set-Content -LiteralPath $OutputCsv -Value (Get-4625Header) -Encoding UTF8 }
}

function Get-CsvRowCount {
    param([Parameter(Mandatory)][string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    return @((Import-Csv -LiteralPath $CsvPath)).Count
}


function Get-4625IntelligenceHeader {
    return 'ReportType,FailurePattern,RiskLevel,DetectionFlag,RecommendedAction,FailureCategory,FailureDescription,FirstEventTime,LastEventTime,EventCount,FirstRecordNumber,LastRecordNumber,EventCollector,EventId,AccountName,AccountDomain,IsMachineAccount,IsPrivilegedAccount,FailureStatus,FailureSubStatus,LogonType,SourceIpAddress,SourcePort,WorkstationName,ProcessName'
}

function Resolve-4625FailureDescription {
    param([string]$SubStatus)
    switch -Regex ($(if ($null -eq $SubStatus) { '' } else { $SubStatus }).ToLowerInvariant()) {
        '^0xc0000064$' { return @{ Category='ACCOUNT_NOT_FOUND'; Description='Account does not exist' } }
        '^0xc000006a$' { return @{ Category='BAD_PASSWORD'; Description='Bad password' } }
        '^0xc000006d$' { return @{ Category='BAD_USERNAME_OR_AUTH_INFO'; Description='Bad username or authentication information' } }
        '^0xc000006e$' { return @{ Category='ACCOUNT_RESTRICTION'; Description='Account restriction' } }
        '^0xc000006f$' { return @{ Category='INVALID_LOGON_HOURS'; Description='Invalid logon hours' } }
        '^0xc0000070$' { return @{ Category='INVALID_WORKSTATION'; Description='Invalid workstation' } }
        '^0xc0000071$' { return @{ Category='PASSWORD_EXPIRED'; Description='Password expired' } }
        '^0xc0000072$' { return @{ Category='ACCOUNT_DISABLED'; Description='Account disabled' } }
        '^0xc0000133$' { return @{ Category='CLOCK_SKEW'; Description='Clock skew between client and domain controller' } }
        '^0xc000015b$' { return @{ Category='LOGON_TYPE_NOT_GRANTED'; Description='User has not been granted the requested logon type' } }
        '^0xc0000193$' { return @{ Category='ACCOUNT_EXPIRED'; Description='Account expired' } }
        '^0xc0000224$' { return @{ Category='PASSWORD_CHANGE_REQUIRED'; Description='User must change password at next logon' } }
        '^0xc0000234$' { return @{ Category='ACCOUNT_LOCKED_OUT'; Description='Account locked out' } }
        '^0xc00002ee$' { return @{ Category='AUTHENTICATION_BLOCKED_OR_POLICY_RELATED'; Description='Authentication blocked or policy-related failure' } }
        '^0x0$' { return @{ Category='STATUS_NOT_PROVIDED'; Description='No detailed substatus provided' } }
        default { return @{ Category='UNKNOWN'; Description='Unknown or unmapped failure substatus' } }
    }
}

function Test-IsPrivilegedAccountName {
    param([string]$AccountName)
    $value = $(if ($null -eq $AccountName) { '' } else { $AccountName }).Trim()
    return ($value -match '^(?i)(administrator|administrador|admin|domain admin|enterprise admin)$')
}

function Get-4625DetectionContext {
    param(
        [Parameter(Mandatory)]$Row,
        [int]$EventCount = 1
    )
    $account = $(if ($null -eq $Row.AccountName) { '' } else { $Row.AccountName }).Trim()
    $sub = $(if ($null -eq $Row.FailureSubStatus) { '' } else { $Row.FailureSubStatus }).Trim().ToLowerInvariant()
    $logonType = $(if ($null -eq $Row.LogonType) { '' } else { $Row.LogonType }).Trim()
    $isMachine = $account.EndsWith('$')
    $isPriv = Test-IsPrivilegedAccountName -AccountName $account

    $pattern = 'GENERAL_FAILED_LOGON'
    $risk = 'LOW'
    $flag = 'REVIEW_FAILED_LOGON'
    $action = 'Review source host, account name, and failure substatus.'

    if ($isMachine -and $sub -eq '0xc0000064') {
        $pattern = 'STALE_OR_MISSING_MACHINE_ACCOUNT'
        $risk = 'LOW'
        $flag = 'CHECK_STALE_MACHINE_ACCOUNT'
        $action = 'Verify whether the workstation account exists in Active Directory and validate secure channel/domain join state.'
    }
    elseif ($isPriv -and $sub -eq '0xc000006a') {
        $pattern = 'ADMIN_PASSWORD_FAILURE'
        $risk = 'HIGH'
        $flag = 'INVESTIGATE_ADMIN_FAILURE'
        $action = 'Investigate the source host immediately and verify stored credentials, services, scheduled tasks, scripts, or unauthorized password attempts.'
    }
    elseif ($account -match '(?i)(svc|service|scan|scanner|cybr|cyber|vuln)') {
        $pattern = 'SERVICE_OR_SCANNER_ACCOUNT_FAILURE'
        $risk = 'MEDIUM'
        $flag = 'CHECK_SERVICE_CREDENTIAL'
        $action = 'Verify the service/scanner account password and confirm the source host is authorized.'
    }
    elseif ($sub -eq '0xc000006a') {
        $pattern = 'BAD_PASSWORD_FAILURE'
        $risk = 'MEDIUM'
        $flag = 'CHECK_BAD_PASSWORD_SOURCE'
        $action = 'Verify stale credentials on the source host and check for repeated attempts.'
    }
    elseif ($sub -eq '0xc0000064') {
        $pattern = 'ACCOUNT_NOT_FOUND_FAILURE'
        $risk = 'LOW'
        $flag = 'CHECK_INVALID_ACCOUNT_REFERENCE'
        $action = 'Check whether the account was removed, renamed, mistyped, or cached by an application/service.'
    }
    elseif ($sub -eq '0xc00002ee' -or $sub -eq '0x0') {
        $pattern = 'AUTHENTICATION_BLOCKED_OR_POLICY_RELATED'
        $risk = 'LOW'
        $flag = 'REVIEW_POLICY_OR_AUTHENTICATION_BLOCK'
        $action = 'Review authentication policy, firewall/security control behavior, and source context for this blocked or policy-related failure.'
    }

    if ($EventCount -ge 10 -and $risk -ne 'HIGH') {
        $risk = 'HIGH'
        $flag = 'POSSIBLE_PASSWORD_ATTACK_OR_LOOP'
        $action = 'High-volume repeated failures detected. Investigate source process, host ownership, and account lockout policy impact.'
    }
    elseif ($EventCount -ge 5 -and $risk -eq 'LOW') {
        $risk = 'MEDIUM'
    }

    return @{ Pattern=$pattern; Risk=$risk; Flag=$flag; Action=$action; IsMachineAccount=$isMachine; IsPrivilegedAccount=$isPriv }
}

function New-4625BucketKey {
    param(
        [string]$EventTime,
        [int]$BucketMinutes
    )
    if ($BucketMinutes -lt 1) { $BucketMinutes = 1 }

    $safeEventTime = if ($null -eq $EventTime) { '' } else { [string]$EventTime }
    $parsedTime = [datetime]::MinValue
    if (-not [datetime]::TryParse($safeEventTime, [ref]$parsedTime)) {
        return 'UNKNOWN_TIME'
    }

    $minute = [int]$parsedTime.Minute
    $bucket = [int]($minute - ($minute % $BucketMinutes))
    return ('{0:yyyy-MM-dd HH}:{1:00}:00' -f $parsedTime, $bucket)
}

function New-4625SafeGroupKey {
    param([Parameter(Mandatory)]$Row)
    $values = @(
        [string]$Row.BucketStart,
        [string]$Row.AccountName,
        [string]$Row.AccountDomain,
        [string]$Row.FailureStatus,
        [string]$Row.FailureSubStatus,
        [string]$Row.LogonType,
        [string]$Row.SourceIpAddress,
        [string]$Row.WorkstationName
    )
    return (($values | ForEach-Object { ($_ -replace '\|', '%7C') }) -join '|')
}

function New-4625IntelligenceObject {
    param(
        $ReportType,
        $FirstRow,
        $LastRow,
        $EventCount,
        $Collapsed,
        $SourcePortTextOverride = $null
    )

    $safeCount = 1
    [void][int]::TryParse(([string]$EventCount), [ref]$safeCount)
    if ($safeCount -lt 1) { $safeCount = 1 }

    $desc = Resolve-4625FailureDescription -SubStatus ([string]$FirstRow.FailureSubStatus)
    $ctx = Get-4625DetectionContext -Row $FirstRow -EventCount $safeCount

    $isMachineText = if ([bool]$ctx.IsMachineAccount) { 'TRUE' } else { 'FALSE' }
    $isPrivText = if ([bool]$ctx.IsPrivilegedAccount) { 'TRUE' } else { 'FALSE' }
    $sourcePortText = if ($null -ne $SourcePortTextOverride -and [string]$SourcePortTextOverride -ne '') { [string]$SourcePortTextOverride } else { [string]$FirstRow.SourcePort }

    return [pscustomobject]([ordered]@{
        ReportType              = [string]$ReportType
        FailurePattern          = [string]$ctx.Pattern
        RiskLevel               = [string]$ctx.Risk
        DetectionFlag           = [string]$ctx.Flag
        RecommendedAction       = [string]$ctx.Action
        FailureCategory         = [string]$desc.Category
        FailureDescription      = [string]$desc.Description
        FirstEventTime          = [string]$FirstRow.EventTime
        LastEventTime           = [string]$LastRow.EventTime
        EventCount              = [string]$safeCount
        FirstRecordNumber       = [string]$FirstRow.RecordNumber
        LastRecordNumber        = [string]$LastRow.RecordNumber
        EventCollector          = [string]$FirstRow.EventCollector
        EventId                 = [string]$FirstRow.EventId
        AccountName             = [string]$FirstRow.AccountName
        AccountDomain           = [string]$FirstRow.AccountDomain
        IsMachineAccount        = $isMachineText
        IsPrivilegedAccount     = $isPrivText
        FailureStatus           = [string]$FirstRow.FailureStatus
        FailureSubStatus        = [string]$FirstRow.FailureSubStatus
        LogonType               = [string]$FirstRow.LogonType
        SourceIpAddress         = [string]$FirstRow.SourceIpAddress
        SourcePort              = $sourcePortText
        WorkstationName         = [string]$FirstRow.WorkstationName
        ProcessName             = [string]$FirstRow.ProcessName
    })
}

function ConvertTo-4625IntelligenceReport {
    param(
        [Parameter(Mandatory)][string]$RawCsv,
        [Parameter(Mandatory)][string]$OutputCsv,
        $CollapseRepeatedFailures = $true,
        $BucketMinutes = 5
    )

    $bucketSize = 5
    [void][int]::TryParse(([string]$BucketMinutes), [ref]$bucketSize)
    if ($bucketSize -lt 1) { $bucketSize = 1 }

    Write-Log 'Intelligence phase started.'

    if (-not (Test-Path -LiteralPath $RawCsv -PathType Leaf)) {
        Set-Content -LiteralPath $OutputCsv -Value (Get-4625IntelligenceHeader) -Encoding UTF8
        Write-Log 'Raw CSV not found. Header-only intelligence CSV created.' 'WARN'
        return
    }

    $rows = @(Import-Csv -LiteralPath $RawCsv)
    Write-Log ("Raw CSV imported. Rows={0}" -f @($rows).Count)

    if (@($rows).Count -eq 0) {
        Set-Content -LiteralPath $OutputCsv -Value (Get-4625IntelligenceHeader) -Encoding UTF8
        Write-Log 'Raw CSV has no rows. Header-only intelligence CSV created.' 'WARN'
        return
    }

    $normalizedRows = @()
    foreach ($r in $rows) {
        $eventTimeText = if ($null -eq $r.EventTime) { '' } else { [string]$r.EventTime }
        $normalizedRows += [pscustomobject]([ordered]@{
            BucketStart          = [string](New-4625BucketKey -EventTime $eventTimeText -BucketMinutes $bucketSize)
            SourceEvtxPath       = if ($null -eq $r.SourceEvtxPath) { '' } else { [string]$r.SourceEvtxPath }
            RecordNumber         = if ($null -eq $r.RecordNumber) { '' } else { [string]$r.RecordNumber }
            EventTime            = $eventTimeText
            EventCollector       = if ($null -eq $r.EventCollector) { '' } else { [string]$r.EventCollector }
            EventId              = if ($null -eq $r.EventId) { '' } else { [string]$r.EventId }
            AccountName          = if ($null -eq $r.AccountName) { '' } else { [string]$r.AccountName }
            AccountDomain        = if ($null -eq $r.AccountDomain) { '' } else { [string]$r.AccountDomain }
            FailureStatus        = if ($null -eq $r.FailureStatus) { '' } else { [string]$r.FailureStatus }
            FailureSubStatus     = if ($null -eq $r.FailureSubStatus) { '' } else { [string]$r.FailureSubStatus }
            FailureReason        = if ($null -eq $r.FailureReason) { '' } else { [string]$r.FailureReason }
            LogonType            = if ($null -eq $r.LogonType) { '' } else { [string]$r.LogonType }
            SourceIpAddress      = if ($null -eq $r.SourceIpAddress) { '' } else { [string]$r.SourceIpAddress }
            SourcePort           = if ($null -eq $r.SourcePort) { '' } else { [string]$r.SourcePort }
            WorkstationName      = if ($null -eq $r.WorkstationName) { '' } else { [string]$r.WorkstationName }
            ProcessName          = if ($null -eq $r.ProcessName) { '' } else { [string]$r.ProcessName }
            SubjectAccountName   = if ($null -eq $r.SubjectAccountName) { '' } else { [string]$r.SubjectAccountName }
            SubjectAccountDomain = if ($null -eq $r.SubjectAccountDomain) { '' } else { [string]$r.SubjectAccountDomain }
        })
    }

    Write-Log ("Rows normalized. Rows={0}; Collapse={1}; BucketMinutes={2}" -f @($normalizedRows).Count, $CollapseRepeatedFailures, $bucketSize)

    $out = @()
    if ([bool]$CollapseRepeatedFailures) {
        $groupMap = @{}
        foreach ($row in $normalizedRows) {
            $key = [string](New-4625SafeGroupKey -Row $row)
            if (-not $groupMap.ContainsKey($key)) { $groupMap[$key] = @() }
            $groupMap[$key] = @($groupMap[$key]) + @($row)
        }

        Write-Log ("Collapse groups created. Groups={0}" -f $groupMap.Keys.Count)

        foreach ($key in @($groupMap.Keys)) {
            $items = @($groupMap[$key] | Sort-Object -Property EventTime)
            if (@($items).Count -eq 0) { continue }
            $first = $items[0]
            $last = $items[@($items).Count - 1]
            $ports = @($items | ForEach-Object { [string]$_.SourcePort } | Where-Object { $_ -and $_ -ne '-' } | Select-Object -Unique)
            $sourcePortText = if (@($items).Count -eq 1 -or @($ports).Count -le 1) {
                if (@($ports).Count -eq 1) { [string]$ports[0] } else { [string]$first.SourcePort }
            }
            else {
                'MULTIPLE'
            }
            $out += New-4625IntelligenceObject -ReportType 'SUMMARY' -FirstRow $first -LastRow $last -EventCount (@($items).Count) -Collapsed 'TRUE' -SourcePortTextOverride $sourcePortText
        }
    }
    else {
        foreach ($row in $normalizedRows) {
            $out += New-4625IntelligenceObject -ReportType 'RAW_ENRICHED' -FirstRow $row -LastRow $row -EventCount 1 -Collapsed 'FALSE' -SourcePortTextOverride ([string]$row.SourcePort)
        }
    }

    Write-Log ("Intelligence objects created. Rows={0}" -f @($out).Count)

    if (@($out).Count -eq 0) {
        Set-Content -LiteralPath $OutputCsv -Value (Get-4625IntelligenceHeader) -Encoding UTF8
        Write-Log 'No intelligence rows produced. Header-only intelligence CSV created.' 'WARN'
        return
    }

    $out | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Log ("Intelligence CSV exported: {0}" -f $OutputCsv)
}

function Select-FolderDialog {
    param([string]$Description, [string]$InitialPath)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) { $dialog.SelectedPath = $InitialPath }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    return $null
}

function Get-EvtxSources {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [System.Collections.Generic.List[string]]$TempArtifacts
    )
    if ($UseLiveLog) {
        $snapshot = New-TempPath -Prefix ('Security-{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss')) -Extension '.evtx'
        [void]$TempArtifacts.Add($snapshot)
        Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $snapshot
        return @($snapshot)
    }
    if ([string]::IsNullOrWhiteSpace($EvtxFolder)) { throw 'EVTX folder is required when live Security channel mode is disabled.' }
    if (-not (Test-Path -LiteralPath $EvtxFolder -PathType Container)) { throw "EVTX folder does not exist: $EvtxFolder" }
    $searchOption = if ($IncludeSubfolders) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
    $all = @([System.IO.Directory]::EnumerateFiles($EvtxFolder, '*.evtx', $searchOption))
    $safe = @(Get-ArchiveSafeEvtxFiles -Paths $all)
    if (@($safe).Count -eq 0) { throw "No archive-safe .evtx files were found in '$EvtxFolder'." }
    return $safe
}

function Test-LiveChannelAccess {
    Set-Progress 10
    Set-Status 'Resolving Security channel...'
    $temp = New-Object System.Collections.Generic.List[string]
    try {
        $sources = @(Get-EvtxSources -UseLiveLog $true -EvtxFolder '' -IncludeSubfolders $false -TempArtifacts $temp)
        $probeCsv = New-TempPath -Prefix 'Security4625Probe' -Extension '.csv'
        [void]$temp.Add($probeCsv)
        Invoke-LogParser4625ToCsv -SourcePath $sources[0] -DestinationCsv $probeCsv -UserAccounts @('*') -UseDateRange $false -FromTime $null -ToTime $null -Context 'ResolveSecurityChannel'
        Set-Progress 100
        Set-Status 'Security channel resolved successfully.'
        Show-MessageBox -Message 'Security channel snapshot and Log Parser probe completed successfully.' -Title 'Resolve Channel'
    }
    finally {
        foreach ($p in $temp) { if ($p -and (Test-Path -LiteralPath $p)) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
        Set-Progress 0
    }
}

function Start-Event4625Processing {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string[]]$UserAccounts,
        [bool]$UseDateRange,
        [object]$FromTime,
        [object]$ToTime,
        [bool]$CollapseRepeatedFailures,
        [int]$BucketMinutes
    )
    $resolvedOutput = if ([string]::IsNullOrWhiteSpace($OutputFolder)) { $script:DefaultOutputDir } else { $OutputFolder }
    Ensure-Directory -Path $resolvedOutput
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $rawCsv = Join-Path $resolvedOutput ('{0}-EventID4625-FailedLogons-RAW-{1}.csv' -f $script:MachineName, $stamp)
    $intelCsv = Join-Path $resolvedOutput ('{0}-EventID4625-FailedLogons-INTELLIGENCE-{1}.csv' -f $script:MachineName, $stamp)
    $tempArtifacts = New-Object System.Collections.Generic.List[string]
    $tempCsvs = New-Object System.Collections.Generic.List[string]
    try {
        Write-Log ("Starting Event ID 4625 intelligence analysis. UseLiveLog={0}; Folder='{1}'; IncludeSubfolders={2}; OutputFolder='{3}'; DateRange={4}; Collapse={5}; BucketMinutes={6}" -f $UseLiveLog, $EvtxFolder, $IncludeSubfolders, $resolvedOutput, $UseDateRange, $CollapseRepeatedFailures, $BucketMinutes)
        Set-Progress 10
        Set-Status 'Preparing EVTX sources...'
        $sources = @(Get-EvtxSources -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -TempArtifacts $tempArtifacts)
        $i = 0
        foreach ($source in $sources) {
            $i++
            $pct = [math]::Min(82, 15 + [int](($i / [double]@($sources).Count) * 62))
            Set-Progress $pct
            Set-Status ('Processing EVTX {0} of {1}...' -f $i, @($sources).Count)
            $tempCsv = New-TempPath -Prefix 'EventID4625' -Extension '.csv'
            [void]$tempArtifacts.Add($tempCsv)
            Invoke-LogParser4625ToCsv -SourcePath $source -DestinationCsv $tempCsv -UserAccounts $UserAccounts -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime -Context ("Extraction4625:{0}" -f $source)
            [void]$tempCsvs.Add($tempCsv)
        }
        Set-Progress 86
        Set-Status 'Consolidating raw CSV report...'
        Merge-CsvFiles -CsvPaths @($tempCsvs) -OutputCsv $rawCsv
        $rawCount = Get-CsvRowCount -CsvPath $rawCsv
        Set-Progress 93
        Set-Status 'Building failed-logon intelligence report...'
        ConvertTo-4625IntelligenceReport -RawCsv $rawCsv -OutputCsv $intelCsv -CollapseRepeatedFailures $CollapseRepeatedFailures -BucketMinutes $BucketMinutes
        $intelCount = Get-CsvRowCount -CsvPath $intelCsv
        $script:LastCsvPath = $intelCsv
        Write-Log "Event ID 4625 intelligence analysis completed. RawRows=$rawCount; IntelligenceRows=$intelCount; Raw='$rawCsv'; Intelligence='$intelCsv'"
        Set-Progress 100
        Set-Status ("Completed. Raw events: {0}; intelligence rows: {1}" -f $rawCount, $intelCount)
        if ($AutoOpen -and (Test-Path -LiteralPath $intelCsv -PathType Leaf)) { Start-Process -FilePath $intelCsv }
        Show-MessageBox -Message "Raw failed logon events: $rawCount`nIntelligence rows: $intelCount`n`nIntelligence CSV:`n$intelCsv`n`nRaw CSV:`n$rawCsv" -Title 'Completed'
    }
    finally {
        foreach ($artifact in $tempArtifacts) { if ($artifact -and (Test-Path -LiteralPath $artifact)) { Remove-Item -LiteralPath $artifact -Force -ErrorAction SilentlyContinue } }
        Set-Progress 0
    }
}

function Open-LastCsv {
    if ($script:LastCsvPath -and (Test-Path -LiteralPath $script:LastCsvPath -PathType Leaf)) { Start-Process -FilePath $script:LastCsvPath; return }
    Show-MessageBox -Message 'No CSV report has been generated in this session.' -Title 'Open CSV' -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
}

Ensure-Directory -Path $script:LogDir
Write-Log 'Script started.'

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Failed Logon Auditor - Event ID 4625 v5.2.0'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(910, 600)
$form.MinimumSize = New-Object System.Drawing.Size(910, 600)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$script:Form = $form

$leftLabel = 22
$leftControl = 190
$controlWidth = 560
$buttonX = 765
$buttonW = 110
$rowY = 22
$rowStep = 38

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Text = 'Use live Security channel (snapshot via wevtutil)'
$checkUseLive.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkUseLive.Size = New-Object System.Drawing.Size(360, 24)
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Size = New-Object System.Drawing.Size($buttonW, 28)
$buttonResolve.Location = New-Object System.Drawing.Point($buttonX, ($rowY - 2))
$form.Controls.Add($buttonResolve)

$rowY += $rowStep
$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Text = 'EVTX Folder:'
$labelEvtx.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelEvtx.AutoSize = $true
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textEvtx.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textEvtx.Text = 'L:\Security'
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = 'Browse...'
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonW, 28)
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, ($rowY - 2))
$form.Controls.Add($buttonBrowseEvtx)

$rowY += $rowStep
$checkSubfolders = New-Object System.Windows.Forms.CheckBox
$checkSubfolders.Text = 'Include subfolders when scanning archived EVTX'
$checkSubfolders.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkSubfolders.Size = New-Object System.Drawing.Size(360, 24)
$checkSubfolders.Checked = $true
$form.Controls.Add($checkSubfolders)

$rowY += $rowStep
$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'Account Filter:'
$labelUsers.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelUsers.AutoSize = $true
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textUsers.Size = New-Object System.Drawing.Size($controlWidth, 50)
$textUsers.Multiline = $true
$textUsers.ScrollBars = 'Vertical'
$textUsers.Text = '*'
$form.Controls.Add($textUsers)

$rowY += 62
$checkDateRange = New-Object System.Windows.Forms.CheckBox
$checkDateRange.Text = 'Use date/time range'
$checkDateRange.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkDateRange.Size = New-Object System.Drawing.Size(170, 24)
$checkDateRange.Checked = $false
$form.Controls.Add($checkDateRange)

$labelFrom = New-Object System.Windows.Forms.Label
$labelFrom.Text = 'From:'
$labelFrom.Location = New-Object System.Drawing.Point(($leftControl + 185), ($rowY + 4))
$labelFrom.AutoSize = $true
$form.Controls.Add($labelFrom)

$dateFrom = New-Object System.Windows.Forms.DateTimePicker
$dateFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateFrom.ShowUpDown = $false
$dateFrom.Location = New-Object System.Drawing.Point(($leftControl + 230), $rowY)
$dateFrom.Size = New-Object System.Drawing.Size(170, 24)
$dateFrom.Value = (Get-Date).AddDays(-1)
$form.Controls.Add($dateFrom)

$labelTo = New-Object System.Windows.Forms.Label
$labelTo.Text = 'To:'
$labelTo.Location = New-Object System.Drawing.Point(($leftControl + 415), ($rowY + 4))
$labelTo.AutoSize = $true
$form.Controls.Add($labelTo)

$dateTo = New-Object System.Windows.Forms.DateTimePicker
$dateTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateTo.ShowUpDown = $false
$dateTo.Location = New-Object System.Drawing.Point(($leftControl + 445), $rowY)
$dateTo.Size = New-Object System.Drawing.Size(170, 24)
$dateTo.Value = Get-Date
$form.Controls.Add($dateTo)

$rowY += $rowStep
$checkCollapse = New-Object System.Windows.Forms.CheckBox
$checkCollapse.Text = 'Collapse repeated failures into intelligence summary'
$checkCollapse.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$checkCollapse.Size = New-Object System.Drawing.Size(335, 24)
$checkCollapse.Checked = $true
$form.Controls.Add($checkCollapse)

$labelBucket = New-Object System.Windows.Forms.Label
$labelBucket.Text = 'Bucket (min):'
$labelBucket.Location = New-Object System.Drawing.Point(($leftControl + 360), ($rowY + 4))
$labelBucket.AutoSize = $true
$form.Controls.Add($labelBucket)

$textBucket = New-Object System.Windows.Forms.TextBox
$textBucket.Location = New-Object System.Drawing.Point(($leftControl + 445), $rowY)
$textBucket.Size = New-Object System.Drawing.Size(70, 24)
$textBucket.Text = '5'
$form.Controls.Add($textBucket)

$rowY += $rowStep
$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = 'Output Folder:'
$labelOutput.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelOutput.AutoSize = $true
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textOutput.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textOutput.Text = $script:DefaultOutputDir
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = 'Browse...'
$buttonBrowseOutput.Size = New-Object System.Drawing.Size($buttonW, 28)
$buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonX, ($rowY - 2))
$form.Controls.Add($buttonBrowseOutput)

$rowY += $rowStep
$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Text = 'Log Folder:'
$labelLog.Location = New-Object System.Drawing.Point($leftLabel, ($rowY + 3))
$labelLog.AutoSize = $true
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point($leftControl, $rowY)
$textLog.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textLog.Text = $script:LogDir
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = 'Browse...'
$buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonW, 28)
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, ($rowY - 2))
$form.Controls.Add($buttonBrowseLog)

$rowY += 50
$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = New-Object System.Drawing.Point(22, $rowY)
$script:ProgressBar.Size = New-Object System.Drawing.Size(850, 20)
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$form.Controls.Add($script:ProgressBar)

$rowY += 30
$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.Location = New-Object System.Drawing.Point(22, $rowY)
$script:StatusLabel.Size = New-Object System.Drawing.Size(850, 24)
$form.Controls.Add($script:StatusLabel)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Size = New-Object System.Drawing.Size(130, 34)
$buttonStart.Location = New-Object System.Drawing.Point(455, 510)
$form.Controls.Add($buttonStart)

$buttonOpen = New-Object System.Windows.Forms.Button
$buttonOpen.Text = 'Open CSV'
$buttonOpen.Size = New-Object System.Drawing.Size(130, 34)
$buttonOpen.Location = New-Object System.Drawing.Point(600, 510)
$form.Controls.Add($buttonOpen)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Size = New-Object System.Drawing.Size(130, 34)
$buttonClose.Location = New-Object System.Drawing.Point(745, 510)
$form.Controls.Add($buttonClose)

$toggleMode = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = -not $isLive
    $buttonBrowseEvtx.Enabled = -not $isLive
    $checkSubfolders.Enabled = -not $isLive
}

$checkUseLive.Add_CheckedChanged($toggleMode)
& $toggleMode

$toggleDateRange = {
    $enabled = $checkDateRange.Checked
    $dateFrom.Enabled = $enabled
    $dateTo.Enabled = $enabled
    $labelFrom.Enabled = $enabled
    $labelTo.Enabled = $enabled
}
$checkDateRange.Add_CheckedChanged($toggleDateRange)
& $toggleDateRange

$checkCollapse.Add_CheckedChanged({ $textBucket.Enabled = $checkCollapse.Checked; $labelBucket.Enabled = $checkCollapse.Checked })
$textBucket.Enabled = $checkCollapse.Checked
$labelBucket.Enabled = $checkCollapse.Checked

$buttonBrowseEvtx.Add_Click({ Invoke-GuiSafe -Context 'Browse EVTX Folder' -ScriptBlock { $selected = Select-FolderDialog -Description 'Select a folder containing Security EVTX files' -InitialPath $textEvtx.Text; if ($selected) { $textEvtx.Text = $selected } } })
$buttonBrowseOutput.Add_Click({ Invoke-GuiSafe -Context 'Browse Output Folder' -ScriptBlock { $selected = Select-FolderDialog -Description 'Select the CSV output folder' -InitialPath $textOutput.Text; if ($selected) { $textOutput.Text = $selected } } })
$buttonBrowseLog.Add_Click({ Invoke-GuiSafe -Context 'Browse Log Folder' -ScriptBlock { $selected = Select-FolderDialog -Description 'Select the log folder' -InitialPath $textLog.Text; if ($selected) { $textLog.Text = $selected; $script:LogDir = $selected; $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log'); Ensure-Directory -Path $script:LogDir } } })
$buttonResolve.Add_Click({ Invoke-GuiSafe -Context 'Resolve Channel' -ScriptBlock { Test-LiveChannelAccess } })
$buttonOpen.Add_Click({ Invoke-GuiSafe -Context 'Open CSV' -ScriptBlock { Open-LastCsv } })
$buttonClose.Add_Click({ $form.Close() })

$buttonStart.Add_Click({
    Invoke-GuiSafe -Context 'Event ID 4625 analysis' -ScriptBlock {
        $buttonStart.Enabled = $false
        $buttonResolve.Enabled = $false
        try {
            $fromValue = $null
            $toValue = $null
            if ($checkDateRange.Checked) {
                $fromValue = [datetime]$dateFrom.Value
                $toValue = [datetime]$dateTo.Value
                if ($toValue -lt $fromValue) { throw 'The To date/time must be greater than or equal to the From date/time.' }
            }
            $bucket = 5
            if (-not [int]::TryParse($textBucket.Text, [ref]$bucket)) { $bucket = 5 }
            if ($bucket -lt 1) { $bucket = 1 }
            Start-Event4625Processing -UseLiveLog $checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders $checkSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts (Get-UserFilters -RawText $textUsers.Text) -UseDateRange $checkDateRange.Checked -FromTime $fromValue -ToTime $toValue -CollapseRepeatedFailures $checkCollapse.Checked -BucketMinutes $bucket
        }
        finally {
            $buttonStart.Enabled = $true
            $buttonResolve.Enabled = $true
        }
    }
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
Write-Log 'Script ended.'

# End of script
