{{
    config(
        materialized='table'
    )
}}

with movies as (
    select * from {{ ref('silver_movies') }}
),

ratings as (
    select * from {{ ref('silver_ratings') }}
),

tags as (
    select * from {{ ref('silver_tags') }}
),

movie_metrics as (
    select
        r.movie_id,
        count(distinct r.user_id) as total_users,
        count(*) as total_ratings,
        round(avg(r.rating), 2) as avg_rating,
        round(stddev(r.rating), 2) as stddev_rating,
        min(r.rating) as min_rating,
        max(r.rating) as max_rating,
        approx_percentile(r.rating, 0.25) as rating_p25,
        approx_percentile(r.rating, 0.50) as rating_median,
        approx_percentile(r.rating, 0.75) as rating_p75,
        sum(case when r.rating_category = 'Excelente' then 1 else 0 end) as ratings_excelente,
        sum(case when r.rating_category = 'Bom' then 1 else 0 end) as ratings_bom,
        sum(case when r.rating_category = 'Regular' then 1 else 0 end) as ratings_regular,
        sum(case when r.rating_category = 'Ruim' then 1 else 0 end) as ratings_ruim,
        min(r.rating_datetime) as first_rating_date,
        max(r.rating_datetime) as last_rating_date,
        date_diff('day', min(r.rating_datetime), max(r.rating_datetime)) as days_active
    from ratings r
    group by r.movie_id
),

tag_metrics as (
    select
        t.movie_id,
        count(*) as total_tags,
        count(distinct t.user_id) as users_with_tags,
        count(distinct t.tag_normalized) as unique_tags,
        sum(case when t.sentiment = 'Positivo' then 1 else 0 end) as tags_positivas,
        sum(case when t.sentiment = 'Negativo' then 1 else 0 end) as tags_negativas,
        sum(case when t.sentiment = 'Neutro' then 1 else 0 end) as tags_neutras
    from tags t
    group by t.movie_id
),

final as (
    select
        m.movie_id,
        m.title_clean as title,
        m.release_year,
        m.decade,
        m.genres,
        m.genres_count,
        m.is_action,
        m.is_comedy,
        m.is_drama,
        m.is_thriller,
        m.is_romance,
        m.is_horror,
        m.is_scifi,

        coalesce(mm.total_users, 0) as total_users,
        coalesce(mm.total_ratings, 0) as total_ratings,
        mm.avg_rating,
        mm.stddev_rating,
        mm.rating_median,
        mm.ratings_excelente,
        mm.ratings_bom,
        mm.ratings_regular,
        mm.ratings_ruim,
        mm.first_rating_date,
        mm.last_rating_date,
        mm.days_active,

        coalesce(tm.total_tags, 0) as total_tags,
        coalesce(tm.unique_tags, 0) as unique_tags,
        coalesce(tm.tags_positivas, 0) as tags_positivas,
        coalesce(tm.tags_negativas, 0) as tags_negativas,

        round(
            (coalesce(mm.avg_rating, 0) * 0.4) +
            (least(ln(coalesce(mm.total_ratings, 1) + 1), 10) * 0.3) +
            (least(ln(coalesce(tm.total_tags, 1) + 1), 5) * 0.3),
            2
        ) as popularity_score,

        case
            when mm.avg_rating >= 4.0 and mm.total_ratings >= 100 then 'Blockbuster'
            when mm.avg_rating >= 3.5 and mm.total_ratings >= 50 then 'Popular'
            when mm.avg_rating >= 3.0 then 'Mediano'
            when mm.avg_rating < 3.0 and mm.total_ratings >= 20 then 'Impopular'
            else 'Pouco Avaliado'
        end as quality_tier,

        case
            when mm.total_ratings >= 1000 then 'Alto'
            when mm.total_ratings >= 100 then 'Médio'
            when mm.total_ratings >= 10 then 'Baixo'
            else 'Muito Baixo'
        end as engagement_level,

        current_timestamp as processed_at

    from movies m
    left join movie_metrics mm on m.movie_id = mm.movie_id
    left join tag_metrics tm on m.movie_id = tm.movie_id
)

select * from final
