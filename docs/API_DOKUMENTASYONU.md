# Nexus Music API Dokümantasyonu

## Genel Bakış

Nexus, YouTube üzerinden ses akışı (stream) ve yerel indirme desteği sunan bir müzik uygulamasıdır. Backend, FastAPI ve yt-dlp kullanılarak inşa edilmiştir.

**Base URL:** `http://localhost:8000`

**Auth:** Tüm endpoint'ler (auth hariç) `Authorization: Bearer <token>` header'ı gerektirir.

---

## Kota Sistemi

| İşlem | Kota Birimi |
|-------|------------|
| Arama (Search) | 100 |
| Video Detayı (ID-based) | 1 |
| Stream URL | 1 |
| İndirme | 1 |
| Günlük Limit | 10,000 |

**Strateji:** Mümkün olduğunca ID-based sorgular (1 birim) kullan, Search'ten (100 birim) kaçın.

---

## Endpoint'ler

### Health Check

```
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0"
}
```

---

### Auth

#### Register
```
POST /auth/register
```

**Request Body:**
```json
{
  "username": "string (3-64 chars)",
  "email": "email format",
  "password": "string (6-128 chars)"
}
```

**Response (201):**
```json
{
  "access_token": "jwt_token",
  "token_type": "bearer",
  "user_id": 1,
  "username": "user"
}
```

#### Login
```
POST /auth/login
```

**Request Body:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response (200):**
```json
{
  "access_token": "jwt_token",
  "token_type": "bearer",
  "user_id": 1,
  "username": "user"
}
```

#### Profile
```
GET /auth/me
```

**Headers:** `Authorization: Bearer <token>`

**Response:**
```json
{
  "id": 1,
  "username": "user",
  "email": "user@example.com",
  "is_active": true,
  "daily_quota_used": 5
}
```

#### Quota Status
```
GET /auth/quota
```

**Response:**
```json
{
  "daily_limit": 10000,
  "used": 5,
  "remaining": 9995,
  "reset_at": "2026-06-11T12:00:00"
}
```

---

### Music

#### Song Info (1 birim)
```
GET /music/info/{youtube_id}
```

**Parameters:**
- `youtube_id`: YouTube video ID (örn. `dQw4w9WgXcQ`)

**Response:**
```json
{
  "id": 1,
  "youtube_id": "dQw4w9WgXcQ",
  "title": "Rick Astley - Never Gonna Give You Up",
  "artist": "Rick Astley",
  "duration_seconds": 212,
  "thumbnail_url": "https://i.ytimg.com/vi/...",
  "audio_url": "",
  "is_cached": false
}
```

#### Stream (1 birim)
```
GET /music/stream/{youtube_id}
```

**Response:** Yerel dosya (eğer cache'de varsa) veya redirect URL + metadata.

```json
{
  "youtube_id": "dQw4w9WgXcQ",
  "title": "Rick Astley - Never Gonna Give You Up",
  "artist": "Rick Astley",
  "duration_seconds": 212,
  "stream_url": "https://...direct-audio-url...",
  "content_type": "audio/webm"
}
```

#### Download (1 birim)
```
POST /music/download/{youtube_id}
```

**Response:**
```json
{
  "status": "downloaded",
  "file_path": "backend/cache/ytdlp/dQw4w9WgXcQ.opus",
  "song_id": 1
}
```

#### Library
```
GET /music/library
```

**Response:**
```json
[
  {
    "id": 1,
    "song": {
      "id": 1,
      "youtube_id": "dQw4w9WgXcQ",
      "title": "...",
      "artist": "...",
      "duration_seconds": 212,
      "thumbnail_url": "...",
      "audio_url": "",
      "is_cached": true
    },
    "is_downloaded": true,
    "added_at": "2026-06-11T12:00:00"
  }
]
```

#### Remove from Library
```
DELETE /music/library/{song_id}
```

**Response:** `204 No Content`

#### Cache Stats
```
GET /music/cache/stats
```

**Response:**
```json
{
  "cache_size_mb": 12.5,
  "metadata_cache_size": 42,
  "stream_cache_size": 5
}
```

---

### Search (100 birim — dikkatli kullanın!)

#### Search
```
GET /search?q={query}&source=auto&limit=10
```

**Parameters:**
- `q`: Arama sorgusu (1-200 chars)
- `source`: `auto` (önce local DB, sonra YouTube), `local`, `youtube`
- `limit`: 1-50

**Response:**
```json
[
  {
    "id": 0,
    "youtube_id": "dQw4w9WgXcQ",
    "title": "...",
    "artist": "...",
    "duration_seconds": 212,
    "thumbnail_url": "...",
    "audio_url": "",
    "is_cached": false
  }
]
```

#### Suggestions (0 birim)
```
GET /search/suggestions?q={query}
```

**Response:**
```json
{
  "suggestions": ["Song Title 1", "Song Title 2", ...]
}
```

---

## ⚡ Kritik Performans Stratejileri

### 1. AAC Öncelikli Streaming (Mobil Optimizasyon)
- **Stream:** `bestaudio[ext=m4a]` öncelikli → mobil donanım decode
- **Download:** FFmpeg ile AAC transcoding (mevcutsa)
- **Fallback:** Opus/WebM → MP3
- **Sebep:** Mobil cihazlar AAC'i donanım seviyesinde decode eder, pil tüketimi %30-50 daha az

### 2. Background Playback (Ekran Kapalıyken Çalma)
- **audio_service** + **audio_session** ile background task
- Telefon ekranı kapandığında müzik kesilmez
- Android/iOS lock screen kontrol desteği
- Audio focus yönetimi (başka uygulama ses çalınca ducking)

### 3. Local-First Fuzzy Search (%90 Kota Tasarrufu)
- **Token bazlı fuzzy matching:** yazım hatalarını tolere eder (`beatls` → `Beatles`)
- **Multi-token parsing:** "paris olimpiyadı" → "Paris" + "Olimpiyatları"
- **Score-based sıralama:** artist match'e bonus, partial match desteği
- **Zero quota cost:** tüm local aramalar ücretsiz, sadece yetersizse YouTube (100 birim)

### 4. Önbellekleme (Caching)
| Katman | TTL | Amaç |
|--------|-----|------|
| In-memory metadata | 1 saat | Sık erişilen şarkı detayları |
| Stream URL | 5 dakika | Geçici stream linkleri |
| SQLite DB | Süresiz | Kalıcı metadata cache |
| Yerel dosya | Kullanıcı silene kadar | Çevrimdışı dinleme |
| Auto-cleanup | 7 gün | Eski cache dosyalarını temizle |

### 5. Adaptive Bitrate
| Bant Genişliği | Kalite |
|---------------|--------|
| < 100 kbps | 48 kbps |
| 100-500 kbps | 70 kbps |
| 500-2000 kbps | 96 kbps |
| > 2000 kbps | 128 kbps (AAC öncelikli) |

---

## Kurulum

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

## Gereksinimler

- Python 3.10+
- yt-dlp (`pip install yt-dlp`)
- ffmpeg (ses dosyası işleme için)