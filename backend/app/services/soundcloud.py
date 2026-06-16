"""SoundCloud API client for searching and streaming music."""
import httpx
from typing import Any

# SoundCloud API v2
SOUNDCLOUD_API = "https://api-v2.soundcloud.com"

# Public client_id (rotates, may need updating)
CLIENT_ID = "iZIs9mchVcX5lhKNRjwHQsiL7gQiXy5Y"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json",
    "Referer": "https://soundcloud.com/",
}


def _extract_client_id(text: str) -> str | None:
    """Extract client_id from SoundCloud page if current one fails."""
    import re
    match = re.search(r'client_id=([a-zA-Z0-9]+)', text)
    if match:
        return match.group(1)
    return None


async def _get_working_client_id() -> str:
    """Get a working client_id from SoundCloud."""
    global CLIENT_ID
    async with httpx.AsyncClient(timeout=10.0, headers=HEADERS) as client:
        # Try current client_id first
        test = await client.get(
            f"{SOUNDCLOUD_API}/search/tracks",
            params={"q": "test", "client_id": CLIENT_ID, "limit": 1}
        )
        if test.status_code == 200:
            return CLIENT_ID

        # Try extracting from main page
        page = await client.get("https://soundcloud.com/")
        if page.status_code == 200:
            new_id = _extract_client_id(page.text)
            if new_id:
                CLIENT_ID = new_id
                return new_id

    return CLIENT_ID


async def search_tracks(query: str, limit: int = 20) -> list[dict]:
    """Search SoundCloud for tracks."""
    client_id = await _get_working_client_id()

    params = {
        "q": query,
        "client_id": client_id,
        "limit": limit,
        "offset": 0,
    }

    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        resp = await client.get(f"{SOUNDCLOUD_API}/search/tracks", params=params)
        resp.raise_for_status()
        data = resp.json()

    tracks = data.get("collection", [])
    results = []
    for track in tracks[:limit]:
        results.append({
            "id": str(track.get("id", "")),
            "title": track.get("title", "Unknown"),
            "artist": track.get("user", {}).get("username", "Unknown Artist") if track.get("user") else "Unknown Artist",
            "album": "",
            "thumbnail": _get_artwork(track),
            "duration": track.get("duration", 0) // 1000,  # ms to seconds
            "streamable": track.get("streamable", False),
            "permalink": track.get("permalink_url", ""),
        })
    return results


def _get_artwork(track: dict) -> str:
    """Get highest quality artwork URL."""
    artwork = track.get("artwork_url", "")
    if artwork:
        # Replace size for larger image
        return artwork.replace("-large.jpg", "-t500x500.jpg")
    # Fallback to user's avatar
    user = track.get("user", {})
    if user:
        avatar = user.get("avatar_url", "")
        if avatar:
            return avatar.replace("-large.jpg", "-t500x500.jpg")
    return ""


async def get_stream_url(track_id: str) -> str | None:
    """Get HLS stream URL for a track."""
    client_id = await _get_working_client_id()

    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        # Get track info first
        resp = await client.get(
            f"{SOUNDCLOUD_API}/tracks/{track_id}",
            params={"client_id": client_id}
        )
        if resp.status_code != 200:
            return None

        track = resp.json()
        media = track.get("media", {})
        transcodings = media.get("transcodings", [])

        # Find progressive MP3 stream
        for trans in transcodings:
            fmt = trans.get("format", {})
            if fmt.get("protocol") == "progressive" and "mp3" in fmt.get("mime_type", ""):
                url_resp = await client.get(
                    trans["url"],
                    params={"client_id": client_id}
                )
                if url_resp.status_code == 200:
                    url_data = url_resp.json()
                    return url_data.get("url")

        # Fallback to HLS
        for trans in transcodings:
            fmt = trans.get("format", {})
            if fmt.get("protocol") == "hls":
                url_resp = await client.get(
                    trans["url"],
                    params={"client_id": client_id}
                )
                if url_resp.status_code == 200:
                    url_data = url_resp.json()
                    return url_data.get("url")

    return None


async def get_track_info(track_id: str) -> dict | None:
    """Get detailed track info."""
    client_id = await _get_working_client_id()

    async with httpx.AsyncClient(timeout=30.0, headers=HEADERS) as client:
        resp = await client.get(
            f"{SOUNDCLOUD_API}/tracks/{track_id}",
            params={"client_id": client_id}
        )
        if resp.status_code != 200:
            return None

        track = resp.json()
        return {
            "id": str(track.get("id", "")),
            "title": track.get("title", "Unknown"),
            "artist": track.get("user", {}).get("username", "Unknown Artist") if track.get("user") else "Unknown Artist",
            "thumbnail": _get_artwork(track),
            "duration": track.get("duration", 0) // 1000,
            "stream_url": await get_stream_url(track_id),
            "permalink": track.get("permalink_url", ""),
        }
