<#
.SYNOPSIS
    Generates WSUS SUSDB (WID) maintenance SQL scripts (TJAP working structure + Classic option).

.DESCRIPTION
    Generates up to three SQL files:

    1) wsus-reindex-smart.sql  (scan ALL indexes)
       - Cursor over dm_db_index_physical_stats(DB_ID('SUSDB'), ... 'LIMITED')
       - REBUILD when Frag >= RebuildPct
       - REORGANIZE when Frag >= ReorgPct
       - Skips small indexes via MinPages
       - Skips disabled indexes and heaps

    2) wsus-verify-fragmentation.sql (report + recommendations)
       - Recommendation columns + filters

    3) wsusdbmaintenance-classic.sql (optional)
       - “Classic” WSUS maintenance:
           - Targets known high-churn WSUS tables
           - Fill-factor overrides for hot tables (configurable)
           - Rebuild/Reorg based on thresholds
           - sp_updatestats at the end

    Notes:
      - This script ONLY generates SQL files. Execution is performed elsewhere (sqlcmd/SSMS).
      - Thresholds/MinPages are embedded into the generated SQL text.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: 2026-02-05  -03
    Version: 1.70 (Smart GUI + robust path selection + fixes array-math GUI bug)
#>

param(
    # Embedded thresholds/pages for Smart + Verify + Classic (where applicable)
    [ValidateRange(1, 1000000)]
    [int]$MinPages = 100,

    [ValidateRange(0, 99)]
    [int]$ReorgPct = 5,

    [ValidateRange(1, 100)]
    [int]$RebuildPct = 30,

    # Output defaults (used by NoGui mode; GUI can override)
    [string]$OutputDirectory = "C:\Logs-TEMP\WSUS-GUI\Scripts",
    [string]$SmartFileName   = "wsus-reindex-smart.sql",
    [string]$VerifyFileName  = "wsus-verify-fragmentation.sql",
    [string]$ClassicFileName = "wsusdbmaintenance-classic.sql",

    # What to generate (used by NoGui mode; GUI can override)
    [switch]$GenerateSmart = $true,
    [switch]$GenerateVerifyFragmentation = $true,
    [switch]$GenerateClassic = $false,

    # UX
    [switch]$NoGui,
    [switch]$Quiet,
    [switch]$ShowConsole
)

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ----------------- WinForms bootstrap -----------------
Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing       | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------- Logging (single log per run) -----------------
$scriptName = [IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$rootDir    = "C:\Logs-TEMP\WSUS-GUI"
$logDir     = Join-Path $rootDir "Logs"
$null       = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
$logPath    = Join-Path $logDir "$scriptName.log"

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO","WARNING","ERROR","DEBUG")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    try { Add-Content -Path $logPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch {}
    if (-not $Quiet) {
        try { Write-Host $line } catch {}
    }
}

function Show-Ui {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Title = "WSUS SQL Generator",
        [ValidateSet("Information","Warning","Error")][string]$Icon = "Information"
    )
    if ($Quiet -or $NoGui) { return }
    $mbIcon = [System.Windows.Forms.MessageBoxIcon]::$Icon
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $mbIcon
    ) | Out-Null
}

# ----------------- Console visibility (optional) -----------------
function Set-ConsoleVisibility {
    param([bool]$Visible)

    try {
        if (-not ("WinConsole" -as [type])) {
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinConsole {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction Stop
        }

        $h = [WinConsole]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) {
            $cmd = if ($Visible) { 5 } else { 0 } # 5=SHOW, 0=HIDE
            [void][WinConsole]::ShowWindow($h, $cmd)
        }
    } catch {
        # best-effort only
    }
}

if (-not $ShowConsole) { Set-ConsoleVisibility -Visible:$false }

# ----------------- File helpers -----------------
function Ensure-Dir {
    param([Parameter(Mandatory=$true)][string]$DirectoryPath)
    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        $null = New-Item -Path $DirectoryPath -ItemType Directory -Force -ErrorAction Stop
    }
}

function Join-SafePath {
    param(
        [Parameter(Mandatory=$true)][string]$DirectoryPath,
        [Parameter(Mandatory=$true)][string]$FileName
    )
    $safeName = ($FileName -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw "Invalid file name." }
    return (Join-Path -Path $DirectoryPath -ChildPath $safeName)
}

