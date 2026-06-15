import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song.dart';

class YoutubeService {
  late final YoutubeExplode _yt;

  static final Map<String, String> _streamUrlCache = {};
  static final Set<String> _prefetching = {};

  YoutubeService() {
    _yt = YoutubeExplode();
  }

  Future<List<Song>> search(String query, {int maxResults = 20}) async {
    try {
      final results = await _yt.search.search(query);
      final songs = <Song>[];
      final videos = results.take(maxResults);
      int i = 0;
      for (final video in videos) {
        songs.add(Song(
          id: i++,
          youtubeId: video.id.value,
          title: video.title,
          artist: video.author,
          durationSeconds: video.duration?.inSeconds ?? 0,
          thumbnailUrl: video.thumbnails.highResUrl,
          audioUrl: '',
          isCached: false,
        ));
      }

      // İLK şarkının URL'ini hemen çözmeye başla (kullanıcı tıklayınca hazır olsun)
      if (songs.isNotEmpty) {
        prefetchStreamUrl(songs.first.youtubeId);
      }

      return songs;
    } catch (e) {
      throw Exception('Arama hatası: $e');
    }
  }

  void prefetchStreamUrl(String youtubeId) {
    if (_streamUrlCache.containsKey(youtubeId) || _prefetching.contains(youtubeId)) return;
    _prefetching.add(youtubeId);
    _resolveStreamUrl(youtubeId).then((url) {
      if (url != null) {
        _streamUrlCache[youtubeId] = url;
        print('[Nexus] Prefetched URL for $youtubeId in ${DateTime.now().millisecondsSinceEpoch}');
      }
      _prefetching.remove(youtubeId);
    });
  }

  Future<String?> getStreamUrl(String youtubeId) async {
    if (_streamUrlCache.containsKey(youtubeId)) {
      return _streamUrlCache[youtubeId];
    }
    return await _resolveStreamUrl(youtubeId);
  }

  Future<String?> _resolveStreamUrl(String youtubeId) async {
    final stopwatch = Stopwatch()..start();

    // 1. Önce direkt YouTube stream (telefon residential IP -> bot korumasına takılmaz)
    try {
      final url = await _getDirectStreamUrl(youtubeId);
      if (url != null) {
        _streamUrlCache[youtubeId] = url;
        print('[Nexus] Resolved in ${stopwatch.elapsedMilliseconds}ms via direct');
        return url;
      }
    } catch (e) {
      print('[Nexus] Direct stream failed: $e');
    }

    // 2. Backend proxy fallback (evde kendi bilgisayarın veya cloud)
    try {
      final url = await _getBackendStreamUrl(youtubeId);
      if (url != null) {
        _streamUrlCache[youtubeId] = url;
        print('[Nexus] Resolved in ${stopwatch.elapsedMilliseconds}ms via backend');
        return url;
      }
    } catch (e) {
      print('[Nexus] Backend stream failed: $e');
    }

    return null;
  }

  /// Direkt YouTube stream URL (telefon IP'si residential)
  Future<String?> _getDirectStreamUrl(String youtubeId) async {
    try {
      // iOS + Safari client: daha az bot korumasına takılır
      final manifest = await _yt.videos.streams.getManifest(
        youtubeId,
        ytClients: [YoutubeApiClient.ios, YoutubeApiClient.safari],
      );
      final audio = manifest.audioOnly.withHighestBitrate();
      if (audio != null) {
        return audio.url.toString();
      }
    } catch (e) {
      print('[Nexus] Direct YouTube error: $e');
    }
    return null;
  }

  // ── Backend URL ─────────────────────────────────────────────────────
  // Kullanıcı ayarladıysa onu, yoksa default'u kullan
  static Future<String> _getBackendBase() async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('backend_url');
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    return kDebugMode
        ? 'http://192.168.18.106:8000'
        : 'https://nexus-music-api-c1fj.onrender.com';
  }

  Future<String?> _getBackendStreamUrl(String youtubeId) async {
    final base = await _getBackendBase();
    final backendUrl = '$base/music/public/stream';
    try {
      final check = await http.get(
        Uri.parse('$base/health'),
      ).timeout(const Duration(seconds: 2));
      if (check.statusCode != 200) {
        print('[Nexus] Backend unreachable: $base');
        return null;
      }
      return '$backendUrl/$youtubeId';
    } catch (e) {
      print('[Nexus] Backend connection failed: $e');
      return null;
    }
  }

  /// Doğrudan youtube_explode_dart stream'i kullanarak indirme yapar.
  /// Bu yöntem YouTube'un segment/tab delimited stream'lerini doğru şekilde işler.
  Future<String?> downloadSong(String youtubeId, String title) async {
    try {
      final manifest = await _yt.videos.streams.getManifest(
        youtubeId,
        ytClients: [YoutubeApiClient.ios, YoutubeApiClient.safari],
      );

      // En iyi audio-only stream'i seç
      final audioOnly = manifest.audioOnly.toList();
      if (audioOnly.isEmpty) return null;

      audioOnly.sort((a, b) {
        final aScore = (a.container.name == 'mp4' || a.container.name == 'm4a') ? 0 : 1;
        final bScore = (b.container.name == 'mp4' || b.container.name == 'm4a') ? 0 : 1;
        if (aScore != bScore) return aScore.compareTo(bScore);
        return a.bitrate.kiloBitsPerSecond.compareTo(b.bitrate.kiloBitsPerSecond);
      });

      final streamInfo = audioOnly.last; // En yüksek kalite audio

      // Dosya yolu oluştur
      final dir = await getApplicationDocumentsDirectory();
      final songDir = Directory('${dir.path}/nexus_downloads');
      if (!await songDir.exists()) await songDir.create(recursive: true);

      final ext = streamInfo.container.name == 'mp4' ? 'm4a' : streamInfo.container.name;
      final filePath = '${songDir.path}/$youtubeId.$ext';
      final file = File(filePath);

      // Zaten indirilmiş ve geçerliyse tekrar indirme
      if (await file.exists() && await file.length() > 0) {
        return filePath;
      }

      // Stream'i chunk-chunk dosyaya yaz (pipe yerine güvenilir yöntem)
      final stream = _yt.videos.streams.get(streamInfo);
      final output = file.openWrite();
      try {
        await for (final data in stream) {
          output.add(data);
        }
        await output.flush();
        await output.close();
      } catch (e) {
        // Yarım kalan dosyayı temizle
        await output.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }

      // Doğrulama: dosya boş olmamalı
      if (!await file.exists() || await file.length() == 0) {
        print('[Nexus] Download produced empty file for $youtubeId');
        return null;
      }

      return filePath;
    } catch (e) {
      print('[Nexus] Download error for $youtubeId: $e');
      return null;
    }
  }


  String? getCachedStreamUrl(String youtubeId) => _streamUrlCache[youtubeId];

  static void clearCache() {
    _streamUrlCache.clear();
    _prefetching.clear();
  }

  void dispose() {
    _yt.close();
  }
}
