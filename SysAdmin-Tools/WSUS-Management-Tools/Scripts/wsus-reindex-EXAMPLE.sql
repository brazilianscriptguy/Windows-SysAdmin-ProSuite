USE SUSDB;
GO

-- Rebuild indexes to reduce fragmentation
ALTER INDEX [IX_tbUpdate_TargetId] ON [PUBLIC].[tbUpdate] REBUILD WITH (ONLINE = OFF);
GO

ALTER INDEX [PK_tbRevision] ON [PUBLIC].[tbRevision] REBUILD WITH (ONLINE = OFF);
GO

ALTER INDEX [IX_tbDeployment_ComputerTargetId] ON [PUBLIC].[tbDeployment] REBUILD WITH (ONLINE = OFF);
GO

ALTER INDEX [IX_tbUpdateApproval_ApprovalId] ON [PUBLIC].[tbUpdateApproval] REBUILD WITH (ONLINE = OFF);
GO

-- Add more ALTER INDEX commands as needed
