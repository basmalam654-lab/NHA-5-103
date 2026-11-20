/* =====================================================
   Creation of the 3 Bronze tables
   ===================================================== */

USE global_shipping_dw;
GO

-- Drop the load views first preventing errors in rerun
DROP VIEW IF EXISTS bronze.vw_load_daily_chokepoints_data;
DROP VIEW IF EXISTS bronze.vw_load_portwatch_chokepoints_database;
DROP VIEW IF EXISTS bronze.vw_load_portwatch_disruptions_database;
GO

DROP TABLE IF EXISTS bronze.Daily_Chokepoints_Data;
DROP TABLE IF EXISTS bronze.PortWatch_chokepoints_database;
DROP TABLE IF EXISTS bronze.[portwatch_disruptions_database(1)];
GO


/* =====================================================
   TABLE 1: DAILY CHOKEPOINTS DATA
   Source: Daily_Chokepoints_Data.csv
   ===================================================== */
CREATE TABLE bronze.Daily_Chokepoints_Data
(
    [date]                  VARCHAR(10)   NULL,
    [year]                  INT           NULL,
    [month]                 INT           NULL,
    [day]                   INT           NULL,
    portid                  VARCHAR(20)   NULL,
    portname                NVARCHAR(100) NULL,
    n_container             INT           NULL,
    n_dry_bulk              INT           NULL,
    n_general_cargo         INT           NULL,
    n_roro                  INT           NULL,
    n_tanker                INT           NULL,
    n_cargo                 INT           NULL,
    n_total                 INT           NULL,
    capacity_container      BIGINT        NULL,
    capacity_dry_bulk       BIGINT        NULL,
    capacity_general_cargo  BIGINT        NULL,
    capacity_roro           BIGINT        NULL,
    capacity_tanker         BIGINT        NULL,
    capacity_cargo          BIGINT        NULL,
    capacity                BIGINT        NULL,
    ObjectId                INT           NULL,
    load_date               DATETIME2(0)  NOT NULL
        CONSTRAINT DF_bronze_daily_load_date DEFAULT SYSDATETIME()
);
GO


/* =====================================================
   TABLE 2: CHOKEPOINTS REFERENCE
   Source: PortWatch_chokepoints_database.csv
   ===================================================== */
CREATE TABLE bronze.PortWatch_chokepoints_database
(
    X                              FLOAT         NULL,
    Y                              FLOAT         NULL,
    portid                         VARCHAR(20)   NULL,
    portname                       NVARCHAR(100) NULL,
    country                        NVARCHAR(100) NULL,
    ISO3                           VARCHAR(10)   NULL,
    continent                      NVARCHAR(50)  NULL,
    fullname                       NVARCHAR(100) NULL,
    lat                            FLOAT         NULL,
    lon                            FLOAT         NULL,
    vessel_count_total             INT           NULL,
    vessel_count_container         INT           NULL,
    vessel_count_dry_bulk          INT           NULL,
    vessel_count_general_cargo     INT           NULL,
    vessel_count_RoRo              INT           NULL,
    vessel_count_tanker            INT           NULL,
    industry_top1                  NVARCHAR(100) NULL,
    industry_top2                  NVARCHAR(100) NULL,
    industry_top3                  NVARCHAR(100) NULL,
    share_country_maritime_import  FLOAT         NULL,
    share_country_maritime_export  FLOAT         NULL,
    LOCODE                         VARCHAR(20)   NULL,
    pageid                         VARCHAR(50)   NULL,
    countrynoaccents               NVARCHAR(100) NULL,
    ObjectId                       INT           NULL,
    load_date                      DATETIME2(0)  NOT NULL
        CONSTRAINT DF_bronze_chokepoints_load_date DEFAULT SYSDATETIME()
);
GO


/* =====================================================
   TABLE 3: EVENTS (DISRUPTIONS)
   Source: portwatch_disruptions_database.csv
   ===================================================== */
CREATE TABLE bronze.[portwatch_disruptions_database(1)]
(
    eventid              BIGINT         NULL,
    eventtype            VARCHAR(10)    NULL,
    eventname            NVARCHAR(200)  NULL,
    htmlname             NVARCHAR(200)  NULL,
    htmldescription      NVARCHAR(500)  NULL,
    alertlevel           VARCHAR(20)    NULL,
    country              NVARCHAR(300)  NULL,
    fromdate             VARCHAR(30)    NULL,
    [year]               INT            NULL,
    todate               VARCHAR(30)    NULL,
    severitytext         NVARCHAR(300)  NULL,
    lat                  FLOAT          NULL,
    [long]               FLOAT          NULL,
    editdate             VARCHAR(30)    NULL,
    affectedports        NVARCHAR(1000) NULL,
    n_affectedports      INT            NULL,
    affectedpopulation   NVARCHAR(200)  NULL,
    pageid               VARCHAR(50)    NULL,
    ObjectId             INT            NULL,
    Shape__Area          FLOAT          NULL,
    Shape__Length        FLOAT          NULL,
    load_date            DATETIME2(0)   NOT NULL
        CONSTRAINT DF_bronze_events_load_date DEFAULT SYSDATETIME()
);
GO


/* =====================================================
   LOAD VIEWS
   ===================================================== */
CREATE VIEW bronze.vw_load_daily_chokepoints_data
AS
SELECT
    [date], [year], [month], [day], portid, portname,
    n_container, n_dry_bulk, n_general_cargo, n_roro, n_tanker, n_cargo, n_total,
    capacity_container, capacity_dry_bulk, capacity_general_cargo, capacity_roro,
    capacity_tanker, capacity_cargo, capacity, ObjectId
FROM bronze.Daily_Chokepoints_Data;
GO

CREATE VIEW bronze.vw_load_portwatch_chokepoints_database
AS
SELECT
    X, Y, portid, portname, country, ISO3, continent, fullname, lat, lon,
    vessel_count_total, vessel_count_container, vessel_count_dry_bulk,
    vessel_count_general_cargo, vessel_count_RoRo, vessel_count_tanker,
    industry_top1, industry_top2, industry_top3,
    share_country_maritime_import, share_country_maritime_export,
    LOCODE, pageid, countrynoaccents, ObjectId
FROM bronze.PortWatch_chokepoints_database;
GO

CREATE VIEW bronze.vw_load_portwatch_disruptions_database
AS
SELECT
    eventid, eventtype, eventname, htmlname, htmldescription, alertlevel,
    country, fromdate, [year], todate, severitytext, lat, [long], editdate,
    affectedports, n_affectedports, affectedpopulation, pageid, ObjectId,
    Shape__Area, Shape__Length
FROM bronze.[portwatch_disruptions_database(1)];
GO