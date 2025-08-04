<#
.SYNOPSIS
    PowerShell Script for Retrieving Information on AD Groups and Their Members.

.DESCRIPTION
    This script retrieves detailed information about Active Directory (AD) groups and their members 
    from a selected domain, allowing users to choose specific groups or all groups via a GUI with 
    checkbox selection, exporting results to a single CSV.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    2025-08-04
#>

# Hide Console
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
[Window]::ShowWindow([Window]::GetConsoleWindow(), 0)

# Load GUI Libraries
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Setup Logging
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = "C:\Logs-TEMP"
$logPath = Join-Path $logDir "$scriptName.log"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

function Write-Log {
    param ([string]$Message, [ValidateSet("INFO", "ERROR", "WARNING")]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    try {
        $logBox.SelectionStart = $logBox.TextLength
        $logBox.SelectionColor = switch ($Level) {
            "ERROR" { 'Red' }
            "WARNING" { 'DarkOrange' }
            "INFO" { 'Black' }
        }
        $logBox.AppendText("$entry`r`n")
        $logBox.ScrollToCaret()
        $entry | Out-File -FilePath $logPath -Append -Encoding UTF8
    } catch {
        Write-Error "Log error: $_"
    }
}

function Show-MessageBox {
    param ([string]$Message, [string]$Title = "Message", [string]$Icon = "Information")
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

# GUI Initialization
$form = New-Object Windows.Forms.Form -Property @{
    Text = "Export AD Group Members"
    Size = '700,780'
    StartPosition = 'CenterScreen'
    FormBorderStyle = 'FixedSingle'
    MaximizeBox = $false
}

$comboDomain = New-Object Windows.Forms.ComboBox -Property @{ Location = '10,30'; Size = '660,25'; DropDownStyle = 'DropDownList' }
$comboDomain.Items.AddRange((Get-ADForest).Domains)
$comboDomain.SelectedIndex = 0
$form.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Select Domain:"; Location = '10,10'; Size = '200,20' }),
        $comboDomain
    ))

$txtSearch = New-Object Windows.Forms.TextBox -Property @{ Location = '10,80'; Size = '660,25' }
$btnClearSearch = New-Object Windows.Forms.Button -Property @{ Text = "Clear Search"; Location = '580,110'; Size = '90,25' }
$form.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Search Groups:"; Location = '10,60'; Size = '200,20' }),
        $txtSearch, $btnClearSearch
    ))

$listGroups = New-Object Windows.Forms.ListView -Property @{ Location = '10,140'; Size = '660,200'; View = 'Details'; CheckBoxes = $true }
[void]$listGroups.Columns.Add("Group Name", 640)
$chkSelectAll = New-Object Windows.Forms.CheckBox -Property @{ Text = "Select All"; Location = '10,120'; Size = '100,20' }
$form.Controls.AddRange(@($chkSelectAll, $listGroups))

$listAttr = New-Object Windows.Forms.CheckedListBox -Property @{ Location = '10,360'; Size = '660,100' }
$listAttr.Items.AddRange(@('Name', 'SamAccountName', 'UserPrincipalName', 'EmailAddress', 'DisplayName', 'Title', 'Department', 'Company', 'Manager', 'Enabled', 'AccountLockoutTime', 'LastLogonDate', 'WhenCreated'))
$form.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Select Attributes:"; Location = '10,340'; Size = '200,20' }),
        $listAttr
    ))

$txtOut = New-Object Windows.Forms.TextBox -Property @{ Location = '10,480'; Size = '560,25'; Text = [Environment]::GetFolderPath("MyDocuments") }
$btnBrowse = New-Object Windows.Forms.Button -Property @{ Text = "Browse"; Location = '580,480'; Size = '90,25' }
$btnBrowse.Add_Click({
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        if ($fbd.ShowDialog() -eq "OK") { $txtOut.Text = $fbd.SelectedPath }
    })
$form.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Output Folder:"; Location = '10,460'; Size = '200,20' }),
        $txtOut, $btnBrowse
    ))

$logBox = New-Object Windows.Forms.RichTextBox -Property @{ Location = '10,520'; Size = '660,80'; ReadOnly = $true; ScrollBars = 'Vertical' }
$form.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Log:"; Location = '10,500'; Size = '200,20' }),
        $logBox
    ))

