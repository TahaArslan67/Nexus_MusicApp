# Nexus — Modern Müzik Uygulaması

YouTube üzerinden ses akışı (stream) ve yerel indirme desteği sunan, Spotify benzeri koyu temalı mobil müzik uygulaması.

## Mimari

```
nexus/
├── backend/                    # FastAPI Backend
│   ├── app/
│   │   ├── main.py            # Uygulama giriş noktası
│   │   ├── config.py          # Yapılandırma (kota, cache, vs.)
│   │   ├── models/
│   │   │   └── database.py    # SQLAlchemy modelleri (User, Song, LibrarySong)
│   │   ├── schemas/
│   │   │   ├── auth.py        # Pydantic şemaları (Auth)
│   │   │   └── music.py       # Pydantic şemaları (Music)
│   │   ├── services/
│   │   │   ├── auth.py        # JWT + password hashing
│   │   │   ├── youtube.py     # yt-dlp stream/download
│   │   │   ├── search.py      # Quota-aware search
│   │   │   ├── quota.py       # Kota yönetimi
│   │   │   └── cache.py       # Önbellekleme + adaptive bitrate
│   │   └── routers/
│   │       ├── auth_router.py   # /auth/* endpoints
│   │       ├── music_router.py  # /music/* endpoints
│   │       └── search_router.py # /search/* endpoints
│   └── requirements.txt
│
├── frontend/                   # Flutter UI
│   ├── lib/
│   │   ├── main.dart          # App giriş + HomeScreen
│   │   ├── core/
│   │   │   ├── theme/         # Spotify-esque dark theme
│   │   │   ├── constants/     # API endpoint sabitleri
│   │   │   └── network/       # Dio HTTP client + auth interceptor
│   │   ├── models/            # Song, StreamInfo modelleri
│   │   └── features/
│   │       ├── auth/          # Login/Register ekranı
│   │       ├── search/        # Arama ekranı
│   │       ├── player/        # Tam ekran oynatıcı (just_audio)
│   │       └── library/       # Kullanıcı kütüphanesi
│   └── pubspec.yaml
│
└── docs/
    └── API_DOKUMENTASYONU.md  # API dokümantasyonu
```

## Öne Çıkan Özellikler

### 🎵 Ses Akışı
- yt-dlp ile YouTube'dan doğrudan ses (audio-only) çekme
- Adaptive bitrate: düşük bant genişliğinde otomatik kalite düşürme
- Çoklu codec desteği: opus, m4a, webm

### 💾 Yerel İndirme
- Şarkıları cihaza kaydetme
- Çevrimdışı dinleme desteği
- Otomatik cache temizleme (7 gün)

### 🔒 Güvenlik
- JWT token authentication
- bcrypt şifreleme
- Session yönetimi

### 📊 Kota Yönetimi
- Günlük 10,000 birim limit
- Search (100 birim) yerine ID-based lookup (1 birim)
- Otomatik kota sıfırlama
- Gerçek zamanlı kota takibi

### ⚡ Performans
- In-memory metadata cache (1 saat)
- Stream URL cache (5 dakika)
- SQLite ile kalıcı metadata cache
- 256KB chunk streaming
- Prefetch hint sistemi

## Kurulum

### Backend

```bash
cd backend
pip install -r requirements.txt
pip install yt-dlp  # yt-dlp kurulumu
uvicorn app.main:app --reload --port 8000
```

API şu adreste çalışacak: `http://localhost:8000`

### Frontend

```bash
cd frontend
flutter pub get
flutter run
```

## API Dokümantasyonu

Detaylı API dokümantasyonu için: [docs/API_DOKUMENTASYONU.md](docs/API_DOKUMENTASYONU.md)

FastAPI otomatik dokümantasyonu: `http://localhost:8000/docs`

## Teknolojiler

| Katman | Teknoloji |
|--------|-----------|
| Backend | FastAPI, SQLAlchemy, yt-dlp |
| Frontend | Flutter, Riverpod, just_audio |
| Auth | JWT (python-jose), bcrypt |
| Cache | In-memory, SQLite, Local files |
| Streaming | yt-dlp, HTTP chunked |

## Lisans

MIT