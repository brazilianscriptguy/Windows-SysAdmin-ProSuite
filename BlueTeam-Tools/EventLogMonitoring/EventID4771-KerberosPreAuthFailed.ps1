#requires -Version 5.1
<#
.SYNOPSIS
    Compiles Kerberos pre-authentication failures (Event ID 4771) from the live Security log or archived Security EVTX files using Log Parser 2.2.

.DESCRIPTION
    Revised for Windows Server 2019 / PowerShell 5.1, following the stable Print Audit architecture:
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
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message" | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
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

function Update-ProgressUi {
    param(
        [int]$Percent,
        [string]$StatusText
    )
    if ($script:ProgressBar) {
        $safe = [Math]::Min([Math]::Max($Percent, 0), 100)
        $script:ProgressBar.Value = $safe
    }
    if ($script:StatusLabel -and $StatusText) {
        $script:StatusLabel.Text = $StatusText
    }
    if ($script:Form) { $script:Form.Refresh() }
}

function Get-LogParserComObjects {
    try {
        return [pscustomobject]@{
            LogQuery     = New-Object -ComObject 'MSUtil.LogQuery'
            InputFormat  = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
            OutputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'
        }
    }
    catch {
        throw "Failed to initialize Log Parser COM objects. Ensure Log Parser 2.2 is installed. $($_.Exception.Message)"
    }
}

function Get-SafeOutputFolder {
    param([string]$RequestedPath)
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        return $script:DefaultOutputDir
    }
    return $RequestedPath
}

function New-HeaderOnlyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    $line = ($Headers -join ',')
    Set-Content -Path $Path -Value $line -Encoding UTF8
}

function Split-FilterList {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $items = $Text -split '[,;\r\n]+'
    return @($items | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-EvtxFiles {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [bool]$IncludeSubfolders
    )
    if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
        throw "The EVTX folder '$FolderPath' does not exist."
    }

    $files = if ($IncludeSubfolders) {
        @(Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop)
    }
    else {
        @(Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -ErrorAction Stop)
    }

    return $files
}

function Invoke-WevtutilExport {
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

    $quotedChannel = '"' + ($ChannelName -replace '"', '\"') + '"'
    $quotedDestination = '"' + ($DestinationPath -replace '"', '\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "wevtutil export failed. ExitCode=$($process.ExitCode). StdErr=$stderr StdOut=$stdout"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "wevtutil export did not create '$DestinationPath'."
    }
}

function Invoke-LogParserQuery {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputCsvPath
    )

    $com = Get-LogParserComObjects
    $escapedInput = $InputPath.Replace("'", "''")
    $escapedOutput = $OutputCsvPath.Replace("'", "''")
    $sql = $Query -replace '\{INPUT\}', $escapedInput -replace '\{OUTPUT\}', $escapedOutput

    Write-Log "Executing Log Parser query against '$InputPath'."
    $result = $com.LogQuery.ExecuteBatch($sql, $com.InputFormat, $com.OutputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $result"
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$SourceFiles,
        [Parameter(Mandatory)][string]$DestinationFile,
        [Parameter(Mandatory)][string[]]$Headers
    )

    $existing = @($SourceFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if (@($existing).Count -eq 0) {
        New-HeaderOnlyCsv -Path $DestinationFile -Headers $Headers
        return
    }

    $first = $true
    foreach ($file in $existing) {
        $content = @(Get-Content -LiteralPath $file -Encoding UTF8)
        if (@($content).Count -eq 0) { continue }

        if ($first) {
            Set-Content -Path $DestinationFile -Value $content -Encoding UTF8
            $first = $false
        }
        else {
            @($content | Select-Object -Skip 1) | Add-Content -Path $DestinationFile -Encoding UTF8
        }
    }

    if (-not (Test-Path -LiteralPath $DestinationFile -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $DestinationFile -Headers $Headers
    }
}

function Get-EventCountFromCsv {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    $rows = @(Import-Csv -LiteralPath $Path)
    return @($rows).Count
}

function Resolve-LiveSecurityChannel {
    param(
        [Parameter(Mandatory)][string]$OutputFolder,
        [string[]]$UserAccounts
    )

    $headers = @('EventTime','UserAccount','LockoutCode','StationIP')
    $probeFile = Join-Path $env:TEMP ('EventID4771-Probe-' + ([guid]::NewGuid().ToString()) + '.evtx')
    $probeCsv = Join-Path $env:TEMP ('EventID4771-Probe-' + ([guid]::NewGuid().ToString()) + '.csv')

    try {
        Update-ProgressUi -Percent 15 -StatusText 'Resolving Security channel via snapshot export...'
        Invoke-WevtutilExport -ChannelName $script:LiveChannelName -DestinationPath $probeFile

        $userClause = if (@($UserAccounts).Count -gt 0) {
            " AND EXTRACT_TOKEN(Strings, 0, '|') IN ('{0}')" -f (($UserAccounts -join "';'").Replace("'", "''"))
        }
        else { '' }

        $query = @"
SELECT TOP 1
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 0, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 3, '|') AS LockoutCode,
    EXTRACT_TOKEN(Strings, 5, '|') AS StationIP
INTO '{OUTPUT}'
FROM '{INPUT}'
WHERE EventID = 4771$userClause
"@

        Invoke-LogParserQuery -Query $query -InputPath $probeFile -OutputCsvPath $probeCsv
        if (Test-Path -LiteralPath $probeCsv -PathType Leaf) {
            Write-Log "Resolve Channel completed successfully using snapshot export."
        }
        else {
            Write-Log "Resolve Channel completed without sample rows. Treating channel access as valid." 'INFO'
        }
    }
    finally {
        Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $probeCsv -Force -ErrorAction SilentlyContinue
        Update-ProgressUi -Percent 0 -StatusText 'Ready.'
    }
}

