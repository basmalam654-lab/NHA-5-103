{{ config(materialized='table') }}

-- Silver: one row per disruption event with readable names, duration, and the affected
-- population turned into a number (approximate: "1.9 million" -> 1,900,000).

with bronze as (

    select * from {{ ref('bronze_disruptions') }}

),

parsed as (

    select
        *,
        nullif(left(affectedpopulation, charindex(' ', affectedpopulation + ' ') - 1), '') as population_number_text
    from bronze

)

select
    eventid                                                  as event_id,
    eventtype                                                as event_type,
    case eventtype
        when 'TC' then 'Tropical cyclone'
        when 'EQ' then 'Earthquake'
        when 'FL' then 'Flood'
        when 'DR' then 'Drought'
        when 'WF' then 'Wildfire'
        when 'VO' then 'Volcano'
        when 'OT' then 'Other'
        else eventtype
    end                                                      as event_type_name,
    eventname                                                as event_name,
    htmlname                                                 as event_title,
    htmldescription                                          as event_description,
    alertlevel                                               as alert_level,
    country                                                  as countries,
    fromdate                                                 as start_at,
    todate                                                   as end_at,
    cast(datediff(hour, fromdate, todate) / 24.0 as decimal(8, 2)) as duration_days,
    severitytext                                             as severity_text,
    lat,
    [long]                                                   as lon,
    affectedports                                            as affected_ports,
    n_affectedports                                          as n_affected_ports,
    affectedpopulation                                       as affected_population_text,
    try_cast(
        try_cast(population_number_text as decimal(12, 2))
        * case
            when affectedpopulation like '%million%'  then 1000000
            when affectedpopulation like '%thousand%' then 1000
            else 1
          end
        as bigint)                                           as affected_population,
    editdate                                                 as last_edited_at
from parsed