<#
.SYNOPSIS
    Troubleshoots spooler, print queue, printers, drivers and related GPO policies.

.DESCRIPTION
    This script performs several actions to restore proper printing system functionality:
    - Clears the print queue (PRINTERS)
    - Fixes the Print Spooler service dependency (RPCSS)
    - Removes installed printers (local or network)
    - Provides GUI for selective driver removal
    - Resets printer policies (PointAndPrint) and forces gpupdate
    - DEEP CLEANUP (optional): Clears spool caches (PRINTERS + SERVERS) and removes orphaned registry remnants (HKLM + optional HKU)
    - Generates a full log at C:\Logs-TEMP
    - Suitable for Startup GPO or technical support use

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last update: 2026-01-29
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==== LOGGING ====
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logDir = 'C:\Logs-TEMP'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$logPath = Join-Path $logDir "$scriptName.log"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logPath -Value "[$ts] [$Level] $Message"
}

Write-Log "==== Session started ===="

# ==== HIDE CONSOLE ====
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public static void Hide() { ShowWindow(GetConsoleWindow(), 0); }
}
"@ -ErrorAction Stop
    [Win]::Hide()
} catch {}

# ==== GUI BASE ====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Info {
    param([Parameter(Mandatory)][string]$msg)
    [void][System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Information',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
}

