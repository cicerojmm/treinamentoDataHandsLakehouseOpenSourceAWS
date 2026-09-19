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

movie_ratings as (
    select
        m.movie_id,
        m.is_action,
        m.is_comedy,
        m.is_drama,
        m.is_thriller,
        m.is_romance,
        m.is_horror,
        m.is_scifi,
        m.is_animation,
        m.is_documentary,
        m.decade,
        r.rating,
        r.user_id,
        r.rating_datetime
    from movies m
    inner join ratings r on m.movie_id = r.movie_id
),

genre_stats as (
    select
        'Action' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_action = true

    union all

    select
        'Comedy' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_comedy = true

    union all

    select
        'Drama' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_drama = true

    union all

    select
        'Thriller' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_thriller = true

    union all

    select
        'Romance' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_romance = true

    union all

    select
        'Horror' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_horror = true

    union all

    select
        'Sci-Fi' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_scifi = true

    union all

    select
        'Animation' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_animation = true

    union all

    select
        'Documentary' as genre,
        count(*) as total_ratings,
        count(distinct movie_id) as total_movies,
        count(distinct user_id) as total_users,
        round(avg(rating), 2) as avg_rating,
        round(stddev(rating), 2) as stddev_rating
    from movie_ratings where is_documentary = true
),

final as (
    select
        genre,
        total_ratings,
        total_movies,
        total_users,
        avg_rating,
        stddev_rating,
        round(cast(total_ratings as double) / nullif(total_movies, 0), 2) as avg_ratings_per_movie,
        round(cast(total_ratings as double) / nullif(total_users, 0), 2) as avg_ratings_per_user,
        current_timestamp as processed_at
    from genre_stats
)

select * from final
order by total_ratings desc
