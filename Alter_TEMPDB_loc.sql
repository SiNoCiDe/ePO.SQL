USE MASTER
GO

ALTER DATABASE tempdb
MODIFY FILE (name=tempdev, FILENAME = 'F:\TEMPDB\tempdb.mdf')
GO

ALTER DATABASE tempdb
MODIFY FILE (name=templog FILENAME = 'F:\TEMPDB\tempdb.ldf')
GO

ALTER DATABASE tempdb
MODIFY FILE (name=temp2 FILENAME = 'F:\TEMPDB\tempdb_mssql_2.ndf')
GO
