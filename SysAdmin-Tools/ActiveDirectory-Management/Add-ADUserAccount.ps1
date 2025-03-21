<#
.SYNOPSIS
    PowerShell Script for Creating New AD User Accounts.

.DESCRIPTION
    This script facilitates the creation of new Active Directory user accounts within specified OUs. 
    It allows operators to search for and select the target domain and OU, providing an intuitive 
    interface for entering user details.

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

# Import necessary modules and assemblies
Add-Type -AssemblyName System.Windows.Forms
Import-Module ActiveDirectory

# Define log and CSV file paths
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName
$csvFilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "${scriptName}_UserCreationLog.csv"

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -ErrorAction Stop
    } catch {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "ERROR", "WARNING")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to export user creation details to CSV
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

    try {
        if (-not (Test-Path $csvFilePath)) {
            $userDetails | Export-Csv -Path $csvFilePath -NoTypeInformation -Append
        } else {
            $userDetails | Export-Csv -Path $csvFilePath -NoTypeInformation -Append -Force
        }
    } catch {
        Write-Error "Failed to export user details to CSV: $_"
    }
}

# Function to display error messages
function Show-ErrorMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Log-Message "Error: $Message" -MessageType "ERROR"
}

# Function to display information messages
function Show-InfoMessage {
    param ([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, 'Information', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Log-Message "Info: $Message" -MessageType "INFO"
}

# Function to retrieve all domains in the current forest
function Get-ForestDomains {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.Domains | ForEach-Object { $_.Name }
    } catch {
        Write-Error "Failed to retrieve forest domains: $_"
        return @()
    }
}

# Function to retrieve the UPN suffix for the forest
function Get-UPNSuffix {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.RootDomain.Name
    } catch {
        Write-Error "Failed to retrieve UPN suffix: $_"
        return ""
    }
}

# Function to retrieve all Organizational Units (OUs) containing "Users"
function Get-AllOUs {
    param ([string]$Domain)
    try {
        return Get-ADOrganizationalUnit -Server $Domain -Filter { Name -like "*Users*" } | Select-Object -ExpandProperty DistinguishedName
    } catch {
        Write-Error "Failed to retrieve Organizational Units: $_"
        return @()
    }
}

# Function to retrieve all groups starting with "G_"
function Get-AllGroups {
    param ([string]$Domain)
    try {
        return Get-ADGroup -Server $Domain -Filter { Name -like "G_*" } | Select-Object -ExpandProperty Name
    } catch {
        Write-Error "Failed to retrieve groups: $_"
        return @()
    }
}

# Function to create a new user in the specified OU
function Create-ADUser {
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
        [string]$UserGroup
    )

    try {
        $existingUser = Get-ADUser -Server $Domain -Filter { SamAccountName -eq $SamAccountName } -ErrorAction SilentlyContinue
        if ($existingUser) {
            Show-ErrorMessage "A user with the Logon Account Name '$SamAccountName' already exists."
            return $false
        }

        $expiration = if ($NoExpiration) { $null } else { $AccountExpirationDate }
        $upnSuffix = Get-UPNSuffix

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
                   -ChangePasswordAtLogon $true `
                   -Enabled $true `
                   -AccountExpirationDate $expiration

        Add-ADGroupMember -Server $Domain -Identity $UserGroup -Members $SamAccountName

        Log-Message "User: $SamAccountName - $DisplayName, created successfully in OU: $OU on domain $Domain and added to group: $UserGroup at Forest: $upnSuffix"
        Export-ToCSV -Domain $Domain `
                     -OU $OU `
                     -GivenName $GivenName `
                     -Surname $Surname `
                     -DisplayName $DisplayName `
                     -EmailAddress $EmailAddress `
                     -SamAccountName $SamAccountName `
                     -UserGroup $UserGroup `
                     -Timestamp (Get-Date)

        Show-InfoMessage "User: $SamAccountName - $DisplayName, created successfully in OU: $OU on domain $Domain and added to group: $UserGroup at Forest: $upnSuffix"
        return $true
    } catch {
        Log-Message "Failed to create user ${GivenName} ${Surname}: $_" -MessageType "ERROR"
        Show-ErrorMessage "Failed to create user ${GivenName} ${Surname}: $_"
        return $false
    }
}

