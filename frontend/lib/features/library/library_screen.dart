import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/song.dart';
import '../../services/local_db_service.dart';

/// Kütüphane ekranı — favoriler + playlist'ler
class LibraryScreen extends StatefulWidget {
  final VoidCallback? onSwitchToSearch;

  const LibraryScreen({super.key, this.onSwitchToSearch});

  @override
  State<LibraryScreen> createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen> with RouteAware {

  final _localDb = LocalDbService();
  List<Song> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ekran görünür hale gelince favorileri yenile
    _loadFavorites();
  }

  /// Dışarıdan (örn. sekme değişimi) favori listesini yenilemek için
  Future<void> reload() => _loadFavorites();

  Future<void> _loadFavorites() async {
    if (!mounted) return;
    _favorites = await _localDb.getFavorites();
    if (mounted) setState(() => _isLoading = false);
  }


  Future<void> _toggleFavorite(Song song) async {
    await _localDb.toggleFavorite(song);
    await _loadFavorites();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🗑️ Favorilerden çıkarıldı'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _playAll() {
    if (_favorites.isEmpty) return;
    Navigator.of(context).pushNamed('/player', arguments: {
      'songs': _favorites,
      'index': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: NexusTheme.primaryGreen));
    }

    return Column(
      children: [
        if (_favorites.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _playAll,
                    icon: const Icon(Icons.play_arrow, color: Colors.black, size: 20),
                    label: const Text('Tümünü Çal'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexusTheme.primaryGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/playlist'),
                    icon: const Icon(Icons.playlist_add, size: 20),
                    label: const Text('Playlist'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NexusTheme.textPrimary,
                      side: const BorderSide(color: NexusTheme.surfaceHover),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: _favorites.isEmpty
              ? GestureDetector(
                  onTap: widget.onSwitchToSearch,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite_border, size: 64, color: NexusTheme.textTertiary),
                        const SizedBox(height: 16),
                        const Text(
                          'Henüz favori şarkı yok',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Arama ekranından şarkıları favorilere ekleyin',
                          style: TextStyle(color: NexusTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: widget.onSwitchToSearch,
                          icon: const Icon(Icons.search),
                          label: const Text('Keşfet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NexusTheme.primaryGreen,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: NexusTheme.primaryGreen,
                  backgroundColor: NexusTheme.surfaceElevated,
                  onRefresh: _loadFavorites,
                  child: ListView.builder(
                    itemCount: _favorites.length,
                    itemBuilder: (ctx, index) {
                      final song = _favorites[index];
                      return Dismissible(
                        key: Key('fav_${song.youtubeId}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: NexusTheme.errorRed,
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) => _localDb.removeFavorite(song.youtubeId).then((_) => _loadFavorites()),
                        child: ListTile(
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
                            icon: const Icon(Icons.delete_outline, color: NexusTheme.textTertiary, size: 20),
                            onPressed: () => _toggleFavorite(song),
                          ),
                          onTap: () => Navigator.of(context).pushNamed('/player', arguments: {
                            'songs': _favorites, 'index': index,
                          }),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
