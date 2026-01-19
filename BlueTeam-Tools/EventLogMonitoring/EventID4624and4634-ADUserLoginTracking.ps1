<#
.SYNOPSIS
    Tracks AD user Logon (4624) and Logoff (4634) events from Security EVTX files using Log Parser (MSUtil.LogQuery COM),
    and exports a consolidated CSV report. Includes a Windows Forms GUI.

.DESCRIPTION
    This tool:
      - Lets you select a folder containing Security .evtx files (recursive).
      - Filters by one or more user accounts (comma-separated).
      - Uses Log Parser 2.2 COM objects to query EVTX files (MSUtil.LogQuery).
      - Executes two MODEL-COMPLIANT queries (4624 and 4634) per EVTX (no IIF/CASE).
      - Merges into a single consolidated CSV (UTF-8).
      - Writes an execution log to C:\Logs-TEMP\<scriptname>.log
      - Optionally auto-opens the final CSV.

.REQUIREMENTS
    - Windows PowerShell 5.1
    - Microsoft Log Parser 2.2 installed (COM ProgID: MSUtil.LogQuery)

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Updated: January 19, 2026 (MODEL-COMPLIANT 4624/4634 queries integrated)
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

#region Initialization
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Hide Console (PS 5.1 compatible + safe re-run)
try {
    if (-not ("ConsoleWindow" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ConsoleWindow {
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void Hide() {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) {
            ShowWindow(hWnd, 0); // SW_HIDE
        }
    }
}
"@ -ErrorAction Stop
    }
    [ConsoleWindow]::Hide()
} catch {
    # If hiding fails, continue without stopping the script.
}

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    Write-Error ("Failed to load required assemblies (System.Windows.Forms / System.Drawing): {0}" -f $_.Exception.Message)
    exit 1
}

$scriptName       = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$DomainServerName = [Environment]::MachineName

# Defaults
$logDir              = "C:\Logs-TEMP"
$outputFolderDefault = [Environment]::GetFolderPath('MyDocuments')
$logPath             = Join-Path $logDir ("{0}.log" -f $scriptName)

if (-not (Test-Path $logDir -PathType Container)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
#endregion

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    try {
        $entry | Out-File -FilePath $script:logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        [System.Diagnostics.Debug]::WriteLine("LOG_WRITE_FAIL: $($_.Exception.Message)")
    }
}