function Select-FolderGui {
    param([Parameter(Mandatory=$true)][string]$DefaultPath)

    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Select output folder for generated .sql files"
    $dlg.SelectedPath = $DefaultPath

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }
    return $null
}

# ----------------- SQL builders (Smart + Verify: match your working structure) -----------------
function Build-ReindexSqlText {
    param([int]$MinPages,[int]$ReorgPct,[int]$RebuildPct)

@"
USE SUSDB;
GO
SET NOCOUNT ON;

DECLARE @schema sysname, @table sysname, @index sysname, @sql nvarchar(max);

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
  AND ips.page_count >= $MinPages       -- avoids useless work
  AND i.is_disabled = 0
  AND i.type_desc <> 'HEAP'             -- heaps do not support REBUILD
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN cur;
DECLARE @frag float, @pages int;

FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @frag >= $RebuildPct
        SET @sql = N'ALTER INDEX ['+@index+'] ON ['+@schema+'].['+@table+'] REBUILD WITH (SORT_IN_TEMPDB = OFF, MAXDOP = 1);';
    ELSE IF @frag >= $ReorgPct
        SET @sql = N'ALTER INDEX ['+@index+'] ON ['+@schema+'].['+@table+'] REORGANIZE;';
    ELSE
        SET @sql = NULL; -- ignore

    IF @sql IS NOT NULL
    BEGIN
        PRINT CONCAT('>> ', @schema, '.', @table, ' [', @index, ']  Frag=', CONVERT(varchar(10), @frag), '%  Pages=', @pages);
        EXEC sp_executesql @sql;
    END

    FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
END

CLOSE cur; DEALLOCATE cur;
GO
"@
}

function Build-VerifyFragmentationSqlText {
    param([int]$MinPages,[int]$ReorgPct,[int]$RebuildPct)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $rb  = [string]::Format($inv, "{0:0.0}", [double]$RebuildPct)
    $rg  = [string]::Format($inv, "{0:0.0}", [double]$ReorgPct)

@"
USE [SUSDB];
GO

DECLARE @MinPages   int   = $MinPages;
DECLARE @RebuildPct float = $rb;
DECLARE @ReorgPct   float = $rg;

SELECT
    s.[name]  AS SchemaName,
    t.[name]  AS TableName,
    i.[name]  AS IndexName,
    i.type_desc AS IndexType,
    ips.partition_number AS PartitionNumber,
    ips.page_count       AS PageCount,
    ROUND(CAST(ips.avg_fragmentation_in_percent AS decimal(9,4)), 2) AS FragmentationPercent,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= @RebuildPct THEN 'High'
        WHEN ips.avg_fragmentation_in_percent >= @ReorgPct   THEN 'Medium'
        ELSE 'Low'
    END AS FragmentationLevel,
    CASE
        WHEN ips.page_count < @MinPages THEN 'NONE (small index)'
        WHEN ips.avg_fragmentation_in_percent >= @RebuildPct THEN 'REBUILD'
        WHEN ips.avg_fragmentation_in_percent >= @ReorgPct   THEN 'REORGANIZE'
        ELSE 'NONE'
    END AS MaintenanceRecommendation
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') AS ips
JOIN sys.indexes AS i
  ON ips.[object_id] = i.[object_id]
 AND ips.index_id    = i.index_id
JOIN sys.tables AS t
  ON i.[object_id] = t.[object_id]
JOIN sys.schemas AS s
  ON t.[schema_id] = s.[schema_id]
WHERE
    i.[name] IS NOT NULL
    AND i.is_disabled = 0
    AND i.is_hypothetical = 0
    AND i.index_id > 0
    AND i.type IN (1,2)
    AND ips.page_count >= @MinPages
ORDER BY
    FragmentationPercent DESC,
    PageCount DESC;
"@
}

