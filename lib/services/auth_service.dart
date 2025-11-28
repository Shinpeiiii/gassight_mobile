import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = "https://gassight.onrender.com";

  // Secure storage for sensitive data
  static const _secureStorage = FlutterSecureStorage();

  // Storage keys
  static const _tokenKey = "jwt_token";
  static const _refreshTokenKey = "refresh_token";
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
    if (password.length < 8) {
      return "Password must be at least 8 characters";
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return "Password must contain at least one uppercase letter";
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return "Password must contain at least one lowercase letter";
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return "Password must contain at least one number";
    }
    return null; // Password is strong
  }

  /// ==================================================
  /// INPUT SANITIZATION
  /// ==================================================
  static String sanitizeInput(String? input) {
    if (input == null || input.isEmpty) return '';
    
    // Remove potential XSS attempts
    String sanitized = input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('&', '')
        .replaceAll(';', '');
    
    return sanitized.trim();
  }

  /// ==================================================
  /// SECURE TOKEN STORAGE
  /// ==================================================
  static Future<void> _saveTokenSecurely(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<String?> _getTokenSecurely() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  static Future<void> _deleteTokenSecurely() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  /// ==================================================
  /// LOGIN WITH JWT
  /// ==================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "GASsight-Mobile/1.0",
        },
        body: jsonEncode({
          "username": sanitizeInput(username),
          "password": password, // Don't sanitize password
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("Connection timeout");
        },
      );

      // Validate JSON response
      if (response.headers["content-type"]?.contains("application/json") != true) {
        return {
          "ok": false,
          "error": "Invalid server response. Code ${response.statusCode}"
        };
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        return {"ok": false, "error": "Invalid JSON response from server."};
      }

      // Success
      if (response.statusCode == 200 && data["success"] == true) {
        final prefs = await SharedPreferences.getInstance();

        // Store JWT token securely
        final token = data["token"];
        if (token != null) {
          await _saveTokenSecurely(token);
        }

        // Store user info
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);

        // Fetch and store full profile
        await _fetchAndStoreProfile();

        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Login failed."};
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// SIGNUP WITH VALIDATION
  /// ==================================================
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
    // Validate password strength
    final passwordError = validatePasswordStrength(password);
    if (passwordError != null) {
      return {"ok": false, "error": passwordError};
    }

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
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("Connection timeout");
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        return {"ok": true};
      }

      return {
        "ok": false,
        "error": data["error"] ?? "Signup failed. Code ${response.statusCode}"
      };
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// FETCH PROFILE FROM SERVER
  /// ==================================================
  static Future<void> _fetchAndStoreProfile() async {
    try {
      final token = await _getTokenSecurely();
      if (token == null) return;

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "User-Agent": "GASsight-Mobile/1.0",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_fullNameKey, data["full_name"] ?? "");
        await prefs.setString(_emailKey, data["email"] ?? "");
        await prefs.setString(_phoneKey, data["phone"] ?? "");
        await prefs.setString(_provinceKey, data["province"] ?? "");
        await prefs.setString(_municipalityKey, data["municipality"] ?? "");
        await prefs.setString(_barangayKey, data["barangay"] ?? "");
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  /// ==================================================
  /// GET VALID TOKEN
  /// ==================================================
  static Future<String?> getValidAccessToken() async {
    final token = await _getTokenSecurely();
    
    if (token == null) return null;

    // Check if token is expired
    if (_isTokenExpired(token)) {
      await _deleteTokenSecurely();
      return null;
    }

    return token;
  }

  /// ==================================================
  /// CHECK IF TOKEN IS EXPIRED
  /// ==================================================
  static bool _isTokenExpired(String token) {
    try {
      // JWT format: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) return true;

      // Decode payload
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final resp = utf8.decode(base64Url.decode(normalized));
      final payloadMap = json.decode(resp);

      // Check expiration
      if (payloadMap['exp'] != null) {
        final exp = payloadMap['exp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return now >= exp;
      }

      return false;
    } catch (e) {
      return true; // If we can't parse, assume expired
    }
  }

  /// ==================================================
  /// LOGOUT
  /// ==================================================
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _deleteTokenSecurely();
  }

  /// ==================================================
  /// GET LOCAL PROFILE
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
  /// CHECK IF LOGGED IN
  /// ==================================================
  static Future<bool> isLoggedIn() async {
    final token = await getValidAccessToken();
    return token != null;
  }

  /// ==================================================
  /// MAKE AUTHENTICATED REQUEST
  /// ==================================================
  static Future<http.Response> authenticatedRequest(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    final token = await getValidAccessToken();
    
    if (token == null) {
      throw Exception("Not authenticated");
    }

    final requestHeaders = {
      "Authorization": "Bearer $token",
      "Content-Type": "application/json",
      "User-Agent": "GASsight-Mobile/1.0",
      ...?headers,
    };

    final uri = Uri.parse("$baseUrl$endpoint");

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: requestHeaders);
      case 'POST':
        return await http.post(uri, headers: requestHeaders, body: body);
      case 'PUT':
        return await http.put(uri, headers: requestHeaders, body: body);
      case 'DELETE':
        return await http.delete(uri, headers: requestHeaders);
      default:
        throw Exception("Unsupported HTTP method");
    }
  }

  /// ==================================================
  /// REFRESH USER PROFILE
  /// ==================================================
  static Future<bool> refreshProfile() async {
    try {
      await _fetchAndStoreProfile();
      return true;
    } catch (e) {
      return false;
    }
  }
}