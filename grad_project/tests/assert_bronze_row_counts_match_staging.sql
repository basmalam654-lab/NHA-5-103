with checks as (
    select 'daily' as model_name,
        (select count(*) from (select distinct [date], portid
            from {{ source('portwatch', 'portwatch_daily_chokepoints') }}) d) as expected_rows,
        (select count(*) from {{ ref('bronze_daily_chokepoints') }}) as actual_rows
    union all
    select 'chokepoints',
        (select count(distinct portid) from {{ source('portwatch', 'portwatch_chokepoints') }}),
        (select count(*) from {{ ref('bronze_chokepoints') }})
    union all
    select 'disruptions',
        (select count(distinct eventid) from {{ source('portwatch', 'portwatch_disruptions') }}),
        (select count(*) from {{ ref('bronze_disruptions') }})
)
select * from checks where expected_rows <> actual_rows