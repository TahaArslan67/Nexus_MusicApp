"""YouTube Streaming Service — powered by yt-dlp + FFmpeg

Hata Toleransı ve Dayanıklılık Stratejileri:

1. **User-Agent Randomization:** Her istekte farklı tarayıcı imzası (bot tespitini önle)
2. **Proxy Rotasyonu:** YouTube throttling'ine karşı IP tabanlı kısıtlama
3. **Invidious Fallback:** yt-dlp hata verirse, açık kaynak Invidious API'sine düş
4. **AAC (audio/m4a) Öncelikli:** Mobil cihazlarda donanım hızlandırması

Youtube API stratejisi:
- ID-based lookups (costs 1 quota unit) instead of Search (100 units)
- Adaptive bitrate for low-bandwidth scenarios
"""

import asyncio
import os
import random
import subprocess
from pathlib import Path
from typing import Optional

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import YT_DLP_CACHE_DIR, AUDIO_FORMAT
from app.models.database import Song
from app.services.logging import nexus_logger as log


# ── User-Agent Havuzu (Browser Fingerprint Rotation) ─────────────────────────

USER_AGENTS = [
    # Chrome 120+ (Windows)
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    # Chrome 120+ (macOS)
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    # Firefox 121 (Windows)
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
    # Firefox 121 (macOS)
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
    # Safari 17 (macOS)
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
    # Edge 120 (Windows)
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
]

# Proxy havuzu (opsiyonel — ortam değişkeni ile aktifleştir)
PROXY_LIST = os.getenv("NEXUS_PROXY_LIST", "").split(",") if os.getenv("NEXUS_PROXY_LIST") else []

# Invidious instance'ları (YouTube'a alternatif API)
INVIDIOUS_INSTANCES = [
    "https://inv.nadeko.net",
    "https://yewtu.be",
    "https://invidious.snopyta.org",
    "https://vid.puffyan.us",
    "https://invidious.private.coffee",
]


def _get_random_user_agent() -> str:
    """Her istekte farklı bir User-Agent döndür."""
    return random.choice(USER_AGENTS)


def _get_random_proxy() -> Optional[str]:
    """Proxy listesi varsa, rastgele bir proxy seç."""
    if not PROXY_LIST:
        return None
    return random.choice(PROXY_LIST)


