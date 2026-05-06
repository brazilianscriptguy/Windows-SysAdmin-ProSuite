<#
.SYNOPSIS
    PowerShell Script for tracking privileged access related events on Windows Server 2019.

.DESCRIPTION
    This revision follows the stable WS2019-compatible structure used in the latest working codebase:
    - PowerShell 5.1 safe runtime
    - Log Parser COM for EVTX parsing
    - wevtutil snapshot export for live log access
    - default CSV export to My Documents
    - count-safe enumeration and CSV merge logic

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    03-16-2026 - RevA - WS2019 migration
#>

[CmdletBinding()]
param(
    [switch]$ShowConsole,
    [bool]$AutoOpen = $true
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

if (-not $ShowConsole) {
    try {
        $hwnd = [Win32Console]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) { [void][Win32Console]::ShowWindow($hwnd, 0) }
    }
    catch {}
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

$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$domainServerName = $env:COMPUTERNAME
$defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir ($scriptName + '.log')
$securityChannel = 'Security'
$eventIds = '4720;4724;4728;4732;4735;4756;4672'

if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','ERROR','WARNING')][string]$Level = 'INFO'
    )
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8 } catch {}
}

function Show-Info([string]$m,[string]$t='Information') {
    [void][System.Windows.Forms.MessageBox]::Show($m,$t,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
}
function Show-ErrorBox([string]$m,[string]$t='Error') {
    [void][System.Windows.Forms.MessageBox]::Show($m,$t,[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
}

function Set-Status {
    param([string]$Text,[int]$Progress = -1)
    $script:labelStatus.Text = $Text
    if ($Progress -ge 0 -and $Progress -le 100) { $script:progressBar.Value = $Progress }
    $script:form.Refresh()
}

function Get-SafeOutputFolder {
    $candidate = $script:textOutputFolder.Text
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $defaultOutputFolder }
    return $candidate
}

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string]$Arguments
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
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
    $quotedChannel = '"' + ($ChannelName -replace '"','\"') + '"'
    $quotedDestination = '"' + ($DestinationPath -replace '"','\"') + '"'
    $args = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)
    $result = Invoke-ExternalProcess -FilePath $wevtutil -Arguments $args
    if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "Snapshot export failed. ExitCode=$($result.ExitCode). StdErr=$($result.StdErr)"
    }
    Write-Log "Live channel snapshot exported to '$DestinationPath'."
}

function New-HeaderOnlyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    Set-Content -LiteralPath $Path -Value ($Headers -join ',') -Encoding UTF8
}

function Get-UserFilterValues {
    $raw = $script:textUsers.Text
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $values = $raw -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($values)
}