function Show-MessageBox {
    param (
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [void][System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Update-ProgressBar {
    param (
        [ValidateRange(0, 100)]
        [int]$Value
    )
    if ($script:progressBar) { $script:progressBar.Value = $Value }
    if ($script:form) { $script:form.Refresh() }
}

function Set-Status {
    param([Parameter(Mandatory)][string]$Text)
    if ($script:labelStatus) { $script:labelStatus.Text = $Text }
    if ($script:form) { $script:form.Refresh() }
}

function Select-Folder {
    param(
        [string]$Description = "Select a folder",
        [bool]$ShowNewFolderButton = $false
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description         = $Description
        ShowNewFolderButton = $ShowNewFolderButton
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-SafeUserListForSqlInClause {
    <#
      Log Parser SQL expects: IN ('user1';'user2';'user3')
      Sanitizes input to avoid breaking SQL strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$UserAccounts
    )

    $clean = New-Object System.Collections.Generic.List[string]

    foreach ($u in $UserAccounts) {
        $t = ([string]$u).Trim()
        if ([string]::IsNullOrWhiteSpace($t)) { continue }

        # Conservative sanitization: strip quotes and semicolons
        $t = $t -replace "['];", ""

        if (-not [string]::IsNullOrWhiteSpace($t)) {
            [void]$clean.Add($t)
        }
    }

    if ($clean.Count -eq 0) {
        throw "No valid user accounts were provided after sanitization."
    }

    # Build: 'u1';'u2'
    return (($clean | ForEach-Object { "'{0}'" -f $_ }) -join ';')
}

function Test-LogParserAvailability {
    try {
        $null = New-Object -ComObject "MSUtil.LogQuery"
        return $true
    } catch {
        return $false
    }
}

function New-LogParserComObjects {
    try {
        return @{
            LogQuery     = (New-Object -ComObject "MSUtil.LogQuery")
            InputFormat  = (New-Object -ComObject "MSUtil.LogQuery.EventLogInputFormat")
            OutputFormat = (New-Object -ComObject "MSUtil.LogQuery.CSVOutputFormat")
        }
    } catch {
        throw ("Log Parser COM components are not available. Install Microsoft Log Parser 2.2 (MSUtil). Details: {0}" -f $_.Exception.Message)
    }
}

function Get-CsvDataRowCountFast {
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$Path
    )

    $lineCount = 0
    foreach ($chunk in Get-Content -Path $Path -ReadCount 2000 -ErrorAction Stop) {
        $arr = @($chunk)
        $lineCount += $arr.Length
    }

    return [Math]::Max(0, $lineCount - 1)
}

function Append-TempCsvToConsolidated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TempCsvPath,
        [Parameter(Mandatory)][string]$ConsolidatedFile,
        [Parameter(Mandatory)][ref]$WroteHeader
    )

    if (-not (Test-Path $TempCsvPath -PathType Leaf)) {
        return $false
    }

    $tempLines = @(Get-Content -Path $TempCsvPath -ErrorAction Stop)

    # header-only or empty
    if ($tempLines.Length -le 1) {
        return $false
    }

    if (-not $WroteHeader.Value) {
        $tempLines | Set-Content -Path $ConsolidatedFile -Encoding UTF8
        $WroteHeader.Value = $true
    } else {
        $tempLines | Select-Object -Skip 1 | Add-Content -Path $ConsolidatedFile -Encoding UTF8
    }

    return $true
}

function Track-LogonLogoffEvents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$LogFolderPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputFolder,

        [Parameter(Mandatory)]
        [string[]]$UserAccounts
    )

    Write-Log -Message ("Starting analysis. EVTX: '{0}' | Output: '{1}' | Users: {2}" -f $LogFolderPath, $OutputFolder, ($UserAccounts -join ', '))

    if (-not (Test-Path $OutputFolder -PathType Container)) {
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
        Write-Log -Message ("Created output folder: '{0}'" -f $OutputFolder)
    }

    $evtxFiles = @(Get-ChildItem -Path $LogFolderPath -Filter "*.evtx" -Recurse -File -ErrorAction Stop)
    if (-not $evtxFiles -or $evtxFiles.Count -eq 0) {
        throw ("No .evtx files found in '{0}'." -f $LogFolderPath)
    }

    $com = New-LogParserComObjects
    $LogQuery     = $com.LogQuery
    $InputFormat  = $com.InputFormat
    $OutputFormat = $com.OutputFormat

    $timestamp        = Get-Date -Format "yyyyMMddHHmmss"
    $consolidatedFile = Join-Path $OutputFolder ("{0}-LogonLogoff-{1}.csv" -f $DomainServerName, $timestamp)

    $userInClause = Get-SafeUserListForSqlInClause -UserAccounts $UserAccounts

    $totalFiles     = $evtxFiles.Count
    $processedFiles = 0
    $failedFiles    = 0
    $wroteHeader    = $false

    foreach ($file in $evtxFiles) {
        $processedFiles++
        $pct = [math]::Round(($processedFiles / $totalFiles) * 80)
        Update-ProgressBar -Value $pct
        Set-Status -Text ("Processing {0} ({1} of {2})..." -f $file.Name, $processedFiles, $totalFiles)

        # Unique temp paths for each query (MODEL-COMPLIANT; no IIF/CASE)
        $temp4624 = Join-Path $env:TEMP ("temp_4624_{0}_{1}.csv" -f $timestamp, ([guid]::NewGuid().ToString("N")))
        $temp4634 = Join-Path $env:TEMP ("temp_4634_{0}_{1}.csv" -f $timestamp, ([guid]::NewGuid().ToString("N")))

        # MODEL-COMPLIANT SQL – Event 4624 (Logon)
        $sql4624 = @"
SELECT
  'Logon' AS EventType,
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 5, '|')  AS UserAccount,
  EXTRACT_TOKEN(Strings, 6, '|')  AS DomainName,
  EXTRACT_TOKEN(Strings, 8, '|')  AS LogonType,
  EXTRACT_TOKEN(Strings, 18, '|') AS SourceIP
INTO '$temp4624'
FROM '$($file.FullName)'
WHERE EventID = 4624
  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userInClause)
"@

        # MODEL-COMPLIANT SQL – Event 4634 (Logoff)
        # Note: SourceIP is often absent/meaningless for 4634, but included as '-' placeholder for column consistency.
        $sql4634 = @"
SELECT
  'Logoff' AS EventType,
  TimeGenerated AS EventTime,
  EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
  EXTRACT_TOKEN(Strings, 6, '|') AS DomainName,
  EXTRACT_TOKEN(Strings, 8, '|') AS LogonType,
  '-' AS SourceIP
INTO '$temp4634'
FROM '$($file.FullName)'
WHERE EventID = 4634
  AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userInClause)
"@

        try {
            # Execute 4624
            $null = $LogQuery.ExecuteBatch($sql4624, $InputFormat, $OutputFormat)

            # Execute 4634
            $null = $LogQuery.ExecuteBatch($sql4634, $InputFormat, $OutputFormat)

            $appendedAny = $false

            if (Append-TempCsvToConsolidated -TempCsvPath $temp4624 -ConsolidatedFile $consolidatedFile -WroteHeader ([ref]$wroteHeader)) {
                $appendedAny = $true
            }

            if (Append-TempCsvToConsolidated -TempCsvPath $temp4634 -ConsolidatedFile $consolidatedFile -WroteHeader ([ref]$wroteHeader)) {
                $appendedAny = $true
            }

            if ($appendedAny) {
                Write-Log -Message ("Processed EVTX: '{0}'" -f $file.FullName)
            } else {
                Write-Log -Message ("No matching 4624/4634 events for selected users in: '{0}'" -f $file.FullName) -Level Warning
            }
        } catch {
            $failedFiles++
            Write-Log -Message ("Failed processing EVTX '{0}': {1}" -f $file.FullName, $_.Exception.Message) -Level Error
            Write-Log -Message ("SQL4624: {0}" -f ($sql4624 -replace "`r?`n", " ")) -Level Error
            Write-Log -Message ("SQL4634: {0}" -f ($sql4634 -replace "`r?`n", " ")) -Level Error
        } finally {
            if (Test-Path $temp4624) { Remove-Item $temp4624 -Force -ErrorAction SilentlyContinue }
            if (Test-Path $temp4634) { Remove-Item $temp4634 -Force -ErrorAction SilentlyContinue }
        }
    }

    Update-ProgressBar -Value 90
    Set-Status -Text "Finalizing report..."

    if (-not (Test-Path $consolidatedFile -PathType Leaf)) {
        Update-ProgressBar -Value 0
        throw "No output file was generated. No matching events were found, or Log Parser failed for all files."
    }

    $eventCount = Get-CsvDataRowCountFast -Path $consolidatedFile

    Update-ProgressBar -Value 100
    Write-Log -Message ("Completed. Events found: {0} | Failed EVTX: {1} | Report: '{2}'" -f $eventCount, $failedFiles, $consolidatedFile)
    Set-Status -Text ("Completed. Found {0} events. Saved to: {1}" -f $eventCount, $consolidatedFile)

    if ($AutoOpen) {
        try { Start-Process -FilePath $consolidatedFile | Out-Null } catch { }
    }

    $summary = "Found $eventCount logon/logoff events.`nReport exported to:`n$consolidatedFile"
    if ($failedFiles -gt 0) {
        $summary += "`n`nWarning: $failedFiles file(s) failed. Check the log:`n$script:logPath"
    }

    Show-MessageBox -Message $summary -Title "Success" -Icon ([System.Windows.Forms.MessageBoxIcon]::Information)
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text            = 'Logon/Logoff Auditor (Event IDs 4624 & 4634)'
    Size            = [System.Drawing.Size]::new(450, 350)
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox     = $false
}

# User Accounts
$labelUsers = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 20)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "User Accounts:"
}
$form.Controls.Add($labelUsers)

$textBoxUsers = New-Object System.Windows.Forms.TextBox -Property @{
    Location  = [System.Drawing.Point]::new(120, 20)
    Size      = [System.Drawing.Size]::new(320, 60)
    Multiline = $true
    Text      = "user01, user02, user03, user04, user05"
}
$form.Controls.Add($textBoxUsers)

# Log Directory
$labelLogDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 90)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Log Directory:"
}
$form.Controls.Add($labelLogDir)

$textBoxLogDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 90)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $logDir
}
$form.Controls.Add($textBoxLogDir)

$buttonBrowseLogDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 90)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseLogDir.Add_Click({
    $folder = Select-Folder -Description "Select a folder for log files" -ShowNewFolderButton $true
    if ($folder) {
        $textBoxLogDir.Text = $folder
        Write-Log -Message ("Log Directory set to: '{0}' (GUI Browse)" -f $folder)
    }
})
$form.Controls.Add($buttonBrowseLogDir)

# Output Folder
$labelOutputDir = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 120)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Output Folder:"
}
$form.Controls.Add($labelOutputDir)

$textBoxOutputDir = New-Object System.Windows.Forms.TextBox -Property @{
    Location = [System.Drawing.Point]::new(120, 120)
    Size     = [System.Drawing.Size]::new(200, 20)
    Text     = $outputFolderDefault
}
$form.Controls.Add($textBoxOutputDir)

$buttonBrowseOutputDir = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 120)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Browse"
}
$buttonBrowseOutputDir.Add_Click({
    $folder = Select-Folder -Description "Select a folder for CSV output" -ShowNewFolderButton $true
    if ($folder) {
        $textBoxOutputDir.Text = $folder
        Write-Log -Message ("Output Folder set to: '{0}' (GUI Browse)" -f $folder)
    }
})
$form.Controls.Add($buttonBrowseOutputDir)

# Status Label
$labelStatus = New-Object System.Windows.Forms.Label -Property @{
    Location = [System.Drawing.Point]::new(10, 180)
    Size     = [System.Drawing.Size]::new(430, 20)
    Text     = "Ready"
}
$form.Controls.Add($labelStatus)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = [System.Drawing.Point]::new(10, 210)
    Size     = [System.Drawing.Size]::new(430, 20)
    Minimum  = 0
    Maximum  = 100
    Value    = 0
}
$form.Controls.Add($progressBar)

# Start Button
$buttonStart = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 240)
    Size     = [System.Drawing.Size]::new(120, 30)
    Text     = 'Start Analysis'
}
$buttonStart.Add_Click({
    try {
        # Apply GUI selections
        $script:logDir = $textBoxLogDir.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($script:logDir)) { throw "Log Directory cannot be empty." }

        if (-not (Test-Path $script:logDir -PathType Container)) {
            New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
        }
        $script:logPath = Join-Path $script:logDir ("{0}.log" -f $scriptName)

        $outputFolder = $textBoxOutputDir.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($outputFolder)) { throw "Output Folder cannot be empty." }

        # Parse users (comma separated)
        $rawUsers = $textBoxUsers.Text
        $userAccounts = @()
        if (-not [string]::IsNullOrWhiteSpace($rawUsers)) {
            $userAccounts = @($rawUsers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        if (-not $userAccounts -or $userAccounts.Count -eq 0) {
            Show-MessageBox -Message "Please enter at least one user account to track." -Title "Input Required" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
            Set-Status -Text "Ready"
            return
        }

        if (-not (Test-LogParserAvailability)) {
            Show-MessageBox -Message "Microsoft Log Parser 2.2 is not installed or MSUtil COM is not registered.`n`nInstall Log Parser 2.2 and try again." -Title "Prerequisite Missing" -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
            Set-Status -Text "Ready"
            return
        }

        Write-Log -Message ("User started analysis. Users: {0}" -f ($userAccounts -join ', '))
        Set-Status -Text "Select the folder containing Security EVTX files..."

        $evtxFolder = Select-Folder -Description "Select the folder containing Security .evtx files" -ShowNewFolderButton $false
        if (-not $evtxFolder) {
            Show-MessageBox -Message "No EVTX folder selected." -Title "Input Required" -Icon ([System.Windows.Forms.MessageBoxIcon]::Warning)
            Set-Status -Text "Ready"
            return
        }

        Set-Status -Text ("Processing EVTX files in: {0}" -f $evtxFolder)
        Update-ProgressBar -Value 5

        Track-LogonLogoffEvents -LogFolderPath $evtxFolder -OutputFolder $outputFolder -UserAccounts $userAccounts
    } catch {
        Write-Log -Message ("Fatal error in Start handler: {0}" -f $_.Exception.Message) -Level Error
        Show-MessageBox -Message ("Error: {0}" -f $_.Exception.Message) -Title "Error" -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
        Set-Status -Text "Error occurred. Check the log."
        Update-ProgressBar -Value 0
    }
})
$form.Controls.Add($buttonStart)

# Script scope variables
$script:form        = $form
$script:progressBar = $progressBar
$script:labelStatus = $labelStatus

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion

# End of script
