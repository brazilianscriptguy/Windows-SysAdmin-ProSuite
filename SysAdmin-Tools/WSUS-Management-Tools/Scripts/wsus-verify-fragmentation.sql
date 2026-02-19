SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

SET NOCOUNT ON;
SELECT
  DB_NAME() AS [DatabaseName],
  OBJECT_SCHEMA_NAME(ips.object_id) AS [SchemaName],
  OBJECT_NAME(ips.object_id) AS [TableName],
  i.name AS [IndexName],
  ips.index_id AS [IndexId],
  ips.page_count AS [PageCount],
  ips.avg_fragmentation_in_percent AS [FragPct],
  CASE
    WHEN ips.page_count < 1000 THEN 'SKIP (small index)'
    WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD'
    WHEN ips.avg_fragmentation_in_percent >= 10 THEN 'REORGANIZE'
    ELSE 'OK'
  END AS [Recommendation]
FROM sys.dm_db_index_physical_stats(DB_ID('SUSDB'), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i
  ON ips.object_id = i.object_id AND ips.index_id = i.index_id
WHERE ips.index_id > 0
  AND i.is_disabled = 0
ORDER BY ips.avg_fragmentation_in_percent DESC, ips.page_count DESC;
