<#
.SYNOPSIS
    PowerShell Script to Configure and Extract Advanced Audit Policies for Microsoft Defender for Identity (MDI).

.DESCRIPTION
    This script retrieves Advanced Audit Policies applied via GPOs on selected servers, maps audit policies to GPOs, and generates a CSV report in the My Documents folder. All actions, including RSOP reports, are logged in C:\Logs-TEMP. The script includes an enhanced progress bar to monitor the process in real-time.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: November 28, 2024
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

# Import required modules
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Required modules are missing or failed to load. Ensure GroupPolicy and ActiveDirectory modules are installed.",
        "Module Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit
}

# Function to initialize script paths
function Initialize-ScriptPaths {
    $scriptName = "MDI_AuditPolicyConfig"
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $documentsFolder = [Environment]::GetFolderPath("MyDocuments")
    $csvPath = Join-Path $documentsFolder "${scriptName}_AuditReport_${timestamp}.csv"
    $logDir = 'C:\Logs-TEMP'
    $logPath = Join-Path $logDir "${scriptName}_${timestamp}.log"
    $rsopDir = Join-Path $logDir "RSOP_Reports"
    
    # Ensure log and RSOP report directories exist
    foreach ($dir in @($logDir, $rsopDir)) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Failed to create directory at $dir.",
                    "Directory Creation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                exit
            }
        }
    }

    return @{
        CsvPath = $csvPath
        LogPath = $logPath
        RsopDir = $rsopDir
    }
}

# Initialize paths
$paths = Initialize-ScriptPaths
$csvPath = $paths.CsvPath
$logPath = $paths.LogPath
$rsopDir = $paths.RsopDir

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][ValidateSet("INFO", "ERROR", "WARNING")][string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[${timestamp}] [${MessageType}] " + $Message
    Add-Content -Path $logPath -Value $logEntry
}

# Unified error handling function
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )
    Log-Message -Message $ErrorMessage -MessageType "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        $ErrorMessage,
        "Error",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

# Retrieve all machine servers from the forest, sorted alphabetically
function Get-AllMachineServers {
    try {
        $servers = Get-ADComputer -Filter { OperatingSystem -like "*Server*" } -Property Name | 
            Select-Object -ExpandProperty Name | 
            Sort-Object
        Log-Message ("Retrieved " + $servers.Count + " servers from the forest.")
        return $servers
    } catch {
        $errorMessage = $_.Exception.Message
        Handle-Error ("Failed to retrieve servers from the forest: " + $errorMessage)
        return @()
    }
}

