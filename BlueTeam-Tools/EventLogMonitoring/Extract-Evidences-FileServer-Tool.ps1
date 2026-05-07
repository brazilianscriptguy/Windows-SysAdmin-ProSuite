<#
.SYNOPSIS
  FileServer Evidence Extraction Tool - Multi Scenario

.DESCRIPTION
  Multi-scenario forensic tool for institutional FileServer investigations.
  Supports:
    1. Who CAN access a target folder/file path (NTFS ACL inventory).
    2. Who DID access target files/folders using Security Event ID 4663.
    3. Official evidence report with legal-safe access classification.
    4. RAW forensic CSV preservation.

  Important:
    Windows Event ID 4663 cannot reliably distinguish "viewed" from "downloaded".
    READ access means the object was accessed for read-type operations and may indicate viewing or copying.

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  2026-05-06-v1.0.1-FILESERVER-EVIDENCE-MULTI-SCENARIO-CONSOLE-HIDDEN
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not $ShowConsole) {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Console {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

        $consolePtr = [Win32Console]::GetConsoleWindow()

        if ($consolePtr -ne [IntPtr]::Zero) {
            [Win32Console]::ShowWindow($consolePtr, 0) | Out-Null
        }
    }
    catch {
        # Console hiding is best-effort only.
    }
}


try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
} catch {}

[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $e)
    try {
        Write-Log -Message ("Unhandled UI exception: {0}" -f $e.Exception.Message) -Level "ERROR"
        Show-Message -Message ("Unhandled UI exception:`r`n{0}" -f $e.Exception.Message) -Type "ERROR"
    } catch {}
})

[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $e)
    try {
        $msg = [string]$e.ExceptionObject
        Write-Log -Message ("Unhandled application exception: {0}" -f $msg) -Level "ERROR"
    } catch {}
})

$script:Version = "2026-05-06-v1.0.1-FILESERVER-EVIDENCE-MULTI-SCENARIO-CONSOLE-HIDDEN"
$script:ToolName = "FileServerEvidenceTool"
$script:DefaultLogDir = "C:\Logs-TEMP"
$script:LastOutputPath = $null
$script:LastRawPath = $null
$script:SnapshotDir = Join-Path $env:TEMP "BlueTeam-Tools-Snapshots"

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Ensure-Directory -Path $script:DefaultLogDir
Ensure-Directory -Path $script:SnapshotDir
$script:LogPath = Join-Path $script:DefaultLogDir "FileServerEvidenceTool.log"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )
    try {
        $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    } catch {}
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Type = "INFO",
        [string]$Title = "FileServer Evidence Tool"
    )

    $icon = switch ($Type) {
        "ERROR" { [System.Windows.Forms.MessageBoxIcon]::Error }
        "WARN"  { [System.Windows.Forms.MessageBoxIcon]::Warning }
        default { [System.Windows.Forms.MessageBoxIcon]::Information }
    }

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $icon
    ) | Out-Null
}

function Invoke-GuiSafe {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$ErrorPrefix = "Operation failed"
    )
    try {
        & $Action
    } catch {
        $msg = "{0}: {1}" -f $ErrorPrefix, $_.Exception.Message
        Write-Log -Message $msg -Level "ERROR"
        Show-Message -Message $msg -Type "ERROR"
    }
}

