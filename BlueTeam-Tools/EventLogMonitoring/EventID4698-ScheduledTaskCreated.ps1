<#
.SYNOPSIS
    PowerShell Script for detecting Event ID 4698 (Scheduled task created).

.DESCRIPTION
    This WS2019-compatible revision analyzes Event ID 4698 from the live Security channel
    or archived .evtx files. In live mode, it exports a temporary snapshot with wevtutil
    and parses it using Log Parser COM SQL with INTO-based CSV output, Get-WinEvent fallback, date range filtering, and user filtering. The consolidated CSV report is exported to
    My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
   2026-05-06-v1.1.6-PRODUCTION-BASELINE-USERFILTER-TEXTBOX-HOTFIX
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true,

    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Native console visibility
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

    if (-not $ShowConsole.IsPresent) {
        $consoleHandle = [Win32Console]::GetConsoleWindow()
        if ($consoleHandle -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($consoleHandle, 0)
        }
    }
}
catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}
#endregion

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load required assemblies. $($_.Exception.Message)"
    exit 1
}

#region Variables
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$computerName = [Environment]::MachineName
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:defaultLogFolder = 'C:\Logs-TEMP'
$script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
$script:tempArtifacts = New-Object System.Collections.ArrayList
$script:progressBar = $null
$script:statusLabel = $null
$script:form = $null
#endregion

#region Helpers
function Initialize-LogDirectory {
    if (-not (Test-Path -LiteralPath $script:defaultLogFolder -PathType Container)) {
        New-Item -Path $script:defaultLogFolder -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARNING', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    try {
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
    } catch {
    }
}


function Test-IsFileLocked {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        return $false
    }
    catch {
        return $true
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Test-IsLikelyActiveEvtxFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$File)

    # PATH-AGNOSTIC ARCHIVE RULE:
    # Do not skip evidence files by canonical names such as Security.evtx/System.evtx.
    # Archived EVTX files may legitimately keep their original channel filename in any folder.
    return $false
}


function Get-ArchiveSafeEvtxFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Files)

    $safeFiles = New-Object System.Collections.Generic.List[string]
    $enumeratedCount = 0
    $selectedCount = 0
    $lockedSkippedCount = 0
    $invalidSkippedCount = 0

    foreach ($file in @($Files)) {
        $enumeratedCount++
        try {
            $path = $null
            if ($file -is [System.IO.FileInfo]) {
                $path = [string]$file.FullName
            }
            elseif ($file -and $file.PSObject.Properties['FullName']) {
                $path = [string]$file.FullName
            }
            else {
                $path = [string]$file
            }

            if ([string]::IsNullOrWhiteSpace($path)) {
                $invalidSkippedCount++
                continue
            }

            $absolutePath = [System.IO.Path]::GetFullPath($path)
            if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
                $invalidSkippedCount++
                continue
            }

            if ([System.IO.Path]::GetExtension($absolutePath) -ine '.evtx') {
                $invalidSkippedCount++
                continue
            }

            if (Test-IsFileLocked -Path $absolutePath) {
                Write-Log "Skipped locked EVTX file in archived mode: '$absolutePath'" 'WARNING'
                $lockedSkippedCount++
                continue
            }

            [void]$safeFiles.Add([string]$absolutePath)
            $selectedCount++
        }
        catch {
            $invalidSkippedCount++
            Write-Log "Skipped invalid EVTX source in archived mode. Error: $($_.Exception.Message)" 'WARNING'
        }
    }

    Write-Log "Archive-safe PATH-AGNOSTIC EVTX selection completed. Enumerated=$enumeratedCount; Selected=$selectedCount; LockedSkipped=$lockedSkippedCount; InvalidSkipped=$invalidSkippedCount"
    return @($safeFiles.ToArray())
}


