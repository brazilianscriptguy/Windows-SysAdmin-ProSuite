<#
.SYNOPSIS
    PowerShell Script for detecting Event ID 1102 (Security log cleared).

.DESCRIPTION
    This WS2019-compatible revision analyzes Event ID 1102 from the live Security channel
    or archived .evtx files. In live mode, it exports a temporary snapshot with wevtutil
    and parses it using Log Parser COM. The consolidated CSV report is exported to
    My Documents by default.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2026-16-03 - RevA - WS2019-compatible migration
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
    param(
        [Parameter(Mandatory)]
        [string]$ChannelName
    )

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
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $header = 'EventTime,EventID,ActorUser,DomainName,ComputerName,LogWasCleared,SourceFile'
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

function Build-UserFilterClause {
    param([string[]]$UserAccounts)

    $normalizedUsers = @($UserAccounts | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($normalizedUsers).Count -eq 0) {
        return ''
    }

    $escaped = @($normalizedUsers | ForEach-Object { "'" + ($_.Replace("'", "''")) + "'" })
    return ("AND EXTRACT_TOKEN(Strings, 1, '|') IN ({0})" -f ($escaped -join '; '))
}

function Build-QueryForFile {
    param(
        [Parameter(Mandatory)]
        [string]$EvtxPath,

        [Parameter(Mandatory)]
        [string]$CsvPath,

        [Parameter()]
        [string[]]$UserAccounts
    )

    $escapedEvtx = $EvtxPath.Replace("'", "''")
    $escapedCsv  = $CsvPath.Replace("'", "''")
    $userClause  = Build-UserFilterClause -UserAccounts $UserAccounts

$query = @"
SELECT
    TimeGenerated AS EventTime,
    EventID,
    EXTRACT_TOKEN(Strings, 1, '|') AS ActorUser,
    EXTRACT_TOKEN(Strings, 2, '|') AS DomainName,
    EXTRACT_TOKEN(Strings, 3, '|') AS ComputerName,
    'Yes' AS LogWasCleared,
    '$escapedEvtx' AS SourceFile
INTO '$escapedCsv'
FROM '$escapedEvtx'
WHERE EventID = 1102
$userClause
"@
    return $query
}

function Merge-CsvFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SourceCsvFiles,

        [Parameter(Mandatory)]
        [string]$DestinationCsv
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
        [Parameter(Mandatory)]
        [string]$EvtxPath,

        [Parameter(Mandatory)]
        [string]$CsvPath,

        [Parameter()]
        [string[]]$UserAccounts
    )

    $lp = New-LogParserObjects
    $lp.OutputFormat.fileName = $CsvPath
    $query = Build-QueryForFile -EvtxPath $EvtxPath -CsvPath $CsvPath -UserAccounts $UserAccounts

    $result = $lp.Query.ExecuteBatch($query, $lp.InputFormat, $lp.OutputFormat)
    Write-Log "Log Parser ExecuteBatch returned: $result"

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        New-HeaderOnlyCsv -Path $CsvPath
    }
}

function Get-EvtxFilesSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [bool]$IncludeSubfolders
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw "The EVTX folder '$RootPath' was not found."
    }

    if ($IncludeSubfolders) {
        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -Recurse -ErrorAction Stop
    }
    else {
        $files = Get-ChildItem -LiteralPath $RootPath -Filter '*.evtx' -File -ErrorAction Stop
    }

    return @($files)
}

function Parse-DelimitedUsers {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $users = $Text -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($users)
}

