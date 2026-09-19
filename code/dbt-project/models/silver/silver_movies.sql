{{
  config(
    materialized='table'
  )
}}

with source as (
    select * from {{ ref('stg_movies') }}
),

enriched as (
    select
        movie_id,
        title,
        try_cast(regexp_extract(title, '\((\d{4})\)$', 1) as integer) as release_year,
        trim(regexp_replace(title, '\s*\(\d{4}\)$', '')) as title_clean,
        genres,
        cardinality(split(genres, '|')) as genres_count,
        strpos(genres, 'Action') > 0 as is_action,
        strpos(genres, 'Comedy') > 0 as is_comedy,
        strpos(genres, 'Drama') > 0 as is_drama,
        strpos(genres, 'Thriller') > 0 as is_thriller,
        strpos(genres, 'Romance') > 0 as is_romance,
        strpos(genres, 'Horror') > 0 as is_horror,
        strpos(genres, 'Sci-Fi') > 0 as is_scifi,
        strpos(genres, 'Animation') > 0 as is_animation,
        strpos(genres, 'Documentary') > 0 as is_documentary,
        floor(try_cast(regexp_extract(title, '\((\d{4})\)$', 1) as integer) / 10) * 10 as decade,
        current_timestamp as processed_at
    from source
    where movie_id is not null
)

select * from enriched
