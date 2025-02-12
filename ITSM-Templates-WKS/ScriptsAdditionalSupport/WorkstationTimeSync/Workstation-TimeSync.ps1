<#
.SYNOPSIS
    PowerShell Script for Synchronizing AD Computer Time Settings.

.DESCRIPTION
    This script synchronizes time settings across Active Directory computers, ensuring accurate 
    time configurations across different time zones and maintaining consistency in network time.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: February 12, 2025
#>

function Hide-ConsoleWindow {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Window {
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll", SetLastError = true)]
        static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        public static void Hide() {
            var handle = GetConsoleWindow();
            ShowWindow(handle, 0);
        }
    }
"@
    [Window]::Hide()
}

function Set-ExecutionPreferences {
    $global:WarningPreference = 'SilentlyContinue'
    $global:VerbosePreference = 'SilentlyContinue'
    $global:DebugPreference = 'SilentlyContinue'
}

function Initialize-LogFile {
    param (
        [string]$LogDirectory = 'C:\ITSM-Logs-WKS',
        [string]$ScriptName
    )

    if (-not (Test-Path $LogDirectory)) {
        try {
            New-Item -Path $LogDirectory -ItemType Directory -ErrorAction Stop | Out-Null
        } catch {
            Write-Error "Failed to create log directory at ${LogDirectory}. Logging will not be possible."
            return $null
        }
    }
    
    $logFilePath = Join-Path $LogDirectory "${ScriptName}.log"
    return $logFilePath
}

function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")][string]$MessageType = "INFO",
        [string]$LogPath
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    
    try {
        Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Write-Log -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

function Display-TimeSyncForm {
    param (
        [string]$LogPath
    )
   
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Time Synchronization Tool'
    $form.Size = New-Object System.Drawing.Size(380, 220)
    $form.StartPosition = 'CenterScreen'

    $labelTimeZone = New-Object System.Windows.Forms.Label
    $labelTimeZone.Text = 'Select Time Zone:'
    $labelTimeZone.Location = New-Object System.Drawing.Point(10, 20)
    $labelTimeZone.Size = New-Object System.Drawing.Size(120, 20)
    $form.Controls.Add($labelTimeZone)

    $comboBoxTimeZone = New-Object System.Windows.Forms.ComboBox
    $comboBoxTimeZone.Location = New-Object System.Drawing.Point(130, 20)
    $comboBoxTimeZone.Size = New-Object System.Drawing.Size(220, 20)
    $comboBoxTimeZone.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    [System.TimeZoneInfo]::GetSystemTimeZones() | ForEach-Object {
        $comboBoxTimeZone.Items.Add("$($_.DisplayName) [ID: $($_.Id)]")
    }
    $form.Controls.Add($comboBoxTimeZone)

    $radioButtonLocalServer = New-Object System.Windows.Forms.RadioButton
    $radioButtonLocalServer.Text = 'Local Domain Server'
    $radioButtonLocalServer.Location = New-Object System.Drawing.Point(10, 60)
    $radioButtonLocalServer.Size = New-Object System.Drawing.Size(180, 20)
    $radioButtonLocalServer.Checked = $true
    $form.Controls.Add($radioButtonLocalServer)

    $radioButtonCustomServer = New-Object System.Windows.Forms.RadioButton
    $radioButtonCustomServer.Text = 'Custom Time Server'
    $radioButtonCustomServer.Location = New-Object System.Drawing.Point(10, 90)
    $radioButtonCustomServer.Size = New-Object System.Drawing.Size(130, 20)
    $form.Controls.Add($radioButtonCustomServer)

    $textBoxTimeServer = New-Object System.Windows.Forms.TextBox
    $textBoxTimeServer.Location = New-Object System.Drawing.Point(140, 90)
    $textBoxTimeServer.Size = New-Object System.Drawing.Size(210, 20)
    $textBoxTimeServer.Enabled = $false
    $form.Controls.Add($textBoxTimeServer)

    $radioButtonLocalServer.Add_CheckedChanged({ $textBoxTimeServer.Enabled = $false })
    $radioButtonCustomServer.Add_CheckedChanged({ 
        $textBoxTimeServer.Enabled = $true
        $textBoxTimeServer.Focus() 
    })

    $buttonUpdate = New-Object System.Windows.Forms.Button
    $buttonUpdate.Text = 'Synchronize'
    $buttonUpdate.Location = New-Object System.Drawing.Point(130, 130)
    $buttonUpdate.Size = New-Object System.Drawing.Size(100, 30)
    $buttonUpdate.Add_Click({

        if (-not $comboBoxTimeZone.SelectedItem) {
            [System.Windows.Forms.MessageBox]::Show("Please select a time zone.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        $comboBoxTimeZone.SelectedItem -match '$$ID: (.+?)$$' | Out-Null
        $timeZoneId = $Matches[1]

        try {
            tzutil /s $timeZoneId
            Write-Log -Message "Time zone set to $timeZoneId" -MessageType "INFO" -LogPath $LogPath
        } catch {
            Handle-Error -ErrorMessage "Failed to set time zone to $timeZoneId"
            return
        }

        $timeServer = if ($radioButtonLocalServer.Checked) { $env:USERDNSDOMAIN } else { $textBoxTimeServer.Text }
        if ($radioButtonCustomServer.Checked -and [string]::IsNullOrWhiteSpace($timeServer)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a valid time server address.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }

        try {
            w32tm /config /manualpeerlist:$timeServer /syncfromflags:manual /reliable:yes /update | Out-Null
            w32tm /resync /rediscover | Out-Null
            Write-Log -Message "Time synchronized with server $timeServer." -MessageType "INFO" -LogPath $LogPath
            [System.Windows.Forms.MessageBox]::Show("Time zone updated and synchronized with server: $timeServer.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            Handle-Error -ErrorMessage "Failed to synchronize time with server $timeServer."
        }
    })
    $form.Controls.Add($buttonUpdate)

    $form.Add_Shown({ $form.Activate() })
    $form.ShowDialog()
}

# Main Script Execution
Hide-ConsoleWindow
Set-ExecutionPreferences

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logPath = Initialize-LogFile -ScriptName $scriptName

Write-Log -Message "Starting Time Synchronization Tool." -MessageType "INFO" -LogPath $logPath
Display-TimeSyncForm -LogPath $logPath
Write-Log -Message "Time Synchronization Tool session ended." -MessageType "INFO" -LogPath $logPath

# End of script
