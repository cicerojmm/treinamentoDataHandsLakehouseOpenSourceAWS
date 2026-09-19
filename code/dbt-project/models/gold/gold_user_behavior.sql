{{
    config(
        materialized='table'
    )
}}

with ratings as (
    select * from {{ ref('silver_ratings') }}
),

tags as (
    select * from {{ ref('silver_tags') }}
),

user_rating_stats as (
    select
        user_id,
        count(*) as total_ratings,
        count(distinct movie_id) as movies_rated,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating,
        min(rating) as min_rating,
        max(rating) as max_rating,
        sum(case when rating_category = 'Excelente' then 1 else 0 end) as ratings_excelente,
        sum(case when rating_category = 'Bom' then 1 else 0 end) as ratings_bom,
        sum(case when rating_category = 'Regular' then 1 else 0 end) as ratings_regular,
        sum(case when rating_category = 'Ruim' then 1 else 0 end) as ratings_ruim,
        min(rating_datetime) as first_rating,
        max(rating_datetime) as last_rating,
        date_diff('day', min(rating_datetime), max(rating_datetime)) as days_active,
        approx_percentile(hour_of_day, 0.5) as typical_hour
    from ratings
    group by user_id
),

user_tag_stats as (
    select
        user_id,
        count(*) as total_tags,
        count(distinct movie_id) as movies_tagged,
        count(distinct tag_normalized) as unique_tags,
        sum(case when sentiment = 'Positivo' then 1 else 0 end) as positive_tags,
        sum(case when sentiment = 'Negativo' then 1 else 0 end) as negative_tags
    from tags
    group by user_id
),

final as (
    select
        r.user_id,
        r.total_ratings,
        r.movies_rated,
        r.avg_rating,
        r.stddev_rating,
        r.ratings_excelente,
        r.ratings_bom,
        r.ratings_regular,
        r.ratings_ruim,
        r.first_rating,
        r.last_rating,
        r.days_active,
        r.typical_hour,

        coalesce(t.total_tags, 0) as total_tags,
        coalesce(t.movies_tagged, 0) as movies_tagged,
        coalesce(t.unique_tags, 0) as unique_tags,

        case
            when r.total_ratings >= 500 then 'Power User'
            when r.total_ratings >= 100 then 'Active'
            when r.total_ratings >= 20 then 'Regular'
            else 'Casual'
        end as user_segment,

        case
            when r.avg_rating >= 4.0 then 'Generoso'
            when r.avg_rating >= 3.0 then 'Equilibrado'
            else 'Crítico'
        end as rating_style,

        case
            when r.stddev_rating >= 1.5 then 'Polarizado'
            when r.stddev_rating >= 1.0 then 'Variado'
            else 'Consistente'
        end as rating_consistency,

        current_timestamp as processed_at

    from user_rating_stats r
    left join user_tag_stats t on r.user_id = t.user_id
)

select * from final
