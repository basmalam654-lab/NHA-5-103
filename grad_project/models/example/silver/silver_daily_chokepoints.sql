{{ config(materialized='table') }}

-- Silver: daily transits per chokepoint, enriched with the chokepoint name and location,
-- date parts taken from the real date, and a few ratios.

select
    d.[date]                                         as transit_date,
    year(d.[date])                                   as transit_year,
    month(d.[date])                                  as transit_month,
    datepart(quarter, d.[date])                      as transit_quarter,
    datename(weekday, d.[date])                      as transit_weekday,
    d.portid                                         as chokepoint_id,
    c.chokepoint_name,
    c.lat,
    c.lon,
    d.n_container,
    d.n_dry_bulk,
    d.n_general_cargo,
    d.n_roro,
    d.n_tanker,
    d.n_cargo,
    d.n_total,
    d.capacity_container,
    d.capacity_dry_bulk,
    d.capacity_general_cargo,
    d.capacity_roro,
    d.capacity_tanker,
    d.capacity_cargo,
    d.capacity,
    cast(d.n_tanker * 1.0 / nullif(d.n_total, 0) as decimal(6, 4))  as tanker_share_of_vessels,
    cast(d.capacity * 1.0 / nullif(d.n_total, 0) as decimal(18, 2)) as avg_capacity_per_vessel
from {{ ref('bronze_daily_chokepoints') }} d
left join {{ ref('silver_chokepoints') }} c
    on c.chokepoint_id = d.portid
where d.[date] is not null