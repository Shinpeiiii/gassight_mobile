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
      print("🔐 Attempting login for: $username");
      
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

      print("📡 Login Response Status: ${response.statusCode}");
      print("📡 Login Response Body: ${response.body}");

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
          print("✅ Token saved securely");
        }

        // Store basic user info from login response
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);
        
        // Store user profile data if provided in login response
        if (data["user"] != null) {
          final userData = data["user"];
          await prefs.setString(_fullNameKey, userData["full_name"] ?? userData["fullName"] ?? "");
          await prefs.setString(_emailKey, userData["email"] ?? "");
          await prefs.setString(_phoneKey, userData["phone"] ?? userData["contact"] ?? "");
          await prefs.setString(_provinceKey, userData["province"] ?? "");
          await prefs.setString(_municipalityKey, userData["municipality"] ?? "");
          await prefs.setString(_barangayKey, userData["barangay"] ?? "");
          print("✅ User profile saved from login response");
        }

        // Fetch and store full profile from API
        await _fetchAndStoreProfile();

        return {"ok": true};
      }

      return {"ok": false, "error": data["error"] ?? "Login failed."};
    } catch (e) {
      print("❌ Login error: $e");
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
      if (token == null) {
        print("⚠️ No token available for profile fetch");
        return;
      }

      print("🔄 Fetching profile from API...");

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "User-Agent": "GASsight-Mobile/1.0",
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 10));

      print("📡 Profile API Status: ${response.statusCode}");
      print("📡 Profile API Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        // Save all profile fields
        await prefs.setString(_usernameKey, data["username"]?.toString() ?? "");
        await prefs.setString(_fullNameKey, data["full_name"]?.toString() ?? data["fullName"]?.toString() ?? "");
        await prefs.setString(_emailKey, data["email"]?.toString() ?? "");
        await prefs.setString(_phoneKey, data["phone"]?.toString() ?? data["contact"]?.toString() ?? "");
        await prefs.setString(_provinceKey, data["province"]?.toString() ?? "");
        await prefs.setString(_municipalityKey, data["municipality"]?.toString() ?? "");
        await prefs.setString(_barangayKey, data["barangay"]?.toString() ?? "");
        
        print("✅ Profile saved to local storage");
        print("   - Username: ${data["username"]}");
        print("   - Full Name: ${data["full_name"] ?? data["fullName"]}");
        print("   - Email: ${data["email"]}");
        print("   - Province: ${data["province"]}");
      } else {
        print("⚠️ Failed to fetch profile: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error fetching profile: $e");
    }
  }

  /// ==================================================
  /// GET VALID TOKEN
  /// ==================================================
  static Future<String?> getValidAccessToken() async {
    final token = await _getTokenSecurely();
    
    if (token == null) {
      print("⚠️ No token found");
      return null;
    }

    // Check if token is expired
    if (_isTokenExpired(token)) {
      print("⚠️ Token expired");
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
      print("❌ Error checking token expiration: $e");
      return true; // If we can't parse, assume expired
    }
  }

  /// ==================================================
  /// LOGOUT
  /// ==================================================
  static Future<void> logout() async {
    print("🚪 Logging out...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _deleteTokenSecurely();
    print("✅ Logout complete");
  }

  /// ==================================================
  /// GET LOCAL PROFILE
  /// ==================================================
  static Future<Map<String, String?>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profile = {
      "username": prefs.getString(_usernameKey),
      "full_name": prefs.getString(_fullNameKey),
      "email": prefs.getString(_emailKey),
      "phone": prefs.getString(_phoneKey),
      "province": prefs.getString(_provinceKey),
      "municipality": prefs.getString(_municipalityKey),
      "barangay": prefs.getString(_barangayKey),
    };
    
    print("📋 Retrieved local profile: $profile");
    return profile;
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
      print("❌ Error refreshing profile: $e");
      return false;
    }
  }
}