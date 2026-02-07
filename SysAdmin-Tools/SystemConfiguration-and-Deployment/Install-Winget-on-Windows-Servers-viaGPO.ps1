<#
.SYNOPSIS
    PowerShell Script for Installing and Configuring WinGet on Windows Server 2019.

.DESCRIPTION
    This script configures WinGet on Windows Server 2019 by downloading the winget binary from a specified GitHub
    release URL, extracting it, and setting it up in a system directory. It ensures winget.exe is functional by adding
    it to the system PATH and verifying its operation. The script also checks for and installs required dependencies
    (e.g., Microsoft.VCLibs.140.00.UWPDesktop) if needed. Suitable for silent deployment via Group Policy (GPO).

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-07
#>

param (
    [string]$LogDir = "C:\Scripts-LOGS", # Default log directory
    [string]$WingetInstallDir = "C:\Program Files\winget" # Directory to install winget
)

# Script initialization
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$VerbosePreference = "SilentlyContinue"

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Configure log file path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $LogDir $logFileName

# Function to log messages (file only, no console output)
function Log-Message {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string]$Severity = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$Severity] [$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        # If logging fails, we can't write to the console, so silently fail
    }
}

# Function to check for elevated privileges
function Test-Elevated {
    $isElevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isElevated) {
        Log-Message "This script requires elevated privileges. Please run as Administrator." -Severity "ERROR"
        exit 1
    }
}

# Function to check PowerShell version
function Test-PowerShellVersion {
    $requiredVersion = [Version]"5.1"
    $currentVersion = $PSVersionTable.PSVersion
    if ($currentVersion -lt $requiredVersion) {
        Log-Message "PowerShell version $requiredVersion or higher is required. Current version: $currentVersion" -Severity "ERROR"
        exit 1
    }
}

# Function to test basic internet connectivity
function Test-InternetConnectivity {
    Log-Message "Checking basic internet connectivity by pinging google.com..."
    try {
        $pingResult = Test-Connection -ComputerName "google.com" -Count 1 -Quiet -ErrorAction Stop
        if ($pingResult) {
            Log-Message "Basic internet connectivity is available."
            return $true
        } else {
            Log-Message "No response from google.com. Internet connectivity may be unavailable." -Severity "WARNING"
            return $false
        }
    } catch {
        Log-Message "Error testing internet connectivity: $_" -Severity "WARNING"
        return $false
    }
}

# Function to test network connectivity to a specific URL
function Test-NetworkConnectivity {
    param (
        [string]$Url
    )
    Log-Message "Checking network connectivity to $Url..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Log-Message "TLS 1.2 enabled for network access."
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -ErrorAction Stop
        Log-Message "Successfully connected to $Url. Status Code: $($response.StatusCode)"
        return $true
    } catch {
        Log-Message "Error connecting to ${Url}. Error: $_" -Severity "WARNING"
        Log-Message "Troubleshooting steps:" -Severity "INFO"
        Log-Message "1. Ensure internet connectivity is available." -Severity "INFO"
        Log-Message "2. Check if a proxy is required and configure it using 'netsh winhttp set proxy'." -Severity "INFO"
        Log-Message "3. Verify that outbound HTTPS traffic (port 443) is allowed by your firewall." -Severity "INFO"
        return $false
    }
}

# Function to download a file
function Download-File {
    param (
        [string]$Url,
        [string]$OutputPath
    )
    Log-Message "Downloading file from $Url to $OutputPath..."
    try {
        $networkAvailable = Test-NetworkConnectivity -Url $Url
        if (-not $networkAvailable) {
            Log-Message "Cannot download file due to network issues." -Severity "ERROR"
            return $false
        }
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing -ErrorAction Stop
        $fileSize = (Get-Item $OutputPath).Length
        Log-Message "Downloaded file successfully. File size: $fileSize bytes."
        return $true
    } catch {
        Log-Message "Error downloading file: $_" -Severity "ERROR"
        return $false
    }
}