def _build_ytdlp_base_args() -> list[str]:
    """yt-dlp base args with User-Agent randomization + optional proxy."""
    args = [
        "yt-dlp",
        "--no-playlist",
        "--quiet",
        "--no-warnings",
        "--user-agent", _get_random_user_agent(),
        "--extractor-args", "youtube:player_client=web",
        "--no-check-certificates",
        "--add-header", "Accept-Language:en-US,en;q=0.9",
        "--add-header", "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ]

    # Proxy rotasyonu
    proxy = _get_random_proxy()
    if proxy:
        args.extend(["--proxy", proxy])

    return args


# ── Helpers ──────────────────────────────────────────────────────────────────

def _ensure_cache_dir():
    Path(YT_DLP_CACHE_DIR).mkdir(parents=True, exist_ok=True)


# ── Invidious Fallback (yt-dlp başarısız olursa) ────────────────────────────

async def _try_invidious_metadata(youtube_id: str) -> dict | None:
    """Invidious API'den video metadata çek (yt-dlp fallback).

    Invidious, YouTube'un açık kaynaklı alternatif frontend'idir.
    yt-dlp throttling yediğinde veya bölgesel kısıtlama olduğunda çalışır.
    """
    for instance in INVIDIOUS_INSTANCES:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"{instance}/api/v1/videos/{youtube_id}"
                response = await client.get(url, headers={
                    "User-Agent": _get_random_user_agent(),
                })
                if response.status_code != 200:
                    continue

                data = response.json()
                return {
                    "id": youtube_id,
                    "title": data.get("title", "Unknown"),
                    "artist": data.get("author", "Unknown Artist"),
                    "duration": data.get("lengthSeconds", 0),
                    "thumbnail": data.get("videoThumbnails", [{}])[-1].get("url", "")
                    if data.get("videoThumbnails") else "",
                }
        except (httpx.TimeoutException, httpx.RequestError, KeyError):
            continue

    return None


async def _try_invidious_stream(youtube_id: str) -> dict | None:
    """Invidious'tan stream URL çek (yt-dlp fallback).

    Invidious, audio stream URL'lerini doğrudan sağlar.
    Genelde AAC formatında ve düşük gecikmeli.
    """
    for instance in INVIDIOUS_INSTANCES:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                url = f"{instance}/api/v1/videos/{youtube_id}"
                response = await client.get(url, headers={
                    "User-Agent": _get_random_user_agent(),
                })
                if response.status_code != 200:
                    continue

                data = response.json()
                # Audio streams'leri bul (AAC öncelikli)
                audio_streams = data.get("adaptiveFormats", [])
                audio_only = [
                    s for s in audio_streams
                    if s.get("type", "").startswith("audio/")
                ]

                if not audio_only:
                    continue

                # AAC öncelikli sırala
                audio_only.sort(
                    key=lambda s: (
                        0 if "audio/mp4" in s.get("type", "") else
                        1 if "audio/webm" in s.get("type", "") else
                        2
                    )
                )

                best = audio_only[0]
                return {
                    "url": best.get("url"),
                    "ext": "m4a" if "mp4" in best.get("type", "") else "webm",
                    "content_type": best.get("type", "audio/mp4"),
                    "filesize": best.get("clen", 0),
                }
        except (httpx.TimeoutException, httpx.RequestError, KeyError):
            continue

    return None


# ── Metadata Extraction ──────────────────────────────────────────────────────

async def fetch_metadata(youtube_id: str) -> dict | None:
    """Fetch video metadata using yt-dlp + Invidious fallback."""
    _ensure_cache_dir()
    url = f"https://www.youtube.com/watch?v={youtube_id}"

    # Step 1: yt-dlp (sync subprocess, Windows-compatible)
    for attempt in range(3):
        cmd = _build_ytdlp_base_args() + [
            "--write-info-json",
            "--skip-download",
            "--print", "%(id)s|%(title)s|%(channel)s|%(duration)s|%(thumbnail)s",
            url,
        ]

        try:
            proc = await asyncio.to_thread(
                subprocess.run,
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )

            if proc.returncode == 0:
                parts = proc.stdout.strip().split("|")
                if len(parts) >= 5:
                    return {
                        "id": parts[0],
                        "title": parts[1],
                        "artist": parts[2] or "Unknown Artist",
                        "duration": int(parts[3]) if parts[3].isdigit() else 0,
                        "thumbnail": parts[4],
                    }

            stderr_text = proc.stderr.lower() if proc.stderr else ""
            print(f"[yt-dlp meta] Exit {proc.returncode}, stderr: {proc.stderr[:300]}")
            if "429" in stderr_text or "too many requests" in stderr_text:
                await asyncio.sleep(2 ** attempt)
                continue

        except subprocess.TimeoutExpired:
            print(f"[yt-dlp meta] Timeout on attempt {attempt+1}")
            await asyncio.sleep(1)
            continue
        except FileNotFoundError:
            raise RuntimeError("yt-dlp is not installed. Run: pip install yt-dlp")

    # Step 2: Invidious fallback
    invidious_result = await _try_invidious_metadata(youtube_id)
    if invidious_result:
        return invidious_result

    return None


# ── Stream URL Resolution (AAC Preferred for Mobile) ─────────────────────────

async def get_stream_url(youtube_id: str) -> dict | None:
    """Resolve best audio-only stream URL."""
    url = f"https://www.youtube.com/watch?v={youtube_id}"

    # Step 1: yt-dlp ile stream URL (sync subprocess, Windows-compatible)
    for attempt in range(3):
        cmd = _build_ytdlp_base_args() + [
            "-f", "bestaudio[ext=m4a]/bestaudio[abr<=128]/bestaudio/best",
            "--print", "%(url)s|%(ext)s|%(filesize_approx)s",
            url,
        ]

        try:
            proc = await asyncio.to_thread(
                subprocess.run,
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )

            if proc.returncode == 0:
                parts = proc.stdout.strip().split("|")
                if parts and parts[0]:
                    ext = parts[1] if len(parts) > 1 else "m4a"
                    content_type_map = {
                        "m4a": "audio/mp4",
                        "mp4": "audio/mp4",
                        "aac": "audio/aac",
                        "opus": "audio/webm",
                        "webm": "audio/webm",
                        "mp3": "audio/mpeg",
                    }
                    return {
                        "url": parts[0],
                        "ext": ext,
                        "content_type": content_type_map.get(ext, "audio/mp4"),
                        "filesize": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0,
                    }

            # Throttle kontrolü
            stderr_text = proc.stderr.lower() if proc.stderr else ""
            if "429" in stderr_text or "too many requests" in stderr_text:
                print(f"[yt-dlp] Throttled, retrying ({attempt+1}/3)")
                await asyncio.sleep(2 ** attempt)
                continue

            # Diğer hataları logla
            print(f"[yt-dlp] Exit {proc.returncode}, stderr: {proc.stderr[:500]}")

        except subprocess.TimeoutExpired:
            print(f"[yt-dlp] Timeout on attempt {attempt+1}")
            await asyncio.sleep(1)
            continue
        except Exception as e:
            print(f"[yt-dlp] Exception: {e}")
            continue

    print("[yt-dlp] All attempts failed, trying Invidious fallback")
    # Step 2: Invidious fallback
    invidious_result = await _try_invidious_stream(youtube_id)
    if invidious_result:
        return invidious_result

    return None


# ── Download with FFmpeg Transcoding to AAC ──────────────────────────────────

async def download_audio(youtube_id: str, output_dir: str | None = None) -> str | None:
    """Download audio and transcode to AAC via FFmpeg.

    Neden FFmpeg ile AAC?
    - Mobil cihazlar AAC codec'ini donanım seviyesinde decode eder (çok daha az pil)
    - audio/mp4 formatı tüm mobil platformlarda sorunsuz çalışır

    FFmpeg yoksa, direkt yt-dlp çıktısını kullanır (fallback).
    """
    dest = output_dir or YT_DLP_CACHE_DIR
    _ensure_cache_dir()

    url = f"https://www.youtube.com/watch?v={youtube_id}"

    # Check FFmpeg availability
    has_ffmpeg = False
    try:
        proc = await asyncio.to_thread(
            subprocess.run,
            ["ffmpeg", "-version"],
            capture_output=True, timeout=5,
        )
        has_ffmpeg = proc.returncode == 0
    except FileNotFoundError:
        has_ffmpeg = False

    if has_ffmpeg:
        # FFmpeg ile AAC transcoding
        cmd = _build_ytdlp_base_args() + [
            "-f", "bestaudio[abr<=128]/bestaudio/best",
            "--extract-audio",
            "--audio-format", "aac",
            "--audio-quality", "0",
            "--postprocessor-args", "ffmpeg:-vn -ac 2 -ar 44100",
            "-o", os.path.join(dest, f"{youtube_id}.%(ext)s"),
            url,
        ]
    else:
        # Fallback: yt-dlp native output
        cmd = _build_ytdlp_base_args() + [
            "-f", "bestaudio[ext=m4a]/bestaudio[abr<=128]/bestaudio/best",
            "-o", os.path.join(dest, f"{youtube_id}.%(ext)s"),
            url,
        ]

    try:
        proc = await asyncio.to_thread(
            subprocess.run,
            cmd,
            capture_output=True,
            timeout=120,
        )

        if proc.returncode != 0:
            return None

        for ext in ["m4a", "aac", "opus", "webm", "mp3"]:
            fp = Path(f"{dest}/{youtube_id}.{ext}")
            if fp.exists():
                return str(fp)
        return None
    except subprocess.TimeoutExpired:
        return None


# ── Database Helpers ──────────────────────────────────────────────────────────

async def get_or_create_song(db: AsyncSession, youtube_id: str) -> Song | None:
    """Get song from DB or fetch from YouTube (costs 1 quota unit)."""
    result = await db.execute(select(Song).where(Song.youtube_id == youtube_id))
    song = result.scalar_one_or_none()

    if song:
        return song

    # Fetch from YouTube (yt-dlp + Invidious fallback)
    meta = await fetch_metadata(youtube_id)
    if not meta:
        return None

    song = Song(
        youtube_id=meta["id"],
        title=meta["title"],
        artist=meta["artist"],
        duration_seconds=meta["duration"],
        thumbnail_url=meta["thumbnail"],
    )
    db.add(song)
    await db.commit()
    await db.refresh(song)
    return song