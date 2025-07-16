<#
.SYNOPSIS
    WSUS Update Source and Proxy Configuration Script

.DESCRIPTION
    A PowerShell script designed to configure and manage the WSUS (Windows Server Update Services) server.
    Requires the WSUS Administration Console components to be installed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 16, 2025 11:05 AM -03
    Version: 2.15
#>

#region --- Global Setup and Loggingcls


# Setup Logging with single consolidated file
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP\WSUS-GUI\Logs'
$timestamp  = Get-Date -Format "yyyyMMdd-HHmmss"  # Set once at script start: 20250716-1105
$logPath    = Join-Path $logDir "$scriptName-$timestamp.log"

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$MessageType = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$stamp] [$MessageType] $Message"
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    Write-Host $entry
}

# Hide Console Window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

# Load required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

#endregion

#region --- Configuration

$global:Config = @{
    WsusAssemblyPath = "C:\Windows\Microsoft.Net\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration\v4.0_4.0.0.0__31bf3856ad364e35\Microsoft.UpdateServices.Administration.dll"
    SqlScriptDir     = "C:\Logs-TEMP\WSUS-GUI\Scripts"
    WsusUtilPath     = "C:\Program Files\Update Services\Tools\wsusutil.exe"
    LogDir           = 'C:\Logs-TEMP\WSUS-GUI\Logs'
    BackupDir        = 'C:\Logs-TEMP\WSUS-GUI\Backups'
    CsvDir           = 'C:\Logs-TEMP\WSUS-GUI\CSV'
    SettingsFile     = 'C:\Logs-TEMP\WSUS-GUI\settings.json'
}

# Load or prompt for configuration
if (Test-Path $Config.SettingsFile) {
    $loadedConfig = Get-Content $Config.SettingsFile -Raw | ConvertFrom-Json
    foreach ($key in $loadedConfig.PSObject.Properties.Name) {
        if ($Config.ContainsKey($key)) {
            $Config[$key] = $loadedConfig.$key
        }
    }
} else {
    $formConfig = New-Object System.Windows.Forms.Form
    $formConfig.Text = "Configure Paths"
    $formConfig.Size = New-Object System.Drawing.Size(400, 200)
    $formConfig.StartPosition = 'CenterScreen'

    $lblWsusAssembly = New-Object System.Windows.Forms.Label; $lblWsusAssembly.Text = "WSUS Assembly Path:"; $lblWsusAssembly.Location = New-Object System.Drawing.Point(10, 20); $formConfig.Controls.Add($lblWsusAssembly)
    $txtWsusAssembly = New-Object System.Windows.Forms.TextBox; $txtWsusAssembly.Text = $Config.WsusAssemblyPath; $txtWsusAssembly.Location = New-Object System.Drawing.Point(150, 20); $txtWsusAssembly.Size = New-Object System.Drawing.Size(230, 20); $formConfig.Controls.Add($txtWsusAssembly)

    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = "Save"; $btnSave.Location = New-Object System.Drawing.Point(150, 150); $btnSave.Add_Click({
        $Config.WsusAssemblyPath = $txtWsusAssembly.Text
        $Config | ConvertTo-Json | Set-Content -Path $Config.SettingsFile -Force
        $formConfig.Close()
    }); $formConfig.Controls.Add($btnSave)

    [void]$formConfig.ShowDialog()
}

$sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue).Source
if (-not $sqlcmdPath) {
    Log-Message "sqlcmd.exe not found. Please install SQL Server tools or specify the path." -MessageType ERROR
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Please install SQL Server tools or specify the path.", "Error", 'OK', 'Error')
    exit 1
}
Log-Message "Using sqlcmd.exe path: $sqlcmdPath" -MessageType INFO

