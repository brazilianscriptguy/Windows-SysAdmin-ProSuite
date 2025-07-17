<#
.SYNOPSIS
    PowerShell Script for Updating AD User Display Names Based on Email Address.

.DESCRIPTION
    Updates AD user display names using a standardized format (e.g., JOHN DOE) derived from email addresses.
    Supports multi-domain forests with preview, apply, undo, and CSV export features.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 17, 2025
    Version: 1.2 (Fixed Preview button issue)
#>

<#
.SYNOPSIS
    PowerShell Script for Cleaning Up Inactive AD Computer Accounts.

.DESCRIPTION
    This script identifies and removes inactive workstation accounts in Active Directory, 
    enhancing security by ensuring that outdated or unused accounts are properly managed and removed.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 17, 2025
    Version: 2.1 (Improved forest domain gathering)
#>

# Hide the PowerShell console window
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
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@

[Window]::Hide()

#region Initialization

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$csvDir = [System.Environment]::GetFolderPath('MyDocuments')
$logPath = Join-Path $logDir "$scriptName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$csvPath = Join-Path $csvDir "$scriptName.csv"

$script:undoStack = New-Object System.Collections.Stack
$script:previewResults = @()

if (-not (Test-Path $logDir)) {
    try { New-Item -Path $logDir -ItemType Directory -Force | Out-Null } catch { Write-Warning "Failed to create log directory: $_" }
}

#endregion

#region Logging and Message Functions

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")] [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$MessageType] $Message"
    Add-Content -Path $logPath -Value $entry -ErrorAction SilentlyContinue
}

function Show-InfoMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Info', 'OK', 'Information') | Out-Null
    Log-Message $Message "INFO"
}

function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', 'OK', 'Error') | Out-Null
    Log-Message $Message "ERROR"
}

#endregion

#region Dependency Validation

try {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "ActiveDirectory module not found."
    }
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Show-ErrorMessage "Active Directory module is missing. Please install RSAT tools."
    exit 1
}

#endregion

#region Core Functions

