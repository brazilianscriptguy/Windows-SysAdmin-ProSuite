<#
.SYNOPSIS
    Generates a wsus-reindex.sql file based on fragmented indexes in SUSDB (WID)

.DESCRIPTION
    This script connects to the Windows Internal Database (WID) SUSDB and identifies fragmented indexes 
    with more than 100 pages and fragmentation above 10%, generating a T-SQL script to rebuild them.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: July 11, 2025
#>

# Parameters
$thresholdFragmentation = 10
$minPageCount = 100
$outputSqlFile = "C:\Scripts\wsus-reindex.sql"
$namedPipe = "np:\\.\pipe\MICROSOFT##WID\tsql\query"

# Check for sqlcmd
$sqlcmd = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Host "sqlcmd.exe not found in PATH. Please install SQLCMD utilities." -ForegroundColor Red
    exit 1
}

# Query to extract REBUILD commands
$sqlQuery = @"
SET NOCOUNT ON;
USE SUSDB;

SELECT 
    'ALTER INDEX [' + i.name + '] ON [' + s.name + '].[' + t.name + '] REBUILD WITH (ONLINE = OFF);' AS RebuildCommand
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

Write-Host "Querying SUSDB for fragmented indexes..."

try {
    # Execute and capture raw SQL
    $results = & sqlcmd -S $namedPipe -E -d SUSDB -Q $sqlQuery -h -1 -W 2>&1

    if (-not $results -or $results.Count -eq 0) {
        Write-Host "No fragmented indexes found above $thresholdFragmentation%."
        exit 0
    }

    # Write SQL file
    Set-Content -Path $outputSqlFile -Value "USE SUSDB;" -Encoding UTF8
    Add-Content -Path $outputSqlFile -Value "GO`n" -Encoding UTF8
    $results | ForEach-Object {
        if ($_ -match '^ALTER INDEX') {
            Add-Content -Path $outputSqlFile -Value "$_`nGO" -Encoding UTF8
        }
    }

    Write-Host "Reindex script generated successfully: $outputSqlFile"
} catch {
    Write-Host "Error occurred while generating the SQL file: $_" -ForegroundColor Red
    exit 1
}

# End of script
