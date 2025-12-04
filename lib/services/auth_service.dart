import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const String baseUrl = "https://gassight.onrender.com";

  // Use both secure storage and shared preferences for redundancy
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
    return null;
  }

  /// ==================================================
  /// INPUT SANITIZATION
  /// ==================================================
  static String sanitizeInput(String? input) {
    if (input == null || input.isEmpty) return '';
    
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
  /// TOKEN STORAGE (Dual storage for reliability)
  /// ==================================================
  static Future<void> _saveToken(String token) async {
    try {
      // Save to secure storage
      await _secureStorage.write(key: _tokenKey, value: token);
      
      // Also save to shared preferences as backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      
      print("✅ Token saved to both secure storage and SharedPreferences");
    } catch (e) {
      print("❌ Error saving token: $e");
    }
  }

  static Future<String?> _getToken() async {
    try {
      // Try secure storage first
      String? token = await _secureStorage.read(key: _tokenKey);
      
      // If not found, try shared preferences
      if (token == null) {
        final prefs = await SharedPreferences.getInstance();
        token = prefs.getString(_tokenKey);
        
        // If found in prefs, save back to secure storage
        if (token != null) {
          await _secureStorage.write(key: _tokenKey, value: token);
        }
      }
      
      return token;
    } catch (e) {
      print("❌ Error getting token: $e");
      // Fallback to shared preferences
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
  }

  static Future<void> _deleteToken() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (e) {
      print("❌ Error deleting token: $e");
    }
  }

  /// ==================================================
  /// LOGIN WITH JWT
  /// ==================================================
  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print("\n" + "=" * 50);
      print("🔐 LOGIN ATTEMPT");
      print("=" * 50);
      print("Username: $username");
      
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
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception("Connection timeout - server took too long to respond");
        },
      );

      print("📡 Login Response Status: ${response.statusCode}");
      print("📡 Login Response Body: ${response.body}");

      if (response.headers["content-type"]?.contains("application/json") != true) {
        print("❌ Invalid response type");
        return {
          "ok": false,
          "error": "Invalid server response"
        };
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
      } catch (e) {
        print("❌ JSON parse error: $e");
        return {"ok": false, "error": "Invalid server response"};
      }

      if (response.statusCode == 200 && data["success"] == true) {
        final prefs = await SharedPreferences.getInstance();

        // Save token
        final token = data["token"];
        if (token != null && token.isNotEmpty) {
          await _saveToken(token);
          print("✅ Token saved: ${token.substring(0, 20)}...");
        } else {
          print("⚠️ No token in response!");
        }

        // Save username
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);
        
        print("✅ Basic info saved");

        // Try to get profile immediately
        await Future.delayed(const Duration(milliseconds: 500));
        await _fetchAndStoreProfile();

        print("✅ Login successful!");
        print("=" * 50 + "\n");
        
        return {"ok": true};
      }

      print("❌ Login failed: ${data['error']}");
      return {"ok": false, "error": data["error"] ?? "Login failed"};
      
    } catch (e) {
      print("❌ Login exception: $e");
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
    String barangay,
  ) async {
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
      ).timeout(const Duration(seconds: 15));

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        return {"ok": true};
      }

      return {
        "ok": false,
        "error": data["error"] ?? "Signup failed"
      };
    } catch (e) {
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// FETCH AND STORE PROFILE
  /// ==================================================
  static Future<bool> _fetchAndStoreProfile() async {
    try {
      final token = await _getToken();
      if (token == null) {
        print("⚠️ No token for profile fetch");
        return false;
      }

      print("\n🔄 Fetching profile from API...");

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 15));

      print("📡 Profile API Status: ${response.statusCode}");
      print("📡 Profile API Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        // Extract and save all fields with multiple name variations
        final username = data["username"]?.toString() ?? "";
        final fullName = data["full_name"]?.toString() ?? 
                        data["fullName"]?.toString() ?? 
                        data["name"]?.toString() ?? "";
        final email = data["email"]?.toString() ?? "";
        final phone = data["phone"]?.toString() ?? 
                     data["contact"]?.toString() ?? "";
        final province = data["province"]?.toString() ?? "";
        final municipality = data["municipality"]?.toString() ?? "";
        final barangay = data["barangay"]?.toString() ?? "";

        await prefs.setString(_usernameKey, username);
        await prefs.setString(_fullNameKey, fullName);
        await prefs.setString(_emailKey, email);
        await prefs.setString(_phoneKey, phone);
        await prefs.setString(_provinceKey, province);
        await prefs.setString(_municipalityKey, municipality);
        await prefs.setString(_barangayKey, barangay);

        print("✅ Profile saved:");
        print("   - Username: $username");
        print("   - Full Name: $fullName");
        print("   - Email: $email");
        print("   - Phone: $phone");
        print("   - Province: $province");
        print("   - Municipality: $municipality");
        print("   - Barangay: $barangay\n");

        return true;
      } else {
        print("⚠️ Profile API returned: ${response.statusCode}");
        return false;
      }
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
      print("⚠️ No token found in storage");
      return null;
    }

    // Don't check expiration - let the server handle it
    // The server will return 401 if token is expired
    print("✅ Token found: ${token.substring(0, 20)}...");
    return token;
  }

  /// ==================================================
  /// LOGOUT
  /// ==================================================
  static Future<void> logout() async {
    print("\n🚪 Logging out...");
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _deleteToken();
    print("✅ Logout complete\n");
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