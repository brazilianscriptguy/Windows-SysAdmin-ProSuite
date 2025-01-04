# Hide PowerShell console window for a cleaner GUI experience
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

# Import necessary assemblies for GUI and file handling
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Configuration Variables
$scriptPath = $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptPath
$repoName = Split-Path -Leaf $repoRoot
$githubusername = "brazilianscriptguy"
$packageSourceUrl = "https://nuget.pkg.github.com/$githubusername/index.json"

# Paths based on repository structure
$nugetExePath = "nuget.exe" # Ensure nuget.exe is available in PATH
$virtualDir = Join-Path (Join-Path $repoRoot "NuGet") "NuGetPackageContent"
$artifactDir = Join-Path $repoRoot "artifacts"
$gpoTemplatesSource = Join-Path $repoRoot "SysAdmin-Tools\GroupPolicyObjects-Templates"
$docDir = Join-Path $repoRoot "doc"
$logDir = "C:\Logs-TEMP"
$logFile = "Publish-NuGetPackage_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logPath = Join-Path $logDir $logFile

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    try {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to create log directory at $logDir. Logging will not be possible.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit 1
    }
}

# Function Definitions

# Function: Log-Message
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to write to log: $_", "Warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    }
}

# Function: Show-MessageBox
function Show-MessageBox {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$Title = "Information",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Icon = "Information"
    )
    $iconEnum = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $iconEnum)
}

# Function: Validate-Directory
function Validate-Directory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirPath
    )
    if (-not (Test-Path $DirPath)) {
        try {
            New-Item -Path $DirPath -ItemType Directory -Force | Out-Null
            Log-Message "Created directory: $DirPath"
        }
        catch {
            Log-Message "Failed to create directory: $DirPath. Error: $_" -MessageType "ERROR"
            Show-MessageBox "Failed to create directory: $DirPath" "Error" "Error"
            throw
        }
    }
    else {
        Log-Message "Directory already exists: $DirPath"
    }
}

# Function: Generate-GPOsTemplates
function Generate-GPOsTemplates {
    # Create or copy GPOs-Templates
    $gpoPath = Join-Path $virtualDir "GPOs-Templates"
    if (-Not (Test-Path $gpoPath)) {
        Log-Message "GPOs-Templates directory not found. Generating from source..."
        try {
            Validate-Directory -DirPath $gpoPath
            Copy-Item -Path $gpoTemplatesSource -Destination $gpoPath -Recurse -Force -ErrorAction Stop
            Log-Message "Copied GPOs-Templates from $gpoTemplatesSource to $gpoPath"
        }
        catch {
            Log-Message "Failed to create or copy GPOs-Templates: $_" -MessageType "ERROR"
            Show-MessageBox "Failed to create or copy GPOs-Templates. Check logs for details." "Error" "Error"
            throw
        }
    }
    else {
        Log-Message "GPOs-Templates directory already exists at $gpoPath."
    }
}

# Function: Prepare-Files
function Prepare-Files {
    Log-Message "Preparing files for NuGet package..."
    Validate-Directory -DirPath $virtualDir

    # Copy necessary directories and files
    $directoriesToCopy = @(
        "Core-ScriptLibrary",
        "ITSM-Templates-SVR",
        "ITSM-Templates-WKS",
        "SysAdmin-Tools"
    )
    foreach ($dir in $directoriesToCopy) {
        $sourcePath = Join-Path $repoRoot $dir
        if (Test-Path $sourcePath) {
            try {
                if ($dir -eq "SysAdmin-Tools") {
                    # Exclude GroupPolicyObjects-Templates from SysAdmin-Tools
                    Copy-Item -Path $sourcePath -Destination $virtualDir -Recurse -Force -Exclude "GroupPolicyObjects-Templates" -ErrorAction Stop
                }
                else {
                    Copy-Item -Path $sourcePath -Destination $virtualDir -Recurse -Force -ErrorAction Stop
                }
                Log-Message "Copied $dir to $virtualDir"
            }
            catch {
                Log-Message "Failed to copy $dir: $_" -MessageType "WARNING"
            }
        }
        else {
            Log-Message "Directory $dir does not exist in the repository." -MessageType "WARNING"
        }
    }

    # Copy README.md and LICENSE
    $sourceReadme = Join-Path $docDir "README.md"
    $destReadme = Join-Path $virtualDir "README.md"
    if (Test-Path $sourceReadme) {
        try {
            Copy-Item -Path $sourceReadme -Destination $destReadme -Force -ErrorAction Stop
            Log-Message "Copied README.md to $virtualDir"
        }
        catch {
            Log-Message "Failed to copy README.md: $_" -MessageType "WARNING"
        }
    }
    else {
        Log-Message "README.md not found in $docDir" -MessageType "WARNING"
    }

    $sourceLicense = Join-Path $repoRoot "LICENSE"
    $destLicense = Join-Path $virtualDir "LICENSE"
    if (Test-Path $sourceLicense) {
        try {
            Copy-Item -Path $sourceLicense -Destination $destLicense -Force -ErrorAction Stop
            Log-Message "Copied LICENSE to $virtualDir"
        }
        catch {
            Log-Message "Failed to copy LICENSE: $_" -MessageType "WARNING"
        }
    }
    else {
        Log-Message "LICENSE file not found at repository root." -MessageType "WARNING"
    }
}

# Function: Verify-VirtualDirectory
function Verify-VirtualDirectory {
    Log-Message "Verifying contents of NuGetPackageContent..."
    try {
        Get-ChildItem -Path $virtualDir -Recurse | ForEach-Object {
            Log-Message $_.FullName
        }
    }
    catch {
        Log-Message "Failed to list contents of $virtualDir: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to list contents of $virtualDir. Check logs for details." "Error" "Error"
        throw
    }

    # Check GPOs-Templates directory
    $gpoPath = Join-Path $virtualDir "GPOs-Templates"
    Log-Message "Verifying GPOs-Templates directory..."
    if (Test-Path $gpoPath) {
        try {
            Get-ChildItem -Path $gpoPath | ForEach-Object {
                Log-Message $_.FullName
            }
        }
        catch {
            Log-Message "Failed to list contents of GPOs-Templates: $_" -MessageType "ERROR"
            Show-MessageBox "Failed to list contents of GPOs-Templates. Check logs for details." "Error" "Error"
            throw
        }
    }
    else {
        Log-Message "GPOs-Templates directory is missing." -MessageType "ERROR"
        Show-MessageBox "GPOs-Templates directory is missing." "Error" "Error"
        throw
    }
}

# Function: Generate-DynamicVersion
function Generate-DynamicVersion {
    $major = 1
    $minor = 0
    $build = Get-Date -Format "yyMMdd"
    $revision = Get-Date -Format "HHmmss"
    $version = "$major.$minor.$build.$revision"
    Log-Message "Generated Version: $version"
    return $version
}

