<#
.SYNOPSIS
  Build a smart WSUS index maintenance script (wsus-reindex-smart.sql) for SUSDB (WID).

.DESCRIPTION
  Prompts for:
    - Minimum page count (skip tiny indexes)
    - Reorganize threshold (%)  [low/medium]
    - Rebuild threshold (%)     [high]
    - Output .sql path (Save dialog; defaults provided)

  Generates a single-batch T-SQL script that:
    - REORGANIZE when Reorg% <= fragmentation < Rebuild% (with LOB_COMPACTION=ON)
    - REBUILD when fragmentation >= Rebuild% (MAXDOP=1; SORT_IN_TEMPDB=OFF)
    - Skips disabled, hypothetical, heaps, and non-rowstore indexes
    - Prints per-index progress; TRY/CATCH around each operation
    - Adds gentle settings: DEADLOCK_PRIORITY LOW, LOCK_TIMEOUT 15s
    - Tracks totals (rebuilds/reorganizes) and overall duration

.AUTHOR
  Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
  Last Updated: Sep 12, 2025
#>

# -------- Optional: hide console while the GUI is up --------
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
[Window]::Hide()

# -------- WinForms --------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Show-InputForm {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Build WSUS Reindex (Smart)"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width  = 520
    $form.Height = 260

    $font = New-Object System.Drawing.Font("Segoe UI", 9)

    $lblMinPages = New-Object System.Windows.Forms.Label
    $lblMinPages.Text = "Minimum Page Count:"
    $lblMinPages.Left = 20; $lblMinPages.Top = 20; $lblMinPages.Width = 180
    $lblMinPages.Font = $font

    $txtMinPages = New-Object System.Windows.Forms.TextBox
    $txtMinPages.Left = 220; $txtMinPages.Top = 18; $txtMinPages.Width = 100
    $txtMinPages.Text = "100"
    $txtMinPages.Font = $font

    $lblReorg = New-Object System.Windows.Forms.Label
    $lblReorg.Text = "Reorganize Threshold (%):"
    $lblReorg.Left = 20; $lblReorg.Top = 55; $lblReorg.Width = 180
    $lblReorg.Font = $font

    $txtReorg = New-Object System.Windows.Forms.TextBox
    $txtReorg.Left = 220; $txtReorg.Top = 53; $txtReorg.Width = 100
    $txtReorg.Text = "5"
    $txtReorg.Font = $font

    $lblRebuild = New-Object System.Windows.Forms.Label
    $lblRebuild.Text = "Rebuild Threshold (%):"
    $lblRebuild.Left = 20; $lblRebuild.Top = 90; $lblRebuild.Width = 180
    $lblRebuild.Font = $font

    $txtRebuild = New-Object System.Windows.Forms.TextBox
    $txtRebuild.Left = 220; $txtRebuild.Top = 88; $txtRebuild.Width = 100
    $txtRebuild.Text = "30"
    $txtRebuild.Font = $font

    $hint = New-Object System.Windows.Forms.Label
    $hint.Left = 20; $hint.Top = 120; $hint.Width = 470
    $hint.Text = "Guidance: REORGANIZE ~5–30%, REBUILD ≥30%. Small indexes (<100 pages) rarely benefit."
    $hint.Font = $font

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Generate SQL"
    $btnOk.Left = 180; $btnOk.Top = 160; $btnOk.Width = 140; $btnOk.Height = 30
    $btnOk.Font = $font
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $btnOk

    $form.Controls.AddRange(@(
        $lblMinPages,$txtMinPages,
        $lblReorg,$txtReorg,
        $lblRebuild,$txtRebuild,
        $hint,$btnOk
    ))

    if ($form.ShowDialog() -eq 'OK') {
        return @{
            MinPages   = [int]$txtMinPages.Text
            ReorgPct   = [double]$txtReorg.Text
            RebuildPct = [double]$txtRebuild.Text
        }
    }
    return $null
}

function Get-OutputPath {
    param([string]$DefaultPath = "C:\Logs-TEMP\WSUS-GUI\Scripts\wsus-reindex-smart.sql")

    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Title = "Save wsus-reindex-smart.sql"
    $dlg.Filter = "SQL files (*.sql)|*.sql|All files (*.*)|*.*"
    try {
        $dir = Split-Path -Path $DefaultPath -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $dlg.InitialDirectory = $dir
    } catch {}

    $dlg.FileName = [System.IO.Path]::GetFileName($DefaultPath)
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.FileName
    }
    return $null
}

