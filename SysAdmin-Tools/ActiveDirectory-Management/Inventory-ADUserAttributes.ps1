<##
.SYNOPSIS
    PowerShell Script for Retrieving Active Directory User Attributes with Filters for Active, Inactive, and inetOrgPerson Accounts.

.DESCRIPTION
    This script retrieves detailed user attributes from Active Directory, providing administrators the option to filter by active, inactive, and inetOrgPerson accounts. The script maintains a user-friendly GUI for easy operation and ensures detailed logging for troubleshooting and audit purposes.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: May 30, 2025
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
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

Import-Module ActiveDirectory
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Log setup
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

function Log-Message {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $entry -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log: $_"
    }
    Write-Host $entry
}

function Get-AllDomainFQDNs {
    try {
        $domains = (Get-ADForest).Domains
        Log-Message "Retrieved domain FQDNs: $($domains -join ', ')" "DEBUG"
        return $domains
    } catch {
        Log-Message "Failed to retrieve domain FQDNs: $_" "ERROR"
        return @()
    }
}

function Export-ADUserAttributes {
    param (
        [string[]]$Attributes,
        [string]$DomainFQDN,
        [string]$OutputPath,
        [string]$UserStatus,
        [bool]$IncludeInetOrgPerson
    )
    try {
        $filter = "(objectClass=user)"

        if ($IncludeInetOrgPerson) {
            $filter = "(|(objectClass=user)(objectClass=inetOrgPerson))"
        }

        switch ($UserStatus) {
            "Active" { $filter = "(&" + $filter + "(!(userAccountControl:1.2.840.113556.1.4.803:=2)))" }
            "Inactive" { $filter = "(&" + $filter + "(userAccountControl:1.2.840.113556.1.4.803:=2))" }
        }

        Log-Message "Using LDAP filter: $filter" "DEBUG"
        Log-Message "Querying domain: $DomainFQDN" "INFO"

        $users = Get-ADUser -LDAPFilter $filter -Properties $Attributes -Server $DomainFQDN -ErrorAction Stop

        if ($users.Count -eq 0) {
            Log-Message "No users found in domain $DomainFQDN using provided filters." "WARNING"
            return $false
        }

        $users | Select-Object -Property $Attributes | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Log-Message "Export completed successfully. File saved at: $OutputPath" "INFO"
        return $true
    } catch {
        Log-Message "Error exporting user attributes: $_" "ERROR"
        return $false
    }
}

function Show-ExportForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Export AD User Attributes'
    $form.Size = New-Object System.Drawing.Size(420, 480)
    $form.StartPosition = 'CenterScreen'

    $comboBoxDomain = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomain.Location = '10,50'; $comboBoxDomain.Size = '380,20'
    $comboBoxDomain.DropDownStyle = 'DropDownList'
    $comboBoxDomain.Items.AddRange((Get-AllDomainFQDNs))
    if ($comboBoxDomain.Items.Count -gt 0) { $comboBoxDomain.SelectedIndex = 0 }
    $form.Controls.Add($comboBoxDomain)

    $comboBoxStatus = New-Object System.Windows.Forms.ComboBox
    $comboBoxStatus.Location = '10,110'; $comboBoxStatus.Size = '380,20'
    $comboBoxStatus.DropDownStyle = 'DropDownList'
    $comboBoxStatus.Items.AddRange(@("All","Active","Inactive")); $comboBoxStatus.SelectedIndex = 0
    $form.Controls.Add($comboBoxStatus)

    $checkBoxInetOrgPerson = New-Object System.Windows.Forms.CheckBox
    $checkBoxInetOrgPerson.Text = 'Include inetOrgPerson Accounts'
    $checkBoxInetOrgPerson.Location = '10,140'; $form.Controls.Add($checkBoxInetOrgPerson)

    $listBoxAttributes = New-Object System.Windows.Forms.CheckedListBox
    $listBoxAttributes.Location = '10,200'; $listBoxAttributes.Size = '380,150'
    $listBoxAttributes.Items.AddRange(@("samAccountName","Name","GivenName","Surname","DisplayName","Mail","Department","Title"))
    $form.Controls.Add($listBoxAttributes)

    $buttonExport = New-Object System.Windows.Forms.Button
    $buttonExport.Text = 'Export'; $buttonExport.Location = '10,390'; $buttonExport.Size = '180,30'
    $buttonExport.Add_Click({
        $attrs = $listBoxAttributes.CheckedItems
        $domain = $comboBoxDomain.SelectedItem
        $status = $comboBoxStatus.SelectedItem
        $includeInetOrg = $checkBoxInetOrgPerson.Checked
        $output = "$([Environment]::GetFolderPath('MyDocuments'))\${scriptName}_${domain}_${status}_${timestamp}.csv"

        if ($attrs.Count -eq 0 -or [string]::IsNullOrWhiteSpace($domain)) {
            [System.Windows.Forms.MessageBox]::Show('Please select attributes and a domain.')
            Log-Message "Export aborted: missing attribute or domain selection." "WARNING"
            return
        }

        $exported = Export-ADUserAttributes -Attributes $attrs -DomainFQDN $domain -OutputPath $output -UserStatus $status -IncludeInetOrgPerson $includeInetOrg

        if ($exported) {
            [System.Windows.Forms.MessageBox]::Show("Export completed:\n$output")
        } else {
            [System.Windows.Forms.MessageBox]::Show('Export failed. Check logs.')
        }
    })
    $form.Controls.Add($buttonExport)

    $buttonClose = New-Object System.Windows.Forms.Button
    $buttonClose.Text = 'Close'; $buttonClose.Location = '210,390'; $buttonClose.Size = '180,30'
    $buttonClose.Add_Click({ $form.Close() }); $form.Controls.Add($buttonClose)

    $form.Add_Shown({ $form.Activate() })
    [void]$form.ShowDialog()
}

Show-ExportForm

# End of script