function Show-Info {
    param([string]$Message, [string]$Title = 'Information')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

function Show-ErrorBox {
    param([string]$Message, [string]$Title = 'Error')
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}


function Register-WinFormsExceptionHandlers {
    [CmdletBinding()]
    param()

    try {
        [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
        [System.Windows.Forms.Application]::add_ThreadException({
            param($sender, $eventArgs)
            try {
                Write-Log -Level 'ERROR' -Message ("Unhandled GUI exception: {0}" -f $eventArgs.Exception.Message)
                Show-ErrorBox -Message ("Unhandled GUI exception.`r`n{0}" -f $eventArgs.Exception.Message) -Title 'Unhandled GUI Exception'
            }
            catch { }
        })
        [AppDomain]::CurrentDomain.add_UnhandledException({
            param($sender, $eventArgs)
            try {
                $exception = $eventArgs.ExceptionObject
                if ($exception -is [System.Exception]) {
                    Write-Log -Level 'ERROR' -Message ("Unhandled AppDomain exception: {0}" -f $exception.Message)
                } else {
                    Write-Log -Level 'ERROR' -Message ("Unhandled AppDomain exception: {0}" -f [string]$exception)
                }
            }
            catch { }
        })
        Write-Log -Message 'WinForms JIT-safe exception handlers registered.'
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Unable to register WinForms exception handlers: $($_.Exception.Message)"
    }
}

function Resolve-SecurityEvtxFolder {
    [CmdletBinding()]
    param()

    $candidateFiles = New-Object System.Collections.Generic.List[string]

    try {
        $classicKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security'
        if (Test-Path -LiteralPath $classicKey) {
            $classicFile = (Get-ItemProperty -LiteralPath $classicKey -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace([string]$classicFile)) {
                [void]$candidateFiles.Add([Environment]::ExpandEnvironmentVariables([string]$classicFile))
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Classic Security EventLog registry lookup failed: $($_.Exception.Message)"
    }

    try {
        $winevtKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Security'
        if (Test-Path -LiteralPath $winevtKey) {
            $winevtFile = (Get-ItemProperty -LiteralPath $winevtKey -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace([string]$winevtFile)) {
                [void]$candidateFiles.Add([Environment]::ExpandEnvironmentVariables([string]$winevtFile))
            }
        }
    }
    catch {
        Write-Log -Level 'WARNING' -Message "WINEVT Security channel registry lookup failed: $($_.Exception.Message)"
    }

    foreach ($filePath in @($candidateFiles)) {
        try {
            if ([string]::IsNullOrWhiteSpace([string]$filePath)) { continue }
            $folder = Split-Path -Path ([string]$filePath) -Parent
            if (-not [string]::IsNullOrWhiteSpace($folder) -and (Test-Path -LiteralPath $folder -PathType Container)) {
                Write-Log -Message "Security EVTX folder resolved: $folder"
                return $folder
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to validate Security EVTX folder candidate '$filePath'. $($_.Exception.Message)"
        }
    }

    $fallback = Join-Path $env:SystemRoot 'System32\winevt\Logs'
    if (Test-Path -LiteralPath $fallback -PathType Container) {
        Write-Log -Level 'WARNING' -Message "Security EVTX folder could not be resolved from registry. Using fallback: $fallback"
        return $fallback
    }

    return $null
}

function Update-ProgressSafe {
    param([int]$Value, [string]$StatusText)

    if ($script:progressBar) {
        $bounded = [Math]::Max(0, [Math]::Min(100, $Value))
        $script:progressBar.Value = $bounded
    }
    if ($script:statusLabel -and $StatusText) {
        $script:statusLabel.Text = $StatusText
    }
    if ($script:form) {
        $script:form.Refresh()
    }
}

function Resolve-OutputFolder {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $script:defaultOutputFolder
    }
    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        New-Item -Path $Candidate -ItemType Directory -Force | Out-Null
    }
    return $Candidate
}

function New-FolderPicker {
    param([string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    return $dialog
}

function Register-TempArtifact {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        [void]$script:tempArtifacts.Add($Path)
    }
}

function Remove-TempArtifacts {
    foreach ($artifact in @($script:tempArtifacts)) {
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                if (Test-Path -LiteralPath $artifact) {
                    Remove-Item -LiteralPath $artifact -Force -ErrorAction Stop
                }
                break
            }
            catch {
                if ($attempt -eq 3) {
                    Write-Log -Level 'WARNING' -Message "Unable to remove temporary artifact: $artifact. Error: $($_.Exception.Message)"
                } else {
                    Start-Sleep -Milliseconds 250
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                }
            }
        }
    }
    $script:tempArtifacts.Clear() | Out-Null
}

function New-LogParserObjects {
    [CmdletBinding()]
    param()

    return [ordered]@{
        Query        = New-Object -ComObject 'MSUtil.LogQuery'
        InputFormat  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        OutputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
    }
}

function Release-LogParserObjects {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Objects)

    foreach ($key in @('OutputFormat','InputFormat','Query')) {
        if ($Objects.Contains($key)) {
            $obj = $Objects[$key]
            if ($null -ne $obj -and [System.Runtime.InteropServices.Marshal]::IsComObject($obj)) {
                try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch { }
            }
        }
    }
}

function Export-LiveChannelSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) {
        throw "wevtutil.exe was not found at '$wevtutil'."
    }

    $snapshotPath = Join-Path $env:TEMP ('{0}-{1}.evtx' -f ($ChannelName -replace '[\\/:*?"<>|]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Register-TempArtifact -Path $snapshotPath

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $quotedChannel = '"' + ($ChannelName -replace '"','\"') + '"'
    $quotedDestination = '"' + ($snapshotPath -replace '"','\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $stdErr = $process.StandardError.ReadToEnd()
    $null = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($process.ExitCode). StdErr=$stdErr"
    }
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        throw "Snapshot export did not create '$snapshotPath'."
    }

    Write-Log "Live channel snapshot exported to '$snapshotPath'."
    return $snapshotPath
}

