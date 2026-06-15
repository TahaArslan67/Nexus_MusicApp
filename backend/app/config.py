"""Nexus Backend Configuration

Loads from .env file if present, falls back to defaults.
API anahtarlarını ve proxy listelerini asla ana dizinde bırakma.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env file (varsa)
env_path = Path(__file__).resolve().parent.parent / ".env"
if env_path.exists():
    load_dotenv(env_path)
else:
    # Try project root
    root_env = Path(__file__).resolve().parent.parent.parent / ".env"
    if root_env.exists():
        load_dotenv(root_env)

# Base directory
BASE_DIR = Path(__file__).resolve().parent.parent

# Security
SECRET_KEY = os.getenv("NEXUS_SECRET_KEY", "change-me-in-production-32chars!")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

# Database
DATABASE_URL = os.getenv(
    "NEXUS_DATABASE_URL",
    f"sqlite+aiosqlite:///{BASE_DIR}/nexus.db"
)

# YouTube / yt-dlp
YT_DLP_CACHE_DIR = os.getenv(
    "NEXUS_CACHE_DIR",
    str(BASE_DIR / "cache" / "ytdlp")
)
STREAM_CHUNK_SIZE = 256 * 1024  # 256 KB per chunk

# Audio
AUDIO_FORMAT = "bestaudio[abr<=128]/bestaudio/best"
PREFERRED_CODECS = ["opus", "m4a", "webm"]

# Rate limiting
QUOTA_SEARCH_COST = 100
QUOTA_DETAIL_COST = 1
DAILY_QUOTA_LIMIT = 10_000

# Caching
REDIS_URL = os.getenv("NEXUS_REDIS_URL", "redis://localhost:6379/0")
CACHE_TTL_SECONDS = 60 * 60 * 24  # 24 hours