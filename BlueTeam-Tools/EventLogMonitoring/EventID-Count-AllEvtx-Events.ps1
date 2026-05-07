<#
.SYNOPSIS
    PowerShell Script for counting Event ID occurrences across EVTX files using Log Parser COM.

.DESCRIPTION
    This WS2019-compatible revision counts Event ID occurrences in archived .evtx files from a selected
    folder, with optional recursion into subfolders. It uses Log Parser COM for parsing and exports the
    consolidated CSV report to My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-05-06-v5.1.7-ZERO-SAFE-HOTFIX
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

        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message

    try {
        Add-Content -LiteralPath $script:logPath -Value $entry -Encoding UTF8
    }
    catch {
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


function Invoke-GuiSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$ErrorPrefix = 'Operation failed'
    )

    try {
        & $Action
    }
    catch {
        $msg = "{0}. {1}" -f $ErrorPrefix, $_.Exception.Message
        Write-Log -Level 'ERROR' -Message $msg
        Show-ErrorBox -Message $msg
    }
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


function Resolve-EventLogRootFolder {
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

            $securityFolder = Split-Path -Path ([string]$filePath) -Parent
            if ([string]::IsNullOrWhiteSpace($securityFolder)) { continue }

            $rootCandidate = Split-Path -Path $securityFolder -Parent
            if (-not [string]::IsNullOrWhiteSpace($rootCandidate) -and (Test-Path -LiteralPath $rootCandidate -PathType Container)) {
                Write-Log -Message "Event log root folder resolved from Security.evtx path: $rootCandidate"
                return $rootCandidate
            }

            if (Test-Path -LiteralPath $securityFolder -PathType Container) {
                Write-Log -Message "Event log folder resolved from Security.evtx path: $securityFolder"
                return $securityFolder
            }
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to validate EventLog folder candidate '$filePath'. $($_.Exception.Message)"
        }
    }

    $fallback = Join-Path $env:SystemRoot 'System32\winevt\Logs'
    if (Test-Path -LiteralPath $fallback -PathType Container) {
        Write-Log -Level 'WARNING' -Message "Event log root folder could not be resolved from registry. Using fallback: $fallback"
        return $fallback
    }

    return $null
}



function Resolve-SmartEventLogFolder {
    [CmdletBinding()]
    param(
        [string]$PreferredChannelFolder
    )

    $resolved = Resolve-EventLogRootFolder

    if ([string]::IsNullOrWhiteSpace($resolved)) {
        return $null
    }

    $candidateFolders = @(
        (Join-Path $resolved 'Security'),
        (Join-Path $resolved 'Microsoft-Windows-PrintService-Operational'),
        (Join-Path $resolved 'System'),
        (Join-Path $resolved 'Application')
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredChannelFolder)) {
        $specific = Join-Path $resolved $PreferredChannelFolder
        $candidateFolders = @($specific) + $candidateFolders
    }

    foreach ($folder in $candidateFolders | Select-Object -Unique) {
        if (Test-Path -LiteralPath $folder -PathType Container) {
            return $folder
        }
    }

    return $resolved
}

function Test-IsLikelyActiveEvtxFile {
    param([Parameter(Mandatory)][string]$Path)

    $name = [System.IO.Path]::GetFileName($Path)

    if ($name -notlike 'Archive-*' -and $name -notlike '*_snapshot*' -and $name -notlike '*Snapshot*') {
        return $true
    }

    return $false
}


function Register-TempArtifact {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        [void]$script:tempArtifacts.Add($Path)
    }
}

function Remove-TempArtifacts {
    foreach ($artifact in @($script:tempArtifacts)) {
        try {
            if (Test-Path -LiteralPath $artifact) {
                Remove-Item -LiteralPath $artifact -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
    $script:tempArtifacts.Clear() | Out-Null
}

function New-LogParserObjects {
    $objects = [ordered]@{
        Query        = New-Object -ComObject 'MSUtil.LogQuery'
        InputFormat  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        OutputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
    }
    return $objects
}

function New-HeaderOnlyCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $header = 'EventID,Count,SourceFile'
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function Get-RowCountSafe {
    param([string]$CsvPath)

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        return 0
    }

    try {
        $rows = Import-Csv -LiteralPath $CsvPath
        return @($rows).Count
    }
    catch {
        return 0
    }
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


function Build-QueryForFile {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")

$query = @"
SELECT
    EventID,
    COUNT(*) AS Count,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
GROUP BY EventID
ORDER BY EventID ASC
"@
    return $query
}

function Invoke-EventCountToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath
    )

    $lp = New-LogParserObjects
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath

    $result = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $result for '$EvtxPath'"

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }
}

