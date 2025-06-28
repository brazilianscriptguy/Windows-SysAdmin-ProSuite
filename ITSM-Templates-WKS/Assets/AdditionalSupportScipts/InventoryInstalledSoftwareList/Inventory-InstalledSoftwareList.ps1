<#
.SYNOPSIS
    PowerShell GUI to Export Installed Software Inventory (x86 and x64) in ANSI Format

.DESCRIPTION
    Exports installed software (32/64-bit) with Display Name, Version, Registry Path, and Architecture.
    Outputs a clean CSV using ANSI encoding for legacy compatibility.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.2.0 - June 19, 2025
#>

# Load required .NET assemblies for GUI support
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hide PowerShell console window during execution
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
        ShowWindow(handle, 0); // SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // SW_SHOW
    }
}
"@
[Window]::Hide()

# Function to retrieve installed software (from both 32-bit and 64-bit registry paths)
function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $registryPaths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
            [PSCustomObject]@{
                DisplayName       = $_.DisplayName
                DisplayVersion    = $_.DisplayVersion
                IdentifyingNumber = ($_.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::', '') -replace 'HKEY_LOCAL_MACHINE', 'HKLM:'
                Architecture      = if ($_.PSPath -match 'WOW6432Node') { '32-bit' } else { '64-bit' }
            }
        }
    }
}

# Build GUI form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Export Installed Software"
$form.Size = New-Object System.Drawing.Size(420, 240)
$form.StartPosition = 'CenterScreen'

# Radio button: use default (Documents) folder
$radioDefault = New-Object System.Windows.Forms.RadioButton
$radioDefault.Text = "Use Documents Folder"
$radioDefault.Location = New-Object System.Drawing.Point(10, 10)
$radioDefault.Checked = $true
$form.Controls.Add($radioDefault)

# Radio button: use custom folder
$radioCustom = New-Object System.Windows.Forms.RadioButton
$radioCustom.Text = "Use Custom Folder"
$radioCustom.Location = New-Object System.Drawing.Point(10, 35)
$form.Controls.Add($radioCustom)

# Label for custom path
$labelPath = New-Object System.Windows.Forms.Label
$labelPath.Text = "Custom Output Path:"
$labelPath.Location = New-Object System.Drawing.Point(10, 60)
$labelPath.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($labelPath)

# Text box for custom path input
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 80)
$textBox.Size = New-Object System.Drawing.Size(380, 20)
$textBox.Enabled = $false
$form.Controls.Add($textBox)

# Enable/disable textbox depending on radio button
$radioCustom.Add_Click({ $textBox.Enabled = $true })
$radioDefault.Add_Click({ $textBox.Enabled = $false })

# OK button
$btnOK = New-Object System.Windows.Forms.Button
$btnOK.Text = "OK"
$btnOK.Location = New-Object System.Drawing.Point(10, 120)
$btnOK.Size = New-Object System.Drawing.Size(75, 23)
$form.Controls.Add($btnOK)
$form.AcceptButton = $btnOK

# Cancel button
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(100, 120)
$btnCancel.Size = New-Object System.Drawing.Size(75, 23)
$form.Controls.Add($btnCancel)
$form.CancelButton = $btnCancel

# OK button click logic
$btnOK.Add_Click({
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $fileName = "Installed-Inventory-SoftwaresList_$($env:COMPUTERNAME)_$timestamp.csv"

    # Determine output path based on selection
    if ($radioDefault.Checked) {
        $outputPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("MyDocuments"), $fileName)
    } elseif ($radioCustom.Checked -and -not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        if (-not (Test-Path $textBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("The custom path is invalid or not found.", "Path Error", 'OK', 'Error')
            return
        }
        $outputPath = [System.IO.Path]::Combine($textBox.Text, $fileName)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid path.", "Error", 'OK', 'Error')
        return
    }

    # Gather software inventory and export to CSV
    $programs = Get-InstalledPrograms
    if ($programs.Count -gt 0) {
        try {
            # Manually write CSV lines to ensure ANSI encoding and formatting
            $header = '"DisplayName","DisplayVersion","IdentifyingNumber","Architecture"'
            $lines = $programs | ForEach-Object {
                '"' + ($_.DisplayName -replace '"','""') + '","' +
                ($_.DisplayVersion -replace '"','""') + '","' +
                ($_.IdentifyingNumber -replace '"','""') + '","' +
                ($_.Architecture -replace '"','""') + '"'
            }

            $output = @($header) + $lines
            $output | Out-File -FilePath $outputPath -Encoding Default

            # Notify user and open file
            [System.Windows.Forms.MessageBox]::Show("Export completed:`n$outputPath", "Done", 'OK', 'Information')
            Start-Process "notepad.exe" -ArgumentList "`"$outputPath`""
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error writing to file: $_", "Export Error", 'OK', 'Error')
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("No installed software found.", "No Results", 'OK', 'Information')
    }

    $form.Close()
})

# Cancel button click logic
$btnCancel.Add_Click({ $form.Close() })

# Show GUI on top of all windows
$form.Topmost = $true
$form.ShowDialog()

# End of script
