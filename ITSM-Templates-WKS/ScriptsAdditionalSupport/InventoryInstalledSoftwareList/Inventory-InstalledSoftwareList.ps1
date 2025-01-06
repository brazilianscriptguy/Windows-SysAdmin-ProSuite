<#
.SYNOPSIS
    PowerShell Script to Retrieve Installed Software (x86 and x64) with GUID and Enhanced GUI

.DESCRIPTION
    This script provides a graphical user interface (GUI) that allows users to export a comprehensive list of installed software on a Windows system. It retrieves both 32-bit and 64-bit installed applications, including their Display Name, Display Version, Identifying Number (GUID), and Architecture. Users can choose to save the exported list to the default Documents folder or specify a custom output path.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.0.0 - December 06, 2025

.NOTES
    - Requires running with administrative privileges to access certain registry keys.
    - The script hides the PowerShell console window during execution for a cleaner user experience.
    - Outputs are saved in CSV format with filenames that include the computer name and timestamp.
    - Ensures that the specified custom output path is valid and accessible.
    - Handles both default and custom path selections through the GUI.
    - Provides error handling and user feedback via message boxes for successful exports and encountered issues.
    - Utilizes PowerShell cmdlets like `Get-ItemProperty` and `Export-Csv` to gather and export data.
    - Designed for compatibility with both 32-bit and 64-bit Windows environments.
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

# Load necessary .NET assemblies for GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Function to convert the registry path to the desired format
function Convert-RegistryPath {
    param ([string]$path)
    $convertedPath = $path -replace 'HKEY_LOCAL_MACHINE', 'HKLM:' -replace 'Microsoft.PowerShell.Core\\Registry::', ''
    return $convertedPath
}

# Function to get installed programs
function Get-InstalledPrograms {
    # Retrieve installed programs (64-bit and 32-bit) and combine them
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedPrograms = $registryPaths | ForEach-Object {
        Get-ItemProperty -Path $_ |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion,
                      @{Name="IdentifyingNumber"; Expression={Convert-RegistryPath $_.PSPath}},
                      @{Name="Architecture"; Expression={if ($_.PSPath -match 'WOW6432Node') {'32-bit'} else {'64-bit'}}}
    }
    return $installedPrograms
}

# Main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "List Installed Software"
$form.Size = New-Object System.Drawing.Size(400, 250)
$form.StartPosition = 'CenterScreen'

# Radio buttons for output option
$radioButtons = @{
    DefaultPath = New-Object System.Windows.Forms.RadioButton
    CustomPath  = New-Object System.Windows.Forms.RadioButton
}
$y = 10
foreach ($key in $radioButtons.Keys) {
    $radio = $radioButtons[$key]
    $radio.Text = if ($key -eq 'DefaultPath') {"Use Default Documents Folder"} else {"Specify Custom Path"}
    $radio.Location = New-Object System.Drawing.Point(10, $y)
    $radio.AutoSize = $true
    $radio.Checked = $key -eq 'DefaultPath'
    $form.Controls.Add($radio)
    $y += 20
}

# Label and TextBox for custom output path
$label = New-Object System.Windows.Forms.Label
$label.Text = "Custom Output Path:"
$label.Location = New-Object System.Drawing.Point(10, 50)
$label.AutoSize = $true
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 70)
$textBox.Size = New-Object System.Drawing.Size(370, 20)
$textBox.Enabled = $false
$form.Controls.Add($textBox)

# Enable/Disable TextBox based on radio button selection
$radioButtons.CustomPath.Add_Click({ $textBox.Enabled = $true })
$radioButtons.DefaultPath.Add_Click({ $textBox.Enabled = $false })

# OK and Cancel buttons
$buttons = @{
    OK     = New-Object System.Windows.Forms.Button
    Cancel = New-Object System.Windows.Forms.Button
}
$y = 100
foreach ($key in $buttons.Keys) {
    $button = $buttons[$key]
    $button.Text = $key
    $button.Location = New-Object System.Drawing.Point(10, $y)
    $button.Size = New-Object System.Drawing.Size(75, 23)
    $form.Controls.Add($button)
    $y += 30
    if ($key -eq 'OK') {
        $button.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.AcceptButton = $button
    } else {
        $button.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.CancelButton = $button
    }
}

# Show the form and get the result
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    # Enhanced filename to include COMPUTERNAME
    $outputFileName = "Installed-Inventory-SoftwaresList_${env:COMPUTERNAME}-$timestamp.csv"
    
    if ($radioButtons.DefaultPath.Checked) {
        $outputPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) $outputFileName
    } elseif ($radioButtons.CustomPath.Checked -and -not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        $outputPath = Join-Path $textBox.Text $outputFileName
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please enter a valid custom output path.", "Error")
        return
    }
    
    $allInstalledPrograms = Get-InstalledPrograms
    if ($allInstalledPrograms -ne $null -and $allInstalledPrograms.Count -gt 0) {
        try {
            $allInstalledPrograms | Export-Csv -Path $outputPath -NoTypeInformation -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show("List of installed software exported successfully to:`n$outputPath", "Export Successful")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to export the list of installed software. Error: $_", "Export Failed")
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("No installed software found to export.", "No Data")
    }
}

# End of script
