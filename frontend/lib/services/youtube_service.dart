import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
    try {
      final stopwatch = Stopwatch()..start();
      final url = await _getBackendStreamUrl(youtubeId);
      if (url != null) {
        _streamUrlCache[youtubeId] = url;
        print('[Nexus] Resolved in ${stopwatch.elapsedMilliseconds}ms via backend');
      }
      return url;
    } catch (e) {
      print('[Nexus] Resolve error for $youtubeId: $e');
      return null;
    }
  }

  // ── Backend URL ─────────────────────────────────────────────────────
  // Debug:  bilgisayarın local IP'si (hot reload için)
  // Release: Render deploy URL'si
  static const String _backendBase =
      kDebugMode ? 'http://192.168.18.106:8000' : 'https://nexus-music-api-c1fj.onrender.com';

  Future<String?> _getBackendStreamUrl(String youtubeId) async {
    final backendUrl = '$_backendBase/music/public/stream';
    try {
      final check = await http.get(
        Uri.parse('$_backendBase/health'),
      ).timeout(const Duration(seconds: 3));
      if (check.statusCode != 200) {
        print('[Nexus] Backend unreachable');
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
      final manifest = await _yt.videos.streams.getManifest(youtubeId);

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
