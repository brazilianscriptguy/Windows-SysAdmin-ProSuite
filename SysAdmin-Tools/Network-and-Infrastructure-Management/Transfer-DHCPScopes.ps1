<#
.SYNOPSIS
    PowerShell GUI Tool for Exporting and Importing DHCP Scopes Between Servers.

.DESCRIPTION
    Provides a Windows Forms GUI for exporting DHCP scopes (with leases) and importing them across domain servers.
    Includes options for excluding and inactivating scopes, structured logging, and GUI feedback.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    v3.5 – July 23, 2025
#>

#region --- Hide Console ---
if (-not $ShowConsole) {
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class Window {
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    }
"@
    [Window]::ShowWindow([Window]::GetConsoleWindow(), 0)
}
#endregion

#region --- Globals and Logging ---
$global:ExportDir = Join-Path $env:LOCALAPPDATA "ScriptLogs"
$global:LogPath = ""

function Initialize-Logger {
    if (-not (Test-Path $global:ExportDir)) {
        New-Item -Path $global:ExportDir -ItemType Directory -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $global:LogPath = Join-Path $global:ExportDir "TransferDhcpScopes_$timestamp.log"
    Add-Content -Path $global:LogPath -Value "=== Logging started at $(Get-Date -Format 'u') ==="
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $global:LogPath -Value $entry
    if ($Level -eq "ERROR") { Write-Error $entry }
    elseif ($Level -eq "WARNING") { Write-Warning $entry }
}
#endregion

#region --- Utilities ---
function Get-LatestExportFile {
    try {
        $latest = Get-ChildItem -Path $global:ExportDir -Filter "Export-Scope_*.xml" |
                  Sort-Object LastWriteTime -Descending |
                  Select-Object -First 1
        return $latest?.FullName
    } catch {
        Write-Log "Error getting latest export file: $_" -Level "ERROR"
        return ""
    }
}

function Get-ForestDomains {
    try {
        return [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Domains |
               Select-Object -ExpandProperty Name
    } catch {
        Write-Log "Error loading domains: $_" -Level "ERROR"
        return @()
    }
}

function Get-DHCPServerFromDomain {
    param ([string]$Domain)
    try {
        $servers = Get-DhcpServerInDC
        foreach ($srv in $servers) {
            if ($srv.DnsName -like "*$Domain*") {
                return $srv.DnsName
            }
        }
        return $null
    } catch {
        Write-Log "DHCP server retrieval error: $_" -Level "ERROR"
        return $null
    }
}

function Test-ScopeId {
    param ([string]$ScopeId)
    return $ScopeId -match "^\d{1,3}(\.\d{1,3}){3}$"
}
#endregion

#region --- Core Functions ---
function Export-DhcpScope {
    param (
        [string]$Server,
        [string]$ScopeId,
        [bool]$ExcludeScope,
        [bool]$InactivateScope,
        [ref]$ExportedFilePath,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )
    try {
        $ProgressBar.Value = 10
        if (-not (Test-ScopeId $ScopeId)) {
            throw "Invalid Scope ID format: $ScopeId"
        }

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $exportFile = Join-Path $global:ExportDir "Export-Scope_${ScopeId}_$timestamp.xml"
        $ExportedFilePath.Value = $exportFile

        Export-DhcpServer -ComputerName $Server -File $exportFile -Leases -ScopeId $ScopeId -Force
        Write-Log "Exported scope $ScopeId to $exportFile"
        $ProgressBar.Value = 60

        if ($InactivateScope) {
            Set-DhcpServerv4Scope -ComputerName $Server -ScopeId $ScopeId -State Inactive
            Write-Log "Inactivated scope $ScopeId"
        }

        if ($ExcludeScope) {
            Remove-DhcpServerv4Scope -ComputerName $Server -ScopeId $ScopeId -Force
            Write-Log "Removed scope $ScopeId from $Server"
        }

        $ProgressBar.Value = 100
        return $true
    } catch {
        Write-Log "Export failed: $_" -Level "ERROR"
        $ProgressBar.Value = 0
        return $false
    }
}

function Import-DhcpScope {
    param (
        [string]$Server,
        [string]$ImportFilePath,
        [bool]$InactivateAfter = $false,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )
    try {
        $ProgressBar.Value = 10

        if (-not (Test-Path $ImportFilePath)) {
            throw "Import file not found: $ImportFilePath"
        }

        [xml]$xmlContent = Get-Content $ImportFilePath
        $existingScopes = Get-DhcpServerv4Scope -ComputerName $Server -ErrorAction Stop | Select-Object -ExpandProperty ScopeId

        $xmlScopeNodes = $xmlContent.DHCPServer.IPv4.Scopes.Scope
        $scopesToImport = @()

        foreach ($scopeNode in $xmlScopeNodes) {
            $scopeId = $scopeNode.ScopeId
            if ($existingScopes -contains $scopeId) {
                Write-Log "Skipping import of scope $scopeId – already exists on $Server" -Level "WARNING"
            } else {
                $scopesToImport += $scopeId
            }
        }

        if ($scopesToImport.Count -eq 0) {
            Write-Log "All scopes in $ImportFilePath already exist on $Server. No import performed." -Level "INFO"
            [Windows.Forms.MessageBox]::Show("All scopes already exist on $Server.`nNothing was imported.", "Info", "OK", "Information")
            $ProgressBar.Value = 100
            return "Skipped"
        }

        Import-DhcpServer -ComputerName $Server -File $ImportFilePath -Leases -BackupPath $global:ExportDir -ErrorAction Stop
        Write-Log "Imported scopes from $ImportFilePath to $Server"

        if ($InactivateAfter) {
            foreach ($newScopeId in $scopesToImport) {
                Set-DhcpServerv4Scope -ComputerName $Server -ScopeId $newScopeId -State Inactive -ErrorAction Stop
                Write-Log "Inactivated scope $newScopeId after import"
            }
        }

        $ProgressBar.Value = 100
        return "Imported"
    } catch {
        Write-Log "Import failed: $_" -Level "ERROR"
        $ProgressBar.Value = 0
        return "Failed"
    }
}
#endregion

#region --- GUI ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-GUI {
    $form = New-Object Windows.Forms.Form -Property @{
        Text = "DHCP Scope Transfer Tool v3.5"
        Size = '720,460'
        StartPosition = 'CenterScreen'
    }

    $tabs = New-Object Windows.Forms.TabControl
    $tabs.Size = '680,400'
    $tabs.Location = '10,10'
    $form.Controls.Add($tabs)

    #region Export Tab
    $tabExport = New-Object Windows.Forms.TabPage -Property @{ Text = "Export Scope" }
    $tabs.Controls.Add($tabExport)

    $cmbDomain = New-Object Windows.Forms.ComboBox -Property @{ Location = '150,30'; Size = '200,20'; DropDownStyle = 'DropDownList' }
    $txtServer = New-Object Windows.Forms.TextBox -Property @{ Location = '150,70'; Size = '200,20' }
    $cmbScope = New-Object Windows.Forms.ComboBox -Property @{ Location = '150,110'; Size = '200,20'; DropDownStyle = 'DropDownList' }
    $txtExportPath = New-Object Windows.Forms.TextBox -Property @{ Location = '150,150'; Size = '400,20'; ReadOnly = $true }
    $btnBrowseExport = New-Object Windows.Forms.Button -Property @{ Text = "Select Path"; Location = '560,150'; Size = '80,22' }
    $chkExclude = New-Object Windows.Forms.CheckBox -Property @{ Text = "Delete scope after export"; Location = '360,30'; Size = '200,20'; AutoSize = $true }
    $chkInactivate = New-Object Windows.Forms.CheckBox -Property @{ Text = "Disable scope after export"; Location = '360,60'; Size = '200,20'; AutoSize = $true }
    $btnExport = New-Object Windows.Forms.Button -Property @{ Text = "Export"; Location = '360,90'; Size = '120,30' }
    $barExport = New-Object Windows.Forms.ProgressBar -Property @{ Location = '10,260'; Size = '630,25' }
    $lblStatusExport = New-Object Windows.Forms.Label -Property @{ Text = ""; Location = '10,290'; Size = '630,20' }

    $tabExport.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Source Domain:"; Location = '10,30'; AutoSize = $true }),
        $cmbDomain, (New-Object Windows.Forms.Label -Property @{ Text = "DHCP Server:"; Location = '10,70'; AutoSize = $true }),
        $txtServer, (New-Object Windows.Forms.Label -Property @{ Text = "Scope ID:"; Location = '10,110'; AutoSize = $true }),
        $cmbScope, (New-Object Windows.Forms.Label -Property @{ Text = "Export Path:"; Location = '10,150'; AutoSize = $true }),
        $txtExportPath, $btnBrowseExport, $chkExclude, $chkInactivate, $btnExport, $barExport, $lblStatusExport
    ))

    #endregion

    #region Import Tab
    $tabImport = New-Object Windows.Forms.TabPage -Property @{ Text = "Import Scope" }
    $tabs.Controls.Add($tabImport)

    $cmbImpDomain = New-Object Windows.Forms.ComboBox -Property @{ Location = '150,30'; Size = '200,20'; DropDownStyle = 'DropDownList' }
    $txtImpServer = New-Object Windows.Forms.TextBox -Property @{ Location = '150,70'; Size = '200,20' }
    $txtImpFile = New-Object Windows.Forms.TextBox -Property @{ Location = '150,110'; Size = '400,20'; Text = Get-LatestExportFile }
    $btnBrowseImp = New-Object Windows.Forms.Button -Property @{ Text = "Select File"; Location = '560,110'; Size = '80,22' }
    $chkInactivateImp = New-Object Windows.Forms.CheckBox -Property @{ Text = "Disable scope after import"; Location = '360,30'; Size = '200,20'; AutoSize = $true }
    $btnImport = New-Object Windows.Forms.Button -Property @{ Text = "Import"; Location = '360,60'; Size = '120,30' }
    $barImport = New-Object Windows.Forms.ProgressBar -Property @{ Location = '10,260'; Size = '630,25' }
    $lblStatusImport = New-Object Windows.Forms.Label -Property @{ Text = ""; Location = '10,290'; Size = '630,20' }

    $tabImport.Controls.AddRange(@(
        (New-Object Windows.Forms.Label -Property @{ Text = "Destination Domain:"; Location = '10,30'; AutoSize = $true }),
        $cmbImpDomain, (New-Object Windows.Forms.Label -Property @{ Text = "DHCP Server:"; Location = '10,70'; AutoSize = $true }),
        $txtImpServer, (New-Object Windows.Forms.Label -Property @{ Text = "Import File:"; Location = '10,110'; AutoSize = $true }),
        $txtImpFile, $btnBrowseImp, $chkInactivateImp, $btnImport, $barImport, $lblStatusImport
    ))
    #endregion

    #region ToolTips
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($cmbDomain, "Select source domain for scope export")
    $toolTip.SetToolTip($txtServer, "DHCP server auto-detected from domain")
    $toolTip.SetToolTip($cmbScope, "IP address range for scope (e.g., 192.168.1.0)")
    $toolTip.SetToolTip($txtExportPath, "XML file path for exported scope")
    $toolTip.SetToolTip($btnBrowseExport, "Choose export file path")
    $toolTip.SetToolTip($chkExclude, "Remove scope from source server")
    $toolTip.SetToolTip($chkInactivate, "Disable scope on source server")
    $toolTip.SetToolTip($btnExport, "Export selected scope")
    $toolTip.SetToolTip($cmbImpDomain, "Select destination domain for import")
    $toolTip.SetToolTip($txtImpServer, "DHCP server for scope import")
    $toolTip.SetToolTip($txtImpFile, "XML file with scope data to import")
    $toolTip.SetToolTip($btnBrowseImp, "Select file for scope import")
    $toolTip.SetToolTip($chkInactivateImp, "Disable imported scope")
    $toolTip.SetToolTip($btnImport, "Import scope from selected file")
    #endregion

    #region Events
    foreach ($d in Get-ForestDomains) {
        $cmbDomain.Items.Add($d) | Out-Null
        $cmbImpDomain.Items.Add($d) | Out-Null
    }

    $cmbDomain.Add_SelectedIndexChanged({
        $cmbScope.Items.Clear()
        $txtServer.Text = Get-DHCPServerFromDomain $cmbDomain.SelectedItem
        if ($txtServer.Text) {
            Get-DhcpServerv4Scope -ComputerName $txtServer.Text | ForEach-Object {
                $cmbScope.Items.Add($_.ScopeId) | Out-Null
            }
        }
        $btnExport.Enabled = $txtServer.Text -and $cmbScope.Text
    })

    $cmbImpDomain.Add_SelectedIndexChanged({
        $txtImpServer.Text = Get-DHCPServerFromDomain $cmbImpDomain.SelectedItem
        $btnImport.Enabled = $txtImpServer.Text -and $txtImpFile.Text
    })

    $txtImpFile.Add_TextChanged({
        $btnImport.Enabled = $txtImpServer.Text -and $txtImpFile.Text
    })

    $btnBrowseExport.Add_Click({
        $dlg = New-Object Windows.Forms.SaveFileDialog
        $dlg.InitialDirectory = $global:ExportDir
        $dlg.Filter = "XML files (*.xml)|*.xml"
        $dlg.FileName = "Export-Scope_$($cmbScope.Text)_$(Get-Date -Format 'yyyyMMdd_HHmmss').xml"
        if ($dlg.ShowDialog() -eq "OK") {
            $txtExportPath.Text = $dlg.FileName
        }
    })

    $btnBrowseImp.Add_Click({
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.InitialDirectory = $global:ExportDir
        $dlg.Filter = "XML files (*.xml)|*.xml"
        if ($dlg.ShowDialog() -eq "OK") {
            $txtImpFile.Text = $dlg.FileName
        }
    })

    $btnExport.Add_Click({
        $barExport.Value = 0
        $lblStatusExport.Text = "Validating inputs..."
        if (-not $txtServer.Text -or -not $cmbScope.Text) {
            [Windows.Forms.MessageBox]::Show("Select domain, server, and scope ID", "Error", "OK", "Error")
            $lblStatusExport.Text = "Export failed: Missing inputs"
            return
        }
        if (-not (Test-ScopeId $cmbScope.Text)) {
            [Windows.Forms.MessageBox]::Show("Invalid Scope ID format (e.g., 192.168.1.0)", "Error", "OK", "Error")
            $lblStatusExport.Text = "Export failed: Invalid Scope ID"
            return
        }

        $lblStatusExport.Text = "Exporting scope..."
        $exportedFile = $txtExportPath.Text
        $success = Export-DhcpScope -Server $txtServer.Text -ScopeId $cmbScope.Text `
            -ExcludeScope:$chkExclude.Checked -InactivateScope:$chkInactivate.Checked `
            -ExportedFilePath ([ref]$exportedFile) -ProgressBar $barExport

        if ($success) {
            $txtExportPath.Text = $exportedFile
            $txtImpFile.Text = $exportedFile
            [Windows.Forms.MessageBox]::Show("Scope exported to $exportedFile", "Success", "OK", "Information")
            $lblStatusExport.Text = "Export completed"
        } else {
            [Windows.Forms.MessageBox]::Show("Export failed. Check log.", "Error", "OK", "Error")
            $lblStatusExport.Text = "Export failed"
        }
    })

    $btnImport.Add_Click({
    $barImport.Value = 0
    $lblStatusImport.Text = "Validating inputs..."

    $serverName = $txtImpServer.Text.Trim()
    $importFile = $txtImpFile.Text.Trim()

    if (-not $serverName -or -not $importFile) {
        [Windows.Forms.MessageBox]::Show("Specify both server and import file.", "Error", "OK", "Error")
        $lblStatusImport.Text = "Import failed: Missing inputs"
        return
    }

    $lblStatusImport.Text = "Importing scope..."
    $result = Import-DhcpScope -Server $serverName -ImportFilePath $importFile `
        -InactivateAfter:$chkInactivateImp.Checked -ProgressBar $barImport

    switch ($result) {
        "Imported" {
            [Windows.Forms.MessageBox]::Show("Scope import process completed on server:`n$serverName", "Success", "OK", "Information")
            $lblStatusImport.Text = "Import completed"
        }
        "Skipped" {
            $lblStatusImport.Text = "Nothing was imported"
        }
        "Failed" {
            [Windows.Forms.MessageBox]::Show("Import failed. Check log for details.", "Error", "OK", "Error")
            $lblStatusImport.Text = "Import failed"
        }
        default {
            [Windows.Forms.MessageBox]::Show("Unexpected result: $result", "Error", "OK", "Error")
            $lblStatusImport.Text = "Import failed"
        }
    }
})

    # Initial button state
    $btnExport.Enabled = $false
    $btnImport.Enabled = $txtImpServer.Text -and $txtImpFile.Text
    #endregion

    $form.ShowDialog()
}
#endregion

# --- Run Script ---
try {
    Initialize-Logger
    Import-Module DHCPServer -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    Show-GUI
} catch {
    Write-Log "Startup error: $_" -Level "ERROR"
    [Windows.Forms.MessageBox]::Show("Startup failed: $_", "Error", "OK", "Error")
}

# End of script
