import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

/// Yerel giriş ekranı — backend yok, sadece username
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingUser();
  }

  void _checkExistingUser() {
    // LocalDbService'den kayıtlı kullanıcıyı kontrol et
    // İlk kullanımda isim girişi ister
    // Sonraki kullanımlarda doğrudan ana sayfaya gider
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // SharedPrefs'ten kontrol
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('username');
      if (name != null && name.isNotEmpty && mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', _nameCtrl.text.trim());
      await prefs.setBool('onboarded', true);
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusTheme.surfaceDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                Icon(Icons.music_note, size: 80, color: NexusTheme.primaryGreen),
                const SizedBox(height: 16),
                Text(
                  'Nexus',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: NexusTheme.primaryGreen,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kütüphanenizi oluşturun',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: NexusTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),

                // Kullanıcı adı
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Kullanıcı Adınız',
                    hintText: 'ör: Ahmet',
                    prefixIcon: const Icon(Icons.person),
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
                    labelStyle: const TextStyle(color: NexusTheme.textSecondary),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 2) {
                      return 'En az 2 karakter girin';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),

                // Başla butonu
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexusTheme.primaryGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Başla',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
