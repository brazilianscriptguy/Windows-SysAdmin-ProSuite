<#
.SYNOPSIS
    PowerShell Script for Adding Workstations to AD OUs and Granting Permissions.

.DESCRIPTION
    This script automates the process of adding workstations to specific Organizational Units (OUs) 
    in Active Directory and assigns the necessary permissions for workstations to join the domain, 
    streamlining domain management.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: March 21, 2025
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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Import-Module ActiveDirectory

# Grant-ComputerJoinPermission Function
function Grant-ComputerJoinPermission {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(Position = 0, Mandatory = $true)]
        [Security.Principal.NTAccount] $Identity,

        [parameter(Position = 1, Mandatory = $true)]
        [alias("ComputerName")]
        [String[]] $Name,

        [String] $Domain,
        [String] $Server,
        [Management.Automation.PSCredential] $Credential
    )

    begin {
        # Validate if identity exists
        try {
            [Void]$Identity.Translate([Security.Principal.SecurityIdentifier])
        } catch [Security.Principal.IdentityNotMappedException] {
            throw "Unable to identify identity - '$Identity'"
        }

        # Create DirectorySearcher object
        $Searcher = [ADSISearcher]""
        [Void]$Searcher.PropertiesToLoad.Add("distinguishedName")

        function Initialize-DirectorySearcher {
            if ($Domain) {
                if ($Server) {
                    $path = "LDAP://$Server/$Domain"
                } else {
                    $path = "LDAP://$Domain"
                }
            } else {
                if ($Server) {
                    $path = "LDAP://$Server"
                } else {
                    $path = ""
                }
            }

            if ($Credential) {
                $networkCredential = $Credential.GetNetworkCredential()
                $dirEntry = New-Object DirectoryServices.DirectoryEntry(
                    $path,
                    $networkCredential.UserName,
                    $networkCredential.Password
                )
            } else {
                $dirEntry = [ADSI]$path
            }

            $Searcher.SearchRoot = $dirEntry
            $Searcher.Filter = "(objectClass=domain)"
            try {
                [Void]$Searcher.FindOne()
            } catch [Management.Automation.MethodInvocationException] {
                throw $_.Exception.InnerException
            }
        }

        Initialize-DirectorySearcher

        # AD rights GUIDs
        $AD_RIGHTS_GUID_RESET_PASSWORD = "00299570-246D-11D0-A768-00AA006E0529"
        $AD_RIGHTS_GUID_VALIDATED_WRITE_DNS = "72E39547-7B18-11D1-ADEF-00C04FD8D5CD"
        $AD_RIGHTS_GUID_VALIDATED_WRITE_SPN = "F3A64788-5306-11D1-A9C5-0000F80367C1"
        $AD_RIGHTS_GUID_ACCT_RESTRICTIONS = "4C164200-20C0-11D0-A768-00AA006E0529"

        # Searches for a computer object; if found, returns its DirectoryEntry
        function Get-ComputerDirectoryEntry {
            param(
                [String]$name
            )
            $Searcher.Filter = "(&(objectClass=computer)(name=$name))"
            try {
                $searchResult = $Searcher.FindOne()
                if ($searchResult) {
                    $searchResult.GetDirectoryEntry()
                }
            } catch [Management.Automation.MethodInvocationException] {
                Write-Error -Exception $_.Exception.InnerException
            }
        }

        function Grant-ComputerJoinPermission {
            param(
                [String]$name
            )
            $domainName = $Searcher.SearchRoot.dc
            # Get computer DirectoryEntry
            $dirEntry = Get-ComputerDirectoryEntry $name
            if (-not $dirEntry) {
                Write-Error "Unable to find computer '$name' in domain '$domainName'" -Category ObjectNotFound
                return
            }
            if (-not $PSCmdlet.ShouldProcess($name, "Allow '$Identity' to join computer to domain '$domainName'")) {
                return
            }
            # Build list of access control entries (ACEs)
            $accessControlEntries = New-Object Collections.ArrayList
            # Reset password
            [Void]$accessControlEntries.Add((
                    New-Object DirectoryServices.ExtendedRightAccessRule(
                        $Identity,
                        [Security.AccessControl.AccessControlType]"Allow",
                        [Guid]$AD_RIGHTS_GUID_RESET_PASSWORD
                    )
                ))
            # Validated write to DNS host name
            [Void]$accessControlEntries.Add((
                    New-Object DirectoryServices.ActiveDirectoryAccessRule(
                        $Identity,
                        [DirectoryServices.ActiveDirectoryRights]"Self",
                        [Security.AccessControl.AccessControlType]"Allow",
                        [Guid]$AD_RIGHTS_GUID_VALIDATED_WRITE_DNS
                    )
                ))
            # Validated write to service principal name
            [Void]$accessControlEntries.Add((
                    New-Object DirectoryServices.ActiveDirectoryAccessRule(
                        $Identity,
                        [DirectoryServices.ActiveDirectoryRights]"Self",
                        [Security.AccessControl.AccessControlType]"Allow",
                        [Guid]$AD_RIGHTS_GUID_VALIDATED_WRITE_SPN
                    )
                ))
            # Write account restrictions
            [Void]$accessControlEntries.Add((
                    New-Object DirectoryServices.ActiveDirectoryAccessRule(
                        $Identity,
                        [DirectoryServices.ActiveDirectoryRights]"WriteProperty",
                        [Security.AccessControl.AccessControlType]"Allow",
                        [Guid]$AD_RIGHTS_GUID_ACCT_RESTRICTIONS
                    )
                ))
            # Get ActiveDirectorySecurity object
            $adSecurity = $dirEntry.ObjectSecurity
            # Add ACEs to ActiveDirectorySecurity object
            $accessControlEntries | ForEach-Object {
                $adSecurity.AddAccessRule($_)
            }
            # Commit changes
            try {
                $dirEntry.CommitChanges()
            } catch [Management.Automation.MethodInvocationException] {
                Write-Error -Exception $_.Exception.InnerException
            }
        }
    }

    process {
        foreach ($nameItem in $Name) {
            Grant-ComputerJoinPermission $nameItem
        }
    }
}

