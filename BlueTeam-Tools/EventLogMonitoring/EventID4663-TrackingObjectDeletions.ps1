<#
.SYNOPSIS
    Tracks object deletion events via Event ID 4663 (Access Mask 0x10000) using Log Parser-first processing.

.DESCRIPTION
    Supports live Security log analysis through a temporary EVTX snapshot created with wevtutil,
    and archived EVTX analysis from a selected folder. Results are exported to CSV in the user's
    My Documents folder by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-05-06-v5.2.2-RESOLVE-FOLDER-REGISTRY-HOTFIX
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = 'Automatically open the consolidated CSV file after processing.')]
    [bool]$AutoOpen = $true,
    [switch]$ShowConsole
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Console helpers
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
    if (-not $ShowConsole) {
        $consoleHwnd = [Win32Console]::GetConsoleWindow()
        if ($consoleHwnd -ne [IntPtr]::Zero) { [void][Win32Console]::ShowWindow($consoleHwnd, 0) }
    }
} catch {
    Write-Error "Failed to initialize console visibility helpers. $($_.Exception.Message)"
    exit 1
}
#endregion

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $eventArgs)
        try {
            Write-Log -Level ERROR -Message ("Unhandled GUI exception: {0}" -f $eventArgs.Exception.Message)
            Show-UiMessage -Message $eventArgs.Exception.Message -Title 'Unhandled GUI Error' -Icon Error
        } catch {}
    })
} catch {}
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:logDir = 'C:\Logs-TEMP'
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:logPath = Join-Path $script:logDir ($scriptName + '.log')
$script:liveChannelName = 'Security'
$script:progressBar = $null
$script:form = $null
$script:labelStatus = $null

if (-not (Test-Path -LiteralPath $script:logDir)) {
    New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')][string]$Level = 'INFO'
    )
    $entry = ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    try { Add-Content -Path $script:logPath -Value $entry -Encoding UTF8 } catch {}
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


function Show-UiMessage {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon)
}

