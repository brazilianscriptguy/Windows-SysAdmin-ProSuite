#requires -Version 5.1
<#
.SYNOPSIS
    Tracks AD user logon (4624) and logoff (4634) events from the live Security log or archived Security EVTX files using Log Parser 2.2.

.DESCRIPTION
    Revised for Windows Server 2019 / PowerShell 5.1, following the working Print Audit architecture:
      - Live log handling through wevtutil snapshot export
      - Archived EVTX parsing through Log Parser COM
      - Count-safe file enumeration
      - Default CSV export path = My Documents
      - Single per-run log file in C:\Logs-TEMP
      - GUI-based execution with stable bottom-aligned actions

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    03-16-2026 - 2.0.0-WS2019-RevA
#>

[CmdletBinding()]
param(
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
#endregion

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
}
catch {
    Write-Error "Failed to load System.Windows.Forms/System.Drawing. $($_.Exception.Message)"
    exit 1
}

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Security'
$script:ProgressBar = $null
$script:StatusLabel = $null
$script:Form = $null

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    try {
        Ensure-Directory -Path $script:LogDir
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -LiteralPath $script:LogPath -Append -Encoding UTF8
    }
    catch {}
}

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Set-Status {
    param([Parameter(Mandatory)][string]$Text)
    if ($script:StatusLabel) { $script:StatusLabel.Text = $Text }
    if ($script:Form) { $script:Form.Refresh() }
}

function Update-ProgressSafe {
    param([Parameter(Mandatory)][int]$Value)
    if ($script:ProgressBar) {
        $script:ProgressBar.Value = [Math]::Max(0, [Math]::Min(100, $Value))
    }
    if ($script:Form) { $script:Form.Refresh() }
}

function Select-Folder {
    param(
        [string]$Description = 'Select a folder',
        [bool]$ShowNewFolderButton = $true
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $ShowNewFolderButton
    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return $null
    }
    finally {
        $dialog.Dispose()
    }
}

function Test-LogParserAvailability {
    try {
        $null = New-Object -ComObject 'MSUtil.LogQuery'
        return $true
    }
    catch {
        return $false
    }
}

function New-LogParserComObjects {
    try {
        [pscustomobject]@{
            LogQuery     = (New-Object -ComObject 'MSUtil.LogQuery')
            InputFormat  = (New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat')
            OutputFormat = (New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat')
        }
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed. $($_.Exception.Message)"
    }
}

function Invoke-LogParserBatch {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)]$LogQuery,
        [Parameter(Mandatory)]$InputFormat,
        [Parameter(Mandatory)]$OutputFormat
    )
    try {
        $result = $LogQuery.ExecuteBatch($Query, $InputFormat, $OutputFormat)
        Write-Log ("Log Parser ExecuteBatch returned: {0}" -f $result)
        return $result
    }
    catch {
        throw "Log Parser ExecuteBatch failed. $($_.Exception.Message)"
    }
}

function Export-LiveChannelSnapshot {
    param(
        [Parameter(Mandatory)][string]$ChannelName,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $wevtutil = Join-Path $env:SystemRoot 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) {
        throw "wevtutil.exe was not found at '$wevtutil'."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $quotedChannel = '"' + ($ChannelName -replace '"','\"') + '"'
    $quotedDestination = '"' + ($DestinationPath -replace '"','\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdOut = $proc.StandardOutput.ReadToEnd()
    $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($proc.ExitCode). StdOut=$stdOut StdErr=$stdErr"
    }
    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "wevtutil reported success, but the snapshot file was not created at '$DestinationPath'."
    }

    Write-Log ("Live channel snapshot exported: '{0}' -> '{1}'" -f $ChannelName, $DestinationPath)
    return $DestinationPath
}

function Get-SafeUserListForSqlInClause {
    param([Parameter(Mandatory)][string[]]$UserAccounts)

    $cleanUsers = New-Object System.Collections.Generic.List[string]
    foreach ($user in $UserAccounts) {
        $value = ([string]$user).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $value = $value -replace "[';]", ''
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$cleanUsers.Add($value)
        }
    }

    if ($cleanUsers.Count -eq 0) {
        throw 'No valid user accounts were provided after sanitization.'
    }

    return (($cleanUsers | ForEach-Object { "'{0}'" -f $_ }) -join ';')
}

