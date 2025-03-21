<#
.SYNOPSIS
    PowerShell Script for Creating InetOrgPerson Entries in Active Directory.

.DESCRIPTION
    This script simplifies the creation of new InetOrgPerson entries in Active Directory, 
    allowing operators to input detailed account information, including organizational attributes.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: March 21, 2025
#>

# Hide PowerShell console window
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

# Import necessary assemblies
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
Import-Module ActiveDirectory

# Define log and CSV file paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logPath = Join-Path $logDir "${scriptName}.log"
$csvFilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}_InetOrgPersonCreationLog.csv"

# Ensure log directory exists
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force }

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "ERROR", "WARNING")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] [$MessageType] $Message" | Out-File -FilePath $logPath -Append
}

# CSV export function
function Export-ToCSV {
    param (
        [string]$Domain,
        [string]$OU,
        [string]$GivenName,
        [string]$Surname,
        [string]$DisplayName,
        [string]$EmailAddress,
        [string]$SamAccountName,
        [string]$UserGroup,
        [datetime]$Timestamp
    )
    $userDetails = [PSCustomObject]@{
        Timestamp      = $Timestamp
        Domain         = $Domain
        OU             = $OU
        GivenName      = $GivenName
        Surname        = $Surname
        DisplayName    = $DisplayName
        EmailAddress   = $EmailAddress
        SamAccountName = $SamAccountName
        UserGroup      = $UserGroup
    }
    $userDetails | Export-Csv -Path $csvFilePath -NoTypeInformation -Append -Force
}

# Message display functions
function Show-ErrorMessage { 
    param ([string]$Message) 
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', 'OK', 'Error')
    Log-Message $Message "ERROR"
}

function Show-InfoMessage { 
    param ([string]$Message) 
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', 'OK', 'Information')
    Log-Message $Message "INFO"
}

