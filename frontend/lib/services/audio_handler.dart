import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song.dart';

/// Bildirim çubuğu ve lock screen medya kontrolleri + arka plan çalma
class NexusAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  List<Song> _queue = [];

  int _currentIndex = 0;

  /// Tekrar modu: 0 = kapalı, 1 = tek şarkı, 2 = tüm liste
  int repeatMode = 0;

  Song? get currentSong =>
      (_queue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  AudioPlayer get player => _player;

  NexusAudioHandler() {
    // Playback state senkronizasyonu
    _player.playbackEventStream.listen(
      (event) => _broadcastState(),
      onError: (Object e, StackTrace st) {
        print('[NexusAudioHandler] playbackEvent error: $e');
      },
    );

    // Şarkı bittiğinde tekrar moduna göre davran
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onTrackCompleted();
      }
      _broadcastState();
    });

    // Duration değiştiğinde mediaItem'ı güncelle
    _player.durationStream.listen((duration) {
      final song = currentSong;
      if (song != null && duration != null) {
        mediaItem.add(_mediaItemFor(song, duration));
      }
    });
  }

  MediaItem _mediaItemFor(Song song, [Duration? duration]) {
    Uri? art;
    if (song.thumbnailUrl.isNotEmpty) {
      art = Uri.tryParse(song.thumbnailUrl);
    }
    return MediaItem(
      id: song.youtubeId,
      title: song.title.isNotEmpty ? song.title : 'Bilinmeyen',
      artist: song.artist.isNotEmpty ? song.artist : 'Bilinmeyen Sanatçı',
      artUri: art,
      duration: duration ?? Duration(seconds: song.durationSeconds),
    );
  }

  void _onTrackCompleted() {
    if (repeatMode == 1) {
      // Tek şarkı tekrarı
      _player.seek(Duration.zero);
      _player.play();
    } else {
      // Sonraki şarkıya geç (UI'a haber ver, gerçek yüklemeyi UI yapar)
      skipToNext();
    }
  }

  Future<void> playSong(Song song, {String? audioUrl}) async {
    _queue = [song];
    _currentIndex = 0;
    mediaItem.add(_mediaItemFor(song));
    if (audioUrl != null && audioUrl.isNotEmpty) {
      await setAudioUrl(audioUrl);
    }
  }

  Future<void> playQueue(List<Song> songs, int index,
      {Map<String, String>? urlMap}) async {
    _queue = List.from(songs);
    _currentIndex = index.clamp(0, songs.length - 1);
    final song = currentSong;
    if (song != null) {
      mediaItem.add(_mediaItemFor(song));
      final url = urlMap?[song.youtubeId];
      if (url != null && url.isNotEmpty) {
        await setAudioUrl(url);
      }
    }
  }

  /// Stream URL'ini player'a yükler ve oynatmaya başlar.
  Future<void> setAudioUrl(String url) async {
    final showLen = url.length > 120 ? 120 : url.length;
    print('[NexusAudioHandler] Loading URL: ${url.substring(0, showLen)}...');
    try {
      await _player.setUrl(url);
      await _player.play();
      _broadcastState();
    } catch (e) {
      print('[NexusAudioHandler] setAudioUrl error: $e');
      rethrow;
    }
  }


  void _broadcastState() {
    final isPlaying = _player.playing;
    final processingState = _player.processingState;

    playbackState.add(playbackState.value.copyWith(
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[processingState]!,
      playing: isPlaying,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      androidCompactActionIndices: const [0, 1, 2],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
    ));
  }

  @override
  Future<void> play() async {
    await _player.play();
    _broadcastState();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcastState();
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
    } else {
      _currentIndex = 0; // Listenin başına dön
    }
    if (onSkipNext != null) {
      onSkipNext?.call();
    } else {
      final s = currentSong;
      if (s != null) mediaItem.add(_mediaItemFor(s));
      _broadcastState();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _queue.length - 1;
    }
    if (onSkipPrevious != null) {
      onSkipPrevious?.call();
    } else {
      final s = currentSong;
      if (s != null) mediaItem.add(_mediaItemFor(s));
      _broadcastState();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _broadcastState();
    await super.stop();
  }

  // Callback'ler - UI'dan dinlenebilir
  void Function()? onSkipNext;
  void Function()? onSkipPrevious;

  void dispose() {
    _player.dispose();
  }
}
