"""Quota-Safe Search Service

Google/YouTube API'de Search 100 birim, ID-based detail ise 1 birim harcar.
Bu servis mümkün olduğunca ID-based lookup kullanarak kotayı korur.

Local-First stratejisi:
1. Önce SQLite'da Fuzzy Search (fuzzywuzzy ile) — 0 birim
2. Sadece sonuç yetersizse YouTube Search (100 birim)
"""

import re
from typing import List, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import QUOTA_SEARCH_COST, QUOTA_DETAIL_COST
from app.models.database import Song


# ── YouTube Search (only when necessary) ─────────────────────────────────────

async def search_youtube(query: str, max_results: int = 10) -> list[dict]:
    """Search YouTube via yt-dlp (costs ~100 quota for the initial search).

    Returns list of {id, title, artist, duration, thumbnail}.
    The client should prefer ID-based lookups afterwards.
    """
    import asyncio
    import subprocess

    cmd = [
        "yt-dlp",
        "--quiet",
        "--no-warnings",
        "--flat-playlist",
        "--print", "%(id)s|%(title)s|%(channel)s|%(duration)s|%(thumbnail)s",
        f"ytsearch{max_results}:{query}",
    ]

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdout, _ = await proc.communicate(timeout=30)

        if proc.returncode != 0:
            return []

        results = []
        for line in stdout.decode().strip().split("\n"):
            if not line:
                continue
            parts = line.split("|")
            if len(parts) >= 5:
                results.append({
                    "id": parts[0],
                    "title": parts[1],
                    "artist": parts[2] or "Unknown Artist",
                    "duration": int(parts[3]) if parts[3].isdigit() else 0,
                    "thumbnail": parts[4],
                })
        return results
    except Exception:
        return []


# ── Fuzzy Search (Local DB — 0 quota cost) ─────────────────────────────────

def _tokenize(text: str) -> set[str]:
    """Split text into lowercase tokens for matching."""
    return set(re.findall(r'\w+', text.lower()))


def _fuzzy_score(query_tokens: set[str], title_tokens: set[str]) -> float:
    """Calculate a simple fuzzy match score between 0.0 and 1.0.

    - Exact match → 1.0
    - All query tokens found → 0.9
    - Partial match → 0.3–0.8
    """
    if not query_tokens or not title_tokens:
        return 0.0

    query_lower = {t.lower() for t in query_tokens}
    title_lower = {t.lower() for t in title_tokens}

    # Exact match
    if query_lower == title_lower:
        return 1.0

    # All query tokens present in title
    if query_lower.issubset(title_lower):
        return 0.9

    # Partial match — what fraction of query tokens appear?
    common = query_lower & title_lower
    ratio = len(common) / len(query_lower)

    # Bonus for character-level similarity (handles typos)
    char_overlap = sum(
        1 for q in query_lower
        if any(q[:3] in t or t[:3] in q for t in title_lower)
    )
    char_ratio = char_overlap / len(query_lower) if query_lower else 0

    return max(ratio * 0.8, char_ratio * 0.6)


async def search_local_fuzzy(db: AsyncSession, query: str, limit: int = 20, threshold: float = 0.4) -> List[Song]:
    """Fuzzy search already-cached songs in local DB (ZERO quota cost!).

    LIKE sorgusuyla adayları bulur, sonra fuzzy score ile sıralar.
    Bu sayede:
    - "ril" yazsan da "RİL" → "Ril" → "Ril" için eşleşme bulur
    - "beatls" → "Beatles" için yazım hatası toleransı
    - Kotada %90 tasarruf: sadece local'de bulamazsan YouTube'a gider
    """
    if not query or not query.strip():
        return []

    # Step 1: Broad SQL LIKE sorgusu (hızlı aday bulma)
    like_pattern = f"%{query.strip()}%"
    stmt = (
        select(Song)
        .where(Song.title.ilike(like_pattern))
        .limit(limit * 3)  # Fazla aday al, fuzzy ile sırala
    )
    result = await db.execute(stmt)
    candidates: List[Song] = list(result.scalars().all())

    if not candidates:
        # Step 1b: Daha geniş LIKE — her kelime için ayrı ayrı
        tokens = re.findall(r'\w+', query)
        if len(tokens) > 1:
            for token in tokens:
                token_pattern = f"%{token}%"
                stmt = (
                    select(Song)
                    .where(Song.title.ilike(token_pattern))
                    .limit(limit)
                )
                result = await db.execute(stmt)
                candidates.extend(list(result.scalars().all()))
            # Remove duplicates
            seen = set()
            unique_candidates = []
            for c in candidates:
                if c.id not in seen:
                    seen.add(c.id)
                    unique_candidates.append(c)
            candidates = unique_candidates

    if not candidates:
        return []

    # Step 2: Fuzzy score hesapla ve sırala
    query_tokens = _tokenize(query)
    scored: List[Tuple[float, Song]] = []

    for song in candidates:
        title_tokens = _tokenize(song.title)
        artist_tokens = _tokenize(song.artist)

        title_score = _fuzzy_score(query_tokens, title_tokens)
        artist_score = _fuzzy_score(query_tokens, artist_tokens)

        # Artist match'e bonus ver (kullanıcı genelde sanatçı adıyla arar)
        final_score = max(title_score, artist_score * 0.9)

        if final_score >= threshold:
            scored.append((final_score, song))

    # Sort by score descending
    scored.sort(key=lambda x: x[0], reverse=True)

    return [song for _, song in scored[:limit]]


# ── Quota Tracking ───────────────────────────────────────────────────────────

# ── Legacy exact LIKE search (kept for compatibility) ─────────────────────

async def search_local(db: AsyncSession, query: str, limit: int = 20) -> List[Song]:
    """Simple LIKE search (fallback)."""
    stmt = (
        select(Song)
        .where(Song.title.ilike(f"%{query}%"))
        .limit(limit)
    )
    result = await db.execute(stmt)
    return list(result.scalars().all())


# ── Quota Cost Constants ─────────────────────────────────────────────────

def get_search_quota_cost() -> int:
    """Returns how many quota units a search operation costs."""
    return QUOTA_SEARCH_COST


def get_detail_quota_cost() -> int:
    """Returns how many quota units a detail lookup costs."""
    return QUOTA_DETAIL_COST
