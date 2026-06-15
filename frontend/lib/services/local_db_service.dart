import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

/// Yerel veritabanı (Hive) — favoriler, indirilenler, geçmiş
class LocalDbService {
  static const String _favoritesBox = 'favorites';
  static const String _historyBox = 'history';
  static const String _downloadsBox = 'downloads';

  static Future<void> initialize() async {
    await Hive.initFlutter();
    // Adapter'ı yalnızca bir kez kaydet (çift kayıt exception fırlatır)
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SongAdapter());
    }
    if (!Hive.isBoxOpen(_favoritesBox)) {
      await Hive.openBox<Song>(_favoritesBox);
    }
    if (!Hive.isBoxOpen(_historyBox)) {
      await Hive.openBox<String>(_historyBox);
    }
    if (!Hive.isBoxOpen(_downloadsBox)) {
      await Hive.openBox<String>(_downloadsBox);
    }
  }


  // ── Favoriler ────────────────────────────────────────────────────

  Future<List<Song>> getFavorites() async {
    final box = Hive.box<Song>(_favoritesBox);
    return box.values.toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<bool> isFavorite(String youtubeId) async {
    final box = Hive.box<Song>(_favoritesBox);
    return box.containsKey(youtubeId);
  }

  Future<void> addFavorite(Song song) async {
    final box = Hive.box<Song>(_favoritesBox);
    await box.put(song.youtubeId, song);
  }

  Future<void> removeFavorite(String youtubeId) async {
    final box = Hive.box<Song>(_favoritesBox);
    await box.delete(youtubeId);
  }

  Future<void> toggleFavorite(Song song) async {
    if (await isFavorite(song.youtubeId)) {
      await removeFavorite(song.youtubeId);
    } else {
      await addFavorite(song);
    }
  }

  int get favoriteCount {
    final box = Hive.box<Song>(_favoritesBox);
    return box.length;
  }

  // ── İndirilenler ─────────────────────────────────────────────────

  Future<List<String>> getDownloadedIds() async {
    final box = Hive.box<String>(_downloadsBox);
    return box.values.toList();
  }

  Future<bool> isDownloaded(String youtubeId) async {
    final box = Hive.box<String>(_downloadsBox);
    return box.containsKey(youtubeId);
  }

  Future<void> markDownloaded(String youtubeId, String filePath) async {
    final box = Hive.box<String>(_downloadsBox);
    await box.put(youtubeId, filePath);
  }

  Future<void> removeDownloaded(String youtubeId) async {
    final box = Hive.box<String>(_downloadsBox);
    await box.delete(youtubeId);
  }

  String? getDownloadedPath(String youtubeId) {
    final box = Hive.box<String>(_downloadsBox);
    return box.get(youtubeId);
  }

  // ── Arama Geçmişi ────────────────────────────────────────────────

  Future<List<String>> getSearchHistory() async {
    final box = Hive.box<String>(_historyBox);
    return box.values.toList().reversed.take(10).toList();
  }

  Future<void> addToHistory(String query) async {
    final box = Hive.box<String>(_historyBox);
    final existing = box.keys.where((k) => box.get(k) == query).toList();
    for (final key in existing) {
      await box.delete(key);
    }

    await box.add(query);
    if (box.length > 50) await box.deleteAt(0);
  }

  Future<void> clearHistory() async {
    final box = Hive.box<String>(_historyBox);
    await box.clear();
  }

  // ── Utility ──────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await Hive.box<Song>(_favoritesBox).clear();
    await Hive.box<String>(_historyBox).clear();
    await Hive.box<String>(_downloadsBox).clear();
  }
}