function New-HeaderOnlyCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $header = 'EventTime,EventID,CreatorUser,DomainName,TaskName,TaskContent,ComputerName,SourceFile'
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function Get-SafeCount {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return 0 }

    try {
        if ($InputObject -is [System.Collections.ICollection]) {
            return [int]$InputObject.Count
        }
    }
    catch { }

    $counter = 0
    try {
        foreach ($item in @($InputObject)) {
            if ($null -ne $item) { $counter++ }
        }
        return [int]$counter
    }
    catch {
        return 1
    }
}

function Get-RowCountSafe {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    try {
        $rows = Import-Csv -LiteralPath $CsvPath
        return (Get-SafeCount -InputObject $rows)
    } catch {
        return 0
    }
}

function Build-UserFilterClause {
    param([string[]]$UserAccounts)

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((Get-SafeCount -InputObject $normalizedUsers) -eq 0) {
        return ''
    }

    $escaped = @($normalizedUsers | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" })
    return ("AND EXTRACT_TOKEN(Strings, 1, '|') IN ({0})" -f ($escaped -join ', '))
}

function Build-QueryForFile {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")
    $userClause  = Build-UserFilterClause -UserAccounts $UserAccounts

$query = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    EXTRACT_TOKEN(Strings, 1, '|') AS CreatorUser,
    EXTRACT_TOKEN(Strings, 2, '|') AS DomainName,
    EXTRACT_TOKEN(Strings, 4, '|') AS TaskName,
    EXTRACT_TOKEN(Strings, 5, '|') AS TaskContent,
    ComputerName,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
WHERE EventID = 4698
$userClause
"@
    return $query
}

function Merge-CsvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$SourceCsvFiles,
        [Parameter(Mandatory)][string]$DestinationCsv
    )

    $existing = @(@($SourceCsvFiles) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath ([string]$_) -PathType Leaf) })
    if ((Get-SafeCount -InputObject $existing) -eq 0) {
        New-HeaderOnlyCsv -Path $DestinationCsv
        return
    }

    $first = $true
    foreach ($csv in @($existing)) {
        if ($first) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $first = $false
        } else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
}