# ----------------- SQL builder (Classic WSUS maintenance) -----------------
function Build-ClassicWsusMaintenanceSqlText {
    param([int]$MinPages,[int]$ReorgPct,[int]$RebuildPct)

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $rb  = [string]::Format($inv, "{0:0.0}", [double]$RebuildPct)
    $rg  = [string]::Format($inv, "{0:0.0}", [double]$ReorgPct)

@"
USE [SUSDB];
GO
SET NOCOUNT ON;

DECLARE @MinPages   int   = $MinPages;
DECLARE @RebuildPct float = $rb;
DECLARE @ReorgPct   float = $rg;

DECLARE @Start datetime2 = SYSDATETIME();
PRINT 'Classic WSUS SUSDB maintenance started: ' + CONVERT(varchar(30), @Start, 121);
PRINT 'MinPages=' + CAST(@MinPages as varchar(20)) + ' Reorg=' + CAST(@ReorgPct as varchar(20)) + '% Rebuild=' + CAST(@RebuildPct as varchar(20)) + '%';

-- Known high-churn WSUS tables (scope control)
DECLARE @Targets TABLE (SchemaName sysname NOT NULL, TableName sysname NOT NULL);
INSERT INTO @Targets (SchemaName, TableName) VALUES
('dbo','tbRevision'),
('dbo','tbRevisionSupersedesUpdate'),
('dbo','tbLocalizedPropertyForRevision'),
('dbo','tbProperty'),
('dbo','tbUpdate'),
('dbo','tbDeployment'),
('dbo','tbComputerTarget'),
('dbo','tbComputerTargetGroup'),
('dbo','tbFile');

-- Fill factor overrides (table-level default)
-- Adjust to your environment if needed.
DECLARE @FillFactor TABLE (SchemaName sysname NOT NULL, TableName sysname NOT NULL, FillFactor int NOT NULL);
INSERT INTO @FillFactor (SchemaName, TableName, FillFactor) VALUES
('dbo','tbRevisionSupersedesUpdate', 90),
('dbo','tbLocalizedPropertyForRevision', 90),
('dbo','tbRevision', 90),
('dbo','tbProperty', 90);

DECLARE @schema sysname, @table sysname, @index sysname, @frag float, @pages int;
DECLARE @ff int;
DECLARE @sql nvarchar(max);

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
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
JOIN @Targets     AS trg ON trg.SchemaName = s.name AND trg.TableName = t.name
WHERE
    i.name IS NOT NULL
    AND i.is_disabled = 0
    AND i.is_hypothetical = 0
    AND i.index_id > 0
    AND i.type IN (1,2)
    AND t.is_ms_shipped = 0
    AND ips.page_count >= @MinPages
ORDER BY
    ips.avg_fragmentation_in_percent DESC,
    ips.page_count DESC;

OPEN cur;
FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ff = NULL;
    SELECT @ff = FillFactor FROM @FillFactor WHERE SchemaName=@schema AND TableName=@table;

    IF @frag >= @RebuildPct
    BEGIN
        IF @ff IS NOT NULL
            SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                     + N' REBUILD WITH (FILLFACTOR = ' + CAST(@ff as nvarchar(10)) + N', SORT_IN_TEMPDB = OFF, MAXDOP = 1);';
        ELSE
            SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table)
                     + N' REBUILD WITH (SORT_IN_TEMPDB = OFF, MAXDOP = 1);';

        PRINT CONCAT('REBUILD >> ', @schema, '.', @table, ' [', @index, ']  Frag=', CONVERT(varchar(10), @frag), '%  Pages=', @pages,
                     CASE WHEN @ff IS NULL THEN '' ELSE CONCAT('  FillFactor=', @ff) END);

        BEGIN TRY
            EXEC sp_executesql @sql;
        END TRY
        BEGIN CATCH
            PRINT CONCAT('FAILED >> ', @schema, '.', @table, ' [', @index, ']  Error=', ERROR_MESSAGE());
        END CATCH
    END
    ELSE IF @frag >= @ReorgPct
    BEGIN
        SET @sql = N'ALTER INDEX ' + QUOTENAME(@index) + N' ON ' + QUOTENAME(@schema) + N'.' + QUOTENAME(@table) + N' REORGANIZE;';
        PRINT CONCAT('REORGANIZE >> ', @schema, '.', @table, ' [', @index, ']  Frag=', CONVERT(varchar(10), @frag), '%  Pages=', @pages);

        BEGIN TRY
            EXEC sp_executesql @sql;
        END TRY
        BEGIN CATCH
            PRINT CONCAT('FAILED >> ', @schema, '.', @table, ' [', @index, ']  Error=', ERROR_MESSAGE());
        END CATCH
    END

    FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