function Get-AllDomains {
    try {
        return [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Domains | ForEach-Object { $_.Name }
    } catch {
        Show-ErrorMessage "Unable to retrieve domain list: $_"
        return @()
    }
}

function Get-DomainController {
    param ([string]$Domain)
    try {
        return (Get-ADDomainController -DomainName $Domain -Discover).HostName
    } catch {
        Show-ErrorMessage "Could not resolve a domain controller for '$Domain'."
        return $null
    }
}

function Preview-Changes {
    param (
        [string]$TargetDomain,
        [string]$EmailFilter
    )

    $previewResults = @()

    if (-not $EmailFilter.StartsWith("*")) { $EmailFilter = "*$EmailFilter" }
    if (-not $EmailFilter.EndsWith("*")) { $EmailFilter = "$EmailFilter*" }

    $dc = Get-DomainController -Domain $TargetDomain
    if (-not $dc) { return @() }

    $filter = "mail -like '$EmailFilter'"
    Log-Message "Using DC '$dc' with filter: $filter"

    try {
        $users = Get-ADUser -Server $dc -Filter $filter -Properties mail, DisplayName
        foreach ($user in $users) {
            if ($user.mail) {
                $parts = $user.mail.Split('@')[0].Split('.')
                if ($parts.Count -eq 2) {
                    $previewResults += [PSCustomObject]@{
                        SamAccountName = $user.SamAccountName
                        OldDisplayName = $user.DisplayName
                        NewDisplayName = ($parts[0] + " " + $parts[1]).ToUpper()
                        Domain         = $TargetDomain
                    }
                }
            }
        }
    } catch {
        Log-Message "Error during Preview-Changes: $_" -MessageType "ERROR"
        Show-ErrorMessage "Preview failed. See log for details."
    }

    return $previewResults | Sort-Object Domain, SamAccountName
}

function Apply-Changes {
    param (
        [array]$Changes
    )

    foreach ($change in $Changes) {
        try {
            $dc = Get-DomainController -Domain $change.Domain
            $user = Get-ADUser -Server $dc -Identity $change.SamAccountName -Properties DisplayName
            Set-ADUser -Server $dc -Identity $user.SamAccountName -DisplayName $change.NewDisplayName

            $script:undoStack.Push([PSCustomObject]@{
                SamAccountName = $change.SamAccountName
                OldDisplayName = $user.DisplayName
                NewDisplayName = $change.NewDisplayName
                Domain         = $change.Domain
            })

            Log-Message "Updated $($change.SamAccountName): '$($user.DisplayName)' -> '$($change.NewDisplayName)'"
        } catch {
            Log-Message "Failed to update $($change.SamAccountName): $_" -MessageType "ERROR"
        }
    }

    Show-InfoMessage "Changes applied successfully."
}

function Undo-LastChange {
    if ($script:undoStack.Count -eq 0) {
        Show-InfoMessage "No changes available to undo."
        return
    }

    $last = $script:undoStack.Pop()
    $dc = Get-DomainController -Domain $last.Domain
    try {
        Set-ADUser -Server $dc -Identity $last.SamAccountName -DisplayName $last.OldDisplayName
        Log-Message "Undo: $($last.SamAccountName) -> '$($last.OldDisplayName)'"
        Show-InfoMessage "Undo successful for '$($last.SamAccountName)'"
    } catch {
        Show-ErrorMessage "Undo failed: $_"
    }
}

function Export-Results {
    param ([array]$Results)
    if ($Results.Count -eq 0) {
        Show-InfoMessage "No data to export."
        return
    }
    try {
        $Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
        Show-InfoMessage "Exported to $csvPath"
    } catch {
        Show-ErrorMessage "Failed to export results."
    }
}

#endregion

#region GUI

function Show-UpdateForm {
    $domains = Get-AllDomains

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Update AD User Display Names"
    $form.Size = New-Object System.Drawing.Size(800, 600)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $comboBox = New-Object Windows.Forms.ComboBox
    $comboBox.Location = New-Object Drawing.Point(10, 20)
    $comboBox.Size = New-Object Drawing.Size(760, 25)
    $comboBox.DropDownStyle = 'DropDownList'
    $domains | ForEach-Object { $comboBox.Items.Add($_) }
    $comboBox.SelectedIndex = 0
    $form.Controls.Add($comboBox)

    $emailBox = New-Object Windows.Forms.TextBox
    $emailBox.Location = New-Object Drawing.Point(10, 55)
    $emailBox.Size = New-Object Drawing.Size(760, 25)
    $emailBox.Text = "*@maildomain.com"
    $form.Controls.Add($emailBox)

    $grid = New-Object Windows.Forms.DataGridView
    $grid.Location = New-Object Drawing.Point(10, 90)
    $grid.Size = New-Object Drawing.Size(760, 370)
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AutoGenerateColumns = $false
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $true
    $grid.ReadOnly = $false

    $colSelect = New-Object Windows.Forms.DataGridViewCheckBoxColumn
    $colSelect.Name = "Select"
    $colSelect.HeaderText = "Select"
    $colSelect.Width = 50
    $grid.Columns.Add($colSelect)

    foreach ($name in "SamAccountName","OldDisplayName","NewDisplayName","Domain") {
        $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $name
        $col.HeaderText = $name
        $col.ReadOnly = $true
        $col.Width = 180
        $grid.Columns.Add($col)
    }

    $form.Controls.Add($grid)

    $btnPreview = New-Object Windows.Forms.Button
    $btnPreview.Text = "Preview"
    $btnPreview.Location = New-Object Drawing.Point(10, 470)
    $btnPreview.Size = New-Object Drawing.Size(150, 30)
    $form.Controls.Add($btnPreview)

    $btnApply = New-Object Windows.Forms.Button
    $btnApply.Text = "Apply Changes"
    $btnApply.Location = New-Object Drawing.Point(170, 470)
    $btnApply.Size = New-Object Drawing.Size(150, 30)
    $btnApply.Enabled = $false
    $form.Controls.Add($btnApply)

    $btnUndo = New-Object Windows.Forms.Button
    $btnUndo.Text = "Undo Last Change"
    $btnUndo.Location = New-Object Drawing.Point(330, 470)
    $btnUndo.Size = New-Object Drawing.Size(150, 30)
    $form.Controls.Add($btnUndo)

    $btnExport = New-Object Windows.Forms.Button
    $btnExport.Text = "Export CSV"
    $btnExport.Location = New-Object Drawing.Point(490, 470)
    $btnExport.Size = New-Object Drawing.Size(150, 30)
    $btnExport.Enabled = $false
    $form.Controls.Add($btnExport)

    $btnPreview.Add_Click({
        $grid.Rows.Clear()
        $targetDomain = $comboBox.SelectedItem
        $emailFilter = $emailBox.Text
        $script:previewResults = Preview-Changes -TargetDomain $targetDomain -EmailFilter $emailFilter
        if ($script:previewResults.Count -eq 0) {
            Show-InfoMessage "No users found for the given filter."
            return
        }
        foreach ($result in $script:previewResults) {
            $rowIndex = $grid.Rows.Add()
            $row = $grid.Rows[$rowIndex]
            $row.Cells["Select"].Value = $false
            $row.Cells["SamAccountName"].Value = $result.SamAccountName
            $row.Cells["OldDisplayName"].Value = $result.OldDisplayName
            $row.Cells["NewDisplayName"].Value = $result.NewDisplayName
            $row.Cells["Domain"].Value = $result.Domain
        }
        $btnApply.Enabled = $true
        $btnExport.Enabled = $true
    })

    $btnApply.Add_Click({
        $selectedChanges = @()
        foreach ($row in $grid.Rows) {
            if ($row.Cells["Select"].Value) {
                $selectedChanges += [PSCustomObject]@{
                    SamAccountName = $row.Cells["SamAccountName"].Value
                    OldDisplayName = $row.Cells["OldDisplayName"].Value
                    NewDisplayName = $row.Cells["NewDisplayName"].Value
                    Domain         = $row.Cells["Domain"].Value
                }
            }
        }
        if ($selectedChanges.Count -eq 0) {
            Show-InfoMessage "No rows selected."
            return
        }
        Apply-Changes -Changes $selectedChanges
    })

    $btnUndo.Add_Click({ Undo-LastChange })
    $btnExport.Add_Click({ Export-Results -Results $script:previewResults })

    $form.ShowDialog() | Out-Null
}

#endregion

Show-UpdateForm

# End of script
