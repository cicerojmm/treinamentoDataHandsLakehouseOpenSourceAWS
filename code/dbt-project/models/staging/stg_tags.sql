with source as (
    select * from {{ source('bronze', 'tags') }}
),

cleaned as (
    select
        userid as user_id,
        movieid as movie_id,
        trim(tag) as tag,
        timestamp as tag_timestamp
    from source
    where userid is not null
      and movieid is not null
      and tag is not null
)

select * from cleaned
