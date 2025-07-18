<#
.SYNOPSIS
    Generates a NuSpec (.nuspec) file for NuGet packaging automation.

.DESCRIPTION
    Dynamically creates a .nuspec file with metadata and ZIP mapping, supporting
    release notes injection and semantic version stripping.

.AUTHOR
    Luiz Hamilton - @brazilianscriptguy
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$PackageId,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Authors = 'Luiz Hamilton',
    [string]$Description = "PowerShell ToolSet Package for $PackageId.",
    [string]$LicenseUrl = "https://opensource.org/licenses/MIT",
    [string]$ProjectUrl = "https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite",
    [string]$OutputPath = ".",
    [string]$ZipPath = "",
    [string]$ReleaseNotesPath = ""
)

# Strip leading "v" from semantic version (e.g. v1.2.3 -> 1.2.3)
$SanitizedVersion = $Version -replace '^v', ''

# Ensure ZIP exists
if (-not (Test-Path $ZipPath)) {
    Write-Error "❌ The specified ZIP file '$ZipPath' does not exist."
    exit 1
}

# Read release notes (optional)
$ReleaseNotes = ""
if ($ReleaseNotesPath -and (Test-Path $ReleaseNotesPath)) {
    $ReleaseNotes = Get-Content -Raw -Path $ReleaseNotesPath
    $ReleaseNotes = $ReleaseNotes -replace '\r?\n', '&#x0A;'  # Preserve newlines in XML
}

# Escape for XML
$escapedZipPath = $ZipPath -replace '\\', '/'
$OutputFile = Join-Path -Path $OutputPath -ChildPath "$PackageId.nuspec"

# Build .nuspec XML
$packageXml = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$PackageId</id>
    <version>$SanitizedVersion</version>
    <authors>$Authors</authors>
    <description>$Description</description>
    <licenseUrl>$LicenseUrl</licenseUrl>
    <projectUrl>$ProjectUrl</projectUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>powershell automation sysadmin blueteam ad gpo itsm $PackageId</tags>
    $(if ($ReleaseNotes) { "<releaseNotes>$ReleaseNotes</releaseNotes>" })
  </metadata>
  <files>
    <file src="$escapedZipPath" target="tools/$PackageId.zip" />
  </files>
</package>
"@

# Write to file with UTF-8 encoding
[System.IO.File]::WriteAllText($OutputFile, $packageXml, [System.Text.Encoding]::UTF8)

Write-Host "✅ NuSpec generated: $OutputFile"
