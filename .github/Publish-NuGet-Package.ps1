<#
.SYNOPSIS
    Builds and publishes the Windows-SysAdmin-ProSuite NuGet package.

.DESCRIPTION
    This script dynamically creates a NuGet package using the `.nuspec` manifest,
    sets the version based on the latest release or pipeline input, and pushes it to
    NuGet.org or GitHub Packages using a secure API key.

.NOTES
    Author: BrazilianScriptGuy
    Updated: 2025-07-18
#>

param (
    [string]$NuSpecPath = ".github/Windows-SysAdmin-ProSuite.nuspec",
    [string]$NuGetExePath = ".github/tools/nuget.exe",
    [string]$PackageOutputDir = "./nuget-publish-output",
    [string]$Version = "",
    [string]$ApiKey = $env:NUGET_API_KEY,
    [string]$NuGetSource = "https://api.nuget.org/v3/index.json"
)

# Ensure output directory exists
if (!(Test-Path -Path $PackageOutputDir)) {
    New-Item -ItemType Directory -Path $PackageOutputDir | Out-Null
}

# Check required files
if (!(Test-Path -Path $NuSpecPath)) {
    Write-Error "Missing .nuspec file at: $NuSpecPath"
    exit 1
}
if (!(Test-Path -Path $NuGetExePath)) {
    Write-Error "nuget.exe not found at: $NuGetExePath"
    exit 1
}

# Auto-generate version if not provided
if (-not $Version) {
    $timestamp = Get-Date -Format "yyyyMMdd.HHmm"
    $Version = "1.0.$($timestamp.Substring(2))"
    Write-Host "Generated dynamic version: $Version"
}

# Inject version dynamically into nuspec
$nuspecContent = Get-Content $NuSpecPath
$updatedContent = $nuspecContent -replace '(<version>)(.*?)(</version>)', "`$1$Version`$3"
$tempNuspecPath = "$PackageOutputDir/TempPackage.nuspec"
$updatedContent | Set-Content -Path $tempNuspecPath -Encoding UTF8

# Build package
Write-Host "Packing NuGet package..."
& $NuGetExePath pack $tempNuspecPath `
    -OutputDirectory $PackageOutputDir `
    -BasePath "./NuGetPackageContent" `
    -Verbosity detailed

# Push package
$nupkg = Get-ChildItem -Path $PackageOutputDir -Filter "*.nupkg" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $nupkg) {
    Write-Error "Package not created. Check nuspec and content structure."
    exit 1
}

Write-Host "Pushing package: $($nupkg.Name)"
& $NuGetExePath push $nupkg.FullName `
    -ApiKey $ApiKey `
    -Source $NuGetSource `
    -NonInteractive `
    -Verbosity detailed

Write-Host "NuGet package published successfully: $($nupkg.Name)"
