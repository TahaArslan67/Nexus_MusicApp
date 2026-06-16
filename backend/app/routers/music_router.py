"""Music Router — Stream, Download, Library Management

Preferred approach: ID-based lookups (costs 1 quota unit per lookup).
Avoid repeated searches — save results in local DB.
"""

import asyncio
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse, FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import STREAM_CHUNK_SIZE
from app.models.database import get_session, User, Song, LibrarySong
from app.schemas.music import SongResponse, StreamInfo, LibraryResponse
from app.services.youtube import (
    fetch_metadata, get_stream_url, download_audio, get_or_create_song,
)
from app.services.jiosaavn import search_songs, get_song_details
from app.services.soundcloud import search_tracks, get_stream_url as get_soundcloud_stream, get_track_info
from app.services.cache import (
    metadata_cache, stream_cache, get_cached_path, get_cache_size_mb,
)
from app.services.quota import consume_quota
from app.services.search import get_search_quota_cost, get_detail_quota_cost
from app.routers.auth_router import require_user

router = APIRouter(prefix="/music", tags=["Music"])


@router.get("/info/{youtube_id}", response_model=SongResponse)
async def get_song_info(
    youtube_id: str,
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Get song metadata by YouTube ID (costs ~1 quota unit).

    Cached results are free — first lookup stores in DB.
    """
    # Check in-memory cache first
    cache_key = f"meta:{youtube_id}"
    cached = metadata_cache.get(cache_key)
    if cached:
        return SongResponse(**cached)

    # Check DB
    from app.services.youtube import get_or_create_song
    song = await get_or_create_song(db, youtube_id)

    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    # Consume quota (1 unit for detail lookup)
    if not await consume_quota(db, user, get_detail_quota_cost()):
        raise HTTPException(status_code=429, detail="Daily quota exhausted")

    # Check local cache
    local_path = get_cached_path(youtube_id)

    resp = SongResponse(
        id=song.id,
        youtube_id=song.youtube_id,
        title=song.title,
        artist=song.artist,
        duration_seconds=song.duration_seconds,
        thumbnail_url=song.thumbnail_url,
        audio_url=song.audio_url,
        is_cached=local_path is not None,
    )

    # Cache in memory
    metadata_cache.set(cache_key, resp.model_dump())
    return resp


@router.get("/stream/{youtube_id}")
async def stream_song(
    youtube_id: str,
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Stream audio from YouTube (auth required)."""
    cache_key = f"stream:{youtube_id}"
    cached = stream_cache.get(cache_key)
    if cached:
        return StreamInfo(**cached)

    local_path = get_cached_path(youtube_id)
    if local_path:
        if not await consume_quota(db, user, get_detail_quota_cost()):
            raise HTTPException(status_code=429, detail="Daily quota exhausted")
        return FileResponse(
            path=local_path,
            media_type="audio/webm",
            filename=f"{youtube_id}.webm",
            headers={"X-Cache": "HIT", "X-Cache-Location": "local"}
        )

    song = await get_or_create_song(db, youtube_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    if not await consume_quota(db, user, get_detail_quota_cost()):
        raise HTTPException(status_code=429, detail="Daily quota exhausted")

    stream = await get_stream_url(youtube_id)
    if not stream:
        raise HTTPException(status_code=502, detail="Failed to get stream URL")

    result = StreamInfo(
        youtube_id=youtube_id,
        title=song.title,
        artist=song.artist,
        duration_seconds=song.duration_seconds,
        stream_url=stream["url"],
        content_type=stream["content_type"],
    )
    stream_cache.set(cache_key, result.model_dump(), ttl=300)
    return result


# ── PUBLIC STREAM (no auth) ─────────────────────────────────────────────────
import aiohttp

@router.get("/public/stream/{youtube_id}")
async def public_stream(youtube_id: str):
    """Public stream endpoint — no auth required.
    Proxies the YouTube audio stream through the backend.
    """
    cache_key = f"stream:{youtube_id}"
    cached = stream_cache.get(cache_key)
    if cached:
        stream_url = cached["stream_url"]
        content_type = cached.get("content_type", "audio/mp4")
    else:
        stream = await get_stream_url(youtube_id)
        if not stream:
            raise HTTPException(status_code=502, detail="Failed to get stream URL")
        stream_url = stream["url"]
        content_type = stream["content_type"]
        stream_cache.set(cache_key, {
            "youtube_id": youtube_id,
            "stream_url": stream_url,
            "content_type": content_type,
        }, ttl=300)

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://www.youtube.com/",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.9",
    }

    async def generate():
        timeout = aiohttp.ClientTimeout(total=None, connect=30, sock_read=30)
        async with aiohttp.ClientSession(timeout=timeout) as session:
            async with session.get(stream_url, headers=headers) as resp:
                async for chunk in resp.content.iter_chunked(8192):
                    yield chunk

    return StreamingResponse(
        generate(),
        media_type=content_type,
        headers={"Accept-Ranges": "bytes"},
    )


@router.post("/download/{youtube_id}")
async def download_song(
    youtube_id: str,
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Download song for offline playback (costs ~1 quota unit)."""
    # Get or create song record
    song = await get_or_create_song(db, youtube_id)
    if not song:
        raise HTTPException(status_code=404, detail="Song not found")

    if not await consume_quota(db, user, get_detail_quota_cost()):
        raise HTTPException(status_code=429, detail="Daily quota exhausted")

    # Check if already cached
    local_path = get_cached_path(youtube_id)
    if not local_path:
        local_path = await download_audio(youtube_id)

    if not local_path:
        raise HTTPException(status_code=502, detail="Download failed")

    # Add to user's library
    existing = await db.execute(
        select(LibrarySong).where(
            LibrarySong.user_id == user.id,
            LibrarySong.song_id == song.id,
        )
    )
    lib_entry = existing.scalar_one_or_none()

    if not lib_entry:
        lib_entry = LibrarySong(
            user_id=user.id,
            song_id=song.id,
            is_downloaded=True,
            file_path=local_path,
        )
        db.add(lib_entry)
        await db.commit()

    return {"status": "downloaded", "file_path": local_path, "song_id": song.id}


@router.get("/library", response_model=List[LibraryResponse])
async def get_library(
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Get user's music library (cached songs). Costs 0 quota."""
    result = await db.execute(
        select(LibrarySong)
        .where(LibrarySong.user_id == user.id)
        .order_by(LibrarySong.added_at.desc())
    )
    entries = result.scalars().all()

    response = []
    for entry in entries:
        song = await db.get(Song, entry.song_id)
        if song:
            response.append(LibraryResponse(
                id=entry.id,
                song=SongResponse(
                    id=song.id,
                    youtube_id=song.youtube_id,
                    title=song.title,
                    artist=song.artist,
                    duration_seconds=song.duration_seconds,
                    thumbnail_url=song.thumbnail_url,
                    audio_url=song.audio_url,
                    is_cached=get_cached_path(song.youtube_id) is not None,
                ),
                is_downloaded=entry.is_downloaded,
                added_at=entry.added_at.isoformat(),
            ))
    return response


@router.delete("/library/{song_id}", status_code=204)
async def remove_from_library(
    song_id: int,
    user: User = Depends(require_user),
    db: AsyncSession = Depends(get_session),
):
    """Remove a song from the library."""
    result = await db.execute(
        select(LibrarySong).where(
            LibrarySong.id == song_id,
            LibrarySong.user_id == user.id,
        )
    )
    entry = result.scalar_one_or_none()
    if not entry:
        raise HTTPException(status_code=404, detail="Song not in library")

    await db.delete(entry)
    await db.commit()


@router.get("/cache/stats")
async def get_cache_stats(
    user: User = Depends(require_user),
):
    """Get cache statistics."""
    return {
        "cache_size_mb": round(get_cache_size_mb(), 2),
        "metadata_cache_size": len(metadata_cache._cache),
        "stream_cache_size": len(stream_cache._cache),
    }


# ── JIOSAAVN (free music source) ───────────────────────────────────────────

@router.get("/jiosaavn/search")
async def jiosaavn_search(query: str = Query(..., min_length=1), limit: int = Query(20, ge=1, le=50)):
    """Search JioSaavn for songs. No auth required."""
    try:
        results = await search_songs(query, limit=limit)
        return {"results": results}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"JioSaavn search failed: {e}")


@router.get("/jiosaavn/song/{song_id}")
async def jiosaavn_song_details(song_id: str):
    """Get JioSaavn song details including stream URL. No auth required."""
    try:
        song = await get_song_details(song_id)
        if not song:
            raise HTTPException(status_code=404, detail="Song not found")
        return song
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"JioSaavn details failed: {e}")


