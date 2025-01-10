<#
.SYNOPSIS
    PowerShell GUI for Executing Scripts Organized by Tabs with Real-Time Search.

.DESCRIPTION
    Dynamically reads the current folder and its subfolders, creating tabs for each subfolder.
    Allows real-time script search limited to the current selected tab and executes selected scripts.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: January 10, 2025
#>

# Hide PowerShell console window
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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Retrieve scripts in current root folder and subfolders
function Get-ScriptsByCategory {
    $rootFolder = (Get-Location).Path
    Write-Host "Root Folder: $rootFolder" -ForegroundColor Cyan
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

# Update the list box in real-time based on search text
function Update-ListBox {
    param (
        [System.Windows.Forms.TextBox]$SearchBox,
        [System.Windows.Forms.CheckedListBox]$ListBox,
        [System.Collections.ObjectModel.Collection[System.IO.FileInfo]]$OriginalList
    )

    $searchText = $SearchBox.Text.Trim().ToLower()
    $ListBox.BeginUpdate()
    $ListBox.Items.Clear()

    # Filter scripts based on search text
    $matchingScripts = $OriginalList | Where-Object { $_.Name.ToLower().Contains($searchText) }
    if ($matchingScripts) {
        foreach ($script in $matchingScripts) {
            $ListBox.Items.Add($script.Name)
        }
    } else {
        $ListBox.Items.Add("<No matching scripts found>")
    }

    $ListBox.EndUpdate()
}

# Create and display the GUI
function Create-GUI {
    # Form Setup
    $Form = [System.Windows.Forms.Form]::new()
    $Form.Text = 'SysAdmin Tool Set Interface'
    $Form.Size = [System.Drawing.Size]::new(1200, 900)
    $Form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $Form.BackColor = [System.Drawing.Color]::WhiteSmoke

    # TabControl for script categories
    $TabControl = [System.Windows.Forms.TabControl]::new()
    $TabControl.Size = [System.Drawing.Size]::new($Form.Width - 40, $Form.Height - 150)
    $TabControl.Location = [System.Drawing.Point]::new(10, 10)
    $TabControl.Anchor = 'Top, Left, Right, Bottom'
    $Form.Controls.Add($TabControl)

    # Fetch script categories and populate tabs
    $ScriptsByCategory = Get-ScriptsByCategory
    $TabControls = @{}

    foreach ($Category in $ScriptsByCategory.Keys) {
        # Create a tab for each category
        $TabPage = [System.Windows.Forms.TabPage]::new()
        $TabPage.Text = $Category

        # Search Box
        $SearchBox = [System.Windows.Forms.TextBox]::new()
        $SearchBox.Size = [System.Drawing.Size]::new($TabPage.Width - 20, 25)
        $SearchBox.Location = [System.Drawing.Point]::new(10, 10)
        $SearchBox.Font = [System.Drawing.Font]::new("Arial", 10)
        $SearchBox.Anchor = 'Top, Left, Right'
        $TabPage.Controls.Add($SearchBox)

        # ListBox for scripts
        $ListBox = [System.Windows.Forms.CheckedListBox]::new()
        $ListBox.Size = [System.Drawing.Size]::new($TabPage.Width - 20, $TabPage.Height - 80)
        $ListBox.Location = [System.Drawing.Point]::new(10, 40)
        $ListBox.Font = [System.Drawing.Font]::new("Arial", 9)
        $ListBox.Anchor = 'Top, Left, Right, Bottom'
        $ListBox.ScrollAlwaysVisible = $true
        $TabPage.Controls.Add($ListBox)

        # Capture variables for this tab
        $CurrentScripts = $ScriptsByCategory[$Category]
        $CurrentSearchBox = $SearchBox
        $CurrentListBox = $ListBox

        # Add TextChanged event for real-time search
        $SearchBox.Add_TextChanged({
            Update-ListBox -SearchBox $CurrentSearchBox -ListBox $CurrentListBox -OriginalList $CurrentScripts
        })

        # Populate the ListBox initially
        Update-ListBox -SearchBox $SearchBox -ListBox $ListBox -OriginalList $CurrentScripts

        # Add controls to the dictionary for later access
        $TabControls[$Category] = @{
            SearchBox = $SearchBox
            ListBox = $ListBox
            Scripts = $CurrentScripts
        }

        # Add the TabPage to the TabControl
        $TabControl.TabPages.Add($TabPage)
    }

    # Execute Button
    $ExecuteButton = [System.Windows.Forms.Button]::new()
    $ExecuteButton.Text = 'Execute'
    $ExecuteButton.Size = [System.Drawing.Size]::new(150, 40)
    $ExecuteButton.Location = [System.Drawing.Point]::new(($Form.ClientSize.Width - 150) / 2, $Form.ClientSize.Height - 80)
    $ExecuteButton.Anchor = 'Bottom'
    $ExecuteButton.BackColor = [System.Drawing.Color]::LightSkyBlue
    $ExecuteButton.FlatStyle = 'Flat'
    $ExecuteButton.Add_Click({
        $ScriptsExecuted = $false

        $SelectedTab = $TabControl.SelectedTab
        if ($SelectedTab -ne $null) {
            $Category = $SelectedTab.Text
            $Controls = $TabControls[$Category]

            foreach ($ScriptName in $Controls.ListBox.CheckedItems) {
                if ($ScriptName -eq "<No matching scripts found>") { continue }
                $ScriptPath = $Controls.Scripts | Where-Object { $_.Name -eq $ScriptName } | Select-Object -ExpandProperty FullName
                if (Test-Path $ScriptPath) {
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ScriptPath`"" -NoNewWindow
                    Write-Host "Executed: $ScriptPath" -ForegroundColor Green
                    $ScriptsExecuted = $true
                } else {
                    [System.Windows.Forms.MessageBox]::Show("Script not found: $ScriptPath", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }
        }

        if (-not $ScriptsExecuted) {
            [System.Windows.Forms.MessageBox]::Show("No scripts selected for execution.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    $Form.Controls.Add($ExecuteButton)

    # Show the Form
    [void] $Form.ShowDialog()
}

# Run the GUI
Create-GUI

# End of script
