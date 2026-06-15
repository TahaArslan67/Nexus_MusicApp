# Nexus Backend Deploy

## Render (Ücretsiz)

1. GitHub repo'sunu Render'a bağla
2. Blueprint olarak `render.yaml` seç
3. Deploy

URL: `https://nexus-music-api.onrender.com`

## Flutter'da Backend URL'yi Güncelle

`lib/services/youtube_service.dart` içindeki `_getBackendStreamUrl` metodundaki IP'yi deploy URL ile değiştir.