function Invoke-EventId4771Processing {
    param(
        [bool]$UseLiveLog,
        [string]$EvtxFolder,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string[]]$UserAccounts
    )

    $headers = @('EventTime','UserAccount','LockoutCode','StationIP')
    $safeOutput = Get-SafeOutputFolder -RequestedPath $OutputFolder
    Ensure-Directory -Path $safeOutput

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $safeOutput ($script:MachineName + '-EventID4771-KerberosPreAuthFailed-' + $timestamp + '.csv')
    $tempFiles = @()
    $snapshotPath = $null

    try {
        Write-Log "Starting Event ID 4771 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$safeOutput'"

        $sources = @()
        if ($UseLiveLog) {
            Update-ProgressUi -Percent 10 -StatusText 'Exporting Security snapshot...'
            $snapshotPath = Join-Path $env:TEMP ('EventID4771-Snapshot-' + ([guid]::NewGuid().ToString()) + '.evtx')
            Invoke-WevtutilExport -ChannelName $script:LiveChannelName -DestinationPath $snapshotPath
            $sources = @([IO.FileInfo]$snapshotPath)
            Write-Log "Live Security snapshot exported to '$snapshotPath'."
        }
        else {
            Update-ProgressUi -Percent 10 -StatusText 'Enumerating EVTX files...'
            $sources = @(Get-EvtxFiles -FolderPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders)
            if (@($sources).Count -eq 0) {
                throw "No .evtx files were found in '$EvtxFolder'."
            }
            Write-Log "Found $(@($sources).Count) EVTX file(s) for processing."
        }

        $total = @($sources).Count
        $index = 0
        foreach ($source in $sources) {
            $index++
            $percent = 10 + [int]([Math]::Round(($index / [double]$total) * 70))
            Update-ProgressUi -Percent $percent -StatusText ("Processing {0} ({1} of {2})..." -f $source.Name, $index, $total)

            $tempCsv = Join-Path $env:TEMP ('EventID4771-' + ([guid]::NewGuid().ToString()) + '.csv')
            $tempFiles += $tempCsv

            $userClause = if (@($UserAccounts).Count -gt 0) {
                " AND EXTRACT_TOKEN(Strings, 0, '|') IN ('{0}')" -f (($UserAccounts -join "';'").Replace("'", "''"))
            }
            else { '' }

            $query = @"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 0, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 3, '|') AS LockoutCode,
    EXTRACT_TOKEN(Strings, 5, '|') AS StationIP
INTO '{OUTPUT}'
FROM '{INPUT}'
WHERE EventID = 4771$userClause
"@

            Invoke-LogParserQuery -Query $query -InputPath $source.FullName -OutputCsvPath $tempCsv
        }

        Update-ProgressUi -Percent 90 -StatusText 'Merging CSV results...'
        Merge-CsvFiles -SourceFiles $tempFiles -DestinationFile $finalCsv -Headers $headers

        $count = Get-EventCountFromCsv -Path $finalCsv
        Update-ProgressUi -Percent 100 -StatusText ("Completed. Found {0} Kerberos pre-authentication failures." -f $count)
        Write-Log "Found $count Kerberos pre-authentication failures. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-MessageBox -Message ("Found {0} Kerberos pre-authentication failures.`r`nReport exported to:`r`n{1}" -f $count, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log "Error processing Event ID 4771: $($_.Exception.Message)" 'ERROR'
        Update-ProgressUi -Percent 0 -StatusText 'Error occurred. Check log for details.'
        Show-MessageBox -Message ("Error processing Event ID 4771:`r`n{0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        foreach ($item in @($tempFiles)) {
            Remove-Item -LiteralPath $item -Force -ErrorAction SilentlyContinue
        }
        if ($snapshotPath) {
            Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
        }
        if ($script:ProgressBar -and $script:ProgressBar.Value -ne 100) {
            $script:ProgressBar.Value = 0
        }
    }
}

