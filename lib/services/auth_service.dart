import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = "https://gassight.onrender.com";

  // Secure storage
  static const _secureStorage = FlutterSecureStorage();

  // Storage keys
  static const _tokenKey = "jwt_token";
  static const _usernameKey = "username";
  static const _fullNameKey = "full_name";
  static const _emailKey = "email";
  static const _phoneKey = "phone";
  static const _provinceKey = "province";
  static const _municipalityKey = "municipality";
  static const _barangayKey = "barangay";
  static const _isAdminKey = "is_admin";

  /// ==================================================
  /// PASSWORD VALIDATION
  /// ==================================================
  static String? validatePasswordStrength(String password) {
    if (password.length < 8) return "Password must be at least 8 characters";
    if (!password.contains(RegExp(r'[A-Z]'))) return "Password must contain at least one uppercase letter";
    if (!password.contains(RegExp(r'[a-z]'))) return "Password must contain at least one lowercase letter";
    if (!password.contains(RegExp(r'[0-9]'))) return "Password must contain at least one number";
    return null;
  }

  /// ==================================================
  /// INPUT SANITIZATION
  /// ==================================================
  static String sanitizeInput(String? input) {
    if (input == null || input.isEmpty) return '';

    return input
        .replaceAll(RegExp(r'[<>\"\'&;]'), '')
        .trim();
  }

  /// ==================================================
  /// TOKEN SAVE
  /// ==================================================
  static Future<void> _saveToken(String token) async {
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);

      print("✅ Token saved to both secure storage + SharedPreferences");
    } catch (e) {
      print("❌ Error saving token: $e");
    }
  }

  /// ==================================================
  /// GET TOKEN (ALWAYS RELIABLE)
  /// ==================================================
  static Future<String?> _getToken() async {
    try {
      // Step 1: Check secure storage
      String? token = await _secureStorage.read(key: _tokenKey);

      // Step 2: If missing, check shared prefs
      if (token == null) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString(_tokenKey);

        // Sync back to secure storage
        if (token != null) {
          await _secureStorage.write(key: _tokenKey, value: token);
        }
      }

      return token;
    } catch (e) {
      print("⚠️ Secure read error: $e");

      // Fallback
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
  }

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

  /// ==================================================
  /// LOGIN
  /// ==================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print("\n========== LOGIN ATTEMPT ==========");
      print("User: $username");

      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "GASsight-Mobile/1.0",
        },
        body: jsonEncode({
          "username": sanitizeInput(username),
          "password": password,
        }),
      ).timeout(const Duration(seconds: 15));

      print("📡 Login Status: ${response.statusCode}");
      print("📡 Body: ${response.body}");

      if (!response.headers["content-type"]!.contains("application/json")) {
        return {"ok": false, "error": "Invalid server response"};
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["success"] == true) {
        final token = data["token"];
        final prefs = await SharedPreferences.getInstance();

        // Save token
        if (token != null && token.isNotEmpty) {
          print("🔑 Token received: ${token.substring(0, 25)}...");
          await _saveToken(token);
        } else {
          print("⚠️ Login success but token missing!");
        }

        // Save basic info
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);

        // Immediately fetch profile
        await _fetchAndStoreProfile();

        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Login failed"};
    } catch (e) {
      print("❌ Login error: $e");
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// SIGNUP
  /// ==================================================
  static Future<Map<String, dynamic>> signup(
      String username,
      String password,
      String fullName,
      String email,
      String phone,
      String province,
      String municipality,
      String barangay) async {

    final err = validatePasswordStrength(password);
    if (err != null) return {"ok": false, "error": err};

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup"),
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "GASsight-Mobile/1.0",
        },
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
      ).timeout(const Duration(seconds: 15));

      final data =
          response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Signup failed"};
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// FETCH PROFILE (API)
  /// ==================================================
  static Future<bool> _fetchAndStoreProfile() async {
    try {
      final token = await _getToken();

      if (token == null) {
        print("⚠️ Cannot fetch profile → no token");
        return false;
      }

      print("🔍 Fetching profile...");

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 15));

      print("📡 Status: ${response.statusCode}");
      print("📡 Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_usernameKey, data["username"] ?? "");
        await prefs.setString(_fullNameKey,
            data["full_name"] ?? data["fullName"] ?? "");
        await prefs.setString(_emailKey, data["email"] ?? "");
        await prefs.setString(_phoneKey,
            data["phone"] ?? data["contact"] ?? "");
        await prefs.setString(_provinceKey, data["province"] ?? "");
        await prefs.setString(_municipalityKey, data["municipality"] ?? "");
        await prefs.setString(_barangayKey, data["barangay"] ?? "");

        print("✅ Profile stored locally");

        return true;
      }

      print("⚠️ Profile error: ${response.statusCode}");
      return false;
    } catch (e) {
      print("❌ Profile fetch error: $e");
      return false;
    }
  }

  /// ==================================================
  /// GET VALID TOKEN
  /// ==================================================
  static Future<String?> getValidAccessToken() async {
    final token = await _getToken();

    if (token == null || token.isEmpty) {
      print("⚠️ No token available");
      return null;
    }

    print("🔑 Token ready: ${token.substring(0, 25)}...");
    return token;
  }

  /// ==================================================
  /// LOGOUT
  /// ==================================================
  static Future<void> logout() async {
    print("🚪 Logging out...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _deleteToken();
  }

  /// ==================================================
  /// LOCAL PROFILE
  /// ==================================================
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

  /// ==================================================
  /// CHECK LOGIN STATUS
  /// ==================================================
  static Future<bool> isLoggedIn() async {
    final token = await _getToken();
    return token != null && token.isNotEmpty;
  }

  /// ==================================================
  /// REFRESH PROFILE
  /// ==================================================
  static Future<bool> refreshProfile() async {
    return await _fetchAndStoreProfile();
  }
}
