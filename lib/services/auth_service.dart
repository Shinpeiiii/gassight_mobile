import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
          "password": password,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("Connection timeout");
        },
      );

      print("🔐 Login Response Status: ${response.statusCode}");
      print("🔐 Login Response Body: ${response.body}");

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

      if (response.statusCode == 200 && data["success"] == true) {
        final prefs = await SharedPreferences.getInstance();

        // Store JWT token securely
        final token = data["token"];
        if (token != null) {
          await _saveTokenSecurely(token);
          print("✅ Token saved securely");
        }

        // Store basic user info
        await prefs.setString(_usernameKey, username);
        await prefs.setBool(_isAdminKey, data["is_admin"] ?? false);

        // Try to fetch full profile from server
        print("📡 Attempting to fetch full profile...");
        final profileFetched = await _fetchAndStoreProfile();
        
        if (!profileFetched) {
          print("⚠️ Could not fetch profile from server, storing login data");
          // Store whatever data we got from login response
          if (data["user"] != null) {
            final user = data["user"];
            await prefs.setString(_fullNameKey, user["full_name"] ?? user["fullName"] ?? "");
            await prefs.setString(_emailKey, user["email"] ?? "");
            await prefs.setString(_phoneKey, user["phone"] ?? user["contact"] ?? "");
            await prefs.setString(_provinceKey, user["province"] ?? "");
            await prefs.setString(_municipalityKey, user["municipality"] ?? "");
            await prefs.setString(_barangayKey, user["barangay"] ?? "");
          }
        }

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

      print("📝 Signup Response Status: ${response.statusCode}");
      print("📝 Signup Response Body: ${response.body}");

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {"ok": true};
      }

      return {
        "ok": false,
        "error": data["error"] ?? "Signup failed. Code ${response.statusCode}"
      };
    } catch (e) {
      print("❌ Signup error: $e");
      return {"ok": false, "error": "Network error: $e"};
    }
  }

  /// ==================================================
  /// FETCH PROFILE FROM SERVER
  /// ==================================================
  static Future<bool> _fetchAndStoreProfile() async {
    try {
      final token = await _getTokenSecurely();
      if (token == null) {
        print("⚠️ No token available for profile fetch");
        return false;
      }

      print("🔍 Fetching profile with token...");

      final response = await http.get(
        Uri.parse("$baseUrl/api/profile"),
        headers: {
          "Authorization": "Bearer $token",
          "User-Agent": "GASsight-Mobile/1.0",
          "Content-Type": "application/json",
        },
      ).timeout(const Duration(seconds: 10));

      print("📡 Profile Response Status: ${response.statusCode}");
      print("📡 Profile Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        // Handle multiple possible response formats
        final username = data["username"]?.toString() ?? 
                        data["user"]?["username"]?.toString() ?? "";
        
        final fullName = data["full_name"]?.toString() ?? 
                        data["fullName"]?.toString() ?? 
                        data["user"]?["full_name"]?.toString() ?? 
                        data["user"]?["fullName"]?.toString() ?? "";
        
        final email = data["email"]?.toString() ?? 
                     data["user"]?["email"]?.toString() ?? "";
        
        final phone = data["phone"]?.toString() ?? 
                     data["contact"]?.toString() ?? 
                     data["user"]?["phone"]?.toString() ?? 
                     data["user"]?["contact"]?.toString() ?? "";
        
        final province = data["province"]?.toString() ?? 
                        data["user"]?["province"]?.toString() ?? "";
        
        final municipality = data["municipality"]?.toString() ?? 
                            data["user"]?["municipality"]?.toString() ?? "";
        
        final barangay = data["barangay"]?.toString() ?? 
                        data["user"]?["barangay"]?.toString() ?? "";

        // Save all profile data
        if (username.isNotEmpty) await prefs.setString(_usernameKey, username);
        if (fullName.isNotEmpty) await prefs.setString(_fullNameKey, fullName);
        if (email.isNotEmpty) await prefs.setString(_emailKey, email);
        if (phone.isNotEmpty) await prefs.setString(_phoneKey, phone);
        if (province.isNotEmpty) await prefs.setString(_provinceKey, province);
        if (municipality.isNotEmpty) await prefs.setString(_municipalityKey, municipality);
        if (barangay.isNotEmpty) await prefs.setString(_barangayKey, barangay);

        print("✅ Profile data stored successfully");
        print("   Username: $username");
        print("   Full Name: $fullName");
        print("   Email: $email");
        print("   Phone: $phone");
        print("   Province: $province");
        print("   Municipality: $municipality");
        print("   Barangay: $barangay");

        return true;
      } else {
        print("⚠️ Profile fetch failed with status: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("❌ Error fetching profile: $e");
      return false;
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
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final resp = utf8.decode(base64Url.decode(normalized));
      final payloadMap = json.decode(resp);

      if (payloadMap['exp'] != null) {
        final exp = payloadMap['exp'] as int;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        return now >= exp;
      }

      return false;
    } catch (e) {
      print("❌ Error checking token expiration: $e");
      return true;
    }
  }

  /// ==================================================
  /// LOGOUT
  /// ==================================================
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _deleteTokenSecurely();
    print("✅ Logged out successfully");
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

    print("📋 Retrieved local profile:");
    print("   Username: ${profile['username']}");
    print("   Full Name: ${profile['full_name']}");
    print("   Email: ${profile['email']}");
    print("   Phone: ${profile['phone']}");
    print("   Province: ${profile['province']}");
    print("   Municipality: ${profile['municipality']}");
    print("   Barangay: ${profile['barangay']}");

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
    print("🔄 Refreshing profile...");
    return await _fetchAndStoreProfile();
  }
}