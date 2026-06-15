import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

import '../../core/theme/app_theme.dart';
import '../../main.dart';
import '../../models/song.dart';
import '../../services/local_db_service.dart';
import '../../services/youtube_service.dart';
import '../../services/room_service.dart';

class PlayerScreen extends StatefulWidget {
  final List<Song> songs;
  final int initialIndex;

  const PlayerScreen({super.key, required this.songs, required this.initialIndex});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _localDb = LocalDbService();
  final _youtubeService = YoutubeService();

  late List<Song> _songs;
  late int _currentIndex;
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _isShuffled = false;
  bool _isRepeat = false;
  List<int> _shuffledOrder = [];
  bool _isDownloaded = false;
  bool _isDownloading = false;
  String? _error;

  // Stream dinleyicileri
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration? _duration;
  bool _isPlaying = false;
  ProcessingState _processingState = ProcessingState.idle;

  // Stream subscription'ları temizlemek için
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.songs);
    _currentIndex = widget.initialIndex;
    _init();
  }

  Future<void> _init() async {
    await _updateState();
    await _loadAndPlay();

    // Global audio handler callback'lerini ayarla
    audioHandler?.onSkipNext = () {
      _onSkipFromNotification(next: true);
    };
    audioHandler?.onSkipPrevious = () {
      _onSkipFromNotification(next: false);
    };

    // Room sync dinleyicileri
    _listenToRoom();
  }

  void _listenToRoom() {
    final rs = roomService;
    if (rs == null) return;

    // Slave: room'dan gelen komutları uygula
    rs.onPlay.listen((posMs) {
      if (!rs.isMaster) {
        audioHandler?.seek(Duration(milliseconds: posMs));
        audioHandler?.play();
      }
    });
    rs.onPause.listen((posMs) {
      if (!rs.isMaster) {
        audioHandler?.seek(Duration(milliseconds: posMs));
        audioHandler?.pause();
      }
    });
    rs.onSeek.listen((posMs) {
      if (!rs.isMaster) {
        audioHandler?.seek(Duration(milliseconds: posMs));
      }
    });
    rs.onSongChange.listen((song) {
      if (!rs.isMaster) {
        setState(() {
          _songs = [song];
          _currentIndex = 0;
        });
        _updateState();
        _loadAndPlay();
      }
    });
  }

  void _listenToPlayer() {
    // Önce eski subscription'ları temizle (memory leak önleme)
    for (final sub in _subs) { sub.cancel(); }
    _subs.clear();

    final player = audioHandler?.player;
    if (player == null) return;

    _subs.add(player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    }));
    _subs.add(player.bufferedPositionStream.listen((buf) {
      if (mounted) setState(() => _buffered = buf);
    }));
    _subs.add(player.durationStream.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }));
    _subs.add(player.playingStream.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    }));
    _subs.add(player.processingStateStream.listen((state) {
      if (mounted) setState(() => _processingState = state);
    }));
  }

  Future<void> _loadAndPlay() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final song = _currentSong;

    // Audio handler kontrolü
    if (audioHandler == null) {
      setState(() {
        _error = 'Ses servisi başlatılamadı';
        _isLoading = false;
      });
      return;
    }

    try {
      // Audio handler'a şarkıyı bildir (bildirim çubuğu hemen güncellensin)
      await audioHandler!.playQueue(_songs, _currentIndex);

      // Player dinleyicilerini bağla
      _listenToPlayer();

      // Stream URL'ini çöz
      final url = await _youtubeService.getStreamUrl(song.youtubeId);
      if (url == null || url.isEmpty) {
        setState(() {
          _error = 'Stream bulunamadı. Başka bir şarkı deneyin.';
          _isLoading = false;
        });
        return;
      }

      // Kullanıcı bu sırada başka şarkıya geçtiyse bu yüklemeyi iptal et
      if (!mounted || _currentSong.youtubeId != song.youtubeId) return;

      // URL'i audio handler'a ver ve oynat
      await audioHandler!.setAudioUrl(url);

      // Sonraki şarkıyı önceden çöz (kesintisiz geçiş)
      if (_songs.length > 1) {
        final nextIndex = (_currentIndex + 1) % _songs.length;
        _youtubeService.prefetchStreamUrl(_songs[nextIndex].youtubeId);
      }

      // Room: master ise şarkı değişikliğini broadcast et
      if (roomService?.isMaster == true) {
        roomService?.sendSongChange(_currentSong);
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e, st) {
      debugPrint('[Nexus] Play error: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Oynatma hatası: $e';
          _isLoading = false;
        });
      }
    }
  }


  Future<void> _updateState() async {
    final song = _currentSong;
    _isFavorite = await _localDb.isFavorite(song.youtubeId);
    _isDownloaded = await _localDb.isDownloaded(song.youtubeId);
    if (mounted) setState(() {});
  }

  Song get _currentSong {
    if (_isShuffled && _shuffledOrder.isNotEmpty) {
      return _songs[_shuffledOrder[_currentIndex % _shuffledOrder.length]];
    }
    return _songs[_currentIndex];
  }

  void _onSkipFromNotification({required bool next}) {
    if (!mounted) return;
    if (next) {
      _playNext();
    } else {
      _playPrevious();
    }
  }

  void _playAt(int index) {
    _currentIndex = index;
    _updateState();
    _loadAndPlay();
  }

  void _playNext() {
    setState(() => _currentIndex = (_currentIndex + 1) % _songs.length);
    _updateState();
    _loadAndPlay();
  }

  void _playPrevious() {
    setState(() => _currentIndex = (_currentIndex - 1 + _songs.length) % _songs.length);
    _updateState();
    _loadAndPlay();
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffled = !_isShuffled;
      if (_isShuffled) {
        _shuffledOrder = List.generate(_songs.length, (i) => i);
        _shuffledOrder.shuffle(Random());
      } else {
        _shuffledOrder = [];
      }
    });
  }

  void _toggleRepeat() {
    setState(() => _isRepeat = !_isRepeat);
    // Handler'a tekrar modunu bildir (1 = tek şarkı, 0 = kapalı)
    audioHandler?.repeatMode = _isRepeat ? 1 : 0;
  }


  Future<void> _toggleFavorite() async {
    final song = _currentSong;
    await _localDb.toggleFavorite(song);
    final nowFav = await _localDb.isFavorite(song.youtubeId);
    setState(() => _isFavorite = nowFav);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nowFav ? '❤️ Favorilere eklendi' : '💔 Favorilerden çıkarıldı'),
          backgroundColor: nowFav ? NexusTheme.primaryGreen : Colors.grey,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _downloadSong() async {
    final song = _currentSong;
    setState(() => _isDownloading = true);

    try {
      final filePath = await _youtubeService.downloadSong(song.youtubeId, song.title);

      if (filePath != null) {
        await _localDb.markDownloaded(song.youtubeId, filePath);
        setState(() => _isDownloaded = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ İndirildi: ${song.title}'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ İndirme başarısız oldu'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('[Nexus] Download error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ İndirme hatası'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _deleteDownload() async {
    final song = _currentSong;
    final path = _localDb.getDownloadedPath(song.youtubeId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _localDb.removeDownloaded(song.youtubeId);
    setState(() => _isDownloaded = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ İndirme silindi')),
      );
    }
  }

  String _fmt(Duration? d) {
    if (d == null) return '00:00';
    final mins = d.inMinutes;
    final secs = d.inSeconds.remainder(60);
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    for (final sub in _subs) { sub.cancel(); }
    _subs.clear();
    audioHandler?.onSkipNext = null;
    audioHandler?.onSkipPrevious = null;
    _youtubeService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _currentSong;
    final total = _isShuffled && _shuffledOrder.isNotEmpty ? _shuffledOrder.length : _songs.length;

    return Scaffold(
      backgroundColor: NexusTheme.surfaceDark,
      body: SafeArea(
        child: Column(
          children: [
            // Üst bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    onPressed: () => Navigator.pop(context),
                    color: NexusTheme.textPrimary,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.songs.length > 1 ? 'Çalma Listesi (${_currentIndex + 1}/$total)' : 'Şimdi Çalınıyor',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: NexusTheme.textSecondary, fontSize: 12, letterSpacing: 1.5),
                        ),
                        if (roomService?.connected == true)
                          Text(
                            '${roomService!.isMaster ? '👑' : '👤'} Oda: ${roomService!.roomCode} (${roomService!.memberCount})',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: NexusTheme.primaryGreen, fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  // İndirme butonu
                  if (_isDownloading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2, color: NexusTheme.primaryGreen),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        _isDownloaded ? Icons.offline_pin : Icons.file_download_outlined,
                        size: 22,
                      ),
                      onPressed: _isDownloaded ? _deleteDownload : _downloadSong,
                      color: _isDownloaded ? NexusTheme.primaryGreen : NexusTheme.textTertiary,
                    ),
                  // Favori butonu
                  IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      size: 22,
                    ),
                    onPressed: _toggleFavorite,
                    color: _isFavorite ? NexusTheme.primaryGreen : NexusTheme.textTertiary,
                  ),
                ],
              ),
            ),

            // Thumbnail
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    song.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: NexusTheme.surfaceElevated,
                      child: const Center(
                        child: Icon(Icons.music_note, size: 80, color: NexusTheme.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Hata mesajı
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  style: const TextStyle(color: NexusTheme.errorRed, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            // Şarkı bilgisi
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        song.artist,
                        style: const TextStyle(fontSize: 15, color: NexusTheme.textSecondary),
                        maxLines: 1,
                      ),
                      if (_isDownloaded) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.offline_pin, size: 14, color: NexusTheme.primaryGreen),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // İlerleme çubuğu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ProgressBar(
                progress: _position,
                buffered: _buffered,
                total: _duration ?? Duration(seconds: song.durationSeconds),
                onSeek: (duration) {
                  audioHandler?.seek(duration);
                  // Room: master ise broadcast et
                  if (roomService?.isMaster == true) {
                    roomService?.sendSeek(duration.inMilliseconds);
                  }
                },
                progressBarColor: NexusTheme.primaryGreen,
                bufferedBarColor: NexusTheme.surfaceHover,
                baseBarColor: NexusTheme.surfaceElevated,
                thumbColor: NexusTheme.primaryGreen,
                timeLabelTextStyle: const TextStyle(color: NexusTheme.textSecondary, fontSize: 12),
              ),
            ),

            const SizedBox(height: 24),

            // Kontroller
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(Icons.shuffle, size: 24),
                    onPressed: _toggleShuffle,
                    color: _isShuffled ? NexusTheme.primaryGreen : NexusTheme.textSecondary,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 38),
                    onPressed: _songs.length > 1 ? _playPrevious : null,
                    color: _songs.length > 1 ? Colors.white : NexusTheme.textTertiary,
                  ),
                  // Play/Pause
                  GestureDetector(
                    onTap: () {
                      if (_isPlaying) {
                        audioHandler?.pause();
                        // Room: master ise broadcast et
                        if (roomService?.isMaster == true) {
                          roomService?.sendPause(_position.inMilliseconds);
                        }
                      } else {
                        audioHandler?.play();
                        // Room: master ise broadcast et
                        if (roomService?.isMaster == true) {
                          roomService?.sendPlay(_position.inMilliseconds);
                        }
                      }
                    },
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: NexusTheme.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 34,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 38),
                    onPressed: _songs.length > 1 ? _playNext : null,
                    color: _songs.length > 1 ? Colors.white : NexusTheme.textTertiary,
                  ),
                  IconButton(
                    icon: Icon(_isRepeat ? Icons.repeat_one : Icons.repeat, size: 24),
                    onPressed: _toggleRepeat,
                    color: _isRepeat ? NexusTheme.primaryGreen : NexusTheme.textSecondary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
