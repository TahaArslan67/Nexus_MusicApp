import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/song.dart';

class RoomService extends ChangeNotifier {
  static Future<String> _getBackendBase() async {
    final prefs = await SharedPreferences.getInstance();
    final customUrl = prefs.getString('backend_url');
    if (customUrl != null && customUrl.isNotEmpty) {
      // http:// veya https:// başlar, ws:// / wss:// yap
      return customUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://');
    }
    return kDebugMode
        ? 'ws://192.168.18.106:8000'
        : 'wss://nexus-music-api-c1fj.onrender.com';
  }

  WebSocketChannel? _ws;
  String? _roomCode;
  String? _userId;
  bool _isMaster = false;
  bool _connected = false;
  int _memberCount = 1;
  Song? _syncedSong;
  bool _syncedPlaying = false;
  int _syncedPositionMs = 0;

  // Streams for external listeners (e.g. PlayerScreen)
  final _onPlay = StreamController<int>.broadcast();
  final _onPause = StreamController<int>.broadcast();
  final _onSeek = StreamController<int>.broadcast();
  final _onSongChange = StreamController<Song>.broadcast();
  final _onMemberChange = StreamController<int>.broadcast();

  String? get roomCode => _roomCode;
  bool get isMaster => _isMaster;
  bool get connected => _connected;
  int get memberCount => _memberCount;
  Song? get syncedSong => _syncedSong;
  bool get syncedPlaying => _syncedPlaying;

  Stream<int> get onPlay => _onPlay.stream;
  Stream<int> get onPause => _onPause.stream;
  Stream<int> get onSeek => _onSeek.stream;
  Stream<Song> get onSongChange => _onSongChange.stream;
  Stream<int> get onMemberChange => _onMemberChange.stream;

  void _generateUserId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    _userId = List.generate(8, (_) => chars[Random().nextInt(chars.length)]).join();
  }

  Future<void> createRoom() async {
    _generateUserId();
    final base = await _getBackendBase();
    final wsUrl = '$base/room/ws/ROOM?user_id=$_userId&action=create';
    await _connect(wsUrl);
  }

  Future<void> joinRoom(String code) async {
    _generateUserId();
    final base = await _getBackendBase();
    final wsUrl = '$base/room/ws/${code.toUpperCase()}?user_id=$_userId&action=join';
    await _connect(wsUrl);
  }

  Future<void> _connect(String wsUrl) async {
    try {
      _ws = WebSocketChannel.connect(Uri.parse(wsUrl));
      _connected = true;
      notifyListeners();

      _ws!.stream.listen(
        (message) => _handleMessage(jsonDecode(message)),
        onError: (e) {
          print('[Room] WS error: $e');
          _connected = false;
          notifyListeners();
        },
        onDone: () {
          print('[Room] WS closed');
          _connected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      print('[Room] Connection failed: $e');
      _connected = false;
      notifyListeners();
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'];
    print('[Room] Received: $type');

    switch (type) {
      case 'sync':
        _isMaster = data['is_master'] ?? false;
        _roomCode = data['room_code'] ?? _roomCode;
        _memberCount = data['member_count'] ?? 1;
        _syncedPlaying = data['is_playing'] ?? false;
        _syncedPositionMs = data['current_position_ms'] ?? 0;
        final songData = data['current_song'];
        if (songData != null) {
          _syncedSong = _songFromJson(songData);
        }
        notifyListeners();
        break;

      case 'member_joined':
        _memberCount = data['member_count'] ?? _memberCount + 1;
        _onMemberChange.add(_memberCount);
        notifyListeners();
        break;

      case 'member_left':
        _memberCount = data['member_count'] ?? max(1, _memberCount - 1);
        _onMemberChange.add(_memberCount);
        notifyListeners();
        break;

      case 'play':
        _syncedPositionMs = data['position_ms'] ?? 0;
        _syncedPlaying = true;
        _onPlay.add(_syncedPositionMs);
        notifyListeners();
        break;

      case 'pause':
        _syncedPositionMs = data['position_ms'] ?? 0;
        _syncedPlaying = false;
        _onPause.add(_syncedPositionMs);
        notifyListeners();
        break;

      case 'seek':
        _syncedPositionMs = data['position_ms'] ?? 0;
        _onSeek.add(_syncedPositionMs);
        notifyListeners();
        break;

      case 'song_change':
        final songData = data['song'];
        if (songData != null) {
          _syncedSong = _songFromJson(songData);
          _syncedPositionMs = 0;
          _syncedPlaying = true;
          _onSongChange.add(_syncedSong!);
        }
        notifyListeners();
        break;

      case 'error':
        print('[Room] Server error: ${data['message']}');
        break;
    }
  }

  Song _songFromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? 0,
      youtubeId: json['youtube_id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artist: json['artist'] ?? 'Unknown',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      durationSeconds: json['duration_seconds'] ?? 0,
    );
  }

  Map<String, dynamic> _songToJson(Song song) {
    return {
      'id': song.id,
      'youtube_id': song.youtubeId,
      'title': song.title,
      'artist': song.artist,
      'thumbnail_url': song.thumbnailUrl,
      'duration_seconds': song.durationSeconds,
    };
  }

  // ── Master actions ──────────────────────────────────────────────

  void sendPlay(int positionMs) {
    if (!isMaster) return;
    _send({'type': 'play', 'position_ms': positionMs});
  }

  void sendPause(int positionMs) {
    if (!isMaster) return;
    _send({'type': 'pause', 'position_ms': positionMs});
  }

  void sendSeek(int positionMs) {
    if (!isMaster) return;
    _send({'type': 'seek', 'position_ms': positionMs});
  }

  void sendSongChange(Song song) {
    if (!isMaster) return;
    _send({'type': 'song_change', 'song': _songToJson(song)});
  }

  void _send(Map<String, dynamic> data) {
    if (_ws != null && _connected) {
      _ws!.sink.add(jsonEncode(data));
    }
  }

  void leaveRoom() {
    _ws?.sink.close();
    _ws = null;
    _roomCode = null;
    _connected = false;
    _isMaster = false;
    _memberCount = 1;
    _syncedSong = null;
    notifyListeners();
  }

  @override
  void dispose() {
    leaveRoom();
    _onPlay.close();
    _onPause.close();
    _onSeek.close();
    _onSongChange.close();
    _onMemberChange.close();
    super.dispose();
  }
}