function Test-Event4698UserMatch {
    [CmdletBinding()]
    param(
        [Parameter()][string]$CreatorUser,
        [Parameter()][string]$DomainName,
        [Parameter()][string[]]$UserAccounts
    )

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$($_)".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ((Get-SafeCount -InputObject $normalizedUsers) -eq 0) { return $true }

    $creator = if ($null -ne $CreatorUser) { [string]$CreatorUser } else { '' }
    $domain  = if ($null -ne $DomainName) { [string]$DomainName } else { '' }
    $domainUser = if (-not [string]::IsNullOrWhiteSpace($domain)) { "$domain\$creator" } else { $creator }

    foreach ($candidate in @($normalizedUsers)) {
        if ($creator.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($domainUser.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($candidate -like '*\*') {
            if ($domainUser.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Get-EventDataValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$XmlEvent,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        $node = @($XmlEvent.Event.EventData.Data | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
        if ((Get-SafeCount -InputObject $node) -gt 0) { return [string]$node[0].'#text' }
    }
    catch { }
    return ''
}

function Invoke-GetWinEventFallbackToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    Write-Log "Get-WinEvent fallback processing: $EvtxPath"
    $filter = @{ Path = $EvtxPath; Id = 4698 }
    if ($null -ne $StartTime) { $filter.StartTime = [datetime]$StartTime }
    if ($null -ne $EndTime) { $filter.EndTime = [datetime]$EndTime }

    $rows = New-Object System.Collections.Generic.List[object]
    try {
        $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue)
        foreach ($event in @($events)) {
            $xml = [xml]$event.ToXml()
            $creator = Get-EventDataValue -XmlEvent $xml -Name 'SubjectUserName'
            $domain  = Get-EventDataValue -XmlEvent $xml -Name 'SubjectDomainName'
            if (-not (Test-Event4698UserMatch -CreatorUser $creator -DomainName $domain -UserAccounts $UserAccounts)) { continue }

            $taskName = Get-EventDataValue -XmlEvent $xml -Name 'TaskName'
            $taskContent = Get-EventDataValue -XmlEvent $xml -Name 'TaskContent'
            if ($null -ne $taskContent) {
                $taskContent = [regex]::Replace([string]$taskContent, "`r?`n", ' ')
            }

            $rows.Add([pscustomobject]@{
                EventTime    = $event.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
                EventID      = $event.Id
                CreatorUser  = $creator
                DomainName   = $domain
                TaskName     = $taskName
                TaskContent  = $taskContent
                ComputerName = $event.MachineName
                SourceFile   = $EvtxPath
            }) | Out-Null
        }
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
        Write-Log -Level 'WARNING' -Message "Get-WinEvent fallback could not read '$EvtxPath'. $($_.Exception.Message)"
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Get-WinEvent fallback failed for '$EvtxPath'. $($_.Exception.Message)"
    }

    if ((Get-SafeCount -InputObject $rows) -gt 0) {
        @($rows) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    }
    else {
        New-HeaderOnlyCsv -Path $CsvPath
    }

    Write-Log "Get-WinEvent fallback completed. Records=$(Get-SafeCount -InputObject $rows)"
    return $true
}

function Apply-CsvPostFilters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return }

    $rows = @(Import-Csv -LiteralPath $CsvPath)
    if ((Get-SafeCount -InputObject $rows) -eq 0) { return }

    $filtered = New-Object System.Collections.Generic.List[object]
    foreach ($row in @($rows)) {
        $keep = $true
        $dt = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$row.EventTime)) {
            try { $dt = [datetime]::Parse([string]$row.EventTime) } catch { $dt = $null }
        }
        if ($null -ne $StartTime -and $null -ne $dt -and $dt -lt ([datetime]$StartTime)) { $keep = $false }
        if ($null -ne $EndTime -and $null -ne $dt -and $dt -gt ([datetime]$EndTime)) { $keep = $false }
        if (-not (Test-Event4698UserMatch -CreatorUser ([string]$row.CreatorUser) -DomainName ([string]$row.DomainName) -UserAccounts $UserAccounts)) { $keep = $false }
        if ($keep) { $filtered.Add($row) | Out-Null }
    }

    if ((Get-SafeCount -InputObject $filtered) -gt 0) {
        @($filtered) | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8
    }
    else {
        New-HeaderOnlyCsv -Path $CsvPath
    }
}