function Set-Status {
    param([string]$Text, [int]$Progress = -1)
    if ($script:labelStatus) { $script:labelStatus.Text = $Text }
    if ($script:progressBar -and $Progress -ge 0) {
        $bounded = [Math]::Max(0, [Math]::Min(100, $Progress))
        $script:progressBar.Value = $bounded
    }
    if ($script:form) {
        $script:form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-DefaultOutputFolder {
    param([string]$Preferred)
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) { return $Preferred }
    return $script:defaultOutputFolder
}

function Select-FolderPath {
    param([Parameter(Mandatory)][string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-LogParserComObjects {
    try {
        return [pscustomobject]@{
            Query  = New-Object -ComObject 'MSUtil.LogQuery'
            Input  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
            Output = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        }
    } catch {
        throw 'Microsoft Log Parser 2.2 COM components are not available.'
    }
}

function New-EmptyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    Set-Content -Path $Path -Value ($Headers -join ',') -Encoding UTF8
}

function Export-LiveChannelSnapshot {
    param([Parameter(Mandatory)][string]$ChannelName)

    $tempDir = Join-Path $env:TEMP 'BlueTeam-Tools-Snapshots'
    Ensure-Directory -Path $tempDir
    $snapshotPath = Join-Path $tempDir ('{0}-{1}.evtx' -f ($ChannelName -replace '[^A-Za-z0-9_-]', '_'), (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'wevtutil.exe'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.Arguments = ('epl "{0}" "{1}" /ow:true' -f $ChannelName, $snapshotPath)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdOut = $process.StandardOutput.ReadToEnd()
    $stdErr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshotPath)) {
        throw ("wevtutil export failed. ExitCode={0}. StdErr={1}" -f $process.ExitCode, $stdErr.Trim())
    }

    Write-Log "Live channel snapshot exported to '$snapshotPath'."
    return $snapshotPath
}


function Get-EventChannelLogPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wevtutil.exe'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        $psi.Arguments = ('gl "{0}" /f:xml' -f $ChannelName)

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdOut = $process.StandardOutput.ReadToEnd()
        $stdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdOut)) {
            try {
                [xml]$xml = $stdOut
                $xmlValue = $xml.SelectSingleNode('//logFileName')
                if ($null -ne $xmlValue -and -not [string]::IsNullOrWhiteSpace($xmlValue.InnerText)) {
                    [void]$candidates.Add($xmlValue.InnerText.Trim())
                }
            } catch {
                Write-Log -Level WARN -Message ("Unable to parse wevtutil XML output for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
            }
        } else {
            Write-Log -Level WARN -Message ("wevtutil XML query did not return a log file for channel '{0}'. ExitCode={1}. StdErr={2}" -f $ChannelName, $process.ExitCode, $stdErr.Trim())
        }
    } catch {
        Write-Log -Level WARN -Message ("wevtutil XML query failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    try {
        $classicName = if ($ChannelName -eq 'Security') { 'Security' } else { $ChannelName }
        $classicPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\$classicName"
        if (Test-Path -LiteralPath $classicPath) {
            $fileValue = (Get-ItemProperty -LiteralPath $classicPath -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
                [void]$candidates.Add($fileValue.Trim())
            }
        }
    } catch {
        Write-Log -Level WARN -Message ("Classic EventLog registry lookup failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    try {
        $winevtPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\$ChannelName"
        if (Test-Path -LiteralPath $winevtPath) {
            $fileValue = (Get-ItemProperty -LiteralPath $winevtPath -Name File -ErrorAction SilentlyContinue).File
            if (-not [string]::IsNullOrWhiteSpace($fileValue)) {
                [void]$candidates.Add($fileValue.Trim())
            }
        }
    } catch {
        Write-Log -Level WARN -Message ("WINEVT registry lookup failed for channel '{0}': {1}" -f $ChannelName, $_.Exception.Message)
    }

    foreach ($candidate in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path -Path $env:SystemRoot -ChildPath $expanded
        }
        if (-not [string]::IsNullOrWhiteSpace($expanded)) {
            Write-Log ("Resolved channel '{0}' log path candidate: {1}" -f $ChannelName, $expanded)
            return $expanded
        }
    }

    return $null
}

function Resolve-EventChannelFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChannelName)

    $logPath = Get-EventChannelLogPath -ChannelName $ChannelName
    if ([string]::IsNullOrWhiteSpace($logPath)) {
        return $null
    }

    $folder = [System.IO.Path]::GetDirectoryName($logPath)
    if ([string]::IsNullOrWhiteSpace($folder)) {
        return $null
    }

    return $folder
}

function Invoke-DeletionQuery {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$CsvPath,
        [string[]]$UserAccounts,
        [object]$FromTime,
        [object]$ToTime
    )

    $com = Get-LogParserComObjects

    $userPredicate = ''
    if (@($UserAccounts).Count -gt 0) {
        $escapedUsers = @($UserAccounts | ForEach-Object { $_.Replace("'", "''") })
        $quotedUsers = @($escapedUsers | ForEach-Object { "'$_'" })
        $userPredicate = (' AND EXTRACT_TOKEN(Strings, 1, ''|'') IN ({0})' -f ($quotedUsers -join ','))
    }

    $datePredicate = ''
    if ($FromTime -is [datetime]) {
        $fromLiteral = ([datetime]$FromTime).ToString('yyyy-MM-dd HH:mm:ss')
        $datePredicate += (" AND TimeGenerated >= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $fromLiteral)
    }
    if ($ToTime -is [datetime]) {
        $toLiteral = ([datetime]$ToTime).ToString('yyyy-MM-dd HH:mm:ss')
        $datePredicate += (" AND TimeGenerated <= TO_TIMESTAMP('{0}', 'yyyy-MM-dd HH:mm:ss')" -f $toLiteral)
    }

    $safePath = $EvtxPath.Replace("'", "''")
    $sql = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    EXTRACT_TOKEN(Strings, 1, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 2, '|') AS Domain,
    EXTRACT_TOKEN(Strings, 5, '|') AS ObjectType,
    EXTRACT_TOKEN(Strings, 6, '|') AS AccessedObject,
    EXTRACT_TOKEN(Strings, 7, '|') AS AccessList,
    EXTRACT_TOKEN(Strings, 8, '|') AS AccessMask,
    EXTRACT_TOKEN(Strings, 9, '|') AS ProcessName
INTO '$CsvPath'
FROM '$safePath'
WHERE EventID = 4663
  AND EXTRACT_TOKEN(Strings, 8, '|') = '0x10000'$userPredicate$datePredicate
"@

    try {
        $result = $com.Query.ExecuteBatch($sql, $com.Input, $com.Output)
        Write-Log ("Log Parser ExecuteBatch returned: {0}" -f $result)
    } catch {
        throw ("Log Parser query failed for '{0}'. {1}" -f $EvtxPath, $_.Exception.Message)
    }

    if (-not (Test-Path -LiteralPath $CsvPath)) {
        New-EmptyCsv -Path $CsvPath -Headers @('EventTime','EventID','UserAccount','Domain','ObjectType','AccessedObject','AccessList','AccessMask','ProcessName')
    }
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$CsvFiles,
        [Parameter(Mandatory)][string]$OutputFile
    )

    $files = @($CsvFiles | Where-Object { Test-Path -LiteralPath $_ })
    if (@($files).Count -eq 0) {
        New-EmptyCsv -Path $OutputFile -Headers @('EventTime','EventID','UserAccount','Domain','ObjectType','AccessedObject','AccessList','AccessMask','ProcessName')
        return
    }

    $first = $true
    foreach ($file in $files) {
        $lines = Get-Content -Path $file -Encoding UTF8
        if ($first) {
            Set-Content -Path $OutputFile -Value $lines -Encoding UTF8
            $first = $false
        } else {
            @($lines | Select-Object -Skip 1) | Add-Content -Path $OutputFile -Encoding UTF8
        }
    }
}

