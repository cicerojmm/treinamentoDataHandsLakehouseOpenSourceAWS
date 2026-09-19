with source as (
    select * from {{ source('bronze', 'movies') }}
),

cleaned as (
    select
        movieid as movie_id,
        trim(title) as title,
        trim(genres) as genres
    from source
    where movieid is not null
)

select * from cleaned