# Function to create and show the form
function Show-Form {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Create New AD User"
    $form.Width = 500
    $form.Height = 680
    $form.StartPosition = "CenterScreen"

    $labelsText = @("Domain:", "OU Search:", "OU:", "Given Names:", "Surnames:", "Display Name:", "Description:", "Phone Number:", "Email Address:", "Temporary Password:", "Logon Name/ Code:", "Account Expiration Date:", "User Group Search:", "User Group:")
    $positions = @(10, 50, 90, 130, 170, 210, 250, 290, 330, 370, 410, 450, 490, 530)
    $textBoxes = @()

    # Domain ComboBox
    $lblDomain = New-Object System.Windows.Forms.Label
    $lblDomain.Text = "Domain:"
    $lblDomain.Location = New-Object System.Drawing.Point(10, $positions[0])
    $lblDomain.AutoSize = $true
    $form.Controls.Add($lblDomain)

    $cmbDomain = New-Object System.Windows.Forms.ComboBox
    $cmbDomain.Location = New-Object System.Drawing.Point(160, $positions[0])
    $cmbDomain.Size = New-Object System.Drawing.Size(260, 20)
    $cmbDomain.DropDownStyle = 'DropDownList'
    $form.Controls.Add($cmbDomain)

    # Populate Domain ComboBox with forest domains
    $forestDomains = Get-ForestDomains
    foreach ($domain in $forestDomains) {
        $cmbDomain.Items.Add($domain)
    }
    if ($cmbDomain.Items.Count -gt 0) {
        $cmbDomain.SelectedIndex = 0
    }

    # OU Search field
    $lblOUSearch = New-Object System.Windows.Forms.Label
    $lblOUSearch.Text = "OU Search:"
    $lblOUSearch.Location = New-Object System.Drawing.Point(10, $positions[1])
    $lblOUSearch.AutoSize = $true
    $form.Controls.Add($lblOUSearch)

    $txtOUSearch = New-Object System.Windows.Forms.TextBox
    $txtOUSearch.Location = New-Object System.Drawing.Point(160, $positions[1])
    $txtOUSearch.Size = New-Object System.Drawing.Size(260, 20)
    $form.Controls.Add($txtOUSearch)

    # OU ComboBox
    $lblOU = New-Object System.Windows.Forms.Label
    $lblOU.Text = "OU:"
    $lblOU.Location = New-Object System.Drawing.Point(10, $positions[2])
    $lblOU.AutoSize = $true
    $form.Controls.Add($lblOU)

    $cmbOU = New-Object System.Windows.Forms.ComboBox
    $cmbOU.Location = New-Object System.Drawing.Point(160, $positions[2])
    $cmbOU.Size = New-Object System.Drawing.Size(260, 20)
    $cmbOU.DropDownStyle = 'DropDownList'
    $form.Controls.Add($cmbOU)

    # Populate OU ComboBox with OUs containing "Users"
    function UpdateOUComboBox {
        $cmbOU.Items.Clear()
        $searchText = $txtOUSearch.Text
        $selectedDomain = $cmbDomain.SelectedItem
        $filteredOUs = Get-AllOUs -Domain $selectedDomain | Where-Object { $_ -like "*$searchText*" }
        foreach ($ou in $filteredOUs) {
            $cmbOU.Items.Add($ou)
        }
        if ($cmbOU.Items.Count -gt 0) {
            $cmbOU.SelectedIndex = 0
        }
    }
    UpdateOUComboBox

    # Search TextBox change event for OU filtering
    $txtOUSearch.Add_TextChanged({
        UpdateOUComboBox
    })

    # Domain ComboBox change event to refresh OUs and Groups
    $cmbDomain.Add_SelectedIndexChanged({
        UpdateOUComboBox
        UpdateGroupComboBox
    })

    # TextBoxes for user details
    for ($i = 3; $i -lt 11; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labelsText[$i]
        $label.Location = New-Object System.Drawing.Point(10, $positions[$i])
        $label.AutoSize = $true
        $form.Controls.Add($label)

        if ($i -eq 6) {
            # Description ComboBox with predefined values
            $cmbDescription = New-Object System.Windows.Forms.ComboBox
            $cmbDescription.Location = New-Object System.Drawing.Point(160, $positions[$i])
            $cmbDescription.Size = New-Object System.Drawing.Size(260, 20)
            $cmbDescription.DropDownStyle = 'DropDownList'
            $form.Controls.Add($cmbDescription)

           # Predefined descriptions
           $descriptions = @(
               "Legal Analyst",
               "Mayor's Office Advisor",
               "Chief of Mayor's Office",
               "Secretary Chief",
               "Temporary Staff",
               "Contracted Staff",
               "Division or Unit Coordinator",
               "Director of Division or Unit",
               "Graduate Fellow",
               "Municipal Judge",
               "Legal Associate",
               "Assigned Employee",
               "Municipal Technician"
           )

            $descriptions | Sort-Object | ForEach-Object { $cmbDescription.Items.Add($_) }
            if ($cmbDescription.Items.Count -gt 0) {
                $cmbDescription.SelectedIndex = 0
            }
        } else {
            $textBox = New-Object System.Windows.Forms.TextBox
            $textBox.Location = New-Object System.Drawing.Point(160, $positions[$i])
            $textBox.Size = New-Object System.Drawing.Size(260, 20)
            $textBoxes += $textBox
            $form.Controls.Add($textBox)
        }
    }

    # DateTimePicker for account expiration date
    $lblExpiration = New-Object System.Windows.Forms.Label
    $lblExpiration.Text = "Account Expiration Date:"
    $lblExpiration.Location = New-Object System.Drawing.Point(10, $positions[11])
    $lblExpiration.AutoSize = $true
    $form.Controls.Add($lblExpiration)

    $dateTimePicker = New-Object System.Windows.Forms.DateTimePicker
    $dateTimePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $dateTimePicker.Location = New-Object System.Drawing.Point(160, $positions[11])
    $dateTimePicker.Size = New-Object System.Drawing.Size(160, 20)
    $dateTimePicker.Value = (Get-Date).AddYears(1)
    $form.Controls.Add($dateTimePicker)

    # CheckBox for no expiration date
    $chkNoExpiration = New-Object System.Windows.Forms.CheckBox
    $chkNoExpiration.Text = "No Expiration"
    $chkNoExpiration.Location = New-Object System.Drawing.Point(330, $positions[11])
    $chkNoExpiration.AutoSize = $true
    $form.Controls.Add($chkNoExpiration)

    # Group Search field
    $lblGroupSearch = New-Object System.Windows.Forms.Label
    $lblGroupSearch.Text = "User Group Search:"
    $lblGroupSearch.Location = New-Object System.Drawing.Point(10, $positions[12])
    $lblGroupSearch.AutoSize = $true
    $form.Controls.Add($lblGroupSearch)

    $txtGroupSearch = New-Object System.Windows.Forms.TextBox
    $txtGroupSearch.Location = New-Object System.Drawing.Point(160, $positions[12])
    $txtGroupSearch.Size = New-Object System.Drawing.Size(260, 20)
    $form.Controls.Add($txtGroupSearch)

    # Group ComboBox
    $lblGroup = New-Object System.Windows.Forms.Label
    $lblGroup.Text = "User Group:"
    $lblGroup.Location = New-Object System.Drawing.Point(10, $positions[13])
    $lblGroup.AutoSize = $true
    $form.Controls.Add($lblGroup)

    $cmbGroup = New-Object System.Windows.Forms.ComboBox
    $cmbGroup.Location = New-Object System.Drawing.Point(160, $positions[13])
    $cmbGroup.Size = New-Object System.Drawing.Size(260, 20)
    $cmbGroup.DropDownStyle = 'DropDownList'
    $form.Controls.Add($cmbGroup)

    # Populate Group ComboBox with groups starting with "G_"
    function UpdateGroupComboBox {
        $cmbGroup.Items.Clear()
        $searchText = $txtGroupSearch.Text
        $selectedDomain = $cmbDomain.SelectedItem
        $filteredGroups = Get-AllGroups -Domain $selectedDomain | Where-Object { $_ -like "*$searchText*" }
        foreach ($group in $filteredGroups) {
            $cmbGroup.Items.Add($group)
        }
        if ($cmbGroup.Items.Count -gt 0) {
            $cmbGroup.SelectedIndex = 0
        }
    }
    UpdateGroupComboBox

    # Search TextBox change event for Group filtering
    $txtGroupSearch.Add_TextChanged({
        UpdateGroupComboBox
    })

    # Function to update Display Name
    function UpdateDisplayName {
        $firstName = $textBoxes[0].Text -split ' ' | Select-Object -First 1
        $lastName = $textBoxes[1].Text -split ' ' | Select-Object -Last 1
        $textBoxes[2].Text = "$firstName $lastName"
    }

    # Text change events to update Display Name
    $textBoxes[0].Add_TextChanged({ UpdateDisplayName })
    $textBoxes[1].Add_TextChanged({ UpdateDisplayName })

    # Create a button for user creation
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Create User"
    $button.Location = New-Object System.Drawing.Point(160, 580)
    $button.Size = New-Object System.Drawing.Size(200, 30)
    $form.Controls.Add($button)

    # Function to clear the form fields
    function Clear-Form {
        $txtOUSearch.Clear()
        UpdateOUComboBox
        $textBoxes | ForEach-Object { $_.Clear() }
        $cmbDescription.SelectedIndex = 0
        $dateTimePicker.Value = (Get-Date).AddYears(1)
        $chkNoExpiration.Checked = $false
        $txtGroupSearch.Clear()
        UpdateGroupComboBox
    }

    # Button click event with validation
    $button.Add_Click({
        $isValidInput = $true
        foreach ($textBox in $textBoxes) {
            if ([string]::IsNullOrWhiteSpace($textBox.Text)) {
                Show-ErrorMessage "Please fill in all fields."
                $isValidInput = $false
                break
            }
        }

        if ($isValidInput) {
            $success = Create-ADUser -Domain $cmbDomain.SelectedItem `
                                     -OU $cmbOU.SelectedItem `
                                     -GivenName $textBoxes[0].Text `
                                     -Surname $textBoxes[1].Text `
                                     -DisplayName $textBoxes[2].Text `
                                     -Description $cmbDescription.SelectedItem `
                                     -PhoneNumber $textBoxes[3].Text `
                                     -EmailAddress $textBoxes[4].Text `
                                     -Password $textBoxes[5].Text `
                                     -SamAccountName $textBoxes[6].Text `
                                     -AccountExpirationDate $dateTimePicker.Value `
                                     -NoExpiration $chkNoExpiration.Checked `
                                     -UserGroup $cmbGroup.SelectedItem
            if ($success) {
                Clear-Form
            }
        } else {
            Log-Message "Input validation failed: One or more fields were empty." -MessageType "ERROR"
        }
    })

    # Show the form
    $form.ShowDialog()
}

# Call the function to show the form
Show-Form

# End of script
