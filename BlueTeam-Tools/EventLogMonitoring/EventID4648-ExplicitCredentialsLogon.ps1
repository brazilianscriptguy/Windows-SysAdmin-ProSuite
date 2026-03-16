<#
.SYNOPSIS
    PowerShell Script for Logging Explicit Credential Usage via Event ID 4648 using Log Parser.

.DESCRIPTION
    Windows Server 2019 / PowerShell 5.1-safe revision.
    Uses wevtutil snapshot export for live Security log collection and Log Parser COM for EVTX parsing.
    Exports consolidated CSV to My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy
    Revised for WS2019 compatibility

.VERSION
    03-16-2026 - 1.0.0-WS2019-RevA
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

    if (-not $ShowConsole) {
        $hwnd = [Win32Console]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][Win32Console]::ShowWindow($hwnd, 0)
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

#region Globals
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$machineName = [Environment]::MachineName
$script:defaultOutputFolder = [Environment]::GetFolderPath('MyDocuments')
$script:logDir = 'C:\Logs-TEMP'
$script:logPath = Join-Path $script:logDir ($scriptName + '.log')
$script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ($scriptName + '-Temp')
$script:liveChannelName = 'Security'
$script:progressBar = $null
$script:form = $null

if (-not (Test-Path -LiteralPath $script:logDir -PathType Container)) {
    New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $script:tempRoot -PathType Container)) {
    New-Item -Path $script:tempRoot -ItemType Directory -Force | Out-Null
}
#endregion

#region Helper Functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    try {
        $line | Out-File -FilePath $script:logPath -Encoding UTF8 -Append -Force
    } catch {
        # Never break the tool because logging failed
    }
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