function Get-EventCountFromCsv {
    param([Parameter(Mandatory)][string]$CsvPath)
    if (-not (Test-Path -LiteralPath $CsvPath)) { return 0 }
    $rows = @(Import-Csv -Path $CsvPath)
    return @($rows).Count
}

function Start-DeletionAnalysis {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string[]]$UserAccounts,
        [bool]$UseDateRange = $false,
        [object]$FromTime,
        [object]$ToTime
    )

    $resolvedOutput = Get-DefaultOutputFolder -Preferred $OutputFolder
    Ensure-Directory -Path $resolvedOutput
    Write-Log "Starting Event ID 4663 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'; DateRange=$UseDateRange"
    if ($UseDateRange -and ($FromTime -is [datetime]) -and ($ToTime -is [datetime]) -and ([datetime]$FromTime -gt [datetime]$ToTime)) {
        throw 'Invalid date range. The From date/time must be earlier than or equal to the To date/time.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ("{0}-ObjectDeletionTracking-{1}.csv" -f $env:COMPUTERNAME, $timestamp)
    $tempDir = Join-Path $env:TEMP ('{0}-{1}' -f $scriptName, $timestamp)
    Ensure-Directory -Path $tempDir
    $tempCsvFiles = New-Object System.Collections.Generic.List[string]
    $tempSnapshot = $null

    try {
        if ($UseLiveLog) {
            Set-Status -Text 'Exporting live Security snapshot...' -Progress 10
            $tempSnapshot = Export-LiveChannelSnapshot -ChannelName $script:liveChannelName
            $tempCsv = Join-Path $tempDir 'LiveSecurity4663.csv'
            Set-Status -Text 'Querying Event ID 4663 from snapshot...' -Progress 40
            Invoke-DeletionQuery -EvtxPath $tempSnapshot -CsvPath $tempCsv -UserAccounts $UserAccounts -FromTime $(if ($UseDateRange) { $FromTime } else { $null }) -ToTime $(if ($UseDateRange) { $ToTime } else { $null })
            $tempCsvFiles.Add($tempCsv)
        } else {
            if ([string]::IsNullOrWhiteSpace($EvtxFolder) -or -not (Test-Path -LiteralPath $EvtxFolder)) {
                throw 'Please provide a valid EVTX folder.'
            }
            $searchOption = if ($IncludeSubfolders) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
            $evtxFiles = @([System.IO.Directory]::GetFiles($EvtxFolder, '*.evtx', $searchOption))
            if (-not $UseLiveLog) {
            $evtxFiles = @(Get-ArchiveSafeEvtxFiles -Files @($evtxFiles))
        }

        if (@($evtxFiles).Count -eq 0) {
                throw "No .evtx files were found in '$EvtxFolder'."
            }
            $total = @($evtxFiles).Count
            $index = 0
            foreach ($evtxFile in $evtxFiles) {
                $index++
                $progress = 10 + [int](($index / $total) * 70)
                Set-Status -Text ("Processing {0} ({1} of {2})..." -f ([IO.Path]::GetFileName($evtxFile)), $index, $total) -Progress $progress
                $tempCsv = Join-Path $tempDir (([IO.Path]::GetFileNameWithoutExtension($evtxFile)) + '.csv')
                Invoke-DeletionQuery -EvtxPath $evtxFile -CsvPath $tempCsv -UserAccounts $UserAccounts -FromTime $(if ($UseDateRange) { $FromTime } else { $null }) -ToTime $(if ($UseDateRange) { $ToTime } else { $null })
                $tempCsvFiles.Add($tempCsv)
            }
        }

        Set-Status -Text 'Merging results...' -Progress 90
        Merge-CsvFiles -CsvFiles $tempCsvFiles.ToArray() -OutputFile $finalCsv
        $eventCount = Get-EventCountFromCsv -CsvPath $finalCsv
        Write-Log "Found $eventCount object deletion events. Report exported to '$finalCsv'"
        Set-Status -Text ("Completed. Found {0} events." -f $eventCount) -Progress 100
        Show-UiMessage -Message ("Analysis complete. Found {0} events.`nSaved to:`n{1}" -f $eventCount, $finalCsv) -Title 'Success'
        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv)) { Start-Process -FilePath $finalCsv }
    } finally {
        if ($tempSnapshot -and (Test-Path -LiteralPath $tempSnapshot)) {
            try { Remove-Item -LiteralPath $tempSnapshot -Force -ErrorAction Stop } catch {}
        }
        if (Test-Path -LiteralPath $tempDir) {
            try { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction Stop } catch {}
        }
        Set-Status -Text 'Ready.' -Progress 0
    }
}

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Event ID 4663 - Object Deletion Tracking'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(760, 470)
$form.MinimumSize = New-Object System.Drawing.Size(760, 470)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$script:form = $form

