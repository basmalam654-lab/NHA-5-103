{{ config(materialized='table') }}

-- Silver: bridge table, one row per (event, affected port).
-- affected_ports holds ids separated by semicolons, e.g. "port137; port784; port896".

select
    e.event_id,
    ltrim(rtrim(p.value))   as port_id,
    e.event_type,
    e.event_type_name,
    e.event_name,
    e.start_at,
    e.end_at
from {{ ref('silver_disruptions') }} e
cross apply string_split(e.affected_ports, ';') p
where ltrim(rtrim(p.value)) <> ''