function Invoke-EventQueryToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $lp = $null
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts
    $executeResult = $false

    try {
        $lp = New-LogParserObjects

        # IMPORTANT: Log Parser COM CSVOutputFormat on Windows PowerShell 5.1 does not expose
        # a writable .fileName property in this execution context. The destination CSV is
        # controlled by the SQL INTO clause generated by Build-QueryForFile.
        $executeResult = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
        Write-Log "Log Parser COM SQL ExecuteBatch returned: $executeResult"
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Log Parser COM failed for '$EvtxPath'. Error: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $lp) { Release-LogParserObjects -Objects $lp }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }

    Apply-CsvPostFilters -CsvPath $CsvPath -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime
    $rowCount = Get-RowCountSafe -CsvPath $CsvPath

    if (($executeResult -eq $false) -or ($rowCount -eq 0)) {
        Write-Log -Level 'WARNING' -Message "Log Parser COM returned ExecuteBatch=$executeResult and RowCount=$rowCount for '$EvtxPath'. Running Get-WinEvent validation/fallback."
        return (Invoke-GetWinEventFallbackToCsv -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime)
    }

    Write-Log "Log Parser COM output accepted. Records=$rowCount"
    return $true
}

function Get-EvtxFilesSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    if ([string]::IsNullOrWhiteSpace($RootPath) -or -not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "The EVTX folder '$RootPath' was not found."
    }

    Write-Log "Enumerating archived EVTX files using PATH-AGNOSTIC string-only pipeline. RootPath='$RootPath'; IncludeSubfolders=$IncludeSubfolders"

    $gciParams = @{
        LiteralPath = $RootPath
        Filter      = '*.evtx'
        File        = $true
        ErrorAction = 'Stop'
    }
    if ($IncludeSubfolders) { $gciParams['Recurse'] = $true }

    $paths = @(Get-ChildItem @gciParams | ForEach-Object { [string]$_.FullName })
    return @(Get-ArchiveSafeEvtxFiles -Files $paths)
}


function Parse-DelimitedUsers {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Text
    )

    $rawText = if ($null -ne $Text) { [string]$Text } else { '' }
    if ([string]::IsNullOrWhiteSpace($rawText)) { return @() }

    $users = @(
        $rawText -split "[,;`r`n]+" |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    return @($users)
}
function Resolve-SecurityChannel {
    [CmdletBinding()]
    param()

    Update-ProgressSafe -Value 10 -StatusText 'Resolving Security channel via snapshot export...'
    $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'

    if (Test-Path -LiteralPath $snapshot -PathType Leaf) {
        Write-Log 'Live Security channel snapshot probe completed successfully. Event 4698 row count is intentionally not required for channel validation.'
        Update-ProgressSafe -Value 0 -StatusText 'Ready.'
        return $snapshot
    }

    throw 'Live Security channel probe did not produce a snapshot file.'
}