# Function to install Microsoft.VCLibs.x64.14.00.Desktop dependency
function Install-VCLibs {
    param (
        [string]$RequiredVersion = "14.0.33728.0"
    )
    Log-Message "Checking for dependency Microsoft.VCLibs.x64.14.00.Desktop..."
    $requiredVersionObj = [Version]$RequiredVersion
    $vclibs = Get-AppxPackage -AllUsers -Name "Microsoft.VCLibs.140.00*" -ErrorAction SilentlyContinue

    if ($vclibs) {
        $installedVersion = [Version]$vclibs.Version
        if ($installedVersion -ge $requiredVersionObj) {
            Log-Message "Dependency Microsoft.VCLibs.x64.14.00.Desktop is already installed. Version: $installedVersion"
            return
        } else {
            Log-Message "Installed version of Microsoft.VCLibs.x64.14.00.Desktop ($installedVersion) is older than the required version ($RequiredVersion). Removing and reinstalling..." -Severity "WARNING"
            try {
                Remove-AppxPackage -Package $vclibs.PackageFullName -AllUsers -ErrorAction Stop
                Log-Message "Removed older version of Microsoft.VCLibs.x64.14.00.Desktop."
            } catch {
                Log-Message "Error removing older version of Microsoft.VCLibs.x64.14.00.Desktop: $_" -Severity "ERROR"
                exit 1
            }
        }
    }

    Log-Message "Attempting to download and install dependency Microsoft.VCLibs.x64.14.00.Desktop (required version: $RequiredVersion or higher)..."
    $DownloadsFolder = Join-Path $env:USERPROFILE "Downloads"
    $vclibsUrl = "https://dl.licaoz.com/runtimes/VCLibs/Desktop/14/33728/Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64__8wekyb3d8bbwe.Appx"
    $vclibsPath = Join-Path $DownloadsFolder "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    
    # Download VCLibs if internet is available
    $internetAvailable = Test-InternetConnectivity
    if (-not (Test-Path $vclibsPath)) {
        if (-not $internetAvailable) {
            Log-Message "Internet connectivity is required to download Microsoft.VCLibs.x64.14.00.Desktop." -Severity "ERROR"
            Log-Message "Please download version >= $RequiredVersion manually from a reliable source (e.g., Microsoft Store or https://store.rg-adguard.net/) and place it at $vclibsPath." -Severity "INFO"
            exit 1
        }
        $downloadSuccess = Download-File -Url $vclibsUrl -OutputPath $vclibsPath
        if (-not $downloadSuccess) {
            Log-Message "Failed to download Microsoft.VCLibs.x64.14.00.Desktop from $vclibsUrl." -Severity "ERROR"
            Log-Message "Please download version >= $RequiredVersion manually from a reliable source (e.g., Microsoft Store or https://store.rg-adguard.net/) and place it at $vclibsPath." -Severity "INFO"
            exit 1
        }
    } else {
        Log-Message "Found Microsoft.VCLibs.x64.14.00.Desktop package at '$vclibsPath'."
    }

    # Validate file size (minimum 700 KB to ensure it's not corrupt)
    $minSizeBytes = 700KB
    $fileSize = (Get-Item $vclibsPath).Length
    if ($fileSize -lt $minSizeBytes) {
        Log-Message "Microsoft.VCLibs.x64.14.00.Desktop package size ($fileSize bytes) is below expected threshold ($minSizeBytes bytes). It may be corrupt." -Severity "WARNING"
        if (-not $internetAvailable) {
            Log-Message "Internet connectivity is required to re-download Microsoft.VCLibs.x64.14.00.Desktop." -Severity "ERROR"
            Log-Message "Please download version >= $RequiredVersion manually from a reliable source (e.g., Microsoft Store or https://store.rg-adguard.net/) and place it at $vclibsPath." -Severity "INFO"
            exit 1
        }
        Log-Message "Deleting and retrying download..."
        Remove-Item $vclibsPath -Force
        $downloadSuccess = Download-File -Url $vclibsUrl -OutputPath $vclibsPath
        if (-not $downloadSuccess) {
            Log-Message "Failed to download Microsoft.VCLibs.x64.14.00.Desktop from $vclibsUrl after retry." -Severity "ERROR"
            Log-Message "Please download version >= $RequiredVersion manually from a reliable source (e.g., Microsoft Store or https://store.rg-adguard.net/) and place it at $vclibsPath." -Severity "INFO"
            exit 1
        }
    }

    # Install the dependency
    $maxRetries = 2
    $retryCount = 0
    $success = $false
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Log-Message "Installing Microsoft.VCLibs.x64.14.00.Desktop package (Attempt $($retryCount + 1) of $maxRetries)..."
            Add-AppxPackage -Path $vclibsPath -ErrorAction Stop
            Log-Message "Microsoft.VCLibs.x64.14.00.Desktop package installation initiated. Waiting for registration..."
            Start-Sleep -Seconds 10
            $success = $true
        } catch {
            $retryCount++
            Log-Message "Error installing Microsoft.VCLibs.x64.14.00.Desktop package: $_" -Severity "ERROR"
            if ($retryCount -lt $maxRetries) {
                Log-Message "Retrying installation in 5 seconds..." -Severity "INFO"
                Start-Sleep -Seconds 5
            } else {
                Log-Message "Failed to install Microsoft.VCLibs.x64.14.00.Desktop after $maxRetries attempts." -Severity "ERROR"
                Log-Message "Troubleshooting steps:" -Severity "INFO"
                Log-Message "1. Verify that the package file at '$vclibsPath' is not corrupted. You can re-download version >= $RequiredVersion from $vclibsUrl." -Severity "INFO"
                Log-Message "2. Check the Event Log for more details: Open Event Viewer (eventvwr.msc) and navigate to Applications and Services Logs > Microsoft > Windows > AppxDeployment-Server." -Severity "INFO"
                Log-Message "3. Ensure that sideloading of apps is enabled in Group Policy (Computer Configuration > Administrative Templates > Windows Components > App Package Deployment > Allow all trusted apps to install)." -Severity "INFO"
                Log-Message "4. Try installing the package manually using: Add-AppxPackage -Path '$vclibsPath'" -Severity "INFO"
                exit 1
            }
        }
    }

    # Verify installation
    $vclibs = Get-AppxPackage -AllUsers -Name "Microsoft.VCLibs.140.00*" -ErrorAction SilentlyContinue
    if (-not $vclibs) {
        Log-Message "Installation of Microsoft.VCLibs.x64.14.00.Desktop failed." -Severity "ERROR"
        exit 1
    } else {
        $installedVersion = [Version]$vclibs.Version
        if ($installedVersion -lt $requiredVersionObj) {
            Log-Message "Installed version of Microsoft.VCLibs.x64.14.00.Desktop ($installedVersion) is still older than the required version ($RequiredVersion)." -Severity "ERROR"
            Log-Message "Please download a version >= $RequiredVersion manually from a reliable source (e.g., Microsoft Store or https://store.rg-adguard.net/) and install it using: Add-AppxPackage -Path <path-to-appx>" -Severity "INFO"
            exit 1
        }
        Log-Message "Dependency Microsoft.VCLibs.x64.14.00.Desktop installed successfully. Version: $installedVersion"
    }
}

