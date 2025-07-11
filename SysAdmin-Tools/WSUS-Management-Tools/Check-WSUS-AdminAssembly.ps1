<#
.SYNOPSIS
    Validates the presence of Microsoft.UpdateServices.Administration.dll in the Global Assembly Cache (GAC).

.DESCRIPTION
    This script checks whether the WSUS Administration Console assembly is loaded in the current PowerShell session,
    and attempts to load it from the Global Assembly Cache if missing. It also verifies that the expected GAC folder exists.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 11, 2025
#>

# Check if the WSUS Admin Assembly is already loaded
$assemblyLoaded = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.FullName -like 'Microsoft.UpdateServices.Administration*' }

if ($assemblyLoaded) {
    Write-Host "WSUS Administration assembly is already loaded in the current session."
    return
}

# Attempt to load it from GAC
try {
    [Reflection.Assembly]::Load("Microsoft.UpdateServices.Administration") | Out-Null
    Write-Host "WSUS Administration assembly loaded successfully from Global Assembly Cache (GAC)."
} catch {
    Write-Warning "Microsoft.UpdateServices.Administration.dll could not be loaded. The WSUS Administration Console may not be installed on this system."
    Write-Host ""
    Write-Host "Resolution:"
    Write-Host "Install the WSUS Administration Console using one of the following options:"
    Write-Host " - Via Server Manager:"
    Write-Host "     Add Roles and Features > Features > Windows Server Update Services > WSUS Tools"
    Write-Host " - Or via PowerShell:"
    Write-Host "     Install-WindowsFeature -Name UpdateServices-UI"
    exit 1
}

# Optional: Validate expected GAC path exists
$expectedGacPath = "$env:windir\Microsoft.NET\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration"

if (Test-Path $expectedGacPath) {
    Write-Host "Expected GAC path exists: $expectedGacPath"
} else {
    Write-Host "GAC folder not found at: $expectedGacPath. This may indicate an incomplete installation."
}

# End of script
