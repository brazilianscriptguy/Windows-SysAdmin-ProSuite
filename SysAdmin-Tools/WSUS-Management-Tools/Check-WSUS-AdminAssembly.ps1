<#
.SYNOPSIS
    Validates and loads Microsoft.UpdateServices.Administration.dll (WSUS Admin API).

.DESCRIPTION
    - Prefers Import-Module UpdateServices (works when WSUS Management Tools are installed).
    - If the module isn't available, attempts to load the WSUS Admin assembly from the GAC.
    - Searches common GAC roots on modern and legacy systems.
    - Falls back to a known explicit path if provided.
    - Uses small WinForms message boxes for guidance/diagnostics.
    - Hides the console window (comment out [Window]::Hide() while debugging).

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: Sep 15, 2025
#>

# ---------------- Console (hidden) ----------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() { var handle = GetConsoleWindow(); ShowWindow(handle, 0); }
}
"@
[Window]::Hide()  # <-- comment this line while debugging to keep the console visible

# ---------------- UI + utils ----------------
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")] [string]$Level = "INFO"
    )
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$stamp] [$Level] $Message"
}

function Show-MessageBox {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = "WSUS Administration Assembly Check",
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon) | Out-Null
}

# If you want to pin a known path (kept from your original script).
$ExplicitAssemblyPath = "C:\Windows\Microsoft.Net\assembly\GAC_MSIL\Microsoft.UpdateServices.Administration\v4.0_4.0.0.0__31bf3856ad364e35\Microsoft.UpdateServices.Administration.dll"

# Common GAC roots on modern/legacy systems
# Common GAC roots on modern/legacy systems
$GacRoots = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL')  # .NET 4+ (Win10/2016+)
    (Join-Path $env:WINDIR 'assembly\GAC_MSIL')                 # legacy view
)

# ---------------- Helper: Is Assembly Loaded? ----------------
function Test-AssemblyLoaded {
    [OutputType([bool])]
    param([string]$PartialName = "Microsoft.UpdateServices.Administration")
    return [AppDomain]::CurrentDomain.GetAssemblies().FullName -match [regex]::Escape($PartialName)
}

# ---------------- Try 1: Import-Module UpdateServices ----------------
try {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        # PowerShell 7+: use Windows PowerShell compatibility shim if available
        Import-Module -Name UpdateServices -UseWindowsPowerShell -ErrorAction Stop
    } else {
        Import-Module -Name UpdateServices -ErrorAction Stop
    }

    if (Test-AssemblyLoaded) {
        Write-Log "WSUS Administration assembly available via UpdateServices module." -Level INFO
        Show-MessageBox -Message "WSUS Administration assembly is available (loaded with UpdateServices module)."
        return
    }
} catch {
    Write-Log "UpdateServices module not available or failed to load: $($_.Exception.Message)" -Level WARNING
}

# ---------------- Try 2: Load from GAC (by partial name) ----------------
try {
    $asm = [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")
    if ($asm -and (Test-AssemblyLoaded)) {
        Write-Log "WSUS Administration assembly loaded from GAC via partial name." -Level INFO
        Show-MessageBox -Message "WSUS Administration assembly loaded from the Global Assembly Cache (GAC)."
        return
    } else {
        throw "LoadWithPartialName returned null."
    }
} catch {
    Write-Log "Could not load WSUS assembly by partial name: $($_.Exception.Message)" -Level WARNING
}

# ---------------- Try 3: Probe known GAC folders and Add-Type ----------------
$foundPath = $null
foreach ($root in $GacRoots) {
    if (-not (Test-Path $root)) { continue }
    try {
        $candidate = Get-ChildItem -Path $root -Recurse -Filter "Microsoft.UpdateServices.Administration.dll" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) { $foundPath = $candidate.FullName; break }
    } catch { }
}

if (-not $foundPath -and (Test-Path $ExplicitAssemblyPath)) {
    $foundPath = $ExplicitAssemblyPath
}

if ($foundPath) {
    try {
        Add-Type -Path $foundPath -ErrorAction Stop
        if (Test-AssemblyLoaded) {
            Write-Log "WSUS Administration assembly loaded from: $foundPath" -Level INFO
            Show-MessageBox -Message "WSUS Administration assembly loaded from:`n$foundPath"
            return
        } else {
            throw "Add-Type succeeded but assembly not visible in current AppDomain."
        }
    } catch {
        $msg = "Failed to load WSUS assembly from:`n$foundPath`n`nDetails: $($_.Exception.Message)"
        Write-Log $msg -Level ERROR
        Show-MessageBox -Message $msg -Icon 'Error'
        exit 1
    }
}

# ---------------- Final guidance (not found) ----------------
$help = @"
WSUS Administration assembly was not found.

Install WSUS Management Tools (Administration Console) using one of the following:

1) Server Manager
   - Add Roles and Features ➜ Features ➜ Windows Server Update Services ➜ WSUS Tools

2) PowerShell (Windows Server)
   Install-WindowsFeature -Name UpdateServices-UI

3) Windows Client (RSAT on Windows 10/11)
   DISM /Online /Enable-Feature /FeatureName:Rsat.WSUS.Tools~~~~0.0.1.0 /All

After installing, re-run this script.
"@

Write-Log "WSUS Administration assembly not found in GAC paths or explicit path." -Level ERROR
Show-MessageBox -Message $help -Icon 'Error'
exit 1

# End of script