function New-EmptyAuditCsv {
    param([Parameter(Mandatory)][string]$Path)
    @(
        'EventType,EventTime,UserAccount,DomainName,LogonType,SourceIP,ComputerName,SourceFile'
    ) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Merge-TempCsvIntoFinal {
    param(
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][ref]$WroteHeader
    )

    if (-not (Test-Path -LiteralPath $TempCsvPath -PathType Leaf)) {
        return $false
    }

    $lines = @(Get-Content -LiteralPath $TempCsvPath -ErrorAction Stop)
    if (@($lines).Count -le 1) {
        return $false
    }

    if (-not $WroteHeader.Value) {
        $lines | Set-Content -LiteralPath $FinalCsvPath -Encoding UTF8
        $WroteHeader.Value = $true
    }
    else {
        @($lines | Select-Object -Skip 1) | Add-Content -LiteralPath $FinalCsvPath -Encoding UTF8
    }

    return $true
}

function Get-CsvDataRowCountFast {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }

    $lineCount = 0
    foreach ($chunk in Get-Content -LiteralPath $Path -ReadCount 2000 -ErrorAction Stop) {
        $lineCount += @($chunk).Length
    }
    return [Math]::Max(0, $lineCount - 1)
}

function Get-Query4624 {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$UserInClause
    )

@"
SELECT
  'Logon' AS EventType,
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 5, '|')  AS UserAccount,
  EXTRACT_TOKEN(Strings, 6, '|')  AS DomainName,
  EXTRACT_TOKEN(Strings, 8, '|')  AS LogonType,
  EXTRACT_TOKEN(Strings, 18, '|') AS SourceIP,
  ComputerName AS ComputerName,
  '$($EvtxPath -replace "'","''")' AS SourceFile
INTO '$($TempCsvPath -replace "'","''")'
FROM '$($EvtxPath -replace "'","''")'
WHERE EventID = 4624
  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($UserInClause)
"@
}

function Get-Query4634 {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$UserInClause
    )

@"
SELECT
  'Logoff' AS EventType,
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
  EXTRACT_TOKEN(Strings, 6, '|') AS DomainName,
  EXTRACT_TOKEN(Strings, 8, '|') AS LogonType,
  '-' AS SourceIP,
  ComputerName AS ComputerName,
  '$($EvtxPath -replace "'","''")' AS SourceFile
INTO '$($TempCsvPath -replace "'","''")'
FROM '$($EvtxPath -replace "'","''")'
WHERE EventID = 4634
  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($UserInClause)
"@
}

function Invoke-EvtxQueryPair {
    param(
        [Parameter(Mandatory)][string]$EvtxPath,
        [Parameter(Mandatory)]$LogQuery,
        [Parameter(Mandatory)]$InputFormat,
        [Parameter(Mandatory)]$OutputFormat,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][string]$UserInClause,
        [Parameter(Mandatory)][ref]$WroteHeader
    )

    $temp4624 = Join-Path $env:TEMP ("4624_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
    $temp4634 = Join-Path $env:TEMP ("4634_{0}.csv" -f ([guid]::NewGuid().ToString('N')))
    $appendedAny = $false

    try {
        $sql4624 = Get-Query4624 -EvtxPath $EvtxPath -TempCsvPath $temp4624 -UserInClause $UserInClause
        $sql4634 = Get-Query4634 -EvtxPath $EvtxPath -TempCsvPath $temp4634 -UserInClause $UserInClause

        [void](Invoke-LogParserBatch -Query $sql4624 -LogQuery $LogQuery -InputFormat $InputFormat -OutputFormat $OutputFormat)
        [void](Invoke-LogParserBatch -Query $sql4634 -LogQuery $LogQuery -InputFormat $InputFormat -OutputFormat $OutputFormat)

        if (Merge-TempCsvIntoFinal -TempCsvPath $temp4624 -FinalCsvPath $FinalCsvPath -WroteHeader ([ref]$WroteHeader.Value)) {
            $appendedAny = $true
        }
        if (Merge-TempCsvIntoFinal -TempCsvPath $temp4634 -FinalCsvPath $FinalCsvPath -WroteHeader ([ref]$WroteHeader.Value)) {
            $appendedAny = $true
        }

        return $appendedAny
    }
    finally {
        if (Test-Path -LiteralPath $temp4624) { Remove-Item -LiteralPath $temp4624 -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $temp4634) { Remove-Item -LiteralPath $temp4634 -Force -ErrorAction SilentlyContinue }
    }
}