# Function to extract winget from an .msix file
function Extract-WingetFromMsix {
    param (
        [string]$MsixPath,
        [string]$ExtractPath
    )
    Log-Message "Extracting .msix file ${MsixPath} to ${ExtractPath}..."
    try {
        # Rename .msix to .zip for extraction
        $msixZipPath = [System.IO.Path]::ChangeExtension($MsixPath, ".zip")
        if (Test-Path $msixZipPath) {
            Log-Message "Removing existing ${msixZipPath} to avoid conflicts..."
            Remove-Item $msixZipPath -Force -ErrorAction Stop
        }
        Copy-Item -Path $MsixPath -Destination $msixZipPath -Force -ErrorAction Stop
        Log-Message "Renamed ${MsixPath} to ${msixZipPath} for extraction."

        # Extract the .msix file
        if (Test-Path $ExtractPath) {
            Log-Message "Removing existing extraction directory ${ExtractPath}..."
            Remove-Item $ExtractPath -Recurse -Force -ErrorAction Stop
        }
        Expand-Archive -Path $msixZipPath -DestinationPath $ExtractPath -Force -ErrorAction Stop
        Log-Message "Extracted .msix file successfully to ${ExtractPath}."

        # Clean up the temporary .zip file
        Remove-Item $msixZipPath -Force -ErrorAction Stop
        Log-Message "Cleaned up temporary file ${msixZipPath}."
    } catch {
        Log-Message "Error extracting .msix file ${MsixPath}. Error: $_" -Severity "ERROR"
        exit 1
    }
}