function Resolve-SecurityChannel {
    [CmdletBinding()]
    param()

    Update-ProgressSafe -Value 10 -StatusText 'Resolving Security channel via snapshot export...'
    $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'

    $tempCsv = Join-Path $env:TEMP ('Security-Probe-1102-{0}.csv' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    Register-TempArtifact -Path $tempCsv
    Invoke-EventQueryToCsv -EvtxPath $snapshot -CsvPath $tempCsv -UserAccounts @()

    if (Test-Path -LiteralPath $tempCsv -PathType Leaf) {
        Write-Log 'Live Security channel probe completed successfully.'
        Update-ProgressSafe -Value 0 -StatusText 'Ready.'
        return $snapshot
    }

    throw 'Live Security channel probe did not produce a CSV file.'
}

function Process-Event1102 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$UseLiveLog,

        [Parameter()]
        [string]$EvtxFolder,

        [Parameter(Mandatory)]
        [bool]$IncludeSubfolders,

        [Parameter()]
        [string]$OutputFolder,

        [Parameter()]
        [string[]]$UserAccounts
    )

    $resolvedOutput = Resolve-OutputFolder -Candidate $OutputFolder
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $finalCsv = Join-Path $resolvedOutput ('{0}-EventID1102-EventLogCleared-{1}.csv' -f $computerName, $timestamp)
    $tempCsvFiles = New-Object System.Collections.ArrayList

    Write-Log "Starting Event ID 1102 processing. UseLiveLog=$UseLiveLog; Folder='$EvtxFolder'; IncludeSubfolders=$IncludeSubfolders; OutputFolder='$resolvedOutput'"

    try {
        Update-ProgressSafe -Value 5 -StatusText 'Preparing...'

        if ($UseLiveLog) {
            Update-ProgressSafe -Value 15 -StatusText 'Exporting Security snapshot...'
            $snapshot = Export-LiveChannelSnapshot -ChannelName 'Security'
            $sourceFiles = @([pscustomobject]@{ FullName = $snapshot; Name = [IO.Path]::GetFileName($snapshot) })
        }
        else {
            Update-ProgressSafe -Value 15 -StatusText 'Enumerating archived EVTX files...'
            $sourceFiles = Get-EvtxFilesSafe -RootPath $EvtxFolder -IncludeSubfolders:$IncludeSubfolders
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

            $tempCsv = Join-Path $env:TEMP ('Event1102-{0}-{1}.csv' -f $index, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
            Register-TempArtifact -Path $tempCsv
            [void]$tempCsvFiles.Add($tempCsv)

            Invoke-EventQueryToCsv -EvtxPath $source.FullName -CsvPath $tempCsv -UserAccounts $UserAccounts
            Write-Log "Processed '$($source.FullName)'."
        }

        Update-ProgressSafe -Value 88 -StatusText 'Merging CSV files...'
        Merge-CsvFiles -SourceCsvFiles @($tempCsvFiles) -DestinationCsv $finalCsv

        $rowCount = Get-RowCountSafe -CsvPath $finalCsv
        Update-ProgressSafe -Value 100 -StatusText ("Completed. Found {0} events. Report saved to '{1}'" -f $rowCount, $finalCsv)
        Write-Log "Found $rowCount Event ID 1102 records. Report exported to '$finalCsv'"

        if ($AutoOpen -and (Test-Path -LiteralPath $finalCsv -PathType Leaf)) {
            Start-Process -FilePath $finalCsv
        }

        Show-Info -Message ("Found {0} Event ID 1102 records.`r`nReport exported to:`r`n{1}" -f $rowCount, $finalCsv) -Title 'Success'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Error processing Event ID 1102. $($_.Exception.Message)"
        Update-ProgressSafe -Value 0 -StatusText 'Error occurred. Check log for details.'
        Show-ErrorBox -Message ("Error processing Event ID 1102.`r`n{0}" -f $_.Exception.Message)
    }
    finally {
        Remove-TempArtifacts
    }
}
#endregion

#region GUI
Initialize-LogDirectory

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Security Log Cleared Detector (Event ID 1102)'
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ClientSize = New-Object System.Drawing.Size(760, 390)
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
$buttonStart.Location = New-Object System.Drawing.Point(420, 342)
$buttonStart.Text = 'Start Analysis'
$form.Controls.Add($buttonStart)

$buttonClose = New-Object System.Windows.Forms.Button
$buttonClose.Size = New-Object System.Drawing.Size(120, 30)
$buttonClose.Location = New-Object System.Drawing.Point(590, 342)
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
        Resolve-SecurityChannel | Out-Null
        Show-Info -Message 'Live Security channel probe completed successfully.' -Title 'Resolve Channel'
    }
    catch {
        Write-Log -Level 'ERROR' -Message "Resolve Channel failed: $($_.Exception.Message)"
        Show-ErrorBox -Message ("Resolve Channel failed.`r`n{0}" -f $_.Exception.Message) -Title 'Resolve Channel'
    }
})

$buttonStart.Add_Click({
    $users = Parse-DelimitedUsers -Text $textUsers.Text
    Process-Event1102 -UseLiveLog:$checkUseLive.Checked -EvtxFolder $textEvtx.Text -IncludeSubfolders:$checkIncludeSubfolders.Checked -OutputFolder $textOutput.Text -UserAccounts $users
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