function Get-EvtxFilesSafe {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [bool]$IncludeSubfolders = $true
    )

    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        throw "EVTX folder does not exist: '$FolderPath'"
    }

    if ($IncludeSubfolders) {
        return @(Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
    }
    return @(Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -ErrorAction Stop)
}

function Resolve-OutputFolder {
    param([string]$RequestedPath)

    $resolved = ([string]$RequestedPath).Trim()
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = $script:DefaultOutputDir
    }
    Ensure-Directory -Path $resolved
    return $resolved
}

function Start-LogonLogoffAnalysis {
    param(
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter(Mandatory)][string]$EvtxFolder,
        [Parameter(Mandatory)][bool]$IncludeSubfolders,
        [Parameter(Mandatory)][string]$OutputFolder,
        [Parameter(Mandatory)][string[]]$UserAccounts
    )

    Write-Log ("Starting Event ID 4624/4634 processing. UseLiveLog={0}; Folder='{1}'; IncludeSubfolders={2}; OutputFolder='{3}'; Users={4}" -f $UseLiveLog, $EvtxFolder, $IncludeSubfolders, $OutputFolder, ($UserAccounts -join ', '))

    $outputDir = Resolve-OutputFolder -RequestedPath $OutputFolder
    $userInClause = Get-SafeUserListForSqlInClause -UserAccounts $UserAccounts
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $outputDir ("{0}-ADUserLoginTracking-{1}.csv" -f $script:MachineName, $timestamp)

    $com = New-LogParserComObjects
    $logQuery = $com.LogQuery
    $inputFormat = $com.InputFormat
    $outputFormat = $com.OutputFormat

    $wroteHeader = $false
    $matchedSources = 0
    $failedSources = 0
    $tempSnapshot = $null

    try {
        if ($UseLiveLog) {
            Update-ProgressSafe 10
            Set-Status 'Exporting Security live snapshot...'

            $tempSnapshot = Join-Path $env:TEMP ("SecuritySnapshot_{0}.evtx" -f ([guid]::NewGuid().ToString('N')))
            [void](Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $tempSnapshot)

            Update-ProgressSafe 55
            Set-Status 'Parsing Security snapshot with Log Parser...'

            if (Invoke-EvtxQueryPair -EvtxPath $tempSnapshot -LogQuery $logQuery -InputFormat $inputFormat -OutputFormat $outputFormat -FinalCsvPath $finalCsv -UserInClause $userInClause -WroteHeader ([ref]$wroteHeader)) {
                $matchedSources++
                Write-Log ("Live Security snapshot produced matching events: '{0}'" -f $tempSnapshot)
            }
            else {
                Write-Log 'Live Security snapshot produced no matching 4624/4634 events for the selected users.' 'WARN'
            }
        }
        else {
            $evtxFiles = Get-EvtxFilesSafe -FolderPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders
            $totalFiles = @($evtxFiles).Count
            if ($totalFiles -eq 0) {
                throw "No .evtx files were found in '$EvtxFolder'."
            }

            for ($i = 0; $i -lt $totalFiles; $i++) {
                $file = $evtxFiles[$i]
                $pct = 10 + [int]((($i + 1) / [double]$totalFiles) * 75)
                Update-ProgressSafe $pct
                Set-Status ("Processing EVTX {0} of {1}: {2}" -f ($i + 1), $totalFiles, $file.Name)

                try {
                    if (Invoke-EvtxQueryPair -EvtxPath $file.FullName -LogQuery $logQuery -InputFormat $inputFormat -OutputFormat $outputFormat -FinalCsvPath $finalCsv -UserInClause $userInClause -WroteHeader ([ref]$wroteHeader)) {
                        $matchedSources++
                        Write-Log ("Processed EVTX with matching events: '{0}'" -f $file.FullName)
                    }
                    else {
                        Write-Log ("No matching 4624/4634 events for selected users in: '{0}'" -f $file.FullName) 'WARN'
                    }
                }
                catch {
                    $failedSources++
                    Write-Log ("Failed processing EVTX '{0}': {1}" -f $file.FullName, $_.Exception.Message) 'ERROR'
                }
            }
        }

        if (-not $wroteHeader) {
            New-EmptyAuditCsv -Path $finalCsv
            Write-Log 'No matching events were found. Created an empty CSV with headers only.' 'WARN'
        }

        $eventCount = Get-CsvDataRowCountFast -Path $finalCsv
        Update-ProgressSafe 100
        Set-Status ("Completed. Found {0} events. Saved to: {1}" -f $eventCount, $finalCsv)
        Write-Log ("Completed. Events found: {0} | Matching sources: {1} | Failed sources: {2} | Report: '{3}'" -f $eventCount, $matchedSources, $failedSources, $finalCsv)

        if ($AutoOpen) {
            try { Start-Process -FilePath $finalCsv | Out-Null } catch {}
        }

        $summary = "Found $eventCount logon/logoff events.`nReport exported to:`n$finalCsv"
        if ($failedSources -gt 0) {
            $summary += "`n`nWarning: $failedSources source(s) failed. Check the log:`n$script:LogPath"
        }
        Show-MessageBox -Message $summary -Title 'Success' -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
    finally {
        if ($tempSnapshot -and (Test-Path -LiteralPath $tempSnapshot)) {
            Remove-Item -LiteralPath $tempSnapshot -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-LiveSecurityProbe {
    param([Parameter(Mandatory)][string[]]$UserAccounts)

    $tempSnapshot = $null
    $tempCsv = $null
    try {
        $com = New-LogParserComObjects
        $userInClause = Get-SafeUserListForSqlInClause -UserAccounts $UserAccounts
        $tempSnapshot = Join-Path $env:TEMP ("SecurityProbe_{0}.evtx" -f ([guid]::NewGuid().ToString('N')))
        $tempCsv = Join-Path $env:TEMP ("SecurityProbe_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

        [void](Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $tempSnapshot)

        $probeQuery = @"
SELECT TOP 1
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount
INTO '$($tempCsv -replace "'","''")'
FROM '$($tempSnapshot -replace "'","''")'
WHERE EventID IN (4624;4634)
  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userInClause)
"@

        [void](Invoke-LogParserBatch -Query $probeQuery -LogQuery $com.LogQuery -InputFormat $com.InputFormat -OutputFormat $com.OutputFormat)

        if (Test-Path -LiteralPath $tempCsv -PathType Leaf) {
            $rows = Get-CsvDataRowCountFast -Path $tempCsv
            if ($rows -gt 0) {
                Write-Log ("Live Security probe completed successfully with sample rows. Snapshot='{0}'" -f $tempSnapshot)
                return 'Live Security probe succeeded.'
            }
        }

        Write-Log 'Live Security probe completed without sample rows. Treating channel access as valid.' 'WARN'
        return 'Live Security probe completed. No sample rows matched the selected users.'
    }
    finally {
        if ($tempCsv -and (Test-Path -LiteralPath $tempCsv)) { Remove-Item -LiteralPath $tempCsv -Force -ErrorAction SilentlyContinue }
        if ($tempSnapshot -and (Test-Path -LiteralPath $tempSnapshot)) { Remove-Item -LiteralPath $tempSnapshot -Force -ErrorAction SilentlyContinue }
    }
}

#region GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'AD User Login Tracking (Event IDs 4624 & 4634)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 440)

$marginLeft = 16
$labelWidth = 140
$textWidth = 470
$buttonWidth = 100
$browseWidth = 100
$rowY = 18
$rowGap = 34

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelUsers.Text = 'User Accounts:'
$form.Controls.Add($labelUsers)

$textBoxUsers = New-Object System.Windows.Forms.TextBox
$textBoxUsers.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$textBoxUsers.Size = New-Object System.Drawing.Size(570, 72)
$textBoxUsers.Multiline = $true
$textBoxUsers.ScrollBars = 'Vertical'
$textBoxUsers.Text = 'user01, user02, user03'
$form.Controls.Add($textBoxUsers)

$rowY += 86
$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$checkUseLive.Size = New-Object System.Drawing.Size(320, 22)
$checkUseLive.Text = 'Use live Security log (snapshot via wevtutil)'
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Location = New-Object System.Drawing.Point(590, ($rowY - 2))
$buttonResolve.Size = New-Object System.Drawing.Size(120, 26)
$buttonResolve.Text = 'Resolve Channel'
$form.Controls.Add($buttonResolve)

$rowY += $rowGap
$labelEvtxFolder = New-Object System.Windows.Forms.Label
$labelEvtxFolder.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$labelEvtxFolder.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtxFolder.Text = 'EVTX Folder:'
$form.Controls.Add($labelEvtxFolder)

$textBoxEvtxFolder = New-Object System.Windows.Forms.TextBox
$textBoxEvtxFolder.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$textBoxEvtxFolder.Size = New-Object System.Drawing.Size($textWidth, 22)
$textBoxEvtxFolder.Text = ''
$form.Controls.Add($textBoxEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size($browseWidth, 24)
$buttonBrowseEvtx.Text = 'Browse'
$form.Controls.Add($buttonBrowseEvtx)

$rowY += $rowGap
$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$checkIncludeSubfolders.Size = New-Object System.Drawing.Size(180, 22)
$checkIncludeSubfolders.Text = 'Include subfolders'
$checkIncludeSubfolders.Checked = $true
$form.Controls.Add($checkIncludeSubfolders)

$rowY += $rowGap
$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelOutput.Text = 'Output Folder:'
$form.Controls.Add($labelOutput)

$textBoxOutput = New-Object System.Windows.Forms.TextBox
$textBoxOutput.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$textBoxOutput.Size = New-Object System.Drawing.Size($textWidth, 22)
$textBoxOutput.Text = $script:DefaultOutputDir
$form.Controls.Add($textBoxOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseOutput.Size = New-Object System.Drawing.Size($browseWidth, 24)
$buttonBrowseOutput.Text = 'Browse'
$form.Controls.Add($buttonBrowseOutput)

$rowY += $rowGap
$labelLogDir = New-Object System.Windows.Forms.Label
$labelLogDir.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$labelLogDir.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelLogDir.Text = 'Log Folder:'
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox
$textBoxLogDir.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $rowY)
$textBoxLogDir.Size = New-Object System.Drawing.Size($textWidth, 22)
$textBoxLogDir.Text = $script:LogDir
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Location = New-Object System.Drawing.Point(640, ($rowY - 1))
$buttonBrowseLog.Size = New-Object System.Drawing.Size($browseWidth, 24)
$buttonBrowseLog.Text = 'Browse'
$form.Controls.Add($buttonBrowseLog)

$rowY += 42
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$statusLabel.Size = New-Object System.Drawing.Size(724, 22)
$statusLabel.Text = 'Ready'
$form.Controls.Add($statusLabel)

$rowY += 26
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point($marginLeft, $rowY)
$progressBar.Size = New-Object System.Drawing.Size(724, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Location = New-Object System.Drawing.Point(16, 380)
$buttonStart.Size = New-Object System.Drawing.Size(130, 30)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Location = New-Object System.Drawing.Point(610, 380)
$buttonClose.Size = New-Object System.Drawing.Size(130, 30)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$script:ProgressBar = $progressBar
$script:StatusLabel = $statusLabel
$script:Form = $form

$toggleInputState = {
    $useLive = $checkUseLive.Checked
    $textBoxEvtxFolder.Enabled = -not $useLive
    $buttonBrowseEvtx.Enabled = -not $useLive
    $checkIncludeSubfolders.Enabled = -not $useLive
}
& $toggleInputState

$checkUseLive.Add_CheckedChanged({ & $toggleInputState })

$buttonBrowseEvtx.Add_Click({
    $folder = Select-Folder -Description 'Select the folder containing Security EVTX files' -ShowNewFolderButton:$false
    if ($folder) { $textBoxEvtxFolder.Text = $folder }
})

$buttonBrowseOutput.Add_Click({
    $folder = Select-Folder -Description 'Select a folder for CSV output' -ShowNewFolderButton:$true
    if ($folder) { $textBoxOutput.Text = $folder }
})

$buttonBrowseLog.Add_Click({
    $folder = Select-Folder -Description 'Select a folder for log files' -ShowNewFolderButton:$true
    if ($folder) { $textBoxLogDir.Text = $folder }
})

$buttonResolve.Add_Click({
    try {
        if (-not (Test-LogParserAvailability)) {
            throw 'Microsoft Log Parser 2.2 is not installed or MSUtil COM is not registered.'
        }

        $rawUsers = $textBoxUsers.Text
        $userAccounts = @($rawUsers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (@($userAccounts).Count -eq 0) {
            throw 'Please enter at least one user account before probing the live Security channel.'
        }

        $script:LogDir = $textBoxLogDir.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:LogDir)) { $script:LogDir = 'C:\Logs-TEMP' }
        Ensure-Directory -Path $script:LogDir
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')

        Set-Status 'Resolving live Security channel...'
        Update-ProgressSafe 10
        $message = Test-LiveSecurityProbe -UserAccounts $userAccounts
        Update-ProgressSafe 100
        Set-Status $message
        Show-MessageBox -Message $message -Title 'Resolve Channel' -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
    }
    catch {
        Write-Log ("Resolve Channel failed: {0}" -f $_.Exception.Message) 'ERROR'
        Update-ProgressSafe 0
        Set-Status 'Resolve Channel failed.'
        Show-MessageBox -Message ("Resolve Channel failed: {0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonStart.Add_Click({
    try {
        if (-not (Test-LogParserAvailability)) {
            throw 'Microsoft Log Parser 2.2 is not installed or MSUtil COM is not registered.'
        }

        $script:LogDir = $textBoxLogDir.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:LogDir)) {
            $script:LogDir = 'C:\Logs-TEMP'
        }
        Ensure-Directory -Path $script:LogDir
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')

        $rawUsers = $textBoxUsers.Text
        $userAccounts = @($rawUsers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (@($userAccounts).Count -eq 0) {
            throw 'Please enter at least one user account to track.'
        }

        $outputFolder = $textBoxOutput.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($outputFolder)) {
            $outputFolder = $script:DefaultOutputDir
            $textBoxOutput.Text = $outputFolder
        }

        Update-ProgressSafe 0
        Set-Status 'Starting analysis...'
        Write-Log 'Starting AD user login tracking analysis.'

        if ($checkUseLive.Checked) {
            Start-LogonLogoffAnalysis -UseLiveLog $true -EvtxFolder '' -IncludeSubfolders:$true -OutputFolder $outputFolder -UserAccounts $userAccounts
        }
        else {
            $evtxFolder = $textBoxEvtxFolder.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($evtxFolder)) {
                throw 'Please select the EVTX folder when live mode is disabled.'
            }
            Start-LogonLogoffAnalysis -UseLiveLog $false -EvtxFolder $evtxFolder -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $outputFolder -UserAccounts $userAccounts
        }
    }
    catch {
        Write-Log ("Fatal error in Start handler: {0}" -f $_.Exception.Message) 'ERROR'
        Update-ProgressSafe 0
        Set-Status 'Error occurred. Check the log.'
        Show-MessageBox -Message ("Error: {0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonClose.Add_Click({ $form.Close() })
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion

# End of script
