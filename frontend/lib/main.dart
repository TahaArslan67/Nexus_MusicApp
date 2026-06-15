import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'features/search/search_screen.dart';
import 'features/library/library_screen.dart';
import 'features/player/player_screen.dart';
import 'features/playlist/playlist_screen.dart';
import 'features/room/room_screen.dart';
import 'models/song.dart';
import 'services/local_db_service.dart';
import 'services/connectivity_service.dart';
import 'services/audio_handler.dart';
import 'services/room_service.dart';

/// Global audio handler — tüm uygulama boyunca tek instance
NexusAudioHandler? audioHandler;

/// Global room service — ortak dinleme için
RoomService? roomService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Yerel veritabanını başlat (favoriler/indirilenler için kritik)
  try {
    await LocalDbService.initialize();
  } catch (e) {
    debugPrint('[Nexus] LocalDb init error: $e');
  }
  ConnectivityService().initialize();


  // Audio session konfigürasyonu (arka plan çalma için gerekli)
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('[Nexus] AudioSession init error: $e');
  }

  // Audio servisini başlat (bildirim çubuğu + arka plan çalma)
  try {
    audioHandler = await AudioService.init(
      builder: () => NexusAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nexus.music.channel',
        androidNotificationChannelName: 'Nexus Music',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF1DB954),
      ),
    );
  } catch (e) {
    debugPrint('[Nexus] AudioService init error: $e');
  }

  runApp(const NexusApp());
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexus',
      debugShowCheckedModeBanner: false,
      theme: NexusTheme.darkTheme,
      initialRoute: '/home',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/home':
            return MaterialPageRoute(builder: (_) => const HomeScreen());
          case '/player':
            final args = settings.arguments as Map<String, dynamic>;
            return MaterialPageRoute(
              builder: (_) => PlayerScreen(
                songs: List<Song>.from(args['songs']),
                initialIndex: args['index'] as int,
              ),
            );
          case '/playlist':
            return MaterialPageRoute(builder: (_) => const PlaylistScreen());
          default:
            return MaterialPageRoute(builder: (_) => const HomeScreen());
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Library ekranını dışarıdan yenileyebilmek için key
  final GlobalKey<LibraryScreenState> _libraryKey = GlobalKey<LibraryScreenState>();

  void switchToSearch() {
    setState(() => _currentIndex = 1);
  }

  void _onTabChanged(int i) {
    setState(() => _currentIndex = i);
    // Favoriler sekmesine dönünce listeyi yenile (IndexedStack canlı tuttuğu için gerekli)
    if (i == 0) {
      _libraryKey.currentState?.reload();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusTheme.surfaceDark,
      appBar: AppBar(
        backgroundColor: NexusTheme.surfaceDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(Icons.music_note, color: NexusTheme.primaryGreen, size: 28),
            SizedBox(width: 8),
            Text('Nexus', style: TextStyle(color: NexusTheme.primaryGreen, fontWeight: FontWeight.bold, fontSize: 22)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () => _showSettingsDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RoomScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          LibraryScreen(key: _libraryKey, onSwitchToSearch: switchToSearch),
          const SearchScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabChanged,

        backgroundColor: NexusTheme.surfaceElevated,
        selectedItemColor: NexusTheme.primaryGreen,
        unselectedItemColor: NexusTheme.textTertiary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favoriler'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Ara'),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(
      text: prefs.getString('backend_url') ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexusTheme.surfaceElevated,
        title: const Text('Backend URL', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kendi backend\'inizin adresini girin.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.5:8000',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                controller.text = 'https://nexus-music-api-c1fj.onrender.com';
              },
              child: const Text('Render (Cloud)', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) {
                await prefs.remove('backend_url');
              } else {
                await prefs.setString('backend_url', url);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
