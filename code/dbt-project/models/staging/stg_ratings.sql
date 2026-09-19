with source as (
    select * from {{ source('bronze', 'ratings') }}
),

cleaned as (
    select
        userid as user_id,
        movieid as movie_id,
        rating,
        timestamp as rating_timestamp
    from source
    where userid is not null
      and movieid is not null
      and rating is not null
)

select * from cleaned
