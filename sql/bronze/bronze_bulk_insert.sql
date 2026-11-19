/* =====================================================
   Load the 3 raw CSV files into the Bronze tables (BULK INSERT)

   Before you run (run create_bronze_tables.sql first):
     Change @data_folder below to the folder where YOUR copy of the repo
        keeps data\raw\snapshot_2026-11-08\
   ===================================================== */

USE global_shipping_dw;
GO

/* ---------- change only these two lines ---------- */
DECLARE @data_folder NVARCHAR(400) = N'path\data\raw\snapshot_2026-11-08\';

-- Line ending of the CSV files:
--   '0x0a'   = LF   (the files as stored in the repo)
--   '0x0d0a' = CRLF (use this if Git on Windows converted them when you cloned)
-- Tip: open the CSV in VS Code or Notepad++ - the status bar shows LF or CRLF.
DECLARE @row_terminator NVARCHAR(10)  = N'0x0a';
/* ------------------------------------------------------------ */

DECLARE @sql     NVARCHAR(MAX);
DECLARE @options NVARCHAR(MAX);

IF @data_folder LIKE N'%path\to%'
    THROW 50001, 'Change @data_folder to the folder that holds your CSV files, then run again.', 1;

IF RIGHT(@data_folder, 1) <> N'\'
    SET @data_folder = @data_folder + N'\';

SET @options =
      N'FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'', FIELDTERMINATOR = '','', '
    + N'ROWTERMINATOR = ''' + @row_terminator + N''', CODEPAGE = ''65001'', KEEPNULLS, TABLOCK';

BEGIN TRY

    -- 1. Daily chokepoints data
    TRUNCATE TABLE bronze.Daily_Chokepoints_Data;
    SET @sql = N'BULK INSERT bronze.vw_load_daily_chokepoints_data FROM '''
             + @data_folder + N'Daily_Chokepoints_Data.csv'' WITH (' + @options + N');';
    EXEC sys.sp_executesql @sql;

    -- 2. Chokepoints reference
    TRUNCATE TABLE bronze.PortWatch_chokepoints_database;
    SET @sql = N'BULK INSERT bronze.vw_load_portwatch_chokepoints_database FROM '''
             + @data_folder + N'PortWatch_chokepoints_database.csv'' WITH (' + @options + N');';
    EXEC sys.sp_executesql @sql;

    -- 3. Events (disruptions)
    TRUNCATE TABLE bronze.[portwatch_disruptions_database(1)];
    SET @sql = N'BULK INSERT bronze.vw_load_portwatch_disruptions_database FROM '''
             + @data_folder + N'portwatch_disruptions_database.csv'' WITH (' + @options + N');';
    EXEC sys.sp_executesql @sql;

END TRY
BEGIN CATCH
    PRINT 'LOAD FAILED. Read the error below. Common causes: wrong @data_folder,';
    PRINT 'wrong @row_terminator, or the SQL Server service cannot read the folder.';
    THROW;
END CATCH;

-- Row-count check
SELECT 'bronze.Daily_Chokepoints_Data' AS table_name,
       COUNT(*) AS rows_loaded, 80332 AS rows_expected,
       CASE WHEN COUNT(*) = 80332 THEN 'OK' ELSE 'CHECK' END AS status,
       MAX(load_date) AS load_date
FROM bronze.Daily_Chokepoints_Data
UNION ALL
SELECT 'bronze.PortWatch_chokepoints_database',
       COUNT(*), 28,
       CASE WHEN COUNT(*) = 28 THEN 'OK' ELSE 'CHECK' END,
       MAX(load_date)
FROM bronze.PortWatch_chokepoints_database
UNION ALL
SELECT 'bronze.portwatch_disruptions_database(1)',
       COUNT(*), 132,
       CASE WHEN COUNT(*) = 132 THEN 'OK' ELSE 'CHECK' END,
       MAX(load_date)
FROM bronze.[portwatch_disruptions_database(1)];
GO