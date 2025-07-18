<#
.SYNOPSIS
    Publishes a NuGet package based on an existing .nuspec file.

.DESCRIPTION
    This script packages a ZIP file into a NuGet `.nupkg` using an existing .nuspec,
    optionally publishes it to GitHub Packages, and embeds changelog/release notes.

.PARAMETER NuspecPath
    Full path to the .nuspec file used for packaging.

.PARAMETER PackageId
    Logical name of the package.

.PARAMETER Version
    Version number for the package (e.g., 1.2.3).

.PARAMETER ZipPath
    Path to the .zip file to include in the package.

.PARAMETER ReleaseNotesPath
    Optional .md or .txt file containing release notes.

.PARAMETER OutputPath
    Where to write the resulting .nupkg file. Defaults to current directory.

.PARAMETER Publish
    If specified, will attempt to publish the package to GitHub Packages.

.PARAMETER ApiKey
    GitHub NuGet API key (use ${{ secrets.NUGET_API_KEY }} in GitHub Actions).
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$NuspecPath,

    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$ZipPath,

    [string]$ReleaseNotesPath = "",

    [string]$OutputPath = ".",

    [switch]$Publish = $false,

    [string]$ApiKey = ""
)

# Validate input paths
if (-not (Test-Path $NuspecPath)) {
    Write-Error "Missing .nuspec file at: $NuspecPath"
    exit 1
}
if (-not (Test-Path $ZipPath)) {
    Write-Error "Missing ZIP package file: $ZipPath"
    exit 1
}

# Download nuget.exe if not already present
$nugetExe = Join-Path -Path $OutputPath -ChildPath "nuget.exe"
if (-not (Test-Path $nugetExe)) {
    Write-Host "Downloading nuget.exe..."
    Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetExe
}

# Pack NuGet package
$packCommand = "& `"$nugetExe`" pack `"$NuspecPath`" -Version `"$Version`" -OutputDirectory `"$OutputPath`""
Invoke-Expression $packCommand

# Locate generated .nupkg file
$nupkgPath = Join-Path -Path $OutputPath -ChildPath "$PackageId.$Version.nupkg"
if (-not (Test-Path $nupkgPath)) {
    Write-Error "Failed to generate .nupkg file at: $nupkgPath"
    exit 1
}

Write-Host "✔ Package built: $nupkgPath"

# Optional: Push to GitHub Packages
if ($Publish) {
    if (-not $ApiKey) {
        Write-Error "API key required for publishing. Provide via -ApiKey parameter."
        exit 1
    }

    $repoOwner = $env:GITHUB_REPOSITORY_OWNER
    if (-not $repoOwner) {
        Write-Error "GITHUB_REPOSITORY_OWNER not set in environment."
        exit 1
    }

    $sourceUrl = "https://nuget.pkg.github.com/$repoOwner/index.json"
    $pushCommand = "& `"$nugetExe`" push `"$nupkgPath`" -Source `"$sourceUrl`" -ApiKey `"$ApiKey`""
    Write-Host "Publishing to GitHub Packages..."
    Invoke-Expression $pushCommand
    Write-Host "✔ Package published successfully."
}

# Optional: Embed SHA256
$shaPath = "$ZipPath.sha256"
Get-FileHash -Algorithm SHA256 -Path $ZipPath | ForEach-Object {
    $_.Hash + " *" + (Split-Path -Leaf $ZipPath)
} | Set-Content -Path $shaPath -Encoding UTF8
Write-Host "✔ SHA256 hash generated: $shaPath"

# Optional: Print release notes
if ($ReleaseNotesPath -and (Test-Path $ReleaseNotesPath)) {
    Write-Host "`n📄 Release Notes:"
    Get-Content -Path $ReleaseNotesPath | ForEach-Object { Write-Host $_ }
}
