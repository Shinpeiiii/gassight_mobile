import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AppLockService {
  static final _storage = const FlutterSecureStorage();
  static const _pinKey = "app_pin";

  static Future<bool> hasPin() async {
    return await _storage.read(key: _pinKey) != null;
  }

  static Future<void> savePin(String pin) async {
    await _storage.write(key: _pinKey, value: pin);
  }

  static Future<bool> verifyPin(String pin) async {
    final saved = await _storage.read(key: _pinKey);
    return saved == pin;
  }

  static Future<bool> biometricAvailable() async {
    final localAuth = LocalAuthentication();
    return await localAuth.canCheckBiometrics;
  }

  static Future<bool> biometricAuthenticate() async {
    final localAuth = LocalAuthentication();
    return await localAuth.authenticate(
      localizedReason: "Authenticate to unlock the app",
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
      ),
    );
  }
}
