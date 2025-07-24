<#
.SYNOPSIS
    Generic NuGet Package Builder & Publisher

.DESCRIPTION
    A PowerShell script with a GUI to prepare, build, validate, and publish a NuGet package to GitHub Packages.
    Supports any GitHub repository and directory structure, with configurable package metadata and file inclusion.

.AUTHOR
    BrazilianScriptGuy

.VERSION
    2.8 - July 17, 2025

.REQUIREMENTS
    - PowerShell 5.1+ (Windows) or PowerShell Core 7+ (cross-platform)
    - nuget.exe in PATH or script directory
    - System.Windows.Forms, System.Drawing (Windows only for GUI)
    - GitHub PAT with package:write scope
#>

param (
    [switch]$ShowConsole = $false,
    [string]$ConfigPath = ""
)

#region --- Hide Console (Optional) ---
if (-not $ShowConsole -and $PSVersionTable.Platform -ne "Unix") {
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
}
#endregion

#region --- Assemblies ---
if ($PSVersionTable.Platform -ne "Unix") {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
#endregion

#region --- Initialization & Logging ---
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = if ($ScriptPath) { Split-Path -Parent $ScriptPath } else { [Environment]::CurrentDirectory }
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "NuGetPublisher\Logs"
$LogPath = Join-Path -Path $LogDir -ChildPath "NuGetPublisher-$Timestamp.log"
$global:LogLevel = "INFO"
$NuGetExePath = $null

# Logging function
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    $levels = @{ "ERROR" = 1; "WARNING" = 2; "INFO" = 3; "DEBUG" = 4 }
    if ($levels[$Level] -le $levels[$global:LogLevel]) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogPath -Value "[$timestamp] [$Level] $Message" -ErrorAction Stop
    }
}

# Error handling function
function Handle-Error {
    param ([string]$ErrorMessage)
    Log-Message -Message $ErrorMessage -Level "ERROR"
    if ($PSVersionTable.Platform -ne "Unix") {
        [System.Windows.Forms.MessageBox]::Show($ErrorMessage, "Error", "OK", "Error") | Out-Null
    } else {
        Write-Error $ErrorMessage
    }
    throw $ErrorMessage
}

# Check for nuget.exe in PATH or script directory
if (Get-Command "nuget.exe" -ErrorAction SilentlyContinue) {
    $NuGetExePath = "nuget.exe"
} elseif (Test-Path (Join-Path $ScriptDir "nuget.exe")) {
    $NuGetExePath = Join-Path $ScriptDir "nuget.exe"
    Log-Message "Found nuget.exe in script directory: $NuGetExePath"
} else {
    Handle-Error "nuget.exe not found in PATH or script directory. Please download from https://www.nuget.org/downloads and place it in $ScriptDir or add to PATH."
}

# Default configuration
$Config = @{
    PackageId = "MyNuGetPackage"
    GitHubUsername = ""
    RepositoryName = ""
    SourceDirs = @("Scripts", "Templates")
    ExcludeDirs = @()
    TargetFramework = "net7.0"
    Tags = "powershell nuget"
    Description = "A generic NuGet package"
}

# Load configuration from file
$defaultConfigPath = Join-Path -Path $ScriptDir -ChildPath "config.json"
if (-not $ConfigPath -and (Test-Path $defaultConfigPath)) {
    $ConfigPath = $defaultConfigPath
}
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
        Log-Message "Loaded configuration from $ConfigPath"
    } catch {
        Write-Warning "Failed to load config file: $_"
    }
}

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Log-Message "=== Launching NuGet Package Publisher ==="
#endregion

#region --- Core Functions ---
function Validate-Directory {
    param ([string]$DirPath)
    try {
        if (-not (Test-Path $DirPath)) {
            New-Item -Path $DirPath -ItemType Directory -Force | Out-Null
            Log-Message "Created directory: $DirPath"
        }
    } catch {
        Handle-Error "Failed to create directory: ${DirPath}: $_"
    }
}

function Generate-File {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $false)]
        [string]$SourcePath
    )
    try {
        if ($FilePath -match '[<>:"|?*]') {
            Handle-Error "Invalid characters in file path: ${FilePath}"
        }
        if ($SourcePath -and (Test-Path $SourcePath)) {
            Copy-Item -Path $SourcePath -Destination $FilePath -Force -ErrorAction Stop
            Log-Message "Copied file from ${SourcePath} to ${FilePath}"
        } else {
            $Content | Out-File -FilePath $FilePath -Encoding UTF8 -Force -ErrorAction Stop
            Log-Message "Created file at ${FilePath}"
        }
    } catch {
        Handle-Error "Failed to generate file ${FilePath}: $_"
    }
}

