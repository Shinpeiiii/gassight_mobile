import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = "https://gassight.onrender.com";

  // secure storage (not const)
  static final _secureStorage = FlutterSecureStorage();

  // keys
  static const _tokenKey = "jwt_token";
  static const _usernameKey = "username";
  static const _fullNameKey = "full_name";
  static const _emailKey = "email";
  static const _phoneKey = "phone";
  static const _provinceKey = "province";
  static const _municipalityKey = "municipality";
  static const _barangayKey = "barangay";
  static const _isAdminKey = "is_admin";

  /// Validate password strength
  static String? validatePasswordStrength(String password) {
    if (password.length < 8) return "Password must be at least 8 characters";
    if (!password.contains(RegExp(r'[A-Z]'))) return "Password must contain an uppercase letter";
    if (!password.contains(RegExp(r'[a-z]'))) return "Password must contain a lowercase letter";
    if (!password.contains(RegExp(r'[0-9]'))) return "Password must contain a number";
    return null;
  }

  /// Sanitizes input by removing potentially dangerous characters
  static String sanitizeInput(String? input) {
    if (input == null || input.isEmpty) return "";
    // Note: using normal string with escaped quotes to avoid raw-string pitfalls
    return input.replaceAll(RegExp("[<>\"'&;]"), "").trim();
  }

  /// Save token to secure storage + shared prefs (backup)
  static Future<void> _saveToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      print("✅ Token saved");
    } catch (e) {
      print("❌ Error saving token: $e");
    }
  }

  /// Private: read token from secure storage, fallback to prefs and sync back
  static Future<String?> _getToken() async {
    try {
      String? token = await _secureStorage.read(key: _tokenKey);
      if (token == null) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString(_tokenKey);
        if (token != null) {
          // sync back
          await _secureStorage.write(key: _tokenKey, value: token);
        }
      }
      return token;
    } catch (e) {
      print("⚠️ Secure storage read error: $e");
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
  }

  /// Public getter used by other modules
  static Future<String?> getToken() => _getToken();

  /// Delete token from both storages
  static Future<void> _deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      print("🗑 Token removed");
    } catch (e) {
      print("❌ Error deleting token: $e");
    }
  }

  /// Login: posts to /login, saves token and basic info, fetches profile
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/login"),
            headers: {
              "Content-Type": "application/json",
              "User-Agent": "GASsight-Mobile/1.0",
            },
            body: jsonEncode({
              "username": sanitizeInput(username),
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && (data["success"] == true || data["token"] != null)) {
        final token = data["token"]?.toString();
        if (token != null && token.isNotEmpty) {
          await _saveToken(token);
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);

        // fetch profile to populate local cache (best-effort)
        await _fetchAndStoreProfile();

        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Login failed"};
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// Signup
  static Future<Map<String, dynamic>> signup(
    String username,
    String password,
    String fullName,
    String email,
    String phone,
    String province,
    String municipality,
    String barangay,
  ) async {
    final passErr = validatePasswordStrength(password);
    if (passErr != null) return {"ok": false, "error": passErr};

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/signup"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "username": sanitizeInput(username),
              "password": password,
              "fullName": sanitizeInput(fullName),
              "email": sanitizeInput(email),
              "contact": sanitizeInput(phone),
              "province": sanitizeInput(province),
              "municipality": sanitizeInput(municipality),
              "barangay": sanitizeInput(barangay),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) return {"ok": true};

      return {"ok": false, "error": data["error"] ?? "Signup failed"};
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// Fetch profile from API and store to SharedPreferences
  static Future<bool> _fetchAndStoreProfile() async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) return false;

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_usernameKey, data["username"]?.toString() ?? "");
        await prefs.setString(_fullNameKey,
            data["full_name"]?.toString() ?? data["fullName"]?.toString() ?? data["name"]?.toString() ?? "");
        await prefs.setString(_emailKey, data["email"]?.toString() ?? "");
        await prefs.setString(_phoneKey, data["phone"]?.toString() ?? data["contact"]?.toString() ?? "");
        await prefs.setString(_provinceKey, data["province"]?.toString() ?? "");
        await prefs.setString(_municipalityKey, data["municipality"]?.toString() ?? "");
        await prefs.setString(_barangayKey, data["barangay"]?.toString() ?? "");

        return true;
      }

      return false;
    } catch (e) {
      print("❌ Profile fetch error: $e");
      return false;
    }
  }

  /// Logout: clear prefs and token
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _deleteToken();
      print("✅ Logged out");
    } catch (e) {
      print("❌ Logout error: $e");
    }
  }

  /// Get local cached profile
  static Future<Map<String, String?>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "username": prefs.getString(_usernameKey),
      "full_name": prefs.getString(_fullNameKey),
      "email": prefs.getString(_emailKey),
      "phone": prefs.getString(_phoneKey),
      "province": prefs.getString(_provinceKey),
      "municipality": prefs.getString(_municipalityKey),
      "barangay": prefs.getString(_barangayKey),
    };
  }

  static Future<bool> isLoggedIn() async {
    final token = await _getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<bool> refreshProfile() async {
    return await _fetchAndStoreProfile();
  }
}
