
<#
.SYNOPSIS
Complete cleanup of WinGet / DesktopAppInstaller environment for Windows Server 2019.

.DESCRIPTION
Removes artifacts created by previous WinGet installation attempts including:
- Portable winget deployments
- DesktopAppInstaller package
- WinGet modules
- PATH entries
- Setup staging directories
- Temporary dependencies

Safe to run multiple times (idempotent).

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
2026-03-06
#>

param(
    [string]$LogDir = "C:\Logs-TEMP",
    [string]$PortableDir = "C:\Program Files\winget",
    [string]$SetupRoot = "C:\ProgramData\WinGet-Setup"
)

$ErrorActionPreference="Continue"

if(!(Test-Path $LogDir)){New-Item $LogDir -ItemType Directory | Out-Null}
$LogPath="$LogDir\winget-cleanup.log"

function WriteLog($m){
 $t=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
 Add-Content $LogPath "[INFO] [$t] $m"
}

WriteLog "Starting WinGet cleanup"

if(Test-Path $PortableDir){
 WriteLog "Removing $PortableDir"
 Remove-Item $PortableDir -Recurse -Force -ErrorAction SilentlyContinue
}

Get-ChildItem "C:\Program Files" -Filter "winget.bak*" -ErrorAction SilentlyContinue | ForEach-Object{
 WriteLog "Removing backup $($_.FullName)"
 Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

WriteLog "Removing DesktopAppInstaller"
Get-AppxPackage -AllUsers Microsoft.DesktopAppInstaller | ForEach-Object{
 Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}

$mods=@(
"C:\Program Files\WindowsPowerShell\Modules\Microsoft.WinGet.Client",
"C:\Program Files\PowerShell\Modules\Microsoft.WinGet.Client"
)

foreach($m in $mods){
 if(Test-Path $m){
  WriteLog "Removing module $m"
  Remove-Item $m -Recurse -Force -ErrorAction SilentlyContinue
 }
}

if(Test-Path $SetupRoot){
 WriteLog "Removing staging $SetupRoot"
 Remove-Item $SetupRoot -Recurse -Force -ErrorAction SilentlyContinue
}

WriteLog "Cleaning PATH"

$p=[Environment]::GetEnvironmentVariable("Path","Machine").Split(";")
$n=@()

foreach($e in $p){
 if($e -match "winget"){WriteLog "Removing PATH entry $e"}
 elseif($e -match "WindowsApps"){WriteLog "Removing PATH entry $e"}
 else{$n+=$e}
}

[Environment]::SetEnvironmentVariable("Path",($n -join ";"),"Machine")

WriteLog "Cleanup finished"
Write-Host ""
Write-Host "WinGet environment cleaned."
Write-Host "Reboot the server before reinstalling."
Write-Host ""
