<#
.SYNOPSIS
    PowerShell Script for Retrieving DHCP Reservations.

.DESCRIPTION
    This script retrieves DHCP reservations from servers and allows filtering by hostname 
    or description, ensuring accurate documentation and management of network resources.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 24, 2024
#>

param(
    [switch]$ShowConsole = $false
)

# Hide the PowerShell console window for a cleaner UI unless requested to show the console
if (-not $ShowConsole) {
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
}

# Load Windows Forms Assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enhanced logging function with error handling and validation
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "ERROR", "WARNING", "DEBUG", "CRITICAL")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"

    try {
        # Ensure the log path exists, create if necessary
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        # Attempt to write to the log file
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        # Fallback: Log to console if writing to the log file fails
        Write-Error "Failed to write to log: $_"
        Write-Output $logEntry
    }
}

# Unified error handling function refactored as a reusable method
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Log-Message -Message "ERROR: $ErrorMessage" -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

# Function to initialize script name and file paths
function Initialize-ScriptPaths {
    # Use $MyInvocation.ScriptName to get the full path of the script, fallback to "Script" if it doesn't exist
    $scriptName = if ($MyInvocation.ScriptName) {
        [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.ScriptName)
    } else {
        "Script"  # Fallback if no name is available
    }

    # Define the log directory and file name with timestamp
    $logDir = 'C:\Logs-TEMP'
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFileName = "${scriptName}_${timestamp}.log"
    $logPath = Join-Path $logDir $logFileName

    # Ensure the log directory exists, create it if necessary
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Return paths for use in logging
    return @{
        LogDir = $logDir
        LogPath = $logPath
        ScriptName = $scriptName
    }
}

# Function to retrieve forest domains (from TransferDHCPScope.ps1)
function Get-ForestDomains {
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        return $forest.Domains | Select-Object -ExpandProperty Name
    } catch {
        Handle-Error "Failed to retrieve forest domains. Error: $_"
        return @()
    }
}

# Function to retrieve DHCP servers from the domain (from TransferDHCPScope.ps1)
function Get-DHCPServerFromDomain {
    param (
        [string]$domain
    )
    try {
        $dhcpServers = Get-DhcpServerInDC -ErrorAction Stop
        $domainDhcpServers = @()
        if ($dhcpServers -and $dhcpServers.Count -gt 0) {
            foreach ($server in $dhcpServers) {
                if ($server.DNSName -like "*.$domain") {
                    $domainDhcpServers += $server.DNSName
                }
            }
            if ($domainDhcpServers.Count -gt 0) {
                return $domainDhcpServers  # Return all matching DHCP servers for the domain
            } else {
                Handle-Error "No authorized DHCP servers found for the domain '${domain}'."
                return @()
            }
        } else {
            Handle-Error "No authorized DHCP servers found in Active Directory."
            return @()
        }
    } catch {
        Handle-Error "Error retrieving DHCP servers for domain '${domain}': $_"
        return @()
    }
}

# Function to retrieve DHCP scopes from a server (from TransferDHCPScope.ps1)
function Get-DhcpScopesFromServer {
    param (
        [string]$dhcpServer
    )
    try {
        $scopes = Get-DhcpServerv4Scope -ComputerName $dhcpServer -ErrorAction Stop
        if ($scopes) {
            return $scopes
        } else {
            Log-Message -Message "No scopes found on DHCP server $dhcpServer" -MessageType "WARNING"
            return @()
        }
    } catch {
        Handle-Error "Error retrieving scopes from DHCP server '$dhcpServer'. Error: $_"
        return @()
    }
}

