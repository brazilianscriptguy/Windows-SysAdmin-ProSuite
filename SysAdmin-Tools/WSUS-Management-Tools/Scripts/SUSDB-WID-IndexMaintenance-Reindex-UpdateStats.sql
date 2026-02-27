-- =============================================
-- Full REINDEX + UPDATE STATISTICS maintenance for SUSDB (WSUS + WID)
-- Commonly recommended to mitigate WSUS timeouts / performance degradation
-- Run as Administrator in SSMS connected to the Windows Internal Database (WID)
-- Runtime can range from ~30 minutes to several hours (run off-peak)
-- =============================================

USE [SUSDB];
GO

SET NOCOUNT ON;
PRINT 'Starting SUSDB maintenance - ' + CONVERT(varchar, GETDATE(), 120);

-- =============================================
-- 1. Create Microsoft-recommended indexes (safe + useful)
-- =============================================
PRINT 'Creating Microsoft-recommended indexes...';

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'nclLocalizedPropertyID' AND object_id = OBJECT_ID('dbo.tbLocalizedPropertyForRevision'))
BEGIN
    CREATE NONCLUSTERED INDEX [nclLocalizedPropertyID]
    ON [dbo].[tbLocalizedPropertyForRevision] ([LocalizedPropertyID] ASC);
    PRINT '✓ Index nclLocalizedPropertyID created.';
END
ELSE
    PRINT '✓ Index nclLocalizedPropertyID already exists.';

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'nclSupercededUpdateID' AND object_id = OBJECT_ID('dbo.tbRevisionSupersedesUpdate'))
BEGIN
    CREATE NONCLUSTERED INDEX [nclSupercededUpdateID]
    ON [dbo].[tbRevisionSupersedesUpdate] ([SupersededUpdateID] ASC);
    PRINT '✓ Index nclSupercededUpdateID created.';
END
ELSE
    PRINT '✓ Index nclSupercededUpdateID already exists.';

-- =============================================
-- 2. Dynamic reindexing (REBUILD vs REORGANIZE based on fragmentation)
-- =============================================
PRINT 'Starting dynamic index maintenance...';

DECLARE @work_to_do TABLE (
    objectid        int,
    indexid         int,
    schemaname      nvarchar(128),
    objectname      nvarchar(128),
    indexname       nvarchar(128),
    frag            float,
    page_count      int,
    partitionnum    bigint,
    partitioncount  bigint,
    command         nvarchar(4000)
);

INSERT @work_to_do
SELECT
    f.object_id,
    f.index_id,
    QUOTENAME(s.name) AS schemaname,
    QUOTENAME(o.name) AS objectname,
    QUOTENAME(i.name) AS indexname,
    f.avg_fragmentation_in_percent,
    f.page_count,
    p.partition_number,
    p.partition_number AS partitioncount,
    'ALTER INDEX ' + QUOTENAME(i.name) + ' ON ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) +
        ' REBUILD ' +
        CASE WHEN p.partition_number > 1
             THEN ' PARTITION = ' + CAST(p.partition_number AS nvarchar(10))
             ELSE ''
        END +
        CASE WHEN p.partition_number > 1
             THEN ' WITH (ONLINE = ON)'
             ELSE ''
        END AS command
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') f
INNER JOIN sys.indexes i
    ON f.object_id = i.object_id
   AND f.index_id = i.index_id
INNER JOIN sys.objects o
    ON f.object_id = o.object_id
INNER JOIN sys.schemas s
    ON o.schema_id = s.schema_id
INNER JOIN sys.partitions p
    ON f.object_id = p.object_id
   AND f.index_id = p.index_id
WHERE f.avg_fragmentation_in_percent > 5.0          -- only indexes with fragmentation > 5%
  AND f.page_count > 1000                           -- ignore small indexes
  AND i.name IS NOT NULL
  AND i.is_disabled = 0
  AND i.is_hypothetical = 0
ORDER BY f.avg_fragmentation_in_percent DESC, f.page_count DESC;

DECLARE
    @objectid       int,
    @indexid        int,
    @schemaname     nvarchar(128),
    @objectname     nvarchar(128),
    @indexname      nvarchar(128),
    @frag           float,
    @pagecount      int,
    @partitionnum   bigint,
    @partitioncount bigint,
    @command        nvarchar(4000);

WHILE (1 = 1)
BEGIN
    SELECT TOP 1
        @objectid       = objectid,
        @indexid        = indexid,
        @schemaname     = schemaname,
        @objectname     = objectname,
        @indexname      = indexname,
        @frag           = frag,
        @pagecount      = page_count,
        @partitionnum   = partitionnum,
        @partitioncount = partitioncount
    FROM @work_to_do;

    IF @@ROWCOUNT = 0 BREAK;

    -- Decide REBUILD vs REORGANIZE
    IF @frag < 30
        SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REORGANIZE';
    ELSE
        SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REBUILD';

    -- Add PARTITION if applicable
    IF @partitioncount > 1
        SET @command = @command + N' PARTITION = ' + CAST(@partitionnum AS nvarchar(10));

    -- Special fillfactor for WSUS-critical indexes
    IF @indexname IN (N'IX_tbUpdateRevision_UpdateID', N'IX_tbUpdate_ArrivalDate', N'IX_tbUpdateRevision_RevisionID')
        SET @command = @command + N' WITH (FILLFACTOR = 70)';

    PRINT 'Running: ' + @command;
    EXEC (@command);

    DELETE FROM @work_to_do
    WHERE objectid = @objectid
      AND indexid = @indexid
      AND partitionnum = @partitionnum;
END

PRINT 'Index maintenance completed successfully!';

-- =============================================
-- 3. Update all database statistics
-- =============================================
PRINT 'Updating database statistics...';
EXEC sp_updatestats;
PRINT 'Statistics updated successfully!';

-- =============================================
-- END
-- =============================================
PRINT 'SUSDB maintenance COMPLETED successfully! - ' + CONVERT(varchar, GETDATE(), 120);
GO