# Function to display GUI with an improved progress bar
function Show-MDIConfigurationForm {
    # Initialize the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Audit Policy Configuration Report"
    $form.Size = New-Object System.Drawing.Size(600, 530)
    $form.StartPosition = "CenterScreen"

    # Label for server selection
    $labelServer = New-Object System.Windows.Forms.Label
    $labelServer.Text = "Select Server:"
    $labelServer.Location = New-Object System.Drawing.Point(10, 20)
    $labelServer.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelServer)

    # Dropdown for server selection
    $comboBoxServer = New-Object System.Windows.Forms.ComboBox
    $comboBoxServer.Location = New-Object System.Drawing.Point(120, 20)
    $comboBoxServer.Size = New-Object System.Drawing.Size(450, 20)
    $comboBoxServer.DropDownStyle = 'DropDownList'

    # Populate the dropdown with sorted server names
    $servers = Get-AllMachineServers
    if ($servers.Count -eq 0) {
        Handle-Error "No servers retrieved from the forest. The script will exit."
        exit
    }
    $comboBoxServer.Items.AddRange($servers)
    $comboBoxServer.SelectedIndex = 0  # Select the first server by default
    $form.Controls.Add($comboBoxServer)

    # Progress Bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(10, 60)
    $progressBar.Size = New-Object System.Drawing.Size(560, 25)
    $progressBar.Style = 'Continuous'
    $form.Controls.Add($progressBar)

    # Label for Progress
    $labelProgress = New-Object System.Windows.Forms.Label
    $labelProgress.Text = "Progress:"
    $labelProgress.Location = New-Object System.Drawing.Point(10, 90)
    $labelProgress.Size = New-Object System.Drawing.Size(100, 20)
    $form.Controls.Add($labelProgress)

    # TextBox for Progress Details
    $textBoxProgress = New-Object System.Windows.Forms.TextBox
    $textBoxProgress.Location = New-Object System.Drawing.Point(10, 120)
    $textBoxProgress.Size = New-Object System.Drawing.Size(560, 250)
    $textBoxProgress.Multiline = $true
    $textBoxProgress.ScrollBars = 'Vertical'
    $textBoxProgress.ReadOnly = $true
    $form.Controls.Add($textBoxProgress)

    # Generate Report Button
    $buttonGenerate = New-Object System.Windows.Forms.Button
    $buttonGenerate.Text = "Generate Audit Report"
    $buttonGenerate.Location = New-Object System.Drawing.Point(10, 430)
    $buttonGenerate.Size = New-Object System.Drawing.Size(560, 30)
    $form.Controls.Add($buttonGenerate)

    # Event Handler for Button Click
    $buttonGenerate.Add_Click({
            $selectedServer = $comboBoxServer.SelectedItem
            if (-not $selectedServer) {
                [System.Windows.Forms.MessageBox]::Show("Please select a server to proceed.", "Input Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            # Disable UI elements during processing
            $buttonGenerate.Enabled = $false
            $comboBoxServer.Enabled = $false

            # Initialize Progress Bar and TextBox
            $progressBar.Minimum = 0
            $progressBar.Maximum = 100
            $progressBar.Value = 0
            $textBoxProgress.Clear()

            # Start Processing in a Background Job to Keep UI Responsive
            $job = Start-Job -ScriptBlock {
                param($ServerName, $CsvPath, $LogPath, $rsopDir)

                # Define Progress Bar sections (20% for each of 5 steps)
                function Update-Progress {
                    param ($Section)
                    Write-Output ("PROGRESS:" + ($Section * 20))
                }

                # Define Parse-GPOsForAuditPolicies function inside the job
                function Parse-GPOsForAuditPolicies {
                    param (
                        [Parameter(Mandatory = $true)][string]$GpoXmlPath
                    )

                    try {
                        [xml]$gpoXml = Get-Content -Path $GpoXmlPath
                        Write-Output ("[INFO] Successfully loaded GPO XML from " + $GpoXmlPath + ".")
                    } catch {
                        $errorMessage = $_.Exception.Message
                        Write-Output ("[ERROR] Failed to load GPO XML from " + $GpoXmlPath + ": " + $errorMessage)
                        return @()
                    }

                    # Define a namespace manager to handle the XML namespaces correctly
                    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($gpoXml.NameTable)
                    $namespaceManager.AddNamespace("q1", "http://www.microsoft.com/GroupPolicy/Types")

                    $policies = @()
                    # XPath to locate audit policies and their associated GPOs
                    $auditPolicyNodes = $gpoXml.SelectNodes("//q1:Policy/q1:PolicySettings/q1:PolicySetting", $namespaceManager)

                    if ($auditPolicyNodes -eq $null -or $auditPolicyNodes.Count -eq 0) {
                        Write-Output ("[WARNING] No Audit Policy nodes found in GPO XML at " + $GpoXmlPath + ".")
                        return $policies
                    } else {
                        Write-Output ("[INFO] Found " + $auditPolicyNodes.Count + " Audit Policy nodes in GPO XML.")
                    }

                    foreach ($policyNode in $auditPolicyNodes) {
                        # Extract Policy Name and GPO Name
                        $policyName = $policyNode.SelectSingleNode("q1:Name", $namespaceManager).InnerText
                        $gpoNameNode = $policyNode.ParentNode.ParentNode.SelectSingleNode("q1:GPOName", $namespaceManager)
                        $gpoName = if ($gpoNameNode) { $gpoNameNode.InnerText } else { "Not Configured" }

                        Write-Output ("[INFO] Processing Policy: " + $policyName + ", Configured By GPO: " + $gpoName + ".")

                        $policies += [PSCustomObject]@{
                            PolicyName = $policyName
                            GPOName = $gpoName
                        }
                    }
                    return $policies
                }

                # Function to generate RSOP report
                function Generate-RSOPReport {
                    param (
                        [string]$ServerName,
                        [string]$RsopXmlPath
                    )
                    try {
                        Write-Output ("[INFO] Generating RSOP report for server ${ServerName}...")
                        Get-GPResultantSetOfPolicy -Computer $ServerName -ReportType Xml -Path $RsopXmlPath -ErrorAction Stop
                        Write-Output ("[INFO] RSOP report generated at ${RsopXmlPath}.")
                    } catch {
                        $errorMessage = $_.Exception.Message
                        Write-Output ("[ERROR] Failed to generate RSOP report for ${ServerName}: ${errorMessage}")
                        throw
                    }
                }

                # Start Processing
                Write-Output ("[INFO] Starting audit report generation for server: ${ServerName}.")

                # Define CSV Output Path with timestamp to prevent overwriting
                $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
                $csvOutputPath = $CsvPath.Replace('.csv', "_${timestamp}.csv")

                # Define RSOP XML path within RSOP reports directory
                $rsopXmlPath = Join-Path $rsopDir "RSOP_${ServerName}_$timestamp.xml"

                # Step 1: Generate RSOP report
                try {
                    Generate-RSOPReport -ServerName $ServerName -RsopXmlPath $rsopXmlPath
                    Update-Progress -Section 1
                } catch {
                    Write-Output ("[ERROR] An error occurred during RSOP report generation.")
                    Write-Output ("PROGRESS:100")
                    return
                }

                # Step 2: Parse RSOP report
                $auditPolicies = Parse-GPOsForAuditPolicies -GpoXmlPath $rsopXmlPath
                if (-not $auditPolicies) {
                    Write-Output ("[ERROR] No audit policies found in RSOP for ${ServerName}.")
                    Write-Output ("PROGRESS:100")
                    return
                }
                Update-Progress -Section 2

                # Step 3: Define required policies with categories and EventIDs
                $RequiredPolicies = @(
                    @{ Category = "Account Logon"; Policy = "Audit Credential Validation"; EventIDs = @(4776, 4625) },
                    @{ Category = "Account Management"; Policy = "Audit Security Group Management"; EventIDs = @(4728, 4729, 4732, 4733) },
                    @{ Category = "Logon/Logoff"; Policy = "Audit Logon"; EventIDs = @(4624, 4625, 4648) },
                    @{ Category = "Object Access"; Policy = "Audit File System"; EventIDs = @(4663, 4656) },
                    @{ Category = "Privilege Use"; Policy = "Audit Sensitive Privilege Use"; EventIDs = @(4672) },
                    @{ Category = "Policy Change"; Policy = "Audit Policy Change"; EventIDs = @(4719, 4907) }
                )
                Update-Progress -Section 3

                # Step 4: Process policies and create CSV data
                $csvData = @()
                foreach ($requiredPolicy in $RequiredPolicies) {
                    $Category = $requiredPolicy.Category
                    $PolicyName = $requiredPolicy.Policy
                    $EventIDs = $requiredPolicy.EventIDs -join ", "

                    # Check if the required policy exists in RSOP
                    $foundPolicy = $auditPolicies | Where-Object { $_.PolicyName -eq $PolicyName }

                    if ($foundPolicy) {
                        $GpoName = $foundPolicy.GPOName
                        $status = if ($GpoName -eq "Not Configured" -or [string]::IsNullOrEmpty($GpoName)) { "Missing" } else { "Configured" }
                    } else {
                        $GpoName = "Not Configured"
                        $status = "Missing"
                    }

                    $csvData += [PSCustomObject]@{
                        Category = $Category
                        Policy = $PolicyName
                        EventIDs = $EventIDs
                        ConfiguredByGPO = $GpoName
                        Status = $status
                    }

                    if ($foundPolicy) {
                        Write-Output ("[INFO] Policy ${PolicyName} processed successfully.")
                    } else {
                        Write-Output ("[WARNING] Policy ${PolicyName} not found in RSOP.")
                    }
                }
                Update-Progress -Section 4

                # Step 5: Export CSV
                try {
                    $csvData | Export-Csv -Path $csvOutputPath -NoTypeInformation -Encoding UTF8 -Force | Out-Null
                    Write-Output ("[INFO] CSV report saved to ${csvOutputPath}.")
                    Update-Progress -Section 5
                } catch {
                    $errorMessage = $_.Exception.Message
                    Write-Output ("[ERROR] Failed to save CSV report to ${csvOutputPath}: ${errorMessage}")
                    Write-Output ("PROGRESS:100")
                    return
                }

                # Final Progress Update
                Write-Output ("PROGRESS:100")
                Write-Output ("[INFO] CSV report successfully saved to ${csvOutputPath}.")
            } -ArgumentList $selectedServer, $csvPath, $logPath, $rsopDir

            # Monitor the Background Job
            while ($true) {
                $jobState = $job.State
                $jobOutput = Receive-Job -Job $job -Keep

                foreach ($line in $jobOutput) {
                    # Update progress for specific steps
                    if ($line -like "[INFO] Starting audit report generation for server:*") {
                        $form.Invoke([Action] {
                                $progressBar.Value = 20  # Step 1 - Starting audit report generation
                            }) | Out-Null
                    } elseif ($line -like "[INFO] RSOP report generated at*") {
                        $form.Invoke([Action] {
                                $progressBar.Value = 40  # Step 2 - RSOP report generation completed
                            }) | Out-Null
                    } elseif ($line -like "[INFO] Found * Audit Policy nodes in GPO XML.") {
                        $form.Invoke([Action] {
                                $progressBar.Value = 60  # Step 3 - Parsing audit policies completed
                            }) | Out-Null
                    } elseif ($line -like "[INFO] CSV report saved to*") {
                        $form.Invoke([Action] {
                                $progressBar.Value = 80  # Step 4 - CSV report processing completed
                            }) | Out-Null
                    }

                    # Display progress messages in the TextBox
                    if ($line -match "^\[.*\]") {
                        $lineContent = $line
                        $form.Invoke([Action] {
                                $textBoxProgress.AppendText($lineContent + "`r`n")
                                $textBoxProgress.ScrollToCaret()
                            }) | Out-Null

                        # Also log the message
                        $messageTypeMatch = $line -match "^\[(INFO|ERROR|WARNING)\]"
                        if ($messageTypeMatch) {
                            $messageType = $matches[1]
                            Log-Message -Message ($line -replace "^\[.*?\] ", "") -MessageType $messageType
                        } else {
                            Log-Message -Message ($line -replace "^\[.*?\] ", "") -MessageType "INFO"
                        }
                    }
                }

                # Break out of loop once the job is completed
                if ($jobState -eq 'Completed' -or $jobState -eq 'Failed' -or $jobState -eq 'Stopped') {
                    break
                }

                Start-Sleep -Milliseconds 500
            }

            # Finalize Progress Bar
            $form.Invoke([Action] {
                    $progressBar.Value = 100  # Step 5 - All tasks completed
                }) | Out-Null

            # Ensure Job is Completed before Proceeding
            $finalOutput = Receive-Job -Job $job -Wait -AutoRemoveJob
            $csvSuccess = $finalOutput | Where-Object { $_ -like "[INFO] CSV report successfully saved to *" }

            # Display the Final Success Message Window
            if ($csvSuccess) {
                # Extract the CSV path from the final output
                $csvPathExtract = $csvSuccess -replace "^\[INFO\] CSV report successfully saved to ", ""
                # Show INFO Message Box
                $form.Invoke([Action] {
                        [System.Windows.Forms.MessageBox]::Show(
                            "CSV report successfully saved to: `n${csvPathExtract}",
                            "Success",
                            [System.Windows.Forms.MessageBoxButtons]::OK,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        )
                    }) | Out-Null
            }

            # Enable UI elements after processing
            $form.Invoke([Action] {
                    $buttonGenerate.Enabled = $true
                    $comboBoxServer.Enabled = $true
                }) | Out-Null
        })

    # Show the form (Start the UI)
    [void]$form.ShowDialog()
}

# Start the GUI
Show-MDIConfigurationForm

# End of script
