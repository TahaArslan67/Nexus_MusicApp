"""Search Router — Quota-Aware Search

Strategy:
1. First search local DB (zero quota cost)
2. Only search YouTube if no local results found (costs 100 quota)
3. Prefer ID-based follow-up lookups for details
"""

from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import get_session, User, Song
from app.schemas.music import SongResponse
from app.services.search import search_local_fuzzy, search_local, search_youtube
from app.services.quota import consume_quota, get_search_quota_cost
from app.services.cache import get_cached_path
from app.routers.auth_router import require_user

router = APIRouter(prefix="/search", tags=["Search"])


@router.get("", response_model=List[SongResponse])
async def search(
    q: str = Query(..., min_length=1, max_length=200, description="Search query"),
    source: str = Query("auto", regex="^(auto|local|youtube)$"),
    limit: int = Query(10, ge=1, le=50),
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Search for songs.

    'auto' mode: tries local DB first, falls back to YouTube.
    'local' mode: only searches cached songs (zero quota cost).
    'youtube' mode: forces YouTube search (costs 100 quota).

    After finding results, use /music/info/{id} for details (1 quota).
    """
    results: List[SongResponse] = []

    if source in ("auto", "local"):
        # Step 1: Fuzzy search local DB (free — zero quota cost!)
        # search_local_fuzzy yazım hatalarını tolere eder, token bazlı eşleşme yapar
        local_results = await search_local_fuzzy(db, q, limit)
        # Fallback: eğer fuzzy sonuç vermezse LIKE ile dene
        if not local_results:
            local_results = await search_local(db, q, limit)
        for song in local_results:
            results.append(SongResponse(
                id=song.id,
                youtube_id=song.youtube_id,
                title=song.title,
                artist=song.artist,
                duration_seconds=song.duration_seconds,
                thumbnail_url=song.thumbnail_url,
                audio_url=song.audio_url,
                is_cached=get_cached_path(song.youtube_id) is not None,
            ))

        if source == "local":
            return results

        # If we have enough local results, return them
        if len(results) >= limit:
            return results[:limit]

    # Step 2: Search YouTube (costs 100 quota)
    if source in ("auto", "youtube"):
        if not await consume_quota(db, user, get_search_quota_cost()):
            # Return local results if quota exhausted
            if results:
                return results
            raise HTTPException(
                status_code=429,
                detail="Daily quota exhausted for search. Try searching cached songs only.",
            )

        yt_results = await search_youtube(q, max_results=limit)

        # Merge: avoid duplicates with local results
        existing_ids = {r.youtube_id for r in results}
        for item in yt_results:
            if item["id"] not in existing_ids:
                results.append(SongResponse(
                    id=0,  # Not yet in DB
                    youtube_id=item["id"],
                    title=item["title"],
                    artist=item["artist"],
                    duration_seconds=item["duration"],
                    thumbnail_url=item["thumbnail"],
                    audio_url="",
                    is_cached=get_cached_path(item["id"]) is not None,
                ))
                existing_ids.add(item["id"])

    return results[:limit]


@router.get("/suggestions")
async def get_suggestions(
    q: str = Query(..., min_length=1, max_length=100),
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Get search suggestions from local DB only (zero quota cost).

    Returns just titles for autocomplete suggestions.
    """
    from sqlalchemy import select

    stmt = (
        select(Song.title)
        .where(Song.title.ilike(f"{q}%"))
        .distinct()
        .limit(8)
    )
    result = await db.execute(stmt)
    suggestions = [row[0] for row in result.all()]

    return {"suggestions": suggestions}