$labelUseLive = New-Object System.Windows.Forms.Label
$labelUseLive.Text = 'Use live Security channel:'
$labelUseLive.Location = New-Object System.Drawing.Point(20, 20)
$labelUseLive.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelUseLive)

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Checked = $true
$checkUseLive.Location = New-Object System.Drawing.Point(200, 18)
$checkUseLive.Size = New-Object System.Drawing.Size(20, 20)
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Location = New-Object System.Drawing.Point(590, 16)
$buttonResolve.Size = New-Object System.Drawing.Size(130, 26)
$form.Controls.Add($buttonResolve)

$labelEvtx = New-Object System.Windows.Forms.Label
$labelEvtx.Text = 'EVTX folder:'
$labelEvtx.Location = New-Object System.Drawing.Point(20, 60)
$labelEvtx.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelEvtx)

$textEvtx = New-Object System.Windows.Forms.TextBox
$textEvtx.Location = New-Object System.Drawing.Point(200, 58)
$textEvtx.Size = New-Object System.Drawing.Size(380, 24)
$form.Controls.Add($textEvtx)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = 'Browse...'
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(590, 56)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(130, 26)
$form.Controls.Add($buttonBrowseEvtx)

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point(200, 90)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(180, 22)
$form.Controls.Add($checkIncludeSubfolders)

$checkDateRange = New-Object System.Windows.Forms.CheckBox
$checkDateRange.Text = 'Use date/time range'
$checkDateRange.Checked = $false
$checkDateRange.Location = New-Object System.Drawing.Point(400, 90)
$checkDateRange.Size = New-Object System.Drawing.Size(180, 22)
$form.Controls.Add($checkDateRange)

$labelFrom = New-Object System.Windows.Forms.Label
$labelFrom.Text = 'From:'
$labelFrom.Location = New-Object System.Drawing.Point(20, 124)
$labelFrom.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelFrom)

