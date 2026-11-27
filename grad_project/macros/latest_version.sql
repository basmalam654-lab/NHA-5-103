{% macro latest_version(relation, key_columns) -%}
(
    select * from (
        select s.*,
               row_number() over (partition by {{ key_columns | join(', ') }}
                                  order by _row_id desc) as _rn
        from {{ relation }} as s
    ) as ranked
    where _rn = 1
)
{%- endmacro %}