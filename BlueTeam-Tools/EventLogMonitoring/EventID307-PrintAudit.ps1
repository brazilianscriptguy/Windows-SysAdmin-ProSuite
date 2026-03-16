#requires -Version 5.1
<#!
.SYNOPSIS
    PowerShell Script for Auditing Print Activities via Event ID 307 using Log Parser.
.DESCRIPTION
    Uses installed Log Parser 2.2 for both live SYSTEM event log reads and archived EVTX files.
    This revision uses the older working Log Parser COM automation path and keeps CSV export defaulted to My Documents on WS2019.
.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy
.VERSION
    03-16-2026 - 3.2.0 - WS2019 snapshot-based live parsing and count-safe archived EVTX processing
#>

[CmdletBinding()]
param(
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

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:ScriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:MachineName = [Environment]::MachineName
$script:LogDir = 'C:\Logs-TEMP'
$script:DefaultOutputDir = [Environment]::GetFolderPath('MyDocuments')
$script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
$script:LiveChannelName = 'Microsoft-Windows-PrintService/Operational'
$script:LogParserExeCandidates = @(
    'C:\Program Files (x86)\Log Parser 2.2\LogParser.exe',
    'C:\Program Files\Log Parser 2.2\LogParser.exe'
)

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-Log {
    param([Parameter(Mandatory)][string]$Message,[ValidateSet('INFO','WARN','ERROR')][string]$Level='INFO')
    try {
        Ensure-Directory -Path $script:LogDir
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -FilePath $script:LogPath -Append -Encoding utf8
    }
    catch {}
}

function Show-MessageBox {
    param([string]$Message,[string]$Title,[System.Windows.Forms.MessageBoxButtons]$Buttons='OK',[System.Windows.Forms.MessageBoxIcon]$Icon='Information')
    [void][System.Windows.Forms.MessageBox]::Show($Message,$Title,$Buttons,$Icon)
}

function Set-Status {
    param([string]$Text)
    if ($script:statusLabel) { $script:statusLabel.Text = $Text }
    if ($script:form) { $script:form.Refresh() }
}

function Update-ProgressSafe {
    param([int]$Value)
    if ($script:progressBar) { $script:progressBar.Value = [Math]::Max(0,[Math]::Min(100,$Value)) }
    if ($script:form) { $script:form.Refresh() }
}

function Select-Folder {
    param([string]$Description='Select a folder')
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
        return $null
    }
    finally { $dialog.Dispose() }
}