function Update-ProgressBar {
    param([int]$Value)
    if ($script:progressBar -ne $null) {
        $bounded = [Math]::Max(0, [Math]::Min(100, $Value))
        $script:progressBar.Value = $bounded
        if ($script:form -ne $null) {
            $script:form.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Get-DefaultOutputFolder {
    param([string]$RequestedFolder)
    if ([string]::IsNullOrWhiteSpace($RequestedFolder)) {
        return $script:defaultOutputFolder
    }
    return $RequestedFolder
}

function New-HeaderOnlyCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers
    )
    $headerLine = ($Headers -join ',')
    Set-Content -LiteralPath $Path -Value $headerLine -Encoding UTF8
}

function Select-FolderDialog {
    param(
        [Parameter(Mandatory)][string]$Description,
        [string]$SelectedPath = ''
    )
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if (-not [string]::IsNullOrWhiteSpace($SelectedPath) -and (Test-Path -LiteralPath $SelectedPath -PathType Container)) {
        $dialog.SelectedPath = $SelectedPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-UserFilterList {
    param([string]$RawText)

    if ([string]::IsNullOrWhiteSpace($RawText)) {
        return @()
    }

    $parts = $RawText -split '[,;`r`n]+'
    $clean = New-Object System.Collections.Generic.List[string]
    foreach ($part in $parts) {
        $value = $part.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$clean.Add($value)
        }
    }
    return @($clean.ToArray())
}

function Build-InClause {
    param([string[]]$Values)

    if (@($Values).Count -eq 0) {
        return ''
    }

    $escaped = foreach ($value in $Values) {
        "'" + ($value -replace "'", "''") + "'"
    }
    return ($escaped -join ',')
}

function Export-LiveSecuritySnapshot {
    param([Parameter(Mandatory)][string]$DestinationPath)

    $wevtutil = Join-Path $env:WINDIR 'System32\wevtutil.exe'
    if (-not (Test-Path -LiteralPath $wevtutil -PathType Leaf)) {
        throw "wevtutil.exe was not found at '$wevtutil'."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $wevtutil
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $quotedChannel = '"' + ($script:liveChannelName -replace '"', '\"') + '"'
    $quotedDestination = '"' + ($DestinationPath -replace '"', '\"') + '"'
    $psi.Arguments = ('epl {0} {1} /ow:true' -f $quotedChannel, $quotedDestination)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        throw "wevtutil epl failed. ExitCode=$($process.ExitCode). StdErr=$stderr StdOut=$stdout"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw "Snapshot export did not create '$DestinationPath'."
    }

    return $DestinationPath
}

function Invoke-LogParserBatch {
    param(
        [Parameter(Mandatory)][string]$SqlQuery
    )

    $logQuery = New-Object -ComObject 'MSUtil.LogQuery'
    $inputFormat = New-Object -ComObject 'MSUtil.LogQuery.EventLogInputFormat'
    $outputFormat = New-Object -ComObject 'MSUtil.LogQuery.CSVOutputFormat'

    try {
        $result = $logQuery.ExecuteBatch($SqlQuery, $inputFormat, $outputFormat)
        Write-Log "Log Parser ExecuteBatch returned: $result"
        return $result
    }
    finally {
        if ($outputFormat -ne $null) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($outputFormat) }
        if ($inputFormat -ne $null)  { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($inputFormat) }
        if ($logQuery -ne $null)     { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($logQuery) }
    }
}

function Get-EventRowsFromCsv {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    $content = Get-Content -LiteralPath $Path -ErrorAction Stop
    if (@($content).Count -le 1) {
        return @()
    }
    return @(Import-Csv -LiteralPath $Path)
}

function Merge-CsvFiles {
    param(
        [Parameter(Mandatory)][string[]]$CsvFiles,
        [Parameter(Mandatory)][string]$OutputCsv,
        [Parameter(Mandatory)][string[]]$Headers
    )

    $allRows = New-Object System.Collections.Generic.List[object]
    foreach ($csvFile in @($CsvFiles)) {
        if (-not [string]::IsNullOrWhiteSpace($csvFile) -and (Test-Path -LiteralPath $csvFile -PathType Leaf)) {
            $rows = @(Get-EventRowsFromCsv -Path $csvFile)
            foreach ($row in $rows) {
                [void]$allRows.Add($row)
            }
        }
    }

    if ($allRows.Count -gt 0) {
        $allRows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
    }
    else {
        New-HeaderOnlyCsv -Path $OutputCsv -Headers $Headers
    }

    return $allRows.Count
}

function Get-EvtxFiles {
    param(
        [Parameter(Mandatory)][string]$FolderPath,
        [bool]$IncludeSubfolders
    )

    $items = if ($IncludeSubfolders) {
        Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop
    } else {
        Get-ChildItem -LiteralPath $FolderPath -Filter '*.evtx' -File -ErrorAction Stop
    }

    return @($items)
}

function Resolve-LiveChannel {
    param([Parameter(Mandatory)][string]$OutputFolder)

    Write-Log "Probing live channel '$($script:liveChannelName)' using snapshot export."
    $probeEvtx = Join-Path $script:tempRoot 'Resolve-Security-Probe.evtx'
    $probeCsv = Join-Path $script:tempRoot 'Resolve-Security-Probe.csv'

    if (Test-Path -LiteralPath $probeEvtx) { Remove-Item -LiteralPath $probeEvtx -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $probeCsv)  { Remove-Item -LiteralPath $probeCsv -Force -ErrorAction SilentlyContinue }

    [void](Export-LiveSecuritySnapshot -DestinationPath $probeEvtx)

    $sql = @"
SELECT TOP 1
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount
INTO '$probeCsv'
FROM '$probeEvtx'
WHERE EventID = 4648
"@

    [void](Invoke-LogParserBatch -SqlQuery $sql)

    if (Test-Path -LiteralPath $probeCsv) {
        Write-Log "Live channel probe completed."
        return $true
    }

    throw "Live channel probe failed. Probe CSV was not created."
}

function Compile-ExplicitCredentialEvents {
    [CmdletBinding()]
    param(
        [bool]$UseLiveLog,
        [string]$LogFolderPath,
        [bool]$IncludeSubfolders,
        [string]$OutputFolder,
        [string[]]$UserAccounts
    )

    $headers = @('EventTime','UserAccount','SubStatusCode','LogonType','StationUser','SourceIP')
    $effectiveOutputFolder = Get-DefaultOutputFolder -RequestedFolder $OutputFolder
    Ensure-Directory -Path $effectiveOutputFolder

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $effectiveOutputFolder ($machineName + '-ExplicitCredentialUsage-' + $timestamp + '.csv')

    Write-Log "Starting Event ID 4648 processing. UseLiveLog=$UseLiveLog; Folder='$LogFolderPath'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$effectiveOutputFolder'"
    Update-ProgressBar -Value 10

    $userInClause = Build-InClause -Values $UserAccounts
    $tempCsvFiles = New-Object System.Collections.Generic.List[string]
    $processed = 0

    if ($UseLiveLog) {
        $snapshotPath = Join-Path $script:tempRoot ('Security-LiveSnapshot-' + $timestamp + '.evtx')
        $tempCsv = Join-Path $script:tempRoot ('Security-LiveSnapshot-' + $timestamp + '.csv')

        Write-Log "Exporting live Security snapshot to '$snapshotPath'"
        [void](Export-LiveSecuritySnapshot -DestinationPath $snapshotPath)
        Update-ProgressBar -Value 35

        $sql = @"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 9, '|') AS SubStatusCode,
    EXTRACT_TOKEN(Strings, 10, '|') AS LogonType,
    EXTRACT_TOKEN(Strings, 13, '|') AS StationUser,
    EXTRACT_TOKEN(Strings, 19, '|') AS SourceIP
INTO '$tempCsv'
FROM '$snapshotPath'
WHERE EventID = 4648
$(if (-not [string]::IsNullOrWhiteSpace($userInClause)) { "  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userInClause)" } else { "" })
"@

        [void](Invoke-LogParserBatch -SqlQuery $sql)
        [void]$tempCsvFiles.Add($tempCsv)
        $processed = 1
        Update-ProgressBar -Value 70
    }
    else {
        if ([string]::IsNullOrWhiteSpace($LogFolderPath)) {
            throw "The EVTX folder path is required when live log mode is disabled."
        }
        if (-not (Test-Path -LiteralPath $LogFolderPath -PathType Container)) {
            throw "The EVTX folder '$LogFolderPath' does not exist."
        }

        $evtxFiles = @(Get-EvtxFiles -FolderPath $LogFolderPath -IncludeSubfolders $IncludeSubfolders)
        if (@($evtxFiles).Count -eq 0) {
            throw "No .evtx files were found in '$LogFolderPath'."
        }

        $total = @($evtxFiles).Count
        $index = 0
        foreach ($file in $evtxFiles) {
            $index++
            $tempCsv = Join-Path $script:tempRoot ([IO.Path]::GetFileNameWithoutExtension($file.Name) + '-' + $timestamp + '.csv')
            $safeEvtx = $file.FullName.Replace("'", "''")
            $safeCsv = $tempCsv.Replace("'", "''")

            Write-Log "Parsing EVTX file '$($file.FullName)' ($index of $total)"
            $sql = @"
SELECT
    TimeGenerated AS EventTime,
    EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
    EXTRACT_TOKEN(Strings, 9, '|') AS SubStatusCode,
    EXTRACT_TOKEN(Strings, 10, '|') AS LogonType,
    EXTRACT_TOKEN(Strings, 13, '|') AS StationUser,
    EXTRACT_TOKEN(Strings, 19, '|') AS SourceIP
INTO '$safeCsv'
FROM '$safeEvtx'
WHERE EventID = 4648
$(if (-not [string]::IsNullOrWhiteSpace($userInClause)) { "  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userInClause)" } else { "" })
"@
            [void](Invoke-LogParserBatch -SqlQuery $sql)
            [void]$tempCsvFiles.Add($tempCsv)

            $percent = 20 + [int](($index / $total) * 60)
            Update-ProgressBar -Value $percent
        }
        $processed = $total
    }

    $count = Merge-CsvFiles -CsvFiles @($tempCsvFiles.ToArray()) -OutputCsv $finalCsv -Headers $headers
    Update-ProgressBar -Value 100

    Write-Log "Found $count explicit credential usage events across $processed source item(s). Report exported to '$finalCsv'"
    return [pscustomobject]@{
        CsvPath = $finalCsv
        EventCount = $count
        SourceCount = $processed
    }
}
#endregion

#region GUI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Event ID 4648 - Explicit Credential Usage'
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Object System.Drawing.Size(780, 440)
$form.MinimumSize = New-Object System.Drawing.Size(780, 440)
$form.MaximizeBox = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$script:form = $form

$labelTitle = New-Object System.Windows.Forms.Label
$labelTitle.Text = 'Explicit Credential Usage Audit (Event ID 4648)'
$labelTitle.Location = New-Object System.Drawing.Point(15, 15)
$labelTitle.Size = New-Object System.Drawing.Size(720, 24)
$labelTitle.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($labelTitle)

$rowY = 50
$labelWidth = 150
$controlWidth = 470
$buttonWidth = 95

$checkLive = New-Object System.Windows.Forms.CheckBox
$checkLive.Text = 'Use live Security channel'
$checkLive.Location = New-Object System.Drawing.Point(18, $rowY)
$checkLive.Size = New-Object System.Drawing.Size(240, 24)
$checkLive.Checked = $true
$form.Controls.Add($checkLive)

$buttonResolve = New-Object System.Windows.Forms.Button
$buttonResolve.Text = 'Resolve Channel'
$buttonResolve.Location = New-Object System.Drawing.Point(610, ($rowY - 2))
$buttonResolve.Size = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($buttonResolve)

$rowY = 86
$labelFolder = New-Object System.Windows.Forms.Label
$labelFolder.Text = 'EVTX Folder:'
$labelFolder.Location = New-Object System.Drawing.Point(18, $rowY)
$labelFolder.Size = New-Object System.Drawing.Size($labelWidth, 24)
$form.Controls.Add($labelFolder)

$textFolder = New-Object System.Windows.Forms.TextBox
$textFolder.Location = New-Object System.Drawing.Point(170, $rowY)
$textFolder.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textFolder.Enabled = $false
$form.Controls.Add($textFolder)

$buttonBrowseEvtx = New-Object System.Windows.Forms.Button
$buttonBrowseEvtx.Text = 'Browse'
$buttonBrowseEvtx.Location = New-Object System.Drawing.Point(650, ($rowY - 1))
$buttonBrowseEvtx.Size = New-Object System.Drawing.Size(90, 26)
$buttonBrowseEvtx.Enabled = $false
$form.Controls.Add($buttonBrowseEvtx)

$rowY = 120
$checkSubfolders = New-Object System.Windows.Forms.CheckBox
$checkSubfolders.Text = 'Include subfolders'
$checkSubfolders.Location = New-Object System.Drawing.Point(170, $rowY)
$checkSubfolders.Size = New-Object System.Drawing.Size(180, 24)
$checkSubfolders.Checked = $true
$form.Controls.Add($checkSubfolders)

$rowY = 156
$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Text = 'User filter:'
$labelUsers.Location = New-Object System.Drawing.Point(18, $rowY)
$labelUsers.Size = New-Object System.Drawing.Size($labelWidth, 24)
$form.Controls.Add($labelUsers)

$textUsers = New-Object System.Windows.Forms.TextBox
$textUsers.Location = New-Object System.Drawing.Point(170, $rowY)
$textUsers.Size = New-Object System.Drawing.Size(($controlWidth + 70), 24)
$textUsers.Text = ''
$form.Controls.Add($textUsers)

$rowY = 192
$labelUsersHint = New-Object System.Windows.Forms.Label
$labelUsersHint.Text = 'Optional. Separate users with comma, semicolon, or new line.'
$labelUsersHint.Location = New-Object System.Drawing.Point(170, $rowY)
$labelUsersHint.Size = New-Object System.Drawing.Size(540, 20)
$form.Controls.Add($labelUsersHint)

$rowY = 226
$labelOutput = New-Object System.Windows.Forms.Label
$labelOutput.Text = 'CSV Output Folder:'
$labelOutput.Location = New-Object System.Drawing.Point(18, $rowY)
$labelOutput.Size = New-Object System.Drawing.Size($labelWidth, 24)
$form.Controls.Add($labelOutput)

$textOutput = New-Object System.Windows.Forms.TextBox
$textOutput.Location = New-Object System.Drawing.Point(170, $rowY)
$textOutput.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textOutput.Text = $script:defaultOutputFolder
$form.Controls.Add($textOutput)

$buttonBrowseOutput = New-Object System.Windows.Forms.Button
$buttonBrowseOutput.Text = 'Browse'
$buttonBrowseOutput.Location = New-Object System.Drawing.Point(650, ($rowY - 1))
$buttonBrowseOutput.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($buttonBrowseOutput)

$rowY = 262
$labelLogFolder = New-Object System.Windows.Forms.Label
$labelLogFolder.Text = 'Log Folder:'
$labelLogFolder.Location = New-Object System.Drawing.Point(18, $rowY)
$labelLogFolder.Size = New-Object System.Drawing.Size($labelWidth, 24)
$form.Controls.Add($labelLogFolder)

$textLogFolder = New-Object System.Windows.Forms.TextBox
$textLogFolder.Location = New-Object System.Drawing.Point(170, $rowY)
$textLogFolder.Size = New-Object System.Drawing.Size($controlWidth, 24)
$textLogFolder.Text = $script:logDir
$form.Controls.Add($textLogFolder)

$buttonBrowseLog = New-Object System.Windows.Forms.Button
$buttonBrowseLog.Text = 'Browse'
$buttonBrowseLog.Location = New-Object System.Drawing.Point(650, ($rowY - 1))
$buttonBrowseLog.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($buttonBrowseLog)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 314)
$progressBar.Size = New-Object System.Drawing.Size(720, 22)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)
$script:progressBar = $progressBar

