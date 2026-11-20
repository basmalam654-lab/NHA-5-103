/*
=========================================================
Project: Global Shipping Disruption Analytics
Layer: Gold
File: 03_create_gold_tables.sql

Description:
Creates the Gold Layer dimension, fact, and bridge tables.
Includes primary keys, foreign keys, unique constraints,
and check constraints.

Database: global_shipping_dw
=========================================================
*/

USE global_shipping_dw;
GO

-- =====================================================
-- 1. GOLD DIMENSION TABLES
-- =====================================================

-- 1.1 Dimension: Chokepoint
CREATE TABLE gold.dim_chokepoint
(
    chokepoint_id SMALLINT NOT NULL,
    chokepoint_code VARCHAR(20) NOT NULL,
    chokepoint_name VARCHAR(60) NOT NULL,
    fullname VARCHAR(100),
    country VARCHAR(60),
    iso3 CHAR(3),
    continent VARCHAR(30),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),

    CONSTRAINT PK_dim_chokepoint
        PRIMARY KEY (chokepoint_id),

    CONSTRAINT UQ_dim_chokepoint_code
        UNIQUE (chokepoint_code),

    CONSTRAINT UQ_dim_chokepoint_name
        UNIQUE (chokepoint_name)
);
GO


-- 1.2 Dimension: Date
CREATE TABLE gold.dim_date
(
    date_key INT NOT NULL,
    full_date DATE NOT NULL,
    year SMALLINT NOT NULL,
    quarter TINYINT NOT NULL,
    month TINYINT NOT NULL,
    iso_week TINYINT NOT NULL,
    week_start_date DATE NOT NULL,
    day TINYINT NOT NULL,
    day_of_week TINYINT NOT NULL,
    is_weekend BIT NOT NULL,

    CONSTRAINT PK_dim_date
        PRIMARY KEY (date_key),

    CONSTRAINT UQ_dim_date_full_date
        UNIQUE (full_date),

    CONSTRAINT CK_dim_date_quarter
        CHECK (quarter BETWEEN 1 AND 4),

    CONSTRAINT CK_dim_date_month
        CHECK (month BETWEEN 1 AND 12),

    CONSTRAINT CK_dim_date_iso_week
        CHECK (iso_week BETWEEN 1 AND 53),

    CONSTRAINT CK_dim_date_day
        CHECK (day BETWEEN 1 AND 31),

    CONSTRAINT CK_dim_date_weekday
        CHECK (day_of_week BETWEEN 1 AND 7)
);
GO


-- 1.3 Dimension: Vessel Type
CREATE TABLE gold.dim_vessel_type
(
    vessel_type_id SMALLINT NOT NULL,
    type_code VARCHAR(20) NOT NULL,
    type_name VARCHAR(40) NOT NULL,
    is_cargo BIT NOT NULL,

    CONSTRAINT PK_dim_vessel_type
        PRIMARY KEY (vessel_type_id),

    CONSTRAINT UQ_dim_vessel_type_code
        UNIQUE (type_code)
);
GO


-- 1.4 Dimension: Event
CREATE TABLE gold.dim_event
(
    event_id BIGINT NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    event_name VARCHAR(150) NOT NULL,
    alert_level VARCHAR(50),
    country VARCHAR(300),
    start_date DATE NOT NULL,
    end_date DATE,
    severity_text VARCHAR(255),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),

    CONSTRAINT PK_dim_event
        PRIMARY KEY (event_id),

    CONSTRAINT CK_dim_event_dates
        CHECK (end_date IS NULL OR end_date >= start_date)
);
GO


-- =====================================================
-- 2. GOLD FACT TABLES
-- =====================================================

-- 2.1 Fact: Daily Summary
CREATE TABLE gold.fact_daily_summary
(
    chokepoint_id SMALLINT NOT NULL,
    date_key INT NOT NULL,
    source_object_id INT NOT NULL,
    n_cargo INT NOT NULL,
    n_total INT NOT NULL,
    capacity_cargo BIGINT NOT NULL,
    capacity_total BIGINT NOT NULL,

    CONSTRAINT PK_fact_daily_summary
        PRIMARY KEY (chokepoint_id, date_key),

    CONSTRAINT UQ_fact_daily_summary_object
        UNIQUE (source_object_id),

    CONSTRAINT FK_summary_chokepoint
        FOREIGN KEY (chokepoint_id)
        REFERENCES gold.dim_chokepoint(chokepoint_id),

    CONSTRAINT FK_summary_date
        FOREIGN KEY (date_key)
        REFERENCES gold.dim_date(date_key)
);
GO


-- 2.2 Fact: Daily Transit
CREATE TABLE gold.fact_daily_transit
(
    chokepoint_id SMALLINT NOT NULL,
    date_key INT NOT NULL,
    vessel_type_id SMALLINT NOT NULL,
    vessel_count INT NOT NULL,
    capacity BIGINT NOT NULL,

    CONSTRAINT PK_fact_daily_transit
        PRIMARY KEY (chokepoint_id, date_key, vessel_type_id),

    CONSTRAINT FK_transit_chokepoint
        FOREIGN KEY (chokepoint_id)
        REFERENCES gold.dim_chokepoint(chokepoint_id),

    CONSTRAINT FK_transit_date
        FOREIGN KEY (date_key)
        REFERENCES gold.dim_date(date_key),

    CONSTRAINT FK_transit_vessel_type
        FOREIGN KEY (vessel_type_id)
        REFERENCES gold.dim_vessel_type(vessel_type_id)
);
GO


-- =====================================================
-- 3. GOLD BRIDGE TABLE
-- =====================================================

-- 3.1 Bridge: Event - Chokepoint
CREATE TABLE gold.bridge_event_chokepoint
(
    event_id BIGINT NOT NULL,
    chokepoint_id SMALLINT NOT NULL,

    CONSTRAINT PK_bridge_event_chokepoint
        PRIMARY KEY (event_id, chokepoint_id),

    CONSTRAINT FK_bridge_event
        FOREIGN KEY (event_id)
        REFERENCES gold.dim_event(event_id),

    CONSTRAINT FK_bridge_chokepoint
        FOREIGN KEY (chokepoint_id)
        REFERENCES gold.dim_chokepoint(chokepoint_id)
);
GO


-- =====================================================
-- END OF GOLD LAYER TABLE CREATION SCRIPT
-- =====================================================