function Process-Event4698 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter()][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter()][string]$OutputFolder,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][object]$StartTime,
        [Parameter()][object]$EndTime
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ('{0}-EventID4698-ScheduledTaskCreated-{1}.csv' -f $computerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.ArrayList

    $normalizedUserAccounts = @($UserAccounts | ForEach-Object { if ($null -ne $_) { ([string]$_).Trim() } } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $userFilterCount = Get-SafeCount -InputObject $normalizedUserAccounts
    $userFilterDisplay = if ($userFilterCount -gt 0) { ($normalizedUserAccounts -join ', ') } else { '<none>' }
    Write-Log "Starting Event ID 4698 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'; StartTime=$StartTime; EndTime=$EndTime; UserFilterText='$userFilterDisplay'; UserFilterCount=$userFilterCount"
    $UserAccounts = @($normalizedUserAccounts)

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Preparing...'

        if ($UseLiveLog) {
            Update-ProgressSafe -Value 15 -StatusText 'Exporting Security snapshot...'
            $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'
            $sourceFiles = @([pscustomobject]@{ FullName = $snapshot; Name = [IO.Path]::GetFileName($snapshot) })
        } else {
            Update-ProgressSafe -Value 15 -StatusText 'Enumerating archived EVTX files...'
            $sourceFiles = Get-EvtxFilesSafe -RootPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders
        }

        if (-not $UseLiveLog) {
            $sourceFiles = @(Get-ArchiveSafeEvtxFiles -Files @($sourceFiles))
        }

        $sourceCount = Get-SafeCount -InputObject $sourceFiles
        if ($sourceCount -eq 0) {
            throw 'No .evtx files were found to process.'
        }

        $index = 0
        foreach ($source in @($sourceFiles)) {
            $index++
            $percent = 15 + [int]([Math]::Floor(($index / $sourceCount) * 65))
            Update-ProgressSafe -Value $percent -StatusText ("Processing {0} ({1} of {2})..." -f $source.Name, $index, $sourceCount)

            $tempCsv = Join-Path $env:TEMP ('Event4698-{0}-{1}.csv' -f $index, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
            Register-TempArtifact -Path $tempCsv
            [void]$tempCsvFiles.Add($tempCsv)

            try {
                $queryOk = Invoke-EventQueryToCsv -EvtxPath $source.FullName -CsvPath $tempCsv -UserAccounts $UserAccounts -StartTime $StartTime -EndTime $EndTime
                if ($queryOk -eq $false) { continue }
            }
            catch {
                Write-Log -Level 'WARNING' -Message "Skipped EVTX after non-fatal processing failure: '$($source.FullName)'. Error: $($_.Exception.Message)"
                continue
            }
            Write-Log "Processed '$($source.FullName)'."
        }

        Update-ProgressSafe -Value 88 -StatusText 'Merging CSV files...'
        Merge-CsvFiles -SourceCsvFiles @($tempCsvFiles) -DestinationCsv $finalCsv

        $rowCount = Get-RowCountSafe -CsvPath $finalCsv
        Update-ProgressSafe -Value 100 -StatusText ("Completed. Found {0} events. Report saved to '{1}'" -f $rowCount, $finalCsv)
        Write-Log "Found $rowCount Event ID 4698 records. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-Info -Message ("Found {0} Event ID 4698 records.`r`nReport exported to:`r`n{1}" -f $rowCount, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Error processing Event ID 4698. $($_.Exception.Message)"
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error processing Event ID 4698.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        Remove-TempArtifacts
    }
}
#endregion

#region GUI
Initialize-LogDirectory
Write-Log '========== START: Scheduled Task Created Detector =========='
Write-Log "Script version: 2026-05-06-v1.1.6-PRODUCTION-BASELINE-USERFILTER-TEXTBOX-HOTFIX"
Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
Write-Log "Execution user: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Computer name: $computerName"
Write-Log "Log path: $script:logPath"
Register-WinFormsExceptionHandlers

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Scheduled Task Created Detector (Event ID 4698)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 430)
$script:form = $form

$left = 14
$top = 16
$labelWidth = 165
$textWidth = 455
$buttonWidth = 92
$rowHeight = 38
$buttonGap = 10
$buttonX = ($left + $labelWidth + $textWidth + $buttonGap)
$currentY = $top

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Location = New-Object System.Drawing.Point($left, $currentY)
$checkUseLive.Size = New-Object System.Drawing.Size(280, 24)
$checkUseLive.Text = 'Use live Security channel'
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonResolve.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonResolve.Text = 'Resolve'
$form.Controls.Add($buttonResolve)

$currentY = $currentY + $rowHeight

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtx.Text = 'EVTX folder:'
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textEvtx.Size = New-Object System.Drawing.Size($textWidth, 24)
$textEvtx.Enabled = $false
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Enabled = $false
$form.Controls.Add($buttonBrowseEvtx)

$currentY = $currentY + $rowHeight

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point($left, $currentY)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(240, 24)
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$form.Controls.Add($checkIncludeSubfolders)

$currentY = $currentY + $rowHeight

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelUsers.Text = 'User filter:'
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textUsers.Size = New-Object System.Drawing.Size($textWidth, 24)
$textUsers.Text = [string]::Empty
$textUsers.AutoCompleteMode = [System.Windows.Forms.AutoCompleteMode]::None
$textUsers.AutoCompleteSource = [System.Windows.Forms.AutoCompleteSource]::None
$form.Controls.Add($textUsers)

$currentY = $currentY + 28

