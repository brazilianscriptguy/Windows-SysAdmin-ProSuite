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
    Updated: July 17, 2025
    Version: 2.2 (Fixed GUI layout issues)
#>

#region --- Initialization and Configuration

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

# Import necessary assemblies for Windows Forms and Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Get the current script directory
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Current Script Directory: $scriptDirectory" -ForegroundColor Cyan

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    $logPath = Join-Path $scriptDirectory "SysAdminToolSet.log"
    try {
        if (-not (Test-Path (Split-Path $logPath))) {
            New-Item -Path (Split-Path $logPath) -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log: $_"
    }
}

Log-Message "Starting Launch Script Automatic Menu execution."

#endregion

#region --- Core Functions

# Function to generate a dictionary of script filenames and paths from all subdirectories
function Get-ScriptDictionaries {
    try {
        $directories = Get-ChildItem -Path $scriptDirectory -Directory -Recurse -ErrorAction Stop
        $scriptsByCategory = @{}

        foreach ($dir in $directories) {
            $scriptFiles = Get-ChildItem -Path $dir.FullName -Filter "*.ps1" -File -ErrorAction Stop
            if ($scriptFiles.Count -gt 0) {
                $category = $dir.Name
                $scriptsByCategory[$category] = $scriptFiles | Sort-Object -Property Name
                Log-Message "Loaded $category category with $($scriptFiles.Count) scripts"
            }
        }
        if ($scriptsByCategory.Count -eq 0) {
            Log-Message "No script categories found" -MessageType "WARN"
        }
        return $scriptsByCategory
    } catch {
        Log-Message "Failed to load script dictionaries: $_" -MessageType "ERROR"
        return @{}
    }
}

# Function to update listbox items based on the search text with debouncing
function Update-ListBox {
    param (
        [System.Windows.Forms.TextBox]$searchBox,
        [System.Windows.Forms.CheckedListBox]$listBox,
        [System.Collections.ObjectModel.Collection[System.IO.FileInfo]]$originalList
    )

    $searchText = $searchBox.Text.Trim().ToLower()
    $listBox.BeginUpdate()
    $listBox.Items.Clear()

    if ([string]::IsNullOrEmpty($searchText)) {
        foreach ($file in $originalList) {
            $listBox.Items.Add($file.Name, $false)
        }
    } else {
        foreach ($file in $originalList) {
            if ($file.Name.ToLower().Contains($searchText)) {
                $listBox.Items.Add($file.Name, $false)
            }
        }
    }

    if ($listBox.Items.Count -eq 0) {
        $listBox.Items.Add("<No matching scripts found>", $false)
    }

    $listBox.EndUpdate()
}

