with source as (
    select * from {{ source('bronze', 'links') }}
),

cleaned as (
    select
        movieid as movie_id,
        imdbid as imdb_id,
        tmdbid as tmdb_id
    from source
    where movieid is not null
)

select * from cleaned
