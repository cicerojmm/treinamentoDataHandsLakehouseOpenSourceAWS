from fastapi import APIRouter, Depends, HTTPException

from app.auth import verify_api_key
from app.db import query_iceberg

router = APIRouter(prefix="/api/v1", tags=["movies"])


@router.get("/movies")
async def list_movies(limit: int = 20, _: str = Depends(verify_api_key)):
    """Lista filmes com analytics."""
    try:
        return query_iceberg("gold_movie_analytics", f"ORDER BY total_ratings DESC LIMIT {limit}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/movies/{movie_id}")
async def get_movie(movie_id: int, _: str = Depends(verify_api_key)):
    """Detalhes de um filme específico."""
    try:
        results = query_iceberg("gold_movie_analytics", f"WHERE movie_id = {movie_id}")
        if not results:
            raise HTTPException(status_code=404, detail="Movie not found")
        return results[0]
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/genres")
async def list_genres(_: str = Depends(verify_api_key)):
    """Analytics por gênero."""
    try:
        return query_iceberg("gold_genre_analytics", "ORDER BY avg_rating DESC")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/recommendations")
async def get_recommendations(user_id: int = None, limit: int = 10, _: str = Depends(verify_api_key)):
    """Recomendações de filmes."""
    try:
        suffix = f"LIMIT {limit}"
        if user_id:
            suffix = f"WHERE user_id = {user_id} " + suffix
        return query_iceberg("gold_movie_recommendations", suffix)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/trends")
async def get_trends(_: str = Depends(verify_api_key)):
    """Tendências temporais de ratings."""
    try:
        return query_iceberg("gold_temporal_trends", "ORDER BY period DESC LIMIT 24")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/users")
async def list_users(limit: int = 20, _: str = Depends(verify_api_key)):
    """Top usuários por engajamento."""
    try:
        return query_iceberg("gold_user_behavior", f"ORDER BY total_ratings DESC LIMIT {limit}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