# Function to download and extract winget
function Install-WingetBinary {
    Log-Message "Installing winget binary..."
    
    # Define paths
    $DownloadsFolder = Join-Path $env:USERPROFILE "Downloads"
    $wingetBundleUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.11.180-preview/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $wingetBundlePath = Join-Path $DownloadsFolder "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $wingetZipPath = Join-Path $DownloadsFolder "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.zip"
    $extractPath = Join-Path $DownloadsFolder "WingetExtract"

    # Download the winget bundle
    if (-not (Test-Path $wingetBundlePath)) {
        $internetAvailable = Test-InternetConnectivity
        if (-not $internetAvailable) {
            Log-Message "Internet connectivity is required to download the winget bundle." -Severity "ERROR"
            Log-Message "Please download the winget release manually from $wingetBundleUrl and place it at $wingetBundlePath." -Severity "INFO"
            exit 1
        }
        $downloadSuccess = Download-File -Url $wingetBundleUrl -OutputPath $wingetBundlePath
        if (-not $downloadSuccess) {
            Log-Message "Failed to download winget bundle from $wingetBundleUrl." -Severity "ERROR"
            Log-Message "Please download the winget release manually from $wingetBundleUrl and place it at $wingetBundlePath." -Severity "INFO"
            exit 1
        }
    } else {
        Log-Message "Found winget bundle at '${wingetBundlePath}'."
    }

    # Validate file size (minimum 5 MB to ensure it's not corrupt)
    $minSizeBytes = 5MB
    $fileSize = (Get-Item $wingetBundlePath).Length
    if ($fileSize -lt $minSizeBytes) {
        Log-Message "Winget bundle size ($fileSize bytes) is below expected threshold ($minSizeBytes bytes). It may be corrupt." -Severity "WARNING"
        $internetAvailable = Test-InternetConnectivity
        if (-not $internetAvailable) {
            Log-Message "Internet connectivity is required to re-download the winget bundle." -Severity "ERROR"
            Log-Message "Please download the winget release manually from $wingetBundleUrl and place it at $wingetBundlePath." -Severity "INFO"
            exit 1
        }
        Log-Message "Deleting and retrying download..."
        Remove-Item $wingetBundlePath -Force
        $downloadSuccess = Download-File -Url $wingetBundleUrl -OutputPath $wingetBundlePath
        if (-not $downloadSuccess) {
            Log-Message "Failed to download winget bundle from $wingetBundleUrl after retry." -Severity "ERROR"
            Log-Message "Please download the winget release manually from $wingetBundleUrl and place it at $wingetBundlePath." -Severity "INFO"
            exit 1
        }
    }

    # Rename .msixbundle to .zip for extraction
    if (Test-Path $wingetBundlePath) {
        Log-Message "Renaming .msixbundle to .zip for extraction..."
        try {
            if (Test-Path $wingetZipPath) {
                Log-Message "Removing existing ${wingetZipPath} to avoid conflicts..."
                Remove-Item $wingetZipPath -Force -ErrorAction Stop
            }
            Rename-Item -Path $wingetBundlePath -NewName "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.zip" -Force -ErrorAction Stop
            Log-Message "Renamed ${wingetBundlePath} to ${wingetZipPath}."
        } catch {
            Log-Message "Error renaming .msixbundle to .zip: $_" -Severity "ERROR"
            exit 1
        }
    }

    # Extract the zip file
    if (Test-Path $wingetZipPath) {
        Log-Message "Extracting winget bundle to ${extractPath}..."
        try {
            if (Test-Path $extractPath) {
                Log-Message "Removing existing extraction directory ${extractPath}..."
                Remove-Item $extractPath -Recurse -Force -ErrorAction Stop
            }
            Expand-Archive -Path $wingetZipPath -DestinationPath $extractPath -Force -ErrorAction Stop
            Log-Message "Extracted winget bundle successfully to ${extractPath}."
        } catch {
            Log-Message "Error extracting winget bundle: $_" -Severity "ERROR"
            exit 1
        }
    } else {
        Log-Message "Winget zip file not found at ${wingetZipPath}." -Severity "ERROR"
        exit 1
    }

    # Look for .msix files in the extracted directory
    $msixFiles = Get-ChildItem -Path $extractPath -Filter "*.msix" -ErrorAction SilentlyContinue
    if (-not $msixFiles) {
        Log-Message "No .msix files found in ${extractPath}." -Severity "ERROR"
        Log-Message "Please ensure the winget bundle has been extracted correctly and contains .msix files." -Severity "INFO"
        Log-Message "You can re-download the winget release from $wingetBundleUrl and extract it manually using a tool like 7-Zip." -Severity "INFO"
        exit 1
    }

    # Determine system architecture
    $is64Bit = [Environment]::Is64BitOperatingSystem
    Log-Message "System architecture detected: $(if ($is64Bit) { '64-bit' } else { '32-bit' })"

    # Try to find the appropriate .msix file based on architecture
    $appInstallerMsix = $null
    if ($is64Bit) {
        $appInstallerMsix = $msixFiles | Where-Object { $_.Name -eq "AppInstaller_x64.msix" } | Select-Object -First 1
        if (-not $appInstallerMsix) {
            $appInstallerMsix = $msixFiles | Where-Object { $_.Name -eq "AppInstaller.msix" -or $_.Name -eq "AppInstallerCLI.msix" } | Select-Object -First 1
        }
    } else {
        $appInstallerMsix = $msixFiles | Where-Object { $_.Name -eq "AppInstaller_x86.msix" } | Select-Object -First 1
        if (-not $appInstallerMsix) {
            $appInstallerMsix = $msixFiles | Where-Object { $_.Name -eq "AppInstaller.msix" -or $_.Name -eq "AppInstallerCLI.msix" } | Select-Object -First 1
        }
    }

    if (-not $appInstallerMsix) {
        Log-Message "No suitable .msix file found in ${extractPath} for the current architecture. Available .msix files: $($msixFiles.Name -join ', ')" -Severity "ERROR"
        Log-Message "Files like AppInstaller_language-*.msix typically contain language resources, not the winget binary." -Severity "INFO"
        Log-Message "Please ensure the correct .msix file (e.g., AppInstaller_x64.msix for 64-bit systems) is present in ${extractPath}. You may need to re-download the winget release from $wingetBundleUrl." -Severity "INFO"
        exit 1
    }

    Log-Message "Selected ${appInstallerMsix} as the source for winget.exe."

    # Extract the selected .msix file
    $msixExtractPath = Join-Path $extractPath "MsixExtract"
    Extract-WingetFromMsix -MsixPath $appInstallerMsix.FullName -ExtractPath $msixExtractPath

    # Locate winget.exe in the extracted .msix contents
    $wingetExePath = Get-ChildItem -Path $msixExtractPath -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $wingetExePath) {
        Log-Message "winget.exe not found in extracted .msix contents at ${msixExtractPath}." -Severity "ERROR"
        Log-Message "Please verify the contents of ${appInstallerMsix} or try a different .msix file in ${extractPath}." -Severity "INFO"
        exit 1
    }

    $wingetSourceDir = $wingetExePath.Directory.FullName
    Log-Message "Found winget.exe at: ${wingetSourceDir}"

    # Create the winget installation directory
    if (-not (Test-Path $WingetInstallDir)) {
        Log-Message "Creating winget installation directory at ${WingetInstallDir}..."
        New-Item -Path $WingetInstallDir -ItemType Directory -Force | Out-Null
    }

    # Copy winget files to the installation directory
    Log-Message "Copying winget files to ${WingetInstallDir}..."
    try {
        Copy-Item -Path "$wingetSourceDir\*" -Destination $WingetInstallDir -Recurse -Force -ErrorAction Stop
        Log-Message "Copied winget files successfully."
    } catch {
        Log-Message "Error copying winget files to ${WingetInstallDir}. Error: $_" -Severity "ERROR"
        exit 1
    }

    # Clean up temporary files
    Log-Message "Cleaning up temporary files..."
    try {
        Remove-Item $wingetZipPath -Force -ErrorAction SilentlyContinue
        Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Log-Message "Temporary files cleaned up."
    } catch {
        Log-Message "Error cleaning up temporary files: $_" -Severity "WARNING"
    }
}