function Merge-CsvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$SourceCsvFiles,
        [Parameter(Mandatory)][string]$DestinationCsv
    )

    $existing = @($SourceCsvFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if (@($existing).Count -eq 0) {
        New-HeaderOnlyCsv -Path $DestinationCsv
        return
    }

    $first = $true
    foreach ($csv in @($existing)) {
        if ($first) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $first = $false
        }
        else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
}



function Get-LogParserPath {
    [CmdletBinding()]
    param()

    $candidates = @(
        "C:\Program Files (x86)\Log Parser 2.2\LogParser.exe",
        "C:\Program Files\Log Parser 2.2\LogParser.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw "Log Parser executable was not found. Please install Microsoft Log Parser 2.2."
}

function Escape-SqlPath {
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace "'", "''")
}

function New-EvtxBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Files,
        [int]$BatchSize = 75
    )

    $batches = New-Object System.Collections.Generic.List[object]
    $current = New-Object System.Collections.Generic.List[string]

    foreach ($file in @($Files)) {
        $path = if ($file -is [System.IO.FileInfo]) { $file.FullName } else { [string]$file }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        [void]$current.Add($path)

        if ($current.Count -ge $BatchSize) {
            [void]$batches.Add(@($current.ToArray()))
            $current = New-Object System.Collections.Generic.List[string]
        }
    }

    if ($current.Count -gt 0) {
        [void]$batches.Add(@($current.ToArray()))
    }

    return @($batches.ToArray())
}

