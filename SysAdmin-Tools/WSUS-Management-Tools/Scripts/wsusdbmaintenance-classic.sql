SET NOCOUNT ON;

-- Classic WSUS SUSDB maintenance (high-churn tables)
DECLARE @ReorgPct FLOAT = 10;
DECLARE @RebuildPct FLOAT = 30;

-- Example hot tables (keep conservative, no fillfactor hacks by default)
DECLARE @T TABLE (SchemaName SYSNAME, TableName SYSNAME);
INSERT INTO @T VALUES
('dbo','tbRevisionSupersedesUpdate'),
('dbo','tbLocalizedPropertyForRevision'),
('dbo','tbRevision'),
('dbo','tbRevisionInCategory'),
('dbo','tbXml'),
('dbo','tbProperty');

DECLARE @schema SYSNAME, @table SYSNAME, @idx SYSNAME, @sql NVARCHAR(MAX), @frag FLOAT, @pages BIGINT;

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT OBJECT_SCHEMA_NAME(ips.object_id), OBJECT_NAME(ips.object_id), i.name, ips.avg_fragmentation_in_percent, ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON ips.object_id=i.object_id AND ips.index_id=i.index_id
JOIN @T t ON t.SchemaName=OBJECT_SCHEMA_NAME(ips.object_id) AND t.TableName=OBJECT_NAME(ips.object_id)
WHERE ips.index_id>0 AND i.is_disabled=0 AND ips.page_count >= 1000 AND ips.avg_fragmentation_in_percent >= @ReorgPct
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN c;
FETCH NEXT FROM c INTO @schema, @table, @idx, @frag, @pages;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF (@frag >= @RebuildPct)
        SET @sql = N'ALTER INDEX [' + REPLACE(@idx,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REBUILD WITH (ONLINE = OFF);';
    ELSE
        SET @sql = N'ALTER INDEX [' + REPLACE(@idx,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REORGANIZE;';

    PRINT @sql;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM c INTO @schema, @table, @idx, @frag, @pages;
END
CLOSE c;
DEALLOCATE c;

EXEC sp_updatestats;
