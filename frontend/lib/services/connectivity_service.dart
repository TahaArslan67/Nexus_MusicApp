import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

/// İnternet bağlantı durumunu izler
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionStatusController.stream;
  bool _isConnected = true;
  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);

    _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  void _updateStatus(List<ConnectivityResult> results) {
    _isConnected = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    _connectionStatusController.add(_isConnected);
  }

  /// Bağlantı yoksa exception fırlat
  void ensureConnected() {
    if (!_isConnected) {
      throw NoInternetException('İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin.');
    }
  }

  void dispose() {
    _connectionStatusController.close();
  }
}

class NoInternetException implements Exception {
  final String message;
  NoInternetException(this.message);

  @override
  String toString() => message;
}