function Get-LogParserPath {
    $candidates = @(
        "C:\Program Files (x86)\Log Parser 2.2\LogParser.exe",
        "C:\Program Files\Log Parser 2.2\LogParser.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    throw "Log Parser 2.2 was not found. Install Microsoft Log Parser 2.2 or adjust the executable path."
}

function Export-SecuritySnapshot {
    $snapshot = Join-Path $script:SnapshotDir ("Security-FileServerEvidence-{0}-{1}.evtx" -f (Get-Date -Format "yyyyMMdd_HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0,8)))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wevtutil.exe"
    $psi.Arguments = "epl Security `"$snapshot`" /ow:true"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    $err = $p.StandardError.ReadToEnd()
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshot)) {
        throw "Security snapshot export failed. ExitCode=$($p.ExitCode). $err"
    }
    Write-Log -Message ("Live Security snapshot exported: {0}" -f $snapshot)
    return $snapshot
}

function Resolve-SecurityEvtxFolder {
    $paths = @()

    try {
        $classic = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security"
        if (Test-Path $classic) {
            $file = (Get-ItemProperty -Path $classic -Name File -ErrorAction SilentlyContinue).File
            if ($file) { $paths += [Environment]::ExpandEnvironmentVariables([string]$file) }
        }
    } catch {}

    try {
        $winevt = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Security"
        if (Test-Path $winevt) {
            $file = (Get-ItemProperty -Path $winevt -Name File -ErrorAction SilentlyContinue).File
            if ($file) { $paths += [Environment]::ExpandEnvironmentVariables([string]$file) }
        }
    } catch {}

    foreach ($p in $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) {
        try {
            $dir = Split-Path -Path $p -Parent
            if ($dir -and (Test-Path -LiteralPath $dir)) {
                return $dir
            }
        } catch {}
    }

    $fallback = "C:\Windows\System32\winevt\Logs"
    if (Test-Path -LiteralPath $fallback) { return $fallback }
    return $null
}

function Convert-DateForLogParser {
    param([datetime]$Date)
    return $Date.ToString("yyyy-MM-dd HH:mm:ss")
}

function Convert-AccessMaskToType {
    param(
        [string]$AccessMask,
        [string]$AccessList
    )

    $combined = ("{0} {1}" -f $AccessMask, $AccessList).ToUpperInvariant()

    if ($combined -match "0X10000|DELETE|%%1537") { return "DELETE" }
    if ($combined -match "0X2|WRITE|APPEND|%%4417|%%4418|%%4419") { return "WRITE_OR_MODIFY" }
    if ($combined -match "0X1|READ|READ_DATA|%%4416") { return "READ" }
    return "OTHER_OR_UNMAPPED"
}

function Get-LegalSafeInterpretation {
    param([string]$AccessType)

    switch ($AccessType) {
        "READ" { return "Read access recorded. This may indicate viewing, opening, previewing, copying, or another read-type operation. Windows auditing does not reliably distinguish viewing from downloading." }
        "WRITE_OR_MODIFY" { return "Write or modification-related access recorded." }
        "DELETE" { return "Deletion-related access recorded or delete permission used." }
        default { return "Access recorded, but the operation type could not be conclusively mapped from the available audit fields." }
    }
}

function Normalize-PathForSqlLike {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim()
    $p = $p -replace "'", "''"
    return $p
}

function Get-EvtxSourceExpression {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders
    )

    if ($UseLiveLog) {
        return Export-SecuritySnapshot
    }

    if ([string]::IsNullOrWhiteSpace($EvtxFolder)) {
        $resolved = Resolve-SecurityEvtxFolder
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            $EvtxFolder = $resolved
        }
    }

    if ([string]::IsNullOrWhiteSpace($EvtxFolder) -or -not (Test-Path -LiteralPath $EvtxFolder -PathType Container)) {
        throw "Please provide a valid EVTX folder or enable live Security channel mode."
    }

    # PATH-AGNOSTIC ARCHIVE RULE:
    # Analyze any .evtx file in the selected folder. Do not prefer Archive-*.evtx
    # and do not assume canonical Security.evtx naming semantics.
    return (Join-Path $EvtxFolder "*.evtx")
}


function Invoke-LogParserQuery {
    param(
        [Parameter(Mandatory)][string]$Sql,
        [Parameter(Mandatory)][string]$Context
    )

    $logParser = Get-LogParserPath

    $tmpSql = Join-Path $env:TEMP ("FileServerEvidence-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -Path $tmpSql -Value $Sql -Encoding ASCII

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $logParser
    $psi.Arguments = "-i:EVT -o:CSV file:`"$tmpSql`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    Write-Log -Message ("Log Parser execution [{0}] ExitCode={1}" -f $Context, $p.ExitCode)
    if ($stderr) { Write-Log -Message ("Log Parser stderr [{0}]: {1}" -f $Context, $stderr) -Level "WARN" }

    Remove-Item -LiteralPath $tmpSql -Force -ErrorAction SilentlyContinue

    if ($p.ExitCode -ne 0) {
        throw "Log Parser failed for $Context. $stderr $stdout"
    }
}

function New-EmptyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    ($Headers -join ",") | Set-Content -Path $Path -Encoding UTF8
}

function Export-AclInventory {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$OutputFolder
    )

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        throw "Target FileServer path does not exist or is not reachable: $TargetPath"
    }

    Ensure-Directory -Path $OutputFolder

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $out = Join-Path $OutputFolder ("{0}-FileServer-ACL-Inventory-{1}.csv" -f $env:COMPUTERNAME, $timestamp)

    $acl = Get-Acl -LiteralPath $TargetPath

    $rows = foreach ($entry in $acl.Access) {
        [pscustomobject]@{
            TargetPath = $TargetPath
            Owner = [string]$acl.Owner
            IdentityReference = [string]$entry.IdentityReference
            AccessControlType = [string]$entry.AccessControlType
            FileSystemRights = [string]$entry.FileSystemRights
            IsInherited = [string]$entry.IsInherited
            InheritanceFlags = [string]$entry.InheritanceFlags
            PropagationFlags = [string]$entry.PropagationFlags
        }
    }

    $rows | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
    $script:LastOutputPath = $out
    Write-Log -Message ("ACL inventory exported: {0}" -f $out)
    return $out
}