END

CLOSE cur; DEALLOCATE cur;

PRINT 'Updating statistics...';
EXEC sp_updatestats;

DECLARE @End datetime2 = SYSDATETIME();
PRINT 'Classic WSUS SUSDB maintenance completed: ' + CONVERT(varchar(30), @End, 121);
PRINT 'Duration (seconds): ' + CAST(DATEDIFF(second, @Start, @End) as varchar(20));
GO
"@
}

# ----------------- Core generator -----------------
function Invoke-GenerateSqlFiles {
    param(
        [Parameter(Mandatory=$true)][string]$OutDir,
        [Parameter(Mandatory=$true)][bool]$DoSmart,
        [Parameter(Mandatory=$true)][bool]$DoVerify,
        [Parameter(Mandatory=$true)][bool]$DoClassic,
        [Parameter(Mandatory=$true)][string]$SmartName,
        [Parameter(Mandatory=$true)][string]$VerifyName,
        [Parameter(Mandatory=$true)][string]$ClassicName,
        [Parameter(Mandatory=$true)][int]$MinPages,
        [Parameter(Mandatory=$true)][int]$ReorgPct,
        [Parameter(Mandatory=$true)][int]$RebuildPct
    )

    if ($RebuildPct -le $ReorgPct) { throw "RebuildPct must be greater than ReorgPct." }
    Ensure-Dir -DirectoryPath $OutDir

    $written = [ordered]@{
        Verify  = $null
        Smart   = $null
        Classic = $null
    }

    if ($DoVerify) {
        $p = Join-SafePath -DirectoryPath $OutDir -FileName $VerifyName
        $sql = Build-VerifyFragmentationSqlText -MinPages $MinPages -ReorgPct $ReorgPct -RebuildPct $RebuildPct
        Set-Content -Path $p -Value $sql -Encoding UTF8 -ErrorAction Stop
        Write-Log "Generated SQL script: $p" "INFO"
        $written.Verify = $p
    } else {
        Write-Log "Verify fragmentation script generation skipped." "INFO"
    }

    if ($DoSmart) {
        $p = Join-SafePath -DirectoryPath $OutDir -FileName $SmartName
        $sql = Build-ReindexSqlText -MinPages $MinPages -ReorgPct $ReorgPct -RebuildPct $RebuildPct
        Set-Content -Path $p -Value $sql -Encoding UTF8 -ErrorAction Stop
        Write-Log "Generated SQL script: $p" "INFO"
        $written.Smart = $p
    } else {
        Write-Log "Smart reindex script generation skipped." "INFO"
    }

    if ($DoClassic) {
        $p = Join-SafePath -DirectoryPath $OutDir -FileName $ClassicName
        $sql = Build-ClassicWsusMaintenanceSqlText -MinPages $MinPages -ReorgPct $ReorgPct -RebuildPct $RebuildPct
        Set-Content -Path $p -Value $sql -Encoding UTF8 -ErrorAction Stop
        Write-Log "Generated SQL script: $p" "INFO"
        $written.Classic = $p
    } else {
        Write-Log "Classic script generation skipped." "INFO"
    }

    return [pscustomobject]$written
}

