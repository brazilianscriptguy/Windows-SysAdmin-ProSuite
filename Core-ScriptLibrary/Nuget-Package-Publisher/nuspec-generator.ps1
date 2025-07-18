<#
.SYNOPSIS
    Generates a NuSpec (.nuspec) file for NuGet packaging automation.

.DESCRIPTION
    Dynamically creates a .nuspec file with metadata and ZIP mapping, supporting
    release notes injection and semantic versioning.

.AUTHOR
    Luiz Hamilton - @brazilianscriptguy
#>

param (
    [Parameter(Mandatory)]
    [string]$PackageId,

    [Parameter(Mandatory)]
    [string]$Version,

    [Parameter(Mandatory)]
    [string]$ZipPath,

    [Parameter(Mandatory)]
    [string]$ReleaseNotesPath,

    [Parameter(Mandatory)]
    [string]$OutputPath
)

# --- Input Validation ---
if (-not (Test-Path $ZipPath)) {
    Write-Error "❌ ZipPath '$ZipPath' not found."
    exit 1
}
if (-not (Test-Path $ReleaseNotesPath)) {
    Write-Error "❌ Release notes file '$ReleaseNotesPath' not found."
    exit 1
}

# --- Prepare Values ---
$nuspecFile = Join-Path $OutputPath "$PackageId.nuspec"
$releaseNotes = Get-Content -Raw -Path $ReleaseNotesPath -Encoding UTF8
$releaseNotesEscaped = [System.Security.SecurityElement]::Escape($releaseNotes)
$cleanZipName = [System.IO.Path]::GetFileName($ZipPath)

# --- Compose .nuspec Content ---
$nuspecContent = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>$PackageId</id>
    <version>$Version</version>
    <authors>Luiz Hamilton</authors>
    <owners>BrazilianScriptGuy</owners>
    <license type="expression">MIT</license>
    <projectUrl>https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite</projectUrl>
    <iconUrl>https://raw.githubusercontent.com/brazilianscriptguy/Windows-SysAdmin-ProSuite/main/icon.png</iconUrl>
    <description>A specialized toolkit for Windows Server and Workstation administration with PowerShell & VBScript automation.</description>
    <summary>Complete Windows SysAdmin Toolkit for Enterprise Environments</summary>
    <releaseNotes>$releaseNotesEscaped</releaseNotes>
    <tags>powershell windows-server activedirectory itsm blueteam evtx gpo automation toolkit forensics ldap sso workstation</tags>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <repository type="git" url="https://github.com/brazilianscriptguy/Windows-SysAdmin-ProSuite" branch="main" />
  </metadata>

  <files>
    <file src="$ZipPath" target="content/$cleanZipName" />
  </files>
</package>
"@

# --- Write .nuspec File ---
$nuspecContent | Set-Content -Path $nuspecFile -Encoding UTF8

Write-Host "✔ .nuspec file generated at: $nuspecFile"
