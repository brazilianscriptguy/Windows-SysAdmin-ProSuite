SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

SET NOCOUNT ON;

DECLARE @MinPages INT = 1000;
DECLARE @ReorgPct FLOAT = 10;
DECLARE @RebuildPct FLOAT = 30;

DECLARE @schema SYSNAME, @table SYSNAME, @index SYSNAME, @sql NVARCHAR(MAX);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR
SELECT
  OBJECT_SCHEMA_NAME(ips.object_id) AS SchemaName,
  OBJECT_NAME(ips.object_id) AS TableName,
  i.name AS IndexName,
  ips.page_count,
  ips.avg_fragmentation_in_percent
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
  ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0
  AND i.is_disabled = 0
  AND ips.page_count >= @MinPages
  AND ips.avg_fragmentation_in_percent >= @ReorgPct
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN c;

DECLARE @page_count BIGINT, @frag FLOAT;

FETCH NEXT FROM c INTO @schema, @table, @index, @page_count, @frag;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF (@frag >= @RebuildPct)
        SET @sql = N'ALTER INDEX [' + REPLACE(@index,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REBUILD WITH (ONLINE = OFF);';
    ELSE
        SET @sql = N'ALTER INDEX [' + REPLACE(@index,']',']]') + N'] ON [' + REPLACE(@schema,']',']]') + N'].[' + REPLACE(@table,']',']]') + N'] REORGANIZE;';

    PRINT @sql;
    EXEC sp_executesql @sql;

    FETCH NEXT FROM c INTO @schema, @table, @index, @page_count, @frag;
END

CLOSE c;
DEALLOCATE c;

EXEC sp_updatestats;
