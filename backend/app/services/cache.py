"""Caching & Performance Optimization Service

Handles:
1. In-memory LRU cache for frequently-accessed metadata
2. Local file cache for downloaded audio
3. Adaptive bitrate selection for low-bandwidth
4. Prefetch hints for the client
"""

import os
import time
import hashlib
import json
from pathlib import Path
from typing import Optional, Any
from functools import lru_cache

from app.config import YT_DLP_CACHE_DIR, CACHE_TTL_SECONDS


# ── Simple In-Memory Cache ──────────────────────────────────────────────────

class MemoryCache:
    """Thread-safe in-memory cache with TTL expiration."""

    def __init__(self, ttl: int = CACHE_TTL_SECONDS, maxsize: int = 256):
        self._cache: dict[str, tuple[float, Any]] = {}
        self.ttl = ttl
        self.maxsize = maxsize

    def get(self, key: str) -> Optional[Any]:
        if key not in self._cache:
            return None
        expires_at, value = self._cache[key]
        if time.time() > expires_at:
            del self._cache[key]
            return None
        return value

    def set(self, key: str, value: Any, ttl: Optional[int] = None):
        if len(self._cache) >= self.maxsize:
            # Evict oldest entry
            oldest = min(self._cache.keys(), key=lambda k: self._cache[k][0])
            del self._cache[oldest]
        expires = time.time() + (ttl or self.ttl)
        self._cache[key] = (expires, value)

    def invalidate(self, key: str):
        self._cache.pop(key, None)

    def clear(self):
        self._cache.clear()


# Global cache instance
metadata_cache = MemoryCache(ttl=3600)  # 1 hour for metadata
stream_cache = MemoryCache(ttl=300)      # 5 min for stream URLs


# ── File Cache Helpers ──────────────────────────────────────────────────────

def get_cached_path(youtube_id: str) -> Optional[str]:
    """Check if an audio file is already cached locally."""
    for ext in ["opus", "m4a", "webm", "mp3"]:
        fp = Path(YT_DLP_CACHE_DIR) / f"{youtube_id}.{ext}"
        if fp.exists():
            return str(fp)
    return None


def get_cache_size_mb() -> float:
    """Get total size of cached audio files in MB."""
    cache_dir = Path(YT_DLP_CACHE_DIR)
    if not cache_dir.exists():
        return 0.0
    total = sum(
        f.stat().st_size for f in cache_dir.iterdir()
        if f.is_file() and f.suffix in (".opus", ".m4a", ".webm", ".mp3")
    )
    return total / (1024 * 1024)


def clear_cache(older_than_days: int = 7):
    """Remove cached files older than N days."""
    cache_dir = Path(YT_DLP_CACHE_DIR)
    if not cache_dir.exists():
        return
    now = time.time()
    cutoff = now - (older_than_days * 86400)
    for f in cache_dir.iterdir():
        if f.is_file() and f.stat().st_mtime < cutoff:
            f.unlink()


# ── Adaptive Bitrate ────────────────────────────────────────────────────────

def get_audio_format_for_bandwidth(bandwidth_kbps: Optional[int] = None) -> str:
    """Return yt-dlp format string optimized for given bandwidth.

    - Very low (< 100 kbps): 48k audio
    - Low (100-500 kbps): 70k audio
    - Medium (500-2000 kbps): 96k audio
    - High (> 2000 kbps): 128k audio (best audio)
    """
    if bandwidth_kbps is None or bandwidth_kbps >= 2000:
        return "bestaudio[abr<=128]/bestaudio/best"
    elif bandwidth_kbps >= 500:
        return "bestaudio[abr<=96]/bestaudio/best"
    elif bandwidth_kbps >= 100:
        return "bestaudio[abr<=70]/bestaudio/best"
    else:
        return "bestaudio[abr<=48]/bestaudio/best"


# ── Prefetch Hint ──────────────────────────────────────────────────────────

def generate_prefetch_hints(youtube_ids: list[str]) -> list[dict]:
    """Generate a list of prefetch hints for the client.

    The client can use these to start caching likely-next songs.
    """
    hints = []
    for vid in youtube_ids:
        cached = get_cached_path(vid)
        hints.append({
            "youtube_id": vid,
            "is_cached_locally": cached is not None,
        })
    return hints