$buttonStart = New-Object System.Windows.Forms.Button
$buttonStart.Text = 'Start Analysis'
$buttonStart.Location = New-Object System.Drawing.Point(390, 350)
$buttonStart.Size = New-Object System.Drawing.Size(150, 34)
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Text = 'Close'
$buttonClose.Location = New-Object System.Drawing.Point(560, 350)
$buttonClose.Size = New-Object System.Drawing.Size(180, 34)
$form.Controls.Add($buttonClose)

$checkLive.Add_CheckedChanged({
    $isArchivedMode = (-not $checkLive.Checked)
    $textFolder.Enabled = $isArchivedMode
    $buttonBrowseEvtx.Enabled = $isArchivedMode
})

$buttonBrowseEvtx.Add_Click({
    $selected = Select-FolderDialog -Description 'Select a folder containing Security EVTX files' -SelectedPath $textFolder.Text
    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        $textFolder.Text = $selected
    }
})

$buttonBrowseOutput.Add_Click({
    $selected = Select-FolderDialog -Description 'Select a folder for CSV export' -SelectedPath $textOutput.Text
    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        $textOutput.Text = $selected
    }
})

$buttonBrowseLog.Add_Click({
    $selected = Select-FolderDialog -Description 'Select a folder for log output' -SelectedPath $textLogFolder.Text
    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        $textLogFolder.Text = $selected
    }
})

