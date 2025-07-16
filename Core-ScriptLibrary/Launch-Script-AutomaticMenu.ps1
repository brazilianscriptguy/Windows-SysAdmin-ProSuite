<#
.SYNOPSIS
    PowerShell GUI for Executing Scripts Organized by Tabs with Real-Time Search

.DESCRIPTION
    Dynamically scans current and subfolders, creates a tab per subfolder,
    displays scripts with live filtering, and allows the execution of selected scripts from each category.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Version 2.0 - July 16, 2025
#>

#region --- Hide Console ---
function Hide-Console {
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
    }
"@
    [Window]::Hide()
}
Hide-Console
#endregion

#region --- Load Assemblies ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
#endregion

#region --- Get Scripts Per Folder ---
function Get-ScriptsByCategory {
    $rootFolder = (Get-Location).Path
    Write-Host "Scanning root folder: $rootFolder" -ForegroundColor Cyan

    $directories = Get-ChildItem -Path $rootFolder -Directory -Recurse
    $scriptsByCategory = @{}

    foreach ($dir in $directories) {
        $scriptFiles = Get-ChildItem -Path $dir.FullName -Filter "*.ps1" -File
        if ($scriptFiles.Count -gt 0) {
            $scriptsByCategory[$dir.Name] = $scriptFiles | Sort-Object -Property Name
        }
    }

    return $scriptsByCategory
}
#endregion

#region --- Real-time ListBox Filter ---
function Update-ListBox {
    param (
        [System.Windows.Forms.TextBox]$SearchBox,
        [System.Windows.Forms.CheckedListBox]$ListBox,
        [System.Collections.ObjectModel.Collection[System.IO.FileInfo]]$OriginalList
    )

    $searchText = $SearchBox.Text.Trim().ToLower()
    $ListBox.BeginUpdate()
    $ListBox.Items.Clear()

    $matchingScripts = $OriginalList | Where-Object { $_.Name.ToLower().Contains($searchText) }
    if ($matchingScripts.Count -gt 0) {
        foreach ($script in $matchingScripts) {
            $ListBox.Items.Add($script.Name)
        }
    } else {
        $ListBox.Items.Add("<No matching scripts found>")
    }

    $ListBox.EndUpdate()
}
#endregion

#region --- GUI Layout and Execution ---
function Create-GUI {
    # Main Form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "SysAdmin Tool Set Interface"
    $Form.Size = New-Object System.Drawing.Size(1200, 900)
    $Form.StartPosition = "CenterScreen"
    $Form.BackColor = [System.Drawing.Color]::WhiteSmoke

    # TabControl
    $TabControl = New-Object System.Windows.Forms.TabControl
    $TabControl.Size = New-Object System.Drawing.Size($Form.Width - 40, $Form.Height - 150)
    $TabControl.Location = New-Object System.Drawing.Point(10, 10)
    $TabControl.Anchor = 'Top, Left, Right, Bottom'
    $Form.Controls.Add($TabControl)

    # Populate Tabs with Script Lists
    $ScriptsByCategory = Get-ScriptsByCategory
    $TabControls = @{}

    foreach ($Category in $ScriptsByCategory.Keys) {
        $TabPage = New-Object System.Windows.Forms.TabPage
        $TabPage.Text = $Category

        # Search TextBox
        $SearchBox = New-Object System.Windows.Forms.TextBox
        $SearchBox.Size = New-Object System.Drawing.Size($TabPage.Width - 20, 25)
        $SearchBox.Location = New-Object System.Drawing.Point(10, 10)
        $SearchBox.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        $SearchBox.Anchor = 'Top, Left, Right'
        $TabPage.Controls.Add($SearchBox)

        # CheckedListBox for script files
        $ListBox = New-Object System.Windows.Forms.CheckedListBox
        $ListBox.Size = New-Object System.Drawing.Size($TabPage.Width - 20, $TabPage.Height - 80)
        $ListBox.Location = New-Object System.Drawing.Point(10, 40)
        $ListBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
        $ListBox.Anchor = 'Top, Left, Right, Bottom'
        $ListBox.ScrollAlwaysVisible = $true
        $TabPage.Controls.Add($ListBox)

        # Wire up search
        $CurrentScripts = $ScriptsByCategory[$Category]
        $SearchBox.Add_TextChanged({
            Update-ListBox -SearchBox $SearchBox -ListBox $ListBox -OriginalList $CurrentScripts
        })

        # Initial population
        Update-ListBox -SearchBox $SearchBox -ListBox $ListBox -OriginalList $CurrentScripts

        # Store control references
        $TabControls[$Category] = @{
            SearchBox = $SearchBox
            ListBox   = $ListBox
            Scripts   = $CurrentScripts
        }

        # Add to GUI
        $TabControl.TabPages.Add($TabPage)
    }

    # Execute Button
    $ExecuteButton = New-Object System.Windows.Forms.Button
    $ExecuteButton.Text = "Execute Selected"
    $ExecuteButton.Size = New-Object System.Drawing.Size(180, 40)
    $ExecuteButton.Location = New-Object System.Drawing.Point(($Form.ClientSize.Width - 180) / 2, $Form.ClientSize.Height - 80)
    $ExecuteButton.Anchor = "Bottom"
    $ExecuteButton.BackColor = [System.Drawing.Color]::LightSkyBlue
    $ExecuteButton.FlatStyle = "Flat"

    $ExecuteButton.Add_Click({
        $ScriptsExecuted = $false
        $SelectedTab = $TabControl.SelectedTab

        if ($SelectedTab -ne $null) {
            $Category = $SelectedTab.Text
            $Controls = $TabControls[$Category]

            foreach ($ScriptName in $Controls.ListBox.CheckedItems) {
                if ($ScriptName -eq "<No matching scripts found>") { continue }

                $ScriptPath = ($Controls.Scripts | Where-Object { $_.Name -eq $ScriptName }).FullName
                if (Test-Path $ScriptPath) {
                    try {
                        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"" -NoNewWindow
                        Write-Host "Executed: $ScriptPath" -ForegroundColor Green
                        $ScriptsExecuted = $true
                    } catch {
                        [System.Windows.Forms.MessageBox]::Show("Failed to start script: $ScriptPath", "Execution Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Script not found: $ScriptPath", "File Missing", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        }

        if (-not $ScriptsExecuted) {
            [System.Windows.Forms.MessageBox]::Show("No scripts selected for execution.", "Information", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })

    $Form.Controls.Add($ExecuteButton)

    # Show GUI
    [void]$Form.ShowDialog()
}
#endregion

# Launch GUI
Create-GUI