$labelUsersHint = New-Object System.Windows.Forms.Label
$labelUsersHint.Location = New-Object System.Drawing.Point(($left + $labelWidth), ($currentY + 2))
$labelUsersHint.Size = New-Object System.Drawing.Size(430, 18)
$labelUsersHint.Text = 'Separate multiple users with comma, semicolon, or line break.'
$form.Controls.Add($labelUsersHint)

$currentY = $currentY + 28

$checkDateRange = New-Object System.Windows.Forms.CheckBox
$checkDateRange.Location = New-Object System.Drawing.Point($left, $currentY)
$checkDateRange.Size = New-Object System.Drawing.Size(180, 24)
$checkDateRange.Text = 'Enable date range'
$checkDateRange.Checked = $false
$form.Controls.Add($checkDateRange)

$labelStartDate = New-Object System.Windows.Forms.Label
$labelStartDate.Location = New-Object System.Drawing.Point(($left + 190), ($currentY + 4))
$labelStartDate.Size = New-Object System.Drawing.Size(42, 20)
$labelStartDate.Text = 'Start:'
$form.Controls.Add($labelStartDate)

$dateStart = New-Object System.Windows.Forms.DateTimePicker
$dateStart.Location = New-Object System.Drawing.Point(($left + 235), $currentY)
$dateStart.Size = New-Object System.Drawing.Size(170, 24)
$dateStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateStart.CustomFormat = 'yyyy-MM-dd HH:mm'
$dateStart.Value = (Get-Date).Date
$dateStart.Enabled = $false
$form.Controls.Add($dateStart)

$labelEndDate = New-Object System.Windows.Forms.Label
$labelEndDate.Location = New-Object System.Drawing.Point(($left + 415), ($currentY + 4))
$labelEndDate.Size = New-Object System.Drawing.Size(36, 20)
$labelEndDate.Text = 'End:'
$form.Controls.Add($labelEndDate)

$dateEnd = New-Object System.Windows.Forms.DateTimePicker
$dateEnd.Location = New-Object System.Drawing.Point(($left + 455), $currentY)
$dateEnd.Size = New-Object System.Drawing.Size(170, 24)
$dateEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateEnd.CustomFormat = 'yyyy-MM-dd HH:mm'
$dateEnd.Value = Get-Date
$dateEnd.Enabled = $false
$form.Controls.Add($dateEnd)

$currentY = $currentY + 38

$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelOutput.Text = 'CSV output folder:'
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textOutput.Size = New-Object System.Drawing.Size($textWidth, 24)
$textOutput.Text = $script:defaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseOutput.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseOutput.Text = 'Browse'
$form.Controls.Add($buttonBrowseOutput)

$currentY = $currentY + $rowHeight

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelLog.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelLog.Text = 'Log folder:'
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textLog.Size = New-Object System.Drawing.Size($textWidth, 24)
$textLog.Text = $script:defaultLogFolder
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseLog.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseLog.Text = 'Browse'
$form.Controls.Add($buttonBrowseLog)

$currentY = $currentY + $rowHeight + 4

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point($left, $currentY)
$progressBar.Size = New-Object System.Drawing.Size(716, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)
$script:progressBar = $progressBar

$currentY = $currentY + 28

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point($left, $currentY)
$statusLabel.Size = New-Object System.Drawing.Size(716, 32)
$statusLabel.Text = 'Ready.'
$form.Controls.Add($statusLabel)
$script:statusLabel = $statusLabel

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Size = New-Object System.Drawing.Size(150, 30)
$buttonStart.Location = New-Object System.Drawing.Point(420, 382)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 382)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

try {
    $initialSecurityFolder = Resolve-SecurityEvtxFolder
    if (-not [string]::IsNullOrWhiteSpace($initialSecurityFolder)) {
        $textEvtx.Text = $initialSecurityFolder
        Write-Log "Initial Security EVTX folder resolved: $initialSecurityFolder"
    }
}
catch {
    Write-Log -Level 'WARNING' -Message "Initial Security EVTX folder resolution failed: $($_.Exception.Message)"
}

$toggleInputs = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
}.GetNewClosure()
& $toggleInputs
$checkUseLive.Add_CheckedChanged($toggleInputs)