# Function to execute the retrieval of DHCP reservations (adapted from Export-DhcpScope)
function Retrieve-DhcpReservations {
    param (
        [string[]]$Servers,
        [string]$NameFilter,
        [string]$DescriptionFilter
    )

    $global:allReservations = @()
    $global:filteredReservations = @()

    foreach ($dhcpServer in $Servers) {
        Log-Message -Message "Processing DHCP server: $dhcpServer" -MessageType "INFO"

        # Get all DHCP scopes on the specified server
        $scopes = Get-DhcpScopesFromServer -dhcpServer $dhcpServer

        if ($scopes) {
            Log-Message -Message "Found $($scopes.Count) scopes on DHCP server $dhcpServer" -MessageType "INFO"

            # Loop through each scope to get reservations
            foreach ($scope in $scopes) {
                $reservations = Get-DhcpServerv4Reservation -ComputerName $dhcpServer -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
                if ($reservations) {
                    # Add the DHCPServer property to each reservation
                    foreach ($reservation in $reservations) {
                        $reservation | Add-Member -NotePropertyName "DHCPServer" -NotePropertyValue $dhcpServer -Force
                    }
                    $global:allReservations += $reservations
                    Log-Message -Message "Retrieved $($reservations.Count) reservations from scope $($scope.ScopeId) on server $dhcpServer" -MessageType "INFO"
                } else {
                    Log-Message -Message "No reservations found in scope $($scope.ScopeId) on server $dhcpServer" -MessageType "WARNING"
                }
            }
        } else {
            Log-Message -Message "No scopes found on DHCP server $dhcpServer" -MessageType "WARNING"
        }
    }

    if ($global:allReservations.Count -eq 0) {
        Handle-Error "No reservations found on the selected DHCP servers."
        return
    }

    # Apply filters (hostname and description)
    $global:filteredReservations = Apply-Filters -Reservations $global:allReservations -NameFilter $NameFilter -DescriptionFilter $DescriptionFilter

    if ($global:filteredReservations.Count -eq 0) {
        Handle-Error "No reservations match the specified filter."
        return
    }

    return $global:filteredReservations
}