$progress = New-Object Windows.Forms.ProgressBar -Property @{ Location = '10,610'; Size = '660,15' }
$lblStatus = New-Object Windows.Forms.Label -Property @{ Text = "Ready"; Location = '10,630'; Size = '660,20' }
$btnExport = New-Object Windows.Forms.Button -Property @{ Text = "Export CSV"; Location = '10,660'; Size = '100,30' }
$btnClose = New-Object Windows.Forms.Button -Property @{ Text = "Close"; Location = '570,660'; Size = '100,30' }
$btnClose.Add_Click({ $form.Close() })
$form.Controls.AddRange(@($progress, $lblStatus, $btnExport, $btnClose))

$allGroups = @()
$checkedGroups = New-Object 'System.Collections.Generic.HashSet[string]'

function Load-Groups {
    $listGroups.BeginUpdate()
    $listGroups.Items.Clear()
    $checkedGroups.Clear()
    try {
        $allGroups = Get-ADGroup -Server $comboDomain.SelectedItem -Filter * | Sort-Object Name
        foreach ($g in $allGroups) {
            $item = New-Object Windows.Forms.ListViewItem $g.Name
            $listGroups.Items.Add($item)
        }
        $lblStatus.Text = "$($allGroups.Count) groups loaded."
        Write-Log "Loaded $($allGroups.Count) groups from domain."
    } catch {
        $lblStatus.Text = "Error loading groups."
        Write-Log "Error loading groups: $_" "ERROR"
    }
    $listGroups.EndUpdate()
}

$comboDomain.Add_SelectedIndexChanged({ Load-Groups })

$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 300
$searchTimer.Add_Tick({
        $searchTimer.Stop()
        if ($null -eq $allGroups -or $allGroups.Count -eq 0) { return }
        $searchText = $txtSearch.Text.ToLowerInvariant().Trim()
        $listGroups.BeginUpdate()
        $listGroups.Items.Clear()
        foreach ($g in $allGroups) {
            if ($g.Name -and $g.Name.ToLowerInvariant().Contains($searchText)) {
                $item = New-Object Windows.Forms.ListViewItem $g.Name
                if ($checkedGroups.Contains($g.Name)) { $item.Checked = $true }
                $listGroups.Items.Add($item)
            }
        }
        $listGroups.EndUpdate()
    })

$txtSearch.Add_TextChanged({
        $searchTimer.Stop()
        $searchTimer.Start()
    })

$listGroups.Add_ItemChecked({
        param($s, $e)
        try {
            if ($e -and $e.Item -and $e.Item.Text) {
                if ($e.Item.Checked) {
                    $checkedGroups.Add($e.Item.Text) | Out-Null
                } else {
                    $checkedGroups.Remove($e.Item.Text) | Out-Null
                }
            }
        } catch {
            Write-Log "Error on item check event: $_" "WARNING"
        }
    })

$chkSelectAll.Add_CheckedChanged({
        $listGroups.BeginUpdate()
        foreach ($item in $listGroups.Items) {
            $item.Checked = $chkSelectAll.Checked
            if ($chkSelectAll.Checked) {
                $checkedGroups.Add($item.Text) | Out-Null
            } else {
                $checkedGroups.Remove($item.Text) | Out-Null
            }
        }
        $listGroups.EndUpdate()
    })

$btnClearSearch.Add_Click({ $txtSearch.Text = "" })

$btnExport.Add_Click({
        $domain = $comboDomain.SelectedItem
        $attrs = $listAttr.CheckedItems
        $output = $txtOut.Text
        $csvPath = Join-Path $output "$domain`_Export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

        if ($checkedGroups.Count -eq 0) {
            Show-MessageBox "Select at least one group." "Warning" "Warning"; return
        }
        if ($attrs.Count -eq 0) {
            Show-MessageBox "Select at least one attribute." "Warning" "Warning"; return
        }

        $progress.Maximum = $checkedGroups.Count
        $progress.Value = 0
        $results = @()

        foreach ($group in $checkedGroups) {
            try {
                $members = Get-ADGroupMember -Identity $group -Server $domain -Recursive | Where-Object { $_.objectClass -eq 'user' }
                foreach ($m in $members) {
                    $user = Get-ADUser -Identity $m.DistinguishedName -Server $domain -Properties $attrs
                    $obj = [ordered]@{ Domain = $domain; Group = $group; UserDN = $m.DistinguishedName }
                    foreach ($attr in $attrs) { $obj[$attr] = $user.$attr }
                    $results += New-Object PSObject -Property $obj
                }
            } catch {
                Write-Log "Failed group ${group}: $_" "ERROR"
            }
            $progress.Value++
        }

        if ($results.Count -gt 0) {
            $results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            Show-MessageBox "Export complete: $csvPath" "Done"
            Start-Process $csvPath
        } else {
            Show-MessageBox "No results to export." "Info"
        }
    })

Load-Groups
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# End of script
