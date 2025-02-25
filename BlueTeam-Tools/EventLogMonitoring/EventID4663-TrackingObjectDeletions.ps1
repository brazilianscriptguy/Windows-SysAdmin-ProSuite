<#
.SYNOPSIS
    PowerShell Script for Tracking Object Deletions via Event ID 4663 (Access Mask 0x10000).

.DESCRIPTION
    This script analyzes object deletion events (Event ID 4663 with Access Mask 0x10000) 
    from EVTX files, allowing user-configurable settings via a GUI, with results exported to CSV.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 24, 2025
#>

[CmdletBinding()]
Param (
    [Parameter(HelpMessage = "Automatically open the consolidated CSV file after processing.")]
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

# Embedded configuration as JSON string
$configJson = @"
{
    "LogDirectory": "C:\\Logs-TEMP",
    "OutputFolder": ""
}
"@
# Define defaults first
$defaultConfig = [PSCustomObject]@{ 
    LogDirectory = 'C:\Logs-TEMP'; 
    OutputFolder = [Environment]::GetFolderPath('MyDocuments') 
}
$config = try {
    $parsedConfig = $configJson | ConvertFrom-Json -ErrorAction Stop
    # Only update OutputFolder if parsed value is valid
    if ($parsedConfig.OutputFolder -and (Test-Path $parsedConfig.OutputFolder)) {
        $defaultConfig.OutputFolder = $parsedConfig.OutputFolder
    }
    $defaultConfig.LogDirectory = $parsedConfig.LogDirectory
    $defaultConfig
} catch {
    Write-Warning "Failed to parse embedded config: $_"
    $defaultConfig
}

$logDir = $config.LogDirectory
$logPath = Join-Path $logDir "${scriptName}.log"
$outputFolderDefault = $config.OutputFolder

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
        $logEntry | Out-File -FilePath $logPath -Append -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log at '$logPath': $_"
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

function Select-EvtxFiles {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        Filter      = "EVTX Files (*.evtx)|*.evtx"
        Title       = "Select EVTX Files"
        Multiselect = $true
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileNames
    }
    return $null
}

function Select-Folder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog -Property @{
        Description = "Select a folder"
        ShowNewFolderButton = $true
    }
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.SelectedPath
    }
    return $null
}

function Get-ObjectDeletionEvents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$EvtxFilePath,
        [string[]]$UserAccounts
    )
    Write-Log "Processing '$EvtxFilePath' for Event ID 4663 (Access Mask 0x10000)"
    $results = [System.Collections.Generic.List[PSObject]]::new()

    try {
        $allEvents = Get-WinEvent -Path $EvtxFilePath -ErrorAction Stop
        Write-Log "Total events in '$EvtxFilePath': $($allEvents.Count)"

        $events = $allEvents | Where-Object { $_.Id -eq 4663 }
        Write-Log "Event ID 4663 events found: $($events.Count)"

        if ($events.Count -eq 0) {
            Write-Log -Message "No Event ID 4663 events found in '$EvtxFilePath'" -Level Warning
            return $results
        }

        foreach ($event in $events) {
            $props = $event.Properties
            Write-Log "Processing Event ID 4663 at $($event.TimeCreated) - Properties count: $($props.Count)"

            if ($props.Count -gt 0) {
                $propValues = $props | ForEach-Object { $_.Value } | Out-String
                Write-Log "Raw properties: $propValues"
            }

            $userAccount = if ($props.Count -ge 2 -and $null -ne $props[1].Value) { $props[1].Value } else { "Unknown" }
            $accessMask = if ($props.Count -ge 9) { $props[8].Value } else { 0 }

            if ($UserAccounts -and $UserAccounts.Count -gt 0 -and $userAccount -notin $UserAccounts) {
                Write-Log "Event skipped - User '$userAccount' not in filter list"
                continue
            }

            if (-not ($accessMask -band 0x10000)) {
                Write-Log "Event skipped - Access Mask 0x$($accessMask.ToString('X')) does not include DELETE (0x10000)"
                continue
            }

            $results.Add([PSCustomObject]@{
                DateTime       = $event.TimeCreated
                EventID        = $event.Id
                UserAccount    = $userAccount
                Domain         = if ($props.Count -ge 3 -and $null -ne $props[2].Value) { $props[2].Value } else { "Unknown" }
                LockoutCode    = if ($props.Count -ge 5 -and $null -ne $props[4].Value) { $props[4].Value } else { "Unknown" }
                ObjectType     = if ($props.Count -ge 6 -and $null -ne $props[5].Value) { $props[5].Value } else { "Unknown" }
                AccessedObject = if ($props.Count -ge 7 -and $null -ne $props[6].Value) { $props[6].Value } else { "Unknown" }
                SubCode        = if ($props.Count -ge 8 -and $null -ne $props[7].Value) { $props[7].Value } else { "Unknown" }
                AccessMask     = "0x$($accessMask.ToString('X'))"
            })
            Write-Log "Deletion event detected - User: $userAccount, Access Mask: 0x$($accessMask.ToString('X'))"
        }
        Write-Log "Processed $($results.Count) deletion events in '$EvtxFilePath'"
    } catch {
        Write-Log -Message "Failed to process '$EvtxFilePath': $_" -Level Error
        Show-MessageBox -Message "Error processing '$EvtxFilePath': $_" -Title "Processing Error" -Icon Error
    }
    return $results
}