# Ensure directories exist
foreach ($dir in @($Config.LogDir, $Config.BackupDir, $Config.CsvDir, $Config.SqlScriptDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

#endregion

#region --- Assembly Validation

function Validate-WSUSAssembly {
    $wsusAssemblyPath = $Config.WsusAssemblyPath
    try {
        $assembly = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
        if ($assembly) {
            Log-Message "WSUS Administration assembly loaded successfully from GAC." -MessageType INFO
            [System.Windows.Forms.MessageBox]::Show("WSUS Administration assembly loaded successfully from the Global Assembly Cache (GAC).", "Success", 'OK', 'Information')
            return
        } else {
            throw "Assembly not loaded from GAC."
        }
    } catch {
        Log-Message "Failed to load WSUS assembly from GAC: $_" -MessageType WARNING
    }

    if (Test-Path $wsusAssemblyPath) {
        try {
            Add-Type -Path $wsusAssemblyPath -ErrorAction Stop
            Log-Message "WSUS Administration assembly loaded successfully from $wsusAssemblyPath." -MessageType INFO
            [System.Windows.Forms.MessageBox]::Show("WSUS Administration assembly loaded successfully from path:`n$wsusAssemblyPath", "Success", 'OK', 'Information')
        } catch {
            $msg = "Error: Failed to load WSUS assembly from:`n$wsusAssemblyPath`n`nDetails: $_"
            Log-Message $msg -MessageType ERROR
            [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
            exit 1
        }
    } else {
        $msg = "WSUS assembly not found at:`n$wsusAssemblyPath`n`nEnsure the WSUS Administration Console is installed using one of the following methods:`n"
        $msg += "`n1. Server Manager:`n   - Add Roles and Features > Features > Windows Server Update Services > WSUS Tools"
        $msg += "`n2. PowerShell:`n   - Install-WindowsFeature -Name UpdateServices-UI"
        Log-Message "Error: WSUS assembly not found at $wsusAssemblyPath." -MessageType ERROR
        [System.Windows.Forms.MessageBox]::Show($msg, "Error", 'OK', 'Error')
        exit 1
    }
}

#endregion

#region --- Script Functions

function Save-Settings {
    $settings = @{
        ServerName         = $txtServer.Text
        Port               = $txtPort.Text
        DeclineUnapproved  = $chkDeclineUnapproved.Checked
        DeclineExpired     = $chkDeclineExpired.Checked
        DeclineSuperseded  = $chkDeclineSuperseded.Checked
        RemoveClassifications = $chkRemoveClassifications.Checked
        UnusedUpdates      = $chkUnusedUpdates.Checked
        ObsoleteComputers  = $chkObsoleteComputers.Checked
        UnneededFiles      = $chkUnneededFiles.Checked
        ExpiredUpdates     = $chkExpiredUpdates.Checked
        SupersededUpdates  = $chkSupersededUpdates.Checked
        CheckDB            = $chkCheckDB.Checked
        CheckFragmentation = $chkCheckFragmentation.Checked
        Reindex            = $chkReindex.Checked
        ShrinkDB           = $chkShrink.Checked
        BackupDB           = $chkBackup.Checked
    }
    $settings | ConvertTo-Json | Set-Content -Path $Config.SettingsFile -Force
}

function Load-Settings {
    if (Test-Path $Config.SettingsFile) {
        $settings = Get-Content $Config.SettingsFile -Raw | ConvertFrom-Json
        $txtServer.Text = if ($settings.ServerName) { $settings.ServerName } else { "localhost" }
        $txtPort.Text = if ($settings.Port) { $settings.Port } else { "8530" }
        $chkDeclineUnapproved.Checked = if ($settings.DeclineUnapproved) { $settings.DeclineUnapproved } else { $false }
        $chkDeclineExpired.Checked = if ($settings.DeclineExpired) { $settings.DeclineExpired } else { $true }
        $chkDeclineSuperseded.Checked = if ($settings.DeclineSuperseded) { $settings.DeclineSuperseded } else { $true }
        $chkRemoveClassifications.Checked = if ($settings.RemoveClassifications) { $settings.RemoveClassifications } else { $false }
        $chkUnusedUpdates.Checked = if ($settings.UnusedUpdates) { $settings.UnusedUpdates } else { $false }
        $chkObsoleteComputers.Checked = if ($settings.ObsoleteComputers) { $settings.ObsoleteComputers } else { $true }
        $chkUnneededFiles.Checked = if ($settings.UnneededFiles) { $settings.UnneededFiles } else { $false }
        $chkExpiredUpdates.Checked = if ($settings.ExpiredUpdates) { $settings.ExpiredUpdates } else { $true }
        $chkSupersededUpdates.Checked = if ($settings.SupersededUpdates) { $settings.SupersededUpdates } else { $true }
        $chkCheckDB.Checked = if ($settings.CheckDB) { $settings.CheckDB } else { $false }
        $chkCheckFragmentation.Checked = if ($settings.CheckFragmentation) { $settings.CheckFragmentation } else { $false }
        $chkReindex.Checked = if ($settings.Reindex) { $settings.Reindex } else { $false }
        $chkShrink.Checked = if ($settings.ShrinkDB) { $settings.ShrinkDB } else { $false }
        $chkBackup.Checked = if ($settings.BackupDB) { $settings.BackupDB } else { $false }
    }
}

function Get-WSUSServers {
    $servers = @("localhost")
    try {
        if (Get-Module -ListAvailable -Name ActiveDirectory -ErrorAction SilentlyContinue) {
            Import-Module ActiveDirectory -ErrorAction Stop
            $wsusServers = Get-ADObject -Filter {objectClass -eq "microsoftWSUS"} -Properties dNSHostName | Select-Object -ExpandProperty dNSHostName -ErrorAction Stop
            if ($wsusServers) {
                $servers += $wsusServers
            }
            Log-Message "Discovered WSUS servers via AD: $($servers -join ', ')" -MessageType INFO
        } else {
            Log-Message "Active Directory module not available, using local server only." -MessageType WARNING
        }
    } catch {
        Log-Message "Failed to discover WSUS servers via AD: $_" -MessageType WARNING
    }
    return $servers | Sort-Object -Unique
}

function Test-WSUSConnection {
    param (
        [string]$ServerName = "localhost",
        [int]$Port = 8530,
        [bool]$UseSSL = $false,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2
    )
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
            if ($wsus -and ($wsus | Get-Member -Name "SearchUpdates" -MemberType Method)) {
                Log-Message "Successfully connected to WSUS server: $ServerName (Port: $Port, SSL: $UseSSL)" -MessageType INFO
                return $wsus
            }
            throw "WSUS connection validation failed."
        } catch {
            $retryCount++
            Log-Message "Failed to connect to WSUS server ($ServerName, Attempt $retryCount/$MaxRetries): $_" -MessageType WARNING
            if ($retryCount -ge $MaxRetries) {
                Log-Message "Max retries reached for WSUS connection to $ServerName" -MessageType ERROR
                throw
            }
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    throw "Unexpected exit from Test-WSUSConnection"
}

function Decline-Updates {
    param (
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][scriptblock]$Filter,
        [Parameter(Mandatory=$true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)
        $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
        if ($updates.Count -eq 0) {
            Log-Message "$Type updates: None found matching criteria." -MessageType INFO
            return @()
        }
        Log-Message "$Type updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Log-Message "Declined $Type update: $($update.Title)" -MessageType INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = $Type
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Log-Message "Failed to decline $Type update: $($update.Title) - $_" -MessageType ERROR
            }
        }
        return $log
    } catch {
        Log-Message "Error in Decline-Updates ($Type): $_" -MessageType ERROR
        throw
    }
}

function Decline-ByClassification {
    param (
        [Parameter(Mandatory=$true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
        $scope.FromCreationDate = (Get-Date).AddDays(-365)
        $classifications = @("Itanium", "Windows XP")
        $updates = $wsus.SearchUpdates($scope) | Where-Object {
            $_.IsDeclined -eq $false -and ($_.Title -match ($classifications -join "|") -or $_.Description -match ($classifications -join "|"))
        }
        if ($updates.Count -eq 0) {
            Log-Message "Classification-based updates: None found matching criteria." -MessageType INFO
            return @()
        }
        Log-Message "Classification-based updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
        $log = @()
        foreach ($update in $updates) {
            try {
                $update.Decline()
                Log-Message "Declined classification-based update: $($update.Title)" -MessageType INFO
                $log += [PSCustomObject]@{
                    KB          = $update.KnowledgeBaseArticles -join ","
                    Title       = $update.Title
                    Type        = "Classification"
                    Date        = $update.CreationDate
                    DeclinedOn  = Get-Date
                    Server      = $ServerName
                }
            } catch {
                Log-Message "Failed to decline classification-based update: $($update.Title) - $_" -MessageType ERROR
            }
        }
        return $log
    } catch {
        Log-Message "Error in Decline-ByClassification: $_" -MessageType ERROR
        throw
    }
}

function Run-WSUSCleanup {
    param (
        [Parameter(Mandatory=$true)][bool]$IncludeUnusedUpdates,
        [Parameter(Mandatory=$true)][bool]$IncludeObsoleteComputers,
        [Parameter(Mandatory=$true)][bool]$IncludeUnneededFiles,
        [Parameter(Mandatory=$true)][bool]$IncludeExpiredUpdates,
        [Parameter(Mandatory=$true)][bool]$IncludeSupersededUpdates,
        [Parameter(Mandatory=$true)][string]$ServerName,
        [int]$Port = 8530,
        [bool]$UseSSL = $false
    )
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
        $cleanup = $wsus.GetCleanupManager()
        $steps = @()
        if ($IncludeUnusedUpdates) {
            $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::UnusedUpdatesAndUpdatesRevisions
            Log-Message "Cleaning Unused Updates and Revisions (older than 30 days)..." -MessageType INFO
        }
        if ($IncludeObsoleteComputers) {
            $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteComputers
            Log-Message "Cleaning Obsolete Computers (not contacted in 30+ days)..." -MessageType INFO
        }
        if ($IncludeUnneededFiles) {
            $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::UnneededUpdateFiles
            Log-Message "Cleaning Unneeded Update Files..." -MessageType INFO
        }
        if ($IncludeExpiredUpdates) {
            $updates = $wsus.SearchUpdates((New-Object Microsoft.UpdateServices.Administration.UpdateScope)) | Where-Object { $_.IsExpired -and -not $_.IsDeclined -and -not $_.IsApproved }
            if ($updates.Count -gt 0) {
                foreach ($update in $updates) {
                    try {
                        $update.Decline()
                        Log-Message "Declined Expired Update: $($update.Title)" -MessageType INFO
                    } catch {
                        Log-Message "Failed to decline Expired Update: $($update.Title) - $_" -MessageType ERROR
                    }
                }
            }
            Log-Message "Checked for Expired Updates (declined if unapproved)..." -MessageType INFO
        }
        if ($IncludeSupersededUpdates) {
            $updates = $wsus.SearchUpdates((New-Object Microsoft.UpdateServices.Administration.UpdateScope)) | Where-Object { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) }
            if ($updates.Count -gt 0) {
                foreach ($update in $updates) {
                    try {
                        $update.Decline()
                        Log-Message "Declined Superseded Update: $($update.Title)" -MessageType INFO
                    } catch {
                        Log-Message "Failed to decline Superseded Update: $($update.Title) - $_" -MessageType ERROR
                    }
                }
            }
            Log-Message "Checked for Superseded Updates (declined if unapproved for 30+ days)..." -MessageType INFO
        }
        if ($steps.Count -gt 0) {
            $success = $false
            foreach ($step in $steps) {
                try {
                    Log-Message "Running Cleanup Step: $step" -MessageType INFO
                    $cleanup.PerformCleanup($step)
                    Log-Message "Cleanup Step '$step' completed." -MessageType INFO
                    $success = $true
                } catch {
                    Log-Message "Cleanup Step '$step' failed with assembly method: $_" -MessageType WARNING
                }
            }
            if (-not $success -and (Test-Path $Config.WsusUtilPath)) {
                Log-Message "Falling back to wsusutil.exe for cleanup..." -MessageType INFO
                $output = & $Config.WsusUtilPath deleteunneededrevisions 2>&1
                Log-Message "wsusutil.exe deleteunneededrevisions output: $output" -MessageType INFO
                if ($IncludeUnneededFiles) {
                    $output = & $Config.WsusUtilPath compress 2>&1
                    Log-Message "wsusutil.exe compress output: $output" -MessageType INFO
                }
                Log-Message "WSUS Cleanup completed using wsusutil.exe." -MessageType INFO
            } elseif (-not $success) {
                Log-Message "Error: No cleanup method succeeded and wsusutil.exe not found at $($Config.WsusUtilPath)" -MessageType ERROR
                throw "Cleanup failed"
            }
        }
    } catch {
        Log-Message "Error in Run-WSUSCleanup: $_" -MessageType ERROR
        throw
    }
}

function Run-WIDMaintenance {
    param (
        [bool]$DoCheckDB,
        [bool]$DoCheckFragmentation,
        [bool]$DoReindex,
        [bool]$DoShrink,
        [bool]$DoBackup
    )
    try {
        $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

        if ($DoBackup) {
            $backupFile = Join-Path $Config.BackupDir "SUSDB-Backup-$timestamp.bak"
            Log-Message "Backing up SUSDB to $backupFile..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "Backup output: $output" -MessageType INFO
        }

        if ($DoCheckDB) {
            Log-Message "Running DBCC CHECKDB..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "DBCC CHECKDB output: $output" -MessageType INFO
        }

        if ($DoCheckFragmentation) {
            $fragmentationScript = Join-Path $Config.SqlScriptDir "wsus-verify-fragmentation.sql"
            if (Test-Path $fragmentationScript) {
                Log-Message "Checking Index Fragmentation with $fragmentationScript..." -MessageType INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Log-Message "Fragmentation Check output: $output" -MessageType INFO
            } else {
                Log-Message "Fragmentation script not found at $fragmentationScript" -MessageType WARNING
            }
        }

        if ($DoReindex) {
            $reindexScript = Join-Path $Config.SqlScriptDir "wsus-reindex.sql"
            if (Test-Path $reindexScript) {
                Log-Message "Reindexing with $reindexScript..." -MessageType INFO
                $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                $output = & $sqlcmdPath $args 2>&1
                Log-Message "Reindex output: $output" -MessageType INFO
            } else {
                Log-Message "Reindex script not found at $reindexScript" -MessageType WARNING
            }
        }

        if ($DoShrink) {
            Log-Message "Shrinking SUSDB..." -MessageType INFO
            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
            $output = & $sqlcmdPath $args 2>&1
            Log-Message "Shrink Database output: $output" -MessageType INFO
        }
    } catch {
        Log-Message "Error in Run-WIDMaintenance: $_" -MessageType ERROR
        throw
    }
}

function Create-ScheduledTask {
    param ([string]$ScriptPath = $PSCommandPath, [string]$TaskName = "WSUSMaintenanceTask", [string]$Time = "02:00")
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $Time
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Weekly WSUS Maintenance" -Force
        Log-Message "Scheduled Task '$TaskName' created successfully at $Time." -MessageType INFO
        [System.Windows.Forms.MessageBox]::Show("Scheduled Task '$TaskName' created successfully at $Time.", "Success", 'OK', 'Information')
    } catch {
        Log-Message "Failed to create scheduled task: $_" -MessageType ERROR
        [System.Windows.Forms.MessageBox]::Show("Failed to create scheduled task: $_", "Error", 'OK', 'Error')
    }
}