function Get-LogParserExePath {
    foreach ($candidate in $script:LogParserExeCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Escape-LogParserPath {
    param([string]$Path)
    return ($Path -replace "'","''")
}

function New-LogParserComObjects {
    try {
        $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
        $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
        $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        [pscustomobject]@{
            LogQuery     = $logQuery
            InputFormat  = $inputFormat
            OutputFormat = $outputFormat
        }
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed correctly. $($_.Exception.Message)"
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

function New-EmptyPrintAuditCsv {
    param([Parameter(Mandatory)][string]$Path)

    @(
        'EventTime,UserId,Workstation,PrinterUsed,ByteSize,PagesPrinted'
    ) | Set-Content -LiteralPath $Path -Encoding UTF8
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
    return $DestinationPath
}

function Merge-TempCsvIntoFinal {
    param(
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][bool]$IsFirstFile
    )

    if (-not (Test-Path -LiteralPath $TempCsvPath -PathType Leaf)) { return $false }
    $lines = @(Get-Content -LiteralPath $TempCsvPath -ErrorAction Stop)
    if ($lines.Count -eq 0) {
        Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    if ($IsFirstFile) {
        $lines | Set-Content -LiteralPath $FinalCsvPath -Encoding UTF8
    }
    else {
        @($lines | Select-Object -Skip 1) | Add-Content -LiteralPath $FinalCsvPath -Encoding UTF8
    }
    Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
    return $true
}

function Invoke-ArchivedEvtxCollection {
    param(
        [Parameter(Mandatory)][object[]]$EvtxFiles,
        [Parameter(Mandatory)]$LogQuery,
        [Parameter(Mandatory)]$InputFormat,
        [Parameter(Mandatory)]$OutputFormat,
        [Parameter(Mandatory)][string]$FinalCsvPath,
        [Parameter(Mandatory)][string]$TempCsvPath,
        [string]$StatusPrefix = 'Processing archived EVTX'
    )

    $fileCount = @($EvtxFiles).Count
    if ($fileCount -eq 0) {
        New-EmptyPrintAuditCsv -Path $FinalCsvPath
        return 0
    }

    $first = $true
    for ($i = 0; $i -lt $fileCount; $i++) {
        $file = $EvtxFiles[$i]
        $pct = 10 + [int](((($i + 1) / [double]$fileCount) * 70))
        Update-ProgressSafe $pct
        Set-Status ("{0} {1} of {2}: {3}" -f $StatusPrefix, ($i + 1), $fileCount, $file.Name)

        if (Test-Path -LiteralPath $TempCsvPath) {
            Remove-Item -LiteralPath $TempCsvPath -Force -ErrorAction SilentlyContinue
        }

        $query = @"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 2, '|') AS UserId,
    EXTRACT_TOKEN(Strings, 3, '|') AS Workstation,
    EXTRACT_TOKEN(Strings, 4, '|') AS PrinterUsed,
    EXTRACT_TOKEN(Strings, 6, '|') AS ByteSize,
    EXTRACT_TOKEN(Strings, 7, '|') AS PagesPrinted
INTO '$([string](Escape-LogParserPath $TempCsvPath))'
FROM '$([string](Escape-LogParserPath $file.FullName))'
WHERE EventID = 307
"@
        $result = Invoke-LogParserBatch -Query $query -LogQuery $LogQuery -InputFormat $InputFormat -OutputFormat $OutputFormat
        Write-Log "Archived EVTX query result for '$($file.FullName)': $result"

        $merged = Merge-TempCsvIntoFinal -TempCsvPath $TempCsvPath -FinalCsvPath $FinalCsvPath -IsFirstFile:$first
        if ($merged) {
            $first = $false
        }
        else {
            Write-Log "No Event ID 307 rows were exported from '$($file.FullName)'."
        }
    }

    if (-not (Test-Path -LiteralPath $FinalCsvPath -PathType Leaf)) {
        New-EmptyPrintAuditCsv -Path $FinalCsvPath
    }

    return @((Import-Csv -LiteralPath $FinalCsvPath -ErrorAction SilentlyContinue)).Count
}

function Test-LivePrintChannel {
    $probeCsv = $null
    $probeEvtx = $null
    try {
        $objects = New-LogParserComObjects
        $probeEvtx = Join-Path $env:TEMP ("PrintAudit307_probe_{0}.evtx" -f ([guid]::NewGuid().ToString('N')))
        $probeCsv = Join-Path $env:TEMP ("PrintAudit307_probe_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

        Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $probeEvtx | Out-Null

        $probeQuery = @"
SELECT TOP 1
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 4, '|') AS PrinterUsed
INTO '$([string](Escape-LogParserPath $probeCsv))'
FROM '$([string](Escape-LogParserPath $probeEvtx))'
WHERE EventID = 307
"@
        $null = Invoke-LogParserBatch -Query $probeQuery -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat
        if (Test-Path -LiteralPath $probeCsv) {
            Write-Log 'Live channel snapshot export and Log Parser probe completed successfully.'
        }
        else {
            Write-Log 'Live channel snapshot export succeeded. No Event ID 307 sample row was exported during the probe.'
        }
        return $true
    }
    catch {
        throw "Live channel probe failed. $($_.Exception.Message)"
    }
    finally {
        if ($probeCsv -and (Test-Path -LiteralPath $probeCsv)) { Remove-Item -LiteralPath $probeCsv -Force -ErrorAction SilentlyContinue }
        if ($probeEvtx -and (Test-Path -LiteralPath $probeEvtx)) { Remove-Item -LiteralPath $probeEvtx -Force -ErrorAction SilentlyContinue }
    }
}

function Process-PrintServiceLog {
    [CmdletBinding()]
    param(
        [string]$LogFolderPath,
        [Parameter(Mandatory)][string]$OutputFolder,
        [Parameter(Mandatory)][bool]$UseLiveLog,
        [Parameter(Mandatory)][bool]$IncludeSubfolders
    )

    $tempCsvPath = $null
    $snapshotEvtxPath = $null
    try {
        if ([string]::IsNullOrWhiteSpace($OutputFolder)) {
            $OutputFolder = [Environment]::GetFolderPath('MyDocuments')
        }
        Ensure-Directory -Path $OutputFolder

        $logParserExe = Get-LogParserExePath
        if ($logParserExe) {
            Write-Log "Using Log Parser executable: '$logParserExe'"
        }
        else {
            Write-Log "LogParser.exe path was not found, but COM automation will be used."
        }

        $objects = New-LogParserComObjects
        Write-Log "Starting Event ID 307 processing. UseLiveLog=$UseLiveLog; Folder='$LogFolderPath'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$OutputFolder'"

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $csvPath = Join-Path $OutputFolder ("{0}-PrintAudit-{1}.csv" -f $script:MachineName, $timestamp)
        $tempCsvPath = Join-Path $env:TEMP ("PrintAudit307_{0}.csv" -f ([guid]::NewGuid().ToString('N')))

        if ($UseLiveLog) {
            Update-ProgressSafe 10
            Set-Status 'Exporting live PrintService Operational snapshot...'
            $snapshotEvtxPath = Join-Path $env:TEMP ("PrintAudit307_live_{0}.evtx" -f ([guid]::NewGuid().ToString('N')))
            Export-LiveChannelSnapshot -ChannelName $script:LiveChannelName -DestinationPath $snapshotEvtxPath | Out-Null
            Write-Log "Live channel snapshot exported to '$snapshotEvtxPath'."

            Set-Status 'Parsing exported live snapshot with Log Parser...'
            $rows = Invoke-ArchivedEvtxCollection -EvtxFiles @([System.IO.FileInfo](Get-Item -LiteralPath $snapshotEvtxPath -ErrorAction Stop)) -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $tempCsvPath -StatusPrefix 'Processing live snapshot'
            if ($rows -eq 0) {
                Write-Log 'Live snapshot query returned no Event ID 307 rows. CSV was created with headers only.'
            }
            else {
                Write-Log 'Live snapshot query completed successfully.'
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($LogFolderPath) -or -not (Test-Path -LiteralPath $LogFolderPath -PathType Container)) {
                throw "Invalid EVTX folder path: '$LogFolderPath'"
            }

            $evtxFiles = if ($IncludeSubfolders) {
                @(Get-ChildItem -LiteralPath $LogFolderPath -Filter '*.evtx' -Recurse -ErrorAction Stop | Where-Object { -not $_.PSIsContainer })
            }
            else {
                @(Get-ChildItem -LiteralPath $LogFolderPath -Filter '*.evtx' -ErrorAction Stop | Where-Object { -not $_.PSIsContainer })
            }
            if (@($evtxFiles).Count -eq 0) {
                throw "No .evtx files were found in '$LogFolderPath'."
            }

            $rows = Invoke-ArchivedEvtxCollection -EvtxFiles @($evtxFiles) -LogQuery $objects.LogQuery -InputFormat $objects.InputFormat -OutputFormat $objects.OutputFormat -FinalCsvPath $csvPath -TempCsvPath $tempCsvPath
        }

        Update-ProgressSafe 85
        Set-Status 'Finalizing report...'
        $count = if (Test-Path -LiteralPath $csvPath) { @((Import-Csv -LiteralPath $csvPath -ErrorAction Stop)).Count } else { 0 }
        Write-Log "Found $count print events. Report exported to '$csvPath'"
        Update-ProgressSafe 100
        Set-Status "Completed. Found $count print events. Report saved to '$csvPath'"
        Show-MessageBox -Message "Found $count print events.`r`nReport exported to:`r`n$csvPath" -Title 'Success'
        if ($AutoOpen -and (Test-Path -LiteralPath $csvPath)) { Start-Process -FilePath $csvPath }
    }
    catch {
        $msg = "Error processing Event ID 307: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Set-Status 'Error occurred. Check log for details.'
        Show-MessageBox -Message $msg -Title 'Error' -Icon Error
    }
    finally {
        Update-ProgressSafe 0
        if ($tempCsvPath -and (Test-Path -LiteralPath $tempCsvPath)) { Remove-Item -LiteralPath $tempCsvPath -Force -ErrorAction SilentlyContinue }
        if ($snapshotEvtxPath -and (Test-Path -LiteralPath $snapshotEvtxPath)) { Remove-Item -LiteralPath $snapshotEvtxPath -Force -ErrorAction SilentlyContinue }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Print Audit Event Parser (Event ID 307) v3.2.0'
$form.Size = New-Object System.Drawing.Size(900,520)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$labelLogDir = New-Object System.Windows.Forms.Label
$labelLogDir.Location = New-Object System.Drawing.Point(20,20)
$labelLogDir.Size = New-Object System.Drawing.Size(120,24)
$labelLogDir.Text = 'Log Directory:'
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox
$textBoxLogDir.Location = New-Object System.Drawing.Point(185,18)
$textBoxLogDir.Size = New-Object System.Drawing.Size(550,24)
$textBoxLogDir.Text = $script:LogDir
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button
$buttonBrowseLogDir.Location = New-Object System.Drawing.Point(750,16)
$buttonBrowseLogDir.Size = New-Object System.Drawing.Size(100,28)
$buttonBrowseLogDir.Text = 'Browse'
$buttonBrowseLogDir.Add_Click({ $folder = Select-Folder -Description 'Select the log directory'; if ($folder) { $textBoxLogDir.Text = $folder } })
$form.Controls.Add($buttonBrowseLogDir)

$labelOutputDir = New-Object System.Windows.Forms.Label
$labelOutputDir.Location = New-Object System.Drawing.Point(20,60)
$labelOutputDir.Size = New-Object System.Drawing.Size(120,24)
$labelOutputDir.Text = 'Output Folder:'
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox
$textBoxOutputDir.Location = New-Object System.Drawing.Point(185,58)
$textBoxOutputDir.Size = New-Object System.Drawing.Size(550,24)
$textBoxOutputDir.Text = $script:DefaultOutputDir
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button
$buttonBrowseOutputDir.Location = New-Object System.Drawing.Point(750,56)
$buttonBrowseOutputDir.Size = New-Object System.Drawing.Size(100,28)
$buttonBrowseOutputDir.Text = 'Browse'
$buttonBrowseOutputDir.Add_Click({ $folder = Select-Folder -Description 'Select the output folder'; if ($folder) { $textBoxOutputDir.Text = $folder } })
$form.Controls.Add($buttonBrowseOutputDir)

$checkBoxLiveLog = New-Object System.Windows.Forms.CheckBox
$checkBoxLiveLog.Location = New-Object System.Drawing.Point(20,100)
$checkBoxLiveLog.Size = New-Object System.Drawing.Size(310,24)
$checkBoxLiveLog.Text = 'Use live PrintService Operational channel'
$checkBoxLiveLog.Checked = $true
$form.Controls.Add($checkBoxLiveLog)

$buttonResolveChannel = New-Object System.Windows.Forms.Button
$buttonResolveChannel.Location = New-Object System.Drawing.Point(590,96)
$buttonResolveChannel.Size = New-Object System.Drawing.Size(145,30)
$buttonResolveChannel.Text = 'Resolve Channel'
$buttonResolveChannel.Add_Click({
    try {
        $script:LogDir = $textBoxLogDir.Text
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        $logParserExe = Get-LogParserExePath
        Set-Status 'Testing live PrintService channel export and Log Parser access...'
        Update-ProgressSafe 15
        $null = Test-LivePrintChannel
        Update-ProgressSafe 0
        Set-Status 'Live channel export and Log Parser validation completed successfully.'
        Show-MessageBox -Message "The live channel can be exported successfully and parsed with Log Parser.`r`n`r`nChannel:`r`n$($script:LiveChannelName)`r`n`r`nLive mode will use a temporary EVTX snapshot to avoid lock issues on Windows Server 2019." -Title 'Resolve Channel'
    }
    catch {
        Update-ProgressSafe 0
        $msg = "Resolve Channel failed: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Set-Status 'Resolve Channel failed.'
        Show-MessageBox -Message $msg -Title 'Resolve Channel' -Icon Error
    }
})
$form.Controls.Add($buttonResolveChannel)

$labelBrowse = New-Object System.Windows.Forms.Label
$labelBrowse.Location = New-Object System.Drawing.Point(20,145)
$labelBrowse.Size = New-Object System.Drawing.Size(120,24)
$labelBrowse.Text = 'EVTX Folder:'
$form.Controls.Add($labelBrowse)

$textBoxEvtxFolder = New-Object System.Windows.Forms.TextBox
$textBoxEvtxFolder.Location = New-Object System.Drawing.Point(185,143)
$textBoxEvtxFolder.Size = New-Object System.Drawing.Size(550,24)
$textBoxEvtxFolder.Text = ''
$textBoxEvtxFolder.Enabled = $false
$form.Controls.Add($textBoxEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(750,141)
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(100,28)
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Enabled = $false
$buttonBrowseEvtx.Add_Click({ $folder = Select-Folder -Description 'Select the folder containing archived EVTX files'; if ($folder) { $textBoxEvtxFolder.Text = $folder } })
$form.Controls.Add($buttonBrowseEvtx)

$checkBoxIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkBoxIncludeSubfolders.Location = New-Object System.Drawing.Point(185,176)
$checkBoxIncludeSubfolders.Size = New-Object System.Drawing.Size(320,24)
$checkBoxIncludeSubfolders.Text = 'Include subfolders for archived EVTX scan'
$checkBoxIncludeSubfolders.Checked = $true
$checkBoxIncludeSubfolders.Enabled = $false
$form.Controls.Add($checkBoxIncludeSubfolders)

$checkBoxLiveLog.Add_CheckedChanged({
    $useLive = $checkBoxLiveLog.Checked
    $textBoxEvtxFolder.Enabled = -not $useLive
    $buttonBrowseEvtx.Enabled = -not $useLive
    $checkBoxIncludeSubfolders.Enabled = -not $useLive
    if ($useLive) {
        Set-Status 'Ready (Live Mode via temporary EVTX snapshot + Log Parser)'
    }
    else {
        Set-Status 'Ready (Archived EVTX Mode via Log Parser file input)'
    }
})

$labelCompatibility = New-Object System.Windows.Forms.Label
$labelCompatibility.Location = New-Object System.Drawing.Point(20,215)
$labelCompatibility.Size = New-Object System.Drawing.Size(830,46)
$labelCompatibility.Text = 'WS2019 fix: live mode now exports a temporary snapshot of the PrintService Operational channel and parses that EVTX snapshot with Log Parser. This avoids live channel locking and preserves the installed Log Parser parsing path.'
$form.Controls.Add($labelCompatibility)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20,275)
$statusLabel.Size = New-Object System.Drawing.Size(830,24)
$statusLabel.Text = 'Ready (Live Mode via temporary EVTX snapshot + Log Parser)'
$form.Controls.Add($statusLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20,320)
$progressBar.Size = New-Object System.Drawing.Size(830,28)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)

$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Location = New-Object System.Drawing.Point(635,395)
$buttonStartAnalysis.Size = New-Object System.Drawing.Size(105,34)
$buttonStartAnalysis.Text = 'Start Analysis'
$buttonStartAnalysis.Add_Click({
    $script:LogDir = $textBoxLogDir.Text
    $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
    $outputFolder = $textBoxOutputDir.Text
    $evtxFolder = $textBoxEvtxFolder.Text
    $useLive = $checkBoxLiveLog.Checked
    $includeSubfolders = $checkBoxIncludeSubfolders.Checked

    try {
        Ensure-Directory -Path $script:LogDir
        if (-not $useLive -and [string]::IsNullOrWhiteSpace($evtxFolder)) {
            Show-MessageBox -Message 'Please select an EVTX folder or enable live mode.' -Title 'Input Required' -Icon Warning
            return
        }
        Write-Log 'Starting print audit analysis.'
        Process-PrintServiceLog -LogFolderPath $evtxFolder -OutputFolder $outputFolder -UseLiveLog $useLive -IncludeSubfolders $includeSubfolders
    }
    catch {
        $msg = "Unexpected error starting analysis: $($_.Exception.Message)"
        Write-Log $msg 'ERROR'
        Show-MessageBox -Message $msg -Title 'Start Analysis' -Icon Error
    }
})
$form.Controls.Add($buttonStartAnalysis)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Location = New-Object System.Drawing.Point(745,395)
$buttonClose.Size = New-Object System.Drawing.Size(105,34)
$buttonClose.Text = 'Close'
$buttonClose.Add_Click({ $form.Close() })
$form.Controls.Add($buttonClose)

$script:form = $form
$script:progressBar = $progressBar
$script:statusLabel = $statusLabel

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# End of script