function Export-4663FileAccessEvidence {
    param(
        [Parameter(Mandatory)][string]$TargetPathFilter,
        [Parameter(Mandatory)][string]$OutputFolder,
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [bool]$UseDateRange,
        [datetime]$FromTime,
        [datetime]$ToTime,
        [string]$UserFilter
    )

    Ensure-Directory -Path $OutputFolder

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeHost = $env:COMPUTERNAME
    $rawCsv = Join-Path $OutputFolder ("{0}-FileServer-EventID4663-RAW-{1}.csv" -f $safeHost, $timestamp)
    $reportCsv = Join-Path $OutputFolder ("{0}-FileServer-EvidenceReport-{1}.csv" -f $safeHost, $timestamp)

    $sourceExpr = Get-EvtxSourceExpression -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders

    $where = New-Object System.Collections.Generic.List[string]
    $where.Add("EventID = 4663")

    $targetLike = Normalize-PathForSqlLike -Path $TargetPathFilter
    if (-not [string]::IsNullOrWhiteSpace($targetLike)) {
        $where.Add("(EXTRACT_TOKEN(Strings, 6, '|') LIKE '%$targetLike%' OR Message LIKE '%$targetLike%')")
    }

    if ($UseDateRange) {
        $from = Convert-DateForLogParser -Date $FromTime
        $to = Convert-DateForLogParser -Date $ToTime
        $where.Add("TimeGenerated >= TO_TIMESTAMP('$from', 'yyyy-MM-dd HH:mm:ss')")
        $where.Add("TimeGenerated <= TO_TIMESTAMP('$to', 'yyyy-MM-dd HH:mm:ss')")
    }

    $userConditions = @()
    if (-not [string]::IsNullOrWhiteSpace($UserFilter)) {
        $users = $UserFilter -split "[,;`r`n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        foreach ($u in $users) {
            if ($u -eq "*") { $userConditions = @(); break }
            $safe = $u -replace "'", "''"
            if ($safe -match "\\") {
                $parts = $safe -split "\\", 2
                $dom = $parts[0]
                $usr = $parts[1]
                $userConditions += "(EXTRACT_TOKEN(Strings, 1, '|') = '$usr' AND EXTRACT_TOKEN(Strings, 2, '|') = '$dom')"
            } else {
                $userConditions += "(EXTRACT_TOKEN(Strings, 1, '|') = '$safe')"
            }
        }
    }
    if ($userConditions.Count -gt 0) {
        $where.Add("(" + ($userConditions -join " OR ") + ")")
    }

    $whereSql = $where -join " AND "

    $sql = @"
SELECT
  [EventLog] AS SourceEvtxPath,
  RecordNumber AS RecordNumber,
  TimeGenerated AS EventTime,
  ComputerName AS EventCollector,
  EventID AS EventId,
  EXTRACT_TOKEN(Strings, 0, '|') AS SubjectUserSid,
  EXTRACT_TOKEN(Strings, 1, '|') AS SubjectAccountName,
  EXTRACT_TOKEN(Strings, 2, '|') AS SubjectAccountDomain,
  EXTRACT_TOKEN(Strings, 3, '|') AS SubjectLogonId,
  EXTRACT_TOKEN(Strings, 4, '|') AS ObjectServer,
  EXTRACT_TOKEN(Strings, 5, '|') AS ObjectType,
  EXTRACT_TOKEN(Strings, 6, '|') AS ObjectName,
  EXTRACT_TOKEN(Strings, 7, '|') AS HandleId,
  EXTRACT_TOKEN(Strings, 8, '|') AS AccessList,
  EXTRACT_TOKEN(Strings, 9, '|') AS AccessMask,
  EXTRACT_TOKEN(Strings, 10, '|') AS ProcessId,
  EXTRACT_TOKEN(Strings, 11, '|') AS ProcessName,
  Message AS Message
