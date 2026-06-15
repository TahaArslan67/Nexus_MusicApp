import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/song.dart';
import '../../services/youtube_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/local_db_service.dart';

/// YouTube arama ekranı — backend yok, youtube_explode_dart ile direkt arama
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _youtubeService = YoutubeService();
  final _localDb = LocalDbService();
  final _connectivity = ConnectivityService();
  final _focusNode = FocusNode();

  List<Song> _results = [];
  Set<String> _favoriteIds = {};
  List<String> _searchHistory = [];
  bool _isLoading = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadFavoriteIds();
  }

  Future<void> _loadFavoriteIds() async {
    final favs = await _localDb.getFavorites();
    if (mounted) {
      setState(() => _favoriteIds = favs.map((s) => s.youtubeId).toSet());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _youtubeService.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    _searchHistory = await _localDb.getSearchHistory();
    setState(() {});
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;

    _focusNode.unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
    });

    try {
      _connectivity.ensureConnected();
      final results = await _youtubeService.search(query.trim());
      if (mounted) {
        setState(() {
          _results = results;
        });
      }
      await _localDb.addToHistory(query.trim());
      await _loadHistory();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('İnternet')
              ? 'İnternet bağlantısı yok'
              : 'Arama başarısız: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusTheme.surfaceDark,
      body: SafeArea(
        child: Column(
          children: [
            // ── Arama Çubuğu ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Şarkı, sanatçı veya albüm ara...',
                  hintStyle: const TextStyle(color: NexusTheme.textTertiary),
                  prefixIcon: const Icon(Icons.search, color: NexusTheme.textTertiary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: NexusTheme.textTertiary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _results = [];
                              _hasSearched = false;
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: NexusTheme.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: NexusTheme.primaryGreen),
                  ),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
              ),
            ),

            // ── Yükleniyor ───────────────────────────────────────
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: NexusTheme.primaryGreen),
              ),

            // ── Hata ─────────────────────────────────────────────
            if (_error != null && !_isLoading)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: NexusTheme.errorRed),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: NexusTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _search(_searchController.text),
                      style: ElevatedButton.styleFrom(backgroundColor: NexusTheme.primaryGreen),
                      child: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),

            // ── Arama Sonuçları ──────────────────────────────────
            if (!_isLoading && _hasSearched && _error == null)
              Expanded(
                child: _results.isEmpty
                    ? const Center(
                        child: Text('Sonuç bulunamadı', style: TextStyle(color: NexusTheme.textSecondary)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _results.length,
                        itemBuilder: (ctx, index) => _buildSongTile(_results[index], index),
                      ),
              ),

            // ── Geçmiş (arama yapılmadığında) ────────────────────
            if (!_hasSearched && !_isLoading)
              Expanded(
                child: _searchHistory.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 64, color: NexusTheme.textTertiary),
                            SizedBox(height: 16),
                            Text(
                              'YouTube\'da şarkı ara',
                              style: TextStyle(color: NexusTheme.textSecondary, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Son Aramalar',
                                  style: TextStyle(
                                    color: NexusTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await _localDb.clearHistory();
                                    await _loadHistory();
                                  },
                                  child: const Text(
                                    'Temizle',
                                    style: TextStyle(color: NexusTheme.textTertiary, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ..._searchHistory.map((query) => ListTile(
                            leading: const Icon(Icons.history, color: NexusTheme.textTertiary, size: 20),
                            title: Text(query, style: const TextStyle(color: Colors.white)),
                            onTap: () {
                              _searchController.text = query;
                              _search(query);
                            },
                          )),
                        ],
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongTile(Song song, int index) {
    final isFav = _favoriteIds.contains(song.youtubeId);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(song.thumbnailUrl, width: 48, height: 48, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(width: 48, height: 48,
            color: NexusTheme.surfaceElevated,
            child: const Icon(Icons.music_note, color: NexusTheme.textTertiary)),
        ),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white)),
      subtitle: Text('${song.artist} • ${song.formattedDuration}',
          style: const TextStyle(color: NexusTheme.textTertiary, fontSize: 12)),
      trailing: IconButton(
        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? NexusTheme.primaryGreen : NexusTheme.textTertiary, size: 22),
        onPressed: () async {
          if (isFav) {
            await _localDb.removeFavorite(song.youtubeId);
          } else {
            await _localDb.addFavorite(song);
          }
          await _loadFavoriteIds();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isFav ? '💔 Favorilerden çıkarıldı' : '❤️ Favorilere eklendi'),
                backgroundColor: isFav ? Colors.grey : NexusTheme.primaryGreen,
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
      onTap: () {
        Navigator.of(context).pushNamed('/player', arguments: {
          'songs': _results,
          'index': index,
        });
      },
    );
  }
}