function Prepare-Files {
    param (
        [string]$RootDir,
        [array]$SourceDirs,
        [array]$ExcludeDirs
    )
    try {
        Log-Message "Preparing files for NuGet package..."
        $virtualDir = Join-Path $RootDir "NuGetPackageContent"
        Validate-Directory -DirPath $virtualDir

        $total = $SourceDirs.Count
        $index = 0
        foreach ($dir in $SourceDirs) {
            $index++
            Write-Progress -Activity "Copying Files" -Status $dir -PercentComplete (($index / $total) * 100)
            $sourcePath = Join-Path $RootDir $dir
            if (Test-Path $sourcePath) {
                Copy-Item -Path "$sourcePath\*" -Destination $virtualDir -Recurse -Force -Exclude $ExcludeDirs -ErrorAction Stop
                Log-Message "Copied $dir to $virtualDir"
            } else {
                Log-Message "Directory $dir not found." -Level "WARNING"
            }
        }

        Generate-File -FilePath (Join-Path $virtualDir "LICENSE") -Content @"
MIT License
Copyright (c) $(Get-Date -Format "yyyy") $($Config.GitHubUsername)
...
"@
        Generate-File -FilePath (Join-Path $virtualDir "README.md") -Content @"
# $($Config.PackageId)
$($Config.Description)
## License
MIT License
"@
        return $virtualDir
    } catch {
        Handle-Error "Failed to prepare files: $_"
    }
}

function Generate-DynamicVersion {
    try {
        $major = 1
        $minor = 0
        $build = Get-Date -Format "yyMMdd"
        $revision = Get-Date -Format "HHmmss"
        $version = "$major.$minor.$build.$revision"
        Log-Message "Generated version: $version"
        return $version
    } catch {
        Handle-Error "Failed to generate version: $_"
    }
}

function Generate-DynamicNuspec {
    param (
        [string]$Version,
        [string]$VirtualDir,
        [string]$PackageId,
        [string]$Description,
        [string]$Tags,
        [array]$SourceDirs
    )
    try {
        $nuspecPath = Join-Path $VirtualDir "package.nuspec"
        $fileEntries = $SourceDirs | ForEach-Object { "<file src=`"$_\**\*`" target=`"content\$_`" />" }
        $nuspecContent = @"
<?xml version="1.0"?>
<package>
  <metadata>
    <id>$PackageId</id>
    <version>$Version</version>
    <authors>$($Config.GitHubUsername)</authors>
    <owners>$($Config.GitHubUsername)</owners>
    <licenseUrl>https://opensource.org/licenses/MIT</licenseUrl>
    <projectUrl>https://github.com/$($Config.GitHubUsername)</projectUrl>
    <description>$Description</description>
    <tags>$Tags</tags>
  </metadata>
  <files>
    $($fileEntries -join "`n    ")
    <file src="LICENSE" target="content" />
    <file src="README.md" target="content" />
    <file src="lib\$($Config.TargetFramework)\PlaceholderDll.dll" target="lib\$($Config.TargetFramework)" />
  </files>
</package>
"@
        Generate-File -FilePath $nuspecPath -Content $nuspecContent
        Log-Message ".nuspec file generated at $nuspecPath"
        return $nuspecPath
    } catch {
        Handle-Error "Failed to generate .nuspec file: $_"
    }
}

function Verify-NuspecFile {
    param ([string]$NuspecPath)
    try {
        if (-not (Test-Path $NuspecPath)) {
            Handle-Error ".nuspec file not found at ${NuspecPath}."
        }
        [xml]$nuspec = Get-Content $NuspecPath
        if (-not $nuspec.package.metadata.id -or -not $nuspec.package.metadata.version) {
            Handle-Error "Invalid .nuspec file: Missing required metadata."
        }
        Log-Message ".nuspec file verified: $NuspecPath" -Level "DEBUG"
    } catch {
        Handle-Error "Failed to verify .nuspec file: $_"
    }
}

function Generate-PlaceholderDll {
    param ([string]$VirtualDir, [string]$TargetFramework)
    try {
        $dllPath = Join-Path $VirtualDir "lib\$TargetFramework\PlaceholderDll.dll"
        Validate-Directory -DirPath (Split-Path -Parent $dllPath)
        [byte[]]$stub = 0x4D, 0x5A, 0x90, 0x00
        [System.IO.File]::WriteAllBytes($dllPath, $stub)
        Log-Message "Generated placeholder DLL at $dllPath"
    } catch {
        Handle-Error "Failed to generate placeholder DLL: $_"
    }
}

function Pack-NuGetPackage {
    param (
        [string]$NuspecPath,
        [string]$ArtifactDir
    )
    try {
        Validate-Directory -DirPath $ArtifactDir
        $output = & $NuGetExePath pack $NuspecPath -OutputDirectory $ArtifactDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Handle-Error "nuget.exe pack failed: $output"
        }
        Log-Message "NuGet package packed to $ArtifactDir"
    } catch {
        Handle-Error "Failed to pack NuGet package: $_"
    }
}

