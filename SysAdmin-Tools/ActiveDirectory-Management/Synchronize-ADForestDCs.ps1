<#
.SYNOPSIS
    PowerShell Script for Synchronizing Domain Controllers Across an AD Forest.

.DESCRIPTION
    Automates the synchronization of all Domain Controllers (DCs) across an Active Directory (AD) forest.
    Ensures replication is triggered and up-to-date.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    UX Enhanced Edition – July 24, 2025
#>

#region ── Hide Console Window ──
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Window]::ShowWindow([Window]::GetConsoleWindow(), 0)
#endregion

#region ── Load Required Types ──
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
#endregion

#region ── Logging Setup ──
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFile = Join-Path $logDir "${scriptName}.log"

if (-not (Test-Path $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch {}
}

function Log-Message {
    param (
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','ERROR','WARN')] [string]$Type = 'INFO'
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Type] $Message"

    try {
        Add-Content -Path $logFile -Value $entry
        $global:logBox.SelectionStart = $global:logBox.TextLength
        $global:logBox.SelectionColor = switch ($Type) {
            'ERROR' { 'Red' }
            'WARN'  { 'DarkOrange' }
            'INFO'  { 'Black' }
        }
        $global:logBox.AppendText("$entry`r`n")
        $global:logBox.ScrollToCaret()
    } catch {
        Write-Error "Log error: $_"
    }
}
#endregion

#region ── Core Functions ──
function Sync-AllDCs {
    Log-Message "Sync process started"
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $forest = Get-ADForest
        $domains = $forest.Domains
    } catch {
        Log-Message "Failed to load forest info: $_" -Type 'ERROR'
        [System.Windows.Forms.MessageBox]::Show("Could not retrieve domains. See log.", "Error", "OK", "Error")
        return
    }

    $allDCs = @()
    foreach ($domain in $domains) {
        try {
            $allDCs += Get-ADDomainController -Filter * -Server $domain
        } catch {
            Log-Message "Error retrieving DCs for ${domain}: $_" -Type 'ERROR'
        }
    }

    foreach ($dc in $allDCs) {
        $name = $dc.HostName
        Log-Message "Syncing $name"
        try {
            $output = & repadmin /syncall /e /A /P /d /q $name
            Log-Message "Result: $output"
        } catch {
            Log-Message "Sync error for ${name}: $_" -Type 'ERROR'
        }
    }

    Log-Message "Sync completed"
    [System.Windows.Forms.MessageBox]::Show("Sync completed. See log for details.", "Info", "OK", "Information")
}

function Show-Log {
    Start-Process notepad.exe $logFile
}

function Show-ReplSummary {
    Log-Message "Running replsummary"
    try {
        $summary = & repadmin /replsummary
        $summary -split "`r`n" | ForEach-Object {
            $global:logBox.AppendText("$_`r`n")
        }
        $global:logBox.ScrollToCaret()
        Log-Message "replsummary complete"
    } catch {
        Log-Message "Error running replsummary: $_" -Type 'ERROR'
        [System.Windows.Forms.MessageBox]::Show("Error running replsummary. See log.", "Error", "OK", "Error")
    }
}
#endregion

#region ── GUI Setup ──

$form = New-Object Windows.Forms.Form -Property @{
    Text            = "AD Forest Sync Tool"
    Size            = '800,660'
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'
    MaximizeBox     = $false
}

# Status bar
$statusStrip = New-Object Windows.Forms.StatusStrip
$statusLabel = New-Object Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = "Ready"
$statusStrip.Items.Add($statusLabel)
$form.Controls.Add($statusStrip)

# RichTextBox for logs
$global:logBox = New-Object Windows.Forms.RichTextBox -Property @{
    Location   = '10,10'
    Size       = '760,500'
    ReadOnly   = $true
    Font       = New-Object Drawing.Font("Consolas", 9)
    WordWrap   = $false
    ScrollBars = "Vertical"
}
$form.Controls.Add($global:logBox)

# Button: Sync
$syncBtn = New-Object Windows.Forms.Button -Property @{
    Text     = "Sync All Forest DCs"
    Location = '50,520'
    Size     = '150,50'
}
$syncBtn.Add_Click({
    $syncBtn.Enabled = $false
    $statusLabel.Text = "Syncing domain controllers..."
    try {
        Sync-AllDCs
        $statusLabel.Text = "Sync completed"
    } finally {
        $syncBtn.Enabled = $true
    }
})
$form.Controls.Add($syncBtn)

# Button: View Logs
$logBtn = New-Object Windows.Forms.Button -Property @{
    Text     = "View Output Logs"
    Location = '250,520'
    Size     = '150,50'
}
$logBtn.Add_Click({ Show-Log })
$form.Controls.Add($logBtn)

# Button: Show Replication Summary
$replBtn = New-Object Windows.Forms.Button -Property @{
    Text     = "Show Replication Summary"
    Location = '450,520'
    Size     = '250,50'
}
$replBtn.Add_Click({
    $replBtn.Enabled = $false
    $statusLabel.Text = "Running replication summary..."
    try {
        Show-ReplSummary
        $statusLabel.Text = "Replication summary complete"
    } finally {
        $replBtn.Enabled = $true
    }
})
$form.Controls.Add($replBtn)

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
#endregion

# ── End of Script ──
