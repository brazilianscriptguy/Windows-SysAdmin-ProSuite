<#
.SYNOPSIS
    Generates a wsus-reindex.sql file based on fragmented indexes in SUSDB (WID), with user-friendly GUI input.

.DESCRIPTION
    This script prompts the user via GUI to define:
    - Minimum fragmentation percentage
    - Minimum page count

    Based on this input, it queries the SUSDB (Windows Internal Database) to identify fragmented indexes 
    and generates a T-SQL script to rebuild them.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 15, 2025
#>

# Hide console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0);
    }
}
"@
[Window]::Hide()

# Load Windows Forms
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# GUI input form
function Show-InputForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS Index Rebuild Criteria"
    $form.Width = 430
    $form.Height = 280
    $form.StartPosition = "CenterScreen"

    # Minimum Fragmentation Label
    $label1 = New-Object System.Windows.Forms.Label
    $label1.Text = "Minimum Fragmentation (%):"
    $label1.Top = 30
    $label1.Left = 20
    $label1.Width = 180

    # Minimum Fragmentation Input
    $input1 = New-Object System.Windows.Forms.TextBox
    $input1.Top = 30
    $input1.Left = 220
    $input1.Width = 150
    $input1.Text = "10"

    # Description below fragmentation
    $desc1 = New-Object System.Windows.Forms.Label
    $desc1.Text = "Indexes with higher fragmentation are slower. Recommended: 10% or more."
    $desc1.Top = 55
    $desc1.Left = 20
    $desc1.Width = 360

    # Minimum Page Count Label
    $label2 = New-Object System.Windows.Forms.Label
    $label2.Text = "Minimum Page Count:"
    $label2.Top = 95
    $label2.Left = 20
    $label2.Width = 180

    # Minimum Page Count Input
    $input2 = New-Object System.Windows.Forms.TextBox
    $input2.Top = 95
    $input2.Left = 220
    $input2.Width = 150
    $input2.Text = "100"

    # Description below page count
    $desc2 = New-Object System.Windows.Forms.Label
    $desc2.Text = "Small indexes (e.g., less than 100 pages) don't benefit much from rebuilds."
    $desc2.Top = 120
    $desc2.Left = 20
    $desc2.Width = 380

    # Generate button
    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Generate SQL Script"
    $okButton.Width = 160
    $okButton.Height = 32
    $okButton.Left = 125
    $okButton.Top = 170
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton

    $form.Controls.AddRange(@($label1, $input1, $desc1, $label2, $input2, $desc2, $okButton))

    if ($form.ShowDialog() -eq "OK") {
        return @{
            Threshold = [int]$input1.Text
            PageCount = [int]$input2.Text
        }
    }
    return $null
}

# Write SQL file
function Write-SQLFile {
    param (
        [string[]]$RebuildCommands,
        [string]$FilePath
    )

    Set-Content -Path $FilePath -Value @"
USE SUSDB;
GO
"@ -Encoding UTF8

    foreach ($cmd in $RebuildCommands) {
        if ($cmd -match '^ALTER INDEX') {
            Add-Content -Path $FilePath -Value "$cmd`nGO" -Encoding UTF8
        }
    }
}

# Prompt for user input
$userInput = Show-InputForm
if (-not $userInput) {
    [System.Windows.Forms.MessageBox]::Show("Operation cancelled by user.", "WSUS Index Rebuild", 'OK', 'Information')
    exit
}

# Assign values
$thresholdFragmentation = $userInput.Threshold
$minPageCount = $userInput.PageCount
$outputSqlFile = "C:\Scripts\wsus-reindex.sql"
$namedPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"

# Validate sqlcmd availability
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    [System.Windows.Forms.MessageBox]::Show("sqlcmd.exe not found. Please install SQLCMD utilities or add it to PATH.", "Error", 'OK', 'Error')
    exit 1
}

# SQL query to fetch fragmented indexes
$sqlQuery = @"
SET NOCOUNT ON;
USE SUSDB;
SELECT 
    'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] REBUILD;' AS RebuildCommand
FROM 
    sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
JOIN 
    sys.indexes AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
JOIN 
    sys.tables AS t ON ips.object_id = t.object_id
JOIN 
    sys.schemas AS s ON t.schema_id = s.schema_id
WHERE 
    ips.page_count > $minPageCount
    AND ips.avg_fragmentation_in_percent >= $thresholdFragmentation
    AND i.name IS NOT NULL
    AND i.is_disabled = 0
ORDER BY 
    ips.avg_fragmentation_in_percent DESC;
"@

# Execute and process result
try {
    $results = & sqlcmd -S $namedPipe -E -d SUSDB -Q $sqlQuery -h -1 -W 2>&1

    if (-not $results -or $results.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No indexes found with more than $minPageCount pages and $thresholdFragmentation% fragmentation.", "Done", 'OK', 'Information')
        exit 0
    }

    Write-SQLFile -RebuildCommands $results -FilePath $outputSqlFile
    [System.Windows.Forms.MessageBox]::Show("Script generated successfully:`n$outputSqlFile", "Success", 'OK', 'Information')
} catch {
    [System.Windows.Forms.MessageBox]::Show("Error during SQLCMD execution:`n$_", "Error", 'OK', 'Error')
    exit 1
}

# End of script