INTO '$rawCsv'
FROM '$sourceExpr'
WHERE $whereSql
ORDER BY EventTime DESC
"@

    Invoke-LogParserQuery -Sql $sql -Context "EventID4663FileAccess"

    if (-not (Test-Path -LiteralPath $rawCsv)) {
        $headers = @("SourceEvtxPath","RecordNumber","EventTime","EventCollector","EventId","SubjectUserSid","SubjectAccountName","SubjectAccountDomain","SubjectLogonId","ObjectServer","ObjectType","ObjectName","HandleId","AccessList","AccessMask","ProcessId","ProcessName","Message")
        New-EmptyCsv -Path $rawCsv -Headers $headers
    }

    $rows = @(Import-Csv -Path $rawCsv)
    $script:LastRawPath = $rawCsv

    if ($rows.Count -eq 0) {
        $reportHeaders = @("ReportType","EventTime","UserName","UserDomain","EventCollector","ObjectName","AccessType","AccessMask","AccessList","ProcessName","RecordNumber","LegalSafeInterpretation","SourceEvtxPath")
        New-EmptyCsv -Path $reportCsv -Headers $reportHeaders
        $script:LastOutputPath = $reportCsv
        Write-Log -Message ("No matching Event ID 4663 records found. Empty report exported: {0}" -f $reportCsv) -Level "WARN"
        return $reportCsv
    }

    $report = foreach ($r in $rows) {
        $accessType = Convert-AccessMaskToType -AccessMask ([string]$r.AccessMask) -AccessList ([string]$r.AccessList)
        [pscustomobject]@{
            ReportType = "FILE_ACCESS_EVIDENCE"
            EventTime = [string]$r.EventTime
            UserName = [string]$r.SubjectAccountName
            UserDomain = [string]$r.SubjectAccountDomain
            EventCollector = [string]$r.EventCollector
            ObjectName = [string]$r.ObjectName
            AccessType = $accessType
            AccessMask = [string]$r.AccessMask
            AccessList = [string]$r.AccessList
            ProcessName = [string]$r.ProcessName
            RecordNumber = [string]$r.RecordNumber
            LegalSafeInterpretation = Get-LegalSafeInterpretation -AccessType $accessType
            SourceEvtxPath = [string]$r.SourceEvtxPath
        }
    }

    $report | Export-Csv -Path $reportCsv -NoTypeInformation -Encoding UTF8
    $script:LastOutputPath = $reportCsv
    Write-Log -Message ("RAW CSV exported: {0}" -f $rawCsv)
    Write-Log -Message ("Official evidence report exported: {0}" -f $reportCsv)
    return $reportCsv
}

function Start-FullEvidenceWorkflow {
    param(
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$OutputFolder,
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [bool]$UseDateRange,
        [datetime]$FromTime,
        [datetime]$ToTime,
        [string]$UserFilter
    )

    $aclPath = Export-AclInventory -TargetPath $TargetPath -OutputFolder $OutputFolder
    $evidencePath = Export-4663FileAccessEvidence -TargetPathFilter $TargetPath -OutputFolder $OutputFolder -UseLiveLog $UseLiveLog -EvtxFolder $EvtxFolder -IncludeSubfolders $IncludeSubfolders -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime -UserFilter $UserFilter

    Write-Log -Message ("Full workflow completed. ACL={0}; Evidence={1}" -f $aclPath, $evidencePath)
    return $evidencePath
}

Write-Log -Message ("Script started. Version={0}" -f $script:Version)