function Verify-PackageIntegrity {
    param (
        [string]$ArtifactDir,
        [array]$SourceDirs
    )
    try {
        $nupkgFile = Get-ChildItem -Path $ArtifactDir -Filter "*.nupkg" | Select-Object -First 1
        if (-not $nupkgFile) {
            Handle-Error "No .nupkg file found in ${ArtifactDir}."
        }
        $extractDir = Join-Path $ArtifactDir "PackageContents_$Timestamp"
        Validate-Directory -DirPath $extractDir
        Expand-Archive -Path $nupkgFile.FullName -DestinationPath $extractDir -Force
        $requiredPaths = $SourceDirs | ForEach-Object { "content\$_" }
        $requiredPaths += @("content\LICENSE", "content\README.md", "lib\$($Config.TargetFramework)\PlaceholderDll.dll")
        foreach ($path in $requiredPaths) {
            if (-not (Test-Path (Join-Path $extractDir $path))) {
                Handle-Error "Missing package content: $path"
            }
        }
        Log-Message "Package integrity verified."
    } catch {
        Handle-Error "Failed to verify package integrity: $_"
    }
}

function Publish-NuGetPackage {
    param (
        [string]$GitHubPAT,
        [string]$PackageSourceUrl,
        [string]$ArtifactDir
    )
    try {
        $packages = Get-ChildItem -Path $ArtifactDir -Filter "*.nupkg"
        if (-not $packages) {
            Handle-Error "No NuGet packages found in ${ArtifactDir}."
        }
        $total = $packages.Count
        $index = 0
        foreach ($package in $packages) {
            $index++
            Write-Progress -Activity "Publishing Packages" -Status $package.Name -PercentComplete (($index / $total) * 100)
            $output = & $NuGetExePath push $package.FullName -ApiKey $GitHubPAT -Source $PackageSourceUrl -NonInteractive 2>&1
            if ($LASTEXITCODE -ne 0) {
                Log-Message "Failed to push $($package.Name): $output" -Level "ERROR"
            } else {
                Log-Message "Published $($package.Name)"
            }
        }
    } catch {
        Handle-Error "Failed to publish NuGet package: $_"
    }
}

function Generate-Report {
    param (
        [string]$OutputDirectory,
        [string]$PackageId,
        [string]$GitHubUsername,
        [string]$PackageSourceUrl
    )
    try {
        $reportPath = Join-Path $OutputDirectory "NuGetReport_$Timestamp.txt"
        $reportContent = @"
NuGet Package Report
Generated On: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Package ID: $PackageId
GitHub Username: $GitHubUsername
Package Source: $PackageSourceUrl
Artifact Directory: $OutputDirectory
"@
        Generate-File -FilePath $reportPath -Content $reportContent
        Log-Message "Report generated at $reportPath"
    } catch {
        Handle-Error "Failed to generate report: $_"
    }
}

