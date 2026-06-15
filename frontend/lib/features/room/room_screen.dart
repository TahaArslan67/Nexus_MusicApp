import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';
import '../../services/room_service.dart';
import '../player/player_screen.dart';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _codeController = TextEditingController();
  late final RoomService _roomService;
  bool _loading = false;
  String? _error;
  late final VoidCallback _roomListener;

  @override
  void initState() {
    super.initState();
    // Her zaman global roomService'i kullan; yoksa yeni oluştur ve global'e set et
    if (roomService != null) {
      _roomService = roomService!;
    } else {
      _roomService = RoomService();
      roomService = _roomService;
    }
    _roomListener = () {
      if (mounted) setState(() {});
    };
    _roomService.addListener(_roomListener);
  }

  @override
  void dispose() {
    _roomService.removeListener(_roomListener);
    _codeController.dispose();
    // NOT: _roomService.dispose() çağrılmıyor çünkü global roomService
    // PlayerScreen ve diğer yerlerde kullanılmaya devam ediyor
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _roomService.createRoom();
    if (_roomService.connected) {
      roomService = _roomService; // Global servisi set et
      setState(() => _loading = false);
    } else {
      setState(() {
        _error = 'Oda oluşturulamadı';
        _loading = false;
      });
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Kod 6 karakter olmalı');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    await _roomService.joinRoom(code);
    if (_roomService.connected) {
      roomService = _roomService; // Global servisi set et
      setState(() => _loading = false);
    } else {
      setState(() {
        _error = 'Oda bulunamadı';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bağlıysa oda bilgisi göster
    if (_roomService.connected) {
      return _buildRoomConnected();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Ortak Dinleme'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            const Text(
              'Arkadaşlarınla birlikte dinle',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Oda oluştur veya bir odaya katıl',
              style: TextStyle(fontSize: 14, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Create Room Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _createRoom,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add),
                label: const Text('Oda Oluştur'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const Divider(color: Colors.white24),
            const SizedBox(height: 24),

            // Join Room
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'KOD GİR',
                hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
                counterText: '',
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _joinRoom,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.login),
                label: const Text('Odaya Katıl'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoomConnected() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Ortak Dinleme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              _roomService.leaveRoom();
              roomService = null;
              setState(() {});
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              _roomService.isMaster ? 'Oda Oluşturuldu!' : 'Odaya Katıldın!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Kod: ${_roomService.roomCode}',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green, letterSpacing: 4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Katılımcı: ${_roomService.memberCount} kişi',
              style: const TextStyle(fontSize: 14, color: Colors.white54),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.search),
                label: const Text('Şimdi Şarkı Ara'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexusTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