$toggleDateRange = {
    $dateStart.Enabled = $checkDateRange.Checked
    $dateEnd.Enabled = $checkDateRange.Checked
}.GetNewClosure()
$checkDateRange.Add_CheckedChanged($toggleDateRange)

$setBusyState = {
    param([bool]$IsBusy)

    $buttonStart.Enabled = (-not $IsBusy)
    $buttonClose.Enabled = (-not $IsBusy)
    $buttonResolve.Enabled = (-not $IsBusy)
    $buttonBrowseEvtx.Enabled = ((-not $IsBusy) -and (-not $checkUseLive.Checked))
    $buttonBrowseOutput.Enabled = (-not $IsBusy)
    $buttonBrowseLog.Enabled = (-not $IsBusy)
    $checkUseLive.Enabled = (-not $IsBusy)
    $checkIncludeSubfolders.Enabled = (-not $IsBusy)
    $textUsers.Enabled = (-not $IsBusy)
    $checkDateRange.Enabled = (-not $IsBusy)
    $dateStart.Enabled = ((-not $IsBusy) -and $checkDateRange.Checked)
    $dateEnd.Enabled = ((-not $IsBusy) -and $checkDateRange.Checked)
    $textOutput.Enabled = (-not $IsBusy)
    $textLog.Enabled = (-not $IsBusy)
}.GetNewClosure()

$buttonBrowseEvtx.Add_Click({
    $dialog = New-FolderPicker -Description 'Select a folder containing Security .evtx files'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textEvtx.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseOutput.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the folder where the CSV report will be saved'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textOutput.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$buttonBrowseLog.Add_Click({
    $dialog = New-FolderPicker -Description 'Select the log folder'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textLog.Text = $dialog.SelectedPath
        $script:defaultLogFolder = $dialog.SelectedPath
        $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
        Initialize-LogDirectory
    }
    $dialog.Dispose()
})

$buttonResolve.Add_Click({
    try {
        & $setBusyState $true
        $resolvedSecurityFolder = Resolve-SecurityEvtxFolder
        if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
            $textEvtx.Text = $resolvedSecurityFolder
        }

        $snapshotPath = Resolve-SecurityChannel

        if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
            Show-Info -Message ("Security channel validated successfully.`r`nEVTX folder:`r`n{0}`r`n`r`nSnapshot:`r`n{1}" -f $resolvedSecurityFolder, $snapshotPath) -Title 'Resolve Channel'
        }
        else {
            Show-Info -Message ("Security channel validated successfully, but the EVTX folder could not be resolved from registry.`r`nSnapshot:`r`n{0}" -f $snapshotPath) -Title 'Resolve Channel'
        }
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Resolve Channel failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Resolve Channel failed.`r`n{0}" -f $_.Exception.Message) -Title 'Resolve Channel'
    }
    finally {
        & $setBusyState $false
        & $toggleInputs
    }
}.GetNewClosure())

$buttonStart.Add_Click({
    try {
        & $setBusyState $true
        Write-Log 'GUI execution started.'
        $userFilterRawText = if ($null -ne $textUsers -and $null -ne $textUsers.Text) { [string]$textUsers.Text } else { '' }
        $users = Parse-DelimitedUsers -Text $userFilterRawText
        Write-Log ("GUI user filter captured. RawText='{0}'; ParsedCount={1}" -f $userFilterRawText, (Get-SafeCount -InputObject $users))
        $startFilter = $null
        $endFilter = $null
        if ($checkDateRange.Checked) {
            $startFilter = [datetime]$dateStart.Value
            $endFilter = [datetime]$dateEnd.Value
            if ($endFilter -lt $startFilter) {
                throw 'The end date/time cannot be earlier than the start date/time.'
            }
        }
        Process-Event4698 -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts $users -StartTime $startFilter -EndTime $endFilter
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Start analysis failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Start analysis failed.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        & $setBusyState $false
        & $toggleInputs
        Write-Log 'GUI execution finished.'
    }
}.GetNewClosure())

$buttonClose.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    Write-Log 'GUI initialized successfully.'
})

$form.Add_FormClosed({
    Write-Log '========== END: Scheduled Task Created Detector =========='
})

[void]$form.ShowDialog()
#endregion

# End of script
