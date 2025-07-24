<#
.SYNOPSIS
    PowerShell Script for Managing and Transferring FSMO Roles.

.DESCRIPTION
    This script facilitates the management and transfer of Flexible Single Master Operation (FSMO) 
    roles within an Active Directory forest, ensuring proper domain functionality and stability.

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

# Import necessary modules
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module ActiveDirectory

# Determine the script name and set up the logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
        $global:logBox.Items.Add($logEntry)
        $global:logBox.TopIndex = $global:logBox.Items.Count - 1
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Counter to track retrievals
$global:retrieveCounter = 0

# Function to retrieve current FSMO roles
function Get-FSMORoles {
    try {
        $forest = Get-ADForest
        $domain = Get-ADDomain

        $roles = @{
            "Schema Master" = $forest.SchemaMaster
            "Domain Naming Master" = $forest.DomainNamingMaster
            "PDC Emulator" = $domain.PDCEmulator
            "RID Master" = $domain.RIDMaster
            "Infrastructure Master" = $domain.InfrastructureMaster
        }

        return $roles
    } catch {
        Log-Message "Error retrieving FSMO roles: $_" -MessageType "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error retrieving FSMO roles. See log for details.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $null
    }
}

# Function to transfer FSMO roles
function Transfer-FSMORoles {
    param (
        [string]$schemaMasterTarget,
        [string]$domainNamingMasterTarget,
        [string]$pdcEmulatorTarget,
        [string]$ridMasterTarget,
        [string]$infrastructureMasterTarget
    )

    try {
        Move-ADDirectoryServerOperationMasterRole -Identity $schemaMasterTarget -OperationMasterRole SchemaMaster -ErrorAction Stop
        Log-Message "Transferred Schema Master to $schemaMasterTarget"

        Move-ADDirectoryServerOperationMasterRole -Identity $domainNamingMasterTarget -OperationMasterRole DomainNamingMaster -ErrorAction Stop
        Log-Message "Transferred Domain Naming Master to $domainNamingMasterTarget"

        Move-ADDirectoryServerOperationMasterRole -Identity $pdcEmulatorTarget -OperationMasterRole PDCEmulator -ErrorAction Stop
        Log-Message "Transferred PDC Emulator to $pdcEmulatorTarget"

        Move-ADDirectoryServerOperationMasterRole -Identity $ridMasterTarget -OperationMasterRole RIDMaster -ErrorAction Stop
        Log-Message "Transferred RID Master to $ridMasterTarget"

        Move-ADDirectoryServerOperationMasterRole -Identity $infrastructureMasterTarget -OperationMasterRole InfrastructureMaster -ErrorAction Stop
        Log-Message "Transferred Infrastructure Master to $infrastructureMasterTarget"

        Log-Message "FSMO Role Transfer Completed"
        [System.Windows.Forms.MessageBox]::Show("FSMO Role Transfer Completed.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Log-Message "Failed to transfer FSMO role: $_" -MessageType "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Failed to transfer FSMO role. See log for details.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Function to display the log file
function Show-Log {
    notepad $logPath
}

# Retrieve list of all domain controllers
$allDCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName

# Initialize the form and controls
$form = New-Object System.Windows.Forms.Form
$form.Text = "FSMO Role Management Tool"
$form.Size = New-Object System.Drawing.Size(600, 560)  # Adjusted size for better presentation
$form.StartPosition = "CenterScreen"

# Create a ListBox to display log messages
$global:logBox = New-Object System.Windows.Forms.ListBox
$global:logBox.Location = New-Object System.Drawing.Point(10, 10)
$global:logBox.Size = New-Object System.Drawing.Size(560, 300)  # Adjusted size to fit form
$form.Controls.Add($global:logBox)

# Add input fields for target servers as ComboBoxes
$schemaMasterLabel = New-Object System.Windows.Forms.Label
$schemaMasterLabel.Location = New-Object System.Drawing.Point(10, 320)
$schemaMasterLabel.Size = New-Object System.Drawing.Size(200, 20)
$schemaMasterLabel.Text = "Schema Master Target:"
$form.Controls.Add($schemaMasterLabel)

$schemaMasterInput = New-Object System.Windows.Forms.ComboBox
$schemaMasterInput.Location = New-Object System.Drawing.Point(220, 320)
$schemaMasterInput.Size = New-Object System.Drawing.Size(300, 20)
$schemaMasterInput.Items.AddRange($allDCs)
$form.Controls.Add($schemaMasterInput)

$domainNamingMasterLabel = New-Object System.Windows.Forms.Label
$domainNamingMasterLabel.Location = New-Object System.Drawing.Point(10, 350)
$domainNamingMasterLabel.Size = New-Object System.Drawing.Size(200, 20)
$domainNamingMasterLabel.Text = "Domain Naming Master Target:"
$form.Controls.Add($domainNamingMasterLabel)

$domainNamingMasterInput = New-Object System.Windows.Forms.ComboBox
$domainNamingMasterInput.Location = New-Object System.Drawing.Point(220, 350)
$domainNamingMasterInput.Size = New-Object System.Drawing.Size(300, 20)
$domainNamingMasterInput.Items.AddRange($allDCs)
$form.Controls.Add($domainNamingMasterInput)

$pdcEmulatorLabel = New-Object System.Windows.Forms.Label
$pdcEmulatorLabel.Location = New-Object System.Drawing.Point(10, 380)
$pdcEmulatorLabel.Size = New-Object System.Drawing.Size(200, 20)
$pdcEmulatorLabel.Text = "PDC Emulator Target:"
$form.Controls.Add($pdcEmulatorLabel)

$pdcEmulatorInput = New-Object System.Windows.Forms.ComboBox
$pdcEmulatorInput.Location = New-Object System.Drawing.Point(220, 380)
$pdcEmulatorInput.Size = New-Object System.Drawing.Size(300, 20)
$pdcEmulatorInput.Items.AddRange($allDCs)
$form.Controls.Add($pdcEmulatorInput)

$ridMasterLabel = New-Object System.Windows.Forms.Label
$ridMasterLabel.Location = New-Object System.Drawing.Point(10, 410)
$ridMasterLabel.Size = New-Object System.Drawing.Size(200, 20)
$ridMasterLabel.Text = "RID Master Target:"
$form.Controls.Add($ridMasterLabel)

$ridMasterInput = New-Object System.Windows.Forms.ComboBox
$ridMasterInput.Location = New-Object System.Drawing.Point(220, 410)
$ridMasterInput.Size = New-Object System.Drawing.Size(300, 20)
$ridMasterInput.Items.AddRange($allDCs)
$form.Controls.Add($ridMasterInput)

$infrastructureMasterLabel = New-Object System.Windows.Forms.Label
$infrastructureMasterLabel.Location = New-Object System.Drawing.Point(10, 440)
$infrastructureMasterLabel.Size = New-Object System.Drawing.Size(200, 20)
$infrastructureMasterLabel.Text = "Infrastructure Master Target:"
$form.Controls.Add($infrastructureMasterLabel)

$infrastructureMasterInput = New-Object System.Windows.Forms.ComboBox
$infrastructureMasterInput.Location = New-Object System.Drawing.Point(220, 440)
$infrastructureMasterInput.Size = New-Object System.Drawing.Size(300, 20)
$infrastructureMasterInput.Items.AddRange($allDCs)
$form.Controls.Add($infrastructureMasterInput)

# Add a button to retrieve current FSMO roles
$retrieveButton = New-Object System.Windows.Forms.Button
$retrieveButton.Location = New-Object System.Drawing.Point(10, 470)
$retrieveButton.Size = New-Object System.Drawing.Size(150, 30)
$retrieveButton.Text = "Retrieve FSMO Roles"
$retrieveButton.Add_Click({
        $global:retrieveCounter++
        Log-Message "Retrieval #$global:retrieveCounter"
        $roles = Get-FSMORoles
        if ($roles -ne $null) {
            foreach ($role in $roles.Keys) {
                Log-Message "${role}: $($roles[$role])"
            }
        }
    })
$form.Controls.Add($retrieveButton)

# Add a button to transfer FSMO roles
$transferButton = New-Object System.Windows.Forms.Button
$transferButton.Location = New-Object System.Drawing.Point(170, 470)
$transferButton.Size = New-Object System.Drawing.Size(150, 30)
$transferButton.Text = "Transfer FSMO Roles"
$transferButton.Add_Click({
        Transfer-FSMORoles -schemaMasterTarget $schemaMasterInput.SelectedItem -domainNamingMasterTarget $domainNamingMasterInput.SelectedItem -pdcEmulatorTarget $pdcEmulatorInput.SelectedItem -ridMasterTarget $ridMasterInput.SelectedItem -infrastructureMasterTarget $infrastructureMasterInput.SelectedItem
    })
$form.Controls.Add($transferButton)

# Add a button to view the log
$logButton = New-Object System.Windows.Forms.Button
$logButton.Location = New-Object System.Drawing.Point(330, 470)
$logButton.Size = New-Object System.Drawing.Size(150, 30)
$logButton.Text = "View Output Log"
$logButton.Add_Click({
        Show-Log
    })
$form.Controls.Add($logButton)

# Show the form
$form.Add_Shown({ $form.Activate() })
[void] $form.ShowDialog()

# End of script