$form = New-Object System.Windows.Forms.Form
$form.Text = "FileServer Evidence Tool - Multi Scenario"
$form.Size = New-Object System.Drawing.Size(980, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblTarget = New-Object System.Windows.Forms.Label
$lblTarget.Text = "Target folder/file path:"
$lblTarget.Location = New-Object System.Drawing.Point(20, 25)
$lblTarget.Size = New-Object System.Drawing.Size(160, 22)

$txtTarget = New-Object System.Windows.Forms.TextBox
$txtTarget.Location = New-Object System.Drawing.Point(190, 22)
$txtTarget.Size = New-Object System.Drawing.Size(620, 24)
$txtTarget.Text = "\\fileserver\store-folder\"

$btnBrowseTarget = New-Object System.Windows.Forms.Button
$btnBrowseTarget.Text = "Browse..."
$btnBrowseTarget.Location = New-Object System.Drawing.Point(825, 20)
$btnBrowseTarget.Size = New-Object System.Drawing.Size(120, 28)

$chkLive = New-Object System.Windows.Forms.CheckBox
$chkLive.Text = "Use live Security channel (snapshot via wevtutil)"
$chkLive.Location = New-Object System.Drawing.Point(190, 60)
$chkLive.Size = New-Object System.Drawing.Size(360, 24)
$chkLive.Checked = $true

$lblEvtx = New-Object System.Windows.Forms.Label
$lblEvtx.Text = "EVTX folder:"
$lblEvtx.Location = New-Object System.Drawing.Point(20, 95)
$lblEvtx.Size = New-Object System.Drawing.Size(160, 22)

$txtEvtx = New-Object System.Windows.Forms.TextBox
$txtEvtx.Location = New-Object System.Drawing.Point(190, 92)
$txtEvtx.Size = New-Object System.Drawing.Size(620, 24)

$btnResolve = New-Object System.Windows.Forms.Button
$btnResolve.Text = "Resolve Channel"
$btnResolve.Location = New-Object System.Drawing.Point(825, 58)
$btnResolve.Size = New-Object System.Drawing.Size(120, 28)

$btnBrowseEvtx = New-Object System.Windows.Forms.Button
$btnBrowseEvtx.Text = "Browse..."
$btnBrowseEvtx.Location = New-Object System.Drawing.Point(825, 90)
$btnBrowseEvtx.Size = New-Object System.Drawing.Size(120, 28)

$chkSub = New-Object System.Windows.Forms.CheckBox
$chkSub.Text = "Include subfolders when scanning archived EVTX"
$chkSub.Location = New-Object System.Drawing.Point(190, 125)
$chkSub.Size = New-Object System.Drawing.Size(380, 24)
$chkSub.Checked = $true

$chkDate = New-Object System.Windows.Forms.CheckBox
$chkDate.Text = "Apply event time range"
$chkDate.Location = New-Object System.Drawing.Point(190, 158)
$chkDate.Size = New-Object System.Drawing.Size(200, 24)
$chkDate.Checked = $true

$lblFrom = New-Object System.Windows.Forms.Label
$lblFrom.Text = "From:"
$lblFrom.Location = New-Object System.Drawing.Point(190, 190)
$lblFrom.Size = New-Object System.Drawing.Size(50, 22)

$dtFrom = New-Object System.Windows.Forms.DateTimePicker
$dtFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtFrom.CustomFormat = "yyyy-MM-dd HH:mm:ss"
$dtFrom.ShowUpDown = $false
$dtFrom.Location = New-Object System.Drawing.Point(245, 187)
$dtFrom.Size = New-Object System.Drawing.Size(180, 24)
$dtFrom.Value = (Get-Date).Date

$lblTo = New-Object System.Windows.Forms.Label
$lblTo.Text = "To:"
$lblTo.Location = New-Object System.Drawing.Point(450, 190)
$lblTo.Size = New-Object System.Drawing.Size(30, 22)

$dtTo = New-Object System.Windows.Forms.DateTimePicker
$dtTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dtTo.CustomFormat = "yyyy-MM-dd HH:mm:ss"
$dtTo.ShowUpDown = $false
$dtTo.Location = New-Object System.Drawing.Point(485, 187)
$dtTo.Size = New-Object System.Drawing.Size(180, 24)
$dtTo.Value = Get-Date

$lblUser = New-Object System.Windows.Forms.Label
$lblUser.Text = "User filter:"
$lblUser.Location = New-Object System.Drawing.Point(20, 230)
$lblUser.Size = New-Object System.Drawing.Size(160, 22)

$txtUser = New-Object System.Windows.Forms.TextBox
$txtUser.Location = New-Object System.Drawing.Point(190, 227)
$txtUser.Size = New-Object System.Drawing.Size(620, 24)
$txtUser.Text = "*"

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = "Output folder:"
$lblOut.Location = New-Object System.Drawing.Point(20, 270)
$lblOut.Size = New-Object System.Drawing.Size(160, 22)

$txtOut = New-Object System.Windows.Forms.TextBox
$txtOut.Location = New-Object System.Drawing.Point(190, 267)
$txtOut.Size = New-Object System.Drawing.Size(620, 24)
$txtOut.Text = [Environment]::GetFolderPath("MyDocuments")

$btnBrowseOut = New-Object System.Windows.Forms.Button
$btnBrowseOut.Text = "Browse..."
$btnBrowseOut.Location = New-Object System.Drawing.Point(825, 265)
$btnBrowseOut.Size = New-Object System.Drawing.Size(120, 28)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Log folder:"
$lblLog.Location = New-Object System.Drawing.Point(20, 305)
$lblLog.Size = New-Object System.Drawing.Size(160, 22)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(190, 302)
$txtLog.Size = New-Object System.Drawing.Size(620, 24)
$txtLog.Text = $script:DefaultLogDir

$btnBrowseLog = New-Object System.Windows.Forms.Button
$btnBrowseLog.Text = "Browse..."
$btnBrowseLog.Location = New-Object System.Drawing.Point(825, 300)
$btnBrowseLog.Size = New-Object System.Drawing.Size(120, 28)

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = "Scenarios"
$grp.Location = New-Object System.Drawing.Point(20, 345)
$grp.Size = New-Object System.Drawing.Size(925, 110)

$btnAcl = New-Object System.Windows.Forms.Button
$btnAcl.Text = "1. Who CAN Access (ACL)"
$btnAcl.Location = New-Object System.Drawing.Point(20, 35)
$btnAcl.Size = New-Object System.Drawing.Size(210, 36)

$btnAccess = New-Object System.Windows.Forms.Button
$btnAccess.Text = "2. Who DID Access (4663)"
$btnAccess.Location = New-Object System.Drawing.Point(250, 35)
$btnAccess.Size = New-Object System.Drawing.Size(220, 36)

$btnFull = New-Object System.Windows.Forms.Button
$btnFull.Text = "3. Full Evidence Workflow"
$btnFull.Location = New-Object System.Drawing.Point(490, 35)
$btnFull.Size = New-Object System.Drawing.Size(220, 36)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open Last CSV"
$btnOpen.Location = New-Object System.Drawing.Point(730, 35)
$btnOpen.Size = New-Object System.Drawing.Size(170, 36)

$grp.Controls.AddRange(@($btnAcl,$btnAccess,$btnFull,$btnOpen))

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20, 475)
$progress.Size = New-Object System.Drawing.Size(925, 22)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready."
$lblStatus.Location = New-Object System.Drawing.Point(20, 510)
$lblStatus.Size = New-Object System.Drawing.Size(925, 25)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(825, 555)
$btnClose.Size = New-Object System.Drawing.Size(120, 36)

