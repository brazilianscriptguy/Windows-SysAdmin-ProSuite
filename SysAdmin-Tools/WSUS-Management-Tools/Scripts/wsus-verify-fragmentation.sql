USE [SUSDB];
GO

DECLARE @MinPages   int   = 100;
DECLARE @RebuildPct float = 30.0;
DECLARE @ReorgPct   float = 5.0;

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