$dateFrom = New-Object System.Windows.Forms.DateTimePicker
$dateFrom.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateFrom.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateFrom.ShowUpDown = $false
$dateFrom.Location = New-Object System.Drawing.Point(200, 122)
$dateFrom.Size = New-Object System.Drawing.Size(180, 24)
$dateFrom.Value = (Get-Date).Date
$form.Controls.Add($dateFrom)

$labelTo = New-Object System.Windows.Forms.Label
$labelTo.Text = 'To:'
$labelTo.Location = New-Object System.Drawing.Point(400, 124)
$labelTo.Size = New-Object System.Drawing.Size(40, 20)
$form.Controls.Add($labelTo)

$dateTo = New-Object System.Windows.Forms.DateTimePicker
$dateTo.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$dateTo.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$dateTo.ShowUpDown = $false
$dateTo.Location = New-Object System.Drawing.Point(440, 122)
$dateTo.Size = New-Object System.Drawing.Size(180, 24)
$dateTo.Value = Get-Date
$form.Controls.Add($dateTo)

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'User filter (comma / semicolon):'
$labelUsers.Location = New-Object System.Drawing.Point(20, 164)
$labelUsers.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(200, 162)
$textUsers.Size = New-Object System.Drawing.Size(520, 24)
$form.Controls.Add($textUsers)

$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = 'Output folder:'
$labelOutput.Location = New-Object System.Drawing.Point(20, 204)
$labelOutput.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point(200, 202)
$textOutput.Size = New-Object System.Drawing.Size(380, 24)
$textOutput.Text = $script:defaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = 'Browse...'
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(590, 200)
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(130, 26)
$form.Controls.Add($buttonBrowseOutput)

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Text = 'Log folder:'
$labelLog.Location = New-Object System.Drawing.Point(20, 244)
$labelLog.Size = New-Object System.Drawing.Size(170, 20)
$form.Controls.Add($labelLog)

$textLog = New-Object System.Windows.Forms.TextBox
$textLog.Location = New-Object System.Drawing.Point(200, 242)
$textLog.Size = New-Object System.Drawing.Size(380, 24)
$textLog.Text = $script:logDir
$form.Controls.Add($textLog)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = 'Browse...'
$buttonBrowseLog.Location = New-Object System.Drawing.Point(590, 240)
$buttonBrowseLog.Size = New-Object System.Drawing.Size(130, 26)
$form.Controls.Add($buttonBrowseLog)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 298)
$progressBar.Size = New-Object System.Drawing.Size(700, 22)
$script:progressBar = $progressBar
$form.Controls.Add($progressBar)

$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Text = 'Ready.'
$labelStatus.Location = New-Object System.Drawing.Point(20, 328)
$labelStatus.Size = New-Object System.Drawing.Size(700, 22)
$script:labelStatus = $labelStatus
$form.Controls.Add($labelStatus)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Location = New-Object System.Drawing.Point(420, 370)
$buttonStart.Size = New-Object System.Drawing.Size(140, 32)
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Location = New-Object System.Drawing.Point(580, 370)
$buttonClose.Size = New-Object System.Drawing.Size(140, 32)
$form.Controls.Add($buttonClose)

$toggleInputs = {
    $isLive = $checkUseLive.Checked
    $dateEnabled = $checkDateRange.Checked
    $textEvtx.Enabled = (-not $isLive)
    $buttonBrowseEvtx.Enabled = (-not $isLive)
    $checkIncludeSubfolders.Enabled = (-not $isLive)
    $dateFrom.Enabled = $dateEnabled
    $dateTo.Enabled = $dateEnabled
}

$checkUseLive.Add_CheckedChanged($toggleInputs)
$checkDateRange.Add_CheckedChanged($toggleInputs)
try {
    $initialResolvedFolder = Resolve-EventChannelFolder -ChannelName $script:liveChannelName
    if (-not [string]::IsNullOrWhiteSpace($initialResolvedFolder)) {
        $textEvtx.Text = $initialResolvedFolder
        Write-Log ("Initial Security channel EVTX folder resolved: {0}" -f $initialResolvedFolder)
    }
} catch {
    Write-Log -Level WARNING -Message ("Initial EVTX folder resolve failed: {0}" -f $_.Exception.Message)
}
& $toggleInputs

