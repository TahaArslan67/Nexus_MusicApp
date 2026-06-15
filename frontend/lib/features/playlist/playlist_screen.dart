import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/song.dart';
import '../../services/local_db_service.dart';

/// Playlist / Albüm oluşturma ekranı
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  final _localDb = LocalDbService();
  List<Song> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _favorites = await _localDb.getFavorites();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusTheme.surfaceDark,
      appBar: AppBar(
        backgroundColor: NexusTheme.surfaceDark,
        elevation: 0,
        title: const Text('Playlist Oluştur', style: TextStyle(color: Colors.white)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: NexusTheme.primaryGreen))
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.playlist_add, size: 64, color: NexusTheme.textTertiary),
                      const SizedBox(height: 16),
                      const Text(
                        'Playlist için önce favorilere şarkı ekleyin',
                        style: TextStyle(color: NexusTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _favorites.length,
                  itemBuilder: (ctx, index) {
                    final song = _favorites[index];
                    return CheckboxListTile(
                      value: true,
                      onChanged: (_) {},
                      activeColor: NexusTheme.primaryGreen,
                      title: Text(song.title, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(song.artist, style: const TextStyle(color: NexusTheme.textTertiary, fontSize: 12)),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _favorites.isEmpty
            ? null
            : () {
                Navigator.of(context).pushNamed('/player', arguments: {
                  'songs': _favorites,
                  'index': 0,
                });
              },
        backgroundColor: NexusTheme.primaryGreen,
        label: const Text('Hepsini Çal', style: TextStyle(color: Colors.black)),
        icon: const Icon(Icons.play_arrow, color: Colors.black),
      ),
    );
  }
}