# Function to get the FQDN of the domain name and forest name
function Get-DomainFQDN {
    try {
        $ComputerSystem = Get-WmiObject Win32_ComputerSystem
        $Domain = $ComputerSystem.Domain
        return $Domain
    } catch {
        Write-Warning "Unable to fetch FQDN automatically."
        return "YourDomainHere"
    }
}

# Form creation
function Show-Form {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AD Computers Management Tool"
    $form.Size = New-Object System.Drawing.Size(600, 550) # Compact form size as in previous codes
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    # Status bar
    $statusBar = New-Object System.Windows.Forms.StatusStrip
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusBar.Items.Add($statusLabel)
    $form.Controls.Add($statusBar)
    $statusLabel.Text = "Ready"

    # Tab control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Location = New-Object System.Drawing.Point(10, 10)
    $tabControl.Size = New-Object System.Drawing.Size(570, 430) # Same as previous codes
    $form.Controls.Add($tabControl)

    # Tab pages
    $tabWorkstation = New-Object System.Windows.Forms.TabPage; $tabWorkstation.Text = "Workstation Info"
    $tabSettings = New-Object System.Windows.Forms.TabPage; $tabSettings.Text = "Settings"
    $tabControl.TabPages.AddRange(@($tabWorkstation, $tabSettings))

    # Workstation Info Tab
    $groupWorkstation = New-Object System.Windows.Forms.GroupBox
    $groupWorkstation.Text = "Workstation Information"
    $groupWorkstation.Location = New-Object System.Drawing.Point(10, 10)
    $groupWorkstation.Size = New-Object System.Drawing.Size(540, 200)
    $tabWorkstation.Controls.Add($groupWorkstation)

    $lblComputers = New-Object System.Windows.Forms.Label; $lblComputers.Text = "Computer Names:"; $lblComputers.Location = New-Object System.Drawing.Point(10, 20); $lblComputers.AutoSize = $true
    $txtComputers = New-Object System.Windows.Forms.TextBox; $txtComputers.Location = New-Object System.Drawing.Point(140, 20); $txtComputers.Size = New-Object System.Drawing.Size(380, 20)
    $txtComputers.Text = "Enter computer names separated by commas"
    $txtComputers.ForeColor = [System.Drawing.Color]::Gray
    $txtComputers.Add_Enter({
            if ($txtComputers.Text -eq "Enter computer names separated by commas") {
                $txtComputers.Text = ''
                $txtComputers.ForeColor = [System.Drawing.Color]::Black
            }
        })
    $txtComputers.Add_Leave({
            if ($txtComputers.Text -eq '') {
                $txtComputers.Text = "Enter computer names separated by commas"
                $txtComputers.ForeColor = [System.Drawing.Color]::Gray
            }
        })

    $lblFileInfo = New-Object System.Windows.Forms.Label; $lblFileInfo.Text = "No file selected"; $lblFileInfo.Location = New-Object System.Drawing.Point(140, 50); $lblFileInfo.Size = New-Object System.Drawing.Size(380, 20)

    $btnOpenFile = New-Object System.Windows.Forms.Button; $btnOpenFile.Text = "Select Computers List File"; $btnOpenFile.Location = New-Object System.Drawing.Point(140, 80); $btnOpenFile.Size = New-Object System.Drawing.Size(380, 30)

    $txtOutput = New-Object System.Windows.Forms.TextBox; $txtOutput.Location = New-Object System.Drawing.Point(140, 120); $txtOutput.Size = New-Object System.Drawing.Size(380, 70); $txtOutput.Multiline = $true; $txtOutput.ReadOnly = $true; $txtOutput.ScrollBars = 'Vertical'

    $groupWorkstation.Controls.AddRange(@($lblComputers, $txtComputers, $lblFileInfo, $btnOpenFile, $txtOutput))

    # Settings Tab
    $groupSettings = New-Object System.Windows.Forms.GroupBox
    $groupSettings.Text = "Account Settings"
    $groupSettings.Location = New-Object System.Drawing.Point(10, 10)
    $groupSettings.Size = New-Object System.Drawing.Size(540, 155) # Increased height to accommodate the new field
    $tabSettings.Controls.Add($groupSettings)

    # 25px vertical spacing between fields
    $lblOUSearch = New-Object System.Windows.Forms.Label; $lblOUSearch.Text = "OU Search:"; $lblOUSearch.Location = New-Object System.Drawing.Point(10, 20); $lblOUSearch.AutoSize = $true
    $txtOUSearch = New-Object System.Windows.Forms.TextBox; $txtOUSearch.Location = New-Object System.Drawing.Point(140, 20); $txtOUSearch.Size = New-Object System.Drawing.Size(380, 20)
    $txtOUSearch.Text = "Search OU..."
    $txtOUSearch.ForeColor = [System.Drawing.Color]::Gray
    $txtOUSearch.Add_Enter({
            if ($txtOUSearch.Text -eq "Search OU...") {
                $txtOUSearch.Text = ''
                $txtOUSearch.ForeColor = [System.Drawing.Color]::Black
            }
        })
    $txtOUSearch.Add_Leave({
            if ($txtOUSearch.Text -eq '') {
                $txtOUSearch.Text = "Search OU..."
                $txtOUSearch.ForeColor = [System.Drawing.Color]::Gray
            }
        })

    $lblOU = New-Object System.Windows.Forms.Label; $lblOU.Text = "OU:"; $lblOU.Location = New-Object System.Drawing.Point(10, 45); $lblOU.AutoSize = $true
    $cmbOU = New-Object System.Windows.Forms.ComboBox; $cmbOU.Location = New-Object System.Drawing.Point(140, 45); $cmbOU.Size = New-Object System.Drawing.Size(380, 20); $cmbOU.DropDownStyle = 'DropDownList'

    $lblSupportGroup = New-Object System.Windows.Forms.Label; $lblSupportGroup.Text = "Ingress Account:"; $lblSupportGroup.Location = New-Object System.Drawing.Point(10, 70); $lblSupportGroup.AutoSize = $true
    $txtSupportGroup = New-Object System.Windows.Forms.TextBox; $txtSupportGroup.Location = New-Object System.Drawing.Point(140, 70); $txtSupportGroup.Size = New-Object System.Drawing.Size(380, 20); $txtSupportGroup.Text = "domainingress@SCRIPTGUY.HQ"; $txtSupportGroup.ReadOnly = $true

    $lblDomainName = New-Object System.Windows.Forms.Label; $lblDomainName.Text = "FQDN Domain Name:"; $lblDomainName.Location = New-Object System.Drawing.Point(10, 95); $lblDomainName.AutoSize = $true
    $txtDomainName = New-Object System.Windows.Forms.TextBox; $txtDomainName.Location = New-Object System.Drawing.Point(140, 95); $txtDomainName.Size = New-Object System.Drawing.Size(380, 20); $txtDomainName.Text = Get-DomainFQDN; $txtDomainName.ReadOnly = $true

    # Description field
    $lblDescription = New-Object System.Windows.Forms.Label; $lblDescription.Text = "Description:"; $lblDescription.Location = New-Object System.Drawing.Point(10, 120); $lblDescription.AutoSize = $true
    $txtDescription = New-Object System.Windows.Forms.TextBox; $txtDescription.Location = New-Object System.Drawing.Point(140, 120); $txtDescription.Size = New-Object System.Drawing.Size(380, 20); $txtDescription.Text = "Workstation - Default ITSM-Templates"; $txtDescription.ReadOnly = $true

    $groupSettings.Controls.AddRange(@($lblOUSearch, $txtOUSearch, $lblOU, $cmbOU, $lblSupportGroup, $txtSupportGroup, $lblDomainName, $txtDomainName, $lblDescription, $txtDescription))

    # Populate OU ComboBox
    $allOUs = Get-ADOrganizationalUnit -Filter 'Name -like "Computers*"' | Select-Object -ExpandProperty DistinguishedName

    function Update-OU {
        $cmbOU.Items.Clear()
        $searchText = $txtOUSearch.Text
        $filteredOUs = $allOUs | Where-Object { $_ -like "*$searchText*" }
        if ($filteredOUs) {
            $cmbOU.Items.AddRange($filteredOUs)
            $cmbOU.SelectedIndex = 0
        }
    }

    Update-OU
    $txtOUSearch.Add_TextChanged({ Update-OU })

    # File selection dialog
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"

    $btnOpenFile.Add_Click({
            if ($openFileDialog.ShowDialog() -eq 'OK') {
                $file = $openFileDialog.FileName
                $computers = Get-Content -Path $file
                # Validate each computer name from the file
                $invalidComputers = @()
                foreach ($computer in $computers) {
                    $computer = $computer.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($computer)) {
                        if ($computer.Length -ne 15 -or $computer -cne $computer.ToUpper()) {
                            $invalidComputers += $computer
                        }
                    }
                }
                if ($invalidComputers.Count -gt 0) {
                    [System.Windows.Forms.MessageBox]::Show("The following computer names are invalid (must be exactly 15 characters and uppercase):`n" + ($invalidComputers -join ", "), 'Error', 'OK', 'Error')
                    return
                }
                $txtComputers.Text = $computers -join ', '
                $lblFileInfo.Text = "Loaded file: $($openFileDialog.FileName) with $($computers.Count) entries."
                $txtOutput.Clear() # Clear output when loading a new file
            }
        })

    # Tooltips
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($txtComputers, "Enter computer names (15 characters, uppercase, e.g., TJDSETICIN59433) separated by commas, or load from a file")
    $toolTip.SetToolTip($btnOpenFile, "Select a text file containing a list of computer names")
    $toolTip.SetToolTip($txtOUSearch, "Type to filter Organizational Units")
    $toolTip.SetToolTip($cmbOU, "Select OU where the computers will be added")
    $toolTip.SetToolTip($txtSupportGroup, "Ingress account for granting join permissions")
    $toolTip.SetToolTip($txtDomainName, "Fully Qualified Domain Name of the domain")
    $toolTip.SetToolTip($txtDescription, "Default description for the computer objects")
    $toolTip.SetToolTip($txtOutput, "Output log of the operation")

    # Buttons
    $btnAddAndGrant = New-Object System.Windows.Forms.Button
    $btnAddAndGrant.Text = "Add and Grant"
    $btnAddAndGrant.Location = New-Object System.Drawing.Point(350, 450) # Same as previous codes
    $btnAddAndGrant.Size = New-Object System.Drawing.Size(100, 30)
    $btnAddAndGrant.BackColor = [System.Drawing.Color]::LightGreen
    $form.Controls.Add($btnAddAndGrant)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = "Clear Form"
    $btnClear.Location = New-Object System.Drawing.Point(460, 450) # Same as previous codes
    $btnClear.Size = New-Object System.Drawing.Size(100, 30)
    $btnClear.BackColor = [System.Drawing.Color]::LightYellow
    $form.Controls.Add($btnClear)

    # Event handlers
    $btnAddAndGrant.Add_Click({
            try {
                $statusLabel.Text = "Processing computers..."
                $txtOutput.Clear() # Clear previous output before starting
                if ($txtComputers.Text -eq "Enter computer names separated by commas" -or [string]::IsNullOrWhiteSpace($txtComputers.Text)) {
                    [System.Windows.Forms.MessageBox]::Show("Please enter computer names or load a file.", 'Error', 'OK', 'Error')
                    $statusLabel.Text = "Operation failed: No computer names provided"
                    return
                }
                if (-not $cmbOU.SelectedItem) {
                    [System.Windows.Forms.MessageBox]::Show("Please select an Organizational Unit.", 'Error', 'OK', 'Error')
                    $statusLabel.Text = "Operation failed: No OU selected"
                    return
                }

                $computers = $txtComputers.Text -split ','
                # Validate computer names
                $invalidComputers = @()
                $validComputers = @()
                foreach ($computer in $computers) {
                    $computer = $computer.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($computer)) {
                        if ($computer.Length -ne 15 -or $computer -cne $computer.ToUpper()) {
                            $invalidComputers += $computer
                        } else {
                            $validComputers += $computer
                        }
                    }
                }

                if ($invalidComputers.Count -gt 0) {
                    [System.Windows.Forms.MessageBox]::Show("The following computer names are invalid (must be exactly 15 characters and uppercase):`n" + ($invalidComputers -join ", "), 'Error', 'OK', 'Error')
                    $statusLabel.Text = "Operation failed: Invalid computer names"
                    return
                }

                if ($validComputers.Count -eq 0) {
                    [System.Windows.Forms.MessageBox]::Show("No valid computer names provided.", 'Error', 'OK', 'Error')
                    $statusLabel.Text = "Operation failed: No valid computer names"
                    return
                }

                $ou = $cmbOU.SelectedItem.ToString()
                $supportGroup = $txtSupportGroup.Text
                $domain = $txtDomainName.Text
                $description = $txtDescription.Text # Get the description value
                $outputPath = Join-Path ([System.Environment]::GetFolderPath('MyDocuments')) "ComputerJoinPermission_${domain}_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

                $csvData = @()
                $successCount = 0
                $failureCount = 0
                $totalCount = 0

                foreach ($computer in $validComputers) {
                    $totalCount++
                    try {
                        New-ADComputer -Name $computer -SAMAccountName $computer -Path $ou -Description $description -PasswordNotRequired $true -PassThru -Verbose
                        Grant-ComputerJoinPermission -Identity $supportGroup -Name $computer -Domain $domain
                        $successCount++
                        $csvData += [PSCustomObject]@{ComputerName = $computer; OU = $ou; Status = "Success" }
                    } catch {
                        $errorMessage = $_.Exception.Message
                        $failureCount++
                        $csvData += [PSCustomObject]@{ComputerName = $computer; OU = $ou; Status = "Failed; Error: $errorMessage" }
                    }
                }

                # Construct the detailed output message from csvData
                $outputLines = @()
                foreach ($entry in $csvData) {
                    $line = "`"$($entry.ComputerName)`",`"$($entry.OU)`",`"$($entry.Status)`""
                    $outputLines += $line
                }
                $detailedMessage = $outputLines -join "`r`n"

                # Set the detailed message to the output textbox and force UI update
                $txtOutput.Text = $detailedMessage
                $txtOutput.Refresh() # Force refresh to ensure the UI updates
                $txtOutput.Update()  # Additional UI update to ensure visibility

                # Export detailed results to CSV
                $csvData | Export-Csv -Path $outputPath -NoTypeInformation

                # Show a completion message box to the operator
                $completionMessage = "Operation completed: Processed $totalCount computer(s). $successCount succeeded, $failureCount failed.`nCheck the output for details."
                [System.Windows.Forms.MessageBox]::Show($completionMessage, 'Operation Completed', 'OK', 'Information')

                $statusLabel.Text = "Operation completed"
            } catch {
                # Catch any unexpected errors and display them
                $errorMessage = $_.Exception.Message
                [System.Windows.Forms.MessageBox]::Show("An unexpected error occurred: $errorMessage", 'Error', 'OK', 'Error')
                $statusLabel.Text = "Operation failed: $errorMessage"
            }
        })

    $btnClear.Add_Click({
            $txtComputers.Text = "Enter computer names separated by commas"
            $txtComputers.ForeColor = [System.Drawing.Color]::Gray
            $lblFileInfo.Text = "No file selected"
            $txtOUSearch.Text = "Search OU..."
            $txtOUSearch.ForeColor = [System.Drawing.Color]::Gray
            Update-OU
            $txtOutput.Clear()
            $statusLabel.Text = "Form cleared"
        })

    # Show form
    $form.ShowDialog()
}

# Execute
Show-Form