function Test-ConnectionClick {
    param ([string]$ServerName, [int]$Port)
    try {
        $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port
        $lblStatus.Text = "Connected to ${ServerName}:${Port}"
        $lblStatus.ForeColor = [System.Drawing.Color]::Green
        Log-Message "Connection test successful to ${ServerName}:${Port}" -MessageType INFO
    } catch {
        $lblStatus.Text = "Failed to connect to ${ServerName}:${Port}"
        $lblStatus.ForeColor = [System.Drawing.Color]::Red
        Log-Message "Connection test failed to ${ServerName}:${Port} - $_" -MessageType ERROR
    }
}

#endregion

#region --- GUI Bootstrapping

$form = New-Object System.Windows.Forms.Form
$form.Text = "WSUS Maintenance Tool"
$form.Size = New-Object System.Drawing.Size(670, 730)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSCommandPath)

$font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)

# --- Top Panel ---
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Size = New-Object System.Drawing.Size(640, 60)
$panelTop.Location = New-Object System.Drawing.Point(15, 10)
$panelTop.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelTop)

$lblServer = New-Object System.Windows.Forms.Label
$lblServer.Text = "WSUS Server:"
$lblServer.Location = New-Object System.Drawing.Point(10, 20)
$lblServer.Size = New-Object System.Drawing.Size(100, 20)
$lblServer.Font = $font
$panelTop.Controls.Add($lblServer)