function Execute-Workflow {
    param (
        [string]$RootDir,
        [string]$GitHubUsername,
        [string]$GitHubPAT,
        [string]$PackageId,
        [string]$Description,
        [string]$Tags,
        [array]$SourceDirs,
        [array]$ExcludeDirs
    )
    try {
        if (-not $GitHubUsername -or -not $GitHubPAT -or -not $PackageId) {
            Handle-Error "GitHub Username, PAT, and Package ID are required."
        }
        $packageSourceUrl = "https://nuget.pkg.github.com/$GitHubUsername/index.json"
        $artifactDir = Join-Path $RootDir "artifacts"
        $virtualDir = Prepare-Files -RootDir $RootDir -SourceDirs $SourceDirs -ExcludeDirs $ExcludeDirs
        $version = Generate-DynamicVersion
        $nuspecPath = Generate-DynamicNuspec -Version $version -VirtualDir $virtualDir -PackageId $PackageId -Description $Description -Tags $Tags -SourceDirs $SourceDirs
        Verify-NuspecFile -NuspecPath $nuspecPath
        Generate-PlaceholderDll -VirtualDir $virtualDir -TargetFramework $Config.TargetFramework
        Pack-NuGetPackage -NuspecPath $nuspecPath -ArtifactDir $artifactDir
        Verify-PackageIntegrity -ArtifactDir $artifactDir -SourceDirs $SourceDirs
        Publish-NuGetPackage -GitHubPAT $GitHubPAT -PackageSourceUrl $packageSourceUrl -ArtifactDir $artifactDir
        Generate-Report -OutputDirectory $artifactDir -PackageId $PackageId -GitHubUsername $GitHubUsername -PackageSourceUrl $packageSourceUrl
        Log-Message "Workflow completed successfully."
    } catch {
        Handle-Error "Workflow failed: $_"
    }
}
#endregion

