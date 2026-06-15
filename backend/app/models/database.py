"""Nexus Database Models"""

from datetime import datetime
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, ForeignKey, BigInteger, Text
)
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base, relationship

from app.config import DATABASE_URL

engine = create_async_engine(DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

Base = declarative_base()


# ── User ────────────────────────────────────────────────────────────────────
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String(64), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    daily_quota_used = Column(Integer, default=0)
    last_quota_reset = Column(DateTime, default=datetime.utcnow)

    library_songs = relationship("LibrarySong", back_populates="user", cascade="all, delete-orphan")


# ── Song Metadata (cached from YouTube) ─────────────────────────────────────
class Song(Base):
    __tablename__ = "songs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    youtube_id = Column(String(32), unique=True, nullable=False, index=True)
    title = Column(String(255), nullable=False)
    artist = Column(String(255), default="Unknown Artist")
    duration_seconds = Column(Integer, default=0)
    thumbnail_url = Column(Text, default="")
    audio_url = Column(Text, default="")
    cached_file_path = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


# ── User Library (downloaded / saved songs) ────────────────────────────────
class LibrarySong(Base):
    __tablename__ = "library_songs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    song_id = Column(Integer, ForeignKey("songs.id", ondelete="CASCADE"), nullable=False)
    is_downloaded = Column(Boolean, default=False)          # fully cached locally
    file_path = Column(Text, nullable=True)                 # local file path
    added_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="library_songs")
    song = relationship("Song")


# ── Helpers ─────────────────────────────────────────────────────────────────
async def init_db():
    """Create all tables."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def get_session() -> AsyncSession:
    async with async_session() as session:
        yield session