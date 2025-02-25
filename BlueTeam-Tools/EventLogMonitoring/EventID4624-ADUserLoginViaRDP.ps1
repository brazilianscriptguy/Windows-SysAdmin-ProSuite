<#
.SYNOPSIS
    PowerShell Script for Auditing RDP Logon Activities via Event ID 4624 (Logon Type 10) using Log Parser.

.DESCRIPTION
    This script searches Security EVTX files in a selected folder for successful RDP logons (Event ID 4624, 
    Logon Type 10) using COM-based LogQuery, generating a detailed CSV report with user-configurable settings via a GUI.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 24, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the generated CSV file after processing.")]
    [bool]$AutoOpen = $true
)

#region Initialization
Add-Type -Name Window -Namespace Console -MemberDefinition @"
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        ShowWindow(GetConsoleWindow(), 0); // 0 = SW_HIDE
    }
"@ -ErrorAction Stop
[Console.Window]::Hide()

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    Write-Error "Failed to load required assemblies: $_"
    exit 1
}

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$DomainServerName = [System.Environment]::MachineName

# Define default paths
$logDir = "C:\Logs-TEMP"
$outputFolderDefault = [Environment]::GetFolderPath('MyDocuments')
$logPath = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path $logDir -PathType Container)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Failed to create log directory at '$logDir': $_"
        exit 1
    }
}
#endregion

#region Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,
        [ValidateSet('Info', 'Error', 'Warning')]
        [string]$Level = 'Info'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    try {
        $logEntry | Out-File -FilePath $script:logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$script:logPath': $_"
    }
}