#region --- GUI ---
function Show-GUI {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "NuGet Package Publisher"
    $form.Size = New-Object System.Drawing.Size(900, 800)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 245)
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if (Test-Path (Join-Path $ScriptDir "icon.ico")) {
        $form.Icon = New-Object System.Drawing.Icon((Join-Path $ScriptDir "icon.ico"))
    }

    # Title label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "NuGet Package Publisher v2.8"
    $titleLabel.Location = New-Object System.Drawing.Point(20, 10)
    $titleLabel.Size = New-Object System.Drawing.Size(850, 30)
    $titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $titleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($titleLabel)

    # Dynamic positioning
    $yPos = 50
    $xLabel = 30
    $xInput = 230
    $inputWidth = 620
    $rowHeight = 32
    $padding = 20

    # Input panel
    $inputPanel = New-Object System.Windows.Forms.GroupBox
    $inputPanel.Text = "Package Configuration"
    $inputPanel.Location = New-Object System.Drawing.Point($xLabel, $yPos)
    $inputPanel.Size = New-Object System.Drawing.Size(820, 340)
    $inputPanel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $form.Controls.Add($inputPanel)

    $yPos += 20

    $fields = @(
        @{ Label = "Root Directory:"; Name = "RootDir"; Default = $ScriptDir; Tooltip = "Root directory of your repository (e.g., D:\15016\Downloads\MyRepo)" },
        @{ Label = "GitHub Username:"; Name = "GitHubUsername"; Default = $Config.GitHubUsername; Tooltip = "Your GitHub username" },
        @{ Label = "GitHub PAT:"; Name = "GitHubPAT"; Default = ""; Password = $true; Tooltip = "Personal Access Token with package:write scope" },
        @{ Label = "Package ID:"; Name = "PackageId"; Default = $Config.PackageId; Tooltip = "Unique identifier for the NuGet package" },
        @{ Label = "Description:"; Name = "Description"; Default = $Config.Description; Tooltip = "Brief description of the package" },
        @{ Label = "Tags (space-separated):"; Name = "Tags"; Default = $Config.Tags; Tooltip = "Tags for package discovery (e.g., powershell nuget)" },
        @{ Label = "Source Directories (comma-separated):"; Name = "SourceDirs"; Default = ($Config.SourceDirs -join ", "); Tooltip = "Directories to include in the package (e.g., Scripts,Templates)" },
        @{ Label = "Exclude Directories (comma-separated):"; Name = "ExcludeDirs"; Default = ($Config.ExcludeDirs -join ", "); Tooltip = "Directories to exclude (e.g., Tests,Logs)" }
    )

    $tabIndex = 0
    foreach ($field in $fields) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $field.Label
        $label.Location = New-Object System.Drawing.Point($xLabel, ($yPos + 5))
        $label.Size = New-Object System.Drawing.Size(200, 20)
        $label.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
        $inputPanel.Controls.Add($label)

        $textBox = if ($field.Password) { New-Object System.Windows.Forms.MaskedTextBox } else { New-Object System.Windows.Forms.TextBox }
        $textBox.Location = New-Object System.Drawing.Point($xInput, $yPos)
        $textBox.Size = New-Object System.Drawing.Size($inputWidth, 25)
        $textBox.Text = $field.Default
        if ($field.Password) { $textBox.PasswordChar = '*' }
        $textBox.BackColor = [System.Drawing.Color]::White
        $textBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $textBox.Tag = $field.Tooltip
        $tooltip = New-Object System.Windows.Forms.ToolTip
        $tooltip.SetToolTip($textBox, $field.Tooltip)
        $textBox.TabIndex = $tabIndex
        $tabIndex++
        Set-Variable -Name "textBox$($field.Name)" -Value $textBox -Scope Global
        $inputPanel.Controls.Add($textBox)

        $yPos += $rowHeight
    }

    $yPos += $padding

    # Output panel
    $outputPanel = New-Object System.Windows.Forms.GroupBox
    $outputPanel.Text = "Results"
    $outputPanel.Location = New-Object System.Drawing.Point($xLabel, $yPos)
    $outputPanel.Size = New-Object System.Drawing.Size(820, 240)
    $outputPanel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $form.Controls.Add($outputPanel)

    $yPos += 20

    $labelOutput = New-Object System.Windows.Forms.Label
    $labelOutput.Text = "Log Output:"
    $labelOutput.Location = New-Object System.Drawing.Point($xLabel, ($yPos + 5))
    $labelOutput.Size = New-Object System.Drawing.Size(200, 20)
    $labelOutput.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $outputPanel.Controls.Add($labelOutput)

    $yPos += 25

    $textBoxResults = New-Object System.Windows.Forms.TextBox
    $textBoxResults.Location = New-Object System.Drawing.Point($xLabel, $yPos)
    $textBoxResults.Size = New-Object System.Drawing.Size(760, 180)
    $textBoxResults.Multiline = $true
    $textBoxResults.ScrollBars = "Vertical"
    $textBoxResults.ReadOnly = $true
    $textBoxResults.BackColor = [System.Drawing.Color]::WhiteSmoke
    $textBoxResults.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $textBoxResults.Tag = "View the progress and results of the NuGet package workflow"
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($textBoxResults, "View the progress and results of the NuGet package workflow")
    $textBoxResults.TabIndex = $tabIndex
    $tabIndex++
    Set-Variable -Name "textBoxResults" -Value $textBoxResults -Scope Global
    $outputPanel.Controls.Add($textBoxResults)

    $yPos += 200

    # Button panel
    $yPos += $padding
    $buttonPanel = New-Object System.Windows.Forms.GroupBox
    $buttonPanel.Text = "Actions"
    $buttonPanel.Location = New-Object System.Drawing.Point($xLabel, $yPos)
    $buttonPanel.Size = New-Object System.Drawing.Size(820, 120)
    $buttonPanel.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $form.Controls.Add($buttonPanel)

    $yPos += 20

    # Run Workflow Button
    $buttonRun = New-Object System.Windows.Forms.Button
    $buttonRun.Text = "Run Workflow"
    $buttonRun.Size = New-Object System.Drawing.Size(360, 40)
    $buttonRun.Location = New-Object System.Drawing.Point(30, $yPos)
    $buttonRun.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $buttonRun.ForeColor = [System.Drawing.Color]::White
    $buttonRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
    $buttonRun.Tag = "Execute the NuGet package creation and publishing workflow"
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($buttonRun, "Execute the NuGet package creation and publishing workflow")
    $buttonRun.TabIndex = $tabIndex
    $tabIndex++
    $buttonRun.Add_Click({
            $statusLabel.Text = "Uploading..."
            $statusLabel.ForeColor = [System.Drawing.Color]::Black
            Validate-Inputs
            if ($script:validationError) {
                $statusLabel.Text = "Error: $script:validationError"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
                return
            }
            try {
                $sourceDirs = $textBoxSourceDirs.Text.Trim() -split ",\s*" | Where-Object { $_ }
                $excludeDirs = $textBoxExcludeDirs.Text.Trim() -split ",\s*" | Where-Object { $_ }

                Execute-Workflow -RootDir $textBoxRootDir.Text.Trim() `
                    -GitHubUsername $textBoxGitHubUsername.Text.Trim() `
                    -GitHubPAT $textBoxGitHubPAT.Text.Trim() `
                    -PackageId $textBoxPackageId.Text.Trim() `
                    -Description $textBoxDescription.Text.Trim() `
                    -Tags $textBoxTags.Text.Trim() `
                    -SourceDirs $sourceDirs `
                    -ExcludeDirs $excludeDirs

                $textBoxResults.AppendText("Workflow completed successfully.`r`n")
                $statusLabel.Text = "Success"
                $statusLabel.ForeColor = [System.Drawing.Color]::Green
            } catch {
                $textBoxResults.AppendText("Error: $_`r`n")
                $statusLabel.Text = "Error: $_"
                $statusLabel.ForeColor = [System.Drawing.Color]::Red
            }
        })
    $buttonPanel.Controls.Add($buttonRun)

    # Exit Button
    $buttonExit = New-Object System.Windows.Forms.Button
    $buttonExit.Text = "Exit"
    $buttonExit.Size = New-Object System.Drawing.Size(360, 40)
    $buttonExit.Location = New-Object System.Drawing.Point(420, $yPos)
    $buttonExit.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
    $buttonExit.ForeColor = [System.Drawing.Color]::White
    $buttonExit.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
    $buttonExit.Tag = "Close the application"
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($buttonExit, "Close the application")
    $buttonExit.TabIndex = $tabIndex
    $tabIndex++
    $buttonExit.Add_Click({ $form.Close() })
    $buttonPanel.Controls.Add($buttonExit)

    # Status Label
    $yPos += 50
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = ""
    $statusLabel.Location = New-Object System.Drawing.Point(30, $yPos)
    $statusLabel.Size = New-Object System.Drawing.Size(760, 20)
    $statusLabel.ForeColor = [System.Drawing.Color]::Black
    $buttonPanel.Controls.Add($statusLabel)

    # Help Button
    $buttonHelp = New-Object System.Windows.Forms.Button
    $buttonHelp.Text = "ℹ️ Help"
    $buttonHelp.Size = New-Object System.Drawing.Size(80, 30)
    $buttonHelp.Location = New-Object System.Drawing.Point(740, 10)
    $buttonHelp.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $buttonHelp.ForeColor = [System.Drawing.Color]::White
    $buttonHelp.FlatStyle = [System.Windows.Forms.FlatStyle]::Popup
    $buttonHelp.Tag = "Open help documentation on GitHub"
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($buttonHelp, "Open help documentation on GitHub (https://github.com/your-username/your-repo)")
    $buttonHelp.TabIndex = $tabIndex
    $tabIndex++
    $buttonHelp.Add_Click({
            Start-Process "https://github.com/your-username/your-repo"
        })
    $form.Controls.Add($buttonHelp)

    # Footer Label
    $footerLabel = New-Object System.Windows.Forms.Label
    $footerLabel.Text = "v2.8 | Config: $ConfigPath"
    $footerLabel.Location = New-Object System.Drawing.Point(20, 760)
    $footerLabel.Size = New-Object System.Drawing.Size(850, 20)
    $footerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $footerLabel.ForeColor = [System.Drawing.Color]::Gray
    $footerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $form.Controls.Add($footerLabel)

    $yPos += 70
    $form.Height = $yPos + 80

    # Validation function
    function Validate-Inputs {
        $script:validationError = $null
        if (-not (Test-Path $textBoxRootDir.Text.Trim())) {
            $textBoxRootDir.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $textBoxRootDir.BackColor = [System.Drawing.Color]::FromArgb(255, 192, 192)
            $script:validationError = "Invalid Root Directory"
        } else {
            $textBoxRootDir.BackColor = [System.Drawing.Color]::White
        }
        if ($textBoxGitHubPAT.Text.Trim().Length -lt 20) {
            $textBoxGitHubPAT.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $textBoxGitHubPAT.BackColor = [System.Drawing.Color]::FromArgb(255, 192, 192)
            $script:validationError = "Invalid GitHub PAT (too short)"
        } else {
            $textBoxGitHubPAT.BackColor = [System.Drawing.Color]::White
        }
    }

    [void]$form.ShowDialog()
}
#endregion

# Start GUI or Run Non-Interactively
if ($PSVersionTable.Platform -ne "Unix") {
    Show-GUI
} else {
    Write-Warning "GUI not supported on non-Windows platforms. Please provide a config file with -ConfigPath."
}

# End of script