$buttonResolve.Add_Click({
    try {
        $selectedLogFolder = if ([string]::IsNullOrWhiteSpace($textLogFolder.Text)) { $script:logDir } else { $textLogFolder.Text }
        Ensure-Directory -Path $selectedLogFolder
        $script:logDir = $selectedLogFolder
        $script:logPath = Join-Path $script:logDir ($scriptName + '.log')

        Update-ProgressBar -Value 15
        if ($checkLive.Checked) {
            [void](Resolve-LiveChannel -OutputFolder $textOutput.Text)
            Update-ProgressBar -Value 100
            Show-MessageBox -Message "Live Security channel probe completed successfully." -Title 'Resolve Channel'
        }
        else {
            if ([string]::IsNullOrWhiteSpace($textFolder.Text)) {
                throw 'Please select an EVTX folder first.'
            }
            if (-not (Test-Path -LiteralPath $textFolder.Text -PathType Container)) {
                throw "The EVTX folder '$($textFolder.Text)' does not exist."
            }
            Update-ProgressBar -Value 100
            Show-MessageBox -Message "EVTX folder is accessible." -Title 'Resolve Channel'
        }
    }
    catch {
        Update-ProgressBar -Value 0
        Write-Log "Resolve Channel failed: $($_.Exception.Message)" 'ERROR'
        Show-MessageBox -Message $_.Exception.Message -Title 'Resolve Channel Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonStart.Add_Click({
    try {
        $selectedLogFolder = if ([string]::IsNullOrWhiteSpace($textLogFolder.Text)) { $script:logDir } else { $textLogFolder.Text }
        Ensure-Directory -Path $selectedLogFolder
        $script:logDir = $selectedLogFolder
        $script:logPath = Join-Path $script:logDir ($scriptName + '.log')

        $outputFolder = Get-DefaultOutputFolder -RequestedFolder $textOutput.Text
        Ensure-Directory -Path $outputFolder
        $textOutput.Text = $outputFolder

        $userFilters = @(Get-UserFilterList -RawText $textUsers.Text)

        Write-Log 'Starting explicit credential usage analysis.'
        $result = Compile-ExplicitCredentialEvents -UseLiveLog $checkLive.Checked -LogFolderPath $textFolder.Text -IncludeSubfolders $checkSubfolders.Checked -OutputFolder $outputFolder -UserAccounts $userFilters

        $message = "Analysis completed.`r`n`r`nEvents found: $($result.EventCount)`r`nCSV file: $($result.CsvPath)"
        Show-MessageBox -Message $message -Title 'Completed'

        if ($AutoOpen -and (Test-Path -LiteralPath $result.CsvPath -PathType Leaf)) {
            Start-Process -FilePath $result.CsvPath
        }
    }
    catch {
        Update-ProgressBar -Value 0
        Write-Log "Error processing Event ID 4648: $($_.Exception.Message)" 'ERROR'
        Show-MessageBox -Message $_.Exception.Message -Title 'Processing Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$buttonClose.Add_Click({
    $form.Close()
})

$form.Add_Shown({
    $form.Activate()
})
#endregion

try {
    [void]$form.ShowDialog()
}
catch {
    Write-Log "Fatal UI error: $($_.Exception.Message)" 'ERROR'
    Show-MessageBox -Message $_.Exception.Message -Title 'Fatal Error' -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
}
finally {
    Update-ProgressBar -Value 0
}

# End of script