$buttonBrowseEvtx.Add_Click({
    $selected = Select-FolderPath -Description 'Select a folder containing Security .evtx files'
    if ($selected) { $textEvtx.Text = $selected }
})

$buttonBrowseOutput.Add_Click({
    $selected = Select-FolderPath -Description 'Select an output folder'
    if ($selected) { $textOutput.Text = $selected }
})

$buttonBrowseLog.Add_Click({
    $selected = Select-FolderPath -Description 'Select a log folder'
    if ($selected) {
        $textLog.Text = $selected
        $script:logDir = $selected
        Ensure-Directory -Path $script:logDir
        $script:logPath = Join-Path $script:logDir ($scriptName + '.log')
    }
})

$buttonResolve.Add_Click({
    try {
        Set-Status -Text 'Resolving Security channel...' -Progress 15
        $resolvedFolder = Resolve-EventChannelFolder -ChannelName $script:liveChannelName
        if (-not [string]::IsNullOrWhiteSpace($resolvedFolder)) {
            $textEvtx.Text = $resolvedFolder
            Write-Log ("Security channel EVTX folder resolved: {0}" -f $resolvedFolder)
        }

        $snapshot = Export-LiveChannelSnapshot -ChannelName $script:liveChannelName
        if (Test-Path -LiteralPath $snapshot) {
            Write-Log 'Live Security channel probe completed successfully.'
            $message = if (-not [string]::IsNullOrWhiteSpace($resolvedFolder)) {
                "Security channel resolved successfully.`n`nEVTX folder:`n$resolvedFolder`n`nSnapshot export test succeeded."
            } else {
                'Security channel snapshot export succeeded, but the configured EVTX folder could not be resolved from wevtutil.'
            }
            Show-UiMessage -Message $message -Title 'Resolve Channel'
        }
        if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot -Force -ErrorAction SilentlyContinue }
        Set-Status -Text 'Ready.' -Progress 0
    } catch {
        Write-Log -Level ERROR -Message ("Resolve Channel failed: {0}" -f $_.Exception.Message)
        Show-UiMessage -Message $_.Exception.Message -Title 'Resolve Channel Error' -Icon Error
        Set-Status -Text 'Resolve Channel failed.' -Progress 0
    }
})

$buttonStart.Add_Click({
    try {
        Write-Log 'Starting object deletion analysis.'
        $users = @($textUsers.Text -split '[,;
]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $evtxFolder = $textEvtx.Text.Trim()
        if (-not $checkUseLive.Checked -and [string]::IsNullOrWhiteSpace($evtxFolder)) {
            $resolvedFolder = Resolve-EventChannelFolder -ChannelName $script:liveChannelName
            if (-not [string]::IsNullOrWhiteSpace($resolvedFolder)) {
                $evtxFolder = $resolvedFolder
                $textEvtx.Text = $resolvedFolder
                Write-Log ("EVTX folder was empty; resolved Security channel folder automatically: {0}" -f $resolvedFolder)
            }
        }
        if (-not $checkUseLive.Checked -and [string]::IsNullOrWhiteSpace($evtxFolder)) {
            Show-UiMessage -Message "Please select an EVTX folder or enable 'Use live Security channel'." -Title 'Input Validation' -Icon Warning
            Set-Status -Text 'EVTX folder required for archive mode.' -Progress 0
            return
        }
        Start-DeletionAnalysis -UseLiveLog $checkUseLive.Checked -EvtxFolder $evtxFolder -IncludeSubfolders $checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts $users -UseDateRange $checkDateRange.Checked -FromTime $dateFrom.Value -ToTime $dateTo.Value
    } catch {
        Write-Log -Level ERROR -Message ("Error processing Event ID 4663: {0}" -f $_.Exception.Message)
        Show-UiMessage -Message $_.Exception.Message -Title 'Processing Error' -Icon Error
        Set-Status -Text 'Processing failed.' -Progress 0
    }
})

$buttonClose.Add_Click({ $form.Close() })

[void]$form.ShowDialog()

# End of Script
