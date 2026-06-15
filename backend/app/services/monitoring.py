"""Nexus Monitoring & Observability Service

Log dosyalarını analiz eder ve dashboard için istatistik sağlar.
yt-dlp hatası, Invidious fallback'leri, proxy stabilitesi gibi
metrikleri gerçek zamanlı takip eder.

Kullanım:
    GET /monitoring/stats     -> JSON istatistikler
    GET /monitoring/dashboard -> HTML görsel dashboard
"""

import os
import re
import json
import glob
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

from app.config import BASE_DIR


# ── Log Analizi ──────────────────────────────────────────────────────────────

LOG_FILE = os.getenv("NEXUS_LOG_FILE", str(BASE_DIR / "logs" / "nexus.log"))


def parse_logs(hours: int = 24) -> dict:
    """Log dosyasını parse ederek istatistik üretir.

    Returns:
        {
            "total_lines": 1520,
            "by_level": {"INFO": 1200, "WARNING": 200, "ERROR": 100, "DEBUG": 20},
            "sources": {"yt-dlp": 45, "invidious": 12, "proxy": 5},
            "recent_errors": [...],
            "top_songs_with_errors": [{"song": "xxx", "errors": 3}, ...],
            "proxy_stats": {"active": 3, "blocked": 1, "total_requests": 80},
            "timeseries": {"14:00": 5, "14:05": 12, ...}
        }
    """
    log_path = Path(LOG_FILE)
    if not log_path.exists():
        return {"error": "Log file not found. Run the application first."}

    # Read last N lines (max 10000 for performance)
    with open(log_path, "r", encoding="utf-8") as f:
        lines = f.readlines()[-10000:]

    # Statistics containers
    by_level = Counter()
    sources = Counter()
    recent_errors = []
    song_error_counter = Counter()
    proxy_requests = 0
    proxy_blocked = 0
    timeseries = Counter()
    endpoint_counter = Counter()
    throttle_count = 0
    invidious_count = 0

    # Time threshold
    cutoff = datetime.utcnow() - timedelta(hours=hours)

    for line in lines:
        # Parse log line format:
        # 2026-06-11 12:15:23 | INFO | youtube:function:line - message
        match = re.match(
            r"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s*\|\s*(\w+)\s*\|\s*([^:]+).*-\s*(.+)",
            line
        )
        if not match:
            continue

        time_str, level, module, message = match.groups()
        try:
            log_time = datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue

        if log_time < cutoff:
            continue

        # By level
        by_level[level] += 1

        # By source
        if "yt-dlp" in message or "ytdlp" in message:
            sources["yt-dlp"] += 1
        if "invidious" in message.lower():
            sources["invidious"] += 1
            invidious_count += 1
        if "proxy" in message.lower():
            sources["proxy"] += 1
            proxy_requests += 1
            if "blocked" in message.lower() or "fail" in message.lower():
                proxy_blocked += 1

        # Throttle
        if "429" in message or "throttle" in message.lower() or "too many requests" in message.lower():
            throttle_count += 1

        # Track songs with errors
        song_match = re.search(r"video[:=]?\s*([a-zA-Z0-9_-]{11})", message)
        if song_match and level in ("ERROR", "WARNING"):
            song_id = song_match.group(1)
            song_error_counter[song_id] += 1

        # Recent errors (last 50)
        if level == "ERROR":
            recent_errors.append({
                "time": time_str,
                "message": message.strip(),
                "module": module.strip(),
            })
            if len(recent_errors) > 50:
                recent_errors.pop(0)

        # Time series (5-minute buckets)
        minute_bucket = time_str[:16]  # "2026-06-11 12:15"
        timeseries[minute_bucket] += 1

        # Endpoint tracking
        endpoint_match = re.search(r"(GET|POST|PUT|DELETE)\s+(/\S+)", message)
        if endpoint_match:
            endpoint_counter[endpoint_match.group(2)] += 1

    # Top error songs
    top_error_songs = [
        {"youtube_id": sid, "errors": count}
        for sid, count in song_error_counter.most_common(10)
    ]

    # Proxy stability score
    proxy_stability = 0
    if proxy_requests > 0:
        proxy_stability = round(((proxy_requests - proxy_blocked) / proxy_requests) * 100, 1)

    return {
        "time_range": f"Last {hours} hours",
        "total_lines_analyzed": len(lines),
        "by_level": dict(by_level),
        "by_source": dict(sources),
        "recent_errors": recent_errors[-20:],  # Last 20
        "top_error_songs": top_error_songs,
        "proxy_stats": {
            "total_requests": proxy_requests,
            "blocked": proxy_blocked,
            "stability_percent": proxy_stability,
        },
        "throttle_events": throttle_count,
        "invidious_fallbacks": invidious_count,
        "endpoint_hits": dict(endpoint_counter.most_common(15)),
        "timeseries": {
            "labels": list(timeseries.keys())[-50:],
            "values": [timeseries[k] for k in list(timeseries.keys())[-50:]],
        },
        "logs_file": str(log_path),
        "logs_size_mb": round(log_path.stat().st_size / (1024 * 1024), 2) if log_path.exists() else 0,
    }