# Function to add winget to the system PATH
function Add-WingetToPath {
    Log-Message "Adding ${WingetInstallDir} to the system PATH..."
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
        if ($currentPath -notlike "*$WingetInstallDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$WingetInstallDir", [EnvironmentVariableTarget]::Machine)
            Log-Message "Added ${WingetInstallDir} to the system PATH."
        } else {
            Log-Message "${WingetInstallDir} is already in the system PATH."
        }
        # Refresh the current session's PATH
        $env:Path = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)
    } catch {
        Log-Message "Error adding ${WingetInstallDir} to the system PATH: $_" -Severity "ERROR"
        exit 1
    }
}

# Function to verify winget installation
function Test-WingetInstallation {
    Log-Message "Verifying winget installation by checking for winget.exe..."
    try {
        $wingetPath = (Get-Command winget -ErrorAction Stop).Source
        Log-Message "winget.exe found at: ${wingetPath}"
        $wingetVersion = & winget --version
        Log-Message "WinGet version: $wingetVersion"
        return $true
    } catch {
        Log-Message "winget.exe is not available in the PATH." -Severity "WARNING"
    }

    # Check if winget.exe exists in the installation directory
    $wingetExePath = Join-Path $WingetInstallDir "winget.exe"
    if (Test-Path $wingetExePath) {
        Log-Message "winget.exe found at: ${wingetExePath}"
        Add-WingetToPath
        try {
            $wingetVersion = & winget --version
            Log-Message "WinGet version: $wingetVersion"
            return $true
        } catch {
            Log-Message "Error running winget --version: $_" -Severity "ERROR"
        }
    } else {
        Log-Message "winget.exe not found in ${WingetInstallDir}." -Severity "ERROR"
    }

    # Provide troubleshooting steps if winget is still not available
    Log-Message "WinGet is not installed or configured." -Severity "ERROR"
    Log-Message "Troubleshooting steps:" -Severity "INFO"
    Log-Message "1. Ensure that the winget binary was downloaded and extracted correctly." -Severity "INFO"
    Log-Message "2. Verify that ${WingetInstallDir} contains winget.exe and its associated files." -Severity "INFO"
    Log-Message "3. Check for missing dependencies (e.g., Microsoft.VCLibs.140.00.UWPDesktop)." -Severity "INFO"
    Log-Message "4. Ensure ${WingetInstallDir} is in the system PATH." -Severity "INFO"
    Log-Message "5. Test winget manually by running: winget --version" -Severity "INFO"
    exit 1
}

# Main script execution
try {
    Log-Message "Starting WinGet configuration process on Windows Server 2019..."
    
    # Step 1: Check for elevated privileges
    Test-Elevated
    
    # Step 2: Check PowerShell version
    Test-PowerShellVersion
    
    # Step 3: Install required dependencies
    Install-VCLibs
    
    # Step 4: Install winget binary
    Install-WingetBinary
    
    # Step 5: Add winget to PATH
    Add-WingetToPath
    
    # Step 6: Verify winget installation
    Test-WingetInstallation
    
    Log-Message "WinGet configuration completed successfully."
    exit 0
} catch {
    Log-Message "An unexpected error occurred: $_" -Severity "ERROR"
    Log-Message "Exception Details: $($_.Exception.Message)" -Severity "ERROR"
    Log-Message "Stack Trace: $($_.ScriptStackTrace)" -Severity "ERROR"
    exit 1
}

# End of script
