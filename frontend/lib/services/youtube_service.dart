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
      final base = await _getBackendBase();
      final uri = Uri.parse('$base/music/jiosaavn/search')
          .replace(queryParameters: {'query': query, 'limit': '$maxResults'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw Exception('Backend search error: ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body);
      final results = (data['results'] as List?) ?? [];
      final songs = <Song>[];
      int i = 0;
      for (final item in results.take(maxResults)) {
        songs.add(Song(
          id: i++,
          youtubeId: item['id'] ?? '',
          title: item['title'] ?? 'Bilinmeyen',
          artist: item['artist'] ?? 'Bilinmeyen Sanatçı',
          durationSeconds: (item['duration'] as num?)?.toInt() ?? 0,
          thumbnailUrl: item['thumbnail'] ?? '',
          audioUrl: '',
          isCached: false,
        ));
      }

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

  Future<String?> _resolveStreamUrl(String songId) async {
    final stopwatch = Stopwatch()..start();

    // JioSaavn stream via backend proxy
    try {
      final base = await _getBackendBase();
      final url = '$base/music/jiosaavn/stream/$songId';
      final check = await http.get(
        Uri.parse('$base/health'),
      ).timeout(const Duration(seconds: 5));
      if (check.statusCode == 200) {
        _streamUrlCache[songId] = url;
        print('[Nexus] Resolved in ${stopwatch.elapsedMilliseconds}ms via JioSaavn');
        return url;
      }
    } catch (e) {
      print('[Nexus] JioSaavn stream failed: $e');
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
  Future<String?> downloadSong(String songId, String title) async {
    try {
      // JioSaavn stream URL'sini backend'den al
      final base = await _getBackendBase();
      final resp = await http.get(
        Uri.parse('$base/music/jiosaavn/song/$songId'),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      final streamUrl = data['stream_url'] as String?;
      if (streamUrl == null || streamUrl.isEmpty) return null;

      // Dosya yolu oluştur
      final dir = await getApplicationDocumentsDirectory();
      final songDir = Directory('${dir.path}/nexus_downloads');
      if (!await songDir.exists()) await songDir.create(recursive: true);

      final filePath = '${songDir.path}/$songId.mp3';
      final file = File(filePath);

      // Zaten indirilmiş ve geçerliyse tekrar indirme
      if (await file.exists() && await file.length() > 0) {
        return filePath;
      }

      // HTTP ile indir
      final songResp = await http.get(Uri.parse(streamUrl)).timeout(const Duration(seconds: 60));
      if (songResp.statusCode != 200) return null;
      await file.writeAsBytes(songResp.bodyBytes);

      if (await file.length() == 0) {
        print('[Nexus] Download produced empty file for $songId');
        return null;
      }

      return filePath;
    } catch (e) {
      print('[Nexus] Download error for $songId: $e');
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
