<#
.SYNOPSIS
    PowerShell GUI Tool for Synchronizing Domain Controllers Across an AD Forest.

.DESCRIPTION
    Functional baseline tool (WinForms) enhanced with:
    - Domain + DC selection (CheckedListBox) with Refresh
    - Progress bar + "Current DC" indicator
    - Cancel (graceful stop)
    - Log UX: Clear, Copy, Save-As
    - Keeps the original working replication logic style (repadmin via call operator, Out-String capture)

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Functional Baseline + GUI Enhancements – 2026-02-09
#>

#region --- Hide Console Window (optional) --- 
param(
    [switch]$ShowConsole
)

if (-not $ShowConsole) {
    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
        [Window]::ShowWindow([Window]::GetConsoleWindow(), 0) | Out-Null
    } catch {
        # Non-fatal
    }
}
#endregion

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region --- Load Required Types --- 
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
#endregion

#region --- Paths + Logging Setup --- 
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir     = 'C:\Logs-TEMP'
$logFile    = Join-Path -Path $logDir -ChildPath ("{0}.log" -f $scriptName)

if (-not (Test-Path -LiteralPath $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch {}
}

# Script-scoped flags / state
$script:CancelRequested = $false
$script:IsBusy          = $false
$script:DiscoveredDomains = @()
$script:DiscoveredDCs     = @()  # objects from Get-ADDomainController

function Convert-ToSafeString {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return "" }
    if ($Value -is [System.Array]) {
        try { return ($Value | ForEach-Object { [string]$_ }) -join [Environment]::NewLine } catch { return [string]$Value }
    }
    return [string]$Value
}

function Log-Message {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','ERROR','WARN')][string]$Type = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[{0}] [{1}] {2}" -f $timestamp, $Type, $Message

    # File
    try { Add-Content -Path $logFile -Value $entry -ErrorAction Stop } catch {}

    # UI (only if initialized)
    if ($global:logBox -and -not $global:logBox.IsDisposed) {
        try {
            $global:logBox.SelectionStart  = $global:logBox.TextLength
            $global:logBox.SelectionLength = 0

            $global:logBox.SelectionColor = switch ($Type) {
                'ERROR' { [System.Drawing.Color]::Red }
                'WARN'  { [System.Drawing.Color]::DarkOrange }
                default { [System.Drawing.Color]::Black }
            }

            $global:logBox.AppendText(("{0}`r`n" -f $entry))
            $global:logBox.SelectionColor = [System.Drawing.Color]::Black
            $global:logBox.ScrollToCaret()
        } catch { }
    }
}

function Set-Status {
    param([Parameter(Mandatory)][string]$Text)
    if ($script:statusLabel -and -not $script:statusLabel.IsDisposed) {
        try { $script:statusLabel.Text = $Text } catch { }
    }
}

function Set-CurrentDC {
    param([string]$Text)
    if ($script:lblCurrentDc -and -not $script:lblCurrentDc.IsDisposed) {
        try { $script:lblCurrentDc.Text = $Text } catch { }
    }
}

function Set-Progress {
    param([int]$Value, [int]$Max)
    if ($script:progress -and -not $script:progress.IsDisposed) {
        try {
            if ($Max -gt 0) {
                $script:progress.Maximum = $Max
                if ($Value -lt 0) { $Value = 0 }
                if ($Value -gt $Max) { $Value = $Max }
                $script:progress.Value = $Value
            } else {
                $script:progress.Value = 0
            }
        } catch { }
    }
}

function Show-UiMessage {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Title = "AD Forest Sync Tool",
        [ValidateSet('Information','Warning','Error')][string]$Icon = 'Information'
    )

    $mbIcon = switch ($Icon) {
        'Information' { [System.Windows.Forms.MessageBoxIcon]::Information }
        'Warning'     { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'       { [System.Windows.Forms.MessageBoxIcon]::Error }
    }

    [void][System.Windows.Forms.MessageBox]::Show(
        $Text,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $mbIcon
    )
}
#endregion

