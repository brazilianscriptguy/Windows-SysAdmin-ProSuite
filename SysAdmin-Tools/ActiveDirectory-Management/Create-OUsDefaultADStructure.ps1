<#
.SYNOPSIS
    PowerShell Script for Creating a Default AD OU Structure.

.DESCRIPTION
    This script helps to create a standardized AD infrastructure by defining predefined Organizational Units (OUs), 
    streamlining domain setup or reorganization within Active Directory.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
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

# Import necessary assemblies and modules
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Setup form and components
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Organizational Unit Management'
$form.Size = New-Object System.Drawing.Size(500, 280)
$form.StartPosition = 'CenterScreen'

# Label for OU search
$labelOUSearch = New-Object System.Windows.Forms.Label
$labelOUSearch.Text = 'Search for an OU:'
$labelOUSearch.Location = New-Object System.Drawing.Point(10, 20)
$labelOUSearch.AutoSize = $true
$form.Controls.Add($labelOUSearch)

# TextBox for OU search
$txtOUSearch = New-Object System.Windows.Forms.TextBox
$txtOUSearch.Location = New-Object System.Drawing.Point(10, 50)
$txtOUSearch.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($txtOUSearch)

# ComboBox for displaying OUs
$cmbOUs = New-Object System.Windows.Forms.ComboBox
$cmbOUs.Location = New-Object System.Drawing.Point(10, 80)
$cmbOUs.Size = New-Object System.Drawing.Size(450, 20)
$cmbOUs.DropDownStyle = 'DropDownList'
$form.Controls.Add($cmbOUs)

# Function to load and refresh the OUs list
function Load-OUs {
    $cmbOUs.Items.Clear()
    $global:allOUs = Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName
    $global:allOUs | ForEach-Object { $cmbOUs.Items.Add($_) }
    if ($cmbOUs.Items.Count -gt 0) {
        $cmbOUs.SelectedIndex = 0
    }
}

# Button to load OUs
$btnLoadOUs = New-Object System.Windows.Forms.Button
$btnLoadOUs.Text = 'Refresh OUs List'
$btnLoadOUs.Location = New-Object System.Drawing.Point(10, 110)
$btnLoadOUs.Size = New-Object System.Drawing.Size(150, 23)
$btnLoadOUs.Add_Click({ Load-OUs })
$form.Controls.Add($btnLoadOUs)

# Search functionality
$txtOUSearch.Add_TextChanged({
        $searchText = $txtOUSearch.Text
        $filteredOUs = $global:allOUs | Where-Object { $_ -like "*$searchText*" }
        $cmbOUs.Items.Clear()
        $filteredOUs | ForEach-Object { $cmbOUs.Items.Add($_) }
        if ($cmbOUs.Items.Count -gt 0) {
            $cmbOUs.SelectedIndex = 0
        } else {
            $cmbOUs.Text = 'No matching OU found'
        }
    })

# Label for Parent OU name
$labelParentOU = New-Object System.Windows.Forms.Label
$labelParentOU.Text = 'Parent OU Name:'
$labelParentOU.Location = New-Object System.Drawing.Point(10, 150)
$labelParentOU.AutoSize = $true
$form.Controls.Add($labelParentOU)

# TextBox for Parent OU name input
$txtParentOU = New-Object System.Windows.Forms.TextBox
$txtParentOU.Location = New-Object System.Drawing.Point(10, 170)
$txtParentOU.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($txtParentOU)

# Button to create Parent OU
$btnCreateParentOU = New-Object System.Windows.Forms.Button
$btnCreateParentOU.Text = 'Create Parent OU'
$btnCreateParentOU.Location = New-Object System.Drawing.Point(10, 200)
$btnCreateParentOU.Size = New-Object System.Drawing.Size(150, 23)
$btnCreateParentOU.Add_Click({
        $targetOU = $cmbOUs.SelectedItem.ToString()
        $parentOU = $txtParentOU.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($targetOU) -or [string]::IsNullOrWhiteSpace($parentOU)) {
            [System.Windows.Forms.MessageBox]::Show("Please select the target OU and enter a valid Parent OU name.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        try {
            New-ADOrganizationalUnit -Name $parentOU -Path $targetOU -ProtectedFromAccidentalDeletion $true
            [System.Windows.Forms.MessageBox]::Show("Parent OU '$parentOU' created successfully in '$targetOU'.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            $global:fullParentPath = "OU=$parentOU,$targetOU"
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error creating Parent OU '$parentOU': $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
    })
$form.Controls.Add($btnCreateParentOU)

# Button to create standard child OUs
$btnCreateChildOUs = New-Object System.Windows.Forms.Button
$btnCreateChildOUs.Text = 'Create Standard Child OUs'
$btnCreateChildOUs.Location = New-Object System.Drawing.Point(180, 200)
$btnCreateChildOUs.Size = New-Object System.Drawing.Size(180, 23)
$btnCreateChildOUs.Add_Click({
        $targetOU = if ($global:fullParentPath) { $global:fullParentPath } else { $cmbOUs.SelectedItem.ToString() }
        $standardChildOUs = @("Computers", "Printers", "Groups", "Users")
        foreach ($childOU in $standardChildOUs) {
            try {
                New-ADOrganizationalUnit -Name $childOU -Path $targetOU -ProtectedFromAccidentalDeletion $true
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error creating Child OU '$childOU': $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Standard Child OUs created successfully under '$targetOU'.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
$form.Controls.Add($btnCreateChildOUs)

# Load OUs initially
Load-OUs

# Show the form
$form.ShowDialog() | Out-Null

# End of script
