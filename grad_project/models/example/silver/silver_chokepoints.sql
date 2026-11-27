{{ config(materialized='table') }}

-- Silver: cleaned chokepoint table. Columns that are empty for every chokepoint
-- (country, iso3, continent, locode, shares) are dropped.

select
    portid                         as chokepoint_id,
    fullname                       as chokepoint_name,
    lat,
    lon,
    X                              as x_mercator,
    Y                              as y_mercator,
    vessel_count_total,
    vessel_count_container,
    vessel_count_dry_bulk,
    vessel_count_general_cargo,
    vessel_count_RoRo              as vessel_count_roro,
    vessel_count_tanker,
    industry_top1,
    industry_top2,
    industry_top3,
    pageid
from {{ ref('bronze_chokepoints') }}