function Build-ReindexSqlText {
    param(
        [Parameter(Mandatory)] [int]    $MinPages,
        [Parameter(Mandatory)] [double] $ReorgPct,
        [Parameter(Mandatory)] [double] $RebuildPct
    )
@"
-- wsus-reindex-smart.sql
-- Purpose: Rebuild or reorganize fragmented indexes in SUSDB (WID-safe).
-- Notes:
--  - REBUILD when fragmentation >= $RebuildPct% and page_count >= $MinPages
--  - REORGANIZE when $ReorgPct% <= fragmentation < $RebuildPct% and page_count >= $MinPages
--  - Skips disabled, hypothetical indexes, heaps, and non-rowstore
--  - Prints per-index progress; continues on errors
--  - Single batch (no GO), safe for sqlcmd

USE [SUSDB];
SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;
SET LOCK_TIMEOUT 15000;

DECLARE @t0 datetime2(0) = SYSUTCDATETIME();

PRINT 'WSUS smart index maintenance starting...';
PRINT 'Timestamp (UTC): ' + CONVERT(varchar(19), @t0, 120);

DECLARE
    @MinPages   int   = $MinPages,
    @RebuildPct float = $RebuildPct,
    @ReorgPct   float = $ReorgPct;

DECLARE
    @schema sysname,
    @table  sysname,
    @index  sysname,
    @frag   float,
    @pages  int,
    @sql    nvarchar(max),
    @op     char(1),   -- 'B' = REBUILD, 'O' = REORG
    @ops    int = 0,
    @opsB   int = 0,
    @opsO   int = 0;

DECLARE cur CURSOR FAST_FORWARD FOR
    SELECT
        s.name  AS SchemaName,
        t.name  AS TableName,
        i.name  AS IndexName,
        ips.avg_fragmentation_in_percent AS Frag,
        ips.page_count AS Pages
    FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') AS ips
    JOIN sys.indexes  AS i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
    JOIN sys.tables   AS t ON t.object_id   = i.object_id
    JOIN sys.schemas  AS s ON s.schema_id   = t.schema_id
    WHERE i.name IS NOT NULL
      AND i.is_disabled = 0
      AND i.is_hypothetical = 0
      AND i.type IN (1,2)               -- 1=CLUSTERED, 2=NONCLUSTERED (rowstore only)
      AND i.type_desc <> 'HEAP'
      AND ips.page_count >= @MinPages
    ORDER BY ips.page_count DESC, ips.avg_fragmentation_in_percent DESC;

OPEN cur;

FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = NULL;
    SET @op  = NULL;

    IF (@frag >= @RebuildPct)
    BEGIN
        SET @sql = N'ALTER INDEX ' + QUOTENAME(@index)
                 + N' ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                 + N' REBUILD WITH (SORT_IN_TEMPDB = OFF, MAXDOP = 1);';
        SET @op = 'B';
    END
    ELSE IF (@frag >= @ReorgPct)
    BEGIN
        SET @sql = N'ALTER INDEX ' + QUOTENAME(@index)
                 + N' ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                 + N' REORGANIZE WITH (LOB_COMPACTION = ON);';
        SET @op = 'O';
    END

    IF (@sql IS NOT NULL)
    BEGIN
        PRINT '>> ' + @schema + '.' + @table + ' [' + @index + ']  Frag='
            + CONVERT(varchar(32), @frag) + '%  Pages=' + CONVERT(varchar(32), @pages);
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
            SET @ops += 1;
            IF (@op = 'B') SET @opsB += 1;
            IF (@op = 'O') SET @opsO += 1;
            PRINT CASE WHEN @op='B' THEN '   OK (REBUILD)' ELSE '   OK (REORGANIZE)' END;
        END TRY
        BEGIN CATCH
            PRINT '   ERROR: ' + ERROR_MESSAGE();
        END CATCH
    END

    FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
END

CLOSE cur;
DEALLOCATE cur;

DECLARE @t1 datetime2(0) = SYSUTCDATETIME();
PRINT 'Totals — executed: ' + CONVERT(varchar(12), @ops)
    + ' | rebuilds: ' + CONVERT(varchar(12), @opsB)
    + ' | reorganizes: ' + CONVERT(varchar(12), @opsO);
PRINT 'Duration: ' + CONVERT(varchar(12), DATEDIFF(second, @t0, @t1)) + ' sec';
PRINT 'WSUS smart index maintenance completed.';
PRINT 'Timestamp (UTC): ' + CONVERT(varchar(19), @t1, 120);
"@
}

# -------- Main flow --------
try {
    $input = Show-InputForm
    if (-not $input) { [System.Windows.Forms.MessageBox]::Show("Operation canceled.","WSUS Reindex (Smart)",'OK','Information') | Out-Null; exit }

    # Validate thresholds
    if ($input.ReorgPct -lt 0 -or $input.RebuildPct -lt 0 -or $input.RebuildPct -le $input.ReorgPct) {
        [System.Windows.Forms.MessageBox]::Show("Invalid thresholds. Ensure: 0 <= Reorganize% < Rebuild%.","Validation",'OK','Error') | Out-Null
        exit 1
    }
    if ($input.MinPages -lt 1) {
        [System.Windows.Forms.MessageBox]::Show("Minimum page count must be at least 1.","Validation",'OK','Error') | Out-Null
        exit 1
    }

    $defaultOut = "C:\Logs-TEMP\WSUS-GUI\Scripts\wsus-reindex-smart.sql"
    $outFile = Get-OutputPath -DefaultPath $defaultOut
    if (-not $outFile) { [System.Windows.Forms.MessageBox]::Show("No file selected. Nothing was written.","WSUS Reindex (Smart)",'OK','Information') | Out-Null; exit }

    $sqlText = Build-ReindexSqlText -MinPages $input.MinPages -ReorgPct $input.ReorgPct -RebuildPct $input.RebuildPct

    $dir = Split-Path -Path $outFile -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

    # UTF8 without BOM is fine; BOM also fine for sqlcmd — choose plain UTF8
    Set-Content -Path $outFile -Value $sqlText -Encoding UTF8

    [System.Windows.Forms.MessageBox]::Show("Script generated:`r`n$outFile","Success",'OK','Information') | Out-Null
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Failed: $($_.Exception.Message)","Error",'OK','Error') | Out-Null
    exit 1
}

# End of script