$form.Controls.AddRange(@(
    $lblTarget,$txtTarget,$btnBrowseTarget,
    $chkLive,$btnResolve,
    $lblEvtx,$txtEvtx,$btnBrowseEvtx,$chkSub,
    $chkDate,$lblFrom,$dtFrom,$lblTo,$dtTo,
    $lblUser,$txtUser,
    $lblOut,$txtOut,$btnBrowseOut,
    $lblLog,$txtLog,$btnBrowseLog,
    $grp,$progress,$lblStatus,$btnClose
))

function Update-ModeUi {
    $txtEvtx.Enabled = -not $chkLive.Checked
    $btnBrowseEvtx.Enabled = -not $chkLive.Checked
}

$chkLive.Add_CheckedChanged({ Update-ModeUi })
Update-ModeUi

$btnBrowseTarget.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Browse target failed" -Action {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Select the target FileServer folder"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtTarget.Text = $dialog.SelectedPath
        }
    }
})

$btnBrowseEvtx.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Browse EVTX folder failed" -Action {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtEvtx.Text = $dialog.SelectedPath
        }
    }
})

$btnBrowseOut.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Browse output folder failed" -Action {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtOut.Text = $dialog.SelectedPath
        }
    }
})

$btnBrowseLog.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Browse log folder failed" -Action {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtLog.Text = $dialog.SelectedPath
            Ensure-Directory -Path $txtLog.Text
            $script:LogPath = Join-Path $txtLog.Text "FileServerEvidenceTool.log"
        }
    }
})