function Export-ResultsToCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Results,
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    Write-Log "Exporting $($Results.Count) results to '$FilePath'"
    try {
        $Results | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Export completed for '$FilePath'"
    } catch {
        Write-Log -Message "Failed to export to '$FilePath': $_" -Level Error
        Show-MessageBox -Message "Export failed for '$FilePath': $_" -Title "Export Error" -Icon Error
    }
}

function Merge-CsvResults {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$InputFiles,
        [Parameter(Mandatory)]
        [string]$OutputFile
    )
    Write-Log "Merging $($InputFiles.Count) CSV files into '$OutputFile'"
    try {
        $allResults = $InputFiles | ForEach-Object { Import-Csv -Path $_ -ErrorAction Stop }
        $allResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "Merge completed for '$OutputFile'"
    } catch {
        Write-Log -Message "Failed to merge results into '$OutputFile': $_" -Level Error
        Show-MessageBox -Message "Merge failed: $_" -Title "Merge Error" -Icon Error
    }
}

function Save-Config {
    param (
        [string]$LogDir,
        [string]$OutputDir
    )
    $newConfig = [PSCustomObject]@{
        LogDirectory = $LogDir
        OutputFolder = $OutputDir
    }
    $configPath = Join-Path $PSScriptRoot "config.json"
    try {
        $newConfig | ConvertTo-Json | Out-File -FilePath $configPath -Encoding UTF8 -ErrorAction Stop
        Write-Log "Configuration saved to '$configPath'"
        Show-MessageBox -Message "Configuration saved to:`n$configPath" -Title "Config Saved"
    } catch {
        Write-Log -Message "Failed to save config: $_" -Level Error
        Show-MessageBox -Message "Failed to save config: $_" -Title "Save Error" -Icon Error
    }
}
#endregion

#region GUI Setup
$form = New-Object System.Windows.Forms.Form -Property @{
    Text          = 'Object Deletion Event Parser (4663, Access Mask 0x10000)'
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
    Text     = ""  # Clear initially to avoid duplication
}
# Explicitly set the text and log it
$textBoxLogDir.Text = $logDir
Write-Log "Initialized Log Directory text box with: '$($textBoxLogDir.Text)'"
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

# Save Config Button
$buttonSaveConfig = New-Object System.Windows.Forms.Button -Property @{
    Location = [System.Drawing.Point]::new(330, 150)
    Size     = [System.Drawing.Size]::new(100, 20)
    Text     = "Save Config"
}
$buttonSaveConfig.Add_Click({
    Save-Config -LogDir $textBoxLogDir.Text -OutputDir $textBoxOutputDir.Text
})
$form.Controls.Add($buttonSaveConfig)

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
    $script:logPath = Join-Path $logDir "${scriptName}.log"
    $outputFolder = $textBoxOutputDir.Text

    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    $userAccounts = if ($textBoxUsers.Text) { $textBoxUsers.Text -split ',\s*' | ForEach-Object { $_.Trim() } } else { @() }

    Write-Log "Analysis started by user (Users: $($userAccounts -join ', '))"
    $labelStatus.Text = "Selecting files..."
    $form.Refresh()

    $evtxFiles = Select-EvtxFiles
    if (-not $evtxFiles) {
        Show-MessageBox -Message "No EVTX files selected." -Title "Input Required" -Icon Warning
        $labelStatus.Text = "Ready"
        return
    }

    $totalFiles = $evtxFiles.Count
    $processedFiles = 0
    $labelStatus.Text = "Processing file 1 of $totalFiles"
    $form.Refresh()

    $outputFiles = $evtxFiles | ForEach-Object {
        $processedFiles++
        $labelStatus.Text = "Processing file $processedFiles of $totalFiles"
        $form.Refresh()
        
        $file = $_
        $results = Get-ObjectDeletionEvents -EvtxFilePath $file -UserAccounts $userAccounts
        if ($results.Count -gt 0) {
            $outputFile = Join-Path $outputFolder "$([System.IO.Path]::GetFileNameWithoutExtension($file))_ObjectDeletionTracking.csv"
            Export-ResultsToCsv -Results $results -FilePath $outputFile
            $outputFile
        }
        Update-ProgressBar -Value ([math]::Round(($processedFiles / $totalFiles) * 100))
    }

    if ($outputFiles.Count -gt 0) {
        $labelStatus.Text = "Merging results..."
        $form.Refresh()
        $consolidatedFile = Join-Path $outputFolder "EventID4663-ObjectDeletionTracking.csv"
        Merge-CsvResults -InputFiles $outputFiles -OutputFile $consolidatedFile
        if (Test-Path $consolidatedFile) {
            Show-MessageBox -Message "Analysis complete. Results saved to:`n$consolidatedFile" -Title "Success"
            if ($AutoOpen) { Start-Process -FilePath $consolidatedFile }
        }
    } else {
        Show-MessageBox -Message "No object deletion events (Event ID 4663, Access Mask 0x10000) found in selected files." -Title "No Results" -Icon Warning
    }
    $labelStatus.Text = "Ready"
})
$form.Controls.Add($button)

$script:form = $form
$script:progressBar = $progressBar

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion
