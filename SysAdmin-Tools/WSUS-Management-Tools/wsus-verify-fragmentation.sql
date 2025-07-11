USE SUSDB;
GO

SELECT 
    dbschemas.[name] AS SchemaName,
    dbtables.[name] AS TableName,
    dbindexes.[name] AS IndexName,
    dbindexes.type_desc AS IndexType,
    indexstats.page_count AS PageCount,
    indexstats.avg_fragmentation_in_percent AS FragmentationPercent,
    CASE 
        WHEN indexstats.avg_fragmentation_in_percent >= 30 THEN 'High'
        WHEN indexstats.avg_fragmentation_in_percent >= 10 THEN 'Medium'
        ELSE 'Low'
    END AS FragmentationLevel
FROM 
    sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') AS indexstats
INNER JOIN 
    sys.indexes dbindexes ON indexstats.[object_id] = dbindexes.[object_id]
                          AND indexstats.index_id = dbindexes.index_id
INNER JOIN 
    sys.tables dbtables ON dbindexes.[object_id] = dbtables.[object_id]
INNER JOIN 
    sys.schemas dbschemas ON dbtables.[schema_id] = dbschemas.[schema_id]
WHERE 
    dbindexes.[name] IS NOT NULL
    AND dbindexes.is_disabled = 0
    AND indexstats.page_count > 100
ORDER BY 
    indexstats.avg_fragmentation_in_percent DESC;
