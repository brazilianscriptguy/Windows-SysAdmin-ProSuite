<#
.SYNOPSIS
    PowerShell GUI for Executing Scripts Organized by Tabs with Real-Time Search.

.DESCRIPTION
    This script provides a GUI interface to browse, search, and execute PowerShell scripts
    organized by tabs representing different script categories (folders). It includes real-time
    search with debouncing, improved error handling, and dynamic resizing.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Updated: August 6, 2025
    Version: 2.3 (Fixed GUI layout, inline search, logging compliance)
#>

#region --- Initialization and Configuration

# Hide the PowerShell console window
if (-not ([System.Management.Automation.PSTypeName]'Window').Type) {
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
}
[Window]::Hide()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Log {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logPath = Join-Path $scriptDirectory "SysAdminToolSet.log"
    $entry = "[$timestamp] [$MessageType] $Message"
    try {
        if (-not (Test-Path $logPath)) {
            $null = New-Item -Path $logPath -ItemType File -Force
        }
        Add-Content -Path $logPath -Value $entry
    } catch {
        Write-Warning "Failed to log message: $_"
    }
}

#endregion

#region --- Core Functions

function Get-ScriptDictionaries {
    try {
        $directories = Get-ChildItem -Path $scriptDirectory -Directory -Recurse -ErrorAction Stop
        $scriptsByCategory = @{}
        foreach ($dir in $directories) {
            $scripts = Get-ChildItem -Path $dir.FullName -Filter "*.ps1" -File -ErrorAction Stop
            if ($scripts.Count -gt 0) {
                $scriptsByCategory[$dir.Name] = $scripts | Sort-Object Name
                Write-Log "Loaded $($dir.Name) with $($scripts.Count) scripts"
            }
        }
        return $scriptsByCategory
    } catch {
        Write-Log "Script dictionary load failed: $_" "ERROR"
        return @{}
    }
}

function Update-ListBox {
    param (
        [System.Windows.Forms.TextBox]$SearchBox,
        [System.Windows.Forms.CheckedListBox]$ListBox,
        [System.IO.FileInfo[]]$ScriptFiles
    )
    $searchText = $SearchBox.Text.Trim().ToLowerInvariant()
    $ListBox.BeginUpdate()
    $ListBox.Items.Clear()
    foreach ($script in $ScriptFiles) {
        if ($searchText -eq "" -or $script.Name.ToLowerInvariant().Contains($searchText)) {
            $ListBox.Items.Add($script.Name, $false)
        }
    }
    if ($ListBox.Items.Count -eq 0) {
        $ListBox.Items.Add("<No matching scripts found>", $false)
    }
    $ListBox.EndUpdate()
}

function Execute-Scripts {
    param ([System.Windows.Forms.TabControl]$TabControl)
    $executed = $false
    foreach ($tab in $TabControl.TabPages) {
        $listBox = $tab.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckedListBox] }
        foreach ($item in $listBox.CheckedItems) {
            if ($item -eq "<No matching scripts found>") { continue }
            $scriptPath = ($scriptsByCategory[$tab.Text] | Where-Object { $_.Name -eq $item }).FullName
            if (-not (Test-Path $scriptPath)) {
                Write-Log "Script not found: $scriptPath" "ERROR"
                continue
            }
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo -Property @{
                    FileName = "powershell.exe"
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
                    UseShellExecute = $false
                    RedirectStandardOutput = $true
                    RedirectStandardError = $true
                }
                $process = [System.Diagnostics.Process]::Start($psi)
                $output = $process.StandardOutput.ReadToEnd()
                $errors = $process.StandardError.ReadToEnd()
                $process.WaitForExit()
                if ($process.ExitCode -eq 0) {
                    Write-Log "Executed successfully: $scriptPath"
                } else {
                    Write-Log "Execution failed: $scriptPath - Error: $errors" "ERROR"
                }
                $executed = $true
            } catch {
                Write-Log "Exception while executing ${scriptPath}: $_" "ERROR"
            }
        }
    }
    if (-not $executed) {
        [System.Windows.Forms.MessageBox]::Show("No scripts selected.", "Info")
    }
}

#endregion

#region --- GUI Builder

function Create-GUI {
    $global:scriptsByCategory = Get-ScriptDictionaries
    if ($scriptsByCategory.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No scripts found.", "Error")
        return
    }

    $form = New-Object Windows.Forms.Form -Property @{
        Text = "Launch Script Menu"
        Size = New-Object Drawing.Size(1100, 800)
        StartPosition = "CenterScreen"
        BackColor = "WhiteSmoke"
    }

    $tabControl = New-Object Windows.Forms.TabControl -Property @{
        Dock = "Fill"
    }
    $form.Controls.Add($tabControl)

    foreach ($category in $scriptsByCategory.Keys) {
        $tab = New-Object Windows.Forms.TabPage -Property @{ Text = $category; AutoScroll = $true }
        $searchBox = New-Object Windows.Forms.TextBox -Property @{ Location = '10,10'; Size = '1050,25' }
        $listBox = New-Object Windows.Forms.CheckedListBox -Property @{ Location = '10,45'; Size = '1050,650' }
        $tab.Controls.AddRange(@($searchBox, $listBox))
        $tabControl.TabPages.Add($tab)
        
        Update-ListBox -SearchBox $searchBox -ListBox $listBox -ScriptFiles $scriptsByCategory[$category]

        $searchBox.Add_TextChanged({
            Update-ListBox -SearchBox $searchBox -ListBox $listBox -ScriptFiles $scriptsByCategory[$category]
        })
    }

    $btnExecute = New-Object Windows.Forms.Button -Property @{
        Text = "Execute Selected"
        Size = '200,30'
        Location = New-Object Drawing.Point(440, 700)
        BackColor = 'LightSkyBlue'
    }
    $btnExecute.Add_Click({ Execute-Scripts -TabControl $tabControl })
    $form.Controls.Add($btnExecute)

    $form.ShowDialog() | Out-Null
}

#endregion

# Entry Point
Create-GUI

# End of script
