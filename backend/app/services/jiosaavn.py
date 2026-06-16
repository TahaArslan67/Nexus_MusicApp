"""JioSaavn API client for searching and streaming music."""
import asyncio
import json
import httpx
from typing import Any

# JioSaavn API endpoints
JIOSAAVN_BASE = "https://www.jiosaavn.com/api.php"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json",
    "Referer": "https://www.jiosaavn.com/",
}


def _extract_json(text: str) -> dict | None:
    """JioSaavn returns JSON wrapped in parentheses sometimes."""
    text = text.strip()
    # Remove common wrappers
    if text.startswith("(") and text.endswith(")"):
        text = text[1:-1]
    # Remove callback wrappers like `callback({...})`
    if "(" in text and text.endswith(")"):
        start = text.find("(")
        text = text[start + 1:-1]
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


async def search_songs(query: str, limit: int = 20) -> list[dict]:
    """Search JioSaavn for songs."""
    params = {
        "__call": "autocomplete.get",
        "_format": "json",
        "_marker": "0",
        "cc": "in",
        "includeMetaTags": "1",
        "query": query,
    }
    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        resp = await client.get(JIOSAAVN_BASE, params=params)
        resp.raise_for_status()
        data = _extract_json(resp.text)
        if not data:
            return []

    songs = []
    # Results are usually in data['songs']['data']
    songs_data = data.get("songs", {}).get("data", []) if isinstance(data, dict) else []
    for item in songs_data[:limit]:
        song = {
            "id": item.get("id", ""),
            "title": item.get("title", "").replace("&quot;", '"').replace("&amp;", "&"),
            "artist": _extract_artists(item),
            "album": item.get("album", "").replace("&quot;", '"').replace("&amp;", "&"),
            "thumbnail": _get_thumbnail(item),
            "duration": _parse_duration(item.get("duration", "")),
        }
        if song["id"]:
            songs.append(song)
    return songs


async def get_song_details(song_id: str) -> dict | None:
    """Get song details including encrypted stream URL."""
    params = {
        "__call": "song.getDetails",
        "cc": "in",
        "_marker": "0",
        "_format": "json",
        "pids": song_id,
    }
    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        resp = await client.get(JIOSAAVN_BASE, params=params)
        resp.raise_for_status()
        data = _extract_json(resp.text)
        if not data or not isinstance(data, dict):
            return None

    songs = data.get("songs", [])
    if not songs:
        # Sometimes wrapped differently
        for key, val in data.items():
            if isinstance(val, list) and len(val) > 0:
                songs = val
                break
            elif isinstance(val, dict):
                return _normalize_song(val)
        if not songs:
            return None

    song = songs[0] if isinstance(songs, list) else songs
    return _normalize_song(song)


def _normalize_song(item: dict) -> dict | None:
    """Normalize JioSaavn song dict to our format."""
    if not item:
        return None

    # Get stream URL - JioSaavn provides encrypted URLs
    media_url = item.get("media_url", "") or item.get("encrypted_media_url", "")
    # Decrypt if needed - JioSaavn uses a simple DES3 encryption
    if media_url and "http" not in media_url:
        media_url = _decrypt_url(media_url)

    # Quality URLs
    more_info = item.get("more_info", {}) or item
    vlink = more_info.get("vlink", "") if isinstance(more_info, dict) else ""
    if not media_url and vlink:
        media_url = vlink

    # Fallback: build from song ID
    if not media_url:
        song_id = item.get("id", "")
        if song_id:
            media_url = f"https://www.jiosaavn.com/song/{song_id}"

    return {
        "id": item.get("id", ""),
        "title": item.get("title", "").replace("&quot;", '"').replace("&amp;", "&"),
        "artist": _extract_artists(item),
        "album": item.get("album", "").replace("&quot;", '"').replace("&amp;", "&"),
        "thumbnail": _get_thumbnail(item),
        "duration": _parse_duration(item.get("duration", "")),
        "stream_url": media_url,
        "encrypted_url": item.get("encrypted_media_url", ""),
    }


def _extract_artists(item: dict) -> str:
    """Extract primary artists from JioSaavn item."""
    more_info = item.get("more_info", {}) if isinstance(item.get("more_info"), dict) else {}
    artist_map = more_info.get("artistMap", {}) if isinstance(more_info, dict) else {}
    artists = artist_map.get("artists", []) if isinstance(artist_map, dict) else []
    if artists:
        return ", ".join(a.get("name", "") for a in artists[:3] if a.get("name"))
    # Fallback
    primary = item.get("primary_artists", "")
    if primary:
        return primary.replace("&quot;", '"').replace("&amp;", "&")
    return item.get("singers", "") or "Unknown Artist"


def _get_thumbnail(item: dict) -> str:
    """Get highest quality thumbnail URL."""
    image = item.get("image", "")
    if not image and isinstance(item.get("more_info"), dict):
        image = item["more_info"].get("image", "")
    if image:
        # JioSaavn images have quality suffixes: 50x50, 150x150, 500x500
        return image.replace("-50x50.", "-500x500.").replace("-150x150.", "-500x500.")
    return ""


def _parse_duration(d: Any) -> int:
    """Parse duration string to seconds."""
    if isinstance(d, int):
        return d
    if isinstance(d, str):
        try:
            return int(d)
        except ValueError:
            pass
    return 0


# JioSaavn DES3 decryption key (publicly known)
JIO_DECRYPT_KEY = b"38346591"


def _decrypt_url(encrypted_url: str) -> str:
    """Decrypt JioSaavn encrypted media URL using DES3."""
    try:
        from Crypto.Cipher import DES
        import base64

        encrypted = base64.b64decode(encrypted_url)
        cipher = DES.new(JIO_DECRYPT_KEY, DES.MODE_ECB)
        decrypted = cipher.decrypt(encrypted)
        # Remove PKCS5 padding
        pad_len = decrypted[-1]
        decrypted = decrypted[:-pad_len]
        url = decrypted.decode("utf-8")
        # Replace http with https
        if url.startswith("http://"):
            url = "https://" + url[7:]
        return url
    except Exception:
        return ""
