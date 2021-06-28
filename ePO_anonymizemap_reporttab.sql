-- Create a new Column to hold the anonymize map data, the name of the new column is AnonymizeMap
IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'OrionLastRunReportMT' AND COLUMN_NAME = 'AnonymizeMap')
	ALTER TABLE [dbo].[OrionLastRunReportMT] ADD AnonymizeMap [image];
GO

-- Dropping the OrionLastRunReport and recreating it again as we have added a new column to the OrionLastRunReportMT table.
-- OrionLastRunReport view.
IF EXISTS (SELECT 1 FROM dbo.sysobjects WHERE id = OBJECT_ID(N'[dbo].[OrionLastRunReport]') AND OBJECTPROPERTY(id, N'IsView') = 1)
  BEGIN
    DROP VIEW OrionLastRunReport
  END
GO

-- Creating the more performant tenant filtered view for OrionLastRunReportMT.
CREATE  VIEW [dbo].[OrionLastRunReport] AS
WITH Tenants AS
(
	SELECT dbo.FN_Core_GetContextTenantId() AS TenantId
	UNION
	SELECT TenantId
	FROM OrionTenant
	WHERE
		dbo.FN_Core_IsSystemUserInContext() = 1
)
    SELECT mtt.*
	FROM OrionLastRunReportMT mtt WHERE UserId in (  SELECT Id FROM OrionUsers ou
	JOIN Tenants t ON ou.TenantId = t.TenantId )
GO