$btnResolve.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Resolve Channel failed" -Action {
        $lblStatus.Text = "Resolving Security channel..."
        $form.Refresh()
        $folder = Resolve-SecurityEvtxFolder
        if ($folder) { $txtEvtx.Text = $folder }
        $snap = Export-SecuritySnapshot
        if ($folder) {
            Show-Message -Message ("Security channel validated.`r`nEVTX folder: {0}`r`nSnapshot: {1}" -f $folder, $snap) -Type "INFO" -Title "Resolve Channel"
        } else {
            Show-Message -Message ("Security channel snapshot export succeeded, but EVTX folder could not be resolved.`r`nSnapshot: {0}" -f $snap) -Type "WARN" -Title "Resolve Channel"
        }
        $lblStatus.Text = "Security channel resolved."
    }
})

$btnAcl.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "ACL inventory failed" -Action {
        $progress.Style = "Marquee"
        $lblStatus.Text = "Extracting ACL inventory..."
        $form.Refresh()
        $out = Export-AclInventory -TargetPath $txtTarget.Text.Trim() -OutputFolder $txtOut.Text.Trim()
        $progress.Style = "Blocks"
        $lblStatus.Text = "ACL inventory completed."
        Show-Message -Message ("ACL inventory completed.`r`nOutput: {0}" -f $out) -Type "INFO"
        Invoke-Item $out
    }
})

$btnAccess.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "EventID 4663 evidence extraction failed" -Action {
        if ($chkDate.Checked -and $dtFrom.Value -gt $dtTo.Value) {
            Show-Message -Message "Invalid date range. From must be earlier than To." -Type "WARN"
            return
        }

        $progress.Style = "Marquee"
        $lblStatus.Text = "Extracting Event ID 4663 file access evidence..."
        $form.Refresh()

        $out = Export-4663FileAccessEvidence `
            -TargetPathFilter $txtTarget.Text.Trim() `
            -OutputFolder $txtOut.Text.Trim() `
            -UseLiveLog $chkLive.Checked `
            -EvtxFolder $txtEvtx.Text.Trim() `
            -IncludeSubfolders $chkSub.Checked `
            -UseDateRange $chkDate.Checked `
            -FromTime $dtFrom.Value `
            -ToTime $dtTo.Value `
            -UserFilter $txtUser.Text

        $progress.Style = "Blocks"
        $lblStatus.Text = "EventID 4663 evidence extraction completed."
        Show-Message -Message ("Evidence extraction completed.`r`nOutput: {0}" -f $out) -Type "INFO"
        Invoke-Item $out
    }
})

$btnFull.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Full evidence workflow failed" -Action {
        if ($chkDate.Checked -and $dtFrom.Value -gt $dtTo.Value) {
            Show-Message -Message "Invalid date range. From must be earlier than To." -Type "WARN"
            return
        }

        $progress.Style = "Marquee"
        $lblStatus.Text = "Running full FileServer evidence workflow..."
        $form.Refresh()

        $out = Start-FullEvidenceWorkflow `
            -TargetPath $txtTarget.Text.Trim() `
            -OutputFolder $txtOut.Text.Trim() `
            -UseLiveLog $chkLive.Checked `
            -EvtxFolder $txtEvtx.Text.Trim() `
            -IncludeSubfolders $chkSub.Checked `
            -UseDateRange $chkDate.Checked `
            -FromTime $dtFrom.Value `
            -ToTime $dtTo.Value `
            -UserFilter $txtUser.Text

        $progress.Style = "Blocks"
        $lblStatus.Text = "Full workflow completed."
        Show-Message -Message ("Full evidence workflow completed.`r`nOutput: {0}" -f $out) -Type "INFO"
        Invoke-Item $out
    }
})

$btnOpen.Add_Click({
    Invoke-GuiSafe -ErrorPrefix "Open last CSV failed" -Action {
        if ($script:LastOutputPath -and (Test-Path -LiteralPath $script:LastOutputPath)) {
            Invoke-Item $script:LastOutputPath
        } else {
            Show-Message -Message "No output CSV is available yet." -Type "WARN"
        }
    }
})

$btnClose.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
Write-Log -Message "Script ended."

# End of script