# Define filter application logic (from previous code)
function Apply-Filters {
    param (
        [array]$Reservations,
        [string]$NameFilter,
        [string]$DescriptionFilter
    )

    if (-not [string]::IsNullOrEmpty($NameFilter) -or -not [string]::IsNullOrEmpty($DescriptionFilter)) {
        $filteredReservations = $Reservations
        if (-not [string]::IsNullOrEmpty($NameFilter)) {
            $regexPatternName = ($NameFilter -split ',' | ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|'
            $filteredReservations = $filteredReservations | Where-Object { $_.Name -match $regexPatternName }
        }
        if (-not [string]::IsNullOrEmpty($DescriptionFilter)) {
            $regexPatternDesc = ($DescriptionFilter -split ',' | ForEach-Object { [regex]::Escape($_.Trim()) }) -join '|'
            $filteredReservations = $filteredReservations | Where-Object { $_.Description -match $regexPatternDesc }
        }
        return $filteredReservations
    }
    return $Reservations # Return all if no filters are applied
}

# Function to execute the export of reservations to CSV (adapted from Export-DhcpScope)
function Export-ReservationsToCSV {
    param (
        [array]$Reservations,
        [string]$FilePath
    )

    try {
        if ($Reservations.Count -gt 0) {
            # Export the filtered reservations to CSV
            $Reservations | Select-Object DHCPServer, ScopeId, IPAddress, ClientId, Description, Name | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8

            # Log success message
            Log-Message -Message "Reservations exported successfully to $FilePath" -MessageType "INFO"
            [System.Windows.Forms.MessageBox]::Show("Reservations exported successfully to $FilePath", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            Handle-Error "No reservations to export."
        }
    } catch {
        Handle-Error "An error occurred during export: $($_.Exception.Message)"
    }
}

# Function to create the GUI (adapted from Create-GUI)
function Create-GUI {
    # Create the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "DHCP Reservations Viewer"
    $form.Size = New-Object System.Drawing.Size(850, 650)
    $form.StartPosition = "CenterScreen"

    # Create controls
    $labelDomain = New-Object System.Windows.Forms.Label
    $labelDomain.Text = "Domain:"
    $labelDomain.Location = New-Object System.Drawing.Point(10, 20)
    $labelDomain.Size = New-Object System.Drawing.Size(110, 20)
    $form.Controls.Add($labelDomain)

    $comboBoxDomain = New-Object System.Windows.Forms.ComboBox
    $comboBoxDomain.Location = New-Object System.Drawing.Point(130, 20)
    $comboBoxDomain.Size = New-Object System.Drawing.Size(390, 20)
    $comboBoxDomain.DropDownStyle = 'DropDownList'
    $form.Controls.Add($comboBoxDomain)

    $labelDhcpServer = New-Object System.Windows.Forms.Label
    $labelDhcpServer.Text = "DHCP Servers:"
    $labelDhcpServer.Location = New-Object System.Drawing.Point(10, 50)
    $labelDhcpServer.Size = New-Object System.Drawing.Size(110, 20)
    $form.Controls.Add($labelDhcpServer)

    # CheckedListBox to display the DHCP servers
    $checkedListDhcpServers = New-Object System.Windows.Forms.CheckedListBox
    $checkedListDhcpServers.Location = New-Object System.Drawing.Point(130, 50)
    $checkedListDhcpServers.Size = New-Object System.Drawing.Size(390, 100)
    $checkedListDhcpServers.CheckOnClick = $true
    $form.Controls.Add($checkedListDhcpServers)

    $labelNameFilter = New-Object System.Windows.Forms.Label
    $labelNameFilter.Text = "Filter by Name:"
    $labelNameFilter.Location = New-Object System.Drawing.Point(10, 160)
    $labelNameFilter.Size = New-Object System.Drawing.Size(110, 20)
    $form.Controls.Add($labelNameFilter)

    $textNameFilter = New-Object System.Windows.Forms.TextBox
    $textNameFilter.Location = New-Object System.Drawing.Point(130, 160)
    $textNameFilter.Size = New-Object System.Drawing.Size(390, 20)
    $form.Controls.Add($textNameFilter)

    $labelDescriptionFilter = New-Object System.Windows.Forms.Label
    $labelDescriptionFilter.Text = "Filter by Description:"
    $labelDescriptionFilter.Location = New-Object System.Drawing.Point(10, 190)
    $labelDescriptionFilter.Size = New-Object System.Drawing.Size(110, 20)
    $form.Controls.Add($labelDescriptionFilter)

    $textDescriptionFilter = New-Object System.Windows.Forms.TextBox
    $textDescriptionFilter.Location = New-Object System.Drawing.Point(130, 190)
    $textDescriptionFilter.Size = New-Object System.Drawing.Size(390, 20)
    $form.Controls.Add($textDescriptionFilter)

    # ToolTip for Name filter textbox
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($textNameFilter, "Enter hostnames separated by commas (e.g. PRT,WKS,SRV)")

    # Create buttons
    $buttonGetReservations = New-Object System.Windows.Forms.Button
    $buttonGetReservations.Location = New-Object System.Drawing.Point(550, 18)
    $buttonGetReservations.Size = New-Object System.Drawing.Size(120, 25)
    $buttonGetReservations.Text = "Get Reservations"
    $form.Controls.Add($buttonGetReservations)

    $buttonExportCSV = New-Object System.Windows.Forms.Button
    $buttonExportCSV.Location = New-Object System.Drawing.Point(680, 18)
    $buttonExportCSV.Size = New-Object System.Drawing.Size(120, 25)
    $buttonExportCSV.Text = "Export to CSV"
    $buttonExportCSV.Enabled = $false  # Initially disabled
    $form.Controls.Add($buttonExportCSV)

    # Create a DataGridView to display the reservations
    $dataGridView = New-Object System.Windows.Forms.DataGridView
    $dataGridView.Location = New-Object System.Drawing.Point(10, 230)
    $dataGridView.Size = New-Object System.Drawing.Size(810, 370)
    $dataGridView.AutoSizeColumnsMode = 'Fill'
    $dataGridView.ReadOnly = $true
    $form.Controls.Add($dataGridView)

    # Populate domain ComboBox
    $domains = Get-ForestDomains
    if ($domains.Count -gt 0) {
        $comboBoxDomain.Items.AddRange($domains)
    } else {
        Handle-Error "No domains found in the forest."
    }

    # Event handler for when a domain is selected
    $comboBoxDomain.Add_SelectedIndexChanged({
            $selectedDomain = $comboBoxDomain.SelectedItem
            if ($selectedDomain) {
                $checkedListDhcpServers.Items.Clear()
                $dhcpServersList = Get-DHCPServerFromDomain -domain $selectedDomain
                if ($dhcpServersList.Count -gt 0) {
                    foreach ($server in $dhcpServersList) {
                        [void]$checkedListDhcpServers.Items.Add($server)
                    }
                    Log-Message -Message "DHCP servers for domain '$selectedDomain' loaded." -MessageType "INFO"
                } else {
                    Handle-Error "No DHCP servers found for domain '$selectedDomain'."
                }
            }
        })

    # Define the button click event for Get Reservations
    $buttonGetReservations.Add_Click({
            # Clear previous data
            $dataGridView.Rows.Clear()
            $dataGridView.Columns.Clear()
            $global:allReservations = @()
            $global:filteredReservations = @()
            $buttonExportCSV.Enabled = $false  # Disable export button until data is loaded

            try {
                # Get the selected DHCP servers from the CheckedListBox
                $checkedItems = $checkedListDhcpServers.CheckedItems
                if ($checkedItems.Count -eq 0) {
                    Handle-Error "Please select at least one DHCP server."
                    return
                } else {
                    $dhcpServers = $checkedItems
                    Log-Message -Message "Using selected DHCP servers: $($dhcpServers -join ', ')" -MessageType "INFO"
                }

                # Get filters
                $filterTextName = $textNameFilter.Text.Trim()
                $filterTextDescription = $textDescriptionFilter.Text.Trim()

                # Retrieve reservations
                $reservations = Retrieve-DhcpReservations -Servers $dhcpServers -NameFilter $filterTextName -DescriptionFilter $filterTextDescription

                if ($reservations) {
                    # Prepare the DataGridView columns
                    $columns = @("DHCPServer", "ScopeId", "IPAddress", "ClientId", "Description", "Name")
                    foreach ($col in $columns) {
                        $dataGridView.Columns.Add($col, $col)
                    }

                    # Populate the DataGridView with reservation data
                    foreach ($reservation in $reservations) {
                        $row = $dataGridView.Rows.Add()
                        $dataGridView.Rows[$row].Cells["DHCPServer"].Value = $reservation.DHCPServer
                        $dataGridView.Rows[$row].Cells["ScopeId"].Value = $reservation.ScopeId
                        $dataGridView.Rows[$row].Cells["IPAddress"].Value = $reservation.IPAddress
                        $dataGridView.Rows[$row].Cells["ClientId"].Value = $reservation.ClientId
                        $dataGridView.Rows[$row].Cells["Description"].Value = $reservation.Description
                        $dataGridView.Rows[$row].Cells["Name"].Value = $reservation.Name
                    }

                    $buttonExportCSV.Enabled = $true  # Enable export button now that data is loaded

                    Log-Message -Message "Successfully retrieved and displayed reservations." -MessageType "INFO"
                }
            } catch {
                Handle-Error "An error occurred while retrieving reservations: $($_.Exception.Message)"
            }
        })

    # Define the button click event for Export to CSV
    $buttonExportCSV.Add_Click({
            try {
                # Create a SaveFileDialog
                $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
                $saveFileDialog.Filter = "CSV Files (*.csv)|*.csv"
                $saveFileDialog.Title = "Save DHCP Reservations"
                $saveFileDialog.InitialDirectory = [Environment]::GetFolderPath("Desktop")
                $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $saveFileDialog.FileName = "DhcpReservations_$timestamp.csv"

                if ($saveFileDialog.ShowDialog() -eq 'OK') {
                    $csvPath = $saveFileDialog.FileName

                    # Export reservations to CSV
                    Export-ReservationsToCSV -Reservations $global:filteredReservations -FilePath $csvPath
                }
            } catch {
                Handle-Error "An error occurred during export: $($_.Exception.Message)"
            }
        })

    # Run the form
    [void]$form.ShowDialog()
}

# Initialize Script Paths and Logging
$paths = Initialize-ScriptPaths
$global:logDir = $paths.LogDir
$global:logPath = $paths.LogPath

# Ensure the log directory and file exist
try {
    if (-not (Test-Path $global:logDir)) {
        New-Item -Path $global:logDir -ItemType Directory -Force | Out-Null
    }
    # Create the log file if it doesn't exist
    if (-not (Test-Path $global:logPath)) {
        New-Item -Path $global:logPath -ItemType File -Force | Out-Null
    }
} catch {
    Handle-Error "Failed to initialize logging."
    exit
}

# Import Necessary Modules with Error Handling
function Import-Modules {
    try {
        Import-Module DHCPServer -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Handle-Error "Failed to import necessary modules."
        exit
    }
}
Import-Modules

# Log that the script has started
Log-Message -Message "Script started" -MessageType "INFO"

# Execute the GUI creation function
Create-GUI

# End of script