function Invoke-LogParserFileQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Sql,
        [Parameter(Mandatory)][string]$Context
    )

    $logParser = Get-LogParserPath

    $sqlFile = Join-Path $env:TEMP ("EventIdCount-{0}.sql" -f ([guid]::NewGuid().ToString("N")))
    Set-Content -Path $sqlFile -Value $Sql -Encoding ASCII

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $logParser
        $psi.Arguments = "-i:EVT -o:CSV file:`"$sqlFile`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $p = [System.Diagnostics.Process]::Start($psi)
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()

        Write-Log -Message ("Log Parser execution [{0}] ExitCode={1}" -f $Context, $p.ExitCode)

        if ($stderr) {
            Write-Log -Level 'WARNING' -Message ("Log Parser stderr [{0}]: {1}" -f $Context, $stderr)
        }

        if ($p.ExitCode -ne 0) {
            throw "Log Parser failed for $Context. ExitCode=$($p.ExitCode). $stderr $stdout"
        }
    }
    finally {
        Remove-Item -LiteralPath $sqlFile -Force -ErrorAction SilentlyContinue
    }
}


function Process-EvtxEventCounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [Parameter(Mandatory)][string]$OutputFolder
    )

    try {
        if ([string]::IsNullOrWhiteSpace($EvtxFolder) -or -not (Test-Path -LiteralPath $EvtxFolder -PathType Container)) {
            throw "Please select a valid EVTX folder."
        }

        if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
            throw "Please select a valid output folder."
        }

        if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
        }

        Write-Log -Message "Starting EVTX Event ID counting. Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$OutputFolder'"

        Update-ProgressSafe -Value 10 -StatusText "Enumerating EVTX files..."

        $gciParams = @{
            LiteralPath = $EvtxFolder
            Filter = "*.evtx"
            File = $true
            ErrorAction = "SilentlyContinue"
        }

        if ($IncludeSubfolders) {
            $gciParams["Recurse"] = $true
        }

        $sourceFiles = @(Get-ChildItem @gciParams)
        if ($sourceFiles.Count -eq 0) {
            throw "No EVTX files were found in the selected folder."
        }

        $sourceFiles = @(Get-ArchiveSafeEvtxFiles -Files $sourceFiles)

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $finalCsv = Join-Path $OutputFolder ("{0}-EventID-Counts-AllEvtx-{1}.csv" -f $env:COMPUTERNAME, $timestamp)

        if ($sourceFiles.Count -eq 0) {
            "EventID,Count,SourceFile" | Set-Content -Path $finalCsv -Encoding UTF8
            Update-ProgressSafe -Value 100 -StatusText "Completed with no archive-safe EVTX files."
            Write-Log -Level 'WARNING' -Message "No archive-safe EVTX files were available. Empty CSV exported: '$finalCsv'"
            Show-Info -Message ("No archive-safe EVTX files were available for processing.`r`nThis usually means the selected folder contains only an active/canonical log file.`r`n`r`nEmpty CSV exported:`r`n{0}" -f $finalCsv) -Title "No Archive-Safe Files"
            try {
                Invoke-Item -LiteralPath $finalCsv
            }
            catch {
                Write-Log -Level 'WARNING' -Message "Failed to auto-open empty CSV '$finalCsv'. $($_.Exception.Message)"
            }
            return
        }

        $batchFolder = Join-Path $env:TEMP ("EventIDCountBatches-{0}" -f ([guid]::NewGuid().ToString("N")))
        New-Item -ItemType Directory -Path $batchFolder -Force | Out-Null

        $batchSize = 75
        $batches = @(New-EvtxBatch -Files $sourceFiles -BatchSize $batchSize)

        Write-Log -Message "Batched Log Parser mode enabled. SourceFiles=$($sourceFiles.Count); BatchSize=$batchSize; Batches=$($batches.Count)"
        Update-ProgressSafe -Value 20 -StatusText "Processing EVTX batches..."

        $tempCsvs = New-Object System.Collections.Generic.List[string]
        $batchIndex = 0

        foreach ($batch in @($batches)) {
            $batchIndex++
            $batchCsv = Join-Path $batchFolder ("batch-{0:0000}.csv" -f $batchIndex)

            $fromParts = @()
            foreach ($path in @($batch)) {
                if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
                $fromParts += ("'{0}'" -f (Escape-SqlPath -Path ([string]$path)))
            }

            if ($fromParts.Count -eq 0) { continue }

            $fromClause = $fromParts -join ","

            $sql = @"
SELECT
  EventID AS EventID,
  COUNT(*) AS Count,
  [EventLog] AS SourceFile
INTO '$batchCsv'
FROM $fromClause
GROUP BY EventID, [EventLog]
ORDER BY EventID ASC
"@

            Invoke-LogParserFileQuery -Sql $sql -Context ("EventIDCountBatch{0}" -f $batchIndex)

            if (Test-Path -LiteralPath $batchCsv) {
                [void]$tempCsvs.Add($batchCsv)
            }

            $pct = 20 + [int](($batchIndex / [double]$batches.Count) * 60)
            if ($pct -gt 80) { $pct = 80 }
            Update-ProgressSafe -Value $pct -StatusText ("Processed batch {0} of {1}" -f $batchIndex, $batches.Count)
        }

        Update-ProgressSafe -Value 85 -StatusText "Merging batch CSV files..."

        $allRows = New-Object System.Collections.Generic.List[object]

        foreach ($csv in @($tempCsvs)) {
            try {
                $rows = @(Import-Csv -Path $csv)
                foreach ($row in $rows) {
                    [void]$allRows.Add([pscustomobject]@{
                        EventID = [string]$row.EventID
                        Count = [string]$row.Count
                        SourceFile = [string]$row.SourceFile
                    })
                }
            }
            catch {
                Write-Log -Level 'WARNING' -Message "Failed to import temporary count CSV '$csv'. $($_.Exception.Message)"
            }
        }

        if ($allRows.Count -eq 0) {
            "EventID,Count,SourceFile" | Set-Content -Path $finalCsv -Encoding UTF8
        }
        else {
            $allRows |
                Sort-Object SourceFile, @{Expression={ 
                    $parsed = 0
                    if ([int]::TryParse([string]$_.EventID, [ref]$parsed)) { $parsed } else { 0 }
                }} |
                Export-Csv -Path $finalCsv -NoTypeInformation -Encoding UTF8
        }

        Remove-Item -LiteralPath $batchFolder -Recurse -Force -ErrorAction SilentlyContinue

        Update-ProgressSafe -Value 100 -StatusText "Completed."
        Write-Log -Message "EVTX Event ID count completed. SourceFiles=$($sourceFiles.Count); Batches=$($batches.Count); Rows=$($allRows.Count); Report='$finalCsv'"

        Show-Info -Message ("Event ID count completed successfully.`r`nSource files: {0}`r`nRows: {1}`r`nReport:`r`n{2}" -f $sourceFiles.Count, $allRows.Count, $finalCsv) -Title "Completed"

        try {
            Invoke-Item -LiteralPath $finalCsv
        }
        catch {
            Write-Log -Level 'WARNING' -Message "Failed to auto-open CSV '$finalCsv'. $($_.Exception.Message)"
        }
    }
    catch {
        Update-ProgressSafe -Value 0 -StatusText "Failed."
        Write-Log -Level 'ERROR' -Message "Error counting Event IDs. $($_.Exception.Message)"
        Show-ErrorBox -Message ("Error counting Event IDs.`r`n{0}" -f $_.Exception.Message)
    }
}
#endregion

#region GUI
Initialize-LogDirectory

$form = New-Object System.Windows.Forms.Form
$form.Text = 'EVTX Event ID Counter'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(870, 352)
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

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelEvtx.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtx.Text = 'EVTX folder:'
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textEvtx.Size = New-Object System.Drawing.Size($textWidth, 24)
try {
    $resolvedDefaultEvtxRoot = Resolve-SmartEventLogFolder
    if (-not [string]::IsNullOrWhiteSpace($resolvedDefaultEvtxRoot)) {
        $textEvtx.Text = $resolvedDefaultEvtxRoot
    }
}
catch {
    Write-Log -Level 'WARNING' -Message "Default EVTX folder resolution failed: $($_.Exception.Message)"
}
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point($buttonX, $currentY)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($buttonWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$form.Controls.Add($buttonBrowseEvtx)

$buttonResolveEvtx = New-Object System.Windows.Forms.Button
$buttonResolveEvtx.Location = New-Object System.Drawing.Point(($buttonX + $buttonWidth + 8), $currentY)
$buttonResolveEvtx.Size = New-Object System.Drawing.Size(92, 24)
$buttonResolveEvtx.Text = 'Resolve'
$form.Controls.Add($buttonResolveEvtx)

$currentY = $currentY + $rowHeight

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point($left, $currentY)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(240, 24)
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$form.Controls.Add($checkIncludeSubfolders)

$currentY = $currentY + $rowHeight

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
$progressBar.Size = New-Object System.Drawing.Size(826, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)
$script:progressBar = $progressBar

$currentY = $currentY + 28

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point($left, $currentY)
$statusLabel.Size = New-Object System.Drawing.Size(826, 32)
$statusLabel.Text = 'Ready.'
$form.Controls.Add($statusLabel)
$script:statusLabel = $statusLabel

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Size = New-Object System.Drawing.Size(150, 30)
$buttonStart.Location = New-Object System.Drawing.Point(530, 304)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(700, 304)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$buttonBrowseEvtx.Add_Click({
    Invoke-GuiSafe -ErrorPrefix 'Browse EVTX folder failed' -Action {
        $dialog = New-FolderPicker -Description 'Select a folder containing EVTX files'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $textEvtx.Text = $dialog.SelectedPath
        }
        $dialog.Dispose()
    }
})

$buttonResolveEvtx.Add_Click({
    Invoke-GuiSafe -ErrorPrefix 'Resolve EVTX folder failed' -Action {
        $resolved = Resolve-SmartEventLogFolder
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            $textEvtx.Text = $resolved
            Show-Info -Message ("Event log root folder resolved:`r`n{0}" -f $resolved) -Title 'Resolve EVTX Folder'
        }
        else {
            Show-Info -Message 'The EVTX folder could not be resolved automatically. Please browse manually.' -Title 'Resolve EVTX Folder'
        }
    }
})

$buttonBrowseOutput.Add_Click({
    Invoke-GuiSafe -ErrorPrefix 'Browse output folder failed' -Action {
        $dialog = New-FolderPicker -Description 'Select the folder where the CSV report will be saved'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $textOutput.Text = $dialog.SelectedPath
        }
        $dialog.Dispose()
    }
})

$buttonBrowseLog.Add_Click({
    Invoke-GuiSafe -ErrorPrefix 'Browse log folder failed' -Action {
        $dialog = New-FolderPicker -Description 'Select the log folder'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $textLog.Text = $dialog.SelectedPath
            $script:defaultLogFolder = $dialog.SelectedPath
            $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
            Initialize-LogDirectory
        }
        $dialog.Dispose()
    }
})

$buttonStart.Add_Click({
    Invoke-GuiSafe -ErrorPrefix 'Event ID count analysis failed' -Action {
        if ([string]::IsNullOrWhiteSpace($textEvtx.Text)) {
            $resolved = Resolve-SmartEventLogFolder
            if (-not [string]::IsNullOrWhiteSpace($resolved)) {
                $textEvtx.Text = $resolved
            }
        }

        if ([string]::IsNullOrWhiteSpace($textEvtx.Text)) {
            Show-ErrorBox -Message 'Please select a folder containing EVTX files.' -Title 'Input Required'
            return
        }

        $script:defaultLogFolder = $textLog.Text
        $script:logPath = Join-Path $script:defaultLogFolder ($scriptName + '.log')
        Initialize-LogDirectory

        Process-EvtxEventCounts -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text
    }
})

$buttonClose.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    Write-Log 'Script initialized successfully.'
})

[void]$form.ShowDialog()
#endregion

# End of script
