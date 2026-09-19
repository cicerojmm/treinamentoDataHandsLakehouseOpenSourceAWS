{{
    config(
        materialized='table'
    )
}}

with source as (
    select * from {{ ref('stg_ratings') }}
),

enriched as (
    select
        user_id,
        movie_id,
        cast(rating as double) as rating,
        rating_timestamp,
        from_unixtime(cast(rating_timestamp as bigint)) as rating_datetime,
        date_trunc('day', from_unixtime(cast(rating_timestamp as bigint))) as rating_date,
        date_trunc('month', from_unixtime(cast(rating_timestamp as bigint))) as rating_month,
        date_trunc('year', from_unixtime(cast(rating_timestamp as bigint))) as rating_year,
        year(from_unixtime(cast(rating_timestamp as bigint))) as year,
        month(from_unixtime(cast(rating_timestamp as bigint))) as month,
        day_of_week(from_unixtime(cast(rating_timestamp as bigint))) as day_of_week,
        hour(from_unixtime(cast(rating_timestamp as bigint))) as hour_of_day,
        case
            when cast(rating as double) >= 4.5 then 'Excelente'
            when cast(rating as double) >= 3.5 then 'Bom'
            when cast(rating as double) >= 2.5 then 'Regular'
            else 'Ruim'
        end as rating_category,
        current_timestamp as processed_at
    from source
    where cast(rating as double) between 0.5 and 5.0
)

select * from enriched