function Show-Error {
    param([Parameter(Mandatory)][string]$msg)
    [void][System.Windows.Forms.MessageBox]::Show(
        $msg,
        'Error',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Ask-YesNoCancel {
    param(
        [Parameter(Mandatory)][string]$msg,
        [string]$caption = 'Confirm'
    )
    return [System.Windows.Forms.MessageBox]::Show(
        $msg,
        $caption,
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

# ==== SERVICES ====
function Stop-Spooler {
    try {
        Stop-Service -Name Spooler -Force -ErrorAction Stop
        Write-Log "Print Spooler stopped successfully."
    } catch {
        Write-Log "Failed to stop Print Spooler: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Start-Spooler {
    try {
        Start-Service -Name Spooler -ErrorAction Stop
        Write-Log "Print Spooler started successfully."
    } catch {
        Write-Log "Failed to start Print Spooler: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Ensure-Spooler {
    try {
        $svc = Get-Service -Name Spooler -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Start-Spooler
            Start-Sleep -Seconds 2
        }
    } catch {
        Write-Log "Failed to ensure Print Spooler: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

# ==== REGISTRY HELPERS (Deep Cleanup) ====
function Test-RegistryPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $null = Get-Item -Path $Path -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Remove-RegistrySubKeysExceptNames {
    <#
      Removes subkeys under $Path, preserving any subkey whose name matches:
      - exact names in $PreserveNames (case-insensitive)
      - OR contains any fragment in $PreserveNameFragments (case-insensitive)
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$PreserveNames = @(),
        [string[]]$PreserveNameFragments = @()
    )

    if (-not (Test-RegistryPath -Path $Path)) {
        Write-Log "Registry path not found (skipping): $Path" 'WARN'
        return
    }

    try {
        $items = Get-ChildItem -Path $Path -ErrorAction Stop
        foreach ($item in $items) {
            $name = $item.PSChildName

            $preserve = $false
            if ($PreserveNames -and ($PreserveNames -contains $name)) { $preserve = $true }

            if (-not $preserve -and $PreserveNameFragments) {
                foreach ($frag in $PreserveNameFragments) {
                    if ([string]::IsNullOrWhiteSpace($frag)) { continue }
                    if ($name -like "*$frag*") { $preserve = $true; break }
                }
            }

            if ($preserve) {
                Write-Log "Preserved subkey: $Path\$name"
                continue
            }

            try {
                Remove-Item -Path $item.PSPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed subkey: $($item.PSPath)"
            } catch {
                Write-Log "Failed removing subkey: $($item.PSPath) :: $($_.Exception.Message)" 'WARN'
            }
        }
    } catch {
        Write-Log "Error enumerating subkeys in $Path :: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Clear-RegistryKeyValues {
    <#
      Removes all values under a key (keeps the key), optionally preserving values by fragments.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$PreserveValueFragments = @()
    )

    if (-not (Test-RegistryPath -Path $Path)) {
        Write-Log "Registry path not found (skipping): $Path" 'WARN'
        return
    }

    try {
        $props = Get-ItemProperty -Path $Path -ErrorAction Stop
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) { continue }

            $preserve = $false
            foreach ($frag in $PreserveValueFragments) {
                if ([string]::IsNullOrWhiteSpace($frag)) { continue }
                if ($p.Name -like "*$frag*") { $preserve = $true; break }
            }
            if ($preserve) {
                Write-Log "Preserved value: $Path :: $($p.Name)"
                continue
            }

            try {
                Remove-ItemProperty -Path $Path -Name $p.Name -Force -ErrorAction Stop
                Write-Log "Removed value: $Path :: $($p.Name)"
            } catch {
                Write-Log "Failed removing value: $Path :: $($p.Name) :: $($_.Exception.Message)" 'WARN'
            }
        }
    } catch {
        Write-Log "Error processing values in $Path :: $($_.Exception.Message)" 'ERROR'
        throw
    }
}

function Clear-SpoolFolders {
    param([string[]]$Folders = @('PRINTERS', 'SERVERS'))

    $spoolRoot = Join-Path $env:SystemRoot 'System32\spool'
    foreach ($f in $Folders) {
        $full = Join-Path $spoolRoot $f
        try {
            if (Test-Path $full) {
                Get-ChildItem -Path $full -Force -Recurse -ErrorAction SilentlyContinue |
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Write-Log "Cleared spool folder contents: $full"
            } else {
                Write-Log "Spool folder not found (skipping): $full" 'WARN'
            }
        } catch {
            Write-Log "Error clearing spool folder $full :: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Get-PreservePrinterNames {
    # Preserve current installed printers + common built-ins
    $builtIns = @(
        'Microsoft Print to PDF',
        'Microsoft XPS Document Writer',
        'OneNote (Desktop)',
        'Send To OneNote'
    )

    $names = New-Object System.Collections.Generic.List[string]
    try {
        $p = Get-Printer -ErrorAction Stop
        foreach ($x in $p) {
            if (-not [string]::IsNullOrWhiteSpace($x.Name)) { $null = $names.Add($x.Name) }
        }
    } catch {
        # fallback: not fatal, but logged
        Write-Log "Get-Printer failed (continuing with built-ins only): $($_.Exception.Message)" 'WARN'
    }

    foreach ($b in $builtIns) { $null = $names.Add($b) }

    # normalize: unique, case-insensitive
    $unique = $names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
    return , $unique
}

# ==== CLEAR PRINT QUEUE ====
function Clear-PrintQueue {
    try {
        Stop-Spooler
        $path = "$env:SystemRoot\System32\spool\PRINTERS\*"
        if (Test-Path $path) {
            Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
            Write-Log "Print queue files deleted (PRINTERS)."
        } else {
            Write-Log "Queue path not found (skipping): $path" 'WARN'
        }
        Start-Spooler
        Show-Info "Print queue successfully cleared."
    } catch {
        Write-Log "Error while clearing queue: $($_.Exception.Message)" 'ERROR'
        Show-Error "Error clearing print queue.`n$($_.Exception.Message)"
    }
}

# ==== FIX SPOOLER DEPENDENCY ====
function Reset-SpoolerDependency {
    try {
        Stop-Spooler
        sc.exe config spooler depend= RPCSS | Out-Null
        Start-Spooler
        Write-Log "Spooler dependency reset successfully."
        Show-Info "Spooler dependency has been reset."
    } catch {
        Write-Log "Error resetting dependency: $($_.Exception.Message)" 'ERROR'
        Show-Error "Error resetting spooler dependency.`n$($_.Exception.Message)"
    }
}

# ==== REMOVE ALL PRINTERS ====
function Remove-AllPrinters {
    try {
        Ensure-Spooler
        $printers = Get-CimInstance -Class Win32_Printer

        if (-not $printers) {
            Show-Info "No printers found."
            return
        }

        foreach ($printer in $printers) {
            $name = $printer.Name
            try {
                Write-Log "Trying to remove printer: $name"

                if ($name -match "^\\\\") {
                    rundll32 printui.dll, PrintUIEntry /dn /n "$name"
                    Start-Sleep -Milliseconds 500
                }

                Remove-Printer -Name "$name" -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 500

                $stillExists = Get-CimInstance -Class Win32_Printer -Filter "Name='$name'" -ErrorAction SilentlyContinue
                if ($null -eq $stillExists) {
                    Write-Log "Printer removed: $name"
                } else {
                    Write-Log "Printer still present after removal attempt: $name" 'WARN'
                }
            } catch {
                Write-Log "Error removing printer ${name}: $($_.Exception.Message)" 'ERROR'
            }
        }
        Show-Info "Printer removal completed. Check the log for details."
    } catch {
        Write-Log "General failure removing printers: $($_.Exception.Message)" 'ERROR'
        Show-Error "Error removing printers.`n$($_.Exception.Message)"
    }
}

# ==== REMOVE DRIVERS ====
function Remove-PrinterDrivers-Interactive {
    try {
        Ensure-Spooler
        $drivers = Get-PrinterDriver | Sort-Object Name
        if (-not $drivers) { Show-Info "No printer drivers found."; return }

        $form = New-Object Windows.Forms.Form
        $form.Text = "Remove Printer Drivers"
        $form.Size = New-Object Drawing.Size(600, 500)
        $form.StartPosition = 'CenterScreen'

        $listBox = New-Object Windows.Forms.CheckedListBox
        $listBox.Location = '10,10'
        $listBox.Size = New-Object Drawing.Size(560, 380)
        foreach ($d in $drivers) { [void]$listBox.Items.Add($d.Name) }
        $form.Controls.Add($listBox)

        $btnRemove = New-Object Windows.Forms.Button
        $btnRemove.Text = "Remove Selected"
        $btnRemove.Size = New-Object Drawing.Size(180, 30)
        $btnRemove.Location = '10,410'
        $btnRemove.Add_Click({
                foreach ($item in $listBox.CheckedItems) {
                    try {
                        Write-Log "Removing driver: ${item}"
                        Remove-PrinterDriver -Name "${item}" -ErrorAction SilentlyContinue
                    } catch {
                        Write-Log "Error removing driver ${item}: $($_.Exception.Message)" "ERROR"
                    }
                }
                Show-Info "Driver removal completed."
                $form.Close()
            })
        $form.Controls.Add($btnRemove)

        $btnCancel = New-Object Windows.Forms.Button
        $btnCancel.Text = "Cancel"
        $btnCancel.Size = New-Object Drawing.Size(120, 30)
        $btnCancel.Location = '420,410'
        $btnCancel.Add_Click({ $form.Close() })
        $form.Controls.Add($btnCancel)

        [void]$form.ShowDialog()
    } catch {
        Write-Log "Error in driver interface: $($_.Exception.Message)" 'ERROR'
        Show-Error "Error loading driver interface.`n$($_.Exception.Message)"
    }
}

# ==== RESET PRINTER POLICIES ====
function Reset-PrinterPolicies {
    try {
        Write-Log "Deleting PointAndPrint policy key..."
        reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint" /f | Out-Null
        Write-Log "PointAndPrint policy key deleted."

        Write-Log "Running gpupdate /force (silent)..."
        $gpOut = & gpupdate /force /target:computer 2>&1
        Write-Log "gpupdate output:`n$gpOut"

        Show-Info "Printer policies have been reset and GPO updated."
    } catch {
        Write-Log "Error resetting printer policies: $($_.Exception.Message)" 'ERROR'
        Show-Error "Error resetting printer policies.`n$($_.Exception.Message)"
    }
}

# ==== DEEP CLEANUP (Registry + Spool Caches) ====
function Invoke-DeepPrintCleanup {
    try {
        $confirm = Ask-YesNoCancel -msg @"
DEEP CLEANUP will:
- Stop Print Spooler
- Clear spool caches: PRINTERS and SERVERS
- Remove ORPHANED printer registry remnants under HKLM Print keys
- Optionally clean per-user remnants under HKEY_USERS (if you choose next)

This is a RESET operation and may remove stale printer mappings.
Proceed?
"@ -caption "Deep Cleanup"

        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Deep Cleanup canceled by user."
            return
        }

        $doHKU = Ask-YesNoCancel -msg @"
Include per-user cleanup (HKEY_USERS)?
This may remove cached user printer connections / devmodes for local profiles.
Recommended only when fixing ghost printers.
"@ -caption "Deep Cleanup (HKU)"

        if ($doHKU -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Log "Deep Cleanup canceled during HKU prompt."
            return
        }

        $includeHKU = ($doHKU -eq [System.Windows.Forms.DialogResult]::Yes)

        Write-Log "Deep Cleanup started. IncludeHKU=$includeHKU"

        Stop-Spooler
        Clear-SpoolFolders -Folders @('PRINTERS', 'SERVERS')

        # Preserve installed printers + built-ins
        $preserveNames = Get-PreservePrinterNames

        # Additional fragments to preserve by convention (optional)
        $preserveFragments = @(
            'Microsoft Print',
            'OneNote',
            'PDF',
            'XPS'
        )

        # --- HKLM print keys ---
        $printKeys = @(
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Connections",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Printers",
            "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\V4 Connections"
        )

        foreach ($k in $printKeys) {
            Write-Log "Deep Cleanup HKLM processing: $k"
            Remove-RegistrySubKeysExceptNames -Path $k -PreserveNames $preserveNames -PreserveNameFragments $preserveFragments
        }

        # --- CSR Provider (Deep Reset behavior) ---
        $csrPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\Providers\Client Side Rendering Print Provider"
        if (Test-RegistryPath -Path $csrPath) {
            Write-Log "Deep Cleanup CSR Provider processing: $csrPath"
            # Keep Servers key; remove other subkeys
            Remove-RegistrySubKeysExceptNames -Path $csrPath -PreserveNames @('Servers') -PreserveNameFragments @()

            $serversPath = Join-Path $csrPath 'Servers'
            if (Test-RegistryPath -Path $serversPath) {
                Write-Log "Deep Cleanup CSR Provider: clearing Servers contents: $serversPath"
                # Remove subkeys inside Servers (deep reset)
                Remove-RegistrySubKeysExceptNames -Path $serversPath -PreserveNames @() -PreserveNameFragments @()
                # Remove values inside Servers
                Clear-RegistryKeyValues -Path $serversPath -PreserveValueFragments @()
            }
        } else {
            Write-Log "CSR Provider path not found (skipping): $csrPath" 'WARN'
        }

        # --- Optional HKU cleanup ---
        if ($includeHKU) {
            Write-Log "Deep Cleanup HKU started."
            $userPreserveFragments = @('Microsoft', 'OneNote', 'PDF', 'XPS', 'scanner', 'Scan')

            try {
                $users = Get-ChildItem -Path "Registry::HKEY_USERS" -ErrorAction Stop
                foreach ($user in $users) {
                    if ($user.PSChildName -like "*Classes") { continue }
                    if ($user.PSChildName -in @(".DEFAULT", "S-1-5-18", "S-1-5-19", "S-1-5-20")) { continue }

                    $userPrintersPath = Join-Path -Path $user.PSPath -ChildPath "Printers"
                    if (-not (Test-RegistryPath -Path $userPrintersPath)) { continue }

                    Write-Log "Deep Cleanup HKU processing user: $($user.PSChildName)"

                    $subkeysToClean = @("ConvertUserDevModesCount", "DevModePerUser", "DevModes2", "Connections")
                    foreach ($subkey in $subkeysToClean) {
                        $cleanPath = Join-Path -Path $userPrintersPath -ChildPath $subkey
                        if (Test-RegistryPath -Path $cleanPath) {
                            Write-Log "Deep Cleanup HKU cleaning: $cleanPath"
                            # preserve installed printers + common fragments
                            Remove-RegistrySubKeysExceptNames -Path $cleanPath -PreserveNames $preserveNames -PreserveNameFragments $userPreserveFragments
                        }
                    }
                }
            } catch {
                Write-Log "Deep Cleanup HKU failed: $($_.Exception.Message)" 'WARN'
            }
        }

        Start-Spooler
        Write-Log "Deep Cleanup completed successfully."
        Show-Info "Deep Cleanup completed.`nCheck the log at:`n$logPath"
    } catch {
        Write-Log "Deep Cleanup failed: $($_.Exception.Message)" 'ERROR'
        try { Start-Spooler } catch {}
        Show-Error "Deep Cleanup failed.`n$($_.Exception.Message)"
    }
}

# ==== MAIN GUI ====
$formMain = New-Object System.Windows.Forms.Form
$formMain.Text = "Printing Troubleshooter"
$formMain.Size = New-Object System.Drawing.Size(600, 440)
$formMain.StartPosition = "CenterScreen"

$btn1 = New-Object System.Windows.Forms.Button
$btn1.Text = "1. Clear Print Queue"
$btn1.Location = New-Object System.Drawing.Point(20, 40)
$btn1.Size = New-Object System.Drawing.Size(540, 40)
$btn1.Add_Click({ Clear-PrintQueue })
$formMain.Controls.Add($btn1)

$btn2 = New-Object System.Windows.Forms.Button
$btn2.Text = "2. Fix Spooler Dependency"
$btn2.Location = New-Object System.Drawing.Point(20, 90)
$btn2.Size = New-Object System.Drawing.Size(540, 40)
$btn2.Add_Click({ Reset-SpoolerDependency })
$formMain.Controls.Add($btn2)

$btn3 = New-Object System.Windows.Forms.Button
$btn3.Text = "3. Remove All Printers"
$btn3.Location = New-Object System.Drawing.Point(20, 140)
$btn3.Size = New-Object System.Drawing.Size(540, 40)
$btn3.Add_Click({ Remove-AllPrinters })
$formMain.Controls.Add($btn3)

$btn4 = New-Object System.Windows.Forms.Button
$btn4.Text = "4. Remove Selected Drivers"
$btn4.Location = New-Object System.Drawing.Point(20, 190)
$btn4.Size = New-Object System.Drawing.Size(540, 40)
$btn4.Add_Click({ Remove-PrinterDrivers-Interactive })
$formMain.Controls.Add($btn4)

$btn5 = New-Object System.Windows.Forms.Button
$btn5.Text = "5. Reset Printer Policies (PointAndPrint)"
$btn5.Location = New-Object System.Drawing.Point(20, 240)
$btn5.Size = New-Object System.Drawing.Size(540, 40)
$btn5.Add_Click({ Reset-PrinterPolicies })
$formMain.Controls.Add($btn5)

$btn6 = New-Object System.Windows.Forms.Button
$btn6.Text = "6. Deep Cleanup (Registry + Spool Caches)"
$btn6.Location = New-Object System.Drawing.Point(20, 290)
$btn6.Size = New-Object System.Drawing.Size(540, 40)
$btn6.Add_Click({ Invoke-DeepPrintCleanup })
$formMain.Controls.Add($btn6)

$formMain.Add_FormClosing({ Write-Log "==== Session ended ====" })
[void]$formMain.ShowDialog()

# ==== END OF SCRIPT ====
