-- SPEC-016 re-validation: no-op comment to trigger airflow-dags.yml CI (2026-09-24)
{{
    config(
        materialized='table'
    )
}}

with links as (
    select * from {{ ref('silver_links') }}
),

movies as (
    select * from {{ ref('silver_movies') }}
),

ratings as (
    select * from {{ ref('silver_ratings') }}
),

movie_stats as (
    select
        movie_id,
        count(*) as total_ratings,
        round(avg(rating), 2) as avg_rating
    from ratings
    group by movie_id
),

final as (
    select
        l.movie_id,
        m.title_clean as title,
        m.release_year,
        m.genres,

        l.imdb_id,
        l.tmdb_id,
        l.imdb_url,
        l.tmdb_url,

        case
            when l.imdb_id is not null then true
            else false
        end as has_imdb,

        case
            when l.tmdb_id is not null then true
            else false
        end as has_tmdb,

        case
            when l.imdb_id is not null and l.tmdb_id is not null then 'Complete'
            when l.imdb_id is not null or l.tmdb_id is not null then 'Partial'
            else 'Missing'
        end as link_status,

        coalesce(s.total_ratings, 0) as total_ratings,
        s.avg_rating,

        current_timestamp as processed_at

    from links l
    inner join movies m on l.movie_id = m.movie_id
    left join movie_stats s on l.movie_id = s.movie_id
)

select * from final