#region --- AD Discovery Helpers --- 
function Ensure-Dependencies {
    # ActiveDirectory module
    try { Import-Module ActiveDirectory -ErrorAction Stop } catch {
        Log-Message ("Failed to load ActiveDirectory module: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
        Show-UiMessage -Text "ActiveDirectory module could not be loaded. See log." -Icon Error
        return $false
    }

    # repadmin
    try { $script:repadminPath = (Get-Command repadmin.exe -ErrorAction Stop).Source } catch { $script:repadminPath = $null }
    if (-not $script:repadminPath) {
        Log-Message "repadmin.exe not found in PATH. Cannot continue." -Type 'ERROR'
        Show-UiMessage -Text "repadmin.exe was not found. Install RSAT/AD tools or fix PATH." -Icon Error
        return $false
    }

    return $true
}

function Refresh-Discovery {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true
    try {
        Set-Status "Refreshing domains and DCs..."
        Set-CurrentDC "Current DC: (none)"
        Set-Progress -Value 0 -Max 1
        [System.Windows.Forms.Application]::DoEvents()

        if (-not (Ensure-Dependencies)) { return }

        $forest = $null
        try { $forest = Get-ADForest -ErrorAction Stop } catch {
            Log-Message ("Failed to load forest info: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
            Show-UiMessage -Text "Could not retrieve forest domains. See log." -Icon Error
            return
        }

        $script:DiscoveredDomains = @($forest.Domains)
        $script:DiscoveredDCs     = @()

        # Fill domains UI
        if ($script:clbDomains) {
            $script:clbDomains.BeginUpdate()
            try {
                $script:clbDomains.Items.Clear()
                foreach ($d in $script:DiscoveredDomains) {
                    [void]$script:clbDomains.Items.Add([string]$d, $true)  # default all checked
                }
            } finally { $script:clbDomains.EndUpdate() }
        }

        # Enumerate DCs for all domains (default selection)
        foreach ($domain in $script:DiscoveredDomains) {
            try {
                $dcs = Get-ADDomainController -Filter * -Server $domain -ErrorAction Stop
                $script:DiscoveredDCs += @($dcs)
                Log-Message ("Discovered {0} DC(s) in {1}" -f @($dcs).Count, $domain) -Type 'INFO'
            } catch {
                Log-Message ("Error retrieving DCs for {0}: {1}" -f $domain, (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
            }
        }

        # Fill DCs UI
        if ($script:clbDcs) {
            $script:clbDcs.BeginUpdate()
            try {
                $script:clbDcs.Items.Clear()

                # Use HostName for display; de-dup
                $seen = @{}
                foreach ($dc in @($script:DiscoveredDCs)) {
                    $hn = Convert-ToSafeString $dc.HostName
                    if ([string]::IsNullOrWhiteSpace($hn)) { continue }
                    if (-not $seen.ContainsKey($hn)) {
                        $seen[$hn] = $true
                        [void]$script:clbDcs.Items.Add($hn, $true) # default all checked
                    }
                }
            } finally { $script:clbDcs.EndUpdate() }
        }

        Set-Status "Ready"
        Log-Message ("Discovery refreshed. Domains={0}, DCs={1}" -f @($script:DiscoveredDomains).Count, @($script:DiscoveredDCs).Count) -Type 'INFO'
    } finally {
        $script:IsBusy = $false
    }
}

function Get-SelectedDomains {
    if (-not $script:clbDomains) { return @($script:DiscoveredDomains) }
    $sel = @()
    foreach ($i in 0..($script:clbDomains.Items.Count-1)) {
        if ($script:clbDomains.GetItemChecked($i)) { $sel += [string]$script:clbDomains.Items[$i] }
    }
    if (@($sel).Count -lt 1) { return @($script:DiscoveredDomains) }
    return @($sel)
}

function Get-SelectedDCNames {
    if (-not $script:clbDcs) {
        # fallback from discovered objects
        return @($script:DiscoveredDCs | ForEach-Object { Convert-ToSafeString $_.HostName } | Where-Object { $_ })
    }

    $sel = @()
    foreach ($i in 0..($script:clbDcs.Items.Count-1)) {
        if ($script:clbDcs.GetItemChecked($i)) { $sel += [string]$script:clbDcs.Items[$i] }
    }
    if (@($sel).Count -lt 1) {
        # None checked => treat as "all"
        foreach ($i in 0..($script:clbDcs.Items.Count-1)) { $sel += [string]$script:clbDcs.Items[$i] }
    }
    return @($sel)
}
#endregion

#region --- Core Actions --- 
function Sync-AllDCs {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true
    $script:CancelRequested = $false

    try {
        Log-Message "Sync process started" -Type 'INFO'
        Set-Status "Preparing..."
        Set-CurrentDC "Current DC: (starting)"
        Set-Progress -Value 0 -Max 1
        [System.Windows.Forms.Application]::DoEvents()

        if (-not (Ensure-Dependencies)) { return }

        # Rebuild DC list from selected domains (avoids stale data)
        $domains = Get-SelectedDomains
        $allDCs  = @()

        foreach ($domain in @($domains)) {
            try {
                $dcs = Get-ADDomainController -Filter * -Server $domain -ErrorAction Stop
                $allDCs += @($dcs)
                Log-Message ("Discovered {0} DC(s) in {1}" -f @($dcs).Count, $domain) -Type 'INFO'
            } catch {
                Log-Message ("Error retrieving DCs for {0}: {1}" -f $domain, (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
            }
        }

        if (@($allDCs).Count -lt 1) {
            Log-Message "No domain controllers discovered. Aborting." -Type 'ERROR'
            Show-UiMessage -Text "No domain controllers were discovered. See log." -Icon Error
            return
        }

        # Apply DC checkbox selection (by hostname)
        $selectedNames = Get-SelectedDCNames
        $selectedSet = @{}
        foreach ($n in @($selectedNames)) { if ($n) { $selectedSet[[string]$n] = $true } }

        $targets = @()
        foreach ($dc in @($allDCs)) {
            $hn = Convert-ToSafeString $dc.HostName
            if ($hn -and $selectedSet.ContainsKey($hn)) { $targets += $dc }
        }

        if (@($targets).Count -lt 1) {
            # If selection didn't match (e.g., DC list stale), fall back to all
            $targets = @($allDCs)
        }

        $total = @($targets).Count
        Set-Status ("Syncing {0} DC(s)..." -f $total)
        Set-Progress -Value 0 -Max $total
        [System.Windows.Forms.Application]::DoEvents()

        $idx = 0
        foreach ($dc in @($targets)) {
            if ($script:CancelRequested) {
                Log-Message "Sync cancelled by user." -Type 'WARN'
                Set-Status "Cancelled"
                Set-CurrentDC "Current DC: (cancelled)"
                return
            }

            $idx++
            $name = Convert-ToSafeString $dc.HostName
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            Set-CurrentDC ("Current DC: {0} ({1}/{2})" -f $name, $idx, $total)
            Set-Progress -Value $idx -Max $total
            [System.Windows.Forms.Application]::DoEvents()

            Log-Message ("Syncing {0}" -f $name) -Type 'INFO'

            try {
                # Capture multi-line output deterministically
                $output = & $script:repadminPath /syncall /e /A /P /d /q $name 2>&1 | Out-String
                $output = (Convert-ToSafeString $output).Trim()

                if ($output) {
                    Log-Message ("Result: {0}" -f $output) -Type 'INFO'
                } else {
                    Log-Message "Result: OK (no output)" -Type 'INFO'
                }
            } catch {
                Log-Message ("Sync error for {0}: {1}" -f $name, (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
            }
        }

        Log-Message "Sync completed" -Type 'INFO'
        Set-Status "Sync completed"
        Set-CurrentDC "Current DC: (done)"
        Show-UiMessage -Text "Sync completed. See log for details." -Icon Information
    } catch {
        Log-Message ("Unhandled error: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
        Show-UiMessage -Text "An unexpected error occurred. See log." -Icon Error
        Set-Status "Error"
        Set-CurrentDC "Current DC: (error)"
    } finally {
        $script:IsBusy = $false
        $script:CancelRequested = $false
    }
}

function Show-Log {
    try {
        Start-Process -FilePath notepad.exe -ArgumentList @("`"$logFile`"") | Out-Null
    } catch {
        Log-Message ("Failed to open log: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
    }
}

function Show-ReplSummary {
    if ($script:IsBusy) { return }
    $script:IsBusy = $true

    try {
        Log-Message "Running replsummary" -Type 'INFO'
        Set-Status "Running replication summary..."

        if (-not (Ensure-Dependencies)) { return }

        $summary = & $script:repadminPath /replsummary 2>&1 | Out-String
        $summary = Convert-ToSafeString $summary

        if ($global:logBox -and -not $global:logBox.IsDisposed) {
            $global:logBox.AppendText("`r`n=== repadmin /replsummary ===`r`n")
            $global:logBox.AppendText($summary)
            $global:logBox.AppendText("`r`n=== end replsummary ===`r`n`r`n")
            $global:logBox.ScrollToCaret()
        }

        Log-Message "replsummary complete" -Type 'INFO'
        Set-Status "Replication summary complete"
    } catch {
        Log-Message ("Error running replsummary: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
        Show-UiMessage -Text "Error running replsummary. See log." -Icon Error
        Set-Status "Error"
    } finally {
        $script:IsBusy = $false
    }
}

function Clear-LogPane {
    if ($global:logBox -and -not $global:logBox.IsDisposed) {
        try { $global:logBox.Clear() } catch { }
    }
    Log-Message "Log pane cleared." -Type 'INFO'
}

function Copy-LogSelection {
    if ($global:logBox -and -not $global:logBox.IsDisposed) {
        try {
            if ($global:logBox.SelectedText) {
                [System.Windows.Forms.Clipboard]::SetText($global:logBox.SelectedText)
            } else {
                [System.Windows.Forms.Clipboard]::SetText($global:logBox.Text)
            }
            Log-Message "Log copied to clipboard." -Type 'INFO'
        } catch {
            Log-Message ("Failed to copy log: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
        }
    }
}

function Save-LogAs {
    try {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = "Save Log As"
        $dlg.Filter = "Text Files (*.txt)|*.txt|Log Files (*.log)|*.log|All Files (*.*)|*.*"
        $dlg.FileName = ("{0}_{1}.txt" -f $scriptName, (Get-Date -Format "yyyyMMdd-HHmmss"))

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $text = if ($global:logBox) { Convert-ToSafeString $global:logBox.Text } else { "" }
            [System.IO.File]::WriteAllText($dlg.FileName, $text, [System.Text.Encoding]::UTF8)
            Log-Message ("Saved log to: {0}" -f $dlg.FileName) -Type 'INFO'
        }
    } catch {
        Log-Message ("Failed to save log: {0}" -f (Convert-ToSafeString $_.Exception.Message)) -Type 'ERROR'
    }
}
#endregion

#region --- GUI Setup --- 
$form = New-Object System.Windows.Forms.Form -Property @{
    Text            = "AD Forest Sync Tool"
    StartPosition   = 'CenterScreen'
    FormBorderStyle = 'FixedDialog'
    MaximizeBox     = $false
    ClientSize      = New-Object System.Drawing.Size(980, 700)
}

# Status bar
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$script:statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$script:statusLabel.Text = "Ready"
$null = $statusStrip.Items.Add($script:statusLabel)
$form.Controls.Add($statusStrip)

# Left: selection group (Domains + DCs)
$grpSel = New-Object System.Windows.Forms.GroupBox -Property @{
    Text     = "Scope Selection"
    Location = New-Object System.Drawing.Point(10, 10)
    Size     = New-Object System.Drawing.Size(300, 610)
}

$lblDomains = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Domains"
    Location = New-Object System.Drawing.Point(12, 25)
    AutoSize = $true
}
$grpSel.Controls.Add($lblDomains)

$script:clbDomains = New-Object System.Windows.Forms.CheckedListBox -Property @{
    Location = New-Object System.Drawing.Point(12, 45)
    Size     = New-Object System.Drawing.Size(275, 170)
    CheckOnClick = $true
}
$grpSel.Controls.Add($script:clbDomains)

$lblDcs = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Domain Controllers (HostName)"
    Location = New-Object System.Drawing.Point(12, 225)
    AutoSize = $true
}
$grpSel.Controls.Add($lblDcs)

$script:clbDcs = New-Object System.Windows.Forms.CheckedListBox -Property @{
    Location = New-Object System.Drawing.Point(12, 245)
    Size     = New-Object System.Drawing.Size(275, 300)
    CheckOnClick = $true
}
$grpSel.Controls.Add($script:clbDcs)

$btnRefresh = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Refresh"
    Location = New-Object System.Drawing.Point(12, 555)
    Size     = New-Object System.Drawing.Size(90, 35)
}
$btnRefresh.Add_Click({ Refresh-Discovery })
$grpSel.Controls.Add($btnRefresh)

$btnAll = New-Object System.Windows.Forms.Button -Property @{
    Text     = "All"
    Location = New-Object System.Drawing.Point(112, 555)
    Size     = New-Object System.Drawing.size(55, 35)
}
$btnAll.Add_Click({
    if ($script:clbDomains) { for ($i=0; $i -lt $script:clbDomains.Items.Count; $i++) { $script:clbDomains.SetItemChecked($i, $true) } }
    if ($script:clbDcs)     { for ($i=0; $i -lt $script:clbDcs.Items.Count; $i++)     { $script:clbDcs.SetItemChecked($i, $true) } }
    Log-Message "Selection set: ALL" -Type 'INFO'
})
$grpSel.Controls.Add($btnAll)

$btnNone = New-Object System.Windows.Forms.Button -Property @{
    Text     = "None"
    Location = New-Object System.Drawing.Point(177, 555)
    Size     = New-Object System.Drawing.Size(55, 35)
}
$btnNone.Add_Click({
    if ($script:clbDomains) { for ($i=0; $i -lt $script:clbDomains.Items.Count; $i++) { $script:clbDomains.SetItemChecked($i, $false) } }
    if ($script:clbDcs)     { for ($i=0; $i -lt $script:clbDcs.Items.Count; $i++)     { $script:clbDcs.SetItemChecked($i, $false) } }
    Log-Message "Selection set: NONE" -Type 'INFO'
})
$grpSel.Controls.Add($btnNone)

$form.Controls.Add($grpSel)

# Right: log group
$grpLog = New-Object System.Windows.Forms.GroupBox -Property @{
    Text     = "Execution Log"
    Location = New-Object System.Drawing.Point(320, 10)
    Size     = New-Object System.Drawing.Size(650, 610)
}
$form.Controls.Add($grpLog)

# RichTextBox for logs
$global:logBox = New-Object System.Windows.Forms.RichTextBox -Property @{
    Location   = New-Object System.Drawing.Point(12, 25)
    Size       = New-Object System.Drawing.Size(625, 470)
    ReadOnly   = $true
    Font       = New-Object System.Drawing.Font("Consolas", 9)
    WordWrap   = $false
    ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
}
$grpLog.Controls.Add($global:logBox)

# Current DC label
$script:lblCurrentDc = New-Object System.Windows.Forms.Label -Property @{
    Text     = "Current DC: (none)"
    Location = New-Object System.Drawing.Point(12, 505)
    AutoSize = $true
}
$grpLog.Controls.Add($script:lblCurrentDc)

# Progress bar
$script:progress = New-Object System.Windows.Forms.ProgressBar -Property @{
    Location = New-Object System.Drawing.Point(12, 530)
    Size     = New-Object System.Drawing.Size(625, 18)
    Minimum  = 0
    Maximum  = 1
    Value    = 0
}
$grpLog.Controls.Add($script:progress)

# Log utility buttons row
$btnClear = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Clear"
    Location = New-Object System.Drawing.Point(12, 555)
    Size     = New-Object System.Drawing.Size(80, 35)
}
$btnClear.Add_Click({ Clear-LogPane })
$grpLog.Controls.Add($btnClear)

$btnCopy = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Copy"
    Location = New-Object System.Drawing.Point(100, 555)
    Size     = New-Object System.Drawing.Size(80, 35)
}
$btnCopy.Add_Click({ Copy-LogSelection })
$grpLog.Controls.Add($btnCopy)

$btnSave = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Save As..."
    Location = New-Object System.Drawing.Point(188, 555)
    Size     = New-Object System.Drawing.Size(90, 35)
}
$btnSave.Add_Click({ Save-LogAs })
$grpLog.Controls.Add($btnSave)

#endregion

#region --- Bottom Action Buttons (aligned) --- 
# Bottom row buttons (outside groups)
$btnY  = 630
$btnH  = 45
$gap   = 12
$leftX = 10

$syncBtn = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Sync Selected DCs"
    Location = New-Object System.Drawing.Point($leftX, $btnY)
    Size     = New-Object System.Drawing.Size(200, $btnH)
}
$syncBtn.Add_Click({
    if ($script:IsBusy) { return }
    $syncBtn.Enabled = $false
    try {
        Set-Status "Syncing..."
        Sync-AllDCs
    } finally {
        $syncBtn.Enabled = $true
    }
})
$form.Controls.Add($syncBtn)

$cancelBtn = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Cancel"
    Location = New-Object System.Drawing.Point(($leftX + 200 + $gap), $btnY)
    Size     = New-Object System.Drawing.Size(120, $btnH)
    Enabled  = $true
}
$cancelBtn.Add_Click({
    if (-not $script:IsBusy) { return }
    $script:CancelRequested = $true
    Log-Message "Cancel requested..." -Type 'WARN'
    Set-Status "Cancelling..."
})
$form.Controls.Add($cancelBtn)

$replBtn = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Replication Summary"
    Location = New-Object System.Drawing.Point(($leftX + 200 + $gap + 120 + $gap), $btnY)
    Size     = New-Object System.Drawing.Size(180, $btnH)
}
$replBtn.Add_Click({ Show-ReplSummary })
$form.Controls.Add($replBtn)

$logBtn = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Open Log File"
    Location = New-Object System.Drawing.Point(($leftX + 200 + $gap + 120 + $gap + 180 + $gap), $btnY)
    Size     = New-Object System.Drawing.Size(150, $btnH)
}
$logBtn.Add_Click({ Show-Log })
$form.Controls.Add($logBtn)

$refreshBtn2 = New-Object System.Windows.Forms.Button -Property @{
    Text     = "Refresh Scope"
    Location = New-Object System.Drawing.Point(($leftX + 200 + $gap + 120 + $gap + 180 + $gap + 150 + $gap), $btnY)
    Size     = New-Object System.Drawing.Size(150, $btnH)
}
$refreshBtn2.Add_Click({ Refresh-Discovery })
$form.Controls.Add($refreshBtn2)
#endregion

$form.Add_Shown({
    $form.Activate() | Out-Null
    Log-Message ("UI initialized. Functional Baseline + GUI Enhancements – 2026-02-09. Log: {0}" -f $logFile) -Type 'INFO'
    Set-Status "Ready"
    try { Refresh-Discovery } catch { }
})

[void]$form.ShowDialog()

# --- End of Script --- 
