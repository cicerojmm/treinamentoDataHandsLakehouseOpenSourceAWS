{{
    config(
        materialized='table'
    )
}}

with source as (
    select * from {{ ref('stg_tags') }}
),

enriched as (
    select
        user_id,
        movie_id,
        lower(trim(tag)) as tag_normalized,
        tag as tag_original,
        tag_timestamp,
        from_unixtime(try_cast(tag_timestamp as bigint)) as tag_datetime,
        date_trunc('month', from_unixtime(try_cast(tag_timestamp as bigint))) as tag_month,
        year(from_unixtime(try_cast(tag_timestamp as bigint))) as year,
        case
            when lower(tag) like '%love%' or lower(tag) like '%great%' or lower(tag) like '%best%'
                or lower(tag) like '%amazing%' or lower(tag) like '%excellent%' then 'Positivo'
            when lower(tag) like '%hate%' or lower(tag) like '%bad%' or lower(tag) like '%worst%'
                or lower(tag) like '%terrible%' or lower(tag) like '%awful%' then 'Negativo'
            else 'Neutro'
        end as sentiment,
        case
            when lower(tag) like '%funny%' or lower(tag) like '%comedy%' then 'Humor'
            when lower(tag) like '%action%' or lower(tag) like '%fight%' then 'Ação'
            when lower(tag) like '%romantic%' or lower(tag) like '%love%' then 'Romance'
            when lower(tag) like '%scary%' or lower(tag) like '%horror%' then 'Terror'
            when lower(tag) like '%twist%' or lower(tag) like '%plot%' then 'Enredo'
            else 'Outros'
        end as tag_category,
        length(tag) as tag_length,
        current_timestamp as processed_at
    from source
    where trim(tag) != ''
)

select * from enriched
