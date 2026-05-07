<#
.SYNOPSIS
    PowerShell Script for detecting Event ID 4672 (Special privileges assigned to new logon).

.DESCRIPTION
    This WS2019-compatible revision analyzes Event ID 4672 from the live Security channel
    or archived .evtx files. In live mode, it exports a temporary snapshot with wevtutil
    and parses it using Log Parser COM. The consolidated CSV report is exported to
    My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-05-06-v5.1.4-RESOLVE-FOLDER-VALIDATION-HOTFIX
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
}
catch {
    # Non-fatal. This can fail if a host already initialized WinForms before script execution.
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

    $header = 'EventTime,EventID,UserAccount,DomainName,PrivilegeList,LogonId,ComputerName,SourceFile'
    Set-Content -LiteralPath $Path -Value $header -Encoding UTF8
}

function Get-RowCountSafe {
    param([string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { return 0 }
    try {
        $rows = Import-Csv -LiteralPath $CsvPath
        return @($rows).Count
    }
    catch {
        return 0
    }
}

function Build-UserFilterClause {
    param([string[]]$UserAccounts)

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($normalizedUsers).Count -eq 0) {
        return ''
    }

    $escaped = @($normalizedUsers | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" })
    return ("AND EXTRACT_TOKEN(Strings, 1, '|') IN ({0})" -f ($escaped -join '; '))
}


function Build-DateFilterClause {
    [CmdletBinding()]
    param(
        [Parameter()][bool]$UseDateRange,
        [Parameter()][object]$FromTime,
        [Parameter()][object]$ToTime
    )

    if (-not $UseDateRange) { return '' }

    $clauses = @()

    if ($null -ne $FromTime) {
        $fromText = ([datetime]$FromTime).ToString('yyyy-MM-dd HH:mm:ss')
        $clauses += ("AND TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $fromText)
    }

    if ($null -ne $ToTime) {
        $toText = ([datetime]$ToTime).ToString('yyyy-MM-dd HH:mm:ss')
        $clauses += ("AND TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $toText)
    }

    return ($clauses -join [Environment]::NewLine)
}


function Build-QueryForFile {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][bool]$UseDateRange = $false,
        [Parameter()][object]$FromTime = $null,
        [Parameter()][object]$ToTime = $null
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")
    $userClause  = Build-UserFilterClause -UserAccounts $UserAccounts
    $dateClause  = Build-DateFilterClause -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime

$query = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    EXTRACT_TOKEN(Strings, 1, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 2, '|') AS DomainName,
    EXTRACT_TOKEN(Strings, 4, '|') AS PrivilegeList,
    EXTRACT_TOKEN(Strings, 3, '|') AS LogonId,
    ComputerName,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
WHERE EventID = 4672
$userClause
$dateClause
ORDER BY EventTime DESC
"@
    return $query
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

function Invoke-EventQueryToCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][bool]$UseDateRange = $false,
        [Parameter()][object]$FromTime = $null,
        [Parameter()][object]$ToTime = $null
    )

    $lp = New-LogParserObjects
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime
    try {
        $result = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
        Write-Log "Log Parser ExecuteBatch returned: $result"
    }
    catch {
        Write-Log -Level 'WARNING' -Message "Skipped EVTX after non-fatal Log Parser/read failure: '$EvtxPath'. Error: $($_.Exception.Message)"
        return $false
    }

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }

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
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $users = $Text -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($users)
}