# ----------------- Smart GUI -----------------
function Show-GeneratorGui {
    param(
        [string]$DefaultOutDir,
        [int]$DefaultMinPages,
        [int]$DefaultReorgPct,
        [int]$DefaultRebuildPct,
        [bool]$DefaultDoSmart,
        [bool]$DefaultDoVerify,
        [bool]$DefaultDoClassic,
        [string]$DefaultSmartName,
        [string]$DefaultVerifyName,
        [string]$DefaultClassicName
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "WSUS SQL Generator (SUSDB) — v1.70"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.Size = New-Object System.Drawing.Size(780, 520)

    $font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
    $form.Font = $font

    # Main layout
    $main = New-Object System.Windows.Forms.TableLayoutPanel
    $main.Dock = 'Fill'
    $main.Padding = New-Object System.Windows.Forms.Padding(12)
    $main.RowCount = 5
    $main.ColumnCount = 1
    $main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 110))) | Out-Null
    $main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 155))) | Out-Null
    $main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 120))) | Out-Null
    $main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 60))) | Out-Null
    $form.Controls.Add($main)

    # Group: Output
    $gbOut = New-Object System.Windows.Forms.GroupBox
    $gbOut.Text = "Output"
    $gbOut.Dock = 'Fill'
    $main.Controls.Add($gbOut, 0, 0)

    $outTbl = New-Object System.Windows.Forms.TableLayoutPanel
    $outTbl.Dock = 'Fill'
    $outTbl.Padding = New-Object System.Windows.Forms.Padding(10, 18, 10, 10)
    $outTbl.ColumnCount = 3
    $outTbl.RowCount = 2
    $outTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120))) | Out-Null
    $outTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $outTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 110))) | Out-Null
    $outTbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
    $outTbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
    $gbOut.Controls.Add($outTbl)

    $lblDir = New-Object System.Windows.Forms.Label
    $lblDir.Text = "Folder:"
    $lblDir.TextAlign = 'MiddleLeft'
    $lblDir.Dock = 'Fill'
    $outTbl.Controls.Add($lblDir, 0, 0)

    $txtDir = New-Object System.Windows.Forms.TextBox
    $txtDir.Text = $DefaultOutDir
    $txtDir.Dock = 'Fill'
    $outTbl.Controls.Add($txtDir, 1, 0)

    $btnBrowse = New-Object System.Windows.Forms.Button
    $btnBrowse.Text = "Browse..."
    $btnBrowse.Dock = 'Fill'
    $outTbl.Controls.Add($btnBrowse, 2, 0)

    $lblHint = New-Object System.Windows.Forms.Label
    $lblHint.Text = "Files will be created inside the selected folder. You can edit file names below."
    $lblHint.AutoSize = $true
    $lblHint.Dock = 'Fill'
    $outTbl.SetColumnSpan($lblHint, 3)
    $outTbl.Controls.Add($lblHint, 0, 1)

    $btnBrowse.Add_Click({
        try {
            $picked = Select-FolderGui -DefaultPath $txtDir.Text
            if ($picked) { $txtDir.Text = $picked }
        } catch { }
    })

    # Group: What to generate
    $gbWhat = New-Object System.Windows.Forms.GroupBox
    $gbWhat.Text = "Generate"
    $gbWhat.Dock = 'Fill'
    $main.Controls.Add($gbWhat, 0, 1)

    $whatTbl = New-Object System.Windows.Forms.TableLayoutPanel
    $whatTbl.Dock = 'Fill'
    $whatTbl.Padding = New-Object System.Windows.Forms.Padding(10, 18, 10, 10)
    $whatTbl.ColumnCount = 3
    $whatTbl.RowCount = 4
    $whatTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 160))) | Out-Null
    $whatTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
    $whatTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140))) | Out-Null
    1..4 | ForEach-Object { $whatTbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null }
    $gbWhat.Controls.Add($whatTbl)

    $chkSmart = New-Object System.Windows.Forms.CheckBox
    $chkSmart.Text = "Smart reindex (scan ALL)"
    $chkSmart.Checked = $DefaultDoSmart
    $chkSmart.Dock = 'Fill'
    $whatTbl.Controls.Add($chkSmart, 0, 0)

    $txtSmart = New-Object System.Windows.Forms.TextBox
    $txtSmart.Text = $DefaultSmartName
    $txtSmart.Dock = 'Fill'
    $whatTbl.Controls.Add($txtSmart, 1, 0)

    $lblSmart = New-Object System.Windows.Forms.Label
    $lblSmart.Text = "Recommended"
    $lblSmart.TextAlign = 'MiddleLeft'
    $lblSmart.Dock = 'Fill'
    $whatTbl.Controls.Add($lblSmart, 2, 0)

    $chkVerify = New-Object System.Windows.Forms.CheckBox
    $chkVerify.Text = "Verify fragmentation (report)"
    $chkVerify.Checked = $DefaultDoVerify
    $chkVerify.Dock = 'Fill'
    $whatTbl.Controls.Add($chkVerify, 0, 1)

    $txtVerify = New-Object System.Windows.Forms.TextBox
    $txtVerify.Text = $DefaultVerifyName
    $txtVerify.Dock = 'Fill'
    $whatTbl.Controls.Add($txtVerify, 1, 1)

    $lblVerify = New-Object System.Windows.Forms.Label
    $lblVerify.Text = "Recommended"
    $lblVerify.TextAlign = 'MiddleLeft'
    $lblVerify.Dock = 'Fill'
    $whatTbl.Controls.Add($lblVerify, 2, 1)

    $chkClassic = New-Object System.Windows.Forms.CheckBox
    $chkClassic.Text = "Classic WSUS maintenance (targeted)"
    $chkClassic.Checked = $DefaultDoClassic
    $chkClassic.Dock = 'Fill'
    $whatTbl.Controls.Add($chkClassic, 0, 2)

    $txtClassic = New-Object System.Windows.Forms.TextBox
    $txtClassic.Text = $DefaultClassicName
    $txtClassic.Dock = 'Fill'
    $whatTbl.Controls.Add($txtClassic, 1, 2)

    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Optional"
    $lblClassic.TextAlign = 'MiddleLeft'
    $lblClassic.Dock = 'Fill'
    $whatTbl.Controls.Add($lblClassic, 2, 2)

    $tip = New-Object System.Windows.Forms.Label
    $tip.Text = "Tip: Classic is a smaller-scope script (known WSUS hot tables) — faster than scanning everything."
    $tip.AutoSize = $true
    $tip.Dock = 'Fill'
    $whatTbl.SetColumnSpan($tip, 3)
    $whatTbl.Controls.Add($tip, 0, 3)

    # Group: Thresholds
    $gbThr = New-Object System.Windows.Forms.GroupBox
    $gbThr.Text = "Thresholds embedded into SQL"
    $gbThr.Dock = 'Fill'
    $main.Controls.Add($gbThr, 0, 2)

    $thrTbl = New-Object System.Windows.Forms.TableLayoutPanel
    $thrTbl.Dock = 'Fill'
    $thrTbl.Padding = New-Object System.Windows.Forms.Padding(10, 18, 10, 10)
    $thrTbl.ColumnCount = 6
    $thrTbl.RowCount = 2
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 110))) | Out-Null
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 110))) | Out-Null
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 110))) | Out-Null
    $thrTbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
    $thrTbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
    $thrTbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 28))) | Out-Null
    $gbThr.Controls.Add($thrTbl)

    $lMin = New-Object System.Windows.Forms.Label
    $lMin.Text = "MinPages:"
    $lMin.TextAlign = 'MiddleLeft'
    $lMin.Dock = 'Fill'
    $thrTbl.Controls.Add($lMin, 0, 0)

    $numMin = New-Object System.Windows.Forms.NumericUpDown
    $numMin.Minimum = 1
    $numMin.Maximum = 1000000
    $numMin.Value = [decimal]$DefaultMinPages
    $numMin.Dock = 'Fill'
    $thrTbl.Controls.Add($numMin, 1, 0)

    $lReorg = New-Object System.Windows.Forms.Label
    $lReorg.Text = "ReorgPct:"
    $lReorg.TextAlign = 'MiddleLeft'
    $lReorg.Dock = 'Fill'
    $thrTbl.Controls.Add($lReorg, 2, 0)

    $numReorg = New-Object System.Windows.Forms.NumericUpDown
    $numReorg.Minimum = 0
    $numReorg.Maximum = 99
    $numReorg.Value = [decimal]$DefaultReorgPct
    $numReorg.Dock = 'Fill'
    $thrTbl.Controls.Add($numReorg, 3, 0)

    $lReb = New-Object System.Windows.Forms.Label
    $lReb.Text = "RebuildPct:"
    $lReb.TextAlign = 'MiddleLeft'
    $lReb.Dock = 'Fill'
    $thrTbl.Controls.Add($lReb, 4, 0)

    $numRebuild = New-Object System.Windows.Forms.NumericUpDown
    $numRebuild.Minimum = 1
    $numRebuild.Maximum = 100
    $numRebuild.Value = [decimal]$DefaultRebuildPct
    $numRebuild.Dock = 'Fill'
    $thrTbl.Controls.Add($numRebuild, 5, 0)

    $lblRule = New-Object System.Windows.Forms.Label
    $lblRule.Text = "Rule: RebuildPct must be greater than ReorgPct. MinPages avoids tiny indexes."
    $lblRule.AutoSize = $true
    $lblRule.Dock = 'Fill'
    $thrTbl.SetColumnSpan($lblRule, 6)
    $thrTbl.Controls.Add($lblRule, 0, 1)

    # Status / buttons row
    $panelBottom = New-Object System.Windows.Forms.Panel
    $panelBottom.Dock = 'Fill'
    $main.Controls.Add($panelBottom, 0, 4)

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text = "Ready"
    $lblStatus.AutoSize = $false
    $lblStatus.TextAlign = 'MiddleLeft'
    $lblStatus.Dock = 'Fill'
    $lblStatus.Location = New-Object System.Drawing.Point(12, 8)
    $lblStatus.Size = New-Object System.Drawing.Size(500, 40)
    $panelBottom.Controls.Add($lblStatus)

    $btnGen = New-Object System.Windows.Forms.Button
    $btnGen.Text = "&Generate"
    $btnGen.Size = New-Object System.Drawing.Size(110, 30)
    $btnGen.Location = New-Object System.Drawing.Point(540, 15)
    $panelBottom.Controls.Add($btnGen)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "&Close"
    $btnClose.Size = New-Object System.Drawing.Size(90, 30)
    $btnClose.Location = New-Object System.Drawing.Point(655, 15)
    $panelBottom.Controls.Add($btnClose)

    $result = $null

    $btnClose.Add_Click({ $form.Close() })

    $btnGen.Add_Click({
        try {
            $outDir = $txtDir.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($outDir)) { throw "Output folder is required." }

            $doSmart   = [bool]$chkSmart.Checked
            $doVerify  = [bool]$chkVerify.Checked
            $doClassic = [bool]$chkClassic.Checked
            if (-not ($doSmart -or $doVerify -or $doClassic)) { throw "Select at least one file to generate." }

            $smartName   = $txtSmart.Text.Trim()
            $verifyName  = $txtVerify.Text.Trim()
            $classicName = $txtClassic.Text.Trim()

            $minPages = [int]$numMin.Value
            $reorg    = [int]$numReorg.Value
            $rebuild  = [int]$numRebuild.Value
            if ($rebuild -le $reorg) { throw "RebuildPct must be greater than ReorgPct." }

            $lblStatus.Text = "Generating..."
            $form.Refresh()

            $written = Invoke-GenerateSqlFiles `
                -OutDir $outDir `
                -DoSmart $doSmart `
                -DoVerify $doVerify `
                -DoClassic $doClassic `
                -SmartName $smartName `
                -VerifyName $verifyName `
                -ClassicName $classicName `
                -MinPages $minPages `
                -ReorgPct $reorg `
                -RebuildPct $rebuild

            $lines = @()
            if ($written.Verify)  { $lines += "Verify:  $($written.Verify)" }  else { $lines += "Verify:  (skipped)" }
            if ($written.Smart)   { $lines += "Smart:   $($written.Smart)" }   else { $lines += "Smart:   (skipped)" }
            if ($written.Classic) { $lines += "Classic: $($written.Classic)" } else { $lines += "Classic: (skipped)" }
            $lines += ""
            $lines += "Log:     $logPath"

            $lblStatus.Text = "Done"
            Show-Ui -Message ($lines -join "`r`n") -Icon Information

            $result = [pscustomobject]@{
                OutputDirectory = $outDir
                GenerateSmart   = $doSmart
                GenerateVerify  = $doVerify
                GenerateClassic = $doClassic
                SmartFileName   = $smartName
                VerifyFileName  = $verifyName
                ClassicFileName = $classicName
                MinPages        = $minPages
                ReorgPct        = $reorg
                RebuildPct      = $rebuild
            }

        } catch {
            $lblStatus.Text = "Failed"
            Show-Ui -Message ("Error: {0}`n`nLog: {1}" -f $_.Exception.Message, $logPath) -Icon Error
            Write-Log ("GUI generate failed: {0}" -f $_.Exception.Message) "ERROR"
        }
    })

    $form.Add_Shown({ $form.Activate() }) | Out-Null
    [void]$form.ShowDialog()
    return $result
}

