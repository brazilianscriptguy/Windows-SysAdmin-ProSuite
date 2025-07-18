<#
.SYNOPSIS
    Dynamically generates a NuSpec (.nuspec) file for NuGet packaging automation.

.DESCRIPTION
    Creates a NuGet specification file using standardized metadata, injecting the
    provided version, description, license, and content files dynamically.

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
    [string]$ZipPath = ""
)

# Validate .zip file existence
if (-not (Test-Path $ZipPath)) {
    Write-Error "The specified ZIP file '$ZipPath' does not exist."
    exit 1
}

# Output path setup
$OutputFile = Join-Path -Path $OutputPath -ChildPath "$PackageId.nuspec"

# Escape paths for XML
$escapedZipPath = $ZipPath -replace '\\', '/'

# Build XML
$packageXml = @"
<?xml version="1.0"?>
<package xmlns="http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd">
  <metadata>
    <id>$PackageId</id>
    <version>$Version</version>
    <authors>$Authors</authors>
    <description>$Description</description>
    <licenseUrl>$LicenseUrl</licenseUrl>
    <projectUrl>$ProjectUrl</projectUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <tags>powershell automation sysadmin blueteam ad gpo itsm $PackageId</tags>
    <!-- Optional Icon (if used later) -->
    <!-- <iconUrl>https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/raw/main/icon.png</iconUrl> -->
  </metadata>
  <files>
    <file src="$escapedZipPath" target="tools/$PackageId.zip" />
  </files>
</package>
"@

# Write file
[System.IO.File]::WriteAllText($OutputFile, $packageXml, [System.Text.Encoding]::UTF8)

Write-Host "✅ NuSpec generated successfully: $OutputFile"