function Select-FolderPath {
    param([string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
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

# GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Kerberos Pre-Auth Failure Auditor (Event ID 4771)'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = [System.Drawing.Size]::new(760, 430)
$form.MinimumSize = [System.Drawing.Size]::new(760, 430)
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$script:Form = $form

$font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Font = $font

$marginLeft = 15
$labelWidth = 165
$textLeft = 185
$textWidth = 445
$smallButtonLeft = 640
$rowY = 20
$rowStep = 38

$checkUseLive = New-Object System.Windows.Forms.CheckBox
$checkUseLive.Text = 'Use live Security channel'
$checkUseLive.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$checkUseLive.Size = [System.Drawing.Size]::new(220, 24)
$checkUseLive.Checked = $true
$form.Controls.Add($checkUseLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Location = [System.Drawing.Point]::new(590, ($rowY - 2))
$buttonResolve.Size = [System.Drawing.Size]::new(140, 28)
$form.Controls.Add($buttonResolve)

$rowY += $rowStep

$labelEvtxFolder = New-Object System.Windows.Forms.Label
$labelEvtxFolder.Text = 'EVTX folder:'
$labelEvtxFolder.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$labelEvtxFolder.Size = [System.Drawing.Size]::new($labelWidth, 24)
$form.Controls.Add($labelEvtxFolder)

$textEvtxFolder = New-Object System.Windows.Forms.TextBox
$textEvtxFolder.Location = [System.Drawing.Point]::new($textLeft, $rowY)
$textEvtxFolder.Size = [System.Drawing.Size]::new($textWidth, 24)
$textEvtxFolder.Enabled = $false
$form.Controls.Add($textEvtxFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = '...'
$buttonBrowseEvtx.Location = [System.Drawing.Point]::new($smallButtonLeft, ($rowY - 1))
$buttonBrowseEvtx.Size = [System.Drawing.Size]::new(35, 26)
$buttonBrowseEvtx.Enabled = $false
$form.Controls.Add($buttonBrowseEvtx)

$rowY += $rowStep

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'User filter:'
$labelUsers.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$labelUsers.Size = [System.Drawing.Size]::new($labelWidth, 24)
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = [System.Drawing.Point]::new($textLeft, $rowY)
$textUsers.Size = [System.Drawing.Size]::new(($textWidth + 70), 24)
$textUsers.Text = ''
$form.Controls.Add($textUsers)

$rowY += $rowStep

$checkIncludeSubfolders = New-Object System.Windows.Forms.CheckBox
$checkIncludeSubfolders.Text = 'Include subfolders when scanning EVTX folder'
$checkIncludeSubfolders.Location = [System.Drawing.Point]::new($textLeft, $rowY)
$checkIncludeSubfolders.Size = [System.Drawing.Size]::new(300, 24)
$checkIncludeSubfolders.Checked = $true
$checkIncludeSubfolders.Enabled = $false
$form.Controls.Add($checkIncludeSubfolders)

$rowY += $rowStep

$labelOutputFolder = New-Object System.Windows.Forms.Label
$labelOutputFolder.Text = 'CSV output folder:'
$labelOutputFolder.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$labelOutputFolder.Size = [System.Drawing.Size]::new($labelWidth, 24)
$form.Controls.Add($labelOutputFolder)

$textOutputFolder = New-Object System.Windows.Forms.TextBox
$textOutputFolder.Location = [System.Drawing.Point]::new($textLeft, $rowY)
$textOutputFolder.Size = [System.Drawing.Size]::new($textWidth, 24)
$textOutputFolder.Text = $script:DefaultOutputDir
$form.Controls.Add($textOutputFolder)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = '...'
$buttonBrowseOutput.Location = [System.Drawing.Point]::new($smallButtonLeft, ($rowY - 1))
$buttonBrowseOutput.Size = [System.Drawing.Size]::new(35, 26)
$form.Controls.Add($buttonBrowseOutput)

$rowY += $rowStep

$labelLogFolder = New-Object System.Windows.Forms.Label
$labelLogFolder.Text = 'Log folder:'
$labelLogFolder.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$labelLogFolder.Size = [System.Drawing.Size]::new($labelWidth, 24)
$form.Controls.Add($labelLogFolder)

$textLogFolder = New-Object System.Windows.Forms.TextBox
$textLogFolder.Location = [System.Drawing.Point]::new($textLeft, $rowY)
$textLogFolder.Size = [System.Drawing.Size]::new($textWidth, 24)
$textLogFolder.Text = $script:LogDir
$form.Controls.Add($textLogFolder)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = '...'
$buttonBrowseLog.Location = [System.Drawing.Point]::new($smallButtonLeft, ($rowY - 1))
$buttonBrowseLog.Size = [System.Drawing.Size]::new(35, 26)
$form.Controls.Add($buttonBrowseLog)

$rowY += $rowStep

$script:StatusLabel = New-Object System.Windows.Forms.Label
$script:StatusLabel.Text = 'Ready.'
$script:StatusLabel.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$script:StatusLabel.Size = [System.Drawing.Size]::new(700, 24)
$form.Controls.Add($script:StatusLabel)

$rowY += 28

$script:ProgressBar = New-Object System.Windows.Forms.ProgressBar
$script:ProgressBar.Location = [System.Drawing.Point]::new($marginLeft, $rowY)
$script:ProgressBar.Size = [System.Drawing.Size]::new(715, 22)
$script:ProgressBar.Minimum = 0
$script:ProgressBar.Maximum = 100
$form.Controls.Add($script:ProgressBar)

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Size = [System.Drawing.Size]::new(120, 32)
$buttonStart.Location = [System.Drawing.Point]::new(475, 335)
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Size = [System.Drawing.Size]::new(120, 32)
$buttonClose.Location = [System.Drawing.Point]::new(610, 335)
$form.Controls.Add($buttonClose)

$toggleArchivedControls = {
    $isLive = $checkUseLive.Checked
    $textEvtxFolder.Enabled = -not $isLive
    $buttonBrowseEvtx.Enabled = -not $isLive
    $checkIncludeSubfolders.Enabled = -not $isLive
}
& $toggleArchivedControls

$checkUseLive.Add_CheckedChanged({ & $toggleArchivedControls })

$buttonBrowseEvtx.Add_Click({
    $selected = Select-FolderPath -Description 'Select the folder containing Security EVTX files'
    if ($selected) { $textEvtxFolder.Text = $selected }
})

$buttonBrowseOutput.Add_Click({
    $selected = Select-FolderPath -Description 'Select the folder for CSV export'
    if ($selected) { $textOutputFolder.Text = $selected }
})

$buttonBrowseLog.Add_Click({
    $selected = Select-FolderPath -Description 'Select the folder for tool logs'
    if ($selected) {
        $script:LogDir = $selected
        $script:LogPath = Join-Path $script:LogDir ($script:ScriptName + '.log')
        $textLogFolder.Text = $selected
        Write-Log "Log folder changed to '$selected'."
    }
})

$buttonResolve.Add_Click({
    try {
        $users = @(Split-FilterList -Text $textUsers.Text)
        Resolve-LiveSecurityChannel -OutputFolder (Get-SafeOutputFolder -RequestedPath $textOutputFolder.Text) -UserAccounts $users
        Show-MessageBox -Message 'Security channel probe completed successfully.' -Title 'Resolve Channel'
    }
    catch {
        Write-Log "Resolve Channel failed: $($_.Exception.Message)" 'ERROR'
        Show-MessageBox -Message ("Resolve Channel failed:`r`n{0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonStart.Add_Click({
    try {
        Ensure-Directory -Path $script:LogDir
        $users = @(Split-FilterList -Text $textUsers.Text)
        Invoke-EventId4771Processing -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtxFolder.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutputFolder.Text -UserAccounts $users
    }
    catch {
        Write-Log "Unhandled start error: $($_.Exception.Message)" 'ERROR'
        Show-MessageBox -Message ("Unhandled start error:`r`n{0}" -f $_.Exception.Message) -Title 'Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonClose.Add_Click({ $form.Close() })

[void]$form.ShowDialog()

# End of script
