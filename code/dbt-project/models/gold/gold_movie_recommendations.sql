{{
    config(
        materialized='table'
    )
}}

with movie_analytics as (
    select * from {{ ref('gold_movie_analytics') }}
),

similar_by_genre as (
    select
        a.movie_id as source_movie_id,
        a.title as source_title,
        b.movie_id as recommended_movie_id,
        b.title as recommended_title,
        b.avg_rating as recommended_avg_rating,
        b.total_ratings as recommended_total_ratings,
        b.popularity_score as recommended_popularity,
        a.genres as source_genres,
        b.genres as recommended_genres,
        'genre_similarity' as recommendation_type,
        (
            case when a.is_action = b.is_action then 1 else 0 end +
            case when a.is_comedy = b.is_comedy then 1 else 0 end +
            case when a.is_drama = b.is_drama then 1 else 0 end +
            case when a.is_thriller = b.is_thriller then 1 else 0 end +
            case when a.is_romance = b.is_romance then 1 else 0 end +
            case when a.is_horror = b.is_horror then 1 else 0 end +
            case when a.is_scifi = b.is_scifi then 1 else 0 end
        ) as genre_match_score
    from movie_analytics a
    cross join movie_analytics b
    where a.movie_id != b.movie_id
      and a.decade = b.decade
      and b.avg_rating >= 3.5
      and b.total_ratings >= 10
),

ranked_recommendations as (
    select
        *,
        row_number() over (
            partition by source_movie_id
            order by genre_match_score desc, recommended_popularity desc
        ) as recommendation_rank
    from similar_by_genre
    where genre_match_score >= 3
),

final as (
    select
        source_movie_id,
        source_title,
        recommended_movie_id,
        recommended_title,
        recommended_avg_rating,
        recommended_total_ratings,
        recommended_popularity,
        source_genres,
        recommended_genres,
        recommendation_type,
        genre_match_score,
        recommendation_rank,
        current_timestamp as processed_at
    from ranked_recommendations
    where recommendation_rank <= 10
)

select * from final
