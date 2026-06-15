"""Music Schemas"""

from pydantic import BaseModel, Field
from typing import Optional


class SongResponse(BaseModel):
    id: int
    youtube_id: str
    title: str
    artist: str
    duration_seconds: int
    thumbnail_url: str
    audio_url: str
    is_cached: bool = False

    class Config:
        from_attributes = True


class SongDetailRequest(BaseModel):
    """ID-based request — costs only 1 quota unit."""
    youtube_id: str = Field(..., description="YouTube video ID")


class StreamInfo(BaseModel):
    """Stream URL + metadata for the client."""
    youtube_id: str
    title: str
    artist: str
    duration_seconds: int
    stream_url: str
    content_type: str


class LibraryResponse(BaseModel):
    id: int
    song: SongResponse
    is_downloaded: bool
    added_at: str

    class Config:
        from_attributes = True


class QuotaResponse(BaseModel):
    daily_limit: int
    used: int
    remaining: int