# ----------------- Main -----------------
Write-Log "========== WSUS SQL GENERATOR START ==========" "INFO"
Write-Log "Log: $logPath" "INFO"
Write-Log "Defaults: OutDir=$OutputDirectory Smart=$([bool]$GenerateSmart) Verify=$([bool]$GenerateVerifyFragmentation) Classic=$([bool]$GenerateClassic) MinPages=$MinPages ReorgPct=$ReorgPct RebuildPct=$RebuildPct" "INFO"

try {
    if (-not $NoGui) {
        $picked = Show-GeneratorGui `
            -DefaultOutDir $OutputDirectory `
            -DefaultMinPages $MinPages `
            -DefaultReorgPct $ReorgPct `
            -DefaultRebuildPct $RebuildPct `
            -DefaultDoSmart ([bool]$GenerateSmart) `
            -DefaultDoVerify ([bool]$GenerateVerifyFragmentation) `
            -DefaultDoClassic ([bool]$GenerateClassic) `
            -DefaultSmartName $SmartFileName `
            -DefaultVerifyName $VerifyFileName `
            -DefaultClassicName $ClassicFileName

        # If user closed without generating, exit cleanly
        if ($null -eq $picked) {
            Write-Log "GUI closed without generation." "WARNING"
            return
        }

        # Apply GUI selections for final output (mainly for logs)
        $OutputDirectory = $picked.OutputDirectory
        $GenerateSmart   = [bool]$picked.GenerateSmart
        $GenerateVerifyFragmentation = [bool]$picked.GenerateVerify
        $GenerateClassic = [bool]$picked.GenerateClassic
        $SmartFileName   = $picked.SmartFileName
        $VerifyFileName  = $picked.VerifyFileName
        $ClassicFileName = $picked.ClassicFileName
        $MinPages        = [int]$picked.MinPages
        $ReorgPct        = [int]$picked.ReorgPct
        $RebuildPct      = [int]$picked.RebuildPct

        Write-Log "GUI selections applied: OutDir=$OutputDirectory Smart=$GenerateSmart Verify=$GenerateVerifyFragmentation Classic=$GenerateClassic" "INFO"
        Write-Log "========== WSUS SQL GENERATOR END ==========" "INFO"
        return
    }

    # NoGui mode: generate immediately using parameters
    if ($RebuildPct -le $ReorgPct) {
        $msg = "RebuildPct must be greater than ReorgPct."
        Write-Log $msg "ERROR"
        Show-Ui -Message $msg -Icon Error
        throw $msg
    }

    $written = Invoke-GenerateSqlFiles `
        -OutDir $OutputDirectory `
        -DoSmart ([bool]$GenerateSmart) `
        -DoVerify ([bool]$GenerateVerifyFragmentation) `
        -DoClassic ([bool]$GenerateClassic) `
        -SmartName $SmartFileName `
        -VerifyName $VerifyFileName `
        -ClassicName $ClassicFileName `
        -MinPages $MinPages `
        -ReorgPct $ReorgPct `
        -RebuildPct $RebuildPct

    if (-not $Quiet) {
        $lines = @()
        if ($written.Verify)  { $lines += "Verify:  $($written.Verify)" }  else { $lines += "Verify:  (skipped)" }
        if ($written.Smart)   { $lines += "Smart:   $($written.Smart)" }   else { $lines += "Smart:   (skipped)" }
        if ($written.Classic) { $lines += "Classic: $($written.Classic)" } else { $lines += "Classic: (skipped)" }
        $lines += ""
        $lines += "Log:     $logPath"
        Show-Ui -Message ($lines -join "`r`n") -Icon Information
    }

    Write-Log "========== WSUS SQL GENERATOR END ==========" "INFO"

} catch {
    Write-Log ("Generator failed: {0}" -f $_.Exception.Message) "ERROR"
    Show-Ui -Message ("Generator failed.`n`nError: {0}`nLog: {1}" -f $_.Exception.Message,$logPath) -Icon Error
    throw
}

# End of script