function Invoke-LogParserQuery {
    param(
        [Parameter(Mandatory)][string]$SourceExpression,
        [Parameter(Mandatory)][string]$CsvPath,
        [string[]]$UserAccounts = @()
    )

    $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
    $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
    $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'

    $inputFormat.resolveSIDs = $true
    $outputFormat.quoteFields = $true
    $outputFormat.headers = $true
    $outputFormat.iTsFormat = 'CSV'

    $userClause = ''
    if (@($UserAccounts).Count -gt 0) {
        $escaped = @($UserAccounts | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" })
        $userClause = ' AND EXTRACT_TOKEN(Strings, 0, ''|'') IN ({0})' -f ($escaped -join ';')
    }

    $sqlQuery = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    EXTRACT_TOKEN(Strings, 0, '|') AS AccountName,
    EXTRACT_TOKEN(Strings, 1, '|') AS CallerUser,
    EXTRACT_TOKEN(Strings, 2, '|') AS Domain
INTO '$CsvPath'
FROM $SourceExpression
WHERE EventID IN ($eventIds)$userClause
"@

    $returnValue = $logQuery.ExecuteBatch($sqlQuery, $inputFormat, $outputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $returnValue"
    return [bool]$returnValue
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$TempCsvPaths,
        [Parameter(Mandatory)][string]$DestinationCsv
    )
    $existing = @($TempCsvPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if (@($existing).Count -eq 0) { return }

    $first = $true
    foreach ($csv in $existing) {
        if ($first) {
            Get-Content -LiteralPath $csv | Set-Content -LiteralPath $DestinationCsv -Encoding UTF8
            $first = $false
        }
        else {
            Get-Content -LiteralPath $csv | Select-Object -Skip 1 | Add-Content -LiteralPath $DestinationCsv -Encoding UTF8
        }
    }
}

function Resolve-LiveChannel {
    try {
        Set-Status -Text 'Resolving Security live channel...' -Progress 10
        $probeSnapshot = Join-Path $env:TEMP ('SecurityProbe_{0}.evtx' -f ([guid]::NewGuid().ToString('N')))
        $probeCsv = Join-Path $env:TEMP ('SecurityProbe_{0}.csv' -f ([guid]::NewGuid().ToString('N')))
        Export-LiveChannelSnapshot -ChannelName $securityChannel -DestinationPath $probeSnapshot
        [void](Invoke-LogParserQuery -SourceExpression ("'{0}'" -f $probeSnapshot) -CsvPath $probeCsv -UserAccounts @())
        if (Test-Path -LiteralPath $probeCsv -PathType Leaf) {
            Write-Log "Live channel probe completed successfully."
            Show-Info "Security channel snapshot and Log Parser probe completed successfully." 'Resolve Channel'
        }
        else {
            New-HeaderOnlyCsv -Path $probeCsv -Headers @('EventTime','EventID','AccountName','CallerUser','Domain')
            Write-Log 'Live channel probe completed without sample rows. Treating channel access as valid.'
            Show-Info "Security channel is reachable. No sample rows were returned by the probe." 'Resolve Channel'
        }
    }
    catch {
        Write-Log -Level ERROR -Message ("Resolve Channel failed: {0}" -f $_.Exception.Message)
        Show-ErrorBox ("Resolve Channel failed: {0}" -f $_.Exception.Message) 'Resolve Channel'
    }
    finally {
        foreach ($p in @($probeSnapshot,$probeCsv)) {
            if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        }
        Set-Status -Text 'Ready.' -Progress 0
    }
}

function Start-Analysis {
    try {
        Write-Log 'Starting privileged access analysis.'
        Set-Status -Text 'Initializing...' -Progress 5

        $outputFolder = Get-SafeOutputFolder
        if (-not (Test-Path -LiteralPath $outputFolder -PathType Container)) {
            New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $finalCsv = Join-Path $outputFolder ('{0}-PrivilegedAccess-{1}.csv' -f $domainServerName, $timestamp)
        $userAccounts = Get-UserFilterValues
        $headers = @('EventTime','EventID','AccountName','CallerUser','Domain')

        Write-Log ("Starting processing. UseLiveLog={0}; Folder='{1}'; IncludeSubfolders={2}; OutputFolder='{3}'" -f $script:checkUseLive.Checked, $script:textEvtxFolder.Text, $script:checkSubfolders.Checked, $outputFolder)

        if ($script:checkUseLive.Checked) {
            Set-Status -Text 'Exporting live Security snapshot...' -Progress 15
            $snapshotPath = Join-Path $env:TEMP ('Security_{0}.evtx' -f ([guid]::NewGuid().ToString('N')))
            Export-LiveChannelSnapshot -ChannelName $securityChannel -DestinationPath $snapshotPath
            Set-Status -Text 'Parsing live snapshot...' -Progress 45
            [void](Invoke-LogParserQuery -SourceExpression ("'{0}'" -f $snapshotPath) -CsvPath $finalCsv -UserAccounts $userAccounts)
            if (-not (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
                New-HeaderOnlyCsv -Path $finalCsv -Headers $headers
                Write-Log 'Live snapshot query returned no rows. Created an empty CSV with headers only.'
            }
            if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) { Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue }
        }
        else {
            $folder = $script:textEvtxFolder.Text
            if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder -PathType Container)) {
                throw 'Please select a valid folder containing .evtx files.'
            }

            $searchOption = if ($script:checkSubfolders.Checked) { '-Recurse' } else { '' }
            $evtxFiles = if ($script:checkSubfolders.Checked) {
                @(Get-ChildItem -LiteralPath $folder -Filter '*.evtx' -File -Recurse)
            }
            else {
                @(Get-ChildItem -LiteralPath $folder -Filter '*.evtx' -File)
            }

            if (@($evtxFiles).Count -eq 0) {
                throw "No .evtx files were found in '$folder'."
            }

            Write-Log ("Archived EVTX file count: {0}" -f @($evtxFiles).Count)
            $tempCsvs = New-Object System.Collections.Generic.List[string]
            $index = 0
            foreach ($file in @($evtxFiles)) {
                $index++
                $percent = [Math]::Min(85, [int](($index / [double]@($evtxFiles).Count) * 75) + 10)
                Set-Status -Text ("Parsing {0} ({1} of {2})..." -f $file.Name, $index, @($evtxFiles).Count) -Progress $percent
                $tempCsv = Join-Path $env:TEMP ('PrivilegedAccess_{0}_{1}.csv' -f ([guid]::NewGuid().ToString('N')), $index)
                [void](Invoke-LogParserQuery -SourceExpression ("'{0}'" -f $file.FullName) -CsvPath $tempCsv -UserAccounts $userAccounts)
                if (Test-Path -LiteralPath $tempCsv -PathType Leaf) { [void]$tempCsvs.Add($tempCsv) }
            }

            if ($tempCsvs.Count -gt 0) {
                Merge-CsvFiles -TempCsvPaths $tempCsvs.ToArray() -DestinationCsv $finalCsv
            }
            if (-not (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
                New-HeaderOnlyCsv -Path $finalCsv -Headers $headers
                Write-Log 'Archived EVTX parsing returned no rows. Created an empty CSV with headers only.'
            }
            foreach ($temp in $tempCsvs) {
                if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            }
        }

        Set-Status -Text 'Finalizing report...' -Progress 95
        $eventCount = 0
        try { $eventCount = @(Import-Csv -LiteralPath $finalCsv).Count } catch { $eventCount = 0 }
        Write-Log ("Found {0} privileged access events. Report exported to '{1}'" -f $eventCount, $finalCsv)
        Set-Status -Text ("Completed. Found {0} events." -f $eventCount) -Progress 100
        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) { Start-Process -FilePath $finalCsv }
        Show-Info ("Found {0} privileged access events.`nReport exported to:`n{1}" -f $eventCount, $finalCsv) 'Success'
    }
    catch {
        Write-Log -Level ERROR -Message ("Error processing privileged access events: {0}" -f $_.Exception.Message)
        Show-ErrorBox ("Error processing privileged access events: {0}" -f $_.Exception.Message) 'Error'
        Set-Status -Text 'Error occurred. Check log for details.' -Progress 0
    }
}

# GUI
$formWidth = 760
$formHeight = 360
$labelWidth = 110
$controlWidth = 510
$rowY = 18
$rowStep = 34

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Privileged Access Tracking (4720/4724/4728/4732/4735/4756/4672)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size($formWidth, $formHeight)

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point(12, $rowY)
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelUsers.Text = 'User Accounts:'
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(130, ($rowY - 2))
$textUsers.Size = New-Object System.Drawing.Size(($controlWidth + 70), 48)
$textUsers.Multiline = $true
$textUsers.ScrollBars = 'Vertical'
$form.Controls.Add($textUsers)
$rowY += 58

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Location = New-Object System.Drawing.Point(130, $rowY)
$checkUseLive.Size = New-Object System.Drawing.Size(270, 20)
$checkUseLive.Text = 'Use live Security channel'
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Location = New-Object System.Drawing.Point(590, ($rowY - 2))
$buttonResolve.Size = New-Object System.Drawing.Size(120, 24)
$buttonResolve.Text = 'Resolve Channel'
$form.Controls.Add($buttonResolve)
$rowY += $rowStep

$labelEvtxFolder = New-Object System.Windows.Forms.Label
$labelEvtxFolder.Location = New-Object System.Drawing.Point(12, $rowY)
$labelEvtxFolder.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelEvtxFolder.Text = 'EVTX Folder:'
$form.Controls.Add($labelEvtxFolder)

$textEvtxFolder = New-Object System.Windows.Forms.TextBox
$textEvtxFolder.Location = New-Object System.Drawing.Point(130, ($rowY - 2))
$textEvtxFolder.Size = New-Object System.Drawing.Size($controlWidth, 24)
$form.Controls.Add($textEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(650, ($rowY - 1))
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(60, 24)
$buttonBrowseEvtx.Text = 'Browse'
$form.Controls.Add($buttonBrowseEvtx)
$rowY += $rowStep

$checkSubfolders = New-Object System.Windows.Forms.CheckBox
$checkSubfolders.Location = New-Object System.Drawing.Point(130, $rowY)
$checkSubfolders.Size = New-Object System.Drawing.Size(180, 20)
$checkSubfolders.Text = 'Include subfolders'
$checkSubfolders.Checked = $true
$form.Controls.Add($checkSubfolders)
$rowY += $rowStep

$labelOutputFolder = New-Object System.Windows.Forms.Label
$labelOutputFolder.Location = New-Object System.Drawing.Point(12, $rowY)
$labelOutputFolder.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelOutputFolder.Text = 'Output Folder:'
$form.Controls.Add($labelOutputFolder)

$textOutputFolder = New-Object System.Windows.Forms.TextBox
$textOutputFolder.Location = New-Object System.Drawing.Point(130, ($rowY - 2))
$textOutputFolder.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textOutputFolder.Text = $defaultOutputFolder
$form.Controls.Add($textOutputFolder)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(650, ($rowY - 1))
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(60, 24)
$buttonBrowseOutput.Text = 'Browse'
$form.Controls.Add($buttonBrowseOutput)
$rowY += $rowStep

$labelLogFolder = New-Object System.Windows.Forms.Label
$labelLogFolder.Location = New-Object System.Drawing.Point(12, $rowY)
$labelLogFolder.Size = New-Object System.Drawing.Size($labelWidth, 20)
$labelLogFolder.Text = 'Log Folder:'
$form.Controls.Add($labelLogFolder)

$textLogFolder = New-Object System.Windows.Forms.TextBox
$textLogFolder.Location = New-Object System.Drawing.Point(130, ($rowY - 2))
$textLogFolder.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textLogFolder.Text = $logDir
$textLogFolder.ReadOnly = $true
$form.Controls.Add($textLogFolder)
$rowY += ($rowStep + 6)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(12, $rowY)
$progressBar.Size = New-Object System.Drawing.Size(698, 18)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$form.Controls.Add($progressBar)
$rowY += 24

$labelStatus = New-Object System.Windows.Forms.Label
$labelStatus.Location = New-Object System.Drawing.Point(12, $rowY)
$labelStatus.Size = New-Object System.Drawing.Size(698, 20)
$labelStatus.Text = 'Ready.'
$form.Controls.Add($labelStatus)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Size = New-Object System.Drawing.Size(110, 28)
$buttonStart.Location = New-Object System.Drawing.Point(480, 315)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(110, 28)
$buttonClose.Location = New-Object System.Drawing.Point(600, 315)
$buttonClose.Text = 'Close'
$form.Controls.Add($buttonClose)

$script:form = $form
$script:progressBar = $progressBar
$script:labelStatus = $labelStatus
$script:checkUseLive = $checkUseLive
$script:textEvtxFolder = $textEvtxFolder
$script:checkSubfolders = $checkSubfolders
$script:textOutputFolder = $textOutputFolder
$script:textUsers = $textUsers

$folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
$folderDialog.ShowNewFolderButton = $false

$buttonBrowseEvtx.Add_Click({
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textEvtxFolder.Text = $folderDialog.SelectedPath
    }
})

$buttonBrowseOutput.Add_Click({
    if ($folderDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $textOutputFolder.Text = $folderDialog.SelectedPath
    }
})

$checkUseLive.Add_CheckedChanged({
    $isLive = $checkUseLive.Checked
    $textEvtxFolder.Enabled = -not $isLive
    $buttonBrowseEvtx.Enabled = -not $isLive
    $checkSubfolders.Enabled = -not $isLive
})

$buttonResolve.Add_Click({ Resolve-LiveChannel })
$buttonStart.Add_Click({ Start-Analysis })
$buttonClose.Add_Click({ $form.Close() })

Write-Log 'Tool started.'
[void]$form.ShowDialog()

# End of script
