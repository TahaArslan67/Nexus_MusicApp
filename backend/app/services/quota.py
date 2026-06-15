"""Quota Management Service

Tracks and enforces daily API quota limits.
Standard free tier: 10,000 quota units/day.
- Search: 100 units
- Video detail (ID-based): 1 unit
"""

from datetime import datetime, date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import DAILY_QUOTA_LIMIT
from app.models.database import User


async def get_quota_usage(db: AsyncSession, user: User) -> dict:
    """Get current quota usage for a user."""
    today = date.today()

    # Reset quota if it's a new day
    if user.last_quota_reset.date() < today:
        user.daily_quota_used = 0
        user.last_quota_reset = datetime.utcnow()
        await db.commit()

    return {
        "daily_limit": DAILY_QUOTA_LIMIT,
        "used": user.daily_quota_used,
        "remaining": max(0, DAILY_QUOTA_LIMIT - user.daily_quota_used),
        "reset_at": user.last_quota_reset.isoformat(),
    }


async def consume_quota(db: AsyncSession, user: User, cost: int) -> bool:
    """Consume quota units. Returns False if quota is exhausted."""
    today = date.today()

    # Reset if new day
    if user.last_quota_reset.date() < today:
        user.daily_quota_used = 0
        user.last_quota_reset = datetime.utcnow()

    if user.daily_quota_used + cost > DAILY_QUOTA_LIMIT:
        return False

    user.daily_quota_used += cost
    await db.commit()
    return True


def get_search_quota_cost() -> int:
    """Search API cost in quota units."""
    return 100


def get_detail_quota_cost() -> int:
    """Video detail (ID-based) API cost in quota units."""
    return 1