function Resolve-SecurityChannel {
    [CmdletBinding()]
    param()

    Update-ProgressSafe -Value 10 -StatusText 'Resolving Security channel via snapshot export...'
    $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'

    $tempCsv = Join-Path $env:TEMP ('Security-Probe-4672-{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Register-TempArtifact -Path $tempCsv
    Invoke-EventQueryToCsv -EvtxPath $snapshot -CsvPath $tempCsv -UserAccounts @()

    if (Test-Path -LiteralPath $tempCsv -PathType Leaf) {
        Write-Log 'Live Security channel probe completed successfully.'
        Update-ProgressSafe -Value 0 -StatusText 'Ready.'
        return $snapshot
    }

    throw 'Live Security channel probe did not produce a CSV file.'
}

function Process-Event4672 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter()][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter()][string]$OutputFolder,
        [Parameter()][string[]]$UserAccounts,
        [Parameter()][bool]$UseDateRange = $false,
        [Parameter()][object]$FromTime = $null,
        [Parameter()][object]$ToTime = $null
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ('{0}-EventID4672-AdminPrivilegesAssigned-{1}.csv' -f $computerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.ArrayList

    Write-Log "Starting Event ID 4672 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'; DateRange=$UseDateRange"

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Preparing...'

        if ($UseLiveLog) {
            Update-ProgressSafe -Value 15 -StatusText 'Exporting Security snapshot...'
            $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'
            $sourceFiles = @([pscustomobject]@{ FullName = $snapshot; Name = [IO.Path]::GetFileName($snapshot) })
        }
        else {
            Update-ProgressSafe -Value 15 -StatusText 'Enumerating archived EVTX files...'

            if ([string]::IsNullOrWhiteSpace($EvtxFolder)) {
                $resolvedSecurityFolder = Resolve-SecurityEvtxFolder
                if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
                    $EvtxFolder = $resolvedSecurityFolder
                    Write-Log -Message "Archive mode EVTX folder auto-resolved to '$EvtxFolder'."
                }
            }

            if ([string]::IsNullOrWhiteSpace($EvtxFolder)) {
                throw "Please select an EVTX folder or enable 'Use live Security channel'."
            }

            $sourceFiles = Get-EvtxFilesSafe -RootPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders
        }

        if (-not $UseLiveLog) {
            $sourceFiles = @(Get-ArchiveSafeEvtxFiles -Files @($sourceFiles))
        }

        $sourceCount = @($sourceFiles).Count
        if ($sourceCount -eq 0) {
            throw 'No .evtx files were found to process.'
        }

        $index = 0
        foreach ($source in @($sourceFiles)) {
            $index++
            $percent = 15 + [int]([Math]::Floor(($index / $sourceCount) * 65))
            Update-ProgressSafe -Value $percent -StatusText ("Processing {0} ({1} of {2})..." -f $source.Name, $index, $sourceCount)

            $tempCsv = Join-Path $env:TEMP ('Event4672-{0}-{1}.csv' -f $index, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
            Register-TempArtifact -Path $tempCsv
            [void]$tempCsvFiles.Add($tempCsv)

            try {
                $queryOk = Invoke-EventQueryToCsv -EvtxPath $source.FullName -CsvPath $tempCsv -UserAccounts $UserAccounts -UseDateRange $UseDateRange -FromTime $FromTime -ToTime $ToTime
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
        Write-Log "Found $rowCount Event ID 4672 records. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-Info -Message ("Found {0} Event ID 4672 records.`r`nReport exported to:`r`n{1}" -f $rowCount, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Error processing Event ID 4672. $($_.Exception.Message)"
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error processing Event ID 4672.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        Remove-TempArtifacts
    }
}
#endregion

#region GUI
Initialize-LogDirectory

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Admin Privileges Assigned Detector (Event ID 4672)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 490)
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

$checkDateRange = New-Object System.Windows.Forms.CheckBox
$checkDateRange.Location = New-Object System.Drawing.Point($left, $currentY)
$checkDateRange.Size = New-Object System.Drawing.Size(240, 24)
$checkDateRange.Text = 'Use date/time range'
$checkDateRange.Checked = $false
$form.Controls.Add($checkDateRange)

$currentY = $currentY + 30

$labelFrom = New-Object System.Windows.Forms.Label
$labelFrom.Location = New-Object System.Drawing.Point($left, ($currentY + 4))
$labelFrom.Size = New-Object System.Drawing.Size(70, 20)
$labelFrom.Text = 'From:'
$form.Controls.Add($labelFrom)

$dateFrom = New-Object System.Windows.Forms.DateTimePicker
$dateFrom.Location = New-Object System.Drawing.Point(($left + 70), $currentY)
$dateFrom.Size = New-Object System.Drawing.Size(220, 24)
$dateFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateFrom.Value = (Get-Date).Date
$dateFrom.Enabled = $false
$form.Controls.Add($dateFrom)

$labelTo = New-Object System.Windows.Forms.Label
$labelTo.Location = New-Object System.Drawing.Point(($left + 320), ($currentY + 4))
$labelTo.Size = New-Object System.Drawing.Size(40, 20)
$labelTo.Text = 'To:'
$form.Controls.Add($labelTo)

$dateTo = New-Object System.Windows.Forms.DateTimePicker
$dateTo.Location = New-Object System.Drawing.Point(($left + 360), $currentY)
$dateTo.Size = New-Object System.Drawing.Size(220, 24)
$dateTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateTo.Value = Get-Date
$dateTo.Enabled = $false
$form.Controls.Add($dateTo)

$checkDateRange.Add_CheckedChanged({
    $dateFrom.Enabled = $checkDateRange.Checked
    $dateTo.Enabled = $checkDateRange.Checked
})

$currentY = $currentY + $rowHeight

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point($left, ($currentY + 3))
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelUsers.Text = 'User filter:'
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(($left + $labelWidth), $currentY)
$textUsers.Size = New-Object System.Drawing.Size($textWidth, 24)
$textUsers.Text = ''
$form.Controls.Add($textUsers)

$currentY = $currentY + 28

$labelUsersHint = New-Object System.Windows.Forms.Label
$labelUsersHint.Location = New-Object System.Drawing.Point(($left + $labelWidth), ($currentY + 2))
$labelUsersHint.Size = New-Object System.Drawing.Size(430, 18)
$labelUsersHint.Text = 'Separate multiple users with comma, semicolon, or line break.'
$form.Controls.Add($labelUsersHint)

$currentY = $currentY + 34

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
$buttonStart.Location = New-Object System.Drawing.Point(420, 442)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 442)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$toggleInputs = {
    $isLive = $checkUseLive.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
}
& $toggleInputs
$checkUseLive.Add_CheckedChanged($toggleInputs)

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
})

$buttonStart.Add_Click({
    try {
        $users = Parse-DelimitedUsers -Text $textUsers.Text
        $useDateRange = [bool]$checkDateRange.Checked
        $fromValue = $null
        $toValue = $null

        if ($useDateRange) {
            $fromValue = $dateFrom.Value
            $toValue = $dateTo.Value

            if ($toValue -lt $fromValue) {
                throw 'The To date/time must be greater than or equal to the From date/time.'
            }
        }

        if (-not $checkUseLive.Checked -and [string]::IsNullOrWhiteSpace($textEvtx.Text)) {
            $resolvedSecurityFolder = Resolve-SecurityEvtxFolder
            if (-not [string]::IsNullOrWhiteSpace($resolvedSecurityFolder)) {
                $textEvtx.Text = $resolvedSecurityFolder
                Write-Log -Message "EVTX folder auto-populated before archive-mode execution: $resolvedSecurityFolder"
            }
        }

        if (-not $checkUseLive.Checked -and [string]::IsNullOrWhiteSpace($textEvtx.Text)) {
            Show-Info -Message "Please select an EVTX folder or enable 'Use live Security channel'." -Title 'Validation'
            return
        }

        Process-Event4672 -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts $users -UseDateRange:$useDateRange -FromTime $fromValue -ToTime $toValue
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Start Analysis failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Start Analysis failed.`r`n{0}" -f $_.Exception.Message) -Title 'Start Analysis'
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
