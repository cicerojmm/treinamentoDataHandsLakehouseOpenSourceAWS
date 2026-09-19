{{
    config(
        materialized='table'
    )
}}

with ratings as (
    select * from {{ ref('silver_ratings') }}
),

monthly_stats as (
    select
        rating_month,
        year,
        month,
        count(*) as total_ratings,
        count(distinct user_id) as active_users,
        count(distinct movie_id) as movies_rated,
        round(avg(rating), 2) as avg_rating,
        sum(case when rating_category = 'Excelente' then 1 else 0 end) as ratings_excelente,
        sum(case when rating_category = 'Bom' then 1 else 0 end) as ratings_bom,
        sum(case when rating_category = 'Regular' then 1 else 0 end) as ratings_regular,
        sum(case when rating_category = 'Ruim' then 1 else 0 end) as ratings_ruim
    from ratings
    where rating_month is not null
    group by rating_month, year, month
),

hourly_distribution as (
    select
        hour_of_day,
        count(*) as total_ratings,
        round(avg(rating), 2) as avg_rating
    from ratings
    group by hour_of_day
),

day_of_week_distribution as (
    select
        day_of_week,
        count(*) as total_ratings,
        round(avg(rating), 2) as avg_rating
    from ratings
    group by day_of_week
),

final_monthly as (
    select
        'monthly' as trend_type,
        cast(year as varchar) || '-' || lpad(cast(month as varchar), 2, '0') as period,
        total_ratings,
        active_users,
        movies_rated,
        avg_rating,
        ratings_excelente,
        ratings_bom,
        ratings_regular,
        ratings_ruim,
        cast(null as integer) as hour_or_day,
        current_timestamp as processed_at
    from monthly_stats
),

final_hourly as (
    select
        'hourly' as trend_type,
        cast(hour_of_day as varchar) as period,
        total_ratings,
        cast(null as bigint) as active_users,
        cast(null as bigint) as movies_rated,
        avg_rating,
        cast(null as bigint) as ratings_excelente,
        cast(null as bigint) as ratings_bom,
        cast(null as bigint) as ratings_regular,
        cast(null as bigint) as ratings_ruim,
        hour_of_day as hour_or_day,
        current_timestamp as processed_at
    from hourly_distribution
),

final_dow as (
    select
        'day_of_week' as trend_type,
        cast(day_of_week as varchar) as period,
        total_ratings,
        cast(null as bigint) as active_users,
        cast(null as bigint) as movies_rated,
        avg_rating,
        cast(null as bigint) as ratings_excelente,
        cast(null as bigint) as ratings_bom,
        cast(null as bigint) as ratings_regular,
        cast(null as bigint) as ratings_ruim,
        day_of_week as hour_or_day,
        current_timestamp as processed_at
    from day_of_week_distribution
)

select * from final_monthly
union all
select * from final_hourly
union all
select * from final_dow