# Function: Update-NuspecVersion
function Update-NuspecVersion {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )
    try {
        (Get-Content $nuspecPath) -replace '<version>.*<\/version>', "<version>$Version</version>" | Set-Content $nuspecPath -ErrorAction Stop
        Log-Message ".nuspec file updated with version $Version"
    }
    catch {
        Log-Message "Failed to update .nuspec file: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to update .nuspec file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Pack-NuGetPackage
function Pack-NuGetPackage {
    Log-Message "Packing NuGet package..."
    try {
        Validate-Directory -DirPath $artifactDir
        $packOutput = & "$nugetExePath" pack "$nuspecPath" -OutputDirectory "$artifactDir" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "nuget.exe pack failed: $packOutput"
        }
        Log-Message "NuGet package packed to $artifactDir"
        Show-MessageBox "NuGet package packed successfully to $artifactDir." "Success" "Information"
    }
    catch {
        Log-Message "Failed to pack NuGet package: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to pack NuGet package. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Inspect-NuGetPackage
function Inspect-NuGetPackage {
    Log-Message "Inspecting the contents of the package..."
    $nupkgFile = Get-ChildItem -Path $artifactDir -Filter "*.nupkg" | Select-Object -First 1
    if ($nupkgFile) {
        try {
            $extractDir = Join-Path $artifactDir "PackageContents_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Validate-Directory -DirPath $extractDir
            Expand-Archive -Path $nupkgFile.FullName -DestinationPath $extractDir -Force
            Log-Message "Package contents extracted to $extractDir"
            Show-MessageBox "Package inspected at $extractDir." "Information" "Information"
        }
        catch {
            Log-Message "Failed to inspect NuGet package: $_" -MessageType "WARNING"
            Show-MessageBox "Failed to inspect NuGet package. Check logs for details." "Warning" "Warning"
        }
    }
    else {
        Log-Message "No .nupkg file found in $artifactDir to inspect." -MessageType "WARNING"
        Show-MessageBox "No .nupkg file found in $artifactDir to inspect." "Warning" "Warning"
    }
}

# GUI Configuration and Execution
$form = New-Object System.Windows.Forms.Form
$form.Text = "NuGet Package Publisher"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

# GitHub Username Field
$labelGitHubUsername = New-Object System.Windows.Forms.Label
$labelGitHubUsername.Text = "GitHub Username:"
$labelGitHubUsername.Location = New-Object System.Drawing.Point(10, 20)
$form.Controls.Add($labelGitHubUsername)

$textBoxGitHubUsername = New-Object System.Windows.Forms.TextBox
$textBoxGitHubUsername.Location = New-Object System.Drawing.Point(150, 20)
$textBoxGitHubUsername.Size = New-Object System.Drawing.Size(620, 20)
$form.Controls.Add($textBoxGitHubUsername)

# Repository Name Field
$labelRepoName = New-Object System.Windows.Forms.Label
$labelRepoName.Text = "GitHub Repository:"
$labelRepoName.Location = New-Object System.Drawing.Point(10, 60)
$form.Controls.Add($labelRepoName)

$textBoxRepoName = New-Object System.Windows.Forms.TextBox
$textBoxRepoName.Location = New-Object System.Drawing.Point(150, 60)
$textBoxRepoName.Size = New-Object System.Drawing.Size(620, 20)
$textBoxRepoName.Text = $repoName
$form.Controls.Add($textBoxRepoName)

# Artifact Directory
$labelArtifactDir = New-Object System.Windows.Forms.Label
$labelArtifactDir.Text = "Artifact Directory:"
$labelArtifactDir.Location = New-Object System.Drawing.Point(10, 100)
$form.Controls.Add($labelArtifactDir)

$textBoxArtifactDir = New-Object System.Windows.Forms.TextBox
$textBoxArtifactDir.Location = New-Object System.Drawing.Point(150, 100)
$textBoxArtifactDir.Size = New-Object System.Drawing.Size(620, 20)
$textBoxArtifactDir.Text = $artifactDir
$form.Controls.Add($textBoxArtifactDir)

# Backup Directory
$labelBackupDir = New-Object System.Windows.Forms.Label
$labelBackupDir.Text = "Backup Directory:"
$labelBackupDir.Location = New-Object System.Drawing.Point(10, 140)
$form.Controls.Add($labelBackupDir)

$textBoxBackupDir = New-Object System.Windows.Forms.TextBox
$textBoxBackupDir.Location = New-Object System.Drawing.Point(150, 140)
$textBoxBackupDir.Size = New-Object System.Drawing.Size(620, 20)
$textBoxBackupDir.Text = $virtualDir
$form.Controls.Add($textBoxBackupDir)

# Run Button
$buttonRun = New-Object System.Windows.Forms.Button
$buttonRun.Text = "Run"
$buttonRun.Location = New-Object System.Drawing.Point(10, 200)
$buttonRun.Size = New-Object System.Drawing.Size(760, 30)
$form.Controls.Add($buttonRun)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 250)
$progressBar.Size = New-Object System.Drawing.Size(760, 20)
$form.Controls.Add($progressBar)

# Event Handler for Run Button
$buttonRun.Add_Click({
    try {
        $githubUsername = $textBoxGitHubUsername.Text
        if (-not $githubUsername) {
            Show-MessageBox "GitHub Username is required." "Error" "Error"
            return
        }
        $packageSourceUrl = "https://nuget.pkg.github.com/$githubUsername/index.json"
        Log-Message "Starting NuGet package generation process..."
        Prepare-Files
        Generate-GPOsTemplates
        Verify-VirtualDirectory
        $version = Generate-DynamicVersion
        Update-NuspecVersion -Version $version
        Pack-NuGetPackage
        Inspect-NuGetPackage
        Show-MessageBox "NuGet package generation completed successfully!" "Success" "Information"
    }
    catch {
        Log-Message "An error occurred: $_" -MessageType "ERROR"
        Show-MessageBox "An error occurred. Check the logs for details." "Error" "Error"
    }
})

# Show GUI Form
$form.ShowDialog()

# Function: Fetch-ExistingPackages
function Fetch-ExistingPackages {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )

    Log-Message "Fetching existing NuGet packages from GitHub Packages..."
    $apiUrl = "https://api.github.com/repos/$GitHubUsername/$RepositoryName/packages?package_type=nuget&per_page=100"
    $headers = @{
        "Authorization" = "Bearer $GitHubPAT"
        "Accept"        = "application/vnd.github+json"
        "User-Agent"    = "$GitHubUsername"
    }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get -ErrorAction Stop
        if ($response) {
            $existingPackages = $response | ForEach-Object { $_.name }
            Log-Message "Fetched Existing Packages:"
            $existingPackages | ForEach-Object { Log-Message $_ }
            return $existingPackages
        }
        else {
            Log-Message "No existing packages found." -MessageType "WARNING"
            return @()
        }
    }
    catch {
        Log-Message "Failed to fetch existing packages: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to fetch existing packages. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Publish-NuGetPackage
function Publish-NuGetPackage {
    param (
        [Parameter(Mandatory = $true)]
        [array]$ExistingPackages,

        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT,

        [Parameter(Mandatory = $true)]
        [string]$PackageSourceUrl
    )

    Log-Message "Publishing NuGet packages..."
    $packages = Get-ChildItem -Path $artifactDir -Filter "*.nupkg"
    if ($packages.Count -eq 0) {
        Log-Message "No NuGet packages found in $artifactDir to publish." -MessageType "WARNING"
        Show-MessageBox "No NuGet packages found in $artifactDir to publish." "Warning" "Warning"
        return
    }
    $progressBar.Maximum = $packages.Count
    $progressBar.Value = 0

    foreach ($package in $packages) {
        $packageName = $package.Name
        if ($ExistingPackages -contains $packageName) {
            Log-Message "Package '$packageName' already exists. Skipping..."
            $progressBar.PerformStep()
            continue
        }
        Log-Message "Pushing '$packageName' to GitHub Packages..."
        try {
            $pushOutput = & "$nugetExePath" push "$($package.FullName)" `
                -ApiKey "$GitHubPAT" `
                -Source "$PackageSourceUrl" `
                --skip-duplicate `
                -Verbosity detailed `
                -NonInteractive 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "nuget.exe push failed: $pushOutput"
            }
            Log-Message "Successfully pushed '$packageName'"
        }
        catch {
            Log-Message "Failed to push '$packageName': $_" -MessageType "ERROR"
        }
        finally {
            $progressBar.PerformStep()
        }
    }
}

# Function: Validate-UserInputs
function Validate-UserInputs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,

        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )

    if (-not $GitHubUsername) {
        Show-MessageBox "GitHub Username is required." "Error" "Error"
        throw "GitHub Username is missing."
    }

    if (-not $GitHubPAT) {
        Show-MessageBox "GitHub Personal Access Token (PAT) is required." "Error" "Error"
        throw "GitHub PAT is missing."
    }

    Log-Message "Validated user inputs successfully."
}

# Function: Main
function Main {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,

        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )

    try {
        Validate-UserInputs -GitHubUsername $GitHubUsername -GitHubPAT $GitHubPAT
        $packageSourceUrl = "https://nuget.pkg.github.com/$GitHubUsername/index.json"

        Log-Message "Starting the NuGet package generation and publishing process..."
        Prepare-Files
        Generate-GPOsTemplates
        Verify-VirtualDirectory
        $version = Generate-DynamicVersion
        Update-NuspecVersion -Version $version
        Pack-NuGetPackage
        Inspect-NuGetPackage

        $existingPackages = Fetch-ExistingPackages -GitHubUsername $GitHubUsername -RepositoryName $repoName -GitHubPAT $GitHubPAT
        Publish-NuGetPackage -ExistingPackages $existingPackages -GitHubPAT $GitHubPAT -PackageSourceUrl $packageSourceUrl

        Show-MessageBox "NuGet package generation and publishing completed successfully!" "Success" "Information"
    }
    catch {
        Log-Message "An error occurred during the process: $_" -MessageType "ERROR"
        Show-MessageBox "An error occurred during the process. Check logs for details." "Error" "Error"
        throw
    }
}

# Execution Triggered by GUI
$buttonRun.Add_Click({
    try {
        $GitHubUsername = $textBoxGitHubUsername.Text.Trim()
        $GitHubPAT = [System.Windows.Forms.MessageBox]::Show("Enter your GitHub PAT:", "GitHub PAT", [System.Windows.Forms.MessageBoxButtons]::OKCancel)
        if (-not $GitHubPAT) {
            Show-MessageBox "GitHub PAT is required to proceed." "Error" "Error"
            return
        }
        Main -GitHubUsername $GitHubUsername -GitHubPAT $GitHubPAT
    }
    catch {
        Show-MessageBox "An error occurred. Check logs for details." "Error" "Error"
    }
})

# Finalizing the Script
$form.ShowDialog()

# =========================
# END OF BLOCK 3 (500 LINES)
# =========================
# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 3
# =========================

# Helper Function: Display-Progress
function Display-Progress {
    param (
        [Parameter(Mandatory = $true)]
        [int]$CurrentStep,
        [Parameter(Mandatory = $true)]
        [int]$TotalSteps,
        [Parameter(Mandatory = $true)]
        [string]$StatusMessage
    )
    $progressPercentage = [math]::Round(($CurrentStep / $TotalSteps) * 100, 2)
    $progressBar.Value = $progressPercentage
    $textBoxResults.AppendText("$StatusMessage ($progressPercentage%)`r`n")
    Log-Message "$StatusMessage ($progressPercentage%)"
}

# Function: Generate-Report
function Generate-Report {
    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $reportPath = Join-Path $OutputDirectory "NuGetPackageReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    try {
        $reportContent = @"
NuGet Package Publishing Report
===============================
Generated On: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Details:
--------
GitHub Username: $GitHubUsername
GitHub Repository: $repoName
Package Source URL: $packageSourceUrl

Artifact Directory: $artifactDir
Backup Directory: $virtualDir

Actions Performed:
------------------
- Generated Dynamic Version: $version
- Updated .nuspec File with Version: $version
- Packaged NuGet Package
- Inspected Package Contents
- Published Package to GitHub Packages

End of Report
"@
        $reportContent | Set-Content -Path $reportPath -Force
        Log-Message "Report generated at $reportPath"
        Show-MessageBox "Report generated successfully: $reportPath" "Success" "Information"
    }
    catch {
        Log-Message "Failed to generate report: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate report. Check logs for details." "Error" "Error"
    }
}

# Function: Cleanup-TemporaryFiles
function Cleanup-TemporaryFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TemporaryDirectory
    )

    try {
        if (Test-Path $TemporaryDirectory) {
            Remove-Item -Path $TemporaryDirectory -Recurse -Force -ErrorAction Stop
            Log-Message "Temporary directory cleaned up: $TemporaryDirectory"
        }
        else {
            Log-Message "Temporary directory not found: $TemporaryDirectory" -MessageType "WARNING"
        }
    }
    catch {
        Log-Message "Failed to clean up temporary directory: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to clean up temporary files. Check logs for details." "Error" "Error"
    }
}

# GUI: Add Validation to Inputs
function Validate-GUIInputs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,
        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT,
        [Parameter(Mandatory = $true)]
        [string]$ArtifactDir,
        [Parameter(Mandatory = $true)]
        [string]$BackupDir
    )

    if (-not $GitHubUsername) {
        Show-MessageBox "GitHub Username cannot be empty." "Error" "Error"
        throw "GitHub Username is required."
    }

    if (-not $GitHubPAT) {
        Show-MessageBox "GitHub PAT cannot be empty." "Error" "Error"
        throw "GitHub PAT is required."
    }

    if (-not (Test-Path $ArtifactDir)) {
        Show-MessageBox "Artifact Directory does not exist: $ArtifactDir" "Error" "Error"
        throw "Invalid Artifact Directory."
    }

    if (-not (Test-Path $BackupDir)) {
        Show-MessageBox "Backup Directory does not exist: $BackupDir" "Error" "Error"
        throw "Invalid Backup Directory."
    }

    Log-Message "GUI inputs validated successfully."
}

# GUI Event: Finalize Publish Button
$buttonPublish.Add_Click({
    try {
        $GitHubUsername = $textBoxGitHubUsername.Text.Trim()
        $GitHubPAT = $textBoxGitHubPAT.Text.Trim()
        $ArtifactDir = $textBoxArtifactDir.Text.Trim()
        $BackupDir = $textBoxBackupDir.Text.Trim()

        Validate-GUIInputs -GitHubUsername $GitHubUsername -GitHubPAT $GitHubPAT -ArtifactDir $ArtifactDir -BackupDir $BackupDir

        $textBoxResults.AppendText("Starting NuGet package generation and publishing process...`r`n")
        Main -GitHubUsername $GitHubUsername -GitHubPAT $GitHubPAT

        $textBoxResults.AppendText("NuGet package generation and publishing completed successfully!`r`n")
        Log-Message "Process completed successfully."
        Generate-Report -OutputDirectory $ArtifactDir
    }
    catch {
        Log-Message "An error occurred during GUI execution: $_" -MessageType "ERROR"
        Show-MessageBox "An error occurred. Check logs for details." "Error" "Error"
    }
})

# Function: Initialize-Directories
function Initialize-Directories {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory
    )

    $artifactDir = Join-Path $BaseDirectory "artifacts"
    $backupDir = Join-Path $BaseDirectory "NuGet\NuGetPackageContent"

    try {
        Validate-Directory -DirPath $artifactDir
        Validate-Directory -DirPath $backupDir
        Log-Message "Initialized directories successfully."
    }
    catch {
        Log-Message "Failed to initialize directories: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to initialize directories. Check logs for details." "Error" "Error"
        throw
    }

    return @{
        ArtifactDir = $artifactDir
        BackupDir = $backupDir
    }
}

# Execution Entry Point
try {
    $BaseDirectory = Split-Path -Parent $scriptPath
    $Directories = Initialize-Directories -BaseDirectory $BaseDirectory
    $artifactDir = $Directories["ArtifactDir"]
    $backupDir = $Directories["BackupDir"]

    Log-Message "Script initialized with Base Directory: $BaseDirectory"
    Log-Message "Artifact Directory: $artifactDir"
    Log-Message "Backup Directory: $backupDir"

    # Launch GUI
    $form.ShowDialog()
}
catch {
    Log-Message "An unexpected error occurred: $_" -MessageType "ERROR"
    Show-MessageBox "An unexpected error occurred. Check logs for details." "Error" "Error"
    throw
}

# =========================
# END OF BLOCK 4 (500 LINES)
# =========================
# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 4
# =========================

# Function: Handle-GPOsTemplates
function Handle-GPOsTemplates {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory
    )

    try {
        if (Test-Path $SourceDirectory) {
            Log-Message "GPOs-Templates source directory found: $SourceDirectory"
            Validate-Directory -DirPath $TargetDirectory

            Copy-Item -Path $SourceDirectory -Destination $TargetDirectory -Recurse -Force -ErrorAction Stop
            Log-Message "Copied GPOs-Templates from $SourceDirectory to $TargetDirectory"
        }
        else {
            Log-Message "GPOs-Templates source directory missing: $SourceDirectory" -MessageType "WARNING"
            Show-MessageBox "GPOs-Templates source directory missing. Process will continue without it." "Warning" "Warning"
        }
    }
    catch {
        Log-Message "Failed to handle GPOs-Templates directory: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to handle GPOs-Templates directory. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Exclude-Folder
function Exclude-Folder {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FolderPath,
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory
    )

    try {
        $itemsToExclude = Get-ChildItem -Path $FolderPath -Recurse -Directory
        foreach ($item in $itemsToExclude) {
            $destinationPath = Join-Path $TargetDirectory $item.Name
            if (Test-Path $destinationPath) {
                Remove-Item -Path $destinationPath -Recurse -Force -ErrorAction Stop
                Log-Message "Excluded folder from target directory: $destinationPath"
            }
        }
    }
    catch {
        Log-Message "Failed to exclude folder: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to exclude folder. Check logs for details." "Error" "Error"
        throw
    }
}

# Update Main Function for NuGet Processing
function Main {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,
        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )

    try {
        Log-Message "Starting NuGet package generation process..."
        $version = Generate-DynamicVersion

        # Update .nuspec with the new version
        Verify-NuspecFile
        Update-NuspecVersion -Version $version

        # Handle Placeholder DLL generation
        Generate-PlaceholderDll

        # Handle GPOs-Templates specifically
        $gposSource = "C:\Windows-SysAdmin-ProSuite\SysAdmin-Tools\GroupPolicyObjects-Templates"
        $gposTarget = Join-Path $virtualDir "GPOs-Templates"
        Handle-GPOsTemplates -SourceDirectory $gposSource -TargetDirectory $gposTarget

        # Exclude GPOs-Templates from SysAdminToolsSet
        $sysAdminToolsSetPath = Join-Path $virtualDir "SysAdminToolsSet"
        Exclude-Folder -FolderPath $gposSource -TargetDirectory $sysAdminToolsSetPath

        # Prepare remaining files
        Prepare-Files

        # Verify virtual directory
        Verify-VirtualDirectory

        # Pack NuGet package
        Pack-NuGetPackage

        # Inspect package contents
        Inspect-NuGetPackage

        # Fetch existing packages
        $existingPackages = Fetch-ExistingPackages -GitHubUsername $GitHubUsername -RepositoryName $repoName -GitHubPAT $GitHubPAT

        # Publish package
        Publish-NuGetPackage -ExistingPackages $existingPackages -GitHubPAT $GitHubPAT -PackageSourceUrl $packageSourceUrl

        Log-Message "NuGet package generation and publishing completed successfully!"
        Show-MessageBox "NuGet package generation and publishing completed successfully!" "Success" "Information"
    }
    catch {
        Log-Message "An error occurred during the NuGet process: $_" -MessageType "ERROR"
        Show-MessageBox "An error occurred during the NuGet process. Check logs for details." "Error" "Error"
        throw
    }
}

# Event Handlers for GUI Buttons

# Refresh Button to Reload GUI Inputs
$buttonRefresh.Add_Click({
    try {
        Log-Message "Refreshing GUI inputs..."

        # Reset text boxes to default values
        $textBoxGitHubUsername.Text = ""
        $textBoxRepoName.Text = [System.IO.Path]::GetFileName($currentFolder)
        $textBoxPackageSource.Text = ""
        $textBoxArtifactDir.Text = Join-Path $currentFolder "artifact"
        $textBoxBackupDir.Text = Join-Path $currentFolder "NuGet\NuGetPackageContent"

        Log-Message "GUI inputs refreshed successfully."
        $textBoxResults.AppendText("GUI inputs refreshed successfully.`r`n")
    }
    catch {
        Log-Message "Failed to refresh GUI inputs: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to refresh GUI inputs. Check logs for details." "Error" "Error"
    }
})

# Clear Logs Button
$buttonClearLogs.Add_Click({
    try {
        Log-Message "Clearing log files..."
        if (Test-Path $logDir) {
            Get-ChildItem -Path $logDir -Filter "*.log" | Remove-Item -Force -ErrorAction Stop
            Log-Message "All log files cleared from $logDir"
            Show-MessageBox "All log files cleared successfully." "Success" "Information"
        }
        else {
            Log-Message "Log directory does not exist: $logDir" -MessageType "WARNING"
            Show-MessageBox "Log directory does not exist." "Warning" "Warning"
        }
    }
    catch {
        Log-Message "Failed to clear log files: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to clear log files. Check logs for details." "Error" "Error"
    }
})

# =========================
# END OF BLOCK 5 (500 LINES)
# =========================

# This block includes:
# - Handling for `GPOs-Templates` directory.
# - Excluding `GroupPolicyObjects-Templates` from `SysAdminToolsSet`.
# - Updated `Main` function logic for NuGet processing.
# - New GUI button handlers for refreshing inputs and clearing logs.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 5
# =========================

# Function: Clean-UpDirectories
function Clean-UpDirectories {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    try {
        if (Test-Path $DirectoryPath) {
            Get-ChildItem -Path $DirectoryPath -Recurse | Remove-Item -Recurse -Force -ErrorAction Stop
            Log-Message "Cleaned up directory: $DirectoryPath"
        }
        else {
            Log-Message "Directory does not exist: $DirectoryPath" -MessageType "WARNING"
        }
    }
    catch {
        Log-Message "Failed to clean up directory: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to clean up directory. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Initialize-Environment
function Initialize-Environment {
    try {
        Log-Message "Initializing environment for NuGet package creation..."

        # Ensure necessary directories exist
        Validate-Directory -DirPath $logDir
        Validate-Directory -DirPath $artifactDir
        Validate-Directory -DirPath $virtualDir

        # Clean up old contents
        Clean-UpDirectories -DirectoryPath $artifactDir
        Clean-UpDirectories -DirectoryPath $virtualDir

        Log-Message "Environment initialization completed successfully."
    }
    catch {
        Log-Message "Failed to initialize environment: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to initialize environment. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Display-Summary
function Display-Summary {
    try {
        Log-Message "Displaying summary of operations..."

        $summary = @"
Operation Summary:
===================
- GitHub Username: $($textBoxGitHubUsername.Text)
- Repository Name: $($textBoxRepoName.Text)
- Package Source URL: $($textBoxPackageSource.Text)
- Artifact Directory: $($textBoxArtifactDir.Text)
- Backup Directory: $($textBoxBackupDir.Text)

Logs saved to: $logDir
"@

        $textBoxResults.AppendText($summary)
        Log-Message "Summary displayed successfully."
    }
    catch {
        Log-Message "Failed to display summary: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to display summary. Check logs for details." "Error" "Error"
    }
}

# Updated GUI Components
# Add "Summary" Button
$buttonSummary = New-Object System.Windows.Forms.Button
$buttonSummary.Location = New-Object System.Drawing.Point(10, 520)
$buttonSummary.Size = New-Object System.Drawing.Size(760, 30)
$buttonSummary.Text = 'Display Operation Summary'
$form.Controls.Add($buttonSummary)

# Summary Button Click Event
$buttonSummary.Add_Click({
    try {
        Display-Summary
    }
    catch {
        Log-Message "Failed to execute Display-Summary: $_" -MessageType "ERROR"
    }
})

# Add "Initialize Environment" Button
$buttonInitialize = New-Object System.Windows.Forms.Button
$buttonInitialize.Location = New-Object System.Drawing.Point(10, 560)
$buttonInitialize.Size = New-Object System.Drawing.Size(760, 30)
$buttonInitialize.Text = 'Initialize Environment'
$form.Controls.Add($buttonInitialize)

# Initialize Environment Button Click Event
$buttonInitialize.Add_Click({
    try {
        Initialize-Environment
        Show-MessageBox "Environment initialized successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed to execute Initialize-Environment: $_" -MessageType "ERROR"
    }
})

# Add MenuStrip for Additional Options
$menuStrip = New-Object System.Windows.Forms.MenuStrip

# File Menu
$fileMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$fileMenu.Text = "File"
$menuStrip.Items.Add($fileMenu)

# Exit Option
$exitOption = New-Object System.Windows.Forms.ToolStripMenuItem
$exitOption.Text = "Exit"
$fileMenu.DropDownItems.Add($exitOption)

$exitOption.Add_Click({
    $form.Close()
})

# Help Menu
$helpMenu = New-Object System.Windows.Forms.ToolStripMenuItem
$helpMenu.Text = "Help"
$menuStrip.Items.Add($helpMenu)

# About Option
$aboutOption = New-Object System.Windows.Forms.ToolStripMenuItem
$aboutOption.Text = "About"
$helpMenu.DropDownItems.Add($aboutOption)

$aboutOption.Add_Click({
    Show-MessageBox "NuGet Package Publisher v1.0. Developed by BrazilianScriptGuy." "About" "Information"
})

# Attach MenuStrip to Form
$form.MainMenuStrip = $menuStrip
$form.Controls.Add($menuStrip)

# Enhanced Logging Functionality
function Log-Detailed {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [string]$FilePath = $logPath
    )
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] $Message"
        Add-Content -Path $FilePath -Value $logEntry -ErrorAction Stop
    }
    catch {
        Show-MessageBox "Failed to write to detailed log. Check permissions and try again." "Error" "Error"
        throw
    }
}

# Log Rotation (Keep Latest 5 Logs)
function Rotate-Logs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )
    try {
        $logFiles = Get-ChildItem -Path $DirectoryPath -Filter "*.log" | Sort-Object LastWriteTime -Descending
        if ($logFiles.Count -gt 5) {
            $filesToDelete = $logFiles | Select-Object -Skip 5
            $filesToDelete | ForEach-Object { Remove-Item -Path $_.FullName -Force }
            Log-Message "Rotated logs, keeping the latest 5 logs."
        }
    }
    catch {
        Log-Message "Failed to rotate logs: $_" -MessageType "ERROR"
        throw
    }
}

# Auto-Rotate Logs on Script Start
Rotate-Logs -DirectoryPath $logDir

# Display Enhanced Progress Bar
$progressBarEnhanced = New-Object System.Windows.Forms.ProgressBar
$progressBarEnhanced.Location = New-Object System.Drawing.Point(10, 600)
$progressBarEnhanced.Size = New-Object System.Drawing.Size(760, 20)
$progressBarEnhanced.Minimum = 0
$progressBarEnhanced.Maximum = 100
$progressBarEnhanced.Style = 'Continuous'
$form.Controls.Add($progressBarEnhanced)

# Update Progress Bar Method
function Update-ProgressBar {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Percentage
    )

    if ($Percentage -ge 0 -and $Percentage -le 100) {
        $progressBarEnhanced.Value = $Percentage
        Log-Message "Progress bar updated to $Percentage%."
    }
    else {
        Log-Message "Invalid progress percentage: $Percentage" -MessageType "WARNING"
    }
}

# =========================
# END OF BLOCK 6 (500 LINES)
# =========================

# This block includes:
# - Clean-UpDirectories and Initialize-Environment functions.
# - Added new GUI buttons for "Summary" and "Initialize Environment".
# - MenuStrip integration with File and Help options.
# - Enhanced logging functionality with log rotation.
# - Progress bar updates.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 6
# =========================

# Function: Generate-GPOsTemplates
function Generate-GPOsTemplates {
    try {
        $gpoPath = Join-Path $virtualDir "GPOs-Templates"

        if (-not (Test-Path $gpoPath)) {
            Log-Message "Creating GPOs-Templates directory..."

            # Create the GPOs-Templates directory
            New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null
            $placeholderFilePath = Join-Path $gpoPath "README.md"

            # Add placeholder content
            "This directory contains Group Policy Object Templates." | Out-File -FilePath $placeholderFilePath -Encoding UTF8 -Force
            Log-Message "Created GPOs-Templates directory and added placeholder README.md."
        }
        else {
            Log-Message "GPOs-Templates directory already exists."
        }
    }
    catch {
        Log-Message "Failed to generate GPOs-Templates: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate GPOs-Templates. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Exclude-DirectoryFromSet
function Exclude-DirectoryFromSet {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    try {
        if (Test-Path $DirectoryPath) {
            Remove-Item -Path $DirectoryPath -Recurse -Force -ErrorAction Stop
            Log-Message "Excluded directory from set: $DirectoryPath"
        }
        else {
            Log-Message "Directory to exclude not found: $DirectoryPath" -MessageType "WARNING"
        }
    }
    catch {
        Log-Message "Failed to exclude directory: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to exclude directory. Check logs for details." "Error" "Error"
        throw
    }
}

# Exclude GPOs-Templates from SysAdminToolSet
$sysAdminToolsPath = Join-Path $repoRoot "SysAdmin-Tools\GroupPolicyObjects-Templates"
Exclude-DirectoryFromSet -DirectoryPath $sysAdminToolsPath

# Function: Validate-PackageContents
function Validate-PackageContents {
    try {
        Log-Message "Validating package contents in $virtualDir..."

        $requiredDirectories = @(
            "GPOs-Templates",
            "ITSM-Templates-SVR",
            "ITSM-Templates-WKS",
            "SysAdminToolsSet"
        )

        foreach ($dir in $requiredDirectories) {
            $dirPath = Join-Path $virtualDir $dir
            if (-not (Test-Path $dirPath)) {
                Log-Message "Missing required directory: $dirPath" -MessageType "ERROR"
                Show-MessageBox "Missing required directory: $dirPath. Package validation failed." "Error" "Error"
                throw "Missing directory: $dir"
            }
            else {
                Log-Message "Validated directory exists: $dirPath"
            }
        }

        Log-Message "Package contents validated successfully."
    }
    catch {
        Log-Message "Failed to validate package contents: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to validate package contents. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Publish-PackageToGitHub
function Publish-PackageToGitHub {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT,

        [Parameter(Mandatory = $true)]
        [string]$PackageSourceUrl
    )

    try {
        Log-Message "Publishing package $PackagePath to GitHub Packages..."

        $pushOutput = & "$nugetExePath" push "$PackagePath" `
            -ApiKey "$GitHubPAT" `
            -Source "$PackageSourceUrl" `
            -NonInteractive 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "nuget.exe push failed: $pushOutput"
        }

        Log-Message "Package $PackagePath published successfully."
        Show-MessageBox "Package published successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed to publish package: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to publish package. Check logs for details." "Error" "Error"
        throw
    }
}

# Add a Button to Validate Package Contents
$buttonValidatePackage = New-Object System.Windows.Forms.Button
$buttonValidatePackage.Location = New-Object System.Drawing.Point(10, 600)
$buttonValidatePackage.Size = New-Object System.Drawing.Size(760, 30)
$buttonValidatePackage.Text = 'Validate Package Contents'
$form.Controls.Add($buttonValidatePackage)

# Validate Package Contents Button Click Event
$buttonValidatePackage.Add_Click({
    try {
        Validate-PackageContents
        Show-MessageBox "Package contents validated successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed to execute Validate-PackageContents: $_" -MessageType "ERROR"
    }
})

# Add a Button to Generate GPOs Templates
$buttonGenerateGPOs = New-Object System.Windows.Forms.Button
$buttonGenerateGPOs.Location = New-Object System.Drawing.Point(10, 640)
$buttonGenerateGPOs.Size = New-Object System.Drawing.Size(760, 30)
$buttonGenerateGPOs.Text = 'Generate GPOs Templates'
$form.Controls.Add($buttonGenerateGPOs)

# Generate GPOs Templates Button Click Event
$buttonGenerateGPOs.Add_Click({
    try {
        Generate-GPOsTemplates
        Show-MessageBox "GPOs Templates generated successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed to execute Generate-GPOsTemplates: $_" -MessageType "ERROR"
    }
})

# Add "Publish Package" Button
$buttonPublishPackage = New-Object System.Windows.Forms.Button
$buttonPublishPackage.Location = New-Object System.Drawing.Point(10, 680)
$buttonPublishPackage.Size = New-Object System.Drawing.Size(760, 30)
$buttonPublishPackage.Text = 'Publish Package to GitHub'
$form.Controls.Add($buttonPublishPackage)

# Publish Package Button Click Event
$buttonPublishPackage.Add_Click({
    try {
        $nupkgFile = Get-ChildItem -Path $artifactDir -Filter "*.nupkg" | Select-Object -First 1

        if (-not $nupkgFile) {
            Show-MessageBox "No .nupkg file found in artifact directory. Cannot publish package." "Error" "Error"
            Log-Message "No .nupkg file found in artifact directory." -MessageType "ERROR"
            return
        }

        Publish-PackageToGitHub -PackagePath $nupkgFile.FullName -GitHubPAT $textBoxGitHubUsername.Text -PackageSourceUrl $textBoxPackageSource.Text
    }
    catch {
        Log-Message "Failed to publish package: $_" -MessageType "ERROR"
    }
})

# Update Form Layout for New Buttons
$form.Height += 120
$form.Controls[$progressBarEnhanced].Location = New-Object System.Drawing.Point(10, 720)

# =========================
# END OF BLOCK 7 (500 LINES)
# =========================

# This block includes:
# - Generate-GPOsTemplates and Exclude-DirectoryFromSet functions.
# - Added validation for package contents.
# - Button implementations for "Validate Package", "Generate GPOs", and "Publish Package".
# - Enhanced error handling and directory exclusion logic.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 7
# =========================

# Function: Generate-LicenseFile
function Generate-LicenseFile {
    try {
        $licensePath = Join-Path $virtualDir "LICENSE"
        if (-not (Test-Path $licensePath)) {
            Log-Message "Creating LICENSE file in $virtualDir..."

            $licenseContent = @"
MIT License

Copyright (c) $(Get-Date -Format "yyyy") BrazilianScriptGuy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
            $licenseContent | Out-File -FilePath $licensePath -Encoding UTF8 -Force
            Log-Message "LICENSE file created at $licensePath."
        }
        else {
            Log-Message "LICENSE file already exists at $licensePath."
        }
    }
    catch {
        Log-Message "Failed to generate LICENSE file: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate LICENSE file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Generate-ReadmeFile
function Generate-ReadmeFile {
    try {
        $readmePath = Join-Path $virtualDir "README.md"
        if (-not (Test-Path $readmePath)) {
            Log-Message "Creating README.md file in $virtualDir..."

            $readmeContent = @"
# Windows-SysAdmin-ProSuite

A comprehensive suite of PowerShell scripts and templates for system administration.

## Features
- Tools for Active Directory management
- ITSM templates for server and workstation compliance
- SysAdmin tools for Blue Team and forensic tasks
- Event log analysis and custom configurations

## Installation
1. Download the NuGet package.
2. Extract the contents to your desired location.
3. Use the included PowerShell scripts and templates as needed.

## License
This project is licensed under the MIT License. See LICENSE for details.

"@
            $readmeContent | Out-File -FilePath $readmePath -Encoding UTF8 -Force
            Log-Message "README.md file created at $readmePath."
        }
        else {
            Log-Message "README.md file already exists at $readmePath."
        }
    }
    catch {
        Log-Message "Failed to generate README.md file: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate README.md file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Finalize-BuildProcess
function Finalize-BuildProcess {
    try {
        Log-Message "Finalizing build process..."

        Generate-LicenseFile
        Generate-ReadmeFile
        Validate-PackageContents

        Log-Message "Build process finalized successfully."
        Show-MessageBox "Build process finalized successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed during build process finalization: $_" -MessageType "ERROR"
        Show-MessageBox "Build process finalization failed. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Export-Logs
function Export-Logs {
    try {
        $exportPath = Join-Path $logDir "NuGet_Logs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Copy-Item -Path $logPath -Destination $exportPath -Force -ErrorAction Stop

        Log-Message "Logs exported to $exportPath."
        Show-MessageBox "Logs exported successfully to $exportPath." "Success" "Information"
    }
    catch {
        Log-Message "Failed to export logs: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to export logs. Check logs for details." "Error" "Error"
        throw
    }
}

# Add a Button to Finalize Build Process
$buttonFinalizeBuild = New-Object System.Windows.Forms.Button
$buttonFinalizeBuild.Location = New-Object System.Drawing.Point(10, 720)
$buttonFinalizeBuild.Size = New-Object System.Drawing.Size(760, 30)
$buttonFinalizeBuild.Text = 'Finalize Build Process'
$form.Controls.Add($buttonFinalizeBuild)

# Finalize Build Process Button Click Event
$buttonFinalizeBuild.Add_Click({
    try {
        Finalize-BuildProcess
    }
    catch {
        Log-Message "Failed to finalize build process: $_" -MessageType "ERROR"
    }
})

# Add a Button to Export Logs
$buttonExportLogs = New-Object System.Windows.Forms.Button
$buttonExportLogs.Location = New-Object System.Drawing.Point(10, 760)
$buttonExportLogs.Size = New-Object System.Drawing.Size(760, 30)
$buttonExportLogs.Text = 'Export Logs'
$form.Controls.Add($buttonExportLogs)

# Export Logs Button Click Event
$buttonExportLogs.Add_Click({
    try {
        Export-Logs
    }
    catch {
        Log-Message "Failed to export logs: $_" -MessageType "ERROR"
    }
})

# Update Form Layout for New Buttons
$form.Height += 80
$form.Controls[$progressBarEnhanced].Location = New-Object System.Drawing.Point(10, 800)

# =========================
# END OF BLOCK 8 (500 LINES)
# =========================

# This block includes:
# - Functions to generate LICENSE and README.md files.
# - Finalize build process, including validation and file generation.
# - Export logs functionality.
# - UI Buttons for Finalize Build and Export Logs.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 8
# =========================

# Function: Validate-PackageContents
function Validate-PackageContents {
    try {
        Log-Message "Validating package contents..."

        $requiredPaths = @(
            Join-Path $virtualDir "GPOs-Templates",
            Join-Path $virtualDir "LICENSE",
            Join-Path $virtualDir "README.md",
            Join-Path $virtualDir "lib\net7.0\PlaceholderDll.dll"
        )

        foreach ($path in $requiredPaths) {
            if (-not (Test-Path $path)) {
                throw "Required file or directory missing: $path"
            }
            Log-Message "Validated existence of $path"
        }

        Log-Message "All required package contents are present."
    }
    catch {
        Log-Message "Validation of package contents failed: $_" -MessageType "ERROR"
        Show-MessageBox "Validation failed. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Prepare-PackageForPublishing
function Prepare-PackageForPublishing {
    try {
        Log-Message "Preparing package for publishing..."

        # Ensure all required directories are present
        Validate-Directory -DirPath $artifactDir
        Validate-Directory -DirPath $virtualDir

        # Ensure required files are generated
        Generate-LicenseFile
        Generate-ReadmeFile

        # Verify directory contents
        Validate-PackageContents

        Log-Message "Package preparation complete."
    }
    catch {
        Log-Message "Failed during package preparation: $_" -MessageType "ERROR"
        Show-MessageBox "Package preparation failed. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Display-PackageSummary
function Display-PackageSummary {
    try {
        Log-Message "Displaying package summary..."

        $summary = @"
Package Summary:
- Artifact Directory: $artifactDir
- Virtual Directory: $virtualDir
- Package Source URL: $packageSourceUrl
- Placeholder DLL: $(Test-Path $placeholderDllPath)

Contents:
- GPOs-Templates: $(Test-Path (Join-Path $virtualDir "GPOs-Templates"))
- LICENSE: $(Test-Path (Join-Path $virtualDir "LICENSE"))
- README.md: $(Test-Path (Join-Path $virtualDir "README.md"))
"@

        $textBoxResults.AppendText($summary)
        Log-Message "Package summary displayed."
    }
    catch {
        Log-Message "Failed to display package summary: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to display package summary. Check logs for details." "Error" "Error"
        throw
    }
}

# Add a Button to Display Package Summary
$buttonPackageSummary = New-Object System.Windows.Forms.Button
$buttonPackageSummary.Location = New-Object System.Drawing.Point(10, 800)
$buttonPackageSummary.Size = New-Object System.Drawing.Size(760, 30)
$buttonPackageSummary.Text = 'Display Package Summary'
$form.Controls.Add($buttonPackageSummary)

# Package Summary Button Click Event
$buttonPackageSummary.Add_Click({
    try {
        Display-PackageSummary
    }
    catch {
        Log-Message "Failed to display package summary: $_" -MessageType "ERROR"
    }
})

# Function: Publish-Package
function Publish-Package {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubUsername,
        [Parameter(Mandatory = $true)]
        [string]$RepositoryName,
        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )
    try {
        Log-Message "Publishing package to GitHub Packages..."

        Prepare-PackageForPublishing

        # Generate the dynamic version and update nuspec
        $version = Generate-DynamicVersion
        Update-NuspecVersion -Version $version

        # Pack the NuGet package
        Pack-NuGetPackage

        # Fetch existing packages to avoid duplication
        $existingPackages = Fetch-ExistingPackages -GitHubUsername $GitHubUsername -RepositoryName $RepositoryName -GitHubPAT $GitHubPAT

        # Publish the package
        Publish-NuGetPackage -ExistingPackages $existingPackages -GitHubPAT $GitHubPAT -PackageSourceUrl $packageSourceUrl

        Log-Message "Package published successfully."
        Show-MessageBox "Package published successfully." "Success" "Information"
    }
    catch {
        Log-Message "Failed to publish package: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to publish package. Check logs for details." "Error" "Error"
        throw
    }
}

# Add a Button to Publish Package
$buttonPublishPackage = New-Object System.Windows.Forms.Button
$buttonPublishPackage.Location = New-Object System.Drawing.Point(10, 840)
$buttonPublishPackage.Size = New-Object System.Drawing.Size(760, 30)
$buttonPublishPackage.Text = 'Publish Package'
$form.Controls.Add($buttonPublishPackage)

# Publish Package Button Click Event
$buttonPublishPackage.Add_Click({
    try {
        $GitHubUsername = $textBoxGitHubUsername.Text.Trim()
        $RepositoryName = $textBoxRepoName.Text.Trim()
        $GitHubPAT = $textBoxPAT.Text.Trim()

        if (-not $GitHubUsername -or -not $RepositoryName -or -not $GitHubPAT) {
            Show-MessageBox "Please fill in all required fields: GitHub Username, Repository Name, and Personal Access Token." "Error" "Error"
            return
        }

        Publish-Package -GitHubUsername $GitHubUsername -RepositoryName $RepositoryName -GitHubPAT $GitHubPAT
    }
    catch {
        Log-Message "Failed to publish package: $_" -MessageType "ERROR"
    }
})

# Update Form Layout for New Buttons
$form.Height += 80
$form.Controls[$progressBarEnhanced].Location = New-Object System.Drawing.Point(10, 880)

# =========================
# END OF BLOCK 9 (500 LINES)
# =========================

# This block includes:
# - Validation of package contents.
# - Preparation of the package for publishing.
# - Displaying package summary in the GUI.
# - Button to publish the package with proper validation and error handling.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 9
# =========================

# Function: Add-License-File
function Generate-LicenseFile {
    try {
        Log-Message "Ensuring LICENSE file exists in virtual directory..."

        $licensePath = Join-Path $virtualDir "LICENSE"
        $sourceLicensePath = Join-Path $repoRoot "LICENSE"

        if (-not (Test-Path $sourceLicensePath)) {
            throw "LICENSE file not found in repository root at $sourceLicensePath."
        }

        Copy-Item -Path $sourceLicensePath -Destination $licensePath -Force
        Log-Message "LICENSE file copied to virtual directory."
    }
    catch {
        Log-Message "Failed to generate LICENSE file: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate LICENSE file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Generate-ReadmeFile
function Generate-ReadmeFile {
    try {
        Log-Message "Ensuring README.md file exists in virtual directory..."

        $readmePath = Join-Path $virtualDir "README.md"
        $sourceReadmePath = Join-Path $docDir "README.md"

        if (-not (Test-Path $sourceReadmePath)) {
            throw "README.md file not found in documentation directory at $sourceReadmePath."
        }

        Copy-Item -Path $sourceReadmePath -Destination $readmePath -Force
        Log-Message "README.md file copied to virtual directory."
    }
    catch {
        Log-Message "Failed to generate README.md file: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate README.md file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Ensure-GPOsTemplates
function Ensure-GPOsTemplates {
    try {
        Log-Message "Ensuring GPOs-Templates directory exists in virtual directory..."

        $gpoTemplatesPath = Join-Path $virtualDir "GPOs-Templates"
        $sourceGpoTemplatesPath = Join-Path $repoRoot "SysAdmin-Tools\GroupPolicyObjects-Templates"

        if (-not (Test-Path $sourceGpoTemplatesPath)) {
            throw "GPOs-Templates directory not found in source path at $sourceGpoTemplatesPath."
        }

        Copy-Item -Path $sourceGpoTemplatesPath -Destination $gpoTemplatesPath -Recurse -Force
        Log-Message "GPOs-Templates directory copied to virtual directory."
    }
    catch {
        Log-Message "Failed to ensure GPOs-Templates directory: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to ensure GPOs-Templates directory. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Generate-PackageStructure
function Generate-PackageStructure {
    try {
        Log-Message "Generating package structure..."

        # Ensure all required directories and files
        Validate-Directory -DirPath $virtualDir
        Generate-LicenseFile
        Generate-ReadmeFile
        Ensure-GPOsTemplates

        Log-Message "Package structure generated successfully."
    }
    catch {
        Log-Message "Failed to generate package structure: $_" -MessageType "ERROR"
        Show-MessageBox "Failed to generate package structure. Check logs for details." "Error" "Error"
        throw
    }
}

# GUI Button for Generating Package Structure
$buttonGenerateStructure = New-Object System.Windows.Forms.Button
$buttonGenerateStructure.Location = New-Object System.Drawing.Point(10, 920)
$buttonGenerateStructure.Size = New-Object System.Drawing.Size(760, 30)
$buttonGenerateStructure.Text = 'Generate Package Structure'
$form.Controls.Add($buttonGenerateStructure)

# Generate Package Structure Button Click Event
$buttonGenerateStructure.Add_Click({
    try {
        Generate-PackageStructure
        Show-MessageBox "Package structure generated successfully." "Success" "Information"
    }
    catch {
        Log-Message "Error during package structure generation: $_" -MessageType "ERROR"
    }
})

# Function: Clean-Up
function Clean-Up {
    try {
        Log-Message "Performing cleanup tasks..."

        $tempPaths = @(
            Join-Path $artifactDir "PackageContents_*",
            Join-Path $virtualDir "temp_*"
        )

        foreach ($tempPath in $tempPaths) {
            if (Test-Path $tempPath) {
                Remove-Item -Path $tempPath -Recurse -Force -ErrorAction Stop
                Log-Message "Removed temporary path: $tempPath"
            }
        }

        Log-Message "Cleanup tasks completed successfully."
    }
    catch {
        Log-Message "Failed during cleanup tasks: $_" -MessageType "WARNING"
        Show-MessageBox "Cleanup encountered issues. Check logs for details." "Warning" "Warning"
    }
}

# Add a Cleanup Button to GUI
$buttonCleanup = New-Object System.Windows.Forms.Button
$buttonCleanup.Location = New-Object System.Drawing.Point(10, 960)
$buttonCleanup.Size = New-Object System.Drawing.Size(760, 30)
$buttonCleanup.Text = 'Perform Cleanup'
$form.Controls.Add($buttonCleanup)

# Cleanup Button Click Event
$buttonCleanup.Add_Click({
    try {
        Clean-Up
        Show-MessageBox "Cleanup completed successfully." "Success" "Information"
    }
    catch {
        Log-Message "Cleanup error: $_" -MessageType "ERROR"
    }
})

# Final Adjustments to Form Layout
$form.Height += 80

# Show the GUI Form
$form.ShowDialog()

# =========================
# END OF BLOCK 10 (500 LINES)
# =========================

# This block includes:
# - Functions for generating the LICENSE, README.md, and GPOs-Templates directories.
# - Added buttons to the GUI for generating the package structure and performing cleanup.
# - Cleanup routine to remove temporary files or directories.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 10
# =========================

# Function: Verify-PackageIntegrity
function Verify-PackageIntegrity {
    try {
        Log-Message "Verifying integrity of generated NuGet package..."

        $nupkgFile = Get-ChildItem -Path $artifactDir -Filter "*.nupkg" | Select-Object -First 1
        if (-not $nupkgFile) {
            throw "No .nupkg file found in artifact directory at $artifactDir."
        }

        $extractDir = Join-Path $artifactDir "PackageContents_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Validate-Directory -DirPath $extractDir

        Expand-Archive -Path $nupkgFile.FullName -DestinationPath $extractDir -Force
        Log-Message "NuGet package contents extracted to $extractDir."

        $requiredPaths = @(
            Join-Path $extractDir "content\GPOs-Templates",
            Join-Path $extractDir "content\LICENSE",
            Join-Path $extractDir "content\README.md",
            Join-Path $extractDir "lib\net7.0\PlaceholderDll.dll"
        )

        foreach ($requiredPath in $requiredPaths) {
            if (-not (Test-Path $requiredPath)) {
                throw "Missing required package content: $requiredPath."
            }
        }

        Log-Message "NuGet package integrity verified successfully."
        Show-MessageBox "NuGet package integrity verified successfully." "Success" "Information"
    }
    catch {
        Log-Message "Package integrity verification failed: $_" -MessageType "ERROR"
        Show-MessageBox "Package integrity verification failed. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Publish-Package
function Publish-Package {
    param (
        [Parameter(Mandatory = $true)]
        [string]$GitHubPAT
    )

    try {
        Log-Message "Starting NuGet package publishing process..."

        $existingPackages = Fetch-ExistingPackages -GitHubUsername $textBoxGitHubUsername.Text.Trim() `
                                                   -RepositoryName $textBoxRepoName.Text.Trim() `
                                                   -GitHubPAT $GitHubPAT

        Publish-NuGetPackage -ExistingPackages $existingPackages `
                             -GitHubPAT $GitHubPAT `
                             -PackageSourceUrl $textBoxPackageSource.Text.Trim()

        Log-Message "NuGet package publishing completed successfully."
        Show-MessageBox "NuGet package published successfully." "Success" "Information"
    }
    catch {
        Log-Message "Error during package publishing: $_" -MessageType "ERROR"
        Show-MessageBox "Error during package publishing. Check logs for details." "Error" "Error"
        throw
    }
}

# Add Verify Integrity Button to GUI
$buttonVerifyIntegrity = New-Object System.Windows.Forms.Button
$buttonVerifyIntegrity.Location = New-Object System.Drawing.Point(10, 1000)
$buttonVerifyIntegrity.Size = New-Object System.Drawing.Size(760, 30)
$buttonVerifyIntegrity.Text = 'Verify Package Integrity'
$form.Controls.Add($buttonVerifyIntegrity)

# Verify Integrity Button Click Event
$buttonVerifyIntegrity.Add_Click({
    try {
        Verify-PackageIntegrity
    }
    catch {
        Log-Message "Integrity verification error: $_" -MessageType "ERROR"
    }
})

# Add Publish Button to GUI
$buttonPublish = New-Object System.Windows.Forms.Button
$buttonPublish.Location = New-Object System.Drawing.Point(10, 1040)
$buttonPublish.Size = New-Object System.Drawing.Size(760, 30)
$buttonPublish.Text = 'Publish NuGet Package'
$form.Controls.Add($buttonPublish)

# Publish Button Click Event
$buttonPublish.Add_Click({
    try {
        $githubPAT = $textBoxPAT.Text.Trim()
        if (-not $githubPAT) {
            Show-MessageBox "Please enter your GitHub PAT (Personal Access Token)." "Error" "Error"
            Log-Message "GitHub PAT not provided." -MessageType "ERROR"
            return
        }

        Publish-Package -GitHubPAT $githubPAT
    }
    catch {
        Log-Message "Publishing error: $_" -MessageType "ERROR"
    }
})

# Function: Validate-Inputs
function Validate-Inputs {
    try {
        if (-not $textBoxGitHubUsername.Text.Trim()) {
            throw "GitHub Username is missing."
        }
        if (-not $textBoxRepoName.Text.Trim()) {
            throw "GitHub Repository Name is missing."
        }
        if (-not $textBoxPAT.Text.Trim()) {
            throw "GitHub Personal Access Token (PAT) is missing."
        }

        Log-Message "Input validation completed successfully."
    }
    catch {
        Log-Message "Input validation error: $_" -MessageType "ERROR"
        Show-MessageBox "Input validation error: $_. Please check the inputs." "Error" "Error"
        throw
    }
}

# Function: Initialize-Script
function Initialize-Script {
    try {
        Log-Message "Initializing script..."

        Validate-Inputs

        # Perform initial setup and validation
        Generate-PackageStructure
        Verify-PackageIntegrity

        Log-Message "Script initialization completed successfully."
    }
    catch {
        Log-Message "Script initialization error: $_" -MessageType "ERROR"
        Show-MessageBox "Script initialization failed. Check logs for details." "Error" "Error"
        throw
    }
}

# Add Initialize Button to GUI
$buttonInitialize = New-Object System.Windows.Forms.Button
$buttonInitialize.Location = New-Object System.Drawing.Point(10, 1080)
$buttonInitialize.Size = New-Object System.Drawing.Size(760, 30)
$buttonInitialize.Text = 'Initialize Script'
$form.Controls.Add($buttonInitialize)

# Initialize Button Click Event
$buttonInitialize.Add_Click({
    try {
        Initialize-Script
    }
    catch {
        Log-Message "Initialization error: $_" -MessageType "ERROR"
    }
})

# Final Adjustments for Extended Form Layout
$form.Height += 160

# Show the Updated GUI Form
$form.ShowDialog()

# =========================
# END OF BLOCK 11 (500 LINES)
# =========================

# This block includes:
# - Functions for verifying package integrity and publishing the package.
# - Buttons for Verify Package Integrity, Publish NuGet Package, and Initialize Script.
# - Extended form height for additional buttons.

# =========================
# PowerShell Script to Build and Publish NuGet Package
# Continuation from Block 11
# =========================

# Function: Generate-DynamicNuspec
function Generate-DynamicNuspec {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    try {
        Log-Message "Generating dynamic .nuspec file with version: $Version"

        $nuspecTemplate = @"
<?xml version="1.0"?>
<package>
  <metadata>
    <id>Windows-SysAdmin-ProSuite</id>
    <version>$Version</version>
    <authors>BrazilianScriptGuy</authors>
    <owners>BrazilianScriptGuy</owners>
    <licenseUrl>https://opensource.org/licenses/MIT</licenseUrl>
    <projectUrl>https://github.com/brazilianscriptguy</projectUrl>
    <iconUrl>https://raw.githubusercontent.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/main/icon.png</iconUrl>
    <description>A comprehensive suite of PowerShell scripts and templates for system administration.</description>
    <releaseNotes>Initial release of Windows-SysAdmin-ProSuite. Includes tools for Blue Team, ITSM, Active Directory, Event Logs analysis, and more.</releaseNotes>
    <tags>active-directory sysadmin siem itsm workstations audit-log admin-tools customize blueteam active-directory-domain-services evtx-analysis sysadmin-tasks sysadmin-tool sysadmin-scripts eventlogs windows-server-2019 organizational-units forensics-tools itsm-solutions</tags>
  </metadata>
  <files>
    <file src="NuGetPackageContent/GPOs-Templates/**/*" target="content/GPOs-Templates" />
    <file src="NuGetPackageContent/ITSM-Templates-SVR/**/*" target="content/ITSM-Templates-SVR" />
    <file src="NuGetPackageContent/ITSM-Templates-WKS/**/*" target="content/ITSM-Templates-WKS" />
    <file src="NuGetPackageContent/SysAdminToolsSet/**/*" target="content/SysAdminToolsSet" />
    <file src="NuGetPackageContent/LICENSE" target="content" />
    <file src="NuGetPackageContent/README.md" target="content" />
    <file src="NuGetPackageContent/lib/net7.0/PlaceholderDll.dll" target="lib/net7.0" />
  </files>
</package>
"@

        $nuspecPath = Join-Path $virtualDir "nuget.package.nuspec"
        $nuspecTemplate | Set-Content -Path $nuspecPath -Encoding UTF8 -ErrorAction Stop
        Log-Message ".nuspec file generated at $nuspecPath"
    }
    catch {
        Log-Message "Error generating .nuspec file: $_" -MessageType "ERROR"
        Show-MessageBox "Error generating .nuspec file. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Clean-ArtifactDirectory
function Clean-ArtifactDirectory {
    try {
        Log-Message "Cleaning up artifact directory..."

        if (Test-Path $artifactDir) {
            Remove-Item -Path $artifactDir -Recurse -Force -ErrorAction Stop
            Log-Message "Artifact directory cleaned: $artifactDir"
        }

        Validate-Directory -DirPath $artifactDir
        Log-Message "Artifact directory ready for new build."
    }
    catch {
        Log-Message "Error cleaning artifact directory: $_" -MessageType "ERROR"
        Show-MessageBox "Error cleaning artifact directory. Check logs for details." "Error" "Error"
        throw
    }
}

# Function: Build-Package
function Build-Package {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    try {
        Log-Message "Starting package build process..."

        Generate-DynamicNuspec -Version $Version
        Pack-NuGetPackage
        Verify-PackageIntegrity

        Log-Message "Package build process completed successfully."
        Show-MessageBox "Package build completed successfully." "Success" "Information"
    }
    catch {
        Log-Message "Error during package build: $_" -MessageType "ERROR"
        Show-MessageBox "Error during package build. Check logs for details." "Error" "Error"
        throw
    }
}

# Add Build Package Button to GUI
$buttonBuildPackage = New-Object System.Windows.Forms.Button
$buttonBuildPackage.Location = New-Object System.Drawing.Point(10, 1120)
$buttonBuildPackage.Size = New-Object System.Drawing.Size(760, 30)
$buttonBuildPackage.Text = 'Build Package'
$form.Controls.Add($buttonBuildPackage)

# Build Package Button Click Event
$buttonBuildPackage.Add_Click({
    try {
        $version = Generate-DynamicVersion
        Build-Package -Version $version
    }
    catch {
        Log-Message "Build package error: $_" -MessageType "ERROR"
    }
})

# Function: Deploy-GPOsTemplates
function Deploy-GPOsTemplates {
    try {
        Log-Message "Deploying GPOs Templates..."

        $gposTemplatesSource = "C:\Windows-SysAdmin-ProSuite\SysAdmin-Tools\GroupPolicyObjects-Templates"
        $gposTemplatesTarget = Join-Path $virtualDir "GPOs-Templates"

        if (-not (Test-Path $gposTemplatesSource)) {
            throw "GPOs Templates source directory not found at $gposTemplatesSource."
        }

        Validate-Directory -DirPath $gposTemplatesTarget

        Copy-Item -Path "$gposTemplatesSource\*" -Destination $gposTemplatesTarget -Recurse -Force -ErrorAction Stop
        Log-Message "GPOs Templates deployed to $gposTemplatesTarget"
    }
    catch {
        Log-Message "Error deploying GPOs Templates: $_" -MessageType "ERROR"
        Show-MessageBox "Error deploying GPOs Templates. Check logs for details." "Error" "Error"
        throw
    }
}

# Add Deploy GPOs Templates Button to GUI
$buttonDeployGPOsTemplates = New-Object System.Windows.Forms.Button
$buttonDeployGPOsTemplates.Location = New-Object System.Drawing.Point(10, 1160)
$buttonDeployGPOsTemplates.Size = New-Object System.Drawing.Size(760, 30)
$buttonDeployGPOsTemplates.Text = 'Deploy GPOs Templates'
$form.Controls.Add($buttonDeployGPOsTemplates)

# Deploy GPOs Templates Button Click Event
$buttonDeployGPOsTemplates.Add_Click({
    try {
        Deploy-GPOsTemplates
    }
    catch {
        Log-Message "Deploy GPOs Templates error: $_" -MessageType "ERROR"
    }
})

# Adjust Form Height for New Buttons
$form.Height += 120

# Show the Updated GUI Form
$form.ShowDialog()

# =========================
# END OF BLOCK 12 (500 LINES)
# =========================

# This block includes:
# - Functions for generating .nuspec dynamically, cleaning artifact directory, and building the package.
# - Function for deploying GPOs Templates.
# - Buttons for Build Package and Deploy GPOs Templates with event handling.
# - Adjusted form height for new buttons.
