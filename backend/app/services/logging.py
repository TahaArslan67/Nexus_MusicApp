"""Nexus Logging Service

yt-dlp hatalarını, Invidious fallback'lerini ve proxy engellemelerini loglar.
Geliştiricinin hangi şarkıların alternatif kaynaklara düştüğünü
ve hangi proxy'lerin engellendiğini görmesini sağlar.
"""

import os
import sys
from pathlib import Path

from loguru import logger


def setup_logging():
    """Configure loguru logger for Nexus.

    Log seviyeleri:
    - DEBUG:    yt-dlp raw output, buffer stats, detaylı hata ayıklama
    - INFO:     Stream başlatma, indirme tamamlama, auth işlemleri
    - WARNING:  Invidious fallback, proxy hatası, throttle uyarısı
    - ERROR:    Stream başarısız, download başarısız, auth hatası
    """
    log_level = os.getenv("NEXUS_LOG_LEVEL", "INFO").upper()
    log_file = os.getenv("NEXUS_LOG_FILE", "./logs/nexus.log")

    # Ensure log directory exists
    log_path = Path(log_file)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    # Remove default handler
    logger.remove()

    # Console handler (renkli, geliştirme için)
    logger.add(
        sys.stderr,
        format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan> - {message}",
        level=log_level,
        colorize=True,
    )

    # File handler (tüm seviyeler, rotasyonlu)
    logger.add(
        log_file,
        format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} - {message}",
        level="DEBUG",
        rotation="10 MB",      # Her 10MB'da yeni dosya
        retention="30 days",   # 30 gün sakla
        compression="zip",     # Eski logları sıkıştır
    )

    logger.info("Nexus logging initialized (level=%s, file=%s)", log_level, log_file)
    return logger


# Global logger instance
nexus_logger = setup_logging()