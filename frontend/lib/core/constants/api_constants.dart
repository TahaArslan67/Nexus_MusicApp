/// API endpoint constants — dinamik base URL desteği
///
/// flutter_dotenv ile .env'den API_BASE_URL okur.
/// .env yoksa, platforma göre otomatik varsayılan seçer:
///   - Android Emulator -> 10.0.2.2:8000
///   - iOS Simulator    -> localhost:8000
///   - Gerçek cihaz     -> .env'deki API_BASE_URL
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConstants {
  // ── Dinamik Base URL ───────────────────────────────────────────────
  // _baseUrl, AppEnvironment tarafından initialize edilir.
  // Varsayılan: platform otomatik algılama
  static String _baseUrl = _defaultBaseUrl();

  static String get baseUrl => _baseUrl;

  /// .env'den yükleme yapıldıktan sonra bu metot çağrılır.
  static void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Platform bazlı varsayılan base URL
  static String _defaultBaseUrl() {
    if (kIsWeb) {
      // Web: aynı sunucuya servis ediliyorsa relative path
      return 'http://localhost:8000';
    }

    try {
      if (Platform.isAndroid) {
        // Android Emulator: 10.0.2.2 host makineye tunnel
        return 'http://10.0.2.2:8000';
      } else if (Platform.isIOS) {
        // iOS Simulator: localhost direkt çalışır
        return 'http://localhost:8000';
      }
    } catch (_) {
      // Platform desteklenmiyorsa (web dışı) fallback
    }

    return 'http://localhost:8000';
  }

  // ── Endpoint'ler ───────────────────────────────────────────────────
  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String profile = '/auth/me';
  static const String quota = '/auth/quota';

  // Music
  static const String songInfo = '/music/info';        // + /{youtube_id}
  static const String stream = '/music/stream';         // + /{youtube_id}
  static const String download = '/music/download';     // + /{youtube_id}
  static const String library = '/music/library';
  static const String cacheStats = '/music/cache/stats';

  // Search
  static const String search = '/search';
  static const String suggestions = '/search/suggestions';

  // Monitoring
  static const String monitoringStats = '/monitoring/stats';
  static const String monitoringDashboard = '/monitoring/dashboard';
}