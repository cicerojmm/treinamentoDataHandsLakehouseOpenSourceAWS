{{
    config(
        materialized='table'
    )
}}

with source as (
    select * from {{ ref('stg_links') }}
),

enriched as (
    select
        movie_id,
        imdb_id,
        tmdb_id,
        concat('https://www.imdb.com/title/tt', lpad(cast(imdb_id as varchar), 7, '0')) as imdb_url,
        concat('https://www.themoviedb.org/movie/', cast(tmdb_id as varchar)) as tmdb_url,
        current_timestamp as processed_at
    from source
    where movie_id is not null
)

select * from enriched
