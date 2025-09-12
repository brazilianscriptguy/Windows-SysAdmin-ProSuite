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
  AND ips.page_count >= 100       -- evita trabalho inútil
  AND i.is_disabled = 0
  AND i.type_desc <> 'HEAP'       -- heaps não têm REBUILD
ORDER BY ips.avg_fragmentation_in_percent DESC;

OPEN cur;
DECLARE @frag float, @pages int;

FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF @frag >= 30
        SET @sql = N'ALTER INDEX ['+@index+'] ON ['+@schema+'].['+@table+'] REBUILD WITH (SORT_IN_TEMPDB = OFF, MAXDOP = 1);';
    ELSE IF @frag >= 5
        SET @sql = N'ALTER INDEX ['+@index+'] ON ['+@schema+'].['+@table+'] REORGANIZE;';
    ELSE
        SET @sql = NULL; -- ignora

    IF @sql IS NOT NULL
    BEGIN
        PRINT CONCAT('>> ', @schema, '.', @table, ' [', @index, ']  Frag=', CONVERT(varchar(10), @frag), '%  Pages=', @pages);
        EXEC sp_executesql @sql;
    END

    FETCH NEXT FROM cur INTO @schema, @table, @index, @frag, @pages;
END

CLOSE cur; DEALLOCATE cur;
GO