# AD functions
function Get-ForestDomains { 
    try { 
        [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Domains | ForEach-Object { $_.Name } 
    } catch { 
        Show-ErrorMessage "Failed to retrieve forest domains: $_"
        return @()
    } 
}

function Get-UPNSuffix { 
    try { 
        [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().RootDomain.Name 
    } catch { 
        Show-ErrorMessage "Failed to retrieve UPN suffix: $_"
        return ""
    } 
}

function Get-AllOUs { 
    param ($Domain) 
    try { 
        Get-ADOrganizationalUnit -Server $Domain -Filter { Name -like "*servic*" } | Select-Object -ExpandProperty DistinguishedName 
    } catch { 
        Show-ErrorMessage "Failed to retrieve OUs: $_"
        return @()
    } 
}

function Get-AllGroups { 
    param ($Domain) 
    try { 
        Get-ADGroup -Server $Domain -Filter { Name -like "G_*" } | Select-Object -ExpandProperty Name 
    } catch { 
        Show-ErrorMessage "Failed to retrieve groups: $_"
        return @()
    } 
}

function Create-InetOrgPerson {
    param (
        [string]$Domain,
        [string]$OU,
        [string]$GivenName,
        [string]$Surname,
        [string]$DisplayName,
        [string]$Description,
        [string]$PhoneNumber,
        [string]$EmailAddress,
        [string]$Password,
        [string]$SamAccountName,
        [datetime]$AccountExpirationDate,
        [bool]$NoExpiration,
        [string]$UserGroup,
        [bool]$NoGroupMembership
    )
    try {
        if (Get-ADUser -Server $Domain -Filter { SamAccountName -eq $SamAccountName } -ErrorAction SilentlyContinue) {
            Show-ErrorMessage "An InetOrgPerson with the Logon Account Name '$SamAccountName' already exists."
            return $false
        }

        $expiration = if ($NoExpiration) { $null } else { $AccountExpirationDate }
        $upnSuffix = Get-UPNSuffix
        $changePasswordAtLogon = -not $NoExpiration

        New-ADUser -Server $Domain `
                   -Name "$GivenName $Surname" `
                   -GivenName $GivenName `
                   -Surname $Surname `
                   -DisplayName $DisplayName `
                   -Description $Description `
                   -OfficePhone $PhoneNumber `
                   -EmailAddress $EmailAddress `
                   -SamAccountName $SamAccountName `
                   -UserPrincipalName "$SamAccountName@$upnSuffix" `
                   -Path $OU `
                   -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
                   -ChangePasswordAtLogon $changePasswordAtLogon `
                   -Enabled $true `
                   -PasswordNeverExpires $NoExpiration `
                   -OtherAttributes @{objectClass = 'inetOrgPerson'}

        if ($expiration) {
            Set-ADUser -Identity $SamAccountName -AccountExpirationDate $expiration -Server $Domain
        }

        if (-not $NoGroupMembership -and $UserGroup) {
            Add-ADGroupMember -Server $Domain -Identity $UserGroup -Members $SamAccountName
            Log-Message "Created InetOrgPerson: $SamAccountName - $DisplayName, OU: $OU, Domain: $Domain, Group: $UserGroup"
            Show-InfoMessage "Created InetOrgPerson: $SamAccountName - $DisplayName, OU: $OU, Domain: $Domain, Group: $UserGroup"
        } else {
            Log-Message "Created InetOrgPerson: $SamAccountName - $DisplayName, OU: $OU, Domain: $Domain without group membership."
            Show-InfoMessage "Created InetOrgPerson: $SamAccountName - $DisplayName, OU: $OU, Domain: $Domain without group membership."
        }

        Export-ToCSV -Domain $Domain `
                     -OU $OU `
                     -GivenName $GivenName `
                     -Surname $Surname `
                     -DisplayName $DisplayName `
                     -EmailAddress $EmailAddress `
                     -SamAccountName $SamAccountName `
                     -UserGroup $UserGroup `
                     -Timestamp (Get-Date)
        return $true
    } catch {
        Show-ErrorMessage "Failed to create InetOrgPerson ${GivenName} ${Surname}: $_"
        Log-Message "Failed to create InetOrgPerson ${GivenName} ${Surname}: $_" "ERROR"
        return $false
    }
}

# Form creation
function Show-Form {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Create New AD InetOrgPerson"
    $form.Size = New-Object System.Drawing.Size(600, 550) # Compact form size as in the last code
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
    $tabControl.Size = New-Object System.Drawing.Size(570, 430) # Same as the last code
    $form.Controls.Add($tabControl)

    # Tab pages
    $tabBasic = New-Object System.Windows.Forms.TabPage; $tabBasic.Text = "Basic Info"
    $tabDetails = New-Object System.Windows.Forms.TabPage; $tabDetails.Text = "Details"
    $tabSettings = New-Object System.Windows.Forms.TabPage; $tabSettings.Text = "Settings"
    $tabControl.TabPages.AddRange(@($tabBasic, $tabDetails, $tabSettings))

    # Basic Info Tab
    $groupBasic = New-Object System.Windows.Forms.GroupBox
    $groupBasic.Text = "User Information"
    $groupBasic.Location = New-Object System.Drawing.Point(10, 10)
    $groupBasic.Size = New-Object System.Drawing.Size(540, 160)
    $tabBasic.Controls.Add($groupBasic)

    $lblGivenName = New-Object System.Windows.Forms.Label; $lblGivenName.Text = "Given Names:"; $lblGivenName.Location = New-Object System.Drawing.Point(10, 20); $lblGivenName.AutoSize = $true
    $txtGivenName = New-Object System.Windows.Forms.TextBox; $txtGivenName.Location = New-Object System.Drawing.Point(140, 20); $txtGivenName.Size = New-Object System.Drawing.Size(380, 20)
    $lblSurname = New-Object System.Windows.Forms.Label; $lblSurname.Text = "Surnames:"; $lblSurname.Location = New-Object System.Drawing.Point(10, 50); $lblSurname.AutoSize = $true
    $txtSurname = New-Object System.Windows.Forms.TextBox; $txtSurname.Location = New-Object System.Drawing.Point(140, 50); $txtSurname.Size = New-Object System.Drawing.Size(380, 20)
    $lblDisplayName = New-Object System.Windows.Forms.Label; $lblDisplayName.Text = "Display Name:"; $lblDisplayName.Location = New-Object System.Drawing.Point(10, 80); $lblDisplayName.AutoSize = $true
    $txtDisplayName = New-Object System.Windows.Forms.TextBox; $txtDisplayName.Location = New-Object System.Drawing.Point(140, 80); $txtDisplayName.Size = New-Object System.Drawing.Size(380, 20)
    $lblLoginID = New-Object System.Windows.Forms.Label; $lblLoginID.Text = "Logon Name/Code:"; $lblLoginID.Location = New-Object System.Drawing.Point(10, 110); $lblLoginID.AutoSize = $true
    $txtLoginID = New-Object System.Windows.Forms.TextBox; $txtLoginID.Location = New-Object System.Drawing.Point(140, 110); $txtLoginID.Size = New-Object System.Drawing.Size(380, 20)

    $groupBasic.Controls.AddRange(@($lblGivenName, $txtGivenName, $lblSurname, $txtSurname, $lblDisplayName, $txtDisplayName, $lblLoginID, $txtLoginID))

    # Details Tab
    $groupDetails = New-Object System.Windows.Forms.GroupBox
    $groupDetails.Text = "User Details"
    $groupDetails.Location = New-Object System.Drawing.Point(10, 10)
    $groupDetails.Size = New-Object System.Drawing.Size(540, 130)
    $tabDetails.Controls.Add($groupDetails)

    $lblDescription = New-Object System.Windows.Forms.Label; $lblDescription.Text = "Description:"; $lblDescription.Location = New-Object System.Drawing.Point(10, 20); $lblDescription.AutoSize = $true
    $cmbDescription = New-Object System.Windows.Forms.ComboBox; $cmbDescription.Location = New-Object System.Drawing.Point(140, 20); $cmbDescription.Size = New-Object System.Drawing.Size(380, 20); $cmbDescription.DropDownStyle = 'DropDownList'
    $lblPhone = New-Object System.Windows.Forms.Label; $lblPhone.Text = "Phone Number:"; $lblPhone.Location = New-Object System.Drawing.Point(10, 50); $lblPhone.AutoSize = $true
    $txtPhone = New-Object System.Windows.Forms.TextBox; $txtPhone.Location = New-Object System.Drawing.Point(140, 50); $txtPhone.Size = New-Object System.Drawing.Size(380, 20); $txtPhone.Text = "(96) 9xxxx-xxxx"
    $lblEmail = New-Object System.Windows.Forms.Label; $lblEmail.Text = "Email Address:"; $lblEmail.Location = New-Object System.Drawing.Point(10, 80); $lblEmail.AutoSize = $true
    $txtEmail = New-Object System.Windows.Forms.TextBox; $txtEmail.Location = New-Object System.Drawing.Point(140, 80); $txtEmail.Size = New-Object System.Drawing.Size(380, 20); $txtEmail.Text = "@tjap.jus.br"

    $groupDetails.Controls.AddRange(@($lblDescription, $cmbDescription, $lblPhone, $txtPhone, $lblEmail, $txtEmail))

    # Populate Description ComboBox
    $descriptions = @(
        "Definitive Service Account",
        "PoC Service Account",
        "Google Workspace Unit Account"
    ) | Sort-Object
    $cmbDescription.Items.AddRange($descriptions)
    $cmbDescription.SelectedIndex = 0

    # Settings Tab
    $groupSettings = New-Object System.Windows.Forms.GroupBox
    $groupSettings.Text = "Account Settings"
    $groupSettings.Location = New-Object System.Drawing.Point(10, 10)
    $groupSettings.Size = New-Object System.Drawing.Size(540, 280) # Same as the last code
    $tabSettings.Controls.Add($groupSettings)

    # 25px vertical spacing between fields
    $lblDomain = New-Object System.Windows.Forms.Label; $lblDomain.Text = "Domain:"; $lblDomain.Location = New-Object System.Drawing.Point(10, 20); $lblDomain.AutoSize = $true
    $cmbDomain = New-Object System.Windows.Forms.ComboBox; $cmbDomain.Location = New-Object System.Drawing.Point(140, 20); $cmbDomain.Size = New-Object System.Drawing.Size(380, 20); $cmbDomain.DropDownStyle = 'DropDownList'
    $lblOUSearch = New-Object System.Windows.Forms.Label; $lblOUSearch.Text = "OU Search:"; $lblOUSearch.Location = New-Object System.Drawing.Point(10, 45); $lblOUSearch.AutoSize = $true
    $txtOUSearch = New-Object System.Windows.Forms.TextBox; $txtOUSearch.Location = New-Object System.Drawing.Point(140, 45); $txtOUSearch.Size = New-Object System.Drawing.Size(380, 20)
    $lblOU = New-Object System.Windows.Forms.Label; $lblOU.Text = "OU:"; $lblOU.Location = New-Object System.Drawing.Point(10, 70); $lblOU.AutoSize = $true
    $cmbOU = New-Object System.Windows.Forms.ComboBox; $cmbOU.Location = New-Object System.Drawing.Point(140, 70); $cmbOU.Size = New-Object System.Drawing.Size(380, 20); $cmbOU.DropDownStyle = 'DropDownList'
    $lblGroupSearch = New-Object System.Windows.Forms.Label; $lblGroupSearch.Text = "User Group Search:"; $lblGroupSearch.Location = New-Object System.Drawing.Point(10, 95); $lblGroupSearch.AutoSize = $true
    $txtGroupSearch = New-Object System.Windows.Forms.TextBox; $txtGroupSearch.Location = New-Object System.Drawing.Point(140, 95); $txtGroupSearch.Size = New-Object System.Drawing.Size(380, 20)
    $lblGroup = New-Object System.Windows.Forms.Label; $lblGroup.Text = "User Group:"; $lblGroup.Location = New-Object System.Drawing.Point(10, 120); $lblGroup.AutoSize = $true
    $cmbGroup = New-Object System.Windows.Forms.ComboBox; $cmbGroup.Location = New-Object System.Drawing.Point(140, 120); $cmbGroup.Size = New-Object System.Drawing.Size(380, 20); $cmbGroup.DropDownStyle = 'DropDownList'
    $chkNoGroupMembership = New-Object System.Windows.Forms.CheckBox; $chkNoGroupMembership.Text = "No Group Membership"; $chkNoGroupMembership.Location = New-Object System.Drawing.Point(10, 145); $chkNoGroupMembership.AutoSize = $true
    $lblPassword = New-Object System.Windows.Forms.Label; $lblPassword.Text = "Password (complex):"; $lblPassword.Location = New-Object System.Drawing.Point(10, 170); $lblPassword.AutoSize = $true
    $txtPassword = New-Object System.Windows.Forms.TextBox; $txtPassword.Location = New-Object System.Drawing.Point(140, 170); $txtPassword.Size = New-Object System.Drawing.Size(380, 30); $txtPassword.Text = "#Temporaria@2025"
    $lblExpiration = New-Object System.Windows.Forms.Label; $lblExpiration.Text = "Expiration Date:"; $lblExpiration.Location = New-Object System.Drawing.Point(10, 205); $lblExpiration.AutoSize = $true
    $dateTimePicker = New-Object System.Windows.Forms.DateTimePicker; $dateTimePicker.Location = New-Object System.Drawing.Point(140, 205); $dateTimePicker.Size = New-Object System.Drawing.Size(250, 35); $dateTimePicker.Value = (Get-Date).AddYears(1)
    $chkNoExpiration = New-Object System.Windows.Forms.CheckBox; $chkNoExpiration.Text = "No Expiration"; $chkNoExpiration.Location = New-Object System.Drawing.Point(400, 205); $chkNoExpiration.AutoSize = $true

    $groupSettings.Controls.AddRange(@($lblDomain, $cmbDomain, $lblOUSearch, $txtOUSearch, $lblOU, $cmbOU, $lblGroupSearch, $txtGroupSearch, $lblGroup, $cmbGroup, $chkNoGroupMembership, $lblPassword, $txtPassword, $lblExpiration, $dateTimePicker, $chkNoExpiration))

    # Populate ComboBoxes and Search Functionality
    $cmbDomain.Items.AddRange((Get-ForestDomains))
    if ($cmbDomain.Items.Count -gt 0) { $cmbDomain.SelectedIndex = 0 }

    function Update-OU {
        $cmbOU.Items.Clear()
        $searchText = $txtOUSearch.Text
        $selectedDomain = $cmbDomain.SelectedItem
        $filteredOUs = Get-AllOUs $selectedDomain | Where-Object { $_ -like "*$searchText*" }
        if ($filteredOUs) {
            $cmbOU.Items.AddRange($filteredOUs)
            $cmbOU.SelectedIndex = 0
        }
    }

    function Update-Group {
        $cmbGroup.Items.Clear()
        $searchText = $txtGroupSearch.Text
        $selectedDomain = $cmbDomain.SelectedItem
        $filteredGroups = Get-AllGroups $selectedDomain | Where-Object { $_ -like "*$searchText*" }
        if ($filteredGroups) {
            $cmbGroup.Items.AddRange($filteredGroups)
            $cmbGroup.SelectedIndex = 0
        }
    }

    Update-OU
    Update-Group

    $txtOUSearch.Add_TextChanged({ Update-OU })
    $txtGroupSearch.Add_TextChanged({ Update-Group })
    $cmbDomain.Add_SelectedIndexChanged({ $txtOUSearch.Text = ""; $txtGroupSearch.Text = ""; Update-OU; Update-Group })

    # Tooltips
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($txtLoginID, "Unique identifier for user login (Logon Name/Code)")
    $toolTip.SetToolTip($txtEmail, "User's email address (e.g., username@tjap.jus.br)")
    $toolTip.SetToolTip($txtPassword, "Temporary Password - user must change at first logon")
    $toolTip.SetToolTip($txtPhone, "Contact number in format (96) 9xxxx-xxxx")
    $toolTip.SetToolTip($cmbDomain, "Select the Active Directory domain")
    $toolTip.SetToolTip($txtOUSearch, "Type to filter Organizational Units")
    $toolTip.SetToolTip($cmbOU, "Select OU where the user will be created")
    $toolTip.SetToolTip($txtGroupSearch, "Type to filter User Groups (starting with G_)")
    $toolTip.SetToolTip($cmbGroup, "Select group for user membership")

    # Buttons
    $btnCreate = New-Object System.Windows.Forms.Button
    $btnCreate.Text = "Create User"
    $btnCreate.Location = New-Object System.Drawing.Point(350, 450) # Same as the last code
    $btnCreate.Size = New-Object System.Drawing.Size(100, 30)
    $btnCreate.BackColor = [System.Drawing.Color]::LightGreen
    $form.Controls.Add($btnCreate)

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Text = "Clear Form"
    $btnClear.Location = New-Object System.Drawing.Point(460, 450) # Same as the last code
    $btnClear.Size = New-Object System.Drawing.Size(100, 30)
    $btnClear.BackColor = [System.Drawing.Color]::LightYellow
    $form.Controls.Add($btnClear)

    # Event handlers
    $txtGivenName.Add_TextChanged({ 
        $firstName = if ($txtGivenName.Text) { $txtGivenName.Text.Split()[0] } else { "" }
        $lastName = if ($txtSurname.Text) { $txtSurname.Text.Split()[-1] } else { "" }
        $txtDisplayName.Text = "$firstName $lastName".Trim()
    })
    $txtSurname.Add_TextChanged({ 
        $firstName = if ($txtGivenName.Text) { $txtGivenName.Text.Split()[0] } else { "" }
        $lastName = if ($txtSurname.Text) { $txtSurname.Text.Split()[-1] } else { "" }
        $txtDisplayName.Text = "$firstName $lastName".Trim()
    })

    $btnCreate.Add_Click({
        $statusLabel.Text = "Creating user..."
        $requiredFields = @($txtGivenName, $txtSurname, $txtLoginID, $txtEmail, $txtPassword)
        if ($requiredFields | Where-Object { [string]::IsNullOrWhiteSpace($_.Text) }) {
            Show-ErrorMessage "Please fill in all required fields."
            $statusLabel.Text = "Creation failed: Missing required fields"
            return
        }
        if (-not $cmbOU.SelectedItem) {
            Show-ErrorMessage "Please select an Organizational Unit."
            $statusLabel.Text = "Creation failed: No OU selected"
            return
        }
        if (-not $chkNoGroupMembership.Checked -and -not $cmbGroup.SelectedItem) {
            Show-ErrorMessage "Please select a User Group or check 'No Group Membership'."
            $statusLabel.Text = "Creation failed: No User Group selected"
            return
        }

        $success = Create-InetOrgPerson -Domain $cmbDomain.SelectedItem `
                                       -OU $cmbOU.SelectedItem `
                                       -GivenName $txtGivenName.Text `
                                       -Surname $txtSurname.Text `
                                       -DisplayName $txtDisplayName.Text `
                                       -Description $cmbDescription.SelectedItem `
                                       -PhoneNumber $txtPhone.Text `
                                       -EmailAddress $txtEmail.Text `
                                       -Password $txtPassword.Text `
                                       -SamAccountName $txtLoginID.Text `
                                       -AccountExpirationDate $dateTimePicker.Value `
                                       -NoExpiration $chkNoExpiration.Checked `
                                       -UserGroup $cmbGroup.SelectedItem `
                                       -NoGroupMembership $chkNoGroupMembership.Checked
        
        $statusLabel.Text = if ($success) { "User created successfully" } else { "User creation failed" }
        if ($success) {
            $txtGivenName.Clear(); $txtSurname.Clear(); $txtDisplayName.Clear(); $txtLoginID.Clear()
            $cmbDescription.SelectedIndex = 0; $txtPhone.Text = "+55(96)98115-5265"
            $txtEmail.Text = "@scriptguy.com"; $txtPassword.Text = "#TempPass@2025"
            $dateTimePicker.Value = (Get-Date).AddYears(1); $chkNoExpiration.Checked = $false
            $txtOUSearch.Text = ""; $txtGroupSearch.Text = ""; Update-OU; Update-Group
            $chkNoGroupMembership.Checked = $false
        }
    })

    $btnClear.Add_Click({
        $txtGivenName.Clear(); $txtSurname.Clear(); $txtDisplayName.Clear(); $txtLoginID.Clear()
        $cmbDescription.SelectedIndex = 0; $txtPhone.Text = "+55(96)98115-5265"
        $txtEmail.Text = "@scriptguy.com"; $txtPassword.Text = "#TempPass@2025"
        $dateTimePicker.Value = (Get-Date).AddYears(1); $chkNoExpiration.Checked = $false
        $txtOUSearch.Text = ""; $txtGroupSearch.Text = ""; Update-OU; Update-Group
        $chkNoGroupMembership.Checked = $false
        $statusLabel.Text = "Form cleared"
    })

    # Show form
    $form.ShowDialog()
}

# Execute
Show-Form