@router.get("/jiosaavn/stream/{song_id}")
async def jiosaavn_stream(song_id: str):
    """Proxy JioSaavn stream. No auth required."""
    try:
        song = await get_song_details(song_id)
        if not song or not song.get("stream_url"):
            raise HTTPException(status_code=404, detail="Stream URL not found")

        stream_url = song["stream_url"]
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": "https://www.jiosaavn.com/",
            "Accept": "audio/mpeg,audio/*,*/*",
        }

        async def generate():
            timeout = aiohttp.ClientTimeout(total=None, connect=30, sock_read=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(stream_url, headers=headers) as resp:
                    async for chunk in resp.content.iter_chunked(8192):
                        yield chunk

        return StreamingResponse(
            generate(),
            media_type="audio/mpeg",
            headers={"Accept-Ranges": "bytes"},
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"JioSaavn stream failed: {e}")


# ── SOUNDCLOUD (better global catalog) ─────────────────────────────────────

@router.get("/soundcloud/search")
async def soundcloud_search(query: str = Query(..., min_length=1), limit: int = Query(20, ge=1, le=50)):
    """Search SoundCloud for tracks. No auth required."""
    try:
        results = await search_tracks(query, limit=limit)
        return {"results": results}
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SoundCloud search failed: {e}")


@router.get("/soundcloud/track/{track_id}")
async def soundcloud_track(track_id: str):
    """Get SoundCloud track info including stream URL. No auth required."""
    try:
        track = await get_track_info(track_id)
        if not track:
            raise HTTPException(status_code=404, detail="Track not found")
        return track
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SoundCloud track failed: {e}")


@router.get("/soundcloud/stream/{track_id}")
async def soundcloud_stream(track_id: str):
    """Redirect to SoundCloud stream URL. No auth required."""
    try:
        url = await get_soundcloud_stream(track_id)
        if not url:
            raise HTTPException(status_code=404, detail="Stream URL not found")
        return {"stream_url": url}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"SoundCloud stream failed: {e}")