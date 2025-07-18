<#
.SYNOPSIS
    Generates a NuSpec (.nuspec) file for NuGet packaging automation.

.DESCRIPTION
    Used in CI pipelines to dynamically create .nuspec files based on a standard template.
    Injects metadata like ID, version, author, license, and package contents.

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

# Ensure output path exists
$OutputFile = Join-Path -Path $OutputPath -ChildPath "$PackageId.nuspec"

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
    <tags>powershell automation admin $PackageId</tags>
  </metadata>
  <files>
    <file src="$ZipPath" target="tools\$PackageId.zip" />
  </files>
</package>
"@

$packageXml | Out-File -Encoding UTF8 -FilePath $OutputFile -Force

Write-Host "Generated: $OutputFile"