$txtServer = New-Object System.Windows.Forms.TextBox
$txtServer.Text = "localhost"
$txtServer.Location = New-Object System.Drawing.Point(110, 18)
$txtServer.Size = New-Object System.Drawing.Size(180, 22)
$txtServer.Font = $font
$panelTop.Controls.Add($txtServer)

$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Port:"
$lblPort.Location = New-Object System.Drawing.Point(300, 20)
$lblPort.Size = New-Object System.Drawing.Size(35, 20)
$lblPort.Font = $font
$panelTop.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Text = "8530"
$txtPort.Location = New-Object System.Drawing.Point(340, 18)
$txtPort.Size = New-Object System.Drawing.Size(60, 22)
$txtPort.Font = $font
$panelTop.Controls.Add($txtPort)

$btnTestConnection = New-Object System.Windows.Forms.Button
$btnTestConnection.Text = "Test Connectivity"
$btnTestConnection.Location = New-Object System.Drawing.Point(410, 15)
$btnTestConnection.Size = New-Object System.Drawing.Size(135, 27)
$btnTestConnection.Font = $font
$btnTestConnection.Add_Click({
    Test-ConnectionClick -ServerName $txtServer.Text -Port ([int]$txtPort.Text)
})
$panelTop.Controls.Add($btnTestConnection)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready"
$lblStatus.Font = $font
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(560, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::Black
$panelTop.Controls.Add($lblStatus)

# --- Tab Control ---
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Size = New-Object System.Drawing.Size(640, 520)
$tabControl.Location = New-Object System.Drawing.Point(15, 80)
$tabControl.Font = $font
$form.Controls.Add($tabControl)

# Updates Tab
$tabUpdates = New-Object System.Windows.Forms.TabPage
$tabUpdates.Text = "Updates"
$tabControl.Controls.Add($tabUpdates)

$groupUpdates = New-Object System.Windows.Forms.GroupBox
$groupUpdates.Text = "Update Maintenance"
$groupUpdates.Size = New-Object System.Drawing.Size(590, 480)
$groupUpdates.Location = New-Object System.Drawing.Point(10, 10)
$groupUpdates.Font = $font
$tabUpdates.Controls.Add($groupUpdates)

$chkDeclineUnapproved = New-Object System.Windows.Forms.CheckBox
$chkDeclineUnapproved.Text = "Decline Unapproved Updates (older than 30 days)"
$chkDeclineUnapproved.Location = New-Object System.Drawing.Point(15, 25)
$chkDeclineUnapproved.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineUnapproved.Font = $font
$groupUpdates.Controls.Add($chkDeclineUnapproved)

$chkDeclineExpired = New-Object System.Windows.Forms.CheckBox
$chkDeclineExpired.Text = "Decline Expired Updates"
$chkDeclineExpired.Location = New-Object System.Drawing.Point(15, 50)
$chkDeclineExpired.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineExpired.Font = $font
$groupUpdates.Controls.Add($chkDeclineExpired)

$chkDeclineSuperseded = New-Object System.Windows.Forms.CheckBox
$chkDeclineSuperseded.Text = "Decline Superseded Updates"
$chkDeclineSuperseded.Location = New-Object System.Drawing.Point(15, 75)
$chkDeclineSuperseded.Size = New-Object System.Drawing.Size(560, 20)
$chkDeclineSuperseded.Font = $font
$groupUpdates.Controls.Add($chkDeclineSuperseded)

$chkRemoveClassifications = New-Object System.Windows.Forms.CheckBox
$chkRemoveClassifications.Text = "Decline Itanium/Windows XP Updates"
$chkRemoveClassifications.Location = New-Object System.Drawing.Point(15, 100)
$chkRemoveClassifications.Size = New-Object System.Drawing.Size(560, 20)
$chkRemoveClassifications.Font = $font
$groupUpdates.Controls.Add($chkRemoveClassifications)

# Maintenance Tab
$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Maintenance"
$tabControl.Controls.Add($tabMaintenance)

$groupWSUS = New-Object System.Windows.Forms.GroupBox
$groupWSUS.Text = "WSUS Cleanup Options"
$groupWSUS.Size = New-Object System.Drawing.Size(590, 230)
$groupWSUS.Location = New-Object System.Drawing.Point(10, 10)
$groupWSUS.Font = $font
$tabMaintenance.Controls.Add($groupWSUS)

$chkUnusedUpdates = New-Object System.Windows.Forms.CheckBox
$chkUnusedUpdates.Text = "Unused Updates and Revisions (excludes > 30 days)"
$chkUnusedUpdates.Location = New-Object System.Drawing.Point(15, 25)
$chkUnusedUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkUnusedUpdates.Font = $font
$groupWSUS.Controls.Add($chkUnusedUpdates)

$chkObsoleteComputers = New-Object System.Windows.Forms.CheckBox
$chkObsoleteComputers.Text = "Obsolete Computers (not contacted in 30+ days)"
$chkObsoleteComputers.Checked = $true
$chkObsoleteComputers.Location = New-Object System.Drawing.Point(15, 50)
$chkObsoleteComputers.Size = New-Object System.Drawing.Size(560, 20)
$chkObsoleteComputers.Font = $font
$groupWSUS.Controls.Add($chkObsoleteComputers)

$chkUnneededFiles = New-Object System.Windows.Forms.CheckBox
$chkUnneededFiles.Text = "Unneeded Update Files"
$chkUnneededFiles.Location = New-Object System.Drawing.Point(15, 75)
$chkUnneededFiles.Size = New-Object System.Drawing.Size(560, 20)
$chkUnneededFiles.Font = $font
$groupWSUS.Controls.Add($chkUnneededFiles)

$chkExpiredUpdates = New-Object System.Windows.Forms.CheckBox
$chkExpiredUpdates.Text = "Expired Updates (declines unapproved)"
$chkExpiredUpdates.Checked = $true
$chkExpiredUpdates.Location = New-Object System.Drawing.Point(15, 100)
$chkExpiredUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkExpiredUpdates.Font = $font
$groupWSUS.Controls.Add($chkExpiredUpdates)

$chkSupersededUpdates = New-Object System.Windows.Forms.CheckBox
$chkSupersededUpdates.Text = "Superseded Updates (declines > 30 days)"
$chkSupersededUpdates.Checked = $true
$chkSupersededUpdates.Location = New-Object System.Drawing.Point(15, 125)
$chkSupersededUpdates.Size = New-Object System.Drawing.Size(560, 20)
$chkSupersededUpdates.Font = $font
$groupWSUS.Controls.Add($chkSupersededUpdates)

$groupSQL = New-Object System.Windows.Forms.GroupBox
$groupSQL.Text = "SUSDB Maintenance Tasks"
$groupSQL.Size = New-Object System.Drawing.Size(590, 230)
$groupSQL.Location = New-Object System.Drawing.Point(10, 250)
$groupSQL.Font = $font
$tabMaintenance.Controls.Add($groupSQL)

$chkCheckDB = New-Object System.Windows.Forms.CheckBox
$chkCheckDB.Text = "Run DBCC CHECKDB"
$chkCheckDB.Location = New-Object System.Drawing.Point(15, 25)
$chkCheckDB.Size = New-Object System.Drawing.Size(560, 20)
$chkCheckDB.Font = $font
$groupSQL.Controls.Add($chkCheckDB)

$chkCheckFragmentation = New-Object System.Windows.Forms.CheckBox
$chkCheckFragmentation.Text = "Check Index Fragmentation"
$chkCheckFragmentation.Location = New-Object System.Drawing.Point(15, 50)
$chkCheckFragmentation.Size = New-Object System.Drawing.Size(560, 20)
$chkCheckFragmentation.Font = $font
$groupSQL.Controls.Add($chkCheckFragmentation)

$chkReindex = New-Object System.Windows.Forms.CheckBox
$chkReindex.Text = "Rebuild Indexes"
$chkReindex.Location = New-Object System.Drawing.Point(15, 75)
$chkReindex.Size = New-Object System.Drawing.Size(560, 20)
$chkReindex.Font = $font
$groupSQL.Controls.Add($chkReindex)

$chkShrink = New-Object System.Windows.Forms.CheckBox
$chkShrink.Text = "Shrink Database"
$chkShrink.Location = New-Object System.Drawing.Point(15, 100)
$chkShrink.Size = New-Object System.Drawing.Size(560, 20)
$chkShrink.Font = $font
$groupSQL.Controls.Add($chkShrink)

$chkBackup = New-Object System.Windows.Forms.CheckBox
$chkBackup.Text = "Backup SUSDB"
$chkBackup.Location = New-Object System.Drawing.Point(15, 125)
$chkBackup.Size = New-Object System.Drawing.Size(560, 20)
$chkBackup.Font = $font
$groupSQL.Controls.Add($chkBackup)

# Bottom Panel for Progress and Controls
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Size = New-Object System.Drawing.Size(640, 70)
$panelBottom.Location = New-Object System.Drawing.Point(15, 610)
$panelBottom.BorderStyle = 'FixedSingle'
$form.Controls.Add($panelBottom)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(10, 40)
$progress.Size = New-Object System.Drawing.Size(400, 20)
$progress.Minimum = 0
$progress.Maximum = 100
$panelBottom.Controls.Add($progress)

$statusBar = New-Object System.Windows.Forms.Label
$statusBar.Text = "Ready"
$statusBar.Location = New-Object System.Drawing.Point(420, 40)
$statusBar.Size = New-Object System.Drawing.Size(190, 20)
$statusBar.Font = $font
$panelBottom.Controls.Add($statusBar)

# Buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "&Run"
$btnRun.Size = New-Object System.Drawing.Size(80, 25)
$btnRun.Location = New-Object System.Drawing.Point(10, 10)
$btnRun.Font = $font
$panelBottom.Controls.Add($btnRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "&Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(80, 25)
$btnCancel.Location = New-Object System.Drawing.Point(100, 10)
$btnCancel.Font = $font
$panelBottom.Controls.Add($btnCancel)

$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "&Help"
$btnHelp.Size = New-Object System.Drawing.Size(80, 25)
$btnHelp.Location = New-Object System.Drawing.Point(190, 10)
$btnHelp.Font = $font
$panelBottom.Controls.Add($btnHelp)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "&Close"
$btnClose.Size = New-Object System.Drawing.Size(80, 25)
$btnClose.Location = New-Object System.Drawing.Point(540, 10)  # Slightly left for margin
$btnClose.Font = $font
$panelBottom.Controls.Add($btnClose)

$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, 4)
$runspacePool.Open()

$btnRun.Add_Click({
    try {
        $btnRun.Enabled = $false
        $btnCancel.Enabled = $false
        $btnHelp.Enabled = $false
        $btnClose.Enabled = $false
        $progress.Value = 0
        $statusBar.Text = "Starting WSUS maintenance..."
        Log-Message "Starting WSUS maintenance..." -MessageType INFO
        Save-Settings

        Validate-WSUSAssembly

        $selectedServer = $txtServer.Text
        $port = [int]$txtPort.Text
        Log-Message "Testing WSUS connection to ${selectedServer}:${port}..." -MessageType INFO
        $wsus = Test-WSUSConnection -ServerName $selectedServer -Port $port
        Log-Message "WSUS connection test passed." -MessageType INFO

        $tasks = @()
        if ($chkDeclineUnapproved.Checked) { $tasks += "DeclineUnapproved" }
        if ($chkDeclineExpired.Checked) { $tasks += "DeclineExpired" }
        if ($chkDeclineSuperseded.Checked) { $tasks += "DeclineSuperseded" }
        if ($chkRemoveClassifications.Checked) { $tasks += "RemoveClassifications" }
        if ($chkUnusedUpdates.Checked -or $chkObsoleteComputers.Checked -or $chkUnneededFiles.Checked -or $chkExpiredUpdates.Checked -or $chkSupersededUpdates.Checked) { $tasks += "WSUSCleanup" }
        if ($chkCheckDB.Checked) { $tasks += "CheckDB" }
        if ($chkCheckFragmentation.Checked) { $tasks += "CheckFragmentation" }
        if ($chkReindex.Checked) { $tasks += "Reindex" }
        if ($chkShrink.Checked) { $tasks += "ShrinkDB" }
        if ($chkBackup.Checked) { $tasks += "BackupDB" }

        $totalTasks = $tasks.Count
        if ($totalTasks -eq 0) {
            Log-Message "No tasks selected." -MessageType WARNING
            $statusBar.Text = "No tasks selected."
            [System.Windows.Forms.MessageBox]::Show("Please select at least one maintenance task.", "Warning", 'OK', 'Warning')
            return
        }

        $progress.Maximum = $totalTasks * 100
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $csvFile = Join-Path $Config.CsvDir "$scriptName-Declined-$timestamp.csv"
        $declined = @()

        $runspace = [PowerShell]::Create().AddScript({
            param($Tasks, $SelectedServer, $Port, $ChkDeclineUnapproved, $ChkDeclineExpired, $ChkDeclineSuperseded, $ChkRemoveClassifications, $ChkUnusedUpdates, $ChkObsoleteComputers, $ChkUnneededFiles, $ChkExpiredUpdates, $ChkSupersededUpdates, $ChkCheckDB, $ChkCheckFragmentation, $ChkReindex, $ChkShrink, $ChkBackup, $CsvFile, $LogPath, $BackupDir, $SqlScriptDir, $SqlcmdPath, $WsusUtilPath, $WsusAssemblyPath)

            $ErrorActionPreference = 'Stop'

            function Log-Message {
                param ([string]$Message, [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")][string]$MessageType = "INFO")
                $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                $entry = "[$stamp] [$MessageType] $Message"
                Add-Content -Path $LogPath -Value $entry -Encoding UTF8
            }

            function Test-WSUSConnection {
                param ([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($ServerName, $UseSSL, $Port)
                    Log-Message "Successfully connected to WSUS server: $ServerName" -MessageType INFO
                    return $wsus
                } catch {
                    Log-Message "Failed to connect to WSUS server ($ServerName): $_" -MessageType ERROR
                    throw
                }
            }

            function Decline-Updates {
                param ([string]$Type, [scriptblock]$Filter, [string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)
                    $updates = $wsus.SearchUpdates($scope) | Where-Object $Filter
                    if ($updates.Count -eq 0) { return @() }
                    Log-Message "$Type updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Log-Message "Declined $Type update: $($update.Title)" -MessageType INFO
                            $log += [PSCustomObject]@{ KB = $update.KnowledgeBaseArticles -join ","; Title = $update.Title; Type = $Type; Date = $update.CreationDate; DeclinedOn = Get-Date; Server = $ServerName }
                        } catch {
                            Log-Message "Failed to decline $Type update: $($update.Title) - $_" -MessageType ERROR
                        }
                    }
                    return $log
                } catch {
                    Log-Message "Error in Decline-Updates ($Type): $_" -MessageType ERROR
                    throw
                }
            }

            function Decline-ByClassification {
                param ([string]$ServerName, [int]$Port = 8530, [bool]$UseSSL = $false)
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
                    $scope.FromCreationDate = (Get-Date).AddDays(-365)
                    $classifications = @("Itanium", "Windows XP")
                    $updates = $wsus.SearchUpdates($scope) | Where-Object { $_.IsDeclined -eq $false -and ($_.Title -match ($classifications -join "|") -or $_.Description -match ($classifications -join "|")) }
                    if ($updates.Count -eq 0) { return @() }
                    Log-Message "Classification-based updates: Found $($updates.Count) updates. Declining..." -MessageType INFO
                    $log = @()
                    foreach ($update in $updates) {
                        try {
                            $update.Decline()
                            Log-Message "Declined classification-based update: $($update.Title)" -MessageType INFO
                            $log += [PSCustomObject]@{ KB = $update.KnowledgeBaseArticles -join ","; Title = $update.Title; Type = "Classification"; Date = $update.CreationDate; DeclinedOn = Get-Date; Server = $ServerName }
                        } catch {
                            Log-Message "Failed to decline classification-based update: $($update.Title) - $_" -MessageType ERROR
                        }
                    }
                    return $log
                } catch {
                    Log-Message "Error in Decline-ByClassification: $_" -MessageType ERROR
                    throw
                }
            }

            function Run-WSUSCleanup {
                param (
                    [bool]$IncludeUnusedUpdates,
                    [bool]$IncludeObsoleteComputers,
                    [bool]$IncludeUnneededFiles,
                    [bool]$IncludeExpiredUpdates,
                    [bool]$IncludeSupersededUpdates,
                    [string]$ServerName,
                    [int]$Port = 8530,
                    [bool]$UseSSL = $false
                )
                try {
                    $wsus = Test-WSUSConnection -ServerName $ServerName -Port $Port -UseSSL $UseSSL
                    $cleanup = $wsus.GetCleanupManager()
                    $steps = @()
                    if ($IncludeUnusedUpdates) {
                        $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::UnusedUpdatesAndUpdatesRevisions
                        Log-Message "Cleaning Unused Updates and Revisions (older than 30 days)..." -MessageType INFO
                    }
                    if ($IncludeObsoleteComputers) {
                        $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::ObsoleteComputers
                        Log-Message "Cleaning Obsolete Computers (not contacted in 30+ days)..." -MessageType INFO
                    }
                    if ($IncludeUnneededFiles) {
                        $steps += [Microsoft.UpdateServices.Administration.CleanupScope]::UnneededUpdateFiles
                        Log-Message "Cleaning Unneeded Update Files..." -MessageType INFO
                    }
                    if ($IncludeExpiredUpdates) {
                        $updates = $wsus.SearchUpdates((New-Object Microsoft.UpdateServices.Administration.UpdateScope)) | Where-Object { $_.IsExpired -and -not $_.IsDeclined -and -not $_.IsApproved }
                        if ($updates.Count -gt 0) {
                            foreach ($update in $updates) {
                                try {
                                    $update.Decline()
                                    Log-Message "Declined Expired Update: $($update.Title)" -MessageType INFO
                                } catch {
                                    Log-Message "Failed to decline Expired Update: $($update.Title) - $_" -MessageType ERROR
                                }
                            }
                        }
                        Log-Message "Checked for Expired Updates (declined if unapproved)..." -MessageType INFO
                    }
                    if ($IncludeSupersededUpdates) {
                        $updates = $wsus.SearchUpdates((New-Object Microsoft.UpdateServices.Administration.UpdateScope)) | Where-Object { $_.IsSuperseded -and -not $_.IsDeclined -and -not $_.IsApproved -and $_.CreationDate -lt (Get-Date).AddDays(-30) }
                        if ($updates.Count -gt 0) {
                            foreach ($update in $updates) {
                                try {
                                    $update.Decline()
                                    Log-Message "Declined Superseded Update: $($update.Title)" -MessageType INFO
                                } catch {
                                    Log-Message "Failed to decline Superseded Update: $($update.Title) - $_" -MessageType ERROR
                                }
                            }
                        }
                        Log-Message "Checked for Superseded Updates (declined if unapproved for 30+ days)..." -MessageType INFO
                    }
                    if ($steps.Count -gt 0) {
                        $success = $false
                        foreach ($step in $steps) {
                            try {
                                Log-Message "Running Cleanup Step: $step" -MessageType INFO
                                $cleanup.PerformCleanup($step)
                                Log-Message "Cleanup Step '$step' completed." -MessageType INFO
                                $success = $true
                            } catch {
                                Log-Message "Cleanup Step '$step' failed with assembly method: $_" -MessageType WARNING
                            }
                        }
                        if (-not $success -and (Test-Path $WsusUtilPath)) {
                            Log-Message "Falling back to wsusutil.exe for cleanup..." -MessageType INFO
                            $output = & $WsusUtilPath deleteunneededrevisions 2>&1
                            Log-Message "wsusutil.exe deleteunneededrevisions output: $output" -MessageType INFO
                            if ($IncludeUnneededFiles) {
                                $output = & $WsusUtilPath compress 2>&1
                                Log-Message "wsusutil.exe compress output: $output" -MessageType INFO
                            }
                            Log-Message "WSUS Cleanup completed using wsusutil.exe." -MessageType INFO
                        } elseif (-not $success) {
                            Log-Message "Error: No cleanup method succeeded and wsusutil.exe not found at $WsusUtilPath" -MessageType ERROR
                            throw "Cleanup failed"
                        }
                    }
                } catch {
                    Log-Message "Error in Run-WSUSCleanup: $_" -MessageType ERROR
                    throw
                }
            }

            function Run-WIDMaintenance {
                param ([bool]$DoCheckDB, [bool]$DoCheckFragmentation, [bool]$DoReindex, [bool]$DoShrink, [bool]$DoBackup)
                try {
                    $widPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"
                    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    if ($DoBackup) {
                        $backupFile = Join-Path $BackupDir "SUSDB-Backup-$timestamp.bak"
                        Log-Message "Backing up SUSDB to $backupFile..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "BACKUP DATABASE SUSDB TO DISK = '$backupFile' WITH INIT")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "Backup output: $output" -MessageType INFO
                    }
                    if ($DoCheckDB) {
                        Log-Message "Running DBCC CHECKDB..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC CHECKDB")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "DBCC CHECKDB output: $output" -MessageType INFO
                    }
                    if ($DoCheckFragmentation) {
                        $fragmentationScript = Join-Path $SqlScriptDir "wsus-verify-fragmentation.sql"
                        if (Test-Path $fragmentationScript) {
                            Log-Message "Checking Index Fragmentation with $fragmentationScript..." -MessageType INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$fragmentationScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Log-Message "Fragmentation Check output: $output" -MessageType INFO
                        } else {
                            Log-Message "Fragmentation script not found at $fragmentationScript" -MessageType WARNING
                        }
                    }
                    if ($DoReindex) {
                        $reindexScript = Join-Path $SqlScriptDir "wsus-reindex.sql"
                        if (Test-Path $reindexScript) {
                            Log-Message "Reindexing with $reindexScript..." -MessageType INFO
                            $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-i", "`"$reindexScript`"")
                            $output = & $SqlcmdPath $args 2>&1
                            Log-Message "Reindex output: $output" -MessageType INFO
                        } else {
                            Log-Message "Reindex script not found at $reindexScript" -MessageType WARNING
                        }
                    }
                    if ($DoShrink) {
                        Log-Message "Shrinking SUSDB..." -MessageType INFO
                        $args = @("-S", $widPipe, "-E", "-d", "SUSDB", "-Q", "DBCC SHRINKDATABASE (SUSDB, 10)")
                        $output = & $SqlcmdPath $args 2>&1
                        Log-Message "Shrink Database output: $output" -MessageType INFO
                    }
                } catch {
                    Log-Message "Error in Run-WIDMaintenance: $_" -MessageType ERROR
                    throw
                }
            }

            $declined = @()
            Log-Message "Runspace started for tasks: $($Tasks -join ', ')" -MessageType INFO
            foreach ($task in $Tasks) {
                Log-Message "Executing Task: $task" -MessageType INFO
                switch ($task) {
                    "DeclineUnapproved" { $declined += Decline-Updates -Type "Unapproved" -Filter { -not $_.IsApproved -and -not $_.IsDeclined -and $_.CreationDate -lt (Get-Date).AddDays(-30) } -ServerName $SelectedServer -Port $Port }
                    "DeclineExpired" { $declined += Decline-Updates -Type "Expired" -Filter { $_.IsExpired -and -not $_.IsDeclined } -ServerName $SelectedServer -Port $Port }
                    "DeclineSuperseded" { $declined += Decline-Updates -Type "Superseded" -Filter { $_.IsSuperseded -and -not $_.IsDeclined } -ServerName $SelectedServer -Port $Port }
                    "RemoveClassifications" { $declined += Decline-ByClassification -ServerName $SelectedServer -Port $Port }
                    "WSUSCleanup" { Run-WSUSCleanup -IncludeUnusedUpdates $ChkUnusedUpdates -IncludeObsoleteComputers $ChkObsoleteComputers -IncludeUnneededFiles $ChkUnneededFiles -IncludeExpiredUpdates $ChkExpiredUpdates -IncludeSupersededUpdates $ChkSupersededUpdates -ServerName $SelectedServer -Port $Port }
                    { $_ -in @("CheckDB", "CheckFragmentation", "Reindex", "ShrinkDB", "BackupDB") } {
                        Run-WIDMaintenance -DoCheckDB ($task -eq "CheckDB" -and $ChkCheckDB) -DoCheckFragmentation ($task -eq "CheckFragmentation" -and $ChkCheckFragmentation) -DoReindex ($task -eq "Reindex" -and $ChkReindex) -DoShrink ($task -eq "ShrinkDB" -and $ChkShrink) -DoBackup ($task -eq "BackupDB" -and $ChkBackup)
                    }
                }
            }
            if ($declined.Count -gt 0) {
                $declined | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
                Log-Message "Declined updates exported to $CsvFile" -MessageType INFO
            }
            Log-Message "Runspace execution completed." -MessageType INFO
            return $declined
        }).AddArgument($tasks).AddArgument($selectedServer).AddArgument($port).AddArgument($chkDeclineUnapproved.Checked).AddArgument($chkDeclineExpired.Checked).AddArgument($chkDeclineSuperseded.Checked).AddArgument($chkRemoveClassifications.Checked).AddArgument($chkUnusedUpdates.Checked).AddArgument($chkObsoleteComputers.Checked).AddArgument($chkUnneededFiles.Checked).AddArgument($chkExpiredUpdates.Checked).AddArgument($chkSupersededUpdates.Checked).AddArgument($chkCheckDB.Checked).AddArgument($chkCheckFragmentation.Checked).AddArgument($chkReindex.Checked).AddArgument($chkShrink.Checked).AddArgument($chkBackup.Checked).AddArgument($csvFile).AddArgument($logPath).AddArgument($Config.BackupDir).AddArgument($Config.SqlScriptDir).AddArgument($sqlcmdPath).AddArgument($Config.WsusUtilPath).AddArgument($Config.WsusAssemblyPath)
        $runspace.RunspacePool = $runspacePool
        $handle = $runspace.BeginInvoke()

        $taskDurations = @{
            "DeclineUnapproved" = 10; "DeclineExpired" = 10; "DeclineSuperseded" = 10; "RemoveClassifications" = 10
            "WSUSCleanup" = 20; "CheckDB" = 20; "CheckFragmentation" = 15; "Reindex" = 25; "ShrinkDB" = 20; "BackupDB" = 30
        }
        $totalDuration = ($tasks | ForEach-Object { $taskDurations[$_] } | Measure-Object -Sum).Sum
        $progressStep = 100 / $totalDuration
        $currentTime = 0

        while (-not $handle.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $currentTime += 0.5
            $progress.Value = [Math]::Min([int]($currentTime * $progressStep), $progress.Maximum)
            $statusBar.Text = "Running Task $currentTime seconds..."
            [System.Windows.Forms.Application]::DoEvents()
        }

        $result = $runspace.EndInvoke($handle)
        $runspace.Dispose()

        $progress.Value = $progress.Maximum
        $statusBar.Text = "Maintenance Complete. Log: $logPath"
        Log-Message "Maintenance complete." -MessageType INFO
        [System.Windows.Forms.MessageBox]::Show("Maintenance completed successfully.`nLog: $logPath`nCSV: $csvFile", "Complete", 'OK', 'Information')
    } catch {
        Log-Message "Execution failed: $_" -MessageType ERROR
        $statusBar.Text = "Maintenance Failed. Check log: $logPath"
        [System.Windows.Forms.MessageBox]::Show("Maintenance failed: $_`nLog: $logPath", "Error", 'OK', 'Error')
    } finally {
        $btnRun.Enabled = $true
        $btnCancel.Enabled = $true
        $btnHelp.Enabled = $true
        $btnClose.Enabled = $true
    }
})

$btnCancel.Add_Click({
    $statusBar.Text = "Operation Canceled."
    Log-Message "Operation canceled by user." -MessageType WARNING
    if ($runspace) {
        $runspace.Stop()
        $runspace.Dispose()
    }
    $progress.Value = 0
    $btnRun.Enabled = $true
    $btnCancel.Enabled = $true
    $btnHelp.Enabled = $true
    $btnClose.Enabled = $true
})

$btnHelp.Add_Click({
    [System.Windows.Forms.MessageBox]::Show("Help content goes here. Contact support for assistance.", "Help", 'OK', 'Information')
    Log-Message "Help button clicked." -MessageType INFO
})

$btnClose.Add_Click({
    Save-Settings
    $form.Close()
})

try {
    Load-Settings
    Log-Message "Starting WSUS Maintenance GUI" -MessageType INFO
    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
    Log-Message "WSUS Maintenance GUI closed" -MessageType INFO
} finally {
    Save-Settings
    $runspacePool.Close()
    $runspacePool.Dispose()
}

#endregion

# End of script