function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title,
        [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
        [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Update-ProgressBar {
    param (
        [ValidateRange(0, 100)]
        [int]$Value
    )
    $script:progressBar.Value = $Value
    $script:form.Refresh()
}

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = "Select a folder containing Security .evtx files"
        ShowNewFolderButton = $false
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

function Find-RDPLogons {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$LogFolderPath,
        [Parameter(Mandatory)]
        [string]$OutputFolder,
        [string[]]$UserAccounts
    )
    Write-Log "Starting to search for RDP logons (Event ID 4624, Logon Type 10) in folder '$LogFolderPath'"

    try {
        $evtxFiles = Get-ChildItem -Path $LogFolderPath -Filter "*.evtx" -ErrorAction Stop
        if (-not $evtxFiles) {
            throw "No .evtx files found in '$LogFolderPath'"
        }

        $totalFiles = $evtxFiles.Count
        $processedFiles = 0

        $LogQuery = New-Object -ComObject "MSUtil.LogQuery"
        $InputFormat = New-Object -ComObject "MSUtil.LogQuery.EventLogInputFormat"
        $OutputFormat = New-Object -ComObject "MSUtil.LogQuery.CSVOutputFormat"

        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $consolidatedFile = Join-Path $OutputFolder "$DomainServerName-RDPLogons-$timestamp.csv"
        $tempCsvPath = Join-Path $env:TEMP "temp_rdp_$timestamp.csv"

        $userFilter = if ($UserAccounts -and $UserAccounts.Count -gt 0) { 
            "'" + ($UserAccounts -join "';'") + "'"
        } else { 
            "" 
        }
        $systemAccounts = "'SYSTEM';'ANONYMOUS LOGON';'LOCAL SERVICE';'NETWORK SERVICE'"
        $systemDomains = "'NT AUTHORITY'"

        foreach ($file in $evtxFiles) {
            $processedFiles++
            Update-ProgressBar -Value ([math]::Round(($processedFiles / $totalFiles) * 50))
            $script:statusLabel.Text = "Processing $($file.Name) ($processedFiles of $totalFiles)..."
            $script:form.Refresh()

            $SQLQuery = @"
            SELECT 
                TimeGenerated AS EventTime,
                EXTRACT_TOKEN(Strings, 5, '|') AS UserAccount,
                EXTRACT_TOKEN(Strings, 6, '|') AS Domain,
                EXTRACT_TOKEN(Strings, 11, '|') AS Workstation,
                EXTRACT_TOKEN(Strings, 18, '|') AS SourceIP,
                EXTRACT_TOKEN(Strings, 10, '|') AS SubStatusCode,
                EXTRACT_TOKEN(Strings, 11, '|') AS AccessedResource,
                EXTRACT_TOKEN(Strings, 8, '|') AS LogonType
            INTO '$tempCsvPath'
            FROM '$($file.FullName)'
            WHERE EventID = 4624
                AND EXTRACT_TOKEN(Strings, 8, '|') = '10'
                AND EXTRACT_TOKEN(Strings, 5, '|') NOT IN ($systemAccounts)
                AND EXTRACT_TOKEN(Strings, 6, '|') NOT IN ($systemDomains)
                $(if ($userFilter) { "AND EXTRACT_TOKEN(Strings, 5, '|') IN ($userFilter)" } else { "" })
"@

            $rtnVal = $LogQuery.ExecuteBatch($SQLQuery, $InputFormat, $OutputFormat)
            if ($rtnVal -eq 0) {
                throw "LogQuery execution failed for '$($file.FullName)'"
            }

            if (Test-Path $tempCsvPath) {
                if ($processedFiles -eq 1) {
                    Get-Content $tempCsvPath | Set-Content $consolidatedFile -Encoding UTF8
                } else {
                    Get-Content $tempCsvPath | Select-Object -Skip 1 | Add-Content $consolidatedFile -Encoding UTF8
                }
                Remove-Item $tempCsvPath -Force
                Write-Log "Processed $($file.Name) for RDP logons"
            }
        }

        Update-ProgressBar -Value 75
        $script:statusLabel.Text = "Finalizing report..."
        $script:form.Refresh()

        $eventCount = if (Test-Path $consolidatedFile) { (Import-Csv $consolidatedFile).Count } else { 0 }

        Update-ProgressBar -Value 90
        Write-Log "Found $eventCount RDP logons. Report exported to '$consolidatedFile'"
        $script:statusLabel.Text = "Completed. Found $eventCount RDP logons. Report saved to '$consolidatedFile'"

        if ($AutoOpen -and (Test-Path $consolidatedFile)) { Start-Process -FilePath $consolidatedFile }
        Update-ProgressBar -Value 100
        Show-MessageBox -Message "Found $eventCount RDP logons.`nReport exported to:`n$consolidatedFile" -Title "Success"
    } catch {
        Write-Log -Message "Error searching for RDP logons: $_" -Level Error
        Show-MessageBox -Message "Error searching for RDP logons: $_" -Title "Error" -Icon Error
        $script:statusLabel.Text = "Error occurred. Check log for details."
    } finally {
        Update-ProgressBar -Value 0
        if (Test-Path $tempCsvPath) { Remove-Item $tempCsvPath -Force }
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'RDP Logon Auditor (Event ID 4624, Logon Type 10)'
    Size          = [System.Drawing.Size]::new(450, 350)
    StartPosition = 'CenterScreen'
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
    Location = [System.Drawing.Point]::new(120, 20)
    Size     = [System.Drawing.Size]::new(320, 60)
    Multiline = $true
    Text     = "user01, user02, user03, user04, user05"
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
    $folder = Select-Folder
    if ($folder) { 
        $textBoxLogDir.Text = $folder 
        Write-Log "Log Directory updated to: '$folder' via browse"
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
    $folder = Select-Folder
    if ($folder) { 
        $textBoxOutputDir.Text = $folder 
        Write-Log "Output Folder updated to: '$folder' via browse"
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
}
$form.Controls.Add($progressBar)

# Start Button
$button = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(10, 240)
    Size     = [System.Drawing.Size]::new(100, 30)
    Text     = 'Start Analysis'
}
$button.Add_Click({
    $script:logDir = $textBoxLogDir.Text
    $script:logPath = Join-Path $script:logDir "${scriptName}.log"
    $outputFolder = $textBoxOutputDir.Text

    if (-not (Test-Path $script:logDir)) {
        New-Item -Path $script:logDir -ItemType Directory -Force | Out-Null
    }

    $userAccounts = if ($textBoxUsers.Text) { $textBoxUsers.Text -split ',\s*' | ForEach-Object { $_.Trim() } } else { @() }

    Write-Log "Analysis started by user (Users: $($userAccounts -join ', '))"
    $script:labelStatus.Text = "Selecting folder..."
    $script:form.Refresh()

    $evtxFolder = Select-Folder
    if (-not $evtxFolder) {
        Show-MessageBox -Message "No folder selected." -Title "Input Required" -Icon Warning
        $script:labelStatus.Text = "Ready"
        return
    }

    $script:labelStatus.Text = "Processing files in '$evtxFolder'..."
    $script:form.Refresh()

    Find-RDPLogons -LogFolderPath $evtxFolder -OutputFolder $outputFolder -UserAccounts $userAccounts
})
$form.Controls.Add($button)

# Script scope variables
$script:form = $form
$script:progressBar = $progressBar
$script:labelStatus = $labelStatus

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
