<#
.SYNOPSIS
    PowerShell GUI to Export Installed Software Inventory (x86 and x64) in ANSI Format

.DESCRIPTION
    Exports installed software (32/64-bit) with Display Name, Version, Registry Path, and Architecture.
    Outputs a clean CSV using ANSI encoding for legacy compatibility.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    1.2.0 - June 19, 2025
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-InstalledPrograms {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($path in $registryPaths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
            [PSCustomObject]@{
                DisplayName       = $_.DisplayName
                DisplayVersion    = $_.DisplayVersion
                IdentifyingNumber = ($_.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::', '') -replace 'HKEY_LOCAL_MACHINE', 'HKLM:'
                Architecture      = if ($_.PSPath -match 'WOW6432Node') { '32-bit' } else { '64-bit' }
            }
        }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Export Installed Software"
$form.Size = New-Object System.Drawing.Size(420, 240)
$form.StartPosition = 'CenterScreen'

$radioDefault = New-Object System.Windows.Forms.RadioButton
$radioDefault.Text = "Use Documents Folder"
$radioDefault.Location = New-Object System.Drawing.Point(10, 10)
$radioDefault.Checked = $true
$form.Controls.Add($radioDefault)

$radioCustom = New-Object System.Windows.Forms.RadioButton
$radioCustom.Text = "Use Custom Folder"
$radioCustom.Location = New-Object System.Drawing.Point(10, 35)
$form.Controls.Add($radioCustom)

$labelPath = New-Object System.Windows.Forms.Label
$labelPath.Text = "Custom Output Path:"
$labelPath.Location = New-Object System.Drawing.Point(10, 60)
$labelPath.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($labelPath)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 80)
$textBox.Size = New-Object System.Drawing.Size(380, 20)
$textBox.Enabled = $false
$form.Controls.Add($textBox)

$radioCustom.Add_Click({ $textBox.Enabled = $true })
$radioDefault.Add_Click({ $textBox.Enabled = $false })

$btnOK = New-Object System.Windows.Forms.Button
$btnOK.Text = "OK"
$btnOK.Location = New-Object System.Drawing.Point(10, 120)
$btnOK.Size = New-Object System.Drawing.Size(75, 23)
$form.Controls.Add($btnOK)
$form.AcceptButton = $btnOK

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(100, 120)
$btnCancel.Size = New-Object System.Drawing.Size(75, 23)
$form.Controls.Add($btnCancel)
$form.CancelButton = $btnCancel

$btnOK.Add_Click({
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $fileName = "Installed-Inventory-SoftwaresList_$($env:COMPUTERNAME)_$timestamp.csv"

    if ($radioDefault.Checked) {
        $outputPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("MyDocuments"), $fileName)
    } elseif ($radioCustom.Checked -and -not [string]::IsNullOrWhiteSpace($textBox.Text)) {
        if (-not (Test-Path $textBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("The custom path is invalid or not found.", "Path Error", 'OK', 'Error')
            return
        }
        $outputPath = [System.IO.Path]::Combine($textBox.Text, $fileName)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a valid path.", "Error", 'OK', 'Error')
        return
    }

    $programs = Get-InstalledPrograms
    if ($programs.Count -gt 0) {
        try {
            # Create ANSI-encoded CSV manually
            $header = '"DisplayName","DisplayVersion","IdentifyingNumber","Architecture"'
            $lines = $programs | ForEach-Object {
                '"' + ($_.DisplayName -replace '"','""') + '","' +
                ($_.DisplayVersion -replace '"','""') + '","' +
                ($_.IdentifyingNumber -replace '"','""') + '","' +
                ($_.Architecture -replace '"','""') + '"'
            }

            $output = @($header) + $lines
            $output | Out-File -FilePath $outputPath -Encoding Default

            [System.Windows.Forms.MessageBox]::Show("Export completed:`n$outputPath", "Done", 'OK', 'Information')
            Start-Process "notepad.exe" -ArgumentList "`"$outputPath`""
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error writing to file: $_", "Export Error", 'OK', 'Error')
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("No installed software found.", "No Results", 'OK', 'Information')
    }

    $form.Close()
})

$btnCancel.Add_Click({ $form.Close() })

$form.Topmost = $true
$form.ShowDialog()

# End of script