# Function to execute selected scripts
function Execute-Scripts {
    param ([System.Windows.Forms.TabControl]$tabControl)
    $anyExecuted = $false

    foreach ($tabPage in $tabControl.TabPages) {
        $listBox = $tabPage.Controls | Where-Object { $_ -is [System.Windows.Forms.CheckedListBox] }
        if ($listBox) {
            foreach ($script in $listBox.CheckedItems) {
                if ($script -eq "<No matching scripts found>") { continue }

                $scriptPath = $scriptsByCategory[$tabPage.Text] | Where-Object { $_.Name -eq $script } | Select-Object -ExpandProperty FullName
                if (Test-Path $scriptPath) {
                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = "powershell.exe"
                        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
                        $psi.UseShellExecute = $false
                        $psi.RedirectStandardOutput = $true
                        $psi.RedirectStandardError = $true
                        $process = [System.Diagnostics.Process]::Start($psi)
                        $output = $process.StandardOutput.ReadToEnd()
                        $errorOutput = $process.StandardError.ReadToEnd()
                        $process.WaitForExit()
                        if ($process.ExitCode -eq 0) {
                            Log-Message "Successfully executed: $scriptPath"
                            Write-Host "Executed: $scriptPath`nOutput: $output" -ForegroundColor Green
                        } else {
                            $errorMessage = "Execution failed for ${scriptPath}: ${errorOutput}"
                            Log-Message $errorMessage -MessageType "ERROR"
                            [System.Windows.Forms.MessageBox]::Show("Error executing ${script}: ${errorOutput}", "Execution Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        }
                        $anyExecuted = $true
                    } catch {
                        $errorMessage = "Failed to execute ${scriptPath}: $_"
                        Log-Message $errorMessage -MessageType "ERROR"
                        [System.Windows.Forms.MessageBox]::Show("Failed to execute ${script}: $_", "Execution Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                } else {
                    Log-Message "Script not found: $scriptPath" -MessageType "ERROR"
                    [System.Windows.Forms.MessageBox]::Show("Script not found: $scriptPath", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        }
    }

    if (-not $anyExecuted) {
        [System.Windows.Forms.MessageBox]::Show("No scripts selected for execution.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}

#endregion

#region --- GUI Implementation

function Create-GUI {
    # Generate script dictionaries
    $scriptsByCategory = Get-ScriptDictionaries
    if ($scriptsByCategory.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No scripts found in $scriptDirectory or its subdirectories.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Initialize the Form
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Lauch Script Automatic Menu'
    $form.Size = [System.Drawing.Size]::new(1200, 900)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = [System.Drawing.Color]::WhiteSmoke
    $form.Add_Resize({
            $tabControl.Size = [System.Drawing.Size]::new($form.ClientSize.Width - 40, $form.ClientSize.Height - 150)
            $executeButton.Location = [System.Drawing.Point]::new(($form.ClientSize.Width - 150) / 2, $form.ClientSize.Height - 80)
        })

    # Add TabControl for organizing script categories
    $tabControl = [System.Windows.Forms.TabControl]::new()
    $tabControl.Size = [System.Drawing.Size]::new($form.ClientSize.Width - 40, $form.ClientSize.Height - 150)
    $tabControl.Location = [System.Drawing.Point]::new(10, 10)
    $tabControl.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $form.Controls.Add($tabControl)

    # Store references to controls
    $tabControls = @{}

    # Add Tabs for each category with debounced search
    foreach ($category in $scriptsByCategory.Keys) {
        $tabPage = [System.Windows.Forms.TabPage]::new()
        $tabPage.Text = $category
        $tabPage.AutoScroll = $true

        # Add Search Box
        $searchBox = [System.Windows.Forms.TextBox]::new()
        $searchBox.Size = [System.Drawing.Size]::new($tabPage.ClientSize.Width - 20, 25)
        $searchBox.Location = [System.Drawing.Point]::new(10, 10)
        $searchBox.Font = [System.Drawing.Font]::new("Arial", 10)
        $searchBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
        $tabPage.Controls.Add($searchBox)

        # Add ListBox
        $listBox = [System.Windows.Forms.CheckedListBox]::new()
        $listBox.Size = [System.Drawing.Size]::new($tabPage.ClientSize.Width - 20, $tabPage.ClientSize.Height - 60)
        $listBox.Location = [System.Drawing.Point]::new(10, 40)
        $listBox.Font = [System.Drawing.Font]::new("Arial", 9)
        $listBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
        $listBox.ScrollAlwaysVisible = $true
        $tabPage.Controls.Add($listBox)

        # Initial population
        Update-ListBox -searchBox $searchBox -listBox $listBox -originalList $scriptsByCategory[$category]

        # Debounced search handler
        $searchTimer = $null
        $searchBox.Add_TextChanged({
                if ($searchTimer) { $searchTimer.Dispose() }
                $searchTimer = New-Object System.Timers.Timer -ArgumentList 300
                $searchTimer.AutoReset = $false
                $searchTimer.add_Elapsed({
                        Update-ListBox -searchBox $searchBox -listBox $listBox -originalList $scriptsByCategory[$category]
                    })
                $searchTimer.Start()
            })

        # Dynamic resize handler for tab page controls
        $tabPage.Add_Resize({
                $searchBox.Size = [System.Drawing.Size]::new($tabPage.ClientSize.Width - 20, 25)
                $listBox.Size = [System.Drawing.Size]::new($tabPage.ClientSize.Width - 20, $tabPage.ClientSize.Height - 60)
            })

        $tabControls[$category] = @{ SearchBox = $searchBox; ListBox = $listBox }
        $tabControl.TabPages.Add($tabPage)
    }

    # Handle tab switch
    $tabControl.Add_SelectedIndexChanged({
            $selectedTab = $tabControl.SelectedTab
            if ($selectedTab -ne $null) {
                $category = $selectedTab.Text
                if ($tabControls.ContainsKey($category)) {
                    $controls = $tabControls[$category]
                    Update-ListBox -searchBox $controls.SearchBox -listBox $controls.ListBox -originalList $scriptsByCategory[$category]
                }
            }
        })

    # Add Execute Button with padding
    $executeButton = [System.Windows.Forms.Button]::new()
    $executeButton.Text = 'Execute'
    $executeButton.Size = [System.Drawing.Size]::new(150, 40)
    $executeButton.Location = [System.Drawing.Point]::new(($form.ClientSize.Width - 150) / 2, $form.ClientSize.Height - 100) # Adjusted for padding
    $executeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom
    $executeButton.BackColor = [System.Drawing.Color]::LightSkyBlue
    $executeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $executeButton.Add_Click({ Execute-Scripts -tabControl $tabControl })
    $form.Controls.Add($executeButton)

    # Show the Form
    [void] $form.ShowDialog()
}

#endregion

# Call the function to create the GUI